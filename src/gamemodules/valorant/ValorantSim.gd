class_name ValorantSim
extends MatchSimulator

## Simulation d'une série VALORANT, round par round.
##
## Pourquoi round par round plutôt qu'un simple tirage sur la force des deux
## équipes ? Parce que c'est l'économie qui fait Valorant : un pistol perdu
## coûte deux rounds, un force-buy raté en coûte trois, et une équipe menée
## 3-9 qui gagne un bonus peut renverser une mi-temps. Simuler la série de
## rounds produit gratuitement des scores crédibles (13-11, 13-4, 14-12),
## des statistiques individuelles cohérentes et un récit à afficher.
##
## Économie officielle reproduite :
##   départ 800 · plafond 9000 · victoire +3000 · défaite +1900/+2400/+2900
##   frag +200 · pose du spike +300 · l'équipement des survivants est conservé.

const START_CREDITS := 800
const MAX_CREDITS := 9000
const WIN_REWARD := 3000
const LOSS_BONUS := [1900, 2400, 2900]
const KILL_REWARD := 200
const PLANT_REWARD := 300
const FULL_BUY_COST := 4200
const FORCE_BUY_COST := 2600
const ECO_COST := 900

const ROUNDS_TO_WIN := 13
const HALF := 12

# Pondérations de la formule de round. Regroupées ici : ce sont les seuls
# chiffres à toucher pour rééquilibrer la simulation.
const W_SKILL := 0.115        # par point d'écart de note d'équipe (1..20)
const W_SIDE := 4.20          # biais attaque/défense propre à la map
const W_ECON := 1.60          # écart d'économie (-0.85..0.85)
const W_MOMENTUM := 0.22
const W_PREP := 0.40          # avantage de préparation (analyste)
const W_PISTOL_SKILL := 0.055 # le pistol est beaucoup plus aléatoire

var _m: ValorantModule


func _init(module: ValorantModule = null) -> void:
	_m = module if module != null else ValorantModule.new()




# ============================================================================
# Construction des notes d'équipe
# ============================================================================

func _build_side(sheet: TeamSheet) -> ValorantSide:
	var s := ValorantSide.new()
	s.sheet = sheet
	s.players = sheet.lineup.duplicate()
	s.prep = sheet.prep_level

	var n := maxi(s.players.size(), 1)
	var fire := 0.0
	var util := 0.0
	var sense := 0.0
	var anch := 0.0
	var pos := 0.0
	var ent := 0.0
	var clu := 0.0
	var eco := 0.0
	var comp := 0.0
	var team := 0.0
	var comm := 0.0

	for p in s.players:
		var cond := p.condition_multiplier()
		var f := (float(p.attr(ValorantModule.AIM)) * 0.34
			+ float(p.attr(ValorantModule.DUELLING)) * 0.26
			+ float(p.attr(ValorantModule.CROSSHAIR)) * 0.22
			+ float(p.attr(ValorantModule.SPRAY)) * 0.10
			+ float(p.attr(Attributes.REACTION)) * 0.08) * cond
		fire += f
		s.power.append(maxf(f, 1.0))
		util += float(p.attr(ValorantModule.UTILITY)) * cond
		sense += float(p.attr(ValorantModule.GAME_SENSE)) * cond
		anch += float(p.attr(ValorantModule.ANCHORING)) * cond
		pos += float(p.attr(ValorantModule.POSITIONING)) * cond
		ent += float(p.attr(ValorantModule.ENTRY)) * cond
		clu += float(p.attr(ValorantModule.CLUTCH)) * cond
		eco += float(p.attr(ValorantModule.ECONOMY))
		comp += float(p.attr(Attributes.COMPOSURE))
		team += float(p.attr(Attributes.TEAMWORK))
		comm += float(p.attr(Attributes.COMMUNICATION))

	s.firepower = fire / n
	s.utility = util / n
	s.anchoring = anch / n
	s.positioning = pos / n
	s.entry = ent / n
	s.clutch = clu / n
	s.composure = comp / n

	# Apport du capitaine en jeu : lecture, appels, gestion de l'éco.
	var igl := sheet.igl()
	var igl_bonus := 0.0
	if igl != null:
		igl_bonus = (float(igl.attr(Attributes.LEADERSHIP)) * 0.4
			+ float(igl.attr(ValorantModule.MID_ROUND)) * 0.4
			+ float(igl.attr(Attributes.DECISION_MAKING)) * 0.2)
		s.eco_iq = (eco / n) * 0.6 + float(igl.attr(ValorantModule.ECONOMY)) * 0.4
	else:
		s.eco_iq = eco / n

	# Apport du staff : le coach porte la tactique, l'analyste la préparation.
	var coach_tac := 8.0
	var coach_man := 8.0
	if sheet.coach != null:
		coach_tac = float(sheet.coach.attr(Staff.TACTICAL))
		coach_man = float(sheet.coach.attr(Staff.MAN_MANAGEMENT))
	var analyst_val := 6.0
	if sheet.analyst != null:
		analyst_val = float(sheet.analyst.attr(Staff.ANALYSIS))

	s.tactical = (sense / n) * 0.46 + igl_bonus * 0.24 + coach_tac * 0.20 + analyst_val * 0.10
	s.cohesion = (sheet.chemistry / 5.0) * 0.42 + (team / n) * 0.28 \
		+ (comm / n) * 0.20 + coach_man * 0.10
	return s


