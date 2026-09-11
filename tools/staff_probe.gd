extends SceneTree

## Sonde d'équilibrage de l'encadrement.
##
##   godot --headless --path . --script res://tools/staff_probe.gd
##
## Les tests disent que le marché du staff est CORRECT. Ils ne disent pas s'il
## tient sur la durée : c'est justement ce qui manquait avant cette version, et
## le monde y perdait tout son encadrement en trois saisons sans que rien ne
## le signale.
##
## Trois invariants, mesurés sur trois saisons simulées :
##
##   1. COACHS FANTÔMES = 0. Un roster ne doit jamais rester branché sur un
##      encadrant qu'il ne paie plus. C'était le bug d'origine : la structure
##      cessait de verser le salaire mais gardait l'apport tactique, soit un
##      coaching gratuit à vie pour les 136 structures du monde.
##   2. L'encadrement ne s'effondre pas. Avant : 338 personnes le premier jour,
##      ZÉRO au bout de trois ans.
##   3. Les structures SOLVABLES gardent un entraîneur. Pas « toutes, tout le
##      temps » : entre le départ d'un coach et la signature du suivant il se
##      passe une semaine ou deux, et une poignée de bancs vides à un instant
##      donné est normale. Au-delà de 3 %, c'est que l'IA ne recrute plus.
##      Les structures en faillite, elles, n'embauchent pas du tout — le
##      circuit ouvert se ruine, ce qui est un problème financier distinct
##      de celui-ci (voir docs/ROADMAP.md).

const SEASONS := 3
const SEED := 4242

## Part des structures solvables tolérée sans entraîneur, délai de recrutement
## oblige. Mesuré à 1 sur 136 en fin de sonde.
const VACANCY_TOLERANCE := 0.03


func _initialize() -> void:
	var world := WorldGenerator.generate(SEED, GameDate.from_ymd(2026, 1, 1))
	print("")
	print("==============================================")
	print("  Encadrement — tenue sur %d saisons" % SEASONS)
	print("==============================================")
	_line(world, "depart")
	for i in SEASONS:
		GameSim.advance_days(world, 365, false)
		_line(world, "an %d" % (i + 1))

	var m := _measure(world)
	var problems: Array[String] = []
	if int(m["ghosts"]) > 0:
		problems.append("%d coach(s) fantome(s) : un roster garde un encadrant "
			% int(m["ghosts"]) + "qu'il ne paie plus")
	if float(m["per_org"]) < 1.0:
		problems.append("l'encadrement s'effondre (%.2f par structure)"
			% float(m["per_org"]))
	var allowed := maxi(3, int(float(m["orgs"]) * VACANCY_TOLERANCE))
	if int(m["solvent_vacant"]) > allowed:
		problems.append("%d structure(s) solvable(s) sans entraineur (max %d)"
			% [int(m["solvent_vacant"]), allowed])
	if float(m["coach_level"]) < 9.0:
		problems.append("le niveau moyen des entraineurs s'effrite (%.1f)"
			% float(m["coach_level"]))

	print("----------------------------------------------")
	if problems.is_empty():
		print("  Aucune derive detectee.")
	else:
		for p in problems:
			print("  [ALERTE] %s" % p)
	print("==============================================")
	print("")
	quit(1 if not problems.is_empty() else 0)


func _line(world: World, when: String) -> void:
	var m := _measure(world)
	print("  %-7s %4d encadrants (%.2f/org) | %3d libres | note %.1f | "
		% [when, int(m["total"]), float(m["per_org"]), int(m["free"]),
			float(m["level"])]
		+ "entraineurs : note %.1f, %d poste(s) vacant(s) dont %d solvable(s)"
			% [float(m["coach_level"]), int(m["vacant"]),
				int(m["solvent_vacant"])]
		+ " | fantomes %d" % int(m["ghosts"]))


func _measure(world: World) -> Dictionary:
	var orgs := 0
	var total := 0
	var ghosts := 0
	var vacant := 0
	var solvent_vacant := 0
	var free := 0
	var level := 0.0
	var n := 0
	var coach_level := 0.0
	var coaches := 0

	for sid in world.staff:
		if (world.staff[sid] as Staff).org_id == "":
			free += 1

	for oid in world.orgs:
		var o: Organization = world.orgs[oid]
		orgs += 1
		total += o.staff_ids.size()
		for sid in o.staff_ids:
			var s := world.staffer(sid)
			if s != null:
				level += s.overall()
				n += 1
		for r in world.rosters_of(o.id):
			var c := world.staffer(r.head_coach_id)
			if c == null:
				continue
			# Branché sur le roster mais plus salarié : c'est un fantôme.
			if c.contract == null or c.org_id != o.id:
				ghosts += 1
		var coach := StaffSystem.holder(world, o, Staff.Role.HEAD_COACH)
		if coach == null:
			vacant += 1
			if not o.bankrupt:
				solvent_vacant += 1
		else:
			coach_level += coach.overall()
			coaches += 1

	return {
		"orgs": orgs,
		"total": total,
		"per_org": float(total) / maxf(float(orgs), 1.0),
		"free": free,
		"level": level / maxf(float(n), 1.0),
		"coach_level": coach_level / maxf(float(coaches), 1.0),
		"vacant": vacant,
		"solvent_vacant": solvent_vacant,
		"ghosts": ghosts,
	}
