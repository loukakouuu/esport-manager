class_name Cs2Sim
extends MatchSimulator

## Simulation d'une série COUNTER-STRIKE 2, round par round.
##
## Même principe que le simulateur Valorant — c'est l'économie qui fait le jeu,
## donc on simule la suite de rounds plutôt que de tirer un vainqueur sur la
## force des deux équipes — mais trois mécaniques sont propres à CS et
## changent réellement les scores produits :
##
## 1. **Les maps sont CT-sided.** Toutes, sans exception (voir maps.json). Un
##    12-0 côté CT suivi d'un effondrement en T est un scénario courant de CS
##    et sort tout seul du biais de map.
## 2. **L'AWP.** 4 750 $ pour une arme qui gagne un round à elle seule, mais
##    qu'on ne rachète pas quand on est à sec. Elle est donc modélisée dans
##    l'ÉCONOMIE, pas comme un bonus d'attribut : une équipe qui perd son
##    AWPeur tôt perd aussi l'arme, et le round suivant avec.
## 3. **Le bonus de défaite monte à 3 400 $ et la pose de bombe paie même en
##    perdant** (800 $ par joueur). Une équipe menée peut donc remonter son
##    économie sans gagner un round — c'est ce qui rend les anti-ecos
##    dangereuses et les scores serrés plus fréquents qu'en Valorant.
##
## Économie officielle CS2 reproduite :
##   départ 800 · plafond 16 000 · victoire +3 250 (+250 si la bombe décide)
##   défaite +1 400 / 1 750 / 2 100 / 2 450 / 2 900 · frag +300
##   pose de bombe +300 au poseur, +800 par joueur si l'équipe perd après pose

const START_MONEY := 800
const MAX_MONEY := 16000
const WIN_REWARD := 3250
const BOMB_WIN_BONUS := 250
const LOSS_BONUS := [1400, 1750, 2100, 2450, 2900]
const KILL_REWARD := 300
const PLANT_REWARD := 300
const PLANT_LOSS_BONUS := 800
const FULL_BUY_COST := 4750
const AWP_EXTRA_COST := 1600      # surcoût de l'AWP par rapport à un fusil
const FORCE_BUY_COST := 2600
const ECO_COST := 1100

const ROUNDS_TO_WIN := 13
const HALF := 12
## Prolongation MR3 : six rounds, camps échangés tous les trois.
const OT_BLOCK := 3

# Pondérations de la formule de round. Ce sont les seuls chiffres à toucher
# pour rééquilibrer la simulation.
const W_SKILL := 0.118        # par point d'écart de note d'équipe (1..20)
const W_SIDE := 4.20          # biais T/CT propre à la map
const W_ECON := 1.85          # l'économie pèse plus lourd qu'en Valorant
const W_AWP := 0.62           # différentiel d'AWP réellement en jeu
const W_MOMENTUM := 0.22
const W_PREP := 0.42          # avantage de préparation (analyste)
const W_PISTOL_SKILL := 0.052 # le pistol est beaucoup plus aléatoire

var _m: Cs2Module


func _init(module: Cs2Module = null) -> void:
	_m = module if module != null else Cs2Module.new()


# ============================================================================
# Construction des notes d'équipe
# ============================================================================

