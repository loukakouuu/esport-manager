extends SceneTree

## Sonde de COHÉRENCE MULTI-DISCIPLINES.
##
##   godot --headless --path . --script res://tools/discipline_probe.gd
##       [--pack=vct_2026]
##
## Sans `--pack`, la sonde mesure l'univers FICTIF. Avec, elle mesure celui du
## pack — et c'est celui-là que le joueur obtient par défaut. La distinction
## n'était pas importante tant qu'un pack ne remplaçait que des NOMS ; elle
## l'est devenue le jour où le pack Counter-Strike a apporté une vraie
## hiérarchie (`strength` tiré du classement mondial HLTV) et des ligues
## d'une autre taille. Les deux univers méritent d'être mesurés.
##
## Le jour où le jeu a cessé d'être mono-discipline, « est-ce que ça tourne »
## a cessé de suffire : une saison peut se terminer proprement alors qu'une
## ligue entière joue à quatre joueurs, qu'aucune équipe Counter-Strike n'a
## d'entraîneur, ou que les maisons à deux sections déposent toutes le bilan.
## Cette sonde mesure, discipline par discipline, ce qui doit rester vrai :
##
##   * chaque discipline simulée a des équipes, des joueurs, un marché ;
##   * une note moyenne de 1.00 — c'est la définition de la note, pas un
##     réglage : un joueur exactement moyen vaut 1.00 dans SA discipline ;
##   * chaque équipe engagée a un cinq complet et un banc ;
##   * `Organization.games` ne ment jamais : une discipline déclarée et
##     simulée a une équipe, et une équipe a sa discipline déclarée ;
##   * les maisons à plusieurs sections restent solvables.

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
	var world := WorldGenerator.generate(20260105, start)
	print("Monde généré en %d ms" % (Time.get_ticks_msec() - t0))

	_report_invariants(world, "à la création du monde")

	var t1 := Time.get_ticks_msec()
	var stop_day := GameDate.from_ymd(2026, 11, 10)
	var series := 0
	while world.today < stop_day:
		var rep := GameSim.advance_day(world)
		series += (rep["results"] as Array).size()
	print("\nSaison simulée : %d séries, %d ms"
		% [series, Time.get_ticks_msec() - t1])

	_report_disciplines(world)
	_report_brands(world)
	_report_internationals(world)
	_report_invariants(world, "après une saison complète")
	_report_structures(world)
	quit(0)


func _requested_pack() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pack="):
			return arg.substr(7)
	return ""


# ============================================================================
# Statistiques par discipline
# ============================================================================

func _report_disciplines(world: World) -> void:
	print("\n=== Note et statistiques, par discipline ===")
	print("  %-18s %6s %6s %6s %6s %6s %6s %7s"
		% ["", "note", "K/round", "D/round", "KAST", "dégâts", "rounds", "écart"])
	for game_id in GameRegistry.all_ids():
		var ratings: Array[float] = []
		var kpr := 0.0
		var dpr := 0.0
		var kast := 0.0
		var adr := 0.0
		var n := 0
		for pid in world.players:
			var p: Player = world.players[pid]
			if p.game_id != game_id or p.retired:
				continue
			var st: Dictionary = p.season_stats
			var rounds := float(st.get("rounds", 0))
			if rounds < 200.0:
				continue     # trop peu joué pour être significatif
			ratings.append(float(st.get("rating", 0.0)))
			kpr += float(st.get("kills", 0)) / rounds
			dpr += float(st.get("deaths", 0)) / rounds
			kast += float(st.get("kast_rounds", 0)) / rounds
			adr += float(st.get("damage", 0)) / rounds
			n += 1
		if n == 0:
			print("  %-18s aucun joueur avec assez de rounds"
				% GameCatalog.label(game_id))
			continue
		var mean := 0.0
		for r in ratings:
			mean += r
		mean /= float(n)
		var sd := 0.0
		for r in ratings:
			sd += (r - mean) * (r - mean)
		sd = sqrt(sd / float(n))
		print("  %-18s %6.3f %6.2f %6.2f %5.0f%% %6.1f %6d %7.3f"
			% [GameCatalog.label(game_id), mean, kpr / n, dpr / n,
				kast / n * 100.0, adr / n, n, sd])

	print("\n=== Format des cartes ===")
	for game_id in GameRegistry.all_ids():
		var maps := 0
		var rounds := 0
		var overtimes := 0
		var blowouts := 0
		for fid in world.fixtures:
			var f: Fixture = world.fixtures[fid]
			if not f.played or f.result == null:
				continue
			var r := world.roster(f.home_id)
			if r == null or r.game_id != game_id:
				continue
			for m in f.result.maps:
				maps += 1
				rounds += m.home_rounds + m.away_rounds
				if m.overtime:
					overtimes += 1
				if absi(m.home_rounds - m.away_rounds) >= 10:
					blowouts += 1
		if maps == 0:
			continue
		print("  %-18s %5d cartes  %.1f rounds  %.1f %% de prolongations  "
			% [GameCatalog.label(game_id), maps, float(rounds) / float(maps),
				float(overtimes) / float(maps) * 100.0]
			+ "%.1f %% de démonstrations" % (float(blowouts) / float(maps) * 100.0))