## Confort de l'équipe sur une map (1..20) : moyenne du cinq.
func _map_comfort(s: ValorantSide, map_name: String) -> float:
	var total := 0.0
	var n := 0
	for p in s.players:
		var maps: Dictionary = p.game_data.get("maps", {})
		total += float(maps.get(map_name, 10))
		n += 1
	return total / maxf(float(n), 1.0)


## Note offensive et défensive sur une map donnée.
func _side_rating(s: ValorantSide, map_name: String, attacking: bool) -> float:
	var info := _m.map_info(map_name)
	var util_w := float(info.get("util_weight", 1.0))
	var comfort := _map_comfort(s, map_name)
	var base: float
	if attacking:
		base = s.firepower * 0.36 + s.utility * util_w * 0.22 \
			+ s.tactical * 0.22 + s.entry * 0.10 + s.cohesion * 0.10
	else:
		base = s.firepower * 0.33 + s.anchoring * 0.17 + s.positioning * 0.14 \
			+ s.utility * util_w * 0.13 + s.tactical * 0.15 + s.cohesion * 0.08
	# Le confort de map vaut environ +/- 1 point de note.
	return base + (comfort - 10.0) * 0.10


# ============================================================================
# Veto de maps
# ============================================================================

## Reproduit le veto officiel : bans alternés, picks alternés, decider.
## Chaque équipe bannit la map où son différentiel est le pire et choisit
## celle où il est le meilleur — avec un peu de bruit, car les vraies équipes
## se trompent aussi.
func _veto(ctx: MatchContext, home: ValorantSide, away: ValorantSide) -> Array:
	var pool: Array[String] = ctx.map_pool.duplicate()
	if pool.is_empty():
		pool = _m.active_map_pool()
	var log_lines: Array = []
	var picks: Array = []

	var diff := {}
	for mn in pool:
		var h := _map_comfort(home, mn)
		var a := _map_comfort(away, mn)
		diff[mn] = h - a + ctx.rng.gauss(0.0, 0.9)

	var order := _veto_order(ctx.best_of)
	for step in order:
		if pool.size() <= 1:
			break
		var by_home: bool = step["home"]
		var action: String = step["action"]
		var best_map := ""
		var best_score := -INF
		for mn in pool:
			var d := float(diff[mn])
			var score := (-d if by_home else d) if action == "ban" else (d if by_home else -d)
			if score > best_score:
				best_score = score
				best_map = mn
		pool.erase(best_map)
		var tag: String = home.sheet.tag() if by_home else away.sheet.tag()
		if action == "ban":
			log_lines.append("%s retire %s" % [tag, best_map])
		else:
			log_lines.append("%s choisit %s" % [tag, best_map])
			picks.append({"map": best_map,
				"picked_by": home.sheet.id() if by_home else away.sheet.id()})

	if not pool.is_empty():
		log_lines.append("Map décisive : %s" % pool[0])
		picks.append({"map": pool[0], "picked_by": ""})
	return [picks, log_lines]


