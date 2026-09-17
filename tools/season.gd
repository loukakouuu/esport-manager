extends SceneTree

## Simule une saison complète en headless et imprime un rapport.
## C'est l'outil d'équilibrage principal : il montre d'un coup d'oeil si les
## finances tiennent, si les classements sont crédibles et si le monde vit.
##
##   godot --headless --path . --script res://tools/season.gd [--pack=vct_2026]
##
## Sans `--pack`, l'univers fictif ; avec, celui du pack — qui est celui que
## le joueur obtient par défaut, et qui n'a plus la même hiérarchie ni les
## mêmes tailles de ligue depuis que le circuit Counter-Strike vient du
## classement mondial HLTV.

func _initialize() -> void:
	var pack := _requested_pack()
	if pack != "":
		if not DataPack.exists(pack):
			print("Pack introuvable : %s" % pack)
			quit(1)
			return
		DataPack.set_active(pack)
	print("Univers : %s" % ("contenu livré (fictif)" if pack == ""
		else "pack « %s »" % str(DataPack.manifest(pack).get("name", pack))))

	var t0 := Time.get_ticks_msec()
	var start := GameDate.from_ymd(2026, 1, 5)
	print("Génération du monde…")
	var world := WorldGenerator.generate(20260105, start)
	print("  %d ms" % (Time.get_ticks_msec() - t0))

	# On prend une structure de Challengers : le vrai scénario de campagne.
	var candidates := WorldGenerator.selectable_orgs(world, "chal_emea")
	var chosen: String = str(candidates[candidates.size() - 4]["org_id"])
	WorldGenerator.assign_player_org(world, chosen)
	var me := world.my_org()
	print("Structure du joueur : %s (%s) — trésorerie %s, réputation %d"
		% [me.name, me.tag, Money.fmt(me.cash()), me.reputation])

	var t1 := Time.get_ticks_msec()
	var days := 0
	var matches := 0
	var stop_day := GameDate.from_ymd(2026, 11, 10)
	while world.today < stop_day and days < 400:
		var rep := GameSim.advance_day(world)
		if GameDate.is_monday(world.today):
			# L’outil joue le rôle d’un manager passif : sans cela le roster
			# du joueur se vide et les chiffres n’ont plus de sens.
			TransferSystem.auto_manage(world, me)
			StaffSystem.auto_manage(world, me)
		if GameDate.is_first_day_of_month(world.today):
			# … y compris la partie sponsors et infrastructures.
			AiDirector.monthly_decisions(world, me)
		matches += (rep["results"] as Array).size()
		days += 1
	print("Saison simulée : %d jours, %d séries, %d ms"
		% [days, matches, Time.get_ticks_msec() - t1])

	_print_league(world, "open_emea")
	_print_league(world, "promo_emea")
	_print_league(world, "chal_emea")
	_print_league(world, "vct_emea")
	_print_league(world, "cs_chal_emea")
	_print_league(world, "cs_pro_emea")
	_print_league(world, "cs_major_fall")
	_print_finances(world)
	_print_squad(world)
	_print_staff(world)
	_print_top_players(world)
	_print_disciplines(world)
	_print_inbox(world)
	_check_save(world)
	quit(0)


func _print_league(world: World, key: String) -> void:
	for cid in world.competitions:
		var c: Competition = world.competitions[cid]
		if c.key != key:
			continue
		print("\n=== %s — %s ===" % [c.name, _status(c)])
		var shown := 0
		for rid in c.final_ranking:
			shown += 1
			if shown > 6:
				break
			var r := world.roster(rid)
			var o := world.org(r.org_id) if r != null else null
			print("  %2d. %-22s  prize %s"
				% [shown, o.name if o != null else "?",
					Money.fmt_short(c.prize_for_placement(shown))])
		if c.final_ranking.is_empty():
			var st := c.active_stage()
			print("  en cours — phase : %s" % (st.name if st != null else "?"))


func _status(c: Competition) -> String:
	match c.status:
		Competition.Status.SCHEDULED: return "à venir"
		Competition.Status.RUNNING: return "en cours"
	return "terminée"


func _print_finances(world: World) -> void:
	var o := world.my_org()
	var from_day := world.start_day
	print("\n=== Finances — %s ===" % o.name)
	print("  Trésorerie      %s" % Money.fmt(o.cash()))
	print("  Résultat annuel %s" % Money.fmt(o.ledger.net(from_day, world.today)))
	print("  Masse salariale %s / an (%.0f %% des revenus)"
		% [Money.fmt(FinanceSystem.wage_bill_yearly(world, o)),
			FinanceSystem.wage_ratio(world, o) * 100.0])
	print("  Prévisionnel    %s / mois"
		% Money.fmt(FinanceSystem.projected_monthly_result(world, o)))
	var runway := FinanceSystem.runway_months(world, o)
	print("  Autonomie       %s"
		% ("rentable" if runway < 0 else "%d mois" % runway))
	print("  Fans            %d   Réputation %d" % [o.fanbase, o.reputation])
	print("  --- Compte de résultat ---")
	var pnl := o.ledger.pnl(from_day, world.today)
	var rows: Array = []
	for cat in pnl:
		rows.append([int(cat), int(pnl[cat])])
	rows.sort_custom(func(a, b): return int(a[1]) > int(b[1]))
	for row in rows:
		print("    %-34s %12s"
			% [Transaction.category_label(row[0] as Transaction.Category),
				Money.fmt(row[1])])


