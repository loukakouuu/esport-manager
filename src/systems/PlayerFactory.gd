class_name PlayerFactory
extends RefCounted

## Génération de joueurs.
##
## Méthode : on part d'une CIBLE de capacité (CA) et on redescend vers les
## attributs — l'inverse de ce qu'on fait pendant la carrière, où les attributs
## évoluent et la CA se recalcule. Cela garantit qu'un « joueur de 145 » se
## comporte comme tel dans la simulation, quel que soit son rôle.
##
## Les attributs CACHÉS (personnalité, régularité, résistance au burnout) sont
## tirés INDÉPENDAMMENT de la CA : c'est ce qui crée les talents ingérables et
## les besogneux surperformants — la matière première du jeu de gestion.

const NAMES_PATH := "res://data/world/names.json"

## Barème de salaire annuel en $ selon la CA. Courbe exponentielle calée sur
## le marché réel Valorant : minimum VCT ~65 k$, titulaire tier 1 ~150-250 k$,
## superstar 600 k$ - 1,5 M$, Challengers 12-45 k$.
static func salary_for_ca(ca: int, reputation: int = 0) -> int:
	var base := exp(float(ca - 85) / 21.0) * 9000.0
	base *= 1.0 + clampf(float(reputation) / 10000.0, 0.0, 1.0) * 0.35
	return Money.from_units(base)


## Valeur marchande (base de la clause de rachat).
static func market_value_for(ca: int, pa: int, age: int, reputation: int) -> int:
	var salary := float(Money.to_units(salary_for_ca(ca, reputation)))
	var mult := 1.9
	# Un joueur jeune avec une grosse marge vaut bien plus que son salaire.
	var headroom := float(maxi(pa - ca, 0)) / 60.0
	if age <= 20:
		mult += 1.8 * headroom + 0.5
	elif age <= 23:
		mult += 1.2 * headroom + 0.2
	elif age >= 27:
		mult -= 0.45
	elif age >= 25:
		mult -= 0.2
	mult = maxf(mult, 0.6)
	return Money.from_units(salary * mult)


static func _names() -> Dictionary:
	return DataFile.load_json(NAMES_PATH, {"regions": {}}) as Dictionary


static func make_gamertag(rng: Rng) -> String:
	var n := _names()
	if rng.chance(0.45):
		return str(rng.pick(n.get("tag_solo", ["Player"])))
	var pre := str(rng.pick(n.get("tag_prefixes", ["Zen"])))
	var suf := str(rng.pick(n.get("tag_suffixes", [""])))
	var tag := pre + suf
	if rng.chance(0.12):
		tag += str(rng.range_i(1, 99))
	return tag


## Génère un joueur complet.
## opts : {target_ca:int, age:int, region:String, role:String, igl:bool,
##         potential_bonus:int, reputation:int}
static func create(rng: Rng, module: GameModule, ids: Ids, today: int,
		opts: Dictionary = {}) -> Player:
	var p := Player.new()
	p.id = ids.next(Ids.PLAYER)
	p.game_id = module.id()

	var region := str(opts.get("region", "EMEA"))
	p.region = region
	var n := _names()
	var reg: Dictionary = (n.get("regions", {}) as Dictionary).get(region, {})
	p.nationality = str(rng.pick(reg.get("countries", ["FR"])))
	p.first_name = str(rng.pick(reg.get("first", ["Alex"])))
	p.last_name = str(rng.pick(reg.get("last", ["Martin"])))
	p.gamertag = make_gamertag(rng)

	var age: int = int(opts.get("age", rng.gauss_i(21.5, 2.6, 16, 32)))
	p.birth_day = GameDate.add_days(GameDate.add_years(today, -age), -rng.range_i(0, 364))

	# Rôle
	var role := str(opts.get("role", ""))
	if role == "":
		role = str(rng.pick(module.roles()))
	p.primary_role = role
	for r in module.roles():
		p.roles[r] = 4 + rng.range_i(0, 6)
	p.roles[role] = rng.gauss_i(17.0, 1.8, 12, 20)
	p.is_igl = bool(opts.get("igl", false))

	var target_ca := int(opts.get("target_ca", rng.gauss_i(105.0, 22.0, 40, 190)))
	target_ca = clampi(target_ca, 20, 195)

	_roll_attributes(rng, module, p, target_ca)
	_roll_hidden(rng, p, age)

	AbilityCalc.refresh(p, module)
	p.potential_ability = _roll_potential(rng, p.current_ability, age,
		int(opts.get("potential_bonus", 0)))

	p.reputation = int(opts.get("reputation", _reputation_for(p.current_ability, rng)))
	p.fan_appeal = clampi(rng.gauss_i(
		float(p.current_ability) / 4.0, 12.0, 1, 100), 1, 100)
	p.market_value = market_value_for(p.current_ability, p.potential_ability, age, p.reputation)
	p.form = rng.gauss(50.0, 9.0, 25.0, 78.0)
	p.morale = rng.gauss(62.0, 10.0, 25.0, 92.0)
	p.sharpness = rng.gauss(55.0, 10.0, 20.0, 85.0)
	p.game_data = module.generate_game_data(p, rng)
	_roll_traits(rng, p)
	return p