func _veto_order(best_of: int) -> Array:
	match best_of:
		1:
			return [
				{"home": true, "action": "ban"}, {"home": false, "action": "ban"},
				{"home": true, "action": "ban"}, {"home": false, "action": "ban"},
				{"home": true, "action": "ban"}, {"home": false, "action": "ban"},
			]
		5:
			return [
				{"home": true, "action": "ban"}, {"home": false, "action": "ban"},
				{"home": true, "action": "pick"}, {"home": false, "action": "pick"},
				{"home": true, "action": "pick"}, {"home": false, "action": "pick"},
			]
		_:
			return [
				{"home": true, "action": "ban"}, {"home": false, "action": "ban"},
				{"home": true, "action": "pick"}, {"home": false, "action": "pick"},
				{"home": true, "action": "ban"}, {"home": false, "action": "ban"},
			]


# ============================================================================
# Série
# ============================================================================

func simulate(ctx: MatchContext) -> MatchResult:
	var home := _build_side(ctx.home)
	var away := _build_side(ctx.away)

	var res := MatchResult.new()
	res.day = ctx.day
	res.competition_id = ctx.competition_id
	res.home_id = home.sheet.id()
	res.away_id = away.sheet.id()

	var veto := _veto(ctx, home, away)
	var map_plan: Array = veto[0]
	res.veto_log = veto[1]

	var needed := int(ctx.best_of / 2) + 1
	for entry in map_plan:
		if res.home_score >= needed or res.away_score >= needed:
			break
		var mr := _simulate_map(ctx, home, away, str(entry["map"]), str(entry["picked_by"]))
		res.maps.append(mr)
		if mr.winner_is_home():
			res.home_score += 1
		else:
			res.away_score += 1

	res.winner_id = res.home_id if res.home_score > res.away_score else res.away_id
	res.loser_id = res.away_id if res.home_score > res.away_score else res.home_id

	_aggregate_series_stats(res, home, away)
	res.mvp_id = _pick_mvp(res)
	res.headline = _headline(res, home, away)
	if not ctx.detailed:
		res.compact()
	return res


# ============================================================================
# Simulation d'une map
# ============================================================================

func _simulate_map(ctx: MatchContext, home: ValorantSide, away: ValorantSide,
		map_name: String, picked_by: String) -> MapResult:
	var mr := MapResult.new()
	mr.map_name = map_name
	mr.picked_by = picked_by

	# Le choix du camp revient à l'équipe qui n'a pas choisi la map.
	# Sur la plupart des maps, on démarre en défense.
	var info := _m.map_info(map_name)
	var atk_bias := float(info.get("atk_win_rate", 0.5))
	if picked_by == "":
		mr.home_started_attack = ctx.rng.chance(0.5)
	elif picked_by == home.sheet.id():
		mr.home_started_attack = atk_bias > 0.5   # away choisit son camp
	else:
		mr.home_started_attack = atk_bias >= 0.5

	home.reset_economy(START_CREDITS)
	away.reset_economy(START_CREDITS)

	var stats := {}
	for p in home.players:
		stats[p.id] = MatchResult.empty_stats()
	for p in away.players:
		stats[p.id] = MatchResult.empty_stats()

	var hr := 0
	var ar := 0
	var round_num := 1
	while round_num <= 60:
		var home_attacking := _home_attacking(round_num, mr.home_started_attack)
		var is_pistol := (round_num == 1 or round_num == HALF + 1)
		if round_num == HALF + 1:
			# Mi-temps : les économies repartent de zéro.
			home.reset_economy(START_CREDITS)
			away.reset_economy(START_CREDITS)

		var atk: ValorantSide = home if home_attacking else away
		var def: ValorantSide = away if home_attacking else home
		var r := _simulate_round(ctx, atk, def, stats, map_name,
			round_num, is_pistol, hr, ar, home_attacking)

		var home_won: bool = (r["atk_won"] and home_attacking) or \
			(not r["atk_won"] and not home_attacking)
		if home_won:
			hr += 1
		else:
			ar += 1

		if ctx.detailed:
			mr.rounds.append({
				"n": round_num,
				"winner": "home" if home_won else "away",
				"type": r["type"],
				"home_side": "atk" if home_attacking else "def",
				"score": "%d-%d" % [hr, ar],
				"plant": r["plant"],
				"text": r["text"],
			})

		if maxi(hr, ar) >= ROUNDS_TO_WIN and absi(hr - ar) >= 2:
			break
		if round_num >= 24 and hr == ar and hr < 12:
			break   # garde-fou : ne devrait jamais arriver
		round_num += 1

	mr.home_rounds = hr
	mr.away_rounds = ar
	mr.overtime = (hr + ar) > 24
	_finalise_map_stats(stats, hr + ar)
	mr.player_stats = stats
	return mr


