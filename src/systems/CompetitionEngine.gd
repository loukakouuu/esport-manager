class_name CompetitionEngine
extends RefCounted

## Moteur de compétition : création des rencontres, résolution, classements,
## enchaînement des phases, distribution des gains.
##
## Le principe directeur est qu'une compétition est une SUITE DE PHASES et que
## chaque phase sait produire un classement. Le passage d'une phase à l'autre
## n'est qu'un transfert de têtes de série. La même mécanique décrit donc une
## saison régulière de VCT, des playoffs à double élimination et un tournoi
## international, sans code spécifique par tournoi.


# ============================================================================
# Création des rencontres
# ============================================================================

static func populate_stage(world: World, comp: Competition, stage: Stage) -> void:
	if not stage.fixture_ids.is_empty():
		return
	match stage.format:
		Stage.Format.ROUND_ROBIN:
			_populate_round_robin(world, comp, stage, stage.participants, "")
		Stage.Format.GROUPS:
			_populate_groups(world, comp, stage)
		Stage.Format.SINGLE_ELIM:
			_populate_single_elim(world, comp, stage)
		Stage.Format.DOUBLE_ELIM:
			_populate_double_elim(world, comp, stage)
		Stage.Format.SWISS:
			_populate_swiss_round(world, comp, stage, 0)
	stage.status = Stage.Status.RUNNING


static func _new_fixture(world: World, comp: Competition, stage: Stage,
		day: int, best_of: int, label: String, bracket: String = "") -> Fixture:
	var f := Fixture.new()
	f.id = world.ids.next(Ids.FIXTURE)
	f.competition_id = comp.id
	f.stage_id = stage.id
	f.day = day
	f.best_of = best_of
	f.round_label = label
	f.bracket = bracket
	f.is_lan = comp.is_lan
	f.importance = _importance_for(comp, label)
	world.fixtures[f.id] = f
	stage.fixture_ids.append(f.id)
	return f


static func _importance_for(comp: Competition, label: String) -> float:
	var base := clampf(float(comp.prestige) / 6000.0, 0.5, 1.6)
	if label.begins_with("Grande finale") or label.begins_with("Finale"):
		base *= 1.5
	elif label.begins_with("Demi"):
		base *= 1.25
	return base


## Répartit `count` journées sur la fenêtre de la phase, en visant les
## week-ends — comme les vraies ligues.
##
## Contrainte impérative : les journées renvoyées sont STRICTEMENT croissantes.
## Sans cela, l'attirance vers le samedi peut poser deux tours d'un arbre le
## même jour — et une demi-finale programmée avant que ses quarts soient joués
## ne trouve pas ses participants, ce qui bloque la compétition.
static func _match_days(start_day: int, end_day: int, count: int) -> Array[int]:
	var out: Array[int] = []
	if count <= 0:
		return out
	var span := maxi(end_day - start_day, count)
	var previous := -1
	for i in count:
		var d := start_day + int(round(float(i) * float(span) / float(maxi(count - 1, 1))))
		# On glisse vers le samedi le plus proche quand c'est possible.
		var wd := GameDate.weekday(d)
		if wd != 6 and wd != 0:
			var shift := (6 - wd)
			if d + shift <= end_day:
				d += shift
		d = maxi(d, previous + 1)
		previous = d
		out.append(d)
	return out


static func _populate_round_robin(world: World, comp: Competition, stage: Stage,
		participants: Array[String], group: String) -> void:
	var double_round := bool(stage.config.get("double_round", false))
	var days := BracketBuilder.round_robin(participants, double_round)
	var slots := _match_days(stage.start_day, stage.end_day, days.size())
	for i in days.size():
		for pair in days[i]:
			var label := "Journée %d" % (i + 1)
			if group != "":
				label = "%s — journée %d" % [group, i + 1]
			var f := _new_fixture(world, comp, stage, slots[i], stage.best_of,
				label, group)
			f.round_index = i
			f.home_id = pair[0]
			f.away_id = pair[1]
	for pid in participants:
		var st := stage.standing_for(pid)
		st["group"] = group


static func _populate_groups(world: World, comp: Competition, stage: Stage) -> void:
	var n := maxi(int(stage.config.get("groups", 2)), 1)
	var buckets: Array = []
	for _i in n:
		buckets.append([] as Array[String])
	# Répartition en serpentin pour équilibrer les poules par niveau.
	for i in stage.participants.size():
		var b := i % n
		if int(i / n) % 2 == 1:
			b = n - 1 - b
		(buckets[b] as Array).append(stage.participants[i])
	for i in n:
		var name := "Poule %s" % char(65 + i)
		_populate_round_robin(world, comp, stage, buckets[i], name)


