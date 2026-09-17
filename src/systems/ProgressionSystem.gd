class_name ProgressionSystem
extends RefCounted

## Développement, usure et fin de carrière des joueurs.
##
## L'esport a une courbe d'âge très différente du sport traditionnel : un
## joueur explose à 17-19 ans, plafonne vers 22-24 et décline dès 25-26 sur les
## qualités mécaniques (réflexes, visée) tout en continuant à progresser sur la
## lecture de jeu et le leadership. C'est pourquoi tant de joueurs deviennent
## IGL ou coach à 26 ans plutôt que de disparaître.
##
## Le BURNOUT est modélisé comme une ressource lente : il monte sous charge
## prolongée, il redescend beaucoup plus lentement, et il ne se voit pas
## directement — seulement à travers la baisse de forme. C'est le vrai risque
## d'une saison esport, bien plus que la blessure.

## Coût, en points d'expérience, d'un point d'attribut.
const XP_PER_POINT := 10.0
## Base de gain hebdomadaire, avant modulation par l'âge, la marge, la rigueur,
## l'encadrement et le programme d'entraînement.
const XP_BASE := 16.0

## Multiplicateur de progression par âge.
const AGE_GROWTH := {
	16: 1.55, 17: 1.45, 18: 1.30, 19: 1.15, 20: 1.00, 21: 0.85, 22: 0.70,
	23: 0.55, 24: 0.40, 25: 0.25, 26: 0.12, 27: 0.05,
}

## Quels attributs déclinent avec l'âge et lesquels continuent de progresser
## est une question de DISCIPLINE, pas de moteur : c'est le GameModule qui
## répond (`declining_attributes` / `ageing_attributes`). Un AWPeur perd son
## AWP avec ses réflexes, un contrôleur Valorant n'a pas d'AWP à perdre.


## Passe hebdomadaire sur tout le monde. Appelée chaque lundi par GameSim.
static func weekly_tick(world: World) -> void:
	for pid in world.players:
		var p: Player = world.players[pid]
		if p.retired:
			continue
		_recover(world, p)
		_develop(world, p)
		_update_morale(world, p)


static func _recover(world: World, p: Player) -> void:
	var rng := world.rng
	var recovery := 6.0
	var burnout_relief := 0.35
	var o := world.org(p.org_id)
	if o != null:
		# Une team house et un pôle performance changent tout sur la durée —
		# les murs, mais aussi la personne qui les fait vivre.
		var staff_care := StaffSystem.wellness_factor(world, o)
		recovery *= o.facility_effect(Facilities.Kind.TEAM_HOUSE)
		recovery *= o.facility_effect(Facilities.Kind.WELLNESS) * staff_care
		burnout_relief *= o.facility_effect(Facilities.Kind.WELLNESS) * staff_care
	p.fatigue = clampf(p.fatigue - recovery, 0.0, 100.0)

	# Le burnout ne recule que si la fatigue est déjà basse : se reposer une
	# semaine après trois mois de surcharge ne suffit pas.
	if p.fatigue < 30.0:
		p.burnout = clampf(p.burnout - burnout_relief
			* (1.0 + float(p.attr(Attributes.BURNOUT_RESISTANCE)) / 20.0), 0.0, 100.0)
	elif p.fatigue > 70.0:
		p.burnout = clampf(p.burnout + 0.55
			* (2.0 - float(p.attr(Attributes.BURNOUT_RESISTANCE)) / 20.0), 0.0, 100.0)

	# La netteté compétitive se perd sans matchs.
	p.sharpness = clampf(p.sharpness - 1.6, 0.0, 100.0)
	# Retour de blessure
	if p.injured_until >= 0 and world.today > p.injured_until:
		p.injured_until = -1
		p.injury_label = ""
		p.sharpness = clampf(p.sharpness - 12.0, 0.0, 100.0)


