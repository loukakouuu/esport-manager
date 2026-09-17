class_name StaffSystem
extends RefCounted

## Marché de l'encadrement : recruter, prolonger, licencier.
##
## Le staff existait depuis le début et pesait déjà sur cinq systèmes — mais il
## était généré une fois pour toutes et jamais renouvelé. Deux conséquences,
## mesurées avant d'écrire ce fichier, sur trois saisons simulées :
##
##   * les 338 encadrants du monde tombaient à ZÉRO — les contrats expirent et
##     personne ne rembauche ;
##   * chaque roster gardait pourtant son entraîneur BRANCHÉ : `head_coach_id`
##     n'était pas nettoyé à l'expiration, donc la structure cessait de le payer
##     mais conservait son apport tactique. 136 coachs fantômes.
##
## D'où la règle qui gouverne ce fichier : un encadrant n'est rattaché que par
## `attach()` et détaché que par `detach()`. Aucun autre code ne touche
## `Roster.head_coach_id` ni `Organization.staff_ids`.
##
## Choix de conception : contrairement aux joueurs, le staff ne se négocie pas
## clause par clause. Ce serait la même mécanique une deuxième fois, pour un
## enjeu plus faible. L'arbitrage intéressant du staff est ailleurs — quels
## postes vaut-il la peine de payer, à quel niveau, pour quelle masse salariale
## mensuelle. Une offre, une réponse.

# ============================================================================
# Barème et réglages
# ============================================================================

## Postes de BANC : rattachés à UNE équipe, donc recrutés autant de fois que la
## maison aligne de sections. Une écurie qui tient un roster Valorant et un
## roster Counter-Strike paie deux entraîneurs et deux analystes — c'est ce
## qu'elle fait dans la réalité, et sans ça sa deuxième équipe jouerait toute
## la saison avec le niveau tactique plancher.
##
## Les autres postes (team manager, préparateurs, recruteur, contenu, directeur
## sportif) servent toute la maison et ne sont recrutés qu'une fois.
const TEAM_ROLES: Array[int] = [
	Staff.Role.HEAD_COACH,
	Staff.Role.ANALYST,
	Staff.Role.ASSISTANT_COACH,
]


## Postes par ordre d'utilité décroissante. Sert à l'IA comme à l'affichage :
## un entraîneur avant un analyste, un analyste avant un directeur sportif.
const ROLE_ORDER: Array[int] = [
	Staff.Role.HEAD_COACH,
	Staff.Role.ANALYST,
	Staff.Role.ASSISTANT_COACH,
	Staff.Role.TEAM_MANAGER,
	Staff.Role.PERFORMANCE_COACH,
	Staff.Role.PSYCHOLOGIST,
	Staff.Role.SCOUT,
	Staff.Role.CONTENT_MANAGER,
	Staff.Role.GENERAL_MANAGER,
]

## Ce que chaque poste change réellement dans le moteur. Cette table n'est pas
## de la décoration : c'est la promesse faite au joueur, et chaque ligne
## correspond à du code qu'on peut montrer du doigt.
const ROLE_EFFECTS := {
	Staff.Role.HEAD_COACH:
		"Niveau tactique et cohésion en match, progression des joueurs, cohésion gagnée à l'entraînement, recrutement en académie",
	Staff.Role.ASSISTANT_COACH:
		"Progression mécanique des joueurs, en renfort de l'entraîneur principal",
	Staff.Role.ANALYST:
		"Préparation adverse : niveau tactique de l'équipe en match",
	Staff.Role.TEAM_MANAGER:
		"Moral du groupe au quotidien, et un peu de poids en négociation",
	Staff.Role.PSYCHOLOGIST:
		"Moral du groupe, et récupération de l'usure mentale",
	Staff.Role.PERFORMANCE_COACH:
		"Récupération de la fatigue, résorption du burnout, risque de blessure",
	Staff.Role.SCOUT:
		"Fiabilité de ce que votre staff sait des joueurs que vous ne possédez pas",
	Staff.Role.CONTENT_MANAGER:
		"Nombre d'activations sponsors réalisables chaque mois",
	Staff.Role.GENERAL_MANAGER:
		"Commission d'agent à la signature, patience des agents en négociation",
}

const MIN_MONTHS := 6
const MAX_MONTHS := 36
const DEFAULT_MONTHS := 18

