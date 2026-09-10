class_name DynamicsSystem
extends RefCounted

## Vie de vestiaire : hiérarchie, affinités, clans, griefs.
##
## Pourquoi ce système existe : dans un jeu de gestion, un effectif n'est pas
## une addition de notes. Cinq joueurs à 150 de CA qui se détestent perdent
## contre cinq joueurs à 135 qui se comprennent. L'esport pousse même le trait,
## parce que les équipes vivent ensemble en gaming house et jouent un jeu où
## tout passe par la voix.
##
## Trois briques :
##   1. INFLUENCE — qui pèse dans le vestiaire (pas forcément le meilleur).
##   2. AFFINITÉS — qui s'entend avec qui, et pourquoi.
##   3. GRIEFS    — ce qu'un joueur reproche à la structure, nommé et donc
##                  adressable par le manager (voir InteractionSystem).
##
## Aucun de ces états n'est aléatoire à l'affichage : ils sont recalculés
## chaque semaine et stockés, pour qu'une conversation puisse s'y appuyer.

# --- Clés de grief ----------------------------------------------------------
const GRIEVANCE_PLAYING_TIME := "playing_time"
const GRIEVANCE_WAGE := "wage"
const GRIEVANCE_AMBITION := "ambition"
const GRIEVANCE_ROLE := "role"
const GRIEVANCE_CONTRACT := "contract"
const GRIEVANCE_TEAMMATE := "teammate"
const GRIEVANCE_OVERWORK := "overwork"

const GRIEVANCE_LABELS := {
	GRIEVANCE_PLAYING_TIME: "Ne joue pas assez",
	GRIEVANCE_WAGE: "Se juge sous-payé",
	GRIEVANCE_AMBITION: "Doute du projet sportif",
	GRIEVANCE_ROLE: "Joue hors de son poste",
	GRIEVANCE_CONTRACT: "Attend une prolongation",
	GRIEVANCE_TEAMMATE: "Conflit avec un coéquipier",
	GRIEVANCE_OVERWORK: "Charge de travail excessive",
}

## Poids de chaque grief sur la satisfaction hebdomadaire.
const GRIEVANCE_WEIGHT := {
	GRIEVANCE_PLAYING_TIME: 2.2,
	GRIEVANCE_WAGE: 1.4,
	GRIEVANCE_AMBITION: 1.6,
	GRIEVANCE_ROLE: 1.1,
	GRIEVANCE_CONTRACT: 0.9,
	GRIEVANCE_TEAMMATE: 1.5,
	GRIEVANCE_OVERWORK: 1.2,
}


static func grievance_label(key: String) -> String:
	return GRIEVANCE_LABELS.get(key, key)


# ============================================================================
# Passe hebdomadaire
# ============================================================================

static func weekly_tick(world: World) -> void:
	for rid in world.rosters:
		var r: Roster = world.rosters[rid]
		var squad := world.players_of(r.id)
		if squad.is_empty():
			continue
		_update_influence(world, r, squad)
		_update_relations(world, r, squad)
		_update_grievances(world, r, squad)


## L'influence n'est pas la CA : un vétéran moyen mais respecté pèse plus
## qu'un prodige de 17 ans arrivé en janvier.
static func _update_influence(world: World, r: Roster, squad: Array) -> void:
	for p_v in squad:
		var p: Player = p_v
		var tenure_days := 0
		if p.contract != null:
			tenure_days = maxi(world.today - p.contract.signed_on_day, 0)
		var tenure := clampf(float(tenure_days) / 730.0, 0.0, 1.0)
		var age_weight := clampf(float(p.age(world.today) - 17) / 8.0, 0.0, 1.0)
		var v := 0.0
		v += float(p.attr(Attributes.LEADERSHIP)) * 2.1
		v += float(p.attr(Attributes.COMMUNICATION)) * 1.1
		v += float(p.current_ability) / 200.0 * 22.0
		v += clampf(float(p.reputation) / 4000.0, 0.0, 1.0) * 14.0
		v += tenure * 16.0
		v += age_weight * 8.0
		if p.is_igl:
			v += 12.0
		if r.starters.has(p.id):
			v += 6.0
		p.influence = clampf(v, 0.0, 100.0)