func _home_attacking(round_num: int, home_started_attack: bool) -> bool:
	if round_num <= HALF:
		return home_started_attack
	if round_num <= HALF * 2:
		return not home_started_attack
	var ot_index := round_num - (HALF * 2 + 1)
	return home_started_attack if (ot_index % 2 == 0) else not home_started_attack


## Décision d'achat. C'est ici que se joue la moitié du jeu : une équipe qui
## gère mal son économie enchaîne les demi-buys et perd des rounds gagnables.
func _decide_buy(s: ValorantSide, is_pistol: bool, must_win: bool, rng: Rng) -> Dictionary:
	if is_pistol:
		return {"type": "pistol", "econ": 0.5, "spend": 0}

	var effective := s.credits + s.saved_value
	var buy_power := clampf(float(effective - 800) / 3600.0, 0.0, 1.0)

	if effective >= FULL_BUY_COST:
		var spend: int = mini(s.credits, FULL_BUY_COST)
		return {"type": "full", "econ": 0.15 + 0.85 * buy_power, "spend": spend}

	# Forcer ou épargner ? Un IGL lucide épargne pour un vrai buy au round
	# suivant ; une équipe paniquée force et se retrouve à sec deux rounds.
	var eco_policy := float(s.sheet.tactic.get("eco_policy", 50))
	var judgement := clampf((s.eco_iq - 10.0) / 10.0, -1.0, 1.0)
	var force_urge := (eco_policy - 50.0) / 100.0 + (0.35 if must_win else 0.0) \
		- judgement * 0.18 + rng.range_f(-0.12, 0.12)
	var can_force := effective >= FORCE_BUY_COST

	if can_force and force_urge > 0.0:
		return {"type": "force", "econ": 0.15 + 0.85 * buy_power * 0.75,
			"spend": mini(s.credits, FORCE_BUY_COST)}

	# Save : on garde les crédits, l'économie du round est faible mais on
	# prépare un vrai buy.
	var eco_econ := 0.12 + 0.30 * clampf(float(s.saved_value) / 6000.0, 0.0, 1.0)
	return {"type": "eco", "econ": eco_econ, "spend": mini(s.credits, ECO_COST)}


# ============================================================================
# Simulation d'un round
# ============================================================================