# ============================================================================
# Invariants de structure
# ============================================================================

## D'OÙ VIENNENT LES PODIUMS INTERNATIONAUX.
##
## Les tournois mondiaux sont le seul endroit où les régions se rencontrent,
## donc le seul endroit où l'écart de niveau entre elles se vérifie. Il compte
## doublement depuis que le circuit Counter-Strike du pack vient du classement
## mondial : ce classement ne place que deux écuries chinoises dans ses
## trente-cinq premières, et sa Pro League n'existe que parce qu'un
## championnat est relatif à sa région. Si la Chine gagnait autant de Majors
## que l'Europe, c'est que l'écart mesuré par HLTV aurait été perdu en route,
## et un Major se jouerait à pile ou face.
##
## On regarde le QUART DE FINALISTE et pas seulement le vainqueur : sur une
## seule saison, un vainqueur ne dit rien — huit places en disent déjà plus.
func _report_internationals(world: World) -> void:
	print("\n=== Internationaux : régions représentées dans les huit premiers ===")
	for game_id in GameRegistry.all_ids():
		var tally := {}
		var played := 0
		for cid in world.competitions:
			var c: Competition = world.competitions[cid]
			if c.game_id != game_id or c.region != "WORLD" \
					or c.final_ranking.is_empty():
				continue
			played += 1
			var shown := 0
			for rid in c.final_ranking:
				shown += 1
				if shown > 8:
					break
				var r := world.roster(str(rid))
				if r == null:
					continue
				tally[r.region] = int(tally.get(r.region, 0)) + 1
		if played == 0:
			continue
		var parts: Array[String] = []
		for region in ["EMEA", "AMERICAS", "PACIFIC", "CHINA"]:
			parts.append("%s %d" % [region, int(tally.get(region, 0))])
		print("  %-18s %d tournoi(s) · %s"
			% [GameCatalog.label(game_id), played, " · ".join(parts)])