static func _populate_single_elim(world: World, comp: Competition, stage: Stage) -> void:
	var rounds := BracketBuilder.single_elim(stage.participants)
	var slots := _match_days(stage.start_day, stage.end_day, rounds.size())
	var ids_by_round: Array = []
	for ri in rounds.size():
		var row: Array[String] = []
		var label := _elim_label(rounds.size() - ri, false)
		var bo: int = stage.final_best_of if ri == rounds.size() - 1 else stage.best_of
		for mi in (rounds[ri] as Array).size():
			var spec: Dictionary = rounds[ri][mi]
			var f := _new_fixture(world, comp, stage, slots[ri], bo, label, "bracket")
			f.round_index = ri
			f.home_id = str(spec.get("home", ""))
			f.away_id = str(spec.get("away", ""))
			var hs: Dictionary = spec.get("home_src", {})
			if not hs.is_empty():
				f.home_source = Fixture.source(Fixture.SlotKind.WINNER_OF,
					ids_by_round[int(hs["round"])][int(hs["match"])])
			var as_: Dictionary = spec.get("away_src", {})
			if not as_.is_empty():
				f.away_source = Fixture.source(Fixture.SlotKind.WINNER_OF,
					ids_by_round[int(as_["round"])][int(as_["match"])])
			row.append(f.id)
		ids_by_round.append(row)


static func _elim_label(rounds_left: int, lower: bool) -> String:
	match rounds_left:
		1: return "Finale"
		2: return "Demi-finale"
		3: return "Quart de finale"
		4: return "Huitième de finale"
	return "Tour préliminaire"


static func _populate_double_elim(world: World, comp: Competition, stage: Stage) -> void:
	if stage.participants.size() != 8:
		# Le format double élimination livré couvre 8 équipes (playoffs VCT).
		# Toute autre taille retombe sur une élimination directe seedée.
		_populate_single_elim(world, comp, stage)
		return
	var rounds := BracketBuilder.double_elim_8(stage.participants)
	var slots := _match_days(stage.start_day, stage.end_day, rounds.size())
	var ids_by_round: Array = []
	for ri in rounds.size():
		var row: Array[String] = []
		for spec_v in rounds[ri]:
			var spec: Dictionary = spec_v
			var label := str(spec["label"])
			var bo: int = stage.final_best_of if label.begins_with("Grande finale") \
				else stage.best_of
			var f := _new_fixture(world, comp, stage, slots[ri], bo, label,
				str(spec.get("b", "")))
			f.round_index = ri
			f.home_id = str(spec.get("home", ""))
			f.away_id = str(spec.get("away", ""))
			if spec.has("home_src"):
				f.home_source = _src_from(spec["home_src"], ids_by_round)
			if spec.has("away_src"):
				f.away_source = _src_from(spec["away_src"], ids_by_round)
			row.append(f.id)
		ids_by_round.append(row)
	stage.config["losses"] = {}


static func _src_from(spec: Array, ids_by_round: Array) -> Dictionary:
	var kind: Fixture.SlotKind = Fixture.SlotKind.WINNER_OF if str(spec[0]) == "winner" \
		else Fixture.SlotKind.LOSER_OF
	return Fixture.source(kind, ids_by_round[int(spec[1])][int(spec[2])])


## Le système suisse ne peut pas être pré-généré : les appariements du tour N+1
## dépendent des résultats du tour N. On crée donc un tour à la fois.
static func _populate_swiss_round(world: World, comp: Competition, stage: Stage,
		round_index: int) -> void:
	var buckets := {}
	for pid in stage.participants:
		var st := stage.standing_for(pid)
		if _swiss_out(stage, st):
			continue
		var key := "%d-%d" % [int(st["w"]), int(st["l"])]
		if not buckets.has(key):
			buckets[key] = [] as Array[String]
		(buckets[key] as Array).append(pid)

	var total_rounds := int(stage.config.get("max_rounds", 5))
	var day := stage.start_day + int(round(
		float(round_index) * float(stage.end_day - stage.start_day)
		/ float(maxi(total_rounds - 1, 1))))

	for key in buckets:
		var group: Array = buckets[key]
		world.rng.shuffle(group)
		var i := 0
		while i + 1 < group.size():
			var wins := int(key.split("-")[0])
			var losses := int(key.split("-")[1])
			var bo: int = stage.final_best_of if (wins == int(stage.config.get(
				"wins_to_qualify", 3)) - 1 or losses == int(stage.config.get(
				"losses_out", 3)) - 1) else stage.best_of
			var f := _new_fixture(world, comp, stage, day, bo,
				"Tour %d (%s)" % [round_index + 1, key], "swiss")
			f.round_index = round_index
			f.home_id = group[i]
			f.away_id = group[i + 1]
			i += 2
	stage.config["swiss_round"] = round_index