func _print_squad(world: World) -> void:
	var o := world.my_org()
	for r in world.rosters_of(o.id):
		print("\n=== Effectif %s — %s (cohésion %.0f) ==="
			% [GameCatalog.short(r.game_id), o.name, r.chemistry])
		for p in world.players_of(r.id):
			var st: Dictionary = p.season_stats
			print("  %-12s %-14s %2d ans  CA %3d/%3d  note %.2f  forme %2.0f  "
				% [p.display_name(), p.primary_role, p.age(world.today),
					p.current_ability, p.potential_ability,
					float(st.get("rating", 0.0)), p.form]
				+ "moral %2.0f  %s/an" % [p.morale,
					Money.fmt_short(p.contract.salary_yearly if p.contract != null else 0)])


## Bilan PAR DISCIPLINE. C'est le tableau qui dit si Counter-Strike est
## réellement intégré ou seulement branché : population, note moyenne — qui
## doit tomber sur 1.00 dans les deux disciplines — et santé financière des
## maisons qui tiennent deux sections.
func _print_disciplines(world: World) -> void:
	print("\n=== Disciplines ===")
	for game_id in GameRegistry.all_ids():
		var teams := 0
		var players := 0
		var free := 0
		var rating_sum := 0.0
		var rated := 0
		var rounds := 0
		var maps := 0
		for rid in world.rosters:
			var r: Roster = world.rosters[rid]
			if r.game_id == game_id:
				teams += 1
		for pid in world.players:
			var p: Player = world.players[pid]
			if p.game_id != game_id or p.retired:
				continue
			players += 1
			if p.is_free_agent():
				free += 1
			if int(p.season_stats.get("series", 0)) >= 8:
				rating_sum += float(p.season_stats.get("rating", 0.0))
				rated += 1
		for fid in world.fixtures:
			var f: Fixture = world.fixtures[fid]
			if not f.played or f.result == null:
				continue
			var r2 := world.roster(f.home_id)
			if r2 == null or r2.game_id != game_id:
				continue
			for m in f.result.maps:
				maps += 1
				rounds += m.home_rounds + m.away_rounds
		print("  %-18s %3d équipes  %4d joueurs (%d libres)  note moy. %.2f  "
			% [GameCatalog.label(game_id), teams, players, free,
				rating_sum / maxf(float(rated), 1.0)]
			+ "%.1f rounds/map" % (float(rounds) / maxf(float(maps), 1.0)))

	# Les maisons à plusieurs sections sont le vrai test de cohérence : elles
	# paient deux masses salariales sur une seule trésorerie.
	var multi := 0
	var solvent := 0
	var worst: Organization = null
	for oid in world.orgs:
		var o: Organization = world.orgs[oid]
		if world.rosters_of(o.id).size() < 2:
			continue
		multi += 1
		if o.cash() >= 0 and not o.bankrupt:
			solvent += 1
		if worst == null or o.cash() < worst.cash():
			worst = o
	print("  %d structures à plusieurs sections, %d solvables (%.0f %%)"
		% [multi, solvent, float(solvent) / maxf(float(multi), 1.0) * 100.0])
	if worst != null:
		print("  la plus en peine : %s à %s" % [worst.name, Money.fmt(worst.cash())])
	var broke := 0
	for oid in world.orgs:
		if (world.orgs[oid] as Organization).bankrupt:
			broke += 1
	print("  %d dépôts de bilan sur %d structures" % [broke, world.orgs.size()])


func _print_top_players(world: World) -> void:
	var all: Array = []
	for pid in world.players:
		var p: Player = world.players[pid]
		if p.retired or int(p.season_stats.get("series", 0)) < 8:
			continue
		all.append(p)
	all.sort_custom(func(a, b):
		return float(a.season_stats.get("rating", 0.0)) \
			> float(b.season_stats.get("rating", 0.0)))
	print("\n=== Meilleures notes de la saison ===")
	for i in mini(10, all.size()):
		var p: Player = all[i]
		var o := world.org(p.org_id)
		print("  %.2f  %-5s %-12s %-20s ACS/ADR %3.0f  CA %d"
			% [float(p.season_stats["rating"]), GameCatalog.short(p.game_id),
				p.display_name(), o.name if o != null else "agent libre",
				float(p.season_stats.get("acs", 0.0)), p.current_ability])


func _print_inbox(world: World) -> void:
	print("\n=== Boîte de réception (%d messages) ===" % world.inbox.size())
	var start := maxi(world.inbox.size() - 8, 0)
	for i in range(start, world.inbox.size()):
		var n: Dictionary = world.inbox[i]
		print("  [%s] %s" % [GameDate.format_day_month(int(n["day"])), n["title"]])


func _check_save(world: World) -> void:
	print("\n=== Sauvegarde ===")
	var ok := SaveGame.save(world, "test_season")
	var reloaded := SaveGame.load_slot("test_season")
	if not ok or reloaded == null:
		print("  ECHEC")
		return
	var a := world.my_org()
	var b := reloaded.my_org()
	print("  écrite et relue : jour %d == %d, trésorerie %s == %s, %d joueurs == %d"
		% [world.today, reloaded.today, Money.fmt(a.cash()), Money.fmt(b.cash()),
			world.players.size(), reloaded.players.size()])


func _print_staff(world: World) -> void:
	var o := world.my_org()
	print("\n=== Staff — %s ===" % o.name)
	for sid in o.staff_ids:
		var s := world.staffer(sid)
		if s == null:
			continue
		print("  %-22s %-24s note %.1f  %s/an"
			% [s.display_name(), s.role_label(), s.overall(),
				Money.fmt_short(s.contract.salary_yearly if s.contract != null else 0)])


func _requested_pack() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pack="):
			return arg.substr(7)
	return ""