## Une semaine d'entraînement. Le gain dépend de la marge de progression, de
## l'âge, de la rigueur du joueur, du staff et des infrastructures.
static func _develop(world: World, p: Player) -> void:
	var rng := world.rng.derive("dev:%s:%d" % [p.id, world.today])
	var module := world.module_for(p.game_id)
	var age := p.age(world.today)

	var age_mult := float(AGE_GROWTH.get(clampi(age, 16, 27), 0.02))
	var headroom := p.growth_headroom()
	var ethic := float(p.attr(Attributes.WORK_ETHIC)) / 20.0
	var pro := float(p.attr(Attributes.PROFESSIONALISM)) / 20.0

	var coaching := 0.55
	var facility := 0.9
	var training := 1.0
	var focus: Dictionary = {}
	var o := world.org(p.org_id)
	if o != null:
		var r := world.main_roster(o.id, p.game_id)
		if r != null:
			# Ce que le manager a programmé cette semaine décide de CE QUI
			# progresse, et le repos décide de COMBIEN.
			training = TrainingSystem.growth_multiplier(r, p)
			focus = TrainingSystem.focus_weights(r, p)
		var coach := world.staffer(r.head_coach_id) if r != null else null
		var assistant: Staff = null
		if r != null:
			for sid in r.staff_ids:
				var s := world.staffer(sid)
				if s != null and s.role == Staff.Role.ASSISTANT_COACH:
					assistant = s
		var c1 := float(coach.attr(Staff.MECHANICAL_COACHING)) / 20.0 if coach != null else 0.3
		var c2 := float(assistant.attr(Staff.MECHANICAL_COACHING)) / 20.0 if assistant != null else 0.0
		var youth := float(coach.attr(Staff.YOUTH_DEVELOPMENT)) / 20.0 if coach != null else 0.3
		coaching = 0.35 + c1 * 0.45 + c2 * 0.25 + (youth * 0.3 if age <= 20 else 0.0)
		facility = o.facility_effect(Facilities.Kind.TRAINING_ROOM)
		if world.main_roster(o.id, p.game_id) != null \
				and not world.main_roster(o.id, p.game_id).starters.has(p.id):
			coaching *= 0.75   # un remplaçant progresse moins vite

	# Points de progression de la semaine.
	#
	# Étalonnage visé, en CA gagnée sur une saison complète avec un
	# encadrement correct :
	#   17-18 ans, gros potentiel .... +20 à +35   (le « wonderkid »)
	#   19-20 ans .................... +8  à +15
	#   22-23 ans .................... +2  à +5
	#   26 ans et plus ............... négatif (déclin mécanique)
	# La marge (headroom) éteint d'elle-même la progression quand la CA
	# rejoint le potentiel : inutile de plafonner ailleurs.
	var gain := XP_BASE * age_mult * headroom * (0.55 + ethic * 0.45) \
		* (0.6 + pro * 0.4) * coaching * facility * training
	gain *= 1.0 - clampf(p.burnout / 140.0, 0.0, 0.7)
	# Bruit MULTIPLICATIF : un bruit additif ferait progresser un joueur au
	# plafond, ce qui n'a aucun sens et gonflerait le monde saison après saison.
	gain *= rng.range_f(0.82, 1.18)

	var pool := float(p.game_data.get("_xp", 0.0)) + gain
	while pool >= XP_PER_POINT:
		pool -= XP_PER_POINT
		_bump_attribute(rng, module, p, 1, false, focus)
	# Le déclin ne touche que les mécaniques, et seulement passé le pic.
	if age >= 25 and rng.chance(0.10 + float(age - 25) * 0.05):
		_bump_attribute(rng, module, p, -1, true)
	p.game_data["_xp"] = pool
	AbilityCalc.refresh(p, module)
	p.market_value = PlayerFactory.market_value_for(p.current_ability,
		p.potential_ability, age, p.reputation)


## Fait bouger un attribut d'un point, en tirant en priorité ceux qui comptent
## pour le rôle (progression) ou ceux qui déclinent avec l'âge (régression).
##
## `focus` ajoute les poids issus du programme d'entraînement : c'est ce qui
## fait qu'une semaine de mécanique fait progresser la visée plutôt que la
## lecture de jeu. Sans lui, régler l'entraînement ne servirait à rien.
static func _bump_attribute(rng: Rng, module: GameModule, p: Player,
		delta: int, decline: bool = false, focus: Dictionary = {}) -> void:
	var candidates: Array[String] = []
	var weights: Array[float] = []
	if decline:
		for k in module.declining_attributes():
			if p.attr(k) > 4:
				candidates.append(k)
				weights.append(float(p.attr(k)))
	else:
		var role_w := module.role_weights(p.primary_role)
		for k in role_w:
			if p.attr(k) < Attributes.MAX:
				candidates.append(k)
				weights.append(float(role_w[k]) + float(focus.get(k, 0.0)))
		# Un joueur âgé progresse surtout sur la compréhension du jeu.
		for k in module.ageing_attributes():
			if p.attr(k) < Attributes.MAX:
				candidates.append(k)
				weights.append(1.2 + float(focus.get(k, 0.0)))
		# Un travail individuel sur un attribut hors du profil de poste doit
		# rester possible : c'est comme ça qu'on reconvertit un joueur.
		if p.training_focus != "" and not candidates.has(p.training_focus) \
				and p.attr(p.training_focus) < Attributes.MAX:
			candidates.append(p.training_focus)
			weights.append(float(focus.get(p.training_focus, 3.2)))
	if candidates.is_empty():
		return
	var idx := 0
	var total := 0.0
	for w in weights:
		total += w
	var roll := rng.randf() * total
	for i in weights.size():
		roll -= weights[i]
		if roll <= 0.0:
			idx = i
			break
	p.set_attr(candidates[idx], p.attr(candidates[idx]) + delta)