static func _swiss_out(stage: Stage, st: Dictionary) -> bool:
	return int(st["w"]) >= int(stage.config.get("wins_to_qualify", 3)) \
		or int(st["l"]) >= int(stage.config.get("losses_out", 3))


# ============================================================================
# Résolution
# ============================================================================

## Enregistre un résultat, met à jour classements et bilans, puis propage le
## vainqueur (et le perdant) vers les rencontres qui en dépendent.
static func apply_result(world: World, f: Fixture, res: MatchResult) -> void:
	f.result = res
	f.played = true
	var comp := world.competition(f.competition_id)
	if comp == null:
		return
	var stage := comp.stage_by_id(f.stage_id)
	if stage == null:
		return

	var winner := res.winner_id
	var loser := res.loser_id
	_update_standing(stage, res, f.home_id, true)
	_update_standing(stage, res, f.away_id, false)
	_update_roster_record(world, f, res)

	if stage.is_bracket():
		var losses: Dictionary = stage.config.get("losses", {})
		losses[loser] = int(losses.get(loser, 0)) + 1
		stage.config["losses"] = losses
		var limit := 2 if stage.format == Stage.Format.DOUBLE_ELIM else 1
		if int(losses[loser]) >= limit:
			_record_elimination(stage, loser)

	_propagate(world, stage, f.id, winner, loser)


static func _propagate(world: World, stage: Stage, from_id: String,
		winner: String, loser: String) -> void:
	for fid in stage.fixture_ids:
		var g: Fixture = world.fixtures[fid]
		if g.played:
			continue
		if g.home_id == "" and str(g.home_source.get("ref", "")) == from_id:
			g.home_id = winner if int(g.home_source.get("kind", 0)) \
				== int(Fixture.SlotKind.WINNER_OF) else loser
		if g.away_id == "" and str(g.away_source.get("ref", "")) == from_id:
			g.away_id = winner if int(g.away_source.get("kind", 0)) \
				== int(Fixture.SlotKind.WINNER_OF) else loser


static func _update_standing(stage: Stage, res: MatchResult, roster_id: String,
		is_home: bool) -> void:
	if roster_id == "":
		return
	var st := stage.standing_for(roster_id)
	var won := res.winner_id == roster_id
	st["w"] = int(st["w"]) + (1 if won else 0)
	st["l"] = int(st["l"]) + (0 if won else 1)
	st["map_w"] = int(st["map_w"]) + (res.home_score if is_home else res.away_score)
	st["map_l"] = int(st["map_l"]) + (res.away_score if is_home else res.home_score)
	for m in res.maps:
		st["round_w"] = int(st["round_w"]) + (m.home_rounds if is_home else m.away_rounds)
		st["round_l"] = int(st["round_l"]) + (m.away_rounds if is_home else m.home_rounds)
	st["pts"] = int(st["w"]) * 3


static func _update_roster_record(world: World, f: Fixture, res: MatchResult) -> void:
	var sides: Array[String] = [f.home_id, f.away_id]
	for rid in sides:
		var r := world.roster(rid)
		if r == null:
			continue
		var rec := r.record_for(f.competition_id)
		var is_home := rid == f.home_id
		var won := res.winner_id == rid
		rec["w"] = int(rec["w"]) + (1 if won else 0)
		rec["l"] = int(rec["l"]) + (0 if won else 1)
		rec["maps_w"] = int(rec["maps_w"]) + (res.home_score if is_home else res.away_score)
		rec["maps_l"] = int(rec["maps_l"]) + (res.away_score if is_home else res.home_score)


static func _record_elimination(stage: Stage, roster_id: String) -> void:
	var elim: Array = stage.config.get("eliminated", [])
	if not elim.has(roster_id):
		elim.append(roster_id)
	stage.config["eliminated"] = elim


