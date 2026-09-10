class_name TrainingSystem
extends RefCounted

## La semaine d'entraînement : programme collectif, travail individuel,
## cohésion et bootcamps.
##
## Deux niveaux, comme dans Football Manager :
##
##  - le PROGRAMME COLLECTIF répartit dix créneaux hebdomadaires entre cinq
##    natures de travail. C'est un arbitrage, jamais un optimum : tout ce qui
##    part en scrims ne part pas en récupération, et une équipe qui scrimme
##    six jours sur sept gagne en netteté ce qu'elle perd en fraîcheur.
##  - le TRAVAIL INDIVIDUEL oriente la progression d'un joueur vers un domaine
##    précis, et règle son intensité (ménager un joueur usé, charger un jeune).
##
## La cohésion (chemistry) reste la variable la plus sous-estimée : cinq très
## bons joueurs réunis la semaine dernière valent moins qu'un cinq moyen qui
## joue ensemble depuis un an. Elle monte lentement, chute brutalement à chaque
## changement de roster — comme les « superteams » qui mettent six mois à
## fonctionner.

const CHEMISTRY_GAIN_BASE := 1.15
const CHEMISTRY_LOSS_PER_CHANGE := 14.0

## Nombre de créneaux à répartir chaque semaine.
const UNITS_PER_WEEK := 10

# --- Natures de travail ------------------------------------------------------
const SCRIM := "scrim"
const AIM := "aim"
const THEORY := "theory"
const PHYSICAL := "physical"
const REST := "rest"

const UNITS: Array[String] = [SCRIM, AIM, THEORY, PHYSICAL, REST]

const UNIT_LABELS := {
	SCRIM: "Scrims",
	AIM: "Mécanique",
	THEORY: "Théorie / VOD",
	PHYSICAL: "Préparation physique",
	REST: "Repos",
}

const UNIT_HINTS := {
	SCRIM: "Matchs d'entraînement : netteté, cohésion, lecture. Fatigant.",
	AIM: "Aim labs et deathmatch : visée, déplacement, duel. Très fatigant.",
	THEORY: "Revue vidéo et préparation : lecture de jeu, adaptation, éco.",
	PHYSICAL: "Sommeil, sport, ergonomie : endurance, moins de blessures.",
	REST: "Journée off : fatigue et usure mentale reculent, le moral remonte.",
}

## Programme par défaut : équilibré, tenable sur une saison entière.
const DEFAULT_PLAN := {
	SCRIM: 4, AIM: 2, THEORY: 2, PHYSICAL: 1, REST: 1,
}

## Domaine d'attributs travaillé par chaque nature de séance. Sert à orienter
## la progression dans ProgressionSystem.
const FOCUS_GROUPS := {
	AIM: ["aim", "crosshair", "spray", "movement", "duelling", "reaction"],
	THEORY: ["game_sense", "map_knowledge", "mid_round", "economy",
		"positioning", "utility", "decision_making", "adaptability"],
	SCRIM: ["entry", "anchoring", "trading", "clutch", "communication",
		"teamwork", "concentration"],
	PHYSICAL: ["stamina", "reaction", "concentration"],
	REST: [],
}


static func unit_label(key: String) -> String:
	return UNIT_LABELS.get(key, key)


static func unit_hint(key: String) -> String:
	return UNIT_HINTS.get(key, "")


## Programme effectif d'un roster, normalisé à UNITS_PER_WEEK créneaux.
static func plan_of(r: Roster) -> Dictionary:
	var plan := {}
	var total := 0
	for k in UNITS:
		var v := int(r.training.get(k, DEFAULT_PLAN.get(k, 0)))
		plan[k] = maxi(v, 0)
		total += plan[k]
	if total == 0:
		return DEFAULT_PLAN.duplicate()
	return plan


static func plan_total(plan: Dictionary) -> int:
	var t := 0
	for k in UNITS:
		t += int(plan.get(k, 0))
	return t


## Intensité globale de la semaine (0.5 = semaine de décharge, 1.5 = bourrin).
static func plan_load(plan: Dictionary) -> float:
	var total := maxf(float(plan_total(plan)), 1.0)
	# Les scrims et la mécanique coûtent cher, le repos rend.
	var load := float(plan.get(SCRIM, 0)) * 1.15 \
		+ float(plan.get(AIM, 0)) * 1.30 \
		+ float(plan.get(THEORY, 0)) * 0.55 \
		+ float(plan.get(PHYSICAL, 0)) * 0.45 \
		+ float(plan.get(REST, 0)) * -0.85
	return clampf(load / total * float(UNITS_PER_WEEK) / 8.0, 0.25, 1.75)