## Indemnité de rupture : part du salaire restant dû réellement versée. Plus
## douce que pour un joueur (0,65) — un encadrant se replace vite.
const SEVERANCE_RATE := 0.55

## Après un refus, la structure ne peut pas re-solliciter la même personne
## avant trois semaines. Sans ce délai, « proposer jusqu'à ce que ça passe »
## rendrait le taux d'acceptation décoratif.
const REFUSAL_COOLDOWN := 21

## Taille visée du vivier libre, par poste et par région.
const MARKET_TARGET := 5
const REGIONS: Array[String] = ["EMEA", "AMERICAS", "PACIFIC", "CHINA"]

## Au-delà, un encadrant sans poste quitte le milieu.
const RETIRE_AGE := 62

## Part maximale des recettes récurrentes qu'une structure IA consacre à son
## encadrement. L'en-tête de FinanceSystem annonce 10-20 % : on s'y tient.
const AI_PAYROLL_SHARE := 0.22

## Commission d'agent de base sur une embauche, en % du salaire annuel.
const AGENT_FEE_PCT := 6.0


# ============================================================================
# Vivier
# ============================================================================

## Peuple le marché au démarrage du monde. Appelé par WorldGenerator après que
## les structures ont pris leur propre encadrement : les gens libres sont ceux
## que personne n'a voulus, plus quelques pointures entre deux projets.
static func seed_market(world: World) -> void:
	var rng := world.rng.derive("staffmarket")
	for region in REGIONS:
		for role in ROLE_ORDER:
			for game_id in _market_games(role):
				for _i in MARKET_TARGET:
					_spawn_free(world, rng, role, region, str(game_id))


## Disciplines pour lesquelles il faut un vivier à ce poste. Les postes de banc
## sont spécialisés — un entraîneur Counter-Strike ne se recrute pas dans le
## vivier Valorant — et tous les autres sont polyvalents (game_id vide).
static func _market_games(role: int) -> Array:
	if not TEAM_ROLES.has(role):
		return [""]
	var out: Array = []
	for g in GameRegistry.all_ids():
		out.append(g)
	return out


static func _spawn_free(world: World, rng: Rng, role: int, region: String,
		game_id: String = "") -> Staff:
	# Le vivier libre est en moyenne moins bon que le staff en poste, avec une
	# queue haute : c'est là qu'on trouve la perle qu'une structure vient de
	# laisser filer.
	var target := rng.gauss(9.4, 3.1, 2.0, 19.0)
	var s := StaffFactory.create(rng, world.ids, world.today, role as Staff.Role, {
		"region": region,
		"target_overall": target,
		"game_id": game_id,
	})
	world.staff[s.id] = s
	return s


## Entretien hebdomadaire du vivier : les trop vieux s'en vont, quelques-uns
## disparaissent, et on complète jusqu'à la cible. Sans cela le marché se vide
## (tout le monde finit embauché) ou enfle (personne ne part jamais).
static func market_upkeep(world: World) -> void:
	var rng := world.rng.derive("staffupkeep:%d" % world.today)
	var counts := {}
	var doomed: Array[String] = []
	for sid in world.staff:
		var s: Staff = world.staff[sid]
		if s.org_id != "":
			continue
		if s.age(world.today) >= RETIRE_AGE or rng.chance(0.012):
			doomed.append(s.id)
			continue
		var key := "%s|%d|%s" % [s.region, int(s.role),
			s.game_id if TEAM_ROLES.has(int(s.role)) else ""]
		counts[key] = int(counts.get(key, 0)) + 1
	for sid in doomed:
		world.staff.erase(sid)

	for region in REGIONS:
		for role in ROLE_ORDER:
			for game_id in _market_games(role):
				var key := "%s|%d|%s" % [region, int(role), str(game_id)]
				var missing := MARKET_TARGET - int(counts.get(key, 0))
				for _i in maxi(missing, 0):
					_spawn_free(world, rng, role, region, str(game_id))