## Moral : influencé par le temps de jeu, les résultats, l'ambition et la
## satisfaction contractuelle. Un joueur ambitieux dans une équipe qui perd
## devient un problème, même s'il est bien payé.
static func _update_morale(world: World, p: Player) -> void:
	if p.is_free_agent():
		p.morale = clampf(p.morale - 0.6, 10.0, 100.0)
		return
	var o := world.org(p.org_id)
	var r := world.main_roster(p.org_id, p.game_id)
	if o == null or r == null:
		return

	var drift := 0.0
	var benched := not r.starters.has(p.id)
	var ambition := float(p.attr(Attributes.AMBITION)) / 20.0
	if benched:
		drift -= 1.2 + ambition * 2.0
	else:
		drift += 0.4

	# Résultats de l'équipe
	var w := 0
	var l := 0
	for cid in r.season_record:
		var rec: Dictionary = r.season_record[cid]
		w += int(rec.get("w", 0))
		l += int(rec.get("l", 0))
	if w + l >= 3:
		drift += (float(w) / float(w + l) - 0.5) * 4.0

	# Salaire perçu comme juste ou non
	if p.contract != null:
		var expected := PlayerFactory.salary_for_ca(p.current_ability, p.reputation)
		var ratio := float(p.contract.salary_yearly) / maxf(float(expected), 1.0)
		drift += clampf((ratio - 1.0) * 2.5, -2.5, 1.5)
		if p.contract.days_remaining(world.today) < 120:
			drift -= 0.8 * ambition

	# Encadrement humain
	var manager_bonus := 0.0
	for sid in o.staff_ids:
		var s := world.staffer(sid)
		if s == null:
			continue
		if s.role == Staff.Role.PSYCHOLOGIST or s.role == Staff.Role.TEAM_MANAGER:
			manager_bonus = maxf(manager_bonus,
				float(s.attr(Staff.MAN_MANAGEMENT)) / 20.0)
	drift += manager_bonus * 1.2
	drift -= p.burnout / 40.0
	# Les griefs nommés pèsent directement : c'est ce qui rend une
	# conversation utile plutôt que cosmétique.
	drift -= DynamicsSystem.grievance_pressure(p) * 0.55
	# Rappel vers la moyenne : sans lui, tous les moraux finissent collés à 0
	# ou à 100 et la jauge ne dit plus rien. Un joueur normalement traité
	# gravite autour de 60, ce qui laisse de la place au-dessus et en dessous.
	drift += (60.0 - p.morale) * 0.07

	p.morale = clampf(p.morale + drift, 0.0, 100.0)
	p.happiness = clampf(p.happiness + drift * 0.7, 0.0, 100.0)
	# Un joueur durablement malheureux demande à partir.
	if p.happiness < 22.0 and not p.wants_out:
		p.wants_out = true
		if world.player_org_id == p.org_id:
			world.add_news(world.today, "%s veut partir" % p.display_name(),
				"%s a fait savoir qu'il souhaitait quitter la structure."
					% p.display_name(), "squad", {"player_id": p.id})
	elif p.happiness > 45.0 and p.wants_out:
		p.wants_out = false


# ============================================================================
# Effets d'un match
# ============================================================================