func _simulate_round(ctx: MatchContext, atk: ValorantSide, def: ValorantSide, stats: Dictionary,
		map_name: String, round_num: int, is_pistol: bool,
		hr: int, ar: int, home_attacking: bool) -> Dictionary:
	var rng := ctx.rng
	var atk_score: int = hr if home_attacking else ar
	var def_score: int = ar if home_attacking else hr

	var atk_buy := _decide_buy(atk, is_pistol, def_score >= 12, rng)
	var def_buy := _decide_buy(def, is_pistol, atk_score >= 12, rng)

	var info := _m.map_info(map_name)
	var atk_rating := _side_rating(atk, map_name, true)
	var def_rating := _side_rating(def, map_name, false)

	var skill_w := W_PISTOL_SKILL if is_pistol else W_SKILL
	var x := (atk_rating - def_rating) * skill_w
	x += (float(info.get("atk_win_rate", 0.5)) - 0.5) * W_SIDE
	if not is_pistol:
		x += (float(atk_buy["econ"]) - float(def_buy["econ"])) * W_ECON
	x += (atk.tilt() - def.tilt()) * W_MOMENTUM
	x += (atk.prep - def.prep) * W_PREP

	var p := clampf(Rng.logistic(x), 0.04, 0.96)
	var atk_won := rng.chance(p)

	# --- Économie ------------------------------------------------------------
	atk.credits -= int(atk_buy["spend"])
	def.credits -= int(def_buy["spend"])

	var closeness := 1.0 - absf(p - 0.5) * 2.0
	var winner: ValorantSide = atk if atk_won else def
	var loser: ValorantSide = def if atk_won else atk
	var loser_deaths: int = rng.weighted_pick([5, 4, 3], [0.68, 0.22, 0.10])
	var winner_deaths: int = rng.weighted_pick([0, 1, 2, 3, 4], [
		1.0 - 0.70 * closeness, 0.90, 0.50 + 0.90 * closeness,
		0.25 + 0.90 * closeness, 0.10 + 0.70 * closeness,
	])

	var planted := false
	if atk_won:
		planted = rng.chance(0.86)
	else:
		planted = rng.chance(0.34)
	var defused := (not atk_won) and planted and rng.chance(0.55)

	var ev := _resolve_kills(rng, winner, loser, stats, winner_deaths, loser_deaths,
		atk_won, atk, def, planted, defused)

	# --- Récompenses ---------------------------------------------------------
	winner.credits += WIN_REWARD
	winner.loss_streak = 0
	loser.credits += LOSS_BONUS[mini(loser.loss_streak, 2)]
	loser.loss_streak += 1
	winner.credits += int(round(float(loser_deaths) * KILL_REWARD / 5.0))
	loser.credits += int(round(float(winner_deaths) * KILL_REWARD / 5.0))
	if planted:
		atk.credits += PLANT_REWARD
	atk.credits = clampi(atk.credits, 0, MAX_CREDITS)
	def.credits = clampi(def.credits, 0, MAX_CREDITS)

	# Le matériel des survivants est conservé pour le round suivant.
	var w_survivors := 5 - winner_deaths
	var l_survivors := 5 - loser_deaths
	winner.saved_value = int(round(float(w_survivors) / 5.0 * float(
		_buy_value(winner == atk, atk_buy, def_buy)) * 0.9))
	loser.saved_value = int(round(float(l_survivors) / 5.0 * float(
		_buy_value(loser == atk, atk_buy, def_buy)) * 0.9))
	winner.last_buy = str(atk_buy["type"] if winner == atk else def_buy["type"])
	loser.last_buy = str(atk_buy["type"] if loser == atk else def_buy["type"])

	# --- Momentum et temps mort ---------------------------------------------
	winner.momentum = clampf(winner.momentum * 0.75 + 0.34, -1.0, 1.0)
	loser.momentum = clampf(loser.momentum * 0.75 - 0.30, -1.0, 1.0)
	var timeout_text := ""
	if loser.loss_streak >= 3 and loser.timeouts > 0 and loser.sheet.coach != null:
		loser.timeouts -= 1
		var quality := float(loser.sheet.coach.attr(Staff.MAN_MANAGEMENT)) / 20.0
		loser.momentum = lerpf(loser.momentum, 0.0, 0.5 + 0.4 * quality)
		winner.momentum *= 0.55
		timeout_text = "%s pose un temps mort." % loser.sheet.tag()

	var rtype := str(atk_buy["type"] if atk_won else def_buy["type"])
	var text := ""
	if ctx.detailed:
		text = _round_text(round_num, is_pistol, rtype, winner, loser, ev,
			planted, defused, atk_won, timeout_text)

	return {"atk_won": atk_won, "type": rtype, "plant": planted,
		"defuse": defused, "text": text}


func _buy_value(is_atk: bool, atk_buy: Dictionary, def_buy: Dictionary) -> int:
	return int(atk_buy["spend"]) if is_atk else int(def_buy["spend"])