## Encadrants sans employeur, filtrés et triés du meilleur au moins bon.
##
## `game_id` ne filtre que les postes de BANC, et laisse toujours passer les
## polyvalents (`game_id` vide) : un préparateur mental ne dépend pas de la
## discipline, un entraîneur si.
static func free_agents(world: World, role: int = -1, region: String = "",
		game_id: String = "") -> Array[Staff]:
	var out: Array[Staff] = []
	for sid in world.staff:
		var s: Staff = world.staff[sid]
		if s.org_id != "":
			continue
		if role >= 0 and int(s.role) != role:
			continue
		if region != "" and s.region != region:
			continue
		if game_id != "" and s.game_id != "" and s.game_id != game_id:
			continue
		out.append(s)
	out.sort_custom(func(a: Staff, b: Staff) -> bool:
		return a.overall() > b.overall())
	return out


# ============================================================================
# Prix et acceptation
# ============================================================================

## Salaire annuel réclamé par un encadrant pour rejoindre CETTE structure.
##
## Le barème de base ne dépend que de son niveau ; ce qui varie, c'est la prime
## de risque. Un coach coté qui descend dans une structure inconnue se fait
## payer sa prise de risque ; le même, appelé par une écurie plus prestigieuse
## que lui, rabat ses prétentions.
static func salary_demand(world: World, s: Staff, org: Organization) -> int:
	var base := StaffFactory.salary_for(s.role, s.overall())
	var ratio := float(s.reputation) / maxf(float(org.reputation), 200.0)
	var mult := clampf(1.0 + (ratio - 1.0) * 0.22, 0.85, 1.55)
	# Une structure au bord du dépôt de bilan paie sa réputation d'employeur.
	if org.months_in_deficit >= 3:
		mult += 0.12
	return Money.pct(base, mult * 100.0)


## Probabilité qu'il accepte l'offre. Rendue au joueur sous forme de verdict,
## jamais de pourcentage : c'est un accord entre deux personnes, pas un jet de
## dés annoncé à l'avance.
static func acceptance_chance(world: World, s: Staff, org: Organization,
		salary: int, months: int) -> float:
	if org.bankrupt:
		return 0.0
	var demand := salary_demand(world, s, org)
	var pay := clampf(float(salary) / maxf(float(demand), 1.0), 0.45, 1.9)
	var score := (pay - 1.0) * 2.4

	# L'attrait du projet compte autant que l'argent pour un encadrant : on
	# n'entraîne pas pour le salaire seul.
	var pull := clampf(float(org.reputation) / maxf(float(s.reputation), 200.0),
		0.0, 2.5)
	score += (pull - 1.0) * 0.62

	# Personne ne signe six mois s'il peut en avoir deux ans ailleurs.
	if months < 12:
		score -= float(12 - months) * 0.045
	if org.months_in_deficit >= 3:
		score -= 0.35
	score -= clampf(60.0 - org.board_confidence, 0.0, 60.0) / 220.0

	return clampf(0.5 + score, 0.02, 0.97)


## Le même chiffre, dit comme le dirait un intermédiaire.
static func verdict(chance: float) -> String:
	if chance >= 0.85:
		return "Signera sans hésiter"
	if chance >= 0.62:
		return "Intéressé"
	if chance >= 0.38:
		return "Hésitera"
	if chance >= 0.15:
		return "Peu probable"
	return "Refusera"


## Un encadrant qui vient de dire non à cette structure.
static func is_cooling_off(world: World, s: Staff, org: Organization) -> bool:
	return s.last_refused_org == org.id and world.today < s.refused_until


# ============================================================================
# Embauche, prolongation, licenciement
# ============================================================================