# ============================================================================
# Enchaînement des phases
# ============================================================================

## Appelée chaque jour. Fait progresser la compétition dès qu'une phase est
## terminée : classement, qualification, phase suivante, clôture.
static func advance(world: World, comp: Competition) -> void:
	if comp.status == Competition.Status.FINISHED:
		return
	var stage := comp.active_stage()
	if stage == null:
		_close_competition(world, comp)
		return
	if stage.status == Stage.Status.PENDING:
		if world.today < stage.start_day - 7:
			return
		# Un tournoi international n'a pas de participants tant que ses
		# qualifications ne sont pas jouées : on attend qu'elles le soient.
		if stage.participants.is_empty() and comp.current_stage == 0:
			if not SeasonBuilder.resolve_seeds(world, comp):
				return
			stage.participants = comp.participants.duplicate()
		populate_stage(world, comp, stage)
		comp.status = Competition.Status.RUNNING
		return
	if not _all_played(world, stage):
		return

	# Système suisse : tant qu'il reste des équipes ni qualifiées ni éliminées.
	if stage.format == Stage.Format.SWISS:
		var next_round := int(stage.config.get("swiss_round", 0)) + 1
		if _swiss_needs_more(stage) and next_round < int(stage.config.get("max_rounds", 5)):
			_populate_swiss_round(world, comp, stage, next_round)
			return

	_close_stage(world, comp, stage)
	comp.current_stage += 1
	var next := comp.active_stage()
	if next == null:
		_close_competition(world, comp)
	else:
		next.participants = _seed_next(world, comp, stage, next)
		if world.today >= next.start_day - 7:
			populate_stage(world, comp, next)


static func _all_played(world: World, stage: Stage) -> bool:
	for fid in stage.fixture_ids:
		if not (world.fixtures[fid] as Fixture).played:
			return false
	return true


static func _swiss_needs_more(stage: Stage) -> bool:
	for pid in stage.participants:
		var st := stage.standing_for(pid)
		if not _swiss_out(stage, st):
			return true
	return false


static func _close_stage(world: World, comp: Competition, stage: Stage) -> void:
	stage.status = Stage.Status.FINISHED
	stage.ranking = compute_ranking(world, stage)


## Classement d'une phase, quel que soit son format.
static func compute_ranking(world: World, stage: Stage) -> Array[String]:
	if stage.is_bracket():
		return _bracket_ranking(world, stage)
	var sorted := stage.standings.duplicate()
	sorted.sort_custom(func(a, b):
		if int(a["w"]) != int(b["w"]):
			return int(a["w"]) > int(b["w"])
		var da := int(a["map_w"]) - int(a["map_l"])
		var db := int(b["map_w"]) - int(b["map_l"])
		if da != db:
			return da > db
		return (int(a["round_w"]) - int(a["round_l"])) \
			> (int(b["round_w"]) - int(b["round_l"])))
	var out: Array[String] = []
	for s in sorted:
		out.append(str(s["roster_id"]))
	return out


## Dans un arbre, le classement se lit à l'envers : le dernier éliminé est
## troisième, le premier éliminé est dernier.
static func _bracket_ranking(world: World, stage: Stage) -> Array[String]:
	var out: Array[String] = []
	var final_fix: Fixture = null
	for fid in stage.fixture_ids:
		var f: Fixture = world.fixtures[fid]
		if f.played and (final_fix == null or f.round_index > final_fix.round_index):
			final_fix = f
	if final_fix != null and final_fix.result != null:
		out.append(final_fix.result.winner_id)
		out.append(final_fix.result.loser_id)
	var elim: Array = stage.config.get("eliminated", [])
	for i in range(elim.size() - 1, -1, -1):
		var rid := str(elim[i])
		if not out.has(rid):
			out.append(rid)
	for pid in stage.participants:
		if not out.has(pid):
			out.append(pid)
	return out


## Têtes de série de la phase suivante.
static func _seed_next(world: World, comp: Competition, prev: Stage,
		next: Stage) -> Array[String]:
	var qualifiers := maxi(next.qualifiers if next.participants.is_empty()
		else next.participants.size(), 0)
	var take := prev.qualifiers
	if prev.format == Stage.Format.GROUPS:
		# On alterne les poules pour que les premiers ne se croisent pas trop tôt.
		return _interleave_groups(prev, take)
	var out: Array[String] = []
	for i in mini(take, prev.ranking.size()):
		out.append(prev.ranking[i])
	return out