func _build_side(sheet: TeamSheet) -> Cs2Side:
	var s := Cs2Side.new()
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
	var lrk := 0.0
	var clu := 0.0
	var eco := 0.0
	var comp := 0.0
	var team := 0.0
	var comm := 0.0

	for i in s.players.size():
		var p: Player = s.players[i]
		var cond := p.condition_multiplier()
		# La puissance de feu CS est plus « brute » qu'en Valorant : pas de
		# compétence pour compenser un duel perdu, d'où le poids du spray.
		var f := (float(p.attr(Cs2Module.AIM)) * 0.34
			+ float(p.attr(Cs2Module.DUELLING)) * 0.24
			+ float(p.attr(Cs2Module.CROSSHAIR)) * 0.20
			+ float(p.attr(Cs2Module.SPRAY)) * 0.14
			+ float(p.attr(Attributes.REACTION)) * 0.08) * cond
		fire += f
		s.power.append(maxf(f, 1.0))
		util += float(p.attr(Cs2Module.UTILITY)) * cond
		sense += float(p.attr(Cs2Module.GAME_SENSE)) * cond
		anch += float(p.attr(Cs2Module.ANCHORING)) * cond
		pos += float(p.attr(Cs2Module.POSITIONING)) * cond
		ent += float(p.attr(Cs2Module.ENTRY)) * cond
		lrk += float(p.attr(Cs2Module.LURKING)) * cond
		clu += float(p.attr(Cs2Module.CLUTCH)) * cond
		eco += float(p.attr(Cs2Module.ECONOMY))
		comp += float(p.attr(Attributes.COMPOSURE))
		team += float(p.attr(Attributes.TEAMWORK))
		comm += float(p.attr(Attributes.COMMUNICATION))

		# On retient le MEILLEUR sniper du cinq, pas la moyenne : l'AWP se
		# tient à une seule paire de mains.
		var snipe := float(p.attr(Cs2Module.SNIPING)) * cond
		if s.awp_index < 0 or snipe > s.awp_skill:
			s.awp_skill = snipe
			s.awp_index = i

	s.firepower = fire / n
	s.utility = util / n
	s.anchoring = anch / n
	s.positioning = pos / n
	s.entry = ent / n
	s.lurk = lrk / n
	s.clutch = clu / n
	s.composure = comp / n

	# Apport du capitaine en jeu : appels de milieu de round et gestion de
	# l'argent, qui compte davantage en CS qu'en Valorant.
	var igl := sheet.igl()
	var igl_bonus := 0.0
	if igl != null:
		igl_bonus = (float(igl.attr(Attributes.LEADERSHIP)) * 0.38
			+ float(igl.attr(Cs2Module.MID_ROUND)) * 0.38
			+ float(igl.attr(Attributes.DECISION_MAKING)) * 0.24)
		s.eco_iq = (eco / n) * 0.55 + float(igl.attr(Cs2Module.ECONOMY)) * 0.45
	else:
		s.eco_iq = eco / n

	var coach_tac := 8.0
	var coach_man := 8.0
	if sheet.coach != null:
		coach_tac = float(sheet.coach.attr(Staff.TACTICAL))
		coach_man = float(sheet.coach.attr(Staff.MAN_MANAGEMENT))
	var analyst_val := 6.0
	if sheet.analyst != null:
		analyst_val = float(sheet.analyst.attr(Staff.ANALYSIS))

	s.tactical = (sense / n) * 0.44 + igl_bonus * 0.26 + coach_tac * 0.20 \
		+ analyst_val * 0.10
	s.cohesion = (sheet.chemistry / 5.0) * 0.42 + (team / n) * 0.28 \
		+ (comm / n) * 0.20 + coach_man * 0.10
	return s


## Confort de l'équipe sur une map (1..20) : moyenne du cinq.
func _map_comfort(s: Cs2Side, map_name: String) -> float:
	var total := 0.0
	var n := 0
	for p in s.players:
		var maps: Dictionary = p.game_data.get("maps", {})
		total += float(maps.get(map_name, 10))
		n += 1
	return total / maxf(float(n), 1.0)


## Note d'un camp sur une map donnée. Le lurk ne compte qu'en T (on lurke pour
## couper une rotation, pas pour tenir un site) et la tenue de site qu'en CT :
## c'est exactement ce qui fait qu'une équipe peut être 11-1 CT et 2-9 T.
func _side_rating(s: Cs2Side, map_name: String, terrorist: bool) -> float:
	var info := _m.map_info(map_name)
	var util_w := float(info.get("util_weight", 1.0))
	var comfort := _map_comfort(s, map_name)
	var base: float
	if terrorist:
		base = s.firepower * 0.35 + s.utility * util_w * 0.18 \
			+ s.tactical * 0.21 + s.entry * 0.11 + s.lurk * 0.06 \
			+ s.cohesion * 0.09
	else:
		base = s.firepower * 0.33 + s.anchoring * 0.18 + s.positioning * 0.15 \
			+ s.utility * util_w * 0.11 + s.tactical * 0.15 + s.cohesion * 0.08
	# Le confort de map vaut environ +/- 1 point de note.
	return base + (comfort - 10.0) * 0.10