static func plan_summary(plan: Dictionary) -> String:
	var load := plan_load(plan)
	if load >= 1.35:
		return "Charge très lourde — tenable quelques semaines, pas une saison."
	if load >= 1.1:
		return "Charge soutenue — progression rapide, fatigue à surveiller."
	if load >= 0.8:
		return "Charge équilibrée."
	if load >= 0.55:
		return "Charge légère — bonne récupération, progression ralentie."
	return "Semaine de décharge — on récupère, on ne progresse plus."


# ============================================================================
# Passe hebdomadaire
# ============================================================================

static func weekly_tick(world: World) -> void:
	for rid in world.rosters:
		var r: Roster = world.rosters[rid]
		var plan := plan_of(r)
		_apply_plan(world, r, plan)
		_update_chemistry(world, r, plan)
		_apply_bootcamp(world, r)


## Effets immédiats du programme : netteté, fatigue, usure, moral.
## La progression d'attributs, elle, est traitée par ProgressionSystem, qui
## lit le programme via `focus_weights()`.
static func _apply_plan(world: World, r: Roster, plan: Dictionary) -> void:
	var total := maxf(float(plan_total(plan)), 1.0)
	var scrim := float(plan.get(SCRIM, 0)) / total
	var aim := float(plan.get(AIM, 0)) / total
	var physical := float(plan.get(PHYSICAL, 0)) / total
	var rest := float(plan.get(REST, 0)) / total
	var o := world.org(r.org_id)
	var wellness := o.facility_effect(Facilities.Kind.WELLNESS) if o != null else 1.0

	for p_v in world.players_of(r.id):
		var p: Player = p_v
		if p.retired:
			continue
		var intensity := clampf(p.training_intensity, 0.5, 1.5)
		# Un joueur blessé ne s'entraîne pas : il récupère.
		if p.is_injured(world.today):
			p.fatigue = clampf(p.fatigue - 8.0, 0.0, 100.0)
			continue

		# Les scrims maintiennent le rythme compétitif ; rien d'autre ne le fait.
		p.sharpness = clampf(p.sharpness + scrim * 9.0 * intensity, 0.0, 100.0)
		var stress := (scrim * 5.0 + aim * 6.5) * intensity \
			* (1.35 - float(p.attr(Attributes.STAMINA)) / 20.0)
		var relief := (rest * 9.0 + physical * 5.0) * wellness
		p.fatigue = clampf(p.fatigue + stress - relief, 0.0, 100.0)

		# L'usure mentale ne recule qu'avec du vrai repos, jamais avec de la
		# préparation physique : c'est la leçon des saisons esport à rallonge.
		#
		# Étalonnage (par saison de 52 semaines, matchs compris) :
		#   programme par défaut ............... ~35 d'usure — gérable
		#   scrims à fond, zéro repos .......... ~75 — épuisement garanti
		#   deux créneaux de repos par semaine .. reste sous 15
		# Le repos est donc le SEUL levier de récupération, et il coûte de la
		# progression : c'est tout l'arbitrage de l'écran d'entraînement.
		var resist := 1.0 + float(p.attr(Attributes.BURNOUT_RESISTANCE)) / 20.0
		p.burnout = clampf(p.burnout
			+ (scrim + aim) * 2.2 * intensity / resist
			- rest * 3.2 * resist * wellness, 0.0, 100.0)
		p.morale = clampf(p.morale + rest * 1.2 - aim * 0.4, 0.0, 100.0)
		# Le physique fait progresser l'endurance à petit feu.
		if physical > 0.15 and world.rng.derive("phys:%s:%d"
				% [p.id, world.today]).chance(physical * 0.10):
			p.set_attr(Attributes.STAMINA, p.attr(Attributes.STAMINA) + 1)