## Tente une embauche. Retourne {"ok": bool, "reason": String}.
static func hire(world: World, org: Organization, s: Staff, salary: int,
		months: int, roster_id: String = "") -> Dictionary:
	if s.org_id != "":
		return {"ok": false,
			"reason": "%s est déjà sous contrat." % s.display_name()}
	if is_cooling_off(world, s, org):
		return {"ok": false, "reason":
			"%s a décliné récemment : il faut le laisser respirer."
				% s.display_name()}
	months = clampi(months, MIN_MONTHS, MAX_MONTHS)
	var fee := agent_fee(world, org, salary)
	if org.ledger.cash < fee:
		return {"ok": false, "reason":
			"Commission d'agent de %s, trésorerie insuffisante." % Money.fmt(fee)}

	var rng := world.rng.derive("hire:%s:%s:%d" % [org.id, s.id, world.today])
	if not rng.chance(acceptance_chance(world, s, org, salary, months)):
		s.last_refused_org = org.id
		s.refused_until = world.today + REFUSAL_COOLDOWN
		return {"ok": false, "reason":
			"%s décline : l'offre ne le convainc pas." % s.display_name()}

	var c := Contract.new()
	c.kind = Contract.Kind.STAFF
	c.org_id = org.id
	c.person_id = s.id
	c.salary_yearly = salary
	c.start_day = world.today
	c.end_day = GameDate.add_months(world.today, months)
	c.signed_on_day = world.today
	# La commission est débitée ici : on ne la recompte pas dans upfront_cost().
	c.agent_fee_pct = 0.0
	if fee > 0:
		org.ledger.debit(world.today, fee, Transaction.Category.AGENT_FEE,
			"Commission d'agent %s" % s.display_name(), s.id)
	s.contract = c
	s.last_refused_org = ""
	s.refused_until = 0
	attach(world, org, s, roster_id)

	if world.player_org_id == org.id:
		world.add_news(world.today, "Arrivée : %s" % s.display_name(),
			"%s rejoint la structure comme %s pour %s par an, jusqu'en %s."
				% [s.full_name(), s.role_label().to_lower(), Money.fmt(salary),
					GameDate.format_month_year(c.end_day)],
			"staff", {"staff_id": s.id})
	return {"ok": true, "reason": ""}


## Commission d'agent sur une embauche. Le directeur sportif la fait baisser :
## c'est le premier effet concret d'un poste qui n'en avait aucun.
static func agent_fee(world: World, org: Organization, salary: int) -> int:
	var pct := AGENT_FEE_PCT * (1.0 - negotiation_edge(world, org) * 0.5)
	return Money.pct(salary, pct)


## Rattache un encadrant à la structure, et à un roster s'il encadre une
## équipe. Seul point d'entrée : voir l'en-tête du fichier.
static func attach(world: World, org: Organization, s: Staff,
		roster_id: String = "") -> void:
	s.org_id = org.id
	if not org.staff_ids.has(s.id):
		org.staff_ids.append(s.id)
	var r := world.roster(roster_id) if roster_id != "" \
		else world.main_roster(org.id, s.game_id)
	if r == null:
		return
	if not TEAM_ROLES.has(int(s.role)):
		# Un poste transverse n'est pas rattaché à un banc : l'accrocher au
		# roster ferait croire qu'il appartient à une section plutôt qu'à la
		# maison, et il disparaîtrait de l'écran dès qu'on change d'équipe.
		return
	# Un encadrant de banc suit la discipline de l'équipe qu'il prend, même
	# s'il vient d'un autre jeu : c'est courant, et un coach CS2 rattaché à un
	# roster Valorant serait un bug invisible.
	s.game_id = r.game_id
	if s.role == Staff.Role.HEAD_COACH:
		var previous := world.staffer(r.head_coach_id)
		if previous != null and previous.id != s.id \
				and not r.staff_ids.has(previous.id):
			# On ne garde pas deux entraîneurs principaux : l'ancien reste au
			# staff jusqu'à la fin de son contrat, sans le banc.
			r.staff_ids.append(previous.id)
		r.head_coach_id = s.id
		r.staff_ids.erase(s.id)
	elif not r.staff_ids.has(s.id):
		r.staff_ids.append(s.id)


## Détache complètement. Nettoie AUSSI les rosters : c'est l'oubli qui a
## produit 136 coachs fantômes.
static func detach(world: World, s: Staff) -> void:
	var o := world.org(s.org_id)
	if o != null:
		o.staff_ids.erase(s.id)
		for rid in o.all_roster_ids():
			var r := world.roster(rid)
			if r == null:
				continue
			if r.head_coach_id == s.id:
				r.head_coach_id = ""
			r.staff_ids.erase(s.id)
	s.org_id = ""
	s.contract = null


## Prolongation d'un encadrant déjà en poste. Il connaît la maison : à prix
## égal, il est plus facile à convaincre qu'un inconnu.
static func renew(world: World, org: Organization, s: Staff, salary: int,
		months: int) -> Dictionary:
	if s.org_id != org.id or s.contract == null:
		return {"ok": false,
			"reason": "%s n'est pas sous vos ordres." % s.display_name()}
	months = clampi(months, MIN_MONTHS, MAX_MONTHS)
	var chance := clampf(acceptance_chance(world, s, org, salary, months) + 0.12,
		0.02, 0.98)
	var rng := world.rng.derive("renew:%s:%s:%d" % [org.id, s.id, world.today])
	if not rng.chance(chance):
		s.last_refused_org = org.id
		s.refused_until = world.today + REFUSAL_COOLDOWN
		return {"ok": false, "reason":
			"%s préfère aller au bout de son contrat." % s.display_name()}
	s.contract.salary_yearly = salary
	s.contract.end_day = GameDate.add_months(world.today, months)
	s.contract.signed_on_day = world.today
	return {"ok": true, "reason": ""}