## Les affinités dérivent lentement vers une valeur cible dictée par la
## compatibilité des personnalités, la concurrence au même poste et les
## résultats communs. Lentement : une amitié ne se décrète pas en une semaine.
static func _update_relations(world: World, r: Roster, squad: Array) -> void:
	if squad.size() < 2:
		return
	var winning := _recent_form(r)
	for i in squad.size():
		var a: Player = squad[i]
		for j in range(i + 1, squad.size()):
			var b: Player = squad[j]
			var target := _relation_target(a, b, winning)
			var cur := float(a.relation_with(b.id))
			# 8 % d'écart comblé par semaine : il faut ~6 mois pour qu'un duo
			# passe d'indifférent à complice.
			var next := cur + (target - cur) * 0.08
			var v := int(round(clampf(next, -100.0, 100.0)))
			a.relations[b.id] = v
			b.relations[a.id] = v


## Valeur d'équilibre d'une relation.
##
## Les coefficients sont volontairement AMPLES : avec des écarts timides, tous
## les duos convergent vers +15 et il ne se forme jamais ni clan ni conflit.
## Un vestiaire doit pouvoir produire les deux. Repères :
##   deux profils collectifs de même nationalité, équipe qui gagne ..... ~+85
##   deux ego au même poste, équipe qui perd ............................ ~-60
static func _relation_target(a: Player, b: Player, winning: float) -> float:
	var t := 8.0 + winning * 30.0
	# Deux gros ego au même poste, c'est la recette du clash.
	var ego := (float(a.attr(Attributes.EGO)) + float(b.attr(Attributes.EGO))) / 2.0
	var team := (float(a.attr(Attributes.TEAMWORK))
		+ float(b.attr(Attributes.TEAMWORK))) / 2.0
	t += (team - 10.0) * 5.5
	t -= (ego - 10.0) * 4.5
	if a.primary_role == b.primary_role:
		t -= 22.0 + (ego - 10.0) * 1.8
	# Même nationalité : la langue commune crée des sous-groupes, pour le
	# meilleur (cohésion) et pour le pire (clans).
	if a.nationality == b.nationality:
		t += 20.0
	elif a.region != b.region:
		t -= 10.0
	# Un professionnel supporte mal un tire-au-flanc.
	var gap := absf(float(a.attr(Attributes.PROFESSIONALISM))
		- float(b.attr(Attributes.PROFESSIONALISM)))
	t -= gap * 2.6
	if a.is_igl or b.is_igl:
		t += 7.0
	return clampf(t, -100.0, 100.0)


## Part de victoires récente du roster, ramenée à -1 .. +1.
static func _recent_form(r: Roster) -> float:
	var w := 0
	var l := 0
	for cid in r.season_record:
		var rec: Dictionary = r.season_record[cid]
		w += int(rec.get("w", 0))
		l += int(rec.get("l", 0))
	if w + l < 3:
		return 0.0
	return clampf((float(w) / float(w + l) - 0.5) * 2.0, -1.0, 1.0)


# ============================================================================
# Griefs
# ============================================================================

static func _update_grievances(world: World, r: Roster, squad: Array) -> void:
	var ranked := squad.duplicate()
	ranked.sort_custom(func(a: Player, b: Player):
		return a.current_ability > b.current_ability)
	var form := _recent_form(r)
	var module := world.module_for(r.game_id)

	for idx in ranked.size():
		var p: Player = ranked[idx]
		_check_playing_time(world, r, p, idx, ranked.size())
		_check_wage(world, p)
		_check_ambition(world, r, p, form)
		_check_role(world, r, p, module)
		_check_contract(world, p)
		_check_teammate(world, p, squad)
		_check_overwork(world, r, p)


static func _check_playing_time(world: World, r: Roster, p: Player, rank: int,
		squad_size: int) -> void:
	# La promesse n'a de sens qu'après un délai d'observation : on ne reproche
	# pas au manager de ne pas avoir aligné un joueur signé il y a huit jours.
	if p.promise_day > 0 and world.today - p.promise_day < 28:
		p.clear_concern(GRIEVANCE_PLAYING_TIME)
		return
	var expected := PlayingTime.expected_share(p.promised_time)
	var actual := _playing_share(world, r, p)
	var deserved := PlayingTime.deserved(rank, squad_size,
		p.attr(Attributes.AMBITION))
	# Un joueur qui mérite mieux que sa promesse la conteste aussi.
	if deserved < p.promised_time - PlayingTime.TOLERANCE:
		expected = maxf(expected, PlayingTime.expected_share(deserved) * 0.8)
	if actual < expected - 0.18:
		p.add_concern(GRIEVANCE_PLAYING_TIME)
	elif actual >= expected - 0.05:
		p.clear_concern(GRIEVANCE_PLAYING_TIME)