## Répartit frags, morts, assists, dégâts et faits marquants du round.
func _resolve_kills(rng: Rng, winner: ValorantSide, loser: ValorantSide, stats: Dictionary,
		winner_deaths: int, loser_deaths: int, atk_won: bool,
		atk: ValorantSide, def: ValorantSide, planted: bool, defused: bool) -> Dictionary:
	var w_kill_w := winner.power.duplicate()
	var l_kill_w := loser.power.duplicate()
	var w_death_w := _death_weights(winner)
	var l_death_w := _death_weights(loser)

	var l_dead := _pick_unique(rng, loser.players.size(), l_death_w, loser_deaths)
	var w_dead := _pick_unique(rng, winner.players.size(), w_death_w, winner_deaths)

	var round_kills := {}
	var fk_id := ""
	var fk_victim := ""

	# Duel d'ouverture : l'équipe qui gagne le round le prend le plus souvent.
	var winner_takes_fk := rng.chance(0.63)
	if l_dead.is_empty():
		winner_takes_fk = false
	if w_dead.is_empty():
		winner_takes_fk = true

	var first_done := false
	for vi in l_dead:
		var victim: Player = loser.players[vi]
		var ki: int = _pick_index(rng, w_kill_w)
		var killer: Player = winner.players[ki]
		_credit_kill(rng, stats, killer, victim, winner, round_kills)
		if winner_takes_fk and not first_done:
			fk_id = killer.id
			fk_victim = victim.id
			first_done = true

	for vi in w_dead:
		var victim2: Player = winner.players[vi]
		var ki2: int = _pick_index(rng, l_kill_w)
		var killer2: Player = loser.players[ki2]
		_credit_kill(rng, stats, killer2, victim2, loser, round_kills)
		if not winner_takes_fk and not first_done:
			fk_id = killer2.id
			fk_victim = victim2.id
			first_done = true

	if fk_id != "":
		stats[fk_id]["first_kills"] += 1
		stats[fk_victim]["first_deaths"] += 1

	# Round joué : dégâts d'usure, KAST, ace, multikill.
	var ace_id := ""
	for s in [winner, loser]:
		var side: ValorantSide = s
		var dead_ids := {}
		for vi in (w_dead if side == winner else l_dead):
			dead_ids[side.players[vi].id] = true
		for p in side.players:
			var st: Dictionary = stats[p.id]
			st["rounds"] += 1
			st["damage"] += rng.range_i(8, 62)
			var k: int = int(round_kills.get(p.id, 0))
			if k >= 3:
				st["multikills"] += 1
			if k >= 5:
				st["aces"] += 1
				ace_id = p.id
			var survived: bool = not dead_ids.has(p.id)
			var traded: bool = (not survived) and side == winner and rng.chance(0.55)
			if k > 0 or survived or traded or rng.chance(0.10):
				st["kast_rounds"] += 1

	# Pose / désamorçage
	if planted:
		var planter: Player = atk.players[_pick_index(rng, _support_weights(atk))]
		stats[planter.id]["plants"] += 1
	if defused:
		var defuser: Player = def.players[_pick_index(rng, _support_weights(def))]
		stats[defuser.id]["defuses"] += 1

	# Clutch : le round s'est terminé en infériorité numérique.
	var clutch_id := ""
	if winner_deaths >= 3:
		var best := -1
		var best_k := -1
		for i in winner.players.size():
			if w_dead.has(i):
				continue
			var kk: int = int(round_kills.get(winner.players[i].id, 0))
			if kk > best_k:
				best_k = kk
				best = i
		if best >= 0:
			var hero: Player = winner.players[best]
			stats[hero.id]["clutch_attempts"] += 1
			stats[hero.id]["clutches"] += 1
			clutch_id = hero.id
	if loser_deaths >= 4 and rng.chance(0.35):
		var idx := _pick_index(rng, loser.power)
		stats[loser.players[idx].id]["clutch_attempts"] += 1

	return {"fk_id": fk_id, "fk_victim": fk_victim, "ace_id": ace_id,
		"clutch_id": clutch_id}


