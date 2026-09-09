extends Node

## Façade unique entre l'interface et le moteur.
##
## Règle stricte du projet : aucun écran n'appelle un système directement.
## L'UI passe toujours par Game, qui exécute puis émet un signal. On peut donc
## rejouer, tester ou scripter n'importe quelle action sans interface, et
## l'ajout d'un écran ne peut pas casser la simulation.

signal world_loaded
signal day_advanced(report: Dictionary)
signal state_changed          # à émettre après toute action modifiant le monde
signal player_match_played(result: MatchResult, fixture: Fixture)

var world: World = null
var last_player_result: MatchResult = null
var last_player_fixture: Fixture = null
var busy := false


func has_world() -> bool:
	return world != null


func new_world(seed_value: int, start_day: int = -1) -> World:
	var start := start_day if start_day > 0 else GameDate.from_ymd(2026, 1, 5)
	world = WorldGenerator.generate(seed_value, start)
	world_loaded.emit()
	return world


func choose_org(org_id: String) -> void:
	WorldGenerator.assign_player_org(world, org_id)
	state_changed.emit()


func my_org() -> Organization:
	return world.my_org() if world != null else null


func my_roster() -> Roster:
	if world == null or world.player_org_id == "":
		return null
	return world.main_roster(world.player_org_id, world.player_game_id)


# ============================================================================
# Avance du temps
# ============================================================================

func advance_day() -> Dictionary:
	if world == null or busy:
		return {}
	busy = true
	var rep := GameSim.advance_day(world)
	_capture_player_match(rep)
	busy = false
	day_advanced.emit(rep)
	state_changed.emit()
	return rep


func advance_days(count: int) -> void:
	if world == null or busy:
		return
	busy = true
	var reports := GameSim.advance_days(world, count, true)
	if not reports.is_empty():
		_capture_player_match(reports[reports.size() - 1])
	busy = false
	if not reports.is_empty():
		day_advanced.emit(reports[reports.size() - 1])
	state_changed.emit()


func advance_to_next_match() -> void:
	if world == null or busy:
		return
	busy = true
	var reports := GameSim.advance_to_next_player_match(world)
	if not reports.is_empty():
		_capture_player_match(reports[reports.size() - 1])
	busy = false
	state_changed.emit()


func _capture_player_match(report: Dictionary) -> void:
	for res_v in report.get("results", []):
		var res: MatchResult = res_v
		for rid in [res.home_id, res.away_id]:
			var r := world.roster(rid)
			if r != null and r.org_id == world.player_org_id:
				last_player_result = res
				last_player_fixture = world.fixture(res.fixture_id)
				player_match_played.emit(res, last_player_fixture)
				return


# ============================================================================
# Actions du joueur
# ============================================================================

func set_starters(player_ids: Array[String]) -> void:
	var r := my_roster()
	if r == null:
		return
	r.starters = player_ids.duplicate()
	state_changed.emit()


func set_tactic(key: String, value) -> void:
	var r := my_roster()
	if r == null:
		return
	r.tactic[key] = value
	state_changed.emit()


func set_budget(key: String, cents: int) -> void:
	var o := my_org()
	if o == null:
		return
	o.budgets[key] = maxi(cents, 0)
	state_changed.emit()


func upgrade_facility(kind: int) -> bool:
	var o := my_org()
	if o == null:
		return false
	var lvl := o.facility_level(kind)
	if lvl >= Facilities.MAX_LEVEL:
		return false
	var cost := Facilities.upgrade_cost(kind, lvl + 1)
	if o.ledger.cash < cost:
		return false
	o.ledger.debit(world.today, cost, Transaction.Category.FACILITY,
		"Investissement — %s niveau %d" % [Facilities.label(kind), lvl + 1], "")
	o.facilities[kind] = lvl + 1
	state_changed.emit()
	return true


func sponsor_offers() -> Array:
	var o := my_org()
	return SponsorSystem.offers_for(world, o, 5) if o != null else []


func sign_sponsor(offer: Dictionary) -> void:
	var o := my_org()
	if o == null:
		return
	SponsorSystem.sign_deal(world, o, offer)
	state_changed.emit()


func take_loan(principal: int, months: int) -> void:
	var o := my_org()
	if o == null:
		return
	FinanceSystem.take_loan(world, o, principal, months)
	state_changed.emit()


func offer_contract(player_id: String, salary: int, months: int,
		squad_role: int) -> bool:
	var o := my_org()
	var p := world.player(player_id)
	if o == null or p == null:
		return false
	var chance := ContractSystem.acceptance_chance(world, p, o, salary,
		squad_role as Contract.SquadRole)
	var accepted := world.rng.derive("offer:%s:%d" % [p.id, world.today]).chance(chance)
	if not accepted:
		return false
	var c := ContractSystem.make_offer(world, o, p, salary, months,
		squad_role as Contract.SquadRole)
	if p.is_free_agent():
		ContractSystem.sign_contract(world, o, p, c)
	else:
		if not ContractSystem.buyout(world, o, p, c):
			return false
	state_changed.emit()
	return true


func release_player(player_id: String) -> void:
	var o := my_org()
	var p := world.player(player_id)
	if o == null or p == null:
		return
	ContractSystem.terminate(world, o, p)
	state_changed.emit()


func mark_news_read(news_id: String) -> void:
	for n in world.inbox:
		if str((n as Dictionary)["id"]) == news_id:
			(n as Dictionary)["read"] = true
	state_changed.emit()


func unread_count() -> int:
	var n := 0
	for item in world.inbox:
		if not bool((item as Dictionary).get("read", false)):
			n += 1
	return n


# ============================================================================
# Sauvegarde
# ============================================================================

func save_game(slot: String) -> bool:
	return SaveGame.save(world, slot)


func load_game(slot: String) -> bool:
	var w := SaveGame.load_slot(slot)
	if w == null:
		return false
	world = w
	world_loaded.emit()
	state_changed.emit()
	return true
