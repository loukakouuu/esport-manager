class_name TrainingSystem
extends RefCounted

## Semaine d'entraînement : cohésion, netteté compétitive, bootcamps.
##
## La cohésion (chemistry) est la variable la plus sous-estimée du jeu réel :
## cinq très bons joueurs réunis la semaine dernière valent moins qu'un cinq
## moyen qui joue ensemble depuis un an. Elle monte lentement, elle chute
## brutalement à chaque changement de roster — exactement comme dans la vraie
## vie où les « superteams » mettent six mois à fonctionner.

const CHEMISTRY_GAIN_BASE := 1.15
const CHEMISTRY_LOSS_PER_CHANGE := 14.0


static func weekly_tick(world: World) -> void:
	for rid in world.rosters:
		var r: Roster = world.rosters[rid]
		_update_chemistry(world, r)
		_apply_bootcamp(world, r)


static func _update_chemistry(world: World, r: Roster) -> void:
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
	if o != null:
		gain *= o.facility_effect(Facilities.Kind.TRAINING_ROOM)
		var coach := world.staffer(r.head_coach_id)
		if coach != null:
			gain *= 0.6 + float(coach.attr(Staff.MAN_MANAGEMENT)) / 25.0
	# Un vestiaire au moral bas ne construit pas de cohésion.
	var morale := 0.0
	var n := 0
	for p in world.players_of(r.id):
		if lineup.has(p.id):
			morale += p.morale
			n += 1
	morale = morale / maxf(float(n), 1.0)
	gain *= clampf(0.4 + morale / 90.0, 0.2, 1.5)
	# La cohésion sature : au-delà de 85, il faut du temps et des résultats.
	var ceiling := 100.0
	gain *= clampf((ceiling - r.chemistry) / 45.0, 0.12, 1.0)
	r.chemistry = clampf(r.chemistry + gain, 0.0, ceiling)


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