## Licenciement. Retourne l'indemnité versée, en cents.
static func dismiss(world: World, org: Organization, s: Staff) -> int:
	if s.org_id != org.id:
		return 0
	var cost := severance(world, s)
	if cost > 0:
		org.ledger.debit(world.today, cost, Transaction.Category.STAFF_SALARY,
			"Indemnité de rupture %s" % s.display_name(), s.id)
	if world.player_org_id == org.id:
		world.add_news(world.today, "Départ : %s" % s.display_name(),
			"%s quitte son poste de %s. Indemnité versée : %s."
				% [s.full_name(), s.role_label().to_lower(), Money.fmt(cost)],
			"staff", {"staff_id": s.id})
	detach(world, s)
	return cost


static func severance(world: World, s: Staff) -> int:
	if s.contract == null:
		return 0
	var remaining := maxi(s.contract.days_remaining(world.today), 0)
	return int(round(float(s.contract.salary_yearly) * float(remaining) / 365.0
		* SEVERANCE_RATE))


# ============================================================================
# Ce que l'encadrement apporte, en clair
# ============================================================================

## Titulaire d'un poste dans la structure (le meilleur s'il y en a plusieurs),
## null si le poste est vacant.
## Qui occupe ce poste ? Pour un poste de banc, la question n'a de sens qu'à
## l'échelle d'une ÉQUIPE : `roster_id` restreint donc la recherche au banc de
## cette équipe-là. Sans lui, une maison à deux sections paraîtrait avoir un
## entraîneur partout alors que sa deuxième équipe n'en a pas.
static func holder(world: World, org: Organization, role: int,
		roster_id: String = "") -> Staff:
	if roster_id != "" and TEAM_ROLES.has(role):
		return _bench_holder(world, roster_id, role)
	var best: Staff = null
	for sid in org.staff_ids:
		var s := world.staffer(sid)
		if s == null or int(s.role) != role:
			continue
		if best == null or s.overall() > best.overall():
			best = s
	return best


static func _bench_holder(world: World, roster_id: String, role: int) -> Staff:
	var r := world.roster(roster_id)
	if r == null:
		return null
	if role == Staff.Role.HEAD_COACH:
		return world.staffer(r.head_coach_id)
	var best: Staff = null
	for sid in r.staff_ids:
		var s := world.staffer(sid)
		if s == null or int(s.role) != role:
			continue
		if best == null or s.overall() > best.overall():
			best = s
	return best


## Équipes d'une structure réellement engagées en compétition — celles qui ont
## besoin d'un banc. L'académie s'entraîne, elle ne dispute pas de saison.
static func competitive_rosters(world: World, org: Organization) -> Array[Roster]:
	var out: Array[Roster] = []
	for r in world.rosters_of(org.id):
		if not r.is_academy:
			out.append(r)
	return out


## Facteur de récupération apporté par le pôle performance : 1,0 sans personne,
## jusqu'à 1,35 avec un préparateur d'élite. Lu par ProgressionSystem pour la
## fatigue, le burnout et le risque de blessure.
static func wellness_factor(world: World, org: Organization) -> float:
	if org == null:
		return 1.0
	var best := 0.0
	for sid in org.staff_ids:
		var s := world.staffer(sid)
		if s == null:
			continue
		if s.role != Staff.Role.PERFORMANCE_COACH \
				and s.role != Staff.Role.PSYCHOLOGIST:
			continue
		var w := float(s.attr(Staff.WELLNESS)) / 20.0
		# Le préparateur physique est là pour ça ; le préparateur mental n'en
		# couvre qu'une partie.
		if s.role == Staff.Role.PSYCHOLOGIST:
			w *= 0.55
		best = maxf(best, w)
	return 1.0 + best * 0.35


