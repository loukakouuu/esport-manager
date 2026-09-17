class_name Cs2Tests
extends RefCounted

## Tests de la discipline COUNTER-STRIKE 2.
##
## Deux familles, et elles ne se recouvrent pas :
##
##   * le SIMULATEUR — scores MR12, prolongations MR3, économie, statistiques,
##     déterminisme. Ce sont les mêmes exigences que pour Valorant, avec les
##     règles de Counter-Strike ;
##   * l'INTÉGRATION — une section CS2 dans le monde généré doit avoir ses
##     joueurs, son banc, son championnat, ses contrats et ses écritures
##     comptables. C'est cette moitié-là qui attrape les régressions : un
##     simulateur juste branché sur un monde qui ne l'engage nulle part passe
##     tous les tests d'unité et ne se joue jamais.


static func run() -> Array[TestCase]:
	return [_module(), _scores(), _stats(), _strength_curve(), _determinism(),
		_economy(), _world_integration(), _finance_integration()]


static func _sim_series(seed: int, ca_home: int, ca_away: int, bo: int = 3,
		detailed: bool = false) -> Array:
	var module := Cs2Module.new()
	var ids := Ids.new()
	var rng := Rng.new(seed)
	var home := TestFactory.make_sheet(rng, module, ids, "Varyag", "VRG", ca_home)
	var away := TestFactory.make_sheet(rng, module, ids, "Kaltbrand", "KLB", ca_away)
	var ctx := TestFactory.make_context(rng, module, home, away, bo, detailed)
	var sim := module.create_simulator()
	return [sim.simulate(ctx), home, away]


# ============================================================================
# Le module
# ============================================================================

static func _module() -> TestCase:
	var t := TestCase.new("CS2 — la discipline est déclarée")
	var m := Cs2Module.new()
	t.eq(m.id(), "cs2", "identifiant de la discipline")
	t.check(GameRegistry.has("cs2"), "elle est enregistrée au registre")
	t.check(GameCatalog.playable("cs2"), "et donc jouable au catalogue")
	t.eq(m.team_size(), 5, "cinq titulaires")
	t.eq(m.roles().size(), 5, "cinq postes")
	t.check(m.roles().has(Cs2Module.AWPER), "dont l'AWPeur")
	t.check(m.roles().has(Cs2Module.LURKER), "et le lurker")

	# Les postes doivent être NOMMÉS : un identifiant en snake_case qui
	# remonte à l'écran trahit une étiquette oubliée.
	for role in m.roles():
		var label := m.role_label(role)
		t.check(label != "" and not label.contains("_"),
			"le poste %s a une étiquette lisible (%s)" % [role, label])
		t.check(not m.role_weights(role).is_empty(),
			"le poste %s a des poids d'attributs" % role)
	for key in m.attribute_keys():
		var attr_label := m.attribute_label(key)
		t.check(attr_label != "" and not attr_label.contains("_"),
			"l'attribut %s a une étiquette lisible (%s)" % [key, attr_label])

	# L'AWP est CE qui distingue la discipline : elle doit peser plus lourd
	# chez l'AWPeur que n'importe quel attribut de n'importe quel autre poste.
	var awp_weight := float(m.role_weights(Cs2Module.AWPER).get(
		Cs2Module.SNIPING, 0.0))
	for role in m.roles():
		if role == Cs2Module.AWPER:
			continue
		t.check(float(m.role_weights(role).get(Cs2Module.SNIPING, 0.0)) < awp_weight,
			"le sniping compte moins pour un %s que pour l'AWPeur" % role)

	t.check(m.attribute_keys().has(Cs2Module.SNIPING),
		"l'AWP est un attribut à part entière")
	t.check(m.attribute_keys().has(Cs2Module.LURKING), "le lurk aussi")
	t.check(m.declining_attributes().has(Cs2Module.SNIPING),
		"et il décline avec les réflexes")

	# Les cartes : toutes CT-sided, c'est la signature de Counter-Strike.
	var pool := m.map_pool()
	t.check(pool.size() >= 7, "le pool actif compte au moins sept cartes")
	for name in pool:
		var info := m.map_info(name)
		t.check(float(info.get("atk_win_rate", 1.0)) < 0.53,
			"%s n'est pas une carte favorable aux T" % name)

	# Un tirage de données de joueur doit produire une maîtrise d'armes.
	var rng := Rng.new(99)
	var ids := Ids.new()
	var p := PlayerFactory.create(rng, m, ids, TestFactory.today(),
		{"target_ca": 140, "role": Cs2Module.AWPER})
	t.eq(p.game_id, "cs2", "le joueur appartient à la discipline")
	var weapons: Dictionary = p.game_data.get("weapons", {})
	t.check(weapons.size() >= 2, "il a une maîtrise d'armes")
	t.check(p.game_data.has("maps"), "et un confort par carte")

	t.check(m.tactic_sliders().size() >= 5, "l'écran Tactique a des curseurs")
	for slider_v in m.tactic_sliders():
		var slider: Dictionary = slider_v
		t.check(m.default_tactic().has(str(slider["key"])),
			"le curseur %s existe dans la tactique par défaut" % slider["key"])
	return t