## Ce que l'AWP rapporte réellement ce round : le niveau du sniper, pondéré
## par la map, et NUL si l'arme n'est pas en jeu. Elle vaut un peu plus en CT,
## où elle tient un angle au lieu de devoir prendre l'espace.
func _awp_value(s: Cs2Side, map_name: String, terrorist: bool) -> float:
	if not s.has_awp or s.awp_index < 0:
		return 0.0
	var w := float(_m.map_info(map_name).get("awp_weight", 1.0))
	return ((s.awp_skill - 10.0) / 10.0 + 0.45) * w * (0.85 if terrorist else 1.0)


# ============================================================================
# Veto de maps
# ============================================================================

## Veto officiel CS : bans alternés, picks alternés, decider. Chaque équipe
## retire la map où son différentiel est le pire et choisit celle où il est le
## meilleur — avec du bruit, parce que les vraies équipes se trompent aussi.
func _veto(ctx: MatchContext, home: Cs2Side, away: Cs2Side) -> Array:
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

	for step in _veto_order(ctx.best_of):
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
		var mr := _simulate_map(ctx, home, away, str(entry["map"]),
			str(entry["picked_by"]))
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

func _simulate_map(ctx: MatchContext, home: Cs2Side, away: Cs2Side,
		map_name: String, picked_by: String) -> MapResult:
	var mr := MapResult.new()
	mr.map_name = map_name
	mr.picked_by = picked_by

	# Le choix du camp revient à l'équipe qui n'a PAS choisi la map. Comme
	# toutes les maps de CS sont CT-sided, ce choix est toujours le même : on
	# commence CT. C'est une règle, pas un hasard.
	if picked_by == "":
		mr.home_started_attack = ctx.rng.chance(0.5)
	elif picked_by == home.sheet.id():
		mr.home_started_attack = true     # away prend le CT
	else:
		mr.home_started_attack = false    # home prend le CT

	home.reset_economy(START_MONEY)
	away.reset_economy(START_MONEY)

	var stats := {}
	for p in home.players:
		stats[p.id] = MatchResult.empty_stats()
	for p in away.players:
		stats[p.id] = MatchResult.empty_stats()

	var hr := 0
	var ar := 0
	var round_num := 1
	while round_num <= 60:
		var home_t := _home_is_t(round_num, mr.home_started_attack)
		var is_pistol := _is_pistol_round(round_num)
		if is_pistol and round_num > 1:
			# Mi-temps et chaque prolongation : les économies repartent à zéro.
			home.reset_economy(START_MONEY)
			away.reset_economy(START_MONEY)

		var atk: Cs2Side = home if home_t else away
		var def: Cs2Side = away if home_t else home
		var r := _simulate_round(ctx, atk, def, stats, map_name,
			round_num, is_pistol, hr, ar, home_t)

		var home_won: bool = (r["atk_won"] and home_t) or \
			(not r["atk_won"] and not home_t)
		if home_won:
			hr += 1
		else:
			ar += 1

		if ctx.detailed:
			mr.rounds.append({
				"n": round_num,
				"winner": "home" if home_won else "away",
				"type": r["type"],
				"home_side": "T" if home_t else "CT",
				"score": "%d-%d" % [hr, ar],
				"plant": r["plant"],
				"text": r["text"],
			})

		if _map_over(hr, ar):
			break
		round_num += 1

	mr.home_rounds = hr
	mr.away_rounds = ar
	mr.overtime = (hr + ar) > HALF * 2
	_finalise_map_stats(stats)
	mr.player_stats = stats
	return mr


## MR12 : premier à 13, 12-12 va en prolongation. Chaque prolongation est un
## bloc de six rounds (MR3) : le palier de victoire monte de trois à chaque
## fois — 16, puis 19, puis 22.
static func _map_over(hr: int, ar: int) -> bool:
	var hi := maxi(hr, ar)
	var lo := mini(hr, ar)
	if hi < ROUNDS_TO_WIN:
		return false
	if lo <= HALF - 1:
		return true                        # 13-11 ou mieux, temps réglementaire
	var target := ROUNDS_TO_WIN + OT_BLOCK
	while target <= hi:
		if lo < target:
			return true
		target += OT_BLOCK
	return false


## Round de pistolet : le premier de chaque mi-temps et le premier de chaque
## bloc de prolongation.
static func _is_pistol_round(round_num: int) -> bool:
	if round_num == 1 or round_num == HALF + 1:
		return true
	if round_num <= HALF * 2:
		return false
	return (round_num - HALF * 2 - 1) % (OT_BLOCK * 2) == 0