func _credit_kill(rng: Rng, stats: Dictionary, killer: Player, victim: Player,
		killer_side: ValorantSide, round_kills: Dictionary) -> void:
	stats[killer.id]["kills"] += 1
	stats[victim.id]["deaths"] += 1
	stats[killer.id]["damage"] += rng.range_i(118, 172)
	round_kills[killer.id] = int(round_kills.get(killer.id, 0)) + 1
	if rng.chance(0.42):
		var helper_i := _pick_index(rng, _support_weights(killer_side))
		var helper: Player = killer_side.players[helper_i]
		if helper.id != killer.id:
			stats[helper.id]["assists"] += 1
	if rng.chance(0.28):
		stats[killer.id]["headshots"] += 1


## Probabilité de mourir : les joueurs agressifs et les entry meurent plus.
func _death_weights(s: ValorantSide) -> Array[float]:
	var out: Array[float] = []
	for p in s.players:
		var w := 1.0 \
			+ float(p.attr(Attributes.AGGRESSION) + p.attr(ValorantModule.ENTRY)) / 40.0 \
			- float(p.attr(ValorantModule.POSITIONING) + p.attr(Attributes.COMPOSURE)) / 55.0
		out.append(maxf(w, 0.15))
	return out


## Poids « joueur de soutien » : utilitaires et esprit d'équipe.
func _support_weights(s: ValorantSide) -> Array[float]:
	var out: Array[float] = []
	for p in s.players:
		out.append(maxf(float(p.attr(ValorantModule.UTILITY)
			+ p.attr(Attributes.TEAMWORK)) / 2.0, 1.0))
	return out


func _pick_index(rng: Rng, weights: Array) -> int:
	var total := 0.0
	for w in weights:
		total += maxf(float(w), 0.0)
	if total <= 0.0:
		return rng.range_i(0, maxi(weights.size() - 1, 0))
	var r := rng.randf() * total
	for i in weights.size():
		r -= maxf(float(weights[i]), 0.0)
		if r <= 0.0:
			return i
	return weights.size() - 1


func _pick_unique(rng: Rng, count_total: int, weights: Array, n: int) -> Array[int]:
	var pool: Array[float] = []
	for w in weights:
		pool.append(maxf(float(w), 0.0))
	var out: Array[int] = []
	for _i in mini(n, count_total):
		var idx := _pick_index(rng, pool)
		out.append(idx)
		pool[idx] = 0.0
	return out


# ============================================================================
# Notes et statistiques
# ============================================================================

## Références de la discipline : un joueur exactement dans la moyenne obtient
## une note de 1.00. Ces constantes sont les repères d'équilibrage des stats.
const REF_KPR := 0.62
const REF_DPR := 0.62
const REF_APR := 0.26
const REF_KAST := 0.72
const REF_ADR := 125.0
const REF_FKPR := 0.10


func _finalise_map_stats(stats: Dictionary, total_rounds: int) -> void:
	for pid in stats:
		compute_derived(stats[pid])


## Calcule ACS et note à partir des compteurs bruts. Public : réutilisé pour
## les cumuls de saison et de carrière.
static func compute_derived(st: Dictionary) -> void:
	var r := maxf(float(st.get("rounds", 0)), 1.0)
	var kpr := float(st["kills"]) / r
	var dpr := float(st["deaths"]) / r
	var apr := float(st["assists"]) / r
	var kast := float(st["kast_rounds"]) / r
	var adr := float(st["damage"]) / r
	var fkpr := float(st["first_kills"]) / r

	st["acs"] = (float(st["damage"]) * 1.25 + float(st["kills"]) * 25.0
		+ float(st["assists"]) * 30.0 + float(st["first_kills"]) * 20.0
		+ float(st["multikills"]) * 25.0) / r

	var rating := 0.30 * (kpr / REF_KPR) \
		+ 0.20 * (kast / REF_KAST) \
		+ 0.20 * (adr / REF_ADR) \
		+ 0.10 * (apr / REF_APR) \
		+ 0.12 * (REF_DPR / maxf(dpr, 0.30)) \
		+ 0.08 * (fkpr / REF_FKPR)
	# Ces bonus doivent être des TAUX, sinon la note enfle mécaniquement avec le
	# nombre de matchs cumulés et sature sur un bilan de saison.
	rating += 0.90 * (float(st["clutches"]) / r) + 1.50 * (float(st["aces"]) / r)
	st["rating"] = clampf(rating, 0.15, 2.6)