## Applique l'après-match : forme, fatigue, netteté, expérience, réputation,
## risque de blessure. Le vrai coût d'une saison se paie ici, match par match.
static func after_match(world: World, f: Fixture, res: MatchResult) -> void:
	var rng := world.rng.derive("post:%s" % f.id)
	var maps_played := maxi(res.maps.size(), 1)
	var load := float(maps_played) * (1.0 + (f.importance - 1.0) * 0.4)
	if f.is_lan:
		load *= 1.25

	for pid in res.player_stats:
		var p := world.player(pid)
		if p == null:
			continue
		var st: Dictionary = res.player_stats[pid]
		var rating := float(st.get("rating", 1.0))
		var won := str(st.get("team", "")) == res.winner_id

		# Forme : moyenne glissante lente, pour qu'un seul match ne suffise pas.
		# Repère : une note de 1.00 avec un bilan équilibré doit ramener la forme
		# vers 50, pas vers 35.
		var target := clampf(50.0 + (rating - 1.0) * 55.0 + (6.0 if won else -6.0),
			0.0, 100.0)
		p.form = lerpf(p.form, target, 0.32)
		p.sharpness = clampf(p.sharpness + 6.0 * float(maps_played), 0.0, 100.0)
		p.fatigue = clampf(p.fatigue + load * 5.5
			* (1.4 - float(p.attr(Attributes.STAMINA)) / 20.0), 0.0, 100.0)
		# Jouer use aussi la tête, et pas seulement les poignets : un calendrier
		# à quarante séries laisse des traces qu'une semaine de vacances
		# n'efface pas. C'est ce qui rend le calendrier gérable, et non subi.
		p.burnout = clampf(p.burnout + load * 0.22
			* (1.4 - float(p.attr(Attributes.BURNOUT_RESISTANCE)) / 20.0),
			0.0, 100.0)
		p.morale = clampf(p.morale + (3.0 if won else -2.4)
			+ (rating - 1.0) * 6.0, 0.0, 100.0)

		# Réputation individuelle : jouer un gros match et bien y jouer paie.
		var comp := world.competition(f.competition_id)
		var prestige := float(comp.prestige if comp != null else 3000)
		var rep_delta := (rating - 0.95) * prestige / 260.0
		p.reputation = clampi(p.reputation + int(round(rep_delta)), 5, 10000)
		if rating > 1.25:
			p.fan_appeal = clampi(p.fan_appeal + 1, 1, 100)

		_check_injury(world, rng, p, load)
		_accumulate_season_stats(p, st, world.module_for(p.game_id))

	# Frais de déplacement pour une LAN.
	if f.is_lan:
		for rid in [f.home_id, f.away_id]:
			var r := world.roster(rid)
			var o := world.org(r.org_id) if r != null else null
			if o != null:
				o.ledger.debit(world.today, Money.from_units(2_500.0),
					Transaction.Category.TRAVEL,
					"Déplacement — %s" % f.round_label, "")


## Blessures et pépins spécifiques à l'esport.
const INJURIES := [
	["Tendinite du poignet", 10, 40],
	["Douleurs dorsales", 5, 21],
	["Syndrome du canal carpien", 25, 90],
	["Fatigue oculaire", 4, 12],
	["Épuisement — arrêt médical", 14, 45],
	["Douleur à l'épaule", 7, 25],
]


static func _check_injury(world: World, rng: Rng, p: Player, load: float) -> void:
	if p.is_injured(world.today):
		return
	var proneness := float(p.attr(Attributes.INJURY_PRONENESS)) / 20.0
	var wellness := 1.0
	var o := world.org(p.org_id)
	if o != null:
		wellness = 2.0 - o.facility_effect(Facilities.Kind.WELLNESS)
		wellness /= StaffSystem.wellness_factor(world, o)
	var risk := 0.0025 * load * (0.4 + proneness * 1.6) \
		* (1.0 + p.fatigue / 90.0) * (1.0 + p.burnout / 70.0) * wellness
	if not rng.chance(clampf(risk, 0.0, 0.08)):
		return
	var inj: Array = rng.pick(INJURIES)
	var days := rng.range_i(int(inj[1]), int(inj[2]))
	p.injured_until = world.today + days
	p.injury_label = str(inj[0])
	if world.player_org_id == p.org_id:
		world.add_news(world.today, "Blessure : %s" % p.display_name(),
			"%s — indisponible environ %d jours." % [p.injury_label, days],
			"squad", {"player_id": p.id})


static func _accumulate_season_stats(p: Player, st: Dictionary,
		module: GameModule) -> void:
	if p.season_stats.is_empty():
		p.season_stats = MatchResult.empty_stats()
		p.season_stats["series"] = 0
	for k in MatchResult.STAT_KEYS:
		p.season_stats[k] = int(p.season_stats.get(k, 0)) + int(st.get(k, 0))
	p.season_stats["series"] = int(p.season_stats.get("series", 0)) + 1
	module.compute_derived_stats(p.season_stats)


# ============================================================================
# Historique de développement
# ============================================================================

## Nombre d'instantanés conservés par joueur (5 ans de mensuel).
const HISTORY_LIMIT := 60