static func _interleave_groups(stage: Stage, total: int) -> Array[String]:
	var groups := {}
	for s in stage.standings:
		var g := str(s["group"])
		if not groups.has(g):
			groups[g] = []
		(groups[g] as Array).append(s)
	var keys := groups.keys()
	keys.sort()
	for g in keys:
		(groups[g] as Array).sort_custom(func(a, b):
			if int(a["w"]) != int(b["w"]):
				return int(a["w"]) > int(b["w"])
			return (int(a["map_w"]) - int(a["map_l"])) \
				> (int(b["map_w"]) - int(b["map_l"])))
	var out: Array[String] = []
	var rank := 0
	while out.size() < total:
		var added := false
		for g in keys:
			var lst: Array = groups[g]
			if rank < lst.size() and out.size() < total:
				out.append(str(lst[rank]["roster_id"]))
				added = true
		if not added:
			break
		rank += 1
	return out


# ============================================================================
# Clôture et récompenses
# ============================================================================

static func _close_competition(world: World, comp: Competition) -> void:
	comp.status = Competition.Status.FINISHED
	if comp.stages.is_empty():
		return
	var last := comp.stages[comp.stages.size() - 1]
	comp.final_ranking = last.ranking.duplicate()
	# Les équipes sorties avant la dernière phase complètent le classement.
	for i in range(comp.stages.size() - 2, -1, -1):
		for rid in comp.stages[i].ranking:
			if not comp.final_ranking.has(rid):
				comp.final_ranking.append(rid)
	for rid in comp.participants:
		if not comp.final_ranking.has(rid):
			comp.final_ranking.append(rid)

	_pay_prizes(world, comp)
	_apply_reputation(world, comp)
	_award_circuit_points(world, comp)
	_record_history(world, comp)


static func _pay_prizes(world: World, comp: Competition) -> void:
	for i in comp.final_ranking.size():
		var amount := comp.prize_for_placement(i + 1)
		if amount <= 0:
			continue
		FinanceSystem.award_prize(world, comp.final_ranking[i], amount,
			_placement_label(i + 1), comp.name)


static func _placement_label(place: int) -> String:
	match place:
		1: return "Vainqueur"
		2: return "Finaliste"
		3: return "3e place"
	return "%de place" % place


## La réputation est le vrai capital d'une structure : elle conditionne les
## sponsors, les joueurs qu'on peut attirer et la valeur de la marque.
static func _apply_reputation(world: World, comp: Competition) -> void:
	var n := comp.final_ranking.size()
	for i in n:
		var r := world.roster(comp.final_ranking[i])
		if r == null:
			continue
		var o := world.org(r.org_id)
		if o == null:
			continue
		# Position relative : +1 pour le vainqueur, -1 pour le dernier.
		var rel := 1.0 - 2.0 * float(i) / float(maxi(n - 1, 1))
		var swing := float(comp.prestige) / 900.0
		o.reputation = clampi(o.reputation + int(round(rel * swing)), 50, 10000)
		var fan_delta := int(round(float(o.fanbase) * rel * 0.045
			* clampf(float(comp.prestige) / 6000.0, 0.3, 1.8)))
		o.fanbase = maxi(o.fanbase + fan_delta, 500)


static func _award_circuit_points(world: World, comp: Competition) -> void:
	if comp.qualification_rules.is_empty():
		return
	var table: Array = [500, 350, 250, 180, 120, 90, 70, 50, 35, 25, 15, 10]
	for i in mini(comp.final_ranking.size(), table.size()):
		var rid := comp.final_ranking[i]
		comp.circuit_points[rid] = int(table[i])


static func _record_history(world: World, comp: Competition) -> void:
	if comp.final_ranking.is_empty():
		return
	var champ := world.roster(comp.final_ranking[0])
	var champ_org := world.org(champ.org_id) if champ != null else null
	world.history.append({
		"year": comp.season_year, "comp_key": comp.key, "comp_name": comp.name,
		"champion_org": champ_org.name if champ_org != null else "?",
		"champion_org_id": champ_org.id if champ_org != null else "",
		"ranking": comp.final_ranking.duplicate(),
	})
	if champ_org != null:
		world.add_news(world.today, "%s remporte %s" % [champ_org.name, comp.name],
			"%s s'adjuge le titre après %s."
				% [champ_org.name, comp.name], "result")