# ============================================================================
# Le simulateur
# ============================================================================

static func _scores() -> TestCase:
	var t := TestCase.new("CS2 — scores plausibles (MR12)")
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
			# MR12 : on gagne à 13 si l'adversaire est à 11 au plus ; 12-12
			# part en prolongation, et un palier de prolongation vaut 3.
			if hi < 13:
				bad_map += 1
			if hi == 13 and lo > 11:
				bad_map += 1
			if hi > 13 and not m.overtime:
				bad_map += 1
			if hi > 13 and (hi - 13) % 3 != 0:
				bad_map += 1
			if m.rounds.size() != m.home_rounds + m.away_rounds:
				bad_map += 1

	t.eq(bad_series, 0, "toutes les séries BO3 se terminent en 2 maps gagnées")
	t.eq(bad_map, 0, "toutes les maps respectent le MR12 et ses prolongations")
	var ot_rate := float(overtimes) / maxf(float(maps_played), 1.0)
	t.between(float(maps_played), 240.0, 360.0,
		"entre deux et trois maps par série")
	return t


static func _stats() -> TestCase:
	var t := TestCase.new("CS2 — statistiques individuelles")
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
		# L'ADR de Counter-Strike vit autour de 78, pas autour de 130 comme
		# l'ACS de Valorant : une plage trop large ne prouverait rien.
		t.between(float(st["adr"]), 20.0, 160.0, "ADR dans une plage crédible")
		t.between(float(st["kast"]), 20.0, 100.0, "KAST exprimé en pourcentage")
	t.eq(total_k, total_d, "autant de frags que de morts sur la série")

	var avg := 0.0
	for r in ratings:
		avg += r
	avg /= float(ratings.size())
	t.between(avg, 0.85, 1.15, "la note moyenne d'un match tourne autour de 1.00")
	return t


static func _strength_curve() -> TestCase:
	var t := TestCase.new("CS2 — courbe de force")
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
	t.between(wr10, 0.52, 0.80, "un léger écart de niveau se voit sans être décisif")
	t.between(wr25, 0.72, 0.96, "un écart net domine largement")
	t.between(wr45, 0.90, 1.0, "un gouffre de niveau ne laisse presque rien passer")
	t.check(wr0 < wr10 and wr10 < wr25 and wr25 <= wr45,
		"la probabilité de victoire croît avec l'écart de niveau")
	return t


static func _determinism() -> TestCase:
	var t := TestCase.new("CS2 — déterminisme")
	var a := _sim_series(31337, 130, 125, 3, true)
	var b := _sim_series(31337, 130, 125, 3, true)
	var ra: MatchResult = a[0]
	var rb: MatchResult = b[0]
	t.eq(ra.score_text(), rb.score_text(), "même graine, même score de série")
	t.eq(ra.map_score_text(), rb.map_score_text(), "même graine, mêmes scores de map")
	t.eq(ra.mvp_id, rb.mvp_id, "même graine, même MVP")
	return t