## Part de séries disputées cette saison. On se base sur les stats agrégées
## du joueur rapportées au total de l'équipe : c'est la seule mesure qui
## survit aux changements de roster en cours de saison.
static func _playing_share(world: World, r: Roster, p: Player) -> float:
	var team_series := 0
	for cid in r.season_record:
		var rec: Dictionary = r.season_record[cid]
		team_series += int(rec.get("w", 0)) + int(rec.get("l", 0))
	if team_series < 3:
		# Saison à peine entamée : la place dans le cinq fait foi.
		return 1.0 if r.starters.has(p.id) else 0.0
	var played := int(p.season_stats.get("series", 0))
	return clampf(float(played) / float(team_series), 0.0, 1.0)


static func _check_wage(world: World, p: Player) -> void:
	if p.contract == null:
		return
	var fair := PlayerFactory.salary_for_ca(p.current_ability, p.reputation)
	var wanted := int(float(fair) * PlayingTime.wage_expectation(p.promised_time))
	var greed := 0.85 + float(p.attr(Attributes.AMBITION)) / 100.0
	if float(p.contract.salary_yearly) < float(wanted) * greed * 0.78:
		p.add_concern(GRIEVANCE_WAGE)
	elif float(p.contract.salary_yearly) >= float(wanted) * 0.95:
		p.clear_concern(GRIEVANCE_WAGE)


static func _check_ambition(world: World, r: Roster, p: Player,
		form: float) -> void:
	var amb := float(p.attr(Attributes.AMBITION))
	if amb < 12.0:
		p.clear_concern(GRIEVANCE_AMBITION)
		return
	# Plus le joueur est ambitieux, plus le seuil de résultats est haut.
	var threshold := -0.35 + (amb - 12.0) * 0.055
	if form < threshold:
		p.add_concern(GRIEVANCE_AMBITION)
	elif form > threshold + 0.25:
		p.clear_concern(GRIEVANCE_AMBITION)


static func _check_role(world: World, r: Roster, p: Player,
		module: GameModule) -> void:
	if not r.starters.has(p.id):
		p.clear_concern(GRIEVANCE_ROLE)
		return
	if RoleFamiliarity.is_misused(p, module, r.role_of(p)):
		p.add_concern(GRIEVANCE_ROLE)
	else:
		p.clear_concern(GRIEVANCE_ROLE)


static func _check_contract(world: World, p: Player) -> void:
	if p.contract == null:
		p.clear_concern(GRIEVANCE_CONTRACT)
		return
	var left := p.contract.days_remaining(world.today)
	# Un joueur important s'inquiète plus tôt qu'un remplaçant.
	var window := 120 + (200 - p.current_ability) / -4
	if left < window and left > 0:
		p.add_concern(GRIEVANCE_CONTRACT)
	else:
		p.clear_concern(GRIEVANCE_CONTRACT)


static func _check_teammate(world: World, p: Player, squad: Array) -> void:
	for other_v in squad:
		var other: Player = other_v
		if other.id == p.id:
			continue
		if p.relation_with(other.id) <= -55:
			p.add_concern(GRIEVANCE_TEAMMATE)
			return
	p.clear_concern(GRIEVANCE_TEAMMATE)


## Un joueur ne se plaint pas d'un pic de fatigue en pleine phase de matchs :
## c'est le métier. Il se plaint d'une USURE INSTALLÉE — la fatigue passagère
## ne compte que si elle s'ajoute à une charge d'entraînement volontairement
## excessive. Sans cette nuance, tout l'effectif porte le grief en permanence
## et l'écran du vestiaire ne dit plus rien.
static func _check_overwork(world: World, r: Roster, p: Player) -> void:
	var tolerance := float(p.attr(Attributes.PROFESSIONALISM)) * 1.6
	var load := TrainingSystem.plan_load(TrainingSystem.plan_of(r))
	var strain := p.burnout + maxf(p.fatigue - 75.0, 0.0) * 0.5 \
		+ maxf(load - 1.0, 0.0) * 30.0 \
		+ maxf(p.training_intensity - 1.0, 0.0) * 25.0
	if strain > 30.0 + tolerance:
		p.add_concern(GRIEVANCE_OVERWORK)
	elif strain < 22.0 + tolerance:
		p.clear_concern(GRIEVANCE_OVERWORK)


# ============================================================================
# Lecture — utilisée par l'interface et par ProgressionSystem
# ============================================================================