static func _home_is_t(round_num: int, home_started_t: bool) -> bool:
	if round_num <= HALF:
		return home_started_t
	if round_num <= HALF * 2:
		return not home_started_t
	var block := int((round_num - HALF * 2 - 1) / OT_BLOCK)
	return home_started_t if (block % 2 == 0) else not home_started_t


## Décision d'achat. C'est ici que se joue la moitié de Counter-Strike : un
## demi-buy raté coûte trois rounds, et l'AWP est le premier arbitrage.
func _decide_buy(s: Cs2Side, is_pistol: bool, must_win: bool, rng: Rng) -> Dictionary:
	if is_pistol:
		s.has_awp = false
		return {"type": "pistol", "econ": 0.5, "spend": 0}

	var effective := s.money + s.saved_value
	var buy_power := clampf(float(effective - 1000) / 5200.0, 0.0, 1.0)
	var awp_pref := clampf(float(s.sheet.tactic.get("awp_priority", 50)) / 100.0,
		0.0, 1.0) * clampf((s.awp_skill - 6.0) / 12.0, 0.0, 1.0)

	if effective >= FULL_BUY_COST:
		var spend: int = mini(s.money, FULL_BUY_COST)
		# L'AWP se rachète si la caisse suit ; sinon on la garde d'un round à
		# l'autre quand son porteur a survécu (c'est `has_awp` déjà à true).
		if s.awp_index >= 0 and not s.has_awp \
				and effective >= FULL_BUY_COST + AWP_EXTRA_COST \
				and rng.chance(0.35 + 0.55 * awp_pref):
			s.has_awp = true
			spend = mini(s.money, FULL_BUY_COST + AWP_EXTRA_COST)
		return {"type": "full", "econ": 0.15 + 0.85 * buy_power, "spend": spend}

	# Forcer ou épargner ? Un IGL lucide épargne ; une équipe paniquée force et
	# se retrouve à sec deux rounds de suite.
	var eco_policy := float(s.sheet.tactic.get("eco_policy", 45))
	var judgement := clampf((s.eco_iq - 10.0) / 10.0, -1.0, 1.0)
	var force_urge := (eco_policy - 50.0) / 100.0 + (0.35 if must_win else 0.0) \
		- judgement * 0.20 + rng.range_f(-0.12, 0.12)

	if effective >= FORCE_BUY_COST and force_urge > 0.0:
		# Un achat incomplet après un round GAGNÉ n'est pas un force buy mais
		# un « bonus » : le vocabulaire compte dans le compte rendu.
		var kind := "bonus" if s.loss_streak == 0 else "force"
		return {"type": kind, "econ": 0.15 + 0.85 * buy_power * 0.72,
			"spend": mini(s.money, FORCE_BUY_COST)}

	# Save : on garde l'argent, le round est perdu d'avance mais le suivant est
	# un vrai buy. Une équipe qui a sauvé du matériel part moins nue.
	s.has_awp = s.has_awp and rng.chance(0.55)
	var eco_econ := 0.10 + 0.30 * clampf(float(s.saved_value) / 7000.0, 0.0, 1.0)
	return {"type": "eco", "econ": eco_econ, "spend": mini(s.money, ECO_COST)}


# ============================================================================
# Simulation d'un round
# ============================================================================