## Poids de chaque attribut dans la progression de la semaine, dérivés du
## programme collectif et du travail individuel du joueur.
##
## C'est le pont entre « ce que le manager a décidé » et « ce qui progresse
## vraiment ». Sans lui, régler l'entraînement serait décoratif.
static func focus_weights(r: Roster, p: Player) -> Dictionary:
	var plan := plan_of(r)
	var total := maxf(float(plan_total(plan)), 1.0)
	var out := {}
	for unit in UNITS:
		var share := float(plan.get(unit, 0)) / total
		if share <= 0.0:
			continue
		for key in FOCUS_GROUPS.get(unit, []):
			out[key] = float(out.get(key, 0.0)) + share * 2.4
	# Le travail individuel pèse lourd : c'est tout l'intérêt de le régler.
	if p.training_focus != "":
		out[p.training_focus] = float(out.get(p.training_focus, 0.0)) + 3.2
	return out


## Multiplicateur de progression lié à l'entraînement (0.25 .. 1.50).
##
## Seul le travail TECHNIQUE fait progresser : la préparation physique entretient
## le corps et le repos répare la tête, mais ni l'un ni l'autre n'apprend à
## viser. Étalonnage sur les programmes types :
##   tout scrims ....... 1.50 — mais l'usure mentale ronge ensuite le gain
##   par défaut ........ 1.32
##   ménagé ............ 1.03
##   décharge totale ... 0.52
## Le piège est volontaire : charger à fond ne rapporte presque rien de plus
## que le programme équilibré, parce que le burnout annule la différence.
static func growth_multiplier(r: Roster, p: Player) -> float:
	var plan := plan_of(r)
	var total := maxf(float(plan_total(plan)), 1.0)
	var technical := (float(plan.get(AIM, 0)) * 1.25
		+ float(plan.get(THEORY, 0)) * 1.00
		+ float(plan.get(SCRIM, 0)) * 0.85) / total
	return clampf(0.25 + technical * 1.35, 0.25, 1.50) \
		* clampf(p.training_intensity, 0.5, 1.5)


# ============================================================================
# Cohésion
# ============================================================================

static func _update_chemistry(world: World, r: Roster, plan: Dictionary) -> void:
	var o := world.org(r.org_id)
	var lineup := r.starters
	var signature := ",".join(lineup)
	var previous := str(r.tactic.get("_lineup_signature", signature))

	if previous != signature:
		# Changement de cinq : la cohésion en prend un coup, proportionnel au
		# nombre de joueurs remplacés.
		var before := previous.split(",")
		var changes := 0
		for pid in lineup:
			if not before.has(pid):
				changes += 1
		r.chemistry = clampf(r.chemistry
			- CHEMISTRY_LOSS_PER_CHANGE * float(changes), 5.0, 100.0)
		r.tactic["_lineup_signature"] = signature
		return

	var gain := CHEMISTRY_GAIN_BASE
	# Seuls les scrims et la théorie construisent une équipe. On peut avoir
	# cinq machines qui ne se sont jamais parlé.
	var total := maxf(float(plan_total(plan)), 1.0)
	var together := (float(plan.get(SCRIM, 0)) * 1.0
		+ float(plan.get(THEORY, 0)) * 0.7) / total
	gain *= clampf(0.25 + together * 1.9, 0.15, 1.6)

	if o != null:
		gain *= o.facility_effect(Facilities.Kind.TRAINING_ROOM)
		var coach := world.staffer(r.head_coach_id)
		if coach != null:
			gain *= 0.6 + float(coach.attr(Staff.MAN_MANAGEMENT)) / 25.0
	# L'ambiance du vestiaire décide de ce qu'on tire du travail commun.
	gain *= DynamicsSystem.chemistry_modifier(world, r)
	# La cohésion sature : au-delà de 85, il faut du temps et des résultats.
	gain *= clampf((100.0 - r.chemistry) / 45.0, 0.12, 1.0)
	r.chemistry = clampf(r.chemistry + gain, 0.0, 100.0)


## Un bootcamp financé accélère la cohésion et la netteté, au prix de la
## fatigue. C'est un pari de court terme avant une échéance importante.
static func _apply_bootcamp(world: World, r: Roster) -> void:
	var o := world.org(r.org_id)
	if o == null or int(o.budgets.get("bootcamp", 0)) <= 0:
		return
	var intensity := clampf(float(o.budgets["bootcamp"])
		/ float(Money.from_units(25_000.0)), 0.0, 1.5)
	r.chemistry = clampf(r.chemistry + 1.6 * intensity, 0.0, 100.0)
	for p in world.players_of(r.id):
		p.sharpness = clampf(p.sharpness + 5.0 * intensity, 0.0, 100.0)
		p.fatigue = clampf(p.fatigue + 4.5 * intensity, 0.0, 100.0)
