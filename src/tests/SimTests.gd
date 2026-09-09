class_name SimTests
extends RefCounted

## Tests du simulateur Valorant : cohérence des scores, des statistiques,
## et surtout de la COURBE DE FORCE (une meilleure équipe doit gagner plus
## souvent, sans jamais gagner toujours).


static func run() -> Array[TestCase]:
	return [_scores(), _stats(), _strength_curve(), _determinism(), _economy()]


static func _sim_series(seed: int, ca_home: int, ca_away: int, bo: int = 3,
		detailed: bool = false) -> Array:
	var module := ValorantModule.new()
	var ids := Ids.new()
	var rng := Rng.new(seed)
	var home := TestFactory.make_sheet(rng, module, ids, "Aurora", "AUR", ca_home)
	var away := TestFactory.make_sheet(rng, module, ids, "Nova", "NVA", ca_away)
	var ctx := TestFactory.make_context(rng, module, home, away, bo, detailed)
	var sim := module.create_simulator()
	return [sim.simulate(ctx), home, away]


static func _scores() -> TestCase:
	var t := TestCase.new("Simulation — scores plausibles")
	var bad_map := 0
	var bad_series := 0
	var overtimes := 0
	var maps_played := 0
	for s in range(1, 121):
		var out := _sim_series(s * 17, 135, 133, 3, true)
		var res: MatchResult = out[0]
		if maxi(res.home_score, res.away_score) != 2:
			bad_series += 1
		if res.maps.size() < 2 or res.maps.size() > 3:
			bad_series += 1
		for m in res.maps:
			maps_played += 1
			var hi: int = maxi(m.home_rounds, m.away_rounds)
			var lo: int = mini(m.home_rounds, m.away_rounds)
			if hi < 13 or (hi - lo) < 2:
				bad_map += 1
			if hi > 13 and not m.overtime:
				bad_map += 1
			if m.overtime:
				overtimes += 1
			if m.rounds.size() != m.home_rounds + m.away_rounds:
				bad_map += 1

	t.eq(bad_series, 0, "toutes les séries BO3 se terminent en 2 maps gagnées")
	t.eq(bad_map, 0, "toutes les maps respectent le MR12 (13 rounds, 2 d'écart)")
	var ot_rate := float(overtimes) / maxf(float(maps_played), 1.0)
	t.between(ot_rate, 0.02, 0.22,
		"taux de prolongation réaliste entre équipes de même niveau")
	return t


static func _stats() -> TestCase:
	var t := TestCase.new("Simulation — statistiques individuelles")
	var out := _sim_series(4242, 140, 138, 3, true)
	var res: MatchResult = out[0]

	t.eq(res.player_stats.size(), 10, "dix joueurs statistiqués")
	t.check(res.mvp_id != "", "un MVP est désigné")

	var total_k := 0
	var total_d := 0
	var ratings: Array[float] = []
	for pid in res.player_stats:
		var st: Dictionary = res.player_stats[pid]
		total_k += int(st["kills"])
		total_d += int(st["deaths"])
		ratings.append(float(st["rating"]))
		t.check(int(st["kast_rounds"]) <= int(st["rounds"]),
			"le KAST ne dépasse jamais le nombre de rounds")
		t.between(float(st["acs"]), 40.0, 480.0, "ACS dans une plage crédible")
	t.eq(total_k, total_d, "autant de frags que de morts sur la série")

	var avg := 0.0
	for r in ratings:
		avg += r
	avg /= float(ratings.size())
	t.between(avg, 0.85, 1.15, "la note moyenne d'un match tourne autour de 1.00")
	return t


static func _strength_curve() -> TestCase:
	var t := TestCase.new("Simulation — courbe de force")
	var gaps := {0: 0, 10: 0, 25: 0, 45: 0}
	var n := 120
	for gap in gaps.keys():
		var wins := 0
		for s in n:
			var out := _sim_series(7000 + s * 31 + gap, 140, 140 - gap, 3)
			var res: MatchResult = out[0]
			if res.winner_id == res.home_id:
				wins += 1
		gaps[gap] = wins

	var wr0 := float(gaps[0]) / float(n)
	var wr10 := float(gaps[10]) / float(n)
	var wr25 := float(gaps[25]) / float(n)
	var wr45 := float(gaps[45]) / float(n)

	t.between(wr0, 0.38, 0.62, "à niveau égal, le résultat est un pile ou face")
	t.between(wr10, 0.52, 0.78, "un léger écart de niveau se voit sans être décisif")
	t.between(wr25, 0.72, 0.95, "un écart net domine largement")
	t.between(wr45, 0.90, 1.0, "un gouffre de niveau ne laisse presque rien passer")
	t.check(wr0 < wr10 and wr10 < wr25 and wr25 <= wr45,
		"la probabilité de victoire croît avec l'écart de niveau")
	return t


static func _determinism() -> TestCase:
	var t := TestCase.new("Simulation — déterminisme")
	var a := _sim_series(31337, 130, 125, 3, true)
	var b := _sim_series(31337, 130, 125, 3, true)
	var ra: MatchResult = a[0]
	var rb: MatchResult = b[0]
	t.eq(ra.score_text(), rb.score_text(), "même graine, même score de série")
	t.eq(ra.map_score_text(), rb.map_score_text(), "même graine, mêmes scores de map")
	t.eq(ra.mvp_id, rb.mvp_id, "même graine, même MVP")
	return t


static func _economy() -> TestCase:
	var t := TestCase.new("Simulation — économie de round")
	var out := _sim_series(555, 140, 140, 1, true)
	var res: MatchResult = out[0]
	var m: MapResult = res.maps[0]

	var types := {}
	for r in m.rounds:
		types[r["type"]] = int(types.get(r["type"], 0)) + 1
	t.eq(int(types.get("pistol", 0)), 2, "exactement deux pistols par map")
	t.check(types.has("full"), "des full buys sont joués")
	t.check(types.has("eco") or types.has("force"),
		"des rounds à économie réduite existent")

	var first_half := 0
	for r in m.rounds:
		if int(r["n"]) <= 12 and str(r["home_side"]) != "":
			first_half += 1
	t.eq(first_half, mini(12, m.rounds.size()), "les 12 premiers rounds sont une mi-temps")
	return t