func _simulate_round(ctx: MatchContext, atk: Cs2Side, def: Cs2Side,
		stats: Dictionary, map_name: String, round_num: int, is_pistol: bool,
		hr: int, ar: int, home_t: bool) -> Dictionary:
	var rng := ctx.rng
	var atk_score: int = hr if home_t else ar
	var def_score: int = ar if home_t else hr

	var atk_buy := _decide_buy(atk, is_pistol, def_score >= HALF, rng)
	var def_buy := _decide_buy(def, is_pistol, atk_score >= HALF, rng)

	var info := _m.map_info(map_name)
	var atk_rating := _side_rating(atk, map_name, true)
	var def_rating := _side_rating(def, map_name, false)

	var skill_w := W_PISTOL_SKILL if is_pistol else W_SKILL
	var x := (atk_rating - def_rating) * skill_w
	x += (float(info.get("atk_win_rate", 0.47)) - 0.5) * W_SIDE
	if not is_pistol:
		x += (float(atk_buy["econ"]) - float(def_buy["econ"])) * W_ECON
		x += (_awp_value(atk, map_name, true) - _awp_value(def, map_name, false)) \
			* W_AWP
	x += (atk.tilt() - def.tilt()) * W_MOMENTUM
	x += (atk.prep - def.prep) * W_PREP

	var p := clampf(Rng.logistic(x), 0.04, 0.96)
	var atk_won := rng.chance(p)

	# --- Économie ------------------------------------------------------------
	atk.money -= int(atk_buy["spend"])
	def.money -= int(def_buy["spend"])

	var closeness := 1.0 - absf(p - 0.5) * 2.0
	var winner: Cs2Side = atk if atk_won else def
	var loser: Cs2Side = def if atk_won else atk
	var loser_deaths: int = rng.weighted_pick([5, 4, 3], [0.70, 0.21, 0.09])
	var winner_deaths: int = rng.weighted_pick([0, 1, 2, 3, 4], [
		1.0 - 0.70 * closeness, 0.90, 0.50 + 0.90 * closeness,
		0.25 + 0.90 * closeness, 0.10 + 0.70 * closeness,
	])

	# La bombe : posée dans la grande majorité des rounds T gagnés, et dans un
	# tiers des rounds T perdus — c'est ce plant-là qui finance la remontée.
	var planted := rng.chance(0.88) if atk_won else rng.chance(0.33)
	var defused := (not atk_won) and planted and rng.chance(0.52)

	var ev := _resolve_kills(rng, winner, loser, stats, winner_deaths,
		loser_deaths, atk_won, atk, def, planted, defused)

	# --- Récompenses ---------------------------------------------------------
	winner.money += WIN_REWARD + (BOMB_WIN_BONUS if (planted and atk_won) \
		or defused else 0)
	winner.loss_streak = 0
	loser.money += LOSS_BONUS[mini(loser.loss_streak, LOSS_BONUS.size() - 1)]
	loser.loss_streak += 1
	winner.money += int(round(float(loser_deaths) * KILL_REWARD / 5.0))
	loser.money += int(round(float(winner_deaths) * KILL_REWARD / 5.0))
	if planted:
		atk.money += PLANT_REWARD
		if not atk_won:
			# Poser la bombe et perdre quand même rapporte : c'est la règle qui
			# permet à une équipe menée de se refaire sans gagner un round.
			atk.money += PLANT_LOSS_BONUS
	atk.money = clampi(atk.money, 0, MAX_MONEY)
	def.money = clampi(def.money, 0, MAX_MONEY)

	# Le matériel des survivants est conservé pour le round suivant.
	var w_survivors := 5 - winner_deaths
	var l_survivors := 5 - loser_deaths
	winner.saved_value = int(round(float(w_survivors) / 5.0 * float(
		_buy_value(winner == atk, atk_buy, def_buy)) * 0.9))
	loser.saved_value = int(round(float(l_survivors) / 5.0 * float(
		_buy_value(loser == atk, atk_buy, def_buy)) * 0.9))
	winner.last_buy = str(atk_buy["type"] if winner == atk else def_buy["type"])
	loser.last_buy = str(atk_buy["type"] if loser == atk else def_buy["type"])
	# L'AWP suit son porteur : s'il tombe, l'arme reste sur le sol.
	_carry_awp(winner, ev, true)
	_carry_awp(loser, ev, false)

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
		text = _round_text(is_pistol, rtype, winner, loser, ev, planted,
			defused, atk_won, timeout_text)

	return {"atk_won": atk_won, "type": rtype, "plant": planted,
		"defuse": defused, "text": text}


## L'AWP est perdue si son porteur est mort ce round.
func _carry_awp(s: Cs2Side, ev: Dictionary, _is_winner: bool) -> void:
	if not s.has_awp or s.awp_index < 0:
		return
	var dead: Dictionary = ev.get("dead_ids", {})
	if dead.has(s.players[s.awp_index].id):
		s.has_awp = false


func _buy_value(is_atk: bool, atk_buy: Dictionary, def_buy: Dictionary) -> int:
	return int(atk_buy["spend"]) if is_atk else int(def_buy["spend"])


