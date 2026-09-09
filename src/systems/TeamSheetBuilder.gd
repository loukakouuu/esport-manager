class_name TeamSheetBuilder
extends RefCounted

## Transforme un Roster du World en TeamSheet prête à simuler.
##
## C'est ici que sont appliquées les règles « de vestiaire » : joueur blessé
## remplacé automatiquement, cinq incomplet complété par le banc, poste vacant
## comblé par le joueur le plus polyvalent. Le simulateur, lui, reçoit toujours
## une feuille valide.

static func build(world: World, roster_id: String, opponent_id: String = "") -> TeamSheet:
	var r := world.roster(roster_id)
	if r == null:
		return null
	var module := world.module_for(r.game_id)
	var sheet := TeamSheet.new()
	sheet.roster = r
	sheet.org = world.org(r.org_id)
	sheet.tactic = r.tactic if not r.tactic.is_empty() else module.default_tactic()
	sheet.chemistry = r.chemistry
	sheet.reputation = sheet.org.reputation if sheet.org != null else 1000

	sheet.lineup = _pick_lineup(world, r, module)
	for p in world.players_of(roster_id):
		if not sheet.lineup.has(p):
			sheet.bench.append(p)

	sheet.coach = world.staffer(r.head_coach_id)
	for sid in r.staff_ids:
		var s := world.staffer(sid)
		if s != null and s.role == Staff.Role.ANALYST:
			sheet.analyst = s
			break
	sheet.prep_level = _prep_level(sheet)
	return sheet


## Sélection du cinq : titulaires valides d'abord, puis les meilleurs
## remplaçants au poste manquant.
static func _pick_lineup(world: World, r: Roster, module: GameModule) -> Array[Player]:
	var size := module.team_size()
	var chosen: Array[Player] = []
	var available: Array[Player] = []
	for p in world.players_of(r.id):
		if p.is_available(world.today):
			available.append(p)

	for pid in r.starters:
		var p := world.player(pid)
		if p != null and available.has(p) and chosen.size() < size:
			chosen.append(p)

	if chosen.size() < size:
		# Il manque du monde : on comble en priorisant les postes non couverts.
		var covered := {}
		for p in chosen:
			covered[p.primary_role] = true
		var rest: Array[Player] = []
		for p in available:
			if not chosen.has(p):
				rest.append(p)
		rest.sort_custom(func(a, b):
			var a_new := 0 if covered.has(a.primary_role) else 1
			var b_new := 0 if covered.has(b.primary_role) else 1
			if a_new != b_new:
				return a_new > b_new
			return a.current_ability > b.current_ability)
		for p in rest:
			if chosen.size() >= size:
				break
			chosen.append(p)
			covered[p.primary_role] = true
	return chosen


## Qualité de préparation adverse (0..1) : analyste + part de la semaine
## consacrée à l'anti-strat. C'est le levier tactique invisible mais décisif.
static func _prep_level(sheet: TeamSheet) -> float:
	var analyst_q := 0.35
	if sheet.analyst != null:
		analyst_q = clampf(float(sheet.analyst.attr(Staff.ANALYSIS)) / 20.0, 0.0, 1.0)
	var coach_q := 0.35
	if sheet.coach != null:
		coach_q = clampf(float(sheet.coach.attr(Staff.TACTICAL)) / 20.0, 0.0, 1.0)
	var focus := clampf(float(sheet.tactic.get("anti_strat", 50)) / 100.0, 0.0, 1.0)
	return clampf(0.20 + (analyst_q * 0.45 + coach_q * 0.35) * (0.55 + 0.45 * focus),
		0.0, 1.0)