## LES PLUS GROSSES MARQUES, et l'écart de réputation à l'intérieur d'une
## ligue.
##
## Ce tableau existe à cause d'un défaut mesuré : la réputation de départ
## valait `pow(strength/100, 2.8)`, et `strength` est un TIRAGE pour tout pack
## qui ne déclare pas de hiérarchie — ce que le pack Valorant ne peut pas
## faire, faute de donnée publique. Le jeu désignait donc au hasard la plus
## grosse marque du monde : Nova Esports passait devant Spirit, NAVI et FaZe.
##
## L'ÉCART DANS LA LIGUE est le chiffre qui le trahit. Une ligue partenaire
## rassemble douze maisons comparables : un rapport de 1,2 à 1,4 entre la plus
## et la moins réputée est sain, 2,4 voulait dire que le dé décidait.
func _report_brands(world: World) -> void:
	print("\n=== Marques : les dix premières réputations ===")
	var rows: Array = []
	for oid in world.orgs:
		var o: Organization = world.orgs[oid]
		rows.append(o)
	rows.sort_custom(func(a, b):
		return int((a as Organization).reputation) \
			> int((b as Organization).reputation))
	for i in mini(10, rows.size()):
		var o: Organization = rows[i]
		var games: Array[String] = []
		for r in world.rosters_of(o.id):
			if not r.is_academy:
				games.append(GameCatalog.short(r.game_id))
		print("  %2d. %-24s %5d  %8d fans  %s"
			% [i + 1, o.name, o.reputation, o.fanbase, " + ".join(games)])

	print("\n=== Écart de réputation dans une ligue (étage 1, maisons à une "
		+ "seule section) ===")
	# Deux exclusions, et les deux comptent :
	#
	#  - on range chaque maison sous sa VITRINE, jamais sous sa section
	#    secondaire, sinon la Challenger League américaine hériterait de la
	#    réputation de NRG — qui la tient de son slot en VCT ;
	#  - on ÉCARTE les maisons à plusieurs sections. Leur prime de marque
	#    (`SECTION_UPLIFT`) est légitime : tenir deux rosters fait bien une
	#    maison plus grosse. La mêler au reste ferait monter le rapport à 1,8
	#    dans le monde fictif, où le haut du VCT est plein de maisons à deux
	#    sections, et on ne saurait plus si c'est la prime ou le dé.
	var by_league := {}
	for oid in world.orgs:
		var o: Organization = world.orgs[oid]
		var sections := 0
		for r in world.rosters_of(o.id):
			if not r.is_academy:
				sections += 1
		if sections != 1:
			continue
		var flagship := WorldGenerator.flagship_roster(world, o)
		if flagship == null:
			continue
		if not by_league.has(flagship.league_key):
			by_league[flagship.league_key] = []
		(by_league[flagship.league_key] as Array).append(o.reputation)
	var keys: Array = by_league.keys()
	keys.sort()
	for key in keys:
		var vals: Array = by_league[key]
		if vals.size() < 4:
			continue
		vals.sort()
		var lo := float(vals[0])
		var hi := float(vals[vals.size() - 1])
		if hi < 4000.0:
			continue      # on ne regarde que l'élite : c'est là que ça se voit
		var ratio := hi / maxf(lo, 1.0)
		print("  %-18s %5d → %5d   rapport %.2f %s"
			% [str(key), int(lo), int(hi), ratio,
				"" if ratio <= 1.6 else "  <-- le hasard décide ?"])


func _report_invariants(world: World, when: String) -> void:
	print("\n=== Invariants %s ===" % when)
	var lying := 0          # discipline déclarée, simulée, mais sans équipe
	var undeclared := 0     # équipe dont la discipline n'est pas déclarée
	var wrong_game := 0     # joueur dont la discipline ne suit pas son équipe
	var wrong_org := 0      # joueur rattaché à une autre structure que la sienne
	var short_squads := {}  # par discipline : équipes sans cinq complet
	var no_coach := {}      # par discipline : équipes sans entraîneur
	var teams := {}

	for oid in world.orgs:
		var o: Organization = world.orgs[oid]
		for g in o.games:
			if GameCatalog.playable(g) and world.main_roster(o.id, g) == null:
				lying += 1
		for r in world.rosters_of(o.id):
			if not o.games.has(r.game_id):
				undeclared += 1
			if r.is_academy:
				continue
			teams[r.game_id] = int(teams.get(r.game_id, 0)) + 1
			var size := world.module_for(r.game_id).team_size()
			if r.player_ids.size() < size:
				short_squads[r.game_id] = int(short_squads.get(r.game_id, 0)) + 1
			if world.staffer(r.head_coach_id) == null and not o.bankrupt:
				no_coach[r.game_id] = int(no_coach.get(r.game_id, 0)) + 1
			for p in world.players_of(r.id):
				if p.game_id != r.game_id:
					wrong_game += 1
				if p.org_id != o.id:
					wrong_org += 1

	_line("sections déclarées et simulées sans équipe", lying, 0)
	_line("équipes dont la discipline n'est pas déclarée", undeclared, 0)
	_line("joueurs alignés dans la mauvaise discipline", wrong_game, 0)
	_line("joueurs rattachés à la mauvaise structure", wrong_org, 0)
	for game_id in GameRegistry.all_ids():
		var total := int(teams.get(game_id, 0))
		print("  %-18s %3d équipes · %d effectif incomplet · %d sans entraîneur"
			% [GameCatalog.label(game_id), total,
				int(short_squads.get(game_id, 0)), int(no_coach.get(game_id, 0))])