## Répartit frags, morts, assists, dégâts et faits marquants du round.
func _resolve_kills(rng: Rng, winner: Cs2Side, loser: Cs2Side, stats: Dictionary,
		winner_deaths: int, loser_deaths: int, atk_won: bool,
		atk: Cs2Side, def: Cs2Side, planted: bool, defused: bool) -> Dictionary:
	var w_kill_w := _kill_weights(winner)
	var l_kill_w := _kill_weights(loser)
	var w_death_w := _death_weights(winner)
	var l_death_w := _death_weights(loser)

	var l_dead := _pick_unique(rng, loser.players.size(), l_death_w, loser_deaths)
	var w_dead := _pick_unique(rng, winner.players.size(), w_death_w, winner_deaths)

	var round_kills := {}
	var fk_id := ""
	var fk_victim := ""

	# Duel d'ouverture : l'équipe qui gagne le round le prend le plus souvent.
	var winner_takes_fk := rng.chance(0.64)
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
	var dead_all := {}
	var ace_id := ""
	for s in [winner, loser]:
		var side: Cs2Side = s
		var dead_ids := {}
		for vi in (w_dead if side == winner else l_dead):
			dead_ids[side.players[vi].id] = true
			dead_all[side.players[vi].id] = true
		for p in side.players:
			var st: Dictionary = stats[p.id]
			st["rounds"] += 1
			# Dégâts sans frag : grenades et duels perdus de peu. Calibré pour
			# que l'ADR moyen tombe sur REF_ADR.
			st["damage"] += rng.range_i(2, 30)
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
		"clutch_id": clutch_id, "dead_ids": dead_all}


func _credit_kill(rng: Rng, stats: Dictionary, killer: Player, victim: Player,
		killer_side: Cs2Side, round_kills: Dictionary) -> void:
	stats[killer.id]["kills"] += 1
	stats[victim.id]["deaths"] += 1
	# Un frag ne vaut pas 100 dégâts : la cible a souvent déjà pris du chip
	# d'un coéquipier, et les dégâts se partagent. Calibré sur REF_ADR.
	stats[killer.id]["damage"] += rng.range_i(68, 112)
	round_kills[killer.id] = int(round_kills.get(killer.id, 0)) + 1
	# Moins d'assists qu'en Valorant : pas de compétence qui « prépare » un
	# frag, seulement une grenade ou un demi-duel.
	if rng.chance(0.24):
		var helper_i := _pick_index(rng, _support_weights(killer_side))
		var helper: Player = killer_side.players[helper_i]
		if helper.id != killer.id:
			stats[helper.id]["assists"] += 1
	# Le taux de têtes de CS est élevé : l'AK tue en un coup à la tête.
	if rng.chance(0.47):
		stats[killer.id]["headshots"] += 1


## Poids de frag. L'AWPeur qui a son arme en main frappe nettement plus fort :
## c'est ce qui produit des lignes « 28-12 » sur une seule paire de mains.
func _kill_weights(s: Cs2Side) -> Array[float]:
	var out: Array[float] = []
	for i in s.players.size():
		var w := s.power[i] if i < s.power.size() else 10.0
		if s.has_awp and i == s.awp_index:
			w *= 1.0 + clampf((s.awp_skill - 8.0) / 24.0, 0.0, 0.55)
		out.append(maxf(w, 0.15))
	return out


## Probabilité de mourir : les joueurs agressifs et les entry meurent plus.
func _death_weights(s: Cs2Side) -> Array[float]:
	var out: Array[float] = []
	for p in s.players:
		var w := 1.0 \
			+ float(p.attr(Attributes.AGGRESSION) + p.attr(Cs2Module.ENTRY)) / 40.0 \
			- float(p.attr(Cs2Module.POSITIONING) + p.attr(Attributes.COMPOSURE)) / 55.0
		out.append(maxf(w, 0.15))
	return out