## Poids du directeur sportif dans les négociations : 0 sans personne, 1 avec
## un négociateur à 20. Réduit la commission d'agent et use moins la patience.
static func negotiation_edge(world: World, org: Organization) -> float:
	if org == null:
		return 0.0
	var best := 0.0
	for sid in org.staff_ids:
		var s := world.staffer(sid)
		if s == null:
			continue
		if s.role != Staff.Role.GENERAL_MANAGER \
				and s.role != Staff.Role.TEAM_MANAGER:
			continue
		var v := float(s.attr(Staff.NEGOTIATION)) / 20.0
		if s.role == Staff.Role.TEAM_MANAGER:
			v *= 0.5
		best = maxf(best, v)
	return clampf(best, 0.0, 1.0)


## Tableau de bord de l'encadrement : un poste par ligne, avec ce que la
## personne en place apporte vraiment. C'est ce qui rend le staff lisible —
## jusqu'ici le joueur payait des salaires sans jamais voir la contrepartie.
## `roster_id` est la section regardée : pour un poste de banc, c'est SON
## occupant qu'on décrit, pas le meilleur de la maison.
static func effect_summary(world: World, org: Organization,
		roster_id: String = "") -> Array:
	var out: Array = []
	for role in ROLE_ORDER:
		var s := holder(world, org, role, roster_id)
		out.append({
			"role": role,
			"label": Staff.ROLE_LABELS.get(role, "Staff"),
			"effect": ROLE_EFFECTS.get(role, ""),
			"staff": s,
			"team_role": TEAM_ROLES.has(role),
			"delivers": _delivers(world, org, role, s),
		})
	return out


static func _delivers(world: World, org: Organization, role: int,
		s: Staff) -> String:
	match role:
		Staff.Role.HEAD_COACH:
			if s == null:
				return "Aucun entraîneur : apport tactique au plancher (8/20)"
			return "Tactique %d, gestion humaine %d, formation %d" % [
				s.attr(Staff.TACTICAL), s.attr(Staff.MAN_MANAGEMENT),
				s.attr(Staff.YOUTH_DEVELOPMENT)]
		Staff.Role.ASSISTANT_COACH:
			if s == null:
				return "Aucun renfort sur le travail individuel"
			return "Coaching mécanique %d" % s.attr(Staff.MECHANICAL_COACHING)
		Staff.Role.ANALYST:
			if s == null:
				return "Préparation adverse au plancher (6/20)"
			return "Analyse %d" % s.attr(Staff.ANALYSIS)
		Staff.Role.TEAM_MANAGER, Staff.Role.PSYCHOLOGIST:
			if s == null:
				return "Aucun soutien au moral du groupe"
			return "Gestion humaine %d" % s.attr(Staff.MAN_MANAGEMENT)
		Staff.Role.PERFORMANCE_COACH:
			var f := wellness_factor(world, org)
			if s == null:
				return "Récupération %+d %%" % int(round((f - 1.0) * 100.0))
			return "Bien-être %d, récupération %+d %%" % [
				s.attr(Staff.WELLNESS), int(round((f - 1.0) * 100.0))]
		Staff.Role.SCOUT:
			if s == null:
				return "Aucune cellule de recrutement : évaluations très floues"
			return "Jugement %d" % s.attr(Staff.JUDGEMENT)
		Staff.Role.CONTENT_MANAGER:
			return "Activations sponsors : %d par mois" % \
				FinanceSystem.content_capacity(world, org)
		Staff.Role.GENERAL_MANAGER:
			var e := negotiation_edge(world, org)
			return "Commission d'agent %.1f %%, patience des agents %+d %%" % [
				AGENT_FEE_PCT * (1.0 - e * 0.5), int(round(e * 30.0))]
	return ""


## Masse salariale annuelle de l'encadrement.
static func payroll_yearly(world: World, org: Organization) -> int:
	var total := 0
	for sid in org.staff_ids:
		var s := world.staffer(sid)
		if s != null and s.contract != null:
			total += s.contract.salary_yearly
	return total


# ============================================================================
# Passes automatiques
# ============================================================================