func _line(label: String, value: int, expected: int) -> void:
	print("  [%s] %-52s %d" % ["OK " if value == expected else "KO", label, value])


# ============================================================================
# Santé des structures
# ============================================================================

func _report_structures(world: World) -> void:
	print("\n=== Structures ===")
	var by_sections := {}
	var solvent := {}
	var wage := {}
	var bankrupt := 0
	for oid in world.orgs:
		var o: Organization = world.orgs[oid]
		var sections := 0
		for r in world.rosters_of(o.id):
			if not r.is_academy:
				sections += 1
		by_sections[sections] = int(by_sections.get(sections, 0)) + 1
		if o.bankrupt:
			bankrupt += 1
		elif o.cash() >= 0:
			solvent[sections] = int(solvent.get(sections, 0)) + 1
		var ratio := FinanceSystem.wage_ratio(world, o)
		if ratio < 90.0:
			wage[sections] = float(wage.get(sections, 0.0)) + ratio

	var keys: Array = by_sections.keys()
	keys.sort()
	for k in keys:
		var total := int(by_sections[k])
		print("  %d section(s) : %3d structures · %3d solvables (%.0f %%) · "
			% [k, total, int(solvent.get(k, 0)),
				float(solvent.get(k, 0)) / float(total) * 100.0]
			+ "masse salariale %.0f %% des recettes"
			% (float(wage.get(k, 0.0)) / float(total) * 100.0))
	print("  %d dépôts de bilan sur %d structures (%.0f %%)"
		% [bankrupt, world.orgs.size(),
			float(bankrupt) / float(world.orgs.size()) * 100.0])

	_report_by_league(world)


## Où les structures meurent-elles ? Par ligue de vitrine : c'est ce qui
## distingue « l'économie du jeu est dure » de « cette discipline-là n'est pas
## finançable ».
func _report_by_league(world: World) -> void:
	print("\n=== Santé par ligue (structure vitrine) ===")
	var rows := {}
	for oid in world.orgs:
		var o: Organization = world.orgs[oid]
		var r := WorldGenerator.flagship_roster(world, o)
		if r == null:
			continue
		var key := r.league_key
		if not rows.has(key):
			rows[key] = {"n": 0, "broke": 0, "result": 0, "cash": 0,
				"game": r.game_id}
		var row: Dictionary = rows[key]
		row["n"] = int(row["n"]) + 1
		row["cash"] = int(row["cash"]) + o.cash()
		row["result"] = int(row["result"]) \
			+ FinanceSystem.projected_monthly_result(world, o)
		if o.bankrupt:
			row["broke"] = int(row["broke"]) + 1
	var keys: Array = rows.keys()
	keys.sort()
	for key in keys:
		var row: Dictionary = rows[key]
		var n := int(row["n"])
		print("  %-5s %-18s %3d structures · %2d faillites · "
			% [GameCatalog.short(str(row["game"])), key, n, int(row["broke"])]
			+ "prévisionnel médian %10s · trésorerie moyenne %10s"
			% [Money.fmt(int(row["result"] / n)), Money.fmt(int(row["cash"] / n))])