## Poids « joueur de soutien » : grenades et esprit d'équipe.
func _support_weights(s: Cs2Side) -> Array[float]:
	var out: Array[float] = []
	for p in s.players:
		out.append(maxf(float(p.attr(Cs2Module.UTILITY)
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
## une note de 1.00. Elles ne sont PAS celles de Valorant — on assiste beaucoup
## moins, et les dégâts par round sont bien plus bas (100 points de vie contre
## 150 shield compris).
##
## Ces valeurs sont MESURÉES sur une saison complète, pas devinées : voir
## `tools/discipline_probe.gd`, qui imprime K/round, D/round, KAST et dégâts
## par discipline. Les recopier ici est ce qui garantit qu'un joueur moyen sort
## à 1.00 — la note est une position dans la distribution, pas un barème
## absolu, et une constante inventée décalerait toute la discipline.
const REF_KPR := 0.63
const REF_DPR := 0.645
const REF_APR := 0.15
const REF_KAST := 0.68
const REF_ADR := 73.0
const REF_OKPR := 0.10


func _finalise_map_stats(stats: Dictionary) -> void:
	for pid in stats:
		compute_derived(stats[pid])


## Calcule ADR, KAST et note à partir des compteurs bruts. Public : réutilisé
## pour les cumuls de saison et de carrière.
##
## La somme des poids vaut exactement 1,0 : un joueur pile dans les références
## sort donc à 1.00, par construction et pas par étalonnage.
static func compute_derived(st: Dictionary) -> void:
	var r := maxf(float(st.get("rounds", 0)), 1.0)
	var kpr := float(st["kills"]) / r
	var dpr := float(st["deaths"]) / r
	var apr := float(st["assists"]) / r
	var kast := float(st["kast_rounds"]) / r
	var adr := float(st["damage"]) / r
	var okpr := float(st["first_kills"]) / r

	st["adr"] = adr
	st["kast"] = kast * 100.0
	# `acs` est la colonne générique du moteur : on y met l'ADR pour que tout
	# code qui l'affiche sans connaître la discipline montre un chiffre juste.
	st["acs"] = adr

	var rating := 0.34 * (kpr / REF_KPR) \
		+ 0.18 * (kast / REF_KAST) \
		+ 0.22 * (adr / REF_ADR) \
		+ 0.06 * (apr / REF_APR) \
		+ 0.12 * (REF_DPR / maxf(dpr, 0.30)) \
		+ 0.08 * (okpr / REF_OKPR)
	# Ces bonus sont des TAUX : un cumul de saison ne doit pas enfler avec le
	# nombre de matchs joués.
	rating += 0.85 * (float(st["clutches"]) / r) + 1.50 * (float(st["aces"]) / r)
	st["rating"] = clampf(rating, 0.15, 2.6)


func _aggregate_series_stats(res: MatchResult, home: Cs2Side, away: Cs2Side) -> void:
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


## Le MVP sort presque toujours du camp vainqueur : bonus plutôt que règle
## absolue, pour laisser passer les performances énormes dans la défaite.
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


func _headline(res: MatchResult, home: Cs2Side, away: Cs2Side) -> String:
	var w_name: String = home.sheet.name() if res.winner_id == res.home_id \
		else away.sheet.name()
	var l_name: String = away.sheet.name() if res.winner_id == res.home_id \
		else home.sheet.name()
	var score := "%d-%d" % [maxi(res.home_score, res.away_score),
		mini(res.home_score, res.away_score)]
	for m in res.maps:
		if m.overtime:
			return "%s arrache la série face à %s après prolongation (%s)" \
				% [w_name, l_name, score]
	if res.maps.size() >= 2 and mini(res.home_score, res.away_score) == 0:
		return "%s ne laisse aucune chance à %s (%s)" % [w_name, l_name, score]
	if absi(res.home_score - res.away_score) <= 1 and res.maps.size() >= 3:
		return "%s s'impose au bout du suspense face à %s (%s)" \
			% [w_name, l_name, score]
	return "%s bat %s %s" % [w_name, l_name, score]


func _round_text(is_pistol: bool, rtype: String, winner: Cs2Side, loser: Cs2Side,
		ev: Dictionary, planted: bool, defused: bool, atk_won: bool,
		timeout_text: String) -> String:
	var tag := winner.sheet.tag()
	var parts: Array[String] = []
	if is_pistol:
		parts.append("Pistol pour %s." % tag)
	elif rtype == "eco":
		parts.append("%s convertit un eco." % tag)
	elif rtype == "bonus":
		parts.append("%s convertit son bonus." % tag)
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
		parts.append("Bombe désamorcée.")
	elif planted and atk_won:
		parts.append("Bombe explosée.")
	elif planted:
		parts.append("Bombe posée pour rien.")
	if timeout_text != "":
		parts.append(timeout_text)
	return " ".join(parts)


func _name_of(s: Cs2Side, pid: String) -> String:
	for p in s.players:
		if p.id == pid:
			return p.display_name()
	return "?"


func _name_of_any(a: Cs2Side, b: Cs2Side, pid: String) -> String:
	var n := _name_of(a, pid)
	if n != "?":
		return n
	return _name_of(b, pid)