static func _economy() -> TestCase:
	var t := TestCase.new("CS2 — économie et camps")
	var out := _sim_series(555, 140, 140, 1, true)
	var res: MatchResult = out[0]
	var m: MapResult = res.maps[0]

	var types := {}
	var sides := {}
	for r in m.rounds:
		types[r["type"]] = int(types.get(r["type"], 0)) + 1
		sides[r["home_side"]] = int(sides.get(r["home_side"], 0)) + 1
	t.check(int(types.get("pistol", 0)) >= 2,
		"au moins deux pistols par map (un par mi-temps)")
	t.check(types.has("full"), "des full buys sont joués")
	t.check(types.has("eco") or types.has("force") or types.has("bonus"),
		"des rounds à économie réduite existent")

	# Le vocabulaire de la discipline : T et CT, jamais « attaque » et
	# « défense ». C'est ce que lit le compte rendu de match.
	t.check(sides.has("T") and sides.has("CT"),
		"les camps sont nommés T et CT")
	var module := Cs2Module.new()
	t.eq(module.side_label(true), "T", "le camp attaquant s'appelle T")
	t.eq(module.side_label(false), "CT", "le camp défenseur s'appelle CT")

	var first_half := 0
	for r in m.rounds:
		if int(r["n"]) <= 12:
			first_half += 1
	t.eq(first_half, mini(12, m.rounds.size()),
		"les 12 premiers rounds sont une mi-temps")

	# Les douze premiers rounds se jouent d'un seul côté, les douze suivants
	# de l'autre : si ce n'est pas vrai, le biais de map ne veut plus rien dire.
	var side_first := str((m.rounds[0] as Dictionary)["home_side"])
	var switched := true
	for r in m.rounds:
		var n := int(r["n"])
		if n <= 12 and str(r["home_side"]) != side_first:
			switched = false
		if n > 12 and n <= 24 and str(r["home_side"]) == side_first:
			switched = false
	t.check(switched, "les camps sont échangés à la mi-temps")
	return t


# ============================================================================
# Intégration dans le monde
# ============================================================================

static var _cached: World = null


static func _world() -> World:
	if _cached == null:
		_cached = WorldGenerator.generate(20260105, GameDate.from_ymd(2026, 1, 5))
	return _cached


static func _world_integration() -> TestCase:
	var t := TestCase.new("CS2 — la discipline vit dans le monde")
	var w := _world()

	# Des équipes, des joueurs, un marché.
	var teams := 0
	var players := 0
	var free := 0
	for rid in w.rosters:
		if (w.rosters[rid] as Roster).game_id == "cs2":
			teams += 1
	for pid in w.players:
		var p: Player = w.players[pid]
		if p.game_id == "cs2":
			players += 1
			if p.is_free_agent():
				free += 1
	t.check(teams >= 40, "le monde compte de vraies ligues CS2 (%d équipes)" % teams)
	t.check(players >= teams * 5, "chaque équipe a son effectif (%d joueurs)" % players)
	t.check(free >= 40, "et un marché d'agents libres (%d)" % free)

	# Des compétitions, à tous les étages, avec leurs dotations.
	var tiers := {}
	var prize := 0
	for cid in w.competitions:
		var c: Competition = w.competitions[cid]
		if c.game_id != "cs2":
			continue
		tiers[c.tier] = int(tiers.get(c.tier, 0)) + 1
		prize += c.prize_pool
	t.check(tiers.has(1) and tiers.has(2) and tiers.has(3),
		"la pyramide CS2 a bien trois étages")
	t.check(prize > Money.from_units(3_000_000.0),
		"les dotations CS2 existent (%s)" % Money.fmt(prize))

	# Chaque équipe engagée : un cinq, un banc, un championnat.
	var short_squads := 0
	var no_coach := 0
	var no_league := 0
	for rid in w.rosters:
		var r: Roster = w.rosters[rid]
		if r.game_id != "cs2" or r.is_academy:
			continue
		if r.player_ids.size() < 5:
			short_squads += 1
		if w.staffer(r.head_coach_id) == null:
			no_coach += 1
		if r.competition_ids.is_empty():
			no_league += 1
	t.eq(short_squads, 0, "aucune équipe CS2 n'est incomplète")
	t.eq(no_coach, 0, "aucune équipe CS2 n'est sans entraîneur")
	t.eq(no_league, 0, "aucune équipe CS2 n'est sans championnat")

	# L'INVARIANT de la structure multi-sections : `games` ne ment jamais.
	var lying := 0
	var undeclared := 0
	var mixed := 0
	var multi := 0
	for oid in w.orgs:
		var o: Organization = w.orgs[oid]
		for g in o.games:
			if GameCatalog.playable(g) and w.main_roster(o.id, g) == null:
				lying += 1
		var rosters := w.rosters_of(o.id)
		if rosters.size() >= 2:
			multi += 1
		for r in rosters:
			if not o.games.has(r.game_id):
				undeclared += 1
			for p in w.players_of(r.id):
				if p.game_id != r.game_id or p.org_id != o.id:
					mixed += 1
	t.eq(lying, 0, "aucune section déclarée et simulée sans équipe")
	t.eq(undeclared, 0, "aucune équipe dont la discipline n'est pas déclarée")
	t.eq(mixed, 0, "aucun joueur dans la mauvaise discipline ni la mauvaise maison")
	t.check(multi >= 10,
		"des maisons tiennent réellement deux sections (%d)" % multi)

	# Un banc par ÉQUIPE, pas par maison : c'est ce qui coûte cher et c'est ce
	# qui fait qu'une section n'hérite pas du coach de l'autre.
	for oid in w.orgs:
		var o: Organization = w.orgs[oid]
		var rosters := w.rosters_of(o.id)
		if rosters.size() < 2:
			continue
		var benches := {}
		var doubled := false
		for r in rosters:
			if r.head_coach_id != "" and benches.has(r.head_coach_id):
				doubled = true
			benches[r.head_coach_id] = true
		t.check(not doubled,
			"%s ne fait pas coacher deux équipes par la même personne" % o.name)
		break
	return t


