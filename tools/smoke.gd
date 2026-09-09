extends SceneTree

func _initialize() -> void:
	print("SMOKE: start")
	var module := ValorantModule.new()
	print("SMOKE: module ", module.display_name())
	var ids := Ids.new()
	var rng := Rng.new(1)
	var p := PlayerFactory.create(rng, module, ids, GameDate.from_ymd(2026, 1, 1),
		{"target_ca": 140, "role": ValorantModule.DUELIST})
	print("SMOKE: player ", p.display_name(), " CA=", p.current_ability,
		" PA=", p.potential_ability, " salaire=", Money.fmt(PlayerFactory.salary_for_ca(p.current_ability)))
	var home := TestFactory.make_sheet(rng, module, ids, "Aurora", "AUR", 140)
	var away := TestFactory.make_sheet(rng, module, ids, "Nova", "NVA", 130)
	print("SMOKE: sheets ok")
	var ctx := TestFactory.make_context(rng, module, home, away, 3, true)
	var sim := module.create_simulator()
	print("SMOKE: simulating...")
	var res: MatchResult = sim.simulate(ctx)
	print("SMOKE: ", res.headline, " | ", res.map_score_text())
	print("SMOKE: done")
	quit(0)