## Pression totale des griefs d'un joueur : sert de dérive de satisfaction.
static func grievance_pressure(p: Player) -> float:
	var total := 0.0
	for c in p.concerns:
		total += float(GRIEVANCE_WEIGHT.get(c, 1.0))
	return total


## Ambiance du vestiaire, 0..100. Combine moral moyen, affinités et griefs
## pondérés par l'influence : un cadre mécontent pèse plus qu'un remplaçant.
static func atmosphere(world: World, r: Roster) -> float:
	var squad := world.players_of(r.id)
	if squad.is_empty():
		return 50.0
	var morale := 0.0
	var weighted_grief := 0.0
	var influence_sum := 0.0
	for p_v in squad:
		var p: Player = p_v
		morale += p.morale
		var w := 0.4 + p.influence / 100.0
		weighted_grief += grievance_pressure(p) * w
		influence_sum += w
	morale /= float(squad.size())
	var relation := average_relation(world, r)
	var grief := weighted_grief / maxf(influence_sum, 1.0)
	return clampf(morale * 0.55 + (relation + 100.0) / 2.0 * 0.45
		- grief * 6.0, 0.0, 100.0)


static func atmosphere_label(v: float) -> String:
	if v >= 78.0:
		return "Excellente"
	if v >= 62.0:
		return "Bonne"
	if v >= 46.0:
		return "Correcte"
	if v >= 30.0:
		return "Tendue"
	return "Explosive"


static func average_relation(world: World, r: Roster) -> float:
	var squad := world.players_of(r.id)
	var total := 0.0
	var n := 0
	for i in squad.size():
		for j in range(i + 1, squad.size()):
			total += float((squad[i] as Player).relation_with((squad[j] as Player).id))
			n += 1
	return total / maxf(float(n), 1.0)


## Hiérarchie du vestiaire, triée par influence décroissante.
## Renvoie [{"player", "influence", "tier"}] avec tier ∈ {cadre, suiveur, ...}.
static func hierarchy(world: World, r: Roster) -> Array:
	var squad := world.players_of(r.id)
	squad.sort_custom(func(a: Player, b: Player): return a.influence > b.influence)
	var out: Array = []
	for i in squad.size():
		var p: Player = squad[i]
		var tier := "Suiveur"
		if i == 0 and p.influence >= 55.0:
			tier = "Patron du vestiaire"
		elif p.influence >= 62.0:
			tier = "Cadre influent"
		elif p.influence >= 44.0:
			tier = "Voix qui compte"
		elif p.age(world.today) <= 19:
			tier = "Jeune du groupe"
		out.append({"player": p, "influence": p.influence, "tier": tier})
	return out


## Clans : groupes de joueurs mutuellement proches (relation >= 45).
## Un clan de 2 est une amitié, un clan de 4 sur 5 est une équipe soudée,
## deux clans de 2 et 3 sont une équipe coupée en deux.
static func cliques(world: World, r: Roster) -> Array:
	var squad := world.players_of(r.id)
	var seen := {}
	var groups: Array = []
	for p_v in squad:
		var p: Player = p_v
		if seen.has(p.id):
			continue
		var group: Array = []
		var queue: Array = [p]
		seen[p.id] = true
		while not queue.is_empty():
			var cur: Player = queue.pop_back()
			group.append(cur)
			for other_v in squad:
				var other: Player = other_v
				if seen.has(other.id):
					continue
				if cur.relation_with(other.id) >= 45:
					seen[other.id] = true
					queue.append(other)
		if group.size() >= 2:
			groups.append(group)
	groups.sort_custom(func(a: Array, b: Array): return a.size() > b.size())
	return groups


## Duos en conflit ouvert (relation <= -55). Le manager doit trancher.
static func conflicts(world: World, r: Roster) -> Array:
	var squad := world.players_of(r.id)
	var out: Array = []
	for i in squad.size():
		for j in range(i + 1, squad.size()):
			var a: Player = squad[i]
			var b: Player = squad[j]
			if a.relation_with(b.id) <= -55:
				out.append({"a": a, "b": b, "value": a.relation_with(b.id)})
	out.sort_custom(func(x, y): return int(x["value"]) < int(y["value"]))
	return out


## Effet des dynamiques sur la cohésion hebdomadaire (multiplicateur).
## C'est le canal par lequel le vestiaire influence VRAIMENT les résultats.
static func chemistry_modifier(world: World, r: Roster) -> float:
	var atm := atmosphere(world, r)
	return clampf(0.45 + atm / 70.0, 0.25, 1.6)