## Fin de contrat. Le joueur est prévenu à 60 puis 21 jours : un entraîneur
## qu'on laisse filer sans s'en apercevoir, c'est une saison perdue.
static func daily_tick(world: World) -> void:
	var leaving: Array[Staff] = []
	for sid in world.staff:
		var s: Staff = world.staff[sid]
		if s.contract == null or s.org_id == "":
			continue
		var left := s.contract.days_remaining(world.today)
		if left < 0:
			leaving.append(s)
		elif world.player_org_id == s.org_id and (left == 60 or left == 21):
			world.add_news(world.today, "Contrat : %s" % s.display_name(),
				"Le contrat de %s (%s) expire dans %d jours."
					% [s.display_name(), s.role_label().to_lower(), left],
				"staff", {"staff_id": s.id})
	for s in leaving:
		var was_player := world.player_org_id == s.org_id
		var who := s.display_name()
		var role_label := s.role_label().to_lower()
		detach(world, s)
		if was_player:
			world.add_news(world.today, "Fin de contrat : %s" % who,
				"%s n'est plus %s de la structure. Le poste est vacant."
					% [who, role_label], "staff", {"staff_id": s.id})


static func weekly_tick(world: World) -> void:
	market_upkeep(world)
	for oid in world.orgs:
		var o: Organization = world.orgs[oid]
		if o.is_player_controlled or o.bankrupt:
			continue
		_ai_staffing(world, o)


## Gestion automatique de l'encadrement pour UNE structure, celle du joueur
## comprise. Utilisée par `tools/season.gd`, qui joue un manager passif :
## sans elle l'équipe du joueur finit la saison sans banc, à 8/20 de tactique,
## et tous les chiffres du rapport d'équilibrage sont faussés.
static func auto_manage(world: World, org: Organization) -> void:
	if org == null or org.bankrupt:
		return
	_ai_staffing(world, org)


## Organigramme que la structure peut se payer, et enveloppe par poste.
##
## Un budget commun ne marche pas : mesuré, il produisait des structures à six
## encadrants qui se retrouvaient ensuite SANS entraîneur, parce que les postes
## secondaires avaient mangé la caisse avant que le contrat du coach n'expire.
## Chaque poste reçoit donc sa propre enveloppe, et l'organigramme s'arrête là
## où l'argent s'arrête — un préfixe de ROLE_ORDER, jamais un trou au milieu.
##
## Un poste de BANC compte autant de fois que la maison a de sections : une
## écurie à deux rosters doit budgéter deux entraîneurs avant d'ouvrir un poste
## de recruteur. L'enveloppe renvoyée reste celle d'UNE personne.
##
## Retourne {role: enveloppe annuelle en cents, par personne}.
static func org_chart(world: World, org: Organization) -> Dictionary:
	var budget := float(FinanceSystem.recurring_monthly_income(world, org)) \
		* 12.0 * AI_PAYROLL_SHARE
	var teams := maxi(competitive_rosters(world, org).size(), 1)
	# 1. Combien de postes ouvrir : au prix d'un titulaire correct.
	var rates := {}
	var counts := {}
	var spent := 0.0
	for role in ROLE_ORDER:
		var heads := teams if TEAM_ROLES.has(role) else 1
		var going_rate := float(StaffFactory.salary_for(role, 10.5)) * float(heads)
		if spent + going_rate > budget and not rates.is_empty():
			break
		rates[role] = going_rate
		counts[role] = heads
		spent += going_rate

	# Une équipe engagée a toujours un entraîneur au budget, même fauchée :
	# sans lui elle joue avec 8/20 de tactique, ce qui la condamne.
	if rates.is_empty():
		return {Staff.Role.HEAD_COACH:
			StaffFactory.salary_for(Staff.Role.HEAD_COACH, 8.0)}

	# 2. Répartir le budget RÉEL sur ces postes, au prorata de leur prix.
	#    Cette étape a été ajoutée après mesure : sans elle, l'enveloppe ne
	#    dépendait que du poste et pas des moyens, et une écurie VCT à 5,45 M$
	#    de recettes n'offrait que 28 500 $ à un entraîneur — donc n'en
	#    trouvait aucun, et jouait trois saisons sans banc.
	var out := {}
	for role in rates:
		var total: float = maxf(budget * float(rates[role]) / spent,
			float(rates[role]))
		out[role] = int(total / float(counts[role]))
	return out