## Distribue les attributs pour atteindre la CA visée.
## On tire d'abord un profil bruité autour de la moyenne cible, puis on corrige
## itérativement : chaque joueur garde donc des pics et des trous personnels
## tout en respectant sa note globale.
static func _roll_attributes(rng: Rng, module: GameModule, p: Player, target_ca: int) -> void:
	var keys: Array[String] = []
	keys.append_array(module.attribute_keys())
	keys.append_array(Attributes.common_visible())
	var mean := clampf(float(target_ca) / 10.0, 1.5, 19.0)
	for k in keys:
		p.set_attr(k, rng.gauss_i(mean, 2.6, 1, 20))

	var weights := module.role_weights(p.primary_role)
	for _pass in 8:
		var ca := AbilityCalc.compute_ca(p, module)
		var delta := target_ca - ca
		if absi(delta) <= 2:
			break
		var step := clampf(float(delta) / 10.0, -2.0, 2.0)
		for k in weights:
			var cur := float(p.attr(k))
			# On pousse en priorité les attributs qui comptent pour le rôle.
			var w := clampf(float(weights[k]) / 3.0, 0.2, 1.0)
			p.set_attr(k, int(round(cur + step * w)))


## Attributs cachés : la personnalité n'a rien à voir avec le talent.
static func _roll_hidden(rng: Rng, p: Player, age: int) -> void:
	for k in Attributes.HIDDEN:
		p.set_attr(k, rng.gauss_i(11.0, 3.4, 1, 20))
	# La maturité vient avec l'âge, pas avec le niveau.
	var maturity := clampf(float(age - 17) / 10.0, 0.0, 1.0)
	p.set_attr(Attributes.PROFESSIONALISM,
		Attributes.clamp_value(p.attr(Attributes.PROFESSIONALISM) + int(maturity * 3.0)))
	p.set_attr(Attributes.PRESSURE,
		Attributes.clamp_value(p.attr(Attributes.PRESSURE) + int(maturity * 2.0)))
	# Les très jeunes brûlent plus vite s'ils sont mal encadrés.
	if age <= 19:
		p.set_attr(Attributes.BURNOUT_RESISTANCE,
			Attributes.clamp_value(p.attr(Attributes.BURNOUT_RESISTANCE) - 2))


## Potentiel : une marge de progression que l'âge referme vite. Dans l'esport,
## un joueur de 24 ans a déjà quasiment atteint son plafond.
static func _roll_potential(rng: Rng, ca: int, age: int, bonus: int) -> int:
	var headroom_by_age := {
		16: 75, 17: 68, 18: 60, 19: 52, 20: 44, 21: 36, 22: 28,
		23: 20, 24: 13, 25: 8, 26: 5, 27: 3,
	}
	var base: int = int(headroom_by_age.get(clampi(age, 16, 27), 2))
	var roll := rng.gauss(float(base) * 0.55, float(base) * 0.40, 0.0, float(base) * 1.35)
	return clampi(ca + int(round(roll)) + bonus, ca, 200)


static func _reputation_for(ca: int, rng: Rng) -> int:
	var base := clampf(pow(float(ca) / 200.0, 2.2) * 9000.0, 10.0, 9500.0)
	return int(clampf(rng.gauss(base, base * 0.22), 5.0, 10000.0))


## Traits : des marqueurs de comportement lisibles par le joueur et utilisés
## par les systèmes (simulation, moral, négociation).
const TRAITS := {
	"clutch_monster": {"attr": "clutch", "min": 16, "chance": 0.55},
	"tilts_easily": {"attr": "composure", "max": 8, "chance": 0.55},
	"shot_caller": {"attr": "leadership", "min": 16, "chance": 0.50},
	"streamer": {"attr": "", "chance": 0.14},
	"prima_donna": {"attr": "ego", "min": 17, "chance": 0.50},
	"grinder": {"attr": "work_ethic", "min": 17, "chance": 0.50},
	"slow_starter": {"attr": "consistency", "max": 8, "chance": 0.30},
	"big_game_player": {"attr": "big_match", "min": 17, "chance": 0.50},
	"injury_prone": {"attr": "injury_proneness", "min": 16, "chance": 0.45},
	"lone_wolf": {"attr": "teamwork", "max": 7, "chance": 0.40},
	"utility_wizard": {"attr": "utility", "min": 17, "chance": 0.45},
	"aim_god": {"attr": "aim", "min": 18, "chance": 0.50},
}

const TRAIT_LABELS := {
	"clutch_monster": "Monstre de clutch",
	"tilts_easily": "Tilt facilement",
	"shot_caller": "Meneur naturel",
	"streamer": "Streamer",
	"prima_donna": "Ego surdimensionné",
	"grinder": "Bosseur acharné",
	"slow_starter": "Démarrage lent",
	"big_game_player": "Joueur des grands soirs",
	"injury_prone": "Fragile",
	"lone_wolf": "Solitaire",
	"utility_wizard": "Maître des utilitaires",
	"aim_god": "Visée d'exception",
}


static func _roll_traits(rng: Rng, p: Player) -> void:
	for t in TRAITS:
		var cfg: Dictionary = TRAITS[t]
		var key := str(cfg.get("attr", ""))
		var ok := true
		if key != "":
			var v := p.attr(key)
			if cfg.has("min") and v < int(cfg["min"]):
				ok = false
			if cfg.has("max") and v > int(cfg["max"]):
				ok = false
		if ok and rng.chance(float(cfg.get("chance", 0.1))):
			p.traits.append(t)


static func trait_label(t: String) -> String:
	return TRAIT_LABELS.get(t, t.capitalize())