# ============================================================================
# Journée de matchs
# ============================================================================

## Simule toutes les rencontres du jour et fait avancer les compétitions.
static func play_day(world: World) -> Array[MatchResult]:
	var results: Array[MatchResult] = []
	var todays := world.fixtures_on(world.today)
	todays.sort_custom(func(a, b): return a.id < b.id)   # ordre déterministe

	for f in todays:
		if not f.is_ready():
			continue
		var res := simulate_fixture(world, f)
		if res != null:
			results.append(res)

	var touched := {}
	for f in todays:
		touched[f.competition_id] = true
	for cid in touched:
		var comp := world.competition(cid)
		if comp != null:
			advance(world, comp)
	return results


static func simulate_fixture(world: World, f: Fixture) -> MatchResult:
	var home := TeamSheetBuilder.build(world, f.home_id, f.away_id)
	var away := TeamSheetBuilder.build(world, f.away_id, f.home_id)
	if home == null or away == null:
		return null
	var comp := world.competition(f.competition_id)
	var module := world.module_for(home.roster.game_id)

	# Une équipe incomplète déclare forfait. Ça arrive dans la vraie vie
	# (visas, blessures, roster non déposé) et ça évite surtout de simuler un
	# match à trois joueurs quand une structure s'est effondrée.
	var home_short := home.lineup.size() < module.team_size()
	var away_short := away.lineup.size() < module.team_size()
	if home_short or away_short:
		return _forfeit(world, f, home, away, home_short, away_short)

	var ctx := MatchContext.new()
	ctx.home = home
	ctx.away = away
	ctx.best_of = f.best_of
	ctx.day = f.day
	ctx.rng = world.rng.derive("fixture:" + f.id)
	ctx.competition_id = f.competition_id
	ctx.competition_name = comp.name if comp != null else ""
	ctx.round_label = f.round_label
	ctx.prestige = comp.prestige if comp != null else 3000
	ctx.is_lan = f.is_lan
	ctx.importance = f.importance
	if module is ValorantModule:
		ctx.map_pool = (module as ValorantModule).active_map_pool()
	# On ne conserve le détail round par round que pour les matchs du joueur.
	ctx.detailed = _is_player_match(world, f)

	var res := module.create_simulator().simulate(ctx)
	res.fixture_id = f.id
	apply_result(world, f, res)
	return res


static func _is_player_match(world: World, f: Fixture) -> bool:
	if world.player_org_id == "":
		return false
	for rid in [f.home_id, f.away_id]:
		var r := world.roster(rid)
		if r != null and r.org_id == world.player_org_id:
			return true
	return false


## Forfait : score sec, sanction financière et perte de réputation.
static func _forfeit(world: World, f: Fixture, home: TeamSheet, away: TeamSheet,
		home_short: bool, away_short: bool) -> MatchResult:
	var res := MatchResult.new()
	res.fixture_id = f.id
	res.competition_id = f.competition_id
	res.day = f.day
	res.home_id = f.home_id
	res.away_id = f.away_id
	var needed := int(f.best_of / 2) + 1
	if home_short and away_short:
		res.home_score = 0
		res.away_score = 0
		res.winner_id = f.home_id     # double forfait : personne ne progresse
		res.loser_id = f.away_id
	elif home_short:
		res.away_score = needed
		res.winner_id = f.away_id
		res.loser_id = f.home_id
	else:
		res.home_score = needed
		res.winner_id = f.home_id
		res.loser_id = f.away_id
	res.headline = "Forfait — %s ne peut pas aligner cinq joueurs." % (
		home.name() if home_short else away.name())

	for sheet in [home, away]:
		var short: bool = (sheet == home and home_short) or (sheet == away and away_short)
		if not short or sheet.org == null:
			continue
		sheet.org.ledger.debit(world.today, Money.from_units(5_000.0),
			Transaction.Category.LEAGUE_FEE, "Amende pour forfait", "")
		sheet.org.reputation = maxi(sheet.org.reputation - 60, 50)
		if world.player_org_id == sheet.org.id:
			world.add_news(world.today, "Forfait déclaré",
				"Faute d'un cinq complet, la rencontre est perdue par forfait "
				+ "et une amende de 5 000 $ est appliquée.", "warning")
	apply_result(world, f, res)
	return res