func _aggregate_series_stats(res: MatchResult, home: ValorantSide, away: ValorantSide) -> void:
	var team_of := {}
	for p in home.players:
		team_of[p.id] = home.sheet.id()
	for p in away.players:
		team_of[p.id] = away.sheet.id()

	var totals := {}
	for m in res.maps:
		for pid in m.player_stats:
			if not totals.has(pid):
				totals[pid] = MatchResult.empty_stats()
			MatchResult.add_stats(totals[pid], m.player_stats[pid])
	for pid in totals:
		compute_derived(totals[pid])
		totals[pid]["team"] = team_of.get(pid, "")
	res.player_stats = totals


## Le MVP sort presque toujours du camp vainqueur : on applique un bonus
## plutôt qu'une règle absolue, pour laisser passer les performances énormes
## dans la défaite.
func _pick_mvp(res: MatchResult) -> String:
	var best := ""
	var best_score := -INF
	for pid in res.player_stats:
		var st: Dictionary = res.player_stats[pid]
		var score := float(st.get("rating", 0.0))
		if str(st.get("team", "")) == res.winner_id:
			score += 0.18
		if score > best_score:
			best_score = score
			best = pid
	return best


func _headline(res: MatchResult, home: ValorantSide, away: ValorantSide) -> String:
	var w_name: String = home.sheet.name() if res.winner_id == res.home_id else away.sheet.name()
	var l_name: String = away.sheet.name() if res.winner_id == res.home_id else home.sheet.name()
	var score := "%d-%d" % [maxi(res.home_score, res.away_score),
		mini(res.home_score, res.away_score)]
	var tight := absi(res.home_score - res.away_score) <= 1 and res.maps.size() >= 3
	if tight:
		return "%s s'impose au bout du suspense face à %s (%s)" % [w_name, l_name, score]
	if res.maps.size() >= 2 and mini(res.home_score, res.away_score) == 0:
		return "%s ne laisse aucune chance à %s (%s)" % [w_name, l_name, score]
	return "%s bat %s %s" % [w_name, l_name, score]


func _round_text(n: int, is_pistol: bool, rtype: String, winner: ValorantSide, loser: ValorantSide,
		ev: Dictionary, planted: bool, defused: bool, atk_won: bool,
		timeout_text: String) -> String:
	var tag := winner.sheet.tag()
	var parts: Array[String] = []
	if is_pistol:
		parts.append("Pistol pour %s." % tag)
	elif rtype == "eco":
		parts.append("%s convertit un eco." % tag)
	elif rtype == "force":
		parts.append("Force buy payant pour %s." % tag)
	else:
		parts.append("%s prend le round." % tag)

	if str(ev.get("ace_id", "")) != "":
		parts.append("ACE de %s !" % _name_of(winner, str(ev["ace_id"])))
	elif str(ev.get("clutch_id", "")) != "":
		parts.append("%s clutch." % _name_of(winner, str(ev["clutch_id"])))
	elif str(ev.get("fk_id", "")) != "":
		parts.append("Ouverture %s." % _name_of_any(winner, loser, str(ev["fk_id"])))

	if defused:
		parts.append("Défuse.")
	elif planted and atk_won:
		parts.append("Spike posé.")
	if timeout_text != "":
		parts.append(timeout_text)
	return " ".join(parts)


func _name_of(s: ValorantSide, pid: String) -> String:
	for p in s.players:
		if p.id == pid:
			return p.display_name()
	return "?"


func _name_of_any(a: ValorantSide, b: ValorantSide, pid: String) -> String:
	var n := _name_of(a, pid)
	if n != "?":
		return n
	return _name_of(b, pid)
