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


func _ready() -> void:
	# Le pack livré « vraies équipes » est l'expérience par défaut ; l'univers
	# fictif reste sélectionnable à l'écran de démarrage.
	DataPack.boot()


func has_world() -> bool:
	return world != null


func new_world(seed_value: int, start_day: int = -1) -> World:
	var start := start_day if start_day > 0 else GameDate.from_ymd(2026, 1, 5)
	world = WorldGenerator.generate(seed_value, start)
	world_loaded.emit()
	return world


## Revenir à l'écran de démarrage en jetant le monde généré. Utilisé quand on
## veut changer d'univers avant d'avoir choisi une structure : le monde n'a
## alors aucune valeur, rien n'est perdu.
func abandon_world() -> void:
	world = null
	last_player_result = null
	last_player_fixture = null
	state_changed.emit()


## Fonder une structure de zéro plutôt que d'en reprendre une.
##
## Le monde doit déjà exister (les concurrents et le calendrier sont générés en
## amont) : on n'y ajoute que la structure du joueur. Voir
## WorldGenerator.found_org pour ce qui est volontairement absent — effectif,
## sponsors, place garantie.
func found_org(config: Dictionary) -> bool:
	if world == null:
		return false
	var org := WorldGenerator.found_org(world, config)
	if org == null:
		return false
	state_changed.emit()
	return true


func choose_org(org_id: String) -> void:
	WorldGenerator.assign_player_org(world, org_id)
	state_changed.emit()


func my_org() -> Organization:
	return world.my_org() if world != null else null


func my_roster() -> Roster:
	return world.my_roster() if world != null else null


# ============================================================================
# Sections de la structure
# ============================================================================

## Bascule la gestion sur une autre équipe de la structure (autre discipline,
## académie…). Refuse une équipe qui n'appartient pas au joueur : la sélection
## de section ne doit jamais devenir une porte dérobée vers un rival.
func select_roster(roster_id: String) -> bool:
	if world == null:
		return false
	var r := world.roster(roster_id)
	if r == null or r.org_id != world.player_org_id:
		return false
	world.player_roster_id = r.id
	world.player_game_id = r.game_id
	state_changed.emit()
	return true


## Toutes les sections de la structure dirigée, dans l'ordre du catalogue.
## Chaque entrée : {game_id, roster_id, label, detail, playable, current}.
## Une section « annoncée » (roster_id vide) correspond à une discipline que la
## structure aligne dans la réalité mais que le moteur ne simule pas encore.
func sections() -> Array:
	var out: Array = []
	if world == null:
		return out
	var o := my_org()
	if o == null:
		return out
	var current := my_roster()
	var current_id := current.id if current != null else ""
	for g in o.games:
		var rosters := world.rosters_of(o.id)
		var found := false
		for r in rosters:
			if r.game_id != g:
				continue
			found = true
			out.append({
				"game_id": g, "roster_id": r.id,
				"label": GameCatalog.label(g),
				"detail": "Académie" if r.is_academy else "Équipe principale",
				"playable": true, "current": r.id == current_id,
			})
		if not found:
			out.append({
				"game_id": g, "roster_id": "",
				"label": GameCatalog.label(g),
				"detail": "Section non simulée",
				"playable": false, "current": false,
			})
	return out


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


## Poste occupé par un joueur dans le cinq (différent de son poste naturel).
func set_player_role(player_id: String, role_id: String) -> void:
	var r := my_roster()
	var p := world.player(player_id) if world != null else null
	if r == null or p == null:
		return
	if role_id == "" or role_id == p.primary_role:
		r.player_roles.erase(player_id)
	else:
		r.player_roles[player_id] = role_id
	state_changed.emit()


func set_igl(player_id: String) -> void:
	var r := my_roster()
	if r == null:
		return
	var module := world.module_for(r.game_id)
	for pid in r.player_ids:
		var p := world.player(pid)
		if p == null:
			continue
		var was := p.is_igl
		p.is_igl = pid == player_id
		if was != p.is_igl:
			# Le rôle d'IGL pèse dans le calcul de la CA : il faut recalculer,
			# sinon la fiche affiche un niveau qui ne correspond plus au poste.
			AbilityCalc.refresh(p, module)
	state_changed.emit()


# ============================================================================
# Entraînement
# ============================================================================

func set_training_unit(unit: String, value: int) -> void:
	var r := my_roster()
	if r == null:
		return
	var plan := TrainingSystem.plan_of(r)
	plan[unit] = clampi(value, 0, TrainingSystem.UNITS_PER_WEEK)
	r.training = plan
	state_changed.emit()


func set_training_plan(plan: Dictionary) -> void:
	var r := my_roster()
	if r == null:
		return
	r.training = plan.duplicate()
	state_changed.emit()


func set_player_focus(player_id: String, attr_key: String) -> void:
	var p := world.player(player_id) if world != null else null
	if p == null or p.org_id != world.player_org_id:
		return
	p.training_focus = attr_key
	state_changed.emit()


func set_player_intensity(player_id: String, intensity: float) -> void:
	var p := world.player(player_id) if world != null else null
	if p == null or p.org_id != world.player_org_id:
		return
	p.training_intensity = clampf(intensity, 0.5, 1.5)
	state_changed.emit()


# ============================================================================
# Vestiaire
# ============================================================================

func set_promised_time(player_id: String, status: int) -> Dictionary:
	var p := world.player(player_id) if world != null else null
	if p == null or p.org_id != world.player_org_id:
		return {"ok": false}
	var out := InteractionSystem.set_promise(world, p, status)
	state_changed.emit()
	return out


func talk_to_player(player_id: String, topic: String, tone: int) -> Dictionary:
	var p := world.player(player_id) if world != null else null
	if p == null or p.org_id != world.player_org_id:
		return {"ok": false, "text": "Ce joueur n'est pas dans votre effectif."}
	var out := InteractionSystem.talk(world, p, topic, tone)
	state_changed.emit()
	return out


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
	# Rétablir le pack de la partie AVANT de rendre la main : maps, agents et
	# prénoms sont relus en cours de simulation, et doivent venir du même
	# univers que celui avec lequel la partie a été créée.
	if DataPack.active() != w.data_pack:
		if w.data_pack == "" or DataPack.exists(w.data_pack):
			DataPack.set_active(w.data_pack)
		else:
			Log.w("save", "Pack « %s » absent : la partie se charge avec le "
				% w.data_pack + "contenu livré, certains noms peuvent différer.")
	world = w
	world_loaded.emit()
	state_changed.emit()
	return true