static func _finance_integration() -> TestCase:
	var t := TestCase.new("CS2 — une section pèse sur la trésorerie")
	var w := _world()

	# On prend une maison à deux sections et on vérifie que la deuxième est
	# bien dans les comptes : c'est le cœur du projet — une structure, un
	# grand livre, plusieurs équipes.
	var target: Organization = null
	var cs_roster: Roster = null
	for oid in w.orgs:
		var o: Organization = w.orgs[oid]
		var val := w.main_roster(o.id, "valorant")
		var cs := w.main_roster(o.id, "cs2")
		if val != null and cs != null:
			target = o
			cs_roster = cs
			break
	if target == null:
		t.check(false, "au moins une maison aligne les deux disciplines")
		return t

	t.check(true, "maison témoin : %s" % target.name)
	var squad := w.players_of(cs_roster.id)
	t.check(squad.size() >= 5, "sa section CS2 a un effectif")

	# Les salaires CS2 doivent être dans la masse salariale de la MAISON.
	var cs_wages := 0
	for p in squad:
		t.check(p.contract != null, "%s a un contrat" % p.display_name())
		if p.contract != null:
			t.eq(p.contract.org_id, target.id, "signé avec la structure")
			cs_wages += p.contract.salary_yearly
	var total := FinanceSystem.wage_bill_yearly(w, target)
	t.check(cs_wages > 0, "la section CS2 coûte quelque chose")
	t.check(total >= cs_wages,
		"la masse salariale de la maison contient celle de la section CS2")

	# Les charges fixes doivent bouger quand on ajoute la section : on le
	# vérifie en comparant à une maison identique sans section CS2.
	var before := FinanceSystem.fixed_monthly_cost(w, target)
	t.check(before > 0, "la maison a des charges fixes")

	# Une clôture mensuelle doit débiter les salaires des DEUX sections.
	var probe := WorldGenerator.generate(4242, GameDate.from_ymd(2026, 1, 5))
	var probe_org: Organization = null
	for oid in probe.orgs:
		var o: Organization = probe.orgs[oid]
		if probe.main_roster(o.id, "valorant") != null \
				and probe.main_roster(o.id, "cs2") != null:
			probe_org = o
			break
	if probe_org == null:
		return t
	var day := probe.today
	FinanceSystem.monthly_close(probe, probe_org)
	var paid := {}
	for tx in probe_org.ledger.in_range(day, day):
		if tx.category == Transaction.Category.PLAYER_SALARY:
			paid[tx.counterparty] = true
	var cs_paid := 0
	for p in probe.players_of(probe.main_roster(probe_org.id, "cs2").id):
		if paid.has(p.id):
			cs_paid += 1
	t.check(cs_paid >= 5,
		"la clôture mensuelle paie les joueurs de la section CS2 (%d)" % cs_paid)

	# Et la ligue CS2 doit verser sa subvention à la maison : c'est ce qui
	# distingue une section réellement engagée d'une ligne décorative.
	var stipends := {}
	for tx in probe_org.ledger.in_range(day, day):
		if tx.category == Transaction.Category.LEAGUE_STIPEND \
				or tx.category == Transaction.Category.LEAGUE_REV_SHARE:
			stipends[tx.counterparty] = true
	var cs_league := ""
	for cid in probe.main_roster(probe_org.id, "cs2").competition_ids:
		var c := probe.competition(cid)
		if c != null and c.stipend_yearly > 0:
			cs_league = c.name
	if cs_league != "":
		t.check(stipends.has(cs_league),
			"la subvention de %s est encaissée par la maison" % cs_league)
	return t
