class_name TestFactory
extends RefCounted

## Fabriques d'objets prêts à simuler, utilisées uniquement par les tests et
## les outils d'équilibrage.

const TODAY := 20_454   # 2026-01-01 approx, recalculé proprement ci-dessous


static func today() -> int:
	return GameDate.from_ymd(2026, 1, 1)


## Crée un cinq complet de niveau `target_ca` avec une composition valide.
static func make_lineup(rng: Rng, module: GameModule, ids: Ids,
		target_ca: int, region: String = "EMEA") -> Array[Player]:
	var roles: Array[String] = [
		ValorantModule.DUELIST, ValorantModule.INITIATOR, ValorantModule.INITIATOR,
		ValorantModule.CONTROLLER, ValorantModule.SENTINEL,
	]
	var out: Array[Player] = []
	for i in roles.size():
		var ca := clampi(target_ca + rng.gauss_i(0.0, 8.0, -20, 20), 20, 195)
		var p := PlayerFactory.create(rng, module, ids, today(), {
			"target_ca": ca, "role": roles[i], "region": region,
			"igl": i == 1,
		})
		out.append(p)
	return out


static func make_sheet(rng: Rng, module: GameModule, ids: Ids, name: String,
		tag: String, target_ca: int, coach_overall: float = 12.0) -> TeamSheet:
	var org := Organization.new()
	org.id = ids.next(Ids.ORG)
	org.name = name
	org.tag = tag
	org.ledger = Ledger.new()

	var roster := Roster.new()
	roster.id = ids.next(Ids.ROSTER)
	roster.org_id = org.id
	roster.name = name
	roster.tactic = module.default_tactic()

	var sheet := TeamSheet.new()
	sheet.org = org
	sheet.roster = roster
	sheet.lineup = make_lineup(rng, module, ids, target_ca)
	for p in sheet.lineup:
		roster.add_player(p.id)
		roster.starters.append(p.id)
	sheet.coach = StaffFactory.create(rng, ids, today(), Staff.Role.HEAD_COACH,
		{"target_overall": coach_overall})
	sheet.analyst = StaffFactory.create(rng, ids, today(), Staff.Role.ANALYST,
		{"target_overall": coach_overall - 1.0})
	sheet.tactic = roster.tactic
	sheet.chemistry = 55.0
	sheet.reputation = 3000
	return sheet


static func make_context(rng: Rng, module: GameModule,
		home: TeamSheet, away: TeamSheet, best_of: int = 3,
		detailed: bool = false) -> MatchContext:
	var ctx := MatchContext.new()
	ctx.home = home
	ctx.away = away
	ctx.best_of = best_of
	ctx.rng = rng
	ctx.day = today()
	ctx.detailed = detailed
	ctx.map_pool = (module as ValorantModule).active_map_pool()
	return ctx