## Instantané mensuel : c'est ce qui permet d'afficher une COURBE de
## progression plutôt qu'un chiffre isolé, et donc de juger un choix
## d'entraînement sur trois mois au lieu de le subir.
##
## Pour les joueurs de la structure du joueur, on garde le détail par attribut
## (« +2 en visée depuis janvier ») ; pour les ~700 autres, seulement les
## agrégats, sinon la sauvegarde enfle sans que personne ne lise la donnée.
static func monthly_snapshot(world: World) -> void:
	for pid in world.players:
		var p: Player = world.players[pid]
		if p.retired:
			continue
		var module := world.module_for(p.game_id)
		var snap := {
			"day": world.today,
			"ca": p.current_ability,
			"pa": p.potential_ability,
			"form": int(round(p.form)),
			"morale": int(round(p.morale)),
		}
		for group_name in module.attribute_groups():
			snap[str(group_name).to_lower()] = int(round(
				_group_average(p, module.attribute_groups()[group_name]) * 10.0))
		if p.org_id != "" and p.org_id == world.player_org_id:
			snap["attrs"] = p.attributes.duplicate()
		p.development.append(snap)
		if p.development.size() > HISTORY_LIMIT:
			p.development = p.development.slice(
				p.development.size() - HISTORY_LIMIT)


static func _group_average(p: Player, keys: Array) -> float:
	if keys.is_empty():
		return 0.0
	var total := 0.0
	for k in keys:
		total += float(p.attr(str(k)))
	return total / float(keys.size())


## Archive la saison écoulée dans le bilan de carrière du joueur.
## Une ligne par saison, comme la page « historique » de Football Manager :
## c'est ce qui donne une épaisseur aux joueurs qu'on suit depuis trois ans.
static func archive_season(world: World) -> void:
	for pid in world.players:
		var p: Player = world.players[pid]
		var series := int(p.season_stats.get("series", 0))
		if series == 0:
			continue
		var o := world.org(p.org_id)
		p.career.append({
			"year": world.season_year,
			"org": o.name if o != null else "Agent libre",
			"series": series,
			"rating": float(p.season_stats.get("rating", 0.0)),
			"acs": float(p.season_stats.get("acs", 0.0)),
			"kills": int(p.season_stats.get("kills", 0)),
			"deaths": int(p.season_stats.get("deaths", 0)),
			"ca": p.current_ability,
		})
		# Vingt saisons suffisent largement : personne ne joue vingt ans.
		if p.career.size() > 20:
			p.career = p.career.slice(p.career.size() - 20)


## Progression par attribut sur les N derniers mois, pour la fiche joueur.
## Renvoie {clé: delta} et ne contient que les attributs qui ont bougé.
static func attribute_changes(p: Player, months: int = 6) -> Dictionary:
	var out := {}
	if p.development.size() < 2:
		return out
	var idx := maxi(0, p.development.size() - 1 - months)
	var old: Dictionary = p.development[idx]
	if not old.has("attrs"):
		return out
	var before: Dictionary = old["attrs"]
	for k in p.attributes:
		var d := int(p.attributes[k]) - int(before.get(k, p.attributes[k]))
		if d != 0:
			out[k] = d
	return out


# ============================================================================
# Fin de carrière
# ============================================================================

## Passe annuelle : retraites et rajeunissement du vivier.
static func yearly_retirements(world: World) -> void:
	var rng := world.rng.derive("retire:%d" % world.today)
	for pid in world.players.keys():
		var p: Player = world.players[pid]
		if p.retired:
			continue
		var age := p.age(world.today)
		# Un espoir jamais signé arrête vers 20-21 ans : sans structure, on ne
		# vit pas de l'esport. Sans cette porte de sortie, le marché se remplit
		# d'adolescents éternels que personne ne recrutera jamais.
		if p.is_free_agent() and age >= 20 and age < 24:
			var give_up := clampf(float(age - 19) * 0.30
				+ float(110 - p.current_ability) / 260.0, 0.05, 0.85)
			if rng.chance(give_up):
				p.retired = true
				p.retire_day = world.today
			continue
		if age < 24:
			continue
		var chance := clampf(float(age - 23) * 0.055, 0.0, 0.9)
		# Un joueur en fin de contrat, sans club et en perte de niveau part vite.
		if p.is_free_agent():
			chance += 0.25
		chance += clampf((float(p.potential_ability - p.current_ability)) / -200.0, 0.0, 0.2)
		chance += p.burnout / 250.0
		chance -= float(p.attr(Attributes.AMBITION)) / 200.0
		if rng.chance(clampf(chance, 0.0, 0.95)):
			p.retired = true
			p.retire_day = world.today
			if p.org_id != "":
				var r := world.main_roster(p.org_id, p.game_id)
				if r != null:
					r.remove_player(p.id)
				if world.player_org_id == p.org_id:
					world.add_news(world.today, "%s prend sa retraite" % p.display_name(),
						"À %d ans, %s met fin à sa carrière professionnelle."
							% [age, p.long_name()], "squad")
				p.org_id = ""
				p.contract = null