## L'IA gère son encadrement comme le reste : elle prolonge ce qu'elle peut
## payer, comble ses trous par ordre d'utilité, et laisse filer ceux dont le
## poste n'est plus dans son organigramme.
static func _ai_staffing(world: World, o: Organization) -> void:
	var rng := world.rng.derive("aistaff:%s:%d" % [o.id, world.today])
	var chart := org_chart(world, o)

	# 1. Prolonger ceux qui arrivent au bout, dans la limite de leur enveloppe.
	for sid in o.staff_ids.duplicate():
		var s := world.staffer(sid)
		if s == null or s.contract == null:
			continue
		var left := s.contract.days_remaining(world.today)
		if left < 0 or left > 75:
			continue
		if not chart.has(int(s.role)):
			continue   # poste supprimé : on ne prolonge pas
		var demand := salary_demand(world, s, o)
		if demand > int(chart[int(s.role)]):
			continue   # devenu trop cher pour la maison
		if rng.chance(0.55):
			renew(world, o, s, demand, rng.range_i(12, 30))

	var teams := competitive_rosters(world, o)

	# 2. Un banc vide est une urgence, pas une ligne de plus sur la liste :
	#    sans entraîneur l'équipe joue à 8/20 de tactique. On ne passe donc
	#    pas par le tirage hebdomadaire pour ce poste-là — et on le fait pour
	#    CHAQUE section, pas seulement pour la vitrine.
	if chart.has(Staff.Role.HEAD_COACH):
		for r in teams:
			if holder(world, o, Staff.Role.HEAD_COACH, r.id) != null:
				continue
			if not _fill_role(world, o, Staff.Role.HEAD_COACH, chart, rng, r.id):
				# Personne dans l'enveloppe : on prend le moins cher du marché.
				# Un banc vide coûte plus qu'un mauvais entraîneur, et il y a
				# toujours quelqu'un à ce prix-là.
				_fill_role(world, o, Staff.Role.HEAD_COACH,
					{Staff.Role.HEAD_COACH: _cheapest_demand(world, o,
						Staff.Role.HEAD_COACH)}, rng, r.id)
			return

	# 3. Combler un autre poste vacant, un seul par semaine : une structure ne
	#    recrute pas cinq encadrants le même lundi.
	if not rng.chance(0.35):
		return
	for role in ROLE_ORDER:
		if not chart.has(role):
			continue
		if TEAM_ROLES.has(role):
			for r in teams:
				if holder(world, o, role, r.id) == null:
					_fill_role(world, o, role, chart, rng, r.id)
					return
		elif holder(world, o, role) == null:
			_fill_role(world, o, role, chart, rng)
			return


## Prétention la plus basse du marché à ce poste. Sert de plancher : il existe
## toujours un encadrant qu'on peut s'offrir, même mauvais.
static func _cheapest_demand(world: World, o: Organization, role: int) -> int:
	var lowest := 0
	for s in free_agents(world, role):
		var d := salary_demand(world, s, o)
		if lowest == 0 or d < lowest:
			lowest = d
	return lowest


## Nombre de candidats sollicités en une fois. Un seul ne suffit pas : s'il
## décline, le refus le met en quarantaine trois semaines et la structure
## retombait sur lui au tour suivant — mesuré, ça bloquait durablement le banc
## de quelques structures. Plus de trois d'affilée brûlerait le marché.
const AI_CALLS_PER_TICK := 3


## Embauche le meilleur candidat qui tienne dans l'enveloppe du poste. Pour un
## poste de banc, `roster_id` dit QUELLE équipe il prend.
static func _fill_role(world: World, o: Organization, role: int,
		chart: Dictionary, rng: Rng, roster_id: String = "") -> bool:
	var envelope := int(chart.get(role, 0))
	var game_id := ""
	var r := world.roster(roster_id)
	if r != null and TEAM_ROLES.has(role):
		game_id = r.game_id
	var pool := free_agents(world, role, o.region, game_id)
	if pool.is_empty():
		pool = free_agents(world, role, "", game_id)
	if pool.is_empty():
		pool = free_agents(world, role)
	# `free_agents` trie du meilleur au moins bon : on descend la liste jusqu'à
	# ce que quelqu'un dise oui.
	var called := 0
	for s in pool:
		if called >= AI_CALLS_PER_TICK:
			break
		if salary_demand(world, s, o) > envelope or is_cooling_off(world, s, o):
			continue
		called += 1
		if bool(hire(world, o, s, salary_demand(world, s, o),
				rng.range_i(12, 30), roster_id)["ok"]):
			return true
	return false
