class_name WorldGenerator
extends RefCounted

## Création d'un monde de départ complet et cohérent.
##
## Cohérent veut dire : le niveau des rosters, la réputation, la fanbase, la
## trésorerie, les sponsors signés et les infrastructures d'une structure
## découlent tous d'un même indice de puissance. Un club du bas de tableau de
## Challengers ne peut donc pas se retrouver avec la trésorerie d'une équipe
## VCT — la simulation économique reste crédible dès le premier jour.
##
## LA GÉNÉRATION SE FAIT EN QUATRE PASSES, et l'ordre n'est pas négociable :
##
##   1. les structures et leur section Valorant ;
##   2. les sections des AUTRES disciplines simulées — Counter-Strike
##      aujourd'hui. Une ligne de `orgs_cs2.json` dont le nom existe déjà
##      OUVRE UNE SECTION dans la maison existante au lieu d'inventer une
##      structure : c'est ce qui donne des écuries à deux rosters sur un seul
##      grand livre. Les autres lignes créent des structures 100 % CS ;
##   3. la marque, réévaluée en fonction du nombre de sections tenues ;
##   4. l'encadrement, les sponsors et la trésorerie de départ.
##
## La passe 4 vient EN DERNIER parce que la trésorerie de départ vaut un
## nombre de mois de charges RÉELLES. La calculer avant la section CS2
## donnerait à une maison à deux rosters la trésorerie d'une maison à un seul,
## et elle déposerait le bilan avant l'été.

const ORGS_PATH := "res://data/world/orgs.json"

## Régions du monde, dans l'ordre où elles sont peuplées.
const REGIONS: Array[String] = ["EMEA", "AMERICAS", "PACIFIC", "CHINA"]

## Nombre d'équipes par région dans la discipline de référence (Valorant :
## 12 + 12 + 10). Sert d'échelle au vivier d'agents libres des autres
## disciplines : une discipline deux fois plus petite n'a pas besoin d'un
## vivier deux fois trop grand.
const REFERENCE_TEAMS_PER_REGION := 34.0

## Correspondance indice de puissance (0-100) -> capacité moyenne du roster.
## 40 -> CA 78 (Challengers bas de tableau) · 88 -> CA 158 (top mondial)
static func ca_for_strength(strength: float) -> float:
	return 45.0 + strength * 1.28


static func generate(seed_value: int, start_day: int,
		player_org_name: String = "") -> World:
	var world := World.new()
	world.seed_value = seed_value
	# On grave le pack utilisé : rejouer une sauvegarde avec un autre contenu
	# afficherait des noms qui ne correspondraient plus à rien.
	world.data_pack = DataPack.active()
	world.rng = Rng.new(seed_value)
	world.today = start_day
	world.start_day = start_day
	world.season_year = GameDate.year_of(start_day)

	var module := GameRegistry.get_module("valorant")
	# org_id -> indice de puissance de sa discipline mère. Gardé le temps de la
	# génération : la passe « encadrement et sponsors » en a besoin, et le
	# World n'a aucune raison de le conserver ensuite.
	var strengths := {}

	var data := DataFile.load_json(module.orgs_path(), {"leagues": {}}) as Dictionary
	var leagues: Dictionary = data.get("leagues", {})
	for league_key in leagues:
		var region := _region_of(league_key)
		var entries: Array = leagues[league_key]
		var spread := _uniform_strength(entries)
		for entry_v in entries:
			var o := _make_org(world, module, str(league_key), region, entry_v,
				spread)
			strengths[o.id] = float(entry_v.get("strength", 50))

	# Passe 2 : les sections des autres disciplines simulées.
	for game_id in GameRegistry.all_ids():
		if game_id == module.id():
			continue
		_build_sections(world, GameRegistry.get_module(game_id), strengths)
	_honour_declared_games(world, strengths)

	# Passe 3 : une maison à deux sections n'a pas la même surface qu'une
	# maison à une seule.
	_apply_section_brand(world)

	# Passe 4 : encadrement, sponsors, trésorerie — sur le périmètre COMPLET.
	for oid in world.orgs:
		_finish_org(world, world.orgs[oid], float(strengths.get(oid, 50.0)))

	SeasonBuilder.build_season(world, world.season_year)
	for m in GameRegistry.all_modules():
		_make_free_agents(world, m)
	StaffSystem.seed_market(world)
	Log.i("worldgen", "Monde généré : %d structures, %d équipes, %d joueurs, "
		% [world.orgs.size(), world.rosters.size(), world.players.size()]
		+ "%d compétitions" % world.competitions.size())
	return world


## Un pack qui donne la MÊME force à toutes les équipes d'une ligue ne déclare
## aucune hiérarchie — c'est le cas du pack VCT, parce que « Fnatic est plus
## fort que BBL » n'est pas une donnée publique et que l'inventer dans les
## données reviendrait à l'affirmer.
##
## Le jeu en fabrique donc une, dérivée de la graine, exactement comme il
## fabrique les attributs : elle change d'une partie à l'autre, ce qui dit bien
## qu'elle est inventée. Sans ça les douze équipes d'une ligue seraient
## rigoureusement interchangeables — même réputation, même trésorerie, même
## niveau — et le championnat n'aurait plus aucun relief.
static func _uniform_strength(entries: Array) -> bool:
	if entries.size() < 3:
		return false
	var first := float((entries[0] as Dictionary).get("strength", 50))
	for e in entries:
		if absf(float((e as Dictionary).get("strength", 50)) - first) > 0.01:
			return false
	return true


static func _spread_strength(rng: Rng, name: String, base: float) -> float:
	return clampf(base + rng.derive("strength:%s" % name).gauss(0.0, 6.0, -13.0, 13.0),
		20.0, 96.0)


## Réputation de départ : la MARQUE, pas la forme du moment.
##
## Elle vient du PRESTIGE DE LA LIGUE où la structure a son slot, et non de son
## niveau sportif. Un slot en ligue partenaire EST la marque : les douze
## équipes du VCT EMEA sont douze grosses maisons, et savoir laquelle finira
## première cette année est une autre question.
##
## AVANT, la réputation valait `pow(strength/100, 2.8) * 12500`. Pour le pack
## VCT, dont le fichier ne déclare aucune hiérarchie — elle n'est pas publique —
## `strength` est un TIRAGE : le jeu désignait donc AU HASARD la plus grosse
## marque du monde. Mesuré : Nova Esports passait devant Spirit, NAVI, FaZe et
## MOUZ. Le prestige d'une ligue, lui, est une donnée du circuit, pas un dé.
##
## Le niveau sportif garde une influence, mais modeste (±19 % sur la bande de
## l'étage) : une équipe qui domine sa ligue est une marque un peu plus grosse
## que la lanterne rouge, pas deux fois plus. C'est aussi ce qui laisse la
## hiérarchie publiée du Counter-Strike se voir : la Pro League chinoise, dont
## les équipes tiennent le bas de la bande tier 1, reste sous l'européenne.
##
## Ensuite, c'est le PALMARÈS qui fait bouger la réputation
## (`CompetitionEngine`, `SeasonBuilder._apply_promotions`) — ce qui est le bon
## moteur pour une marque : lent, et mérité.

## Bande de ±13 % autour du prestige de la ligue. Étroite à dessein : on
## corrige le CLASSEMENT des marques, pas l'échelle, et elle laisse la place à
## la prime des maisons à deux sections (`SECTION_UPLIFT`) sans taper le
## plafond.
const BRAND_FLOOR := 0.68
const BRAND_SPAN := 0.26

## L'échelle de prestige des ligues (8 300 / 3 500 / 1 200) est plus PLATE que
## l'écart de marque réel entre les étages. La cambrer remet la pyramide à la
## pente qu'elle avait, et ce n'est pas de la cosmétique : la réputation ouvre
## les paliers de sponsors et multiplie les recettes de merchandising. Mesuré
## sans cette correction — le circuit ouvert gagnait 39 % de réputation, les
## dépôts de bilan tombaient de 18 % à 2 %, et la masse salariale d'une
## structure passait de 54 % à 34 % de ses recettes. Un monde où plus personne
## ne coule n'a plus d'enjeu.
const BRAND_CURVE := 1.2

static func _brand_for(game_id: String, league_key: String,
		strength: float) -> int:
	var prestige := 1200.0
	var tier := 3
	for slot_v in SeasonBuilder.league_slots(game_id):
		var slot: Dictionary = slot_v
		if str(slot["key"]) == league_key:
			prestige = float(slot.get("prestige", 1200))
			tier = int(slot.get("tier", 3))
			break
	var lo := _tier_floor(tier)
	var hi := _tier_ceiling(tier)
	var pos := clampf((strength - lo) / maxf(hi - lo, 1.0), 0.0, 1.0)
	var base := 10000.0 * pow(prestige / 10000.0, BRAND_CURVE)
	return int(clampf(base * (BRAND_FLOOR + BRAND_SPAN * pos), 90.0, 9800.0))


## Le public suit la MARQUE, pas le classement de la semaine — et il la suit de
## façon très inégale : une maison deux fois plus réputée qu'une autre a bien
## plus du double de son public.
##
## La courbe part de la réputation et non de la force, sans quoi une écurie
## célèbre reléguée d'un étage perdrait ses fans du jour au lendemain. Mesuré
## avant ce changement : HEROIC tombait à 9 772 fans, moins qu'une équipe
## inventée de circuit ouvert.
## La courbe est CALIBRÉE sur l'audience qu'avait chaque étage avant que la
## réputation change de source, et pas librement choisie : le public est ce qui
## paie le merchandising, donc la principale recette d'une petite structure.
## Première tentative mesurée avec une pente plus douce : le circuit ouvert
## passait de 10 000 à 28 000 fans, et les dépôts de bilan de 18 % à 1 % — un
## monde où plus personne ne coule n'a plus d'enjeu.
static func _fanbase_for(reputation: int) -> int:
	return int(clampf(pow(float(reputation) / 10000.0, 2.3) * 4_000_000.0,
		2_500.0, 4_000_000.0))


static func _region_of(league_key: String) -> String:
	if league_key.ends_with("emea"):
		return "EMEA"
	if league_key.ends_with("americas"):
		return "AMERICAS"
	if league_key.ends_with("pacific"):
		return "PACIFIC"
	return "CHINA"


const OWNER_MAP := {
	"self_funded": Organization.Owner.SELF_FUNDED,
	"investor": Organization.Owner.INVESTOR,
	"endemic": Organization.Owner.ENDEMIC_BRAND,
	"celebrity": Organization.Owner.CELEBRITY,
	"corporate": Organization.Owner.CORPORATE,
}


static func _make_org(world: World, module: GameModule, league_key: String,
		region: String, entry_v, spread: bool = false) -> Organization:
	var entry: Dictionary = entry_v
	var rng := world.rng
	var strength := float(entry.get("strength", 50))
	if spread:
		strength = _spread_strength(rng, str(entry["name"]), strength)
	var tier1 := league_key.begins_with("vct")

	var o := Organization.new()
	o.id = world.ids.next(Ids.ORG)
	o.name = str(entry["name"])
	o.tag = str(entry["tag"])
	o.region = region
	o.country = str(entry.get("country", "FR"))
	o.color_primary = str(entry.get("color", "#e04141"))
	o.founded_year = GameDate.year_of(world.today) - rng.range_i(2, 14)
	o.owner = OWNER_MAP.get(str(entry.get("owner", "self_funded")),
		Organization.Owner.SELF_FUNDED)
	o.games = _declared_games(entry, strength, rng, o.name)
	o.ledger = Ledger.new()

	o.reputation = _brand_for(module.id(), league_key, strength)
	o.fanbase = _fanbase_for(o.reputation)
	o.facilities = _facilities_for(strength, rng)

	o.brand_value = Money.from_units(pow(float(o.reputation) / 10000.0, 2.4)
		* 26_000_000.0)
	o.board_confidence = rng.gauss(62.0, 8.0, 35.0, 88.0)

	world.orgs[o.id] = o
	_make_roster(world, module, o, league_key, region, strength, tier1)
	return o


## Passe 4 : encadrement, sponsors et trésorerie de départ.
##
## Séparée de `_make_org` parce qu'elle doit voir TOUTES les sections de la
## maison. Un encadrement est recruté par équipe, et la trésorerie vaut un
## nombre de mois de charges réelles : les deux dépendent de ce que la
## structure aligne vraiment, pas seulement de sa section Valorant.
static func _finish_org(world: World, o: Organization, strength: float) -> void:
	var rng := world.rng
	_make_staff(world, o, o.region, strength)
	_sign_initial_sponsors(world, o, strength)

	var monthly_cost := FinanceSystem.fixed_monthly_cost(world, o)
	var months := rng.range_f(2.5, 4.5) if strength < 55.0 else rng.range_f(4.5, 9.0)
	o.ledger.cash = int(float(monthly_cost) * months)
	o.budgets["marketing"] = Money.pct(monthly_cost, rng.range_f(2.0, 6.0))


# ============================================================================
# Sections des autres disciplines
# ============================================================================

## Ouvre les sections d'une discipline autre que celle des ligues du monde.
##
## Chaque ligne du fichier `orgs_<jeu>.json` est d'abord cherchée PAR NOM parmi
## les structures existantes. Si elle y est, on lui ajoute une équipe : même
## trésorerie, même marque, même direction — c'est la promesse du projet
## « on dirige une STRUCTURE, pas une équipe ». Sinon on crée une structure
## dédiée à cette discipline, comme il en existe beaucoup dans la réalité.
static func _build_sections(world: World, module: GameModule,
		strengths: Dictionary) -> void:
	var data = DataFile.load_json(module.orgs_path(), {"leagues": {}})
	if not (data is Dictionary):
		return
	var leagues: Dictionary = (data as Dictionary).get("leagues", {})
	if leagues.is_empty():
		Log.w("worldgen", "Aucune structure déclarée pour « %s »" % module.id())
		return

	var by_name := {}
	for oid in world.orgs:
		by_name[(world.orgs[oid] as Organization).name] = world.orgs[oid]

	var tiers := _league_tiers(module)
	for league_key in leagues:
		var key := str(league_key)
		var region := _region_of(key)
		var entries: Array = leagues[league_key]
		var spread := _uniform_strength(entries)
		var tier1 := int(tiers.get(key, 2)) == 1
		for entry_v in entries:
			var entry: Dictionary = entry_v
			var strength := float(entry.get("strength", 50))
			if spread:
				strength = _spread_strength(world.rng, str(entry["name"]), strength)
			var o: Organization = by_name.get(str(entry["name"]), null)
			if o == null:
				o = _make_bare_org(world, entry, region, strength,
					module.id(), key)
				strengths[o.id] = strength
				by_name[o.name] = o
			_open_section(world, module, o, key, region, strength, tier1)


## Une structure qui n'existe que dans cette discipline. Même barème de marque
## et d'infrastructures que les autres : c'est le même métier.
static func _make_bare_org(world: World, entry: Dictionary, region: String,
		strength: float, game_id: String, league_key: String) -> Organization:
	var rng := world.rng
	var o := Organization.new()
	o.id = world.ids.next(Ids.ORG)
	o.name = str(entry["name"])
	o.tag = str(entry["tag"])
	o.region = region
	o.country = str(entry.get("country", "FR"))
	o.color_primary = str(entry.get("color", "#e04141"))
	o.founded_year = GameDate.year_of(world.today) - rng.range_i(2, 14)
	o.owner = OWNER_MAP.get(str(entry.get("owner", "self_funded")),
		Organization.Owner.SELF_FUNDED)
	o.games = []
	o.ledger = Ledger.new()
	o.reputation = _brand_for(game_id, league_key, strength)
	o.fanbase = _fanbase_for(o.reputation)
	o.facilities = _facilities_for(strength, rng)
	o.brand_value = Money.from_units(pow(float(o.reputation) / 10000.0, 2.4)
		* 26_000_000.0)
	o.board_confidence = rng.gauss(62.0, 8.0, 35.0, 88.0)
	world.orgs[o.id] = o
	return o


## Ajoute une équipe à une structure et déclare la discipline dans sa liste de
## sections. Les deux vont ENSEMBLE : une section déclarée sans équipe est un
## mensonge affiché au joueur, une équipe sans section déclarée est une équipe
## que l'écran Structure n'affichera jamais.
static func _open_section(world: World, module: GameModule, o: Organization,
		league_key: String, region: String, strength: float,
		tier1: bool) -> void:
	if world.main_roster(o.id, module.id()) != null:
		return   # la maison tient déjà une équipe sur cette discipline
	var declared := o.games.duplicate()
	declared.append(module.id())
	o.games = GameCatalog.sanitize(declared)
	_make_roster(world, module, o, league_key, region, strength, tier1)


## Étage de chaque ligue d'une discipline, lu dans son fichier de saison.
static func _league_tiers(module: GameModule) -> Dictionary:
	var out := {}
	for slot_v in SeasonBuilder.league_slots(module.id()):
		var slot: Dictionary = slot_v
		out[str(slot["key"])] = int(slot["tier"])
	return out


## Aucune section déclarée ne doit rester sans équipe si le moteur sait la
## simuler.
##
## Le cas vient des packs : le pack VCT déclare une section CS2 pour douze
## structures réelles à partir des portails Liquipedia. Sans cette passe, ces
## douze maisons afficheraient « Counter-Strike 2 — non simulée » alors que le
## jeu simule une saison CS complète à côté.
##
## On les engage à l'étage qui correspond à leur SURFACE : une écurie qui pèse
## 80 en Valorant n'entre pas dans le circuit ouvert de Counter-Strike, elle
## entre en Pro League. La ligue accueille simplement une équipe de plus — un
## championnat toutes rondes n'a pas de taille imposée.
static func _honour_declared_games(world: World, strengths: Dictionary) -> void:
	for game_id in GameRegistry.all_ids():
		var module := GameRegistry.get_module(game_id)
		var slots := SeasonBuilder.league_slots(game_id)
		if slots.is_empty():
			continue
		for oid in world.orgs:
			var o: Organization = world.orgs[oid]
			if not o.games.has(game_id):
				continue
			if world.main_roster(o.id, game_id) != null:
				continue
			# Une section ouverte en second n'est pas la vitrine de la maison :
			# on la place un cran sous ce que vaut la structure.
			var strength := clampf(float(strengths.get(o.id, 45.0)) - 8.0,
				26.0, 88.0)
			var slot := _league_for_strength(slots, o.region, strength)
			if slot.is_empty():
				continue
			var tier := int(slot["tier"])
			_make_roster(world, module, o, str(slot["key"]), o.region,
				clampf(strength, _tier_floor(tier), _tier_ceiling(tier)),
				tier == 1)


## Ligue d'une région correspondant au niveau d'une structure. À défaut
## d'étage exact, on retombe sur le plus bas que la région propose.
static func _league_for_strength(slots: Array, region: String,
		strength: float) -> Dictionary:
	var wanted := 1 if strength >= 66.0 else (2 if strength >= 42.0 else 3)
	var fallback := {}
	for slot_v in slots:
		var slot: Dictionary = slot_v
		if str(slot["region"]) != region:
			continue
		if int(slot["tier"]) == wanted:
			return slot
		if fallback.is_empty() or int(slot["tier"]) > int(fallback["tier"]):
			fallback = slot
	return fallback


## Bande de niveau d'un étage : une structure célèbre qui débarque dans le
## circuit ouvert n'y aligne pas un cinq de Pro League, et inversement.
static func _tier_ceiling(tier: int) -> float:
	match tier:
		1: return 88.0
		2: return 62.0
		_: return 40.0


static func _tier_floor(tier: int) -> float:
	match tier:
		1: return 64.0
		2: return 40.0
		_: return 26.0


## La MARQUE d'une maison à plusieurs sections.
##
## Pourquoi cette passe existe : une structure qui aligne deux rosters de haut
## niveau paie deux masses salariales sur une seule trésorerie. Si sa marque ne
## valait pas plus que celle de sa voisine mono-section, elle déposerait le
## bilan avant l'été — et l'inverse serait tout aussi faux, puisque dans la
## réalité une deuxième section, c'est un deuxième public, un deuxième
## calendrier et deux fois plus d'inventaire à vendre à une marque.
##
## L'uplift est donc indexé sur l'ÉTAGE de la section supplémentaire : une
## équipe de Pro League apporte une audience, une équipe de circuit ouvert
## apporte une ligne sur le site.
const SECTION_UPLIFT := {
	1: {"reputation": 0.22, "fanbase": 0.60},
	2: {"reputation": 0.09, "fanbase": 0.20},
	3: {"reputation": 0.03, "fanbase": 0.06},
}


static func _apply_section_brand(world: World) -> void:
	var tiers := {}
	for game_id in GameRegistry.all_ids():
		for slot_v in SeasonBuilder.league_slots(game_id):
			var slot: Dictionary = slot_v
			tiers[str(slot["key"])] = int(slot["tier"])

	for oid in world.orgs:
		var o: Organization = world.orgs[oid]
		var rosters := world.rosters_of(o.id)
		if rosters.size() <= 1:
			continue
		# La section la MIEUX classée est la vitrine : elle porte déjà la
		# marque. Ce sont les autres qui ajoutent quelque chose.
		var ranks: Array[int] = []
		for r in rosters:
			if not r.is_academy:
				ranks.append(int(tiers.get(r.league_key, 3)))
		ranks.sort()
		var rep_gain := 0.0
		var fan_gain := 0.0
		for i in range(1, ranks.size()):
			var up: Dictionary = SECTION_UPLIFT.get(ranks[i],
				SECTION_UPLIFT[3])
			rep_gain += float(up["reputation"])
			fan_gain += float(up["fanbase"])
		if rep_gain <= 0.0:
			continue
		o.reputation = int(clampf(float(o.reputation) * (1.0 + rep_gain),
			90.0, 10000.0))
		o.fanbase = int(clampf(float(o.fanbase) * (1.0 + fan_gain),
			1_500.0, 6_000_000.0))
		o.brand_value = int(float(o.brand_value) * (1.0 + rep_gain))


## Disciplines alignées par la structure.
##
## Un pack de données peut les déclarer ("games": ["valorant", "lol"]) — c'est
## le cas du pack VCT, alimenté par les portails Liquipedia de chaque jeu.
## Sinon on en tire un jeu plausible à partir de la puissance : une écurie
## majeure aligne plusieurs sections, un club de Challengers une seule.
##
## Le tirage passe par un RNG DÉRIVÉ et non par le flux principal : ajouter
## cette information ne devait pas décaler tous les mondes existants à graine
## identique.
static func _declared_games(entry: Dictionary, strength: float,
		rng: Rng, org_name: String) -> Array[String]:
	var declared := GameCatalog.sanitize(entry.get("games", []))
	if not declared.is_empty():
		# La discipline simulée est celle des ligues du monde : une structure
		# engagée en VCT aligne forcément Valorant, quoi que dise le pack.
		if not declared.has("valorant"):
			declared.insert(0, "valorant")
		return declared

	var side := rng.derive("games:%s" % org_name)
	var extra := 0
	if strength >= 82.0:
		extra = side.range_i(2, 4)
	elif strength >= 72.0:
		extra = side.range_i(1, 3)
	elif strength >= 62.0:
		extra = side.range_i(0, 2)
	elif strength >= 52.0:
		extra = side.range_i(0, 1)
	var pool: Array = ["cs2", "lol", "rl", "apex", "r6", "dota2", "ow2"]
	side.shuffle(pool)
	var picked: Array = pool.slice(0, extra)
	picked.append("valorant")
	return GameCatalog.sanitize(picked)


## Infrastructures de départ. Elles sont volontairement modestes : une équipe
## de Challengers n'a ni team house ni académie, et leurs charges d'entretien
## représenteraient à elles seules la moitié de son budget.
static func _facilities_for(strength: float, rng: Rng) -> Dictionary:
	var levels := Facilities.default_levels()
	var base := clampi(int(floor(strength / 26.0)), 0, 3)
	for k in Facilities.Kind.values():
		var lvl := clampi(base + rng.range_i(-1, 1), 0, Facilities.MAX_LEVEL)
		# Le confort coûte cher : réservé aux structures qui en ont les moyens.
		if k == Facilities.Kind.TEAM_HOUSE and strength < 68.0:
			lvl = 0
		if k == Facilities.Kind.ACADEMY and strength < 72.0:
			lvl = 0
		if k == Facilities.Kind.CONTENT_STUDIO and strength < 55.0:
			lvl = mini(lvl, 1)
		levels[k] = lvl
	return levels


static func _make_roster(world: World, module: GameModule, o: Organization,
		league_key: String, region: String, strength: float, tier1: bool) -> void:
	var rng := world.rng
	var r := Roster.new()
	r.id = world.ids.next(Ids.ROSTER)
	r.org_id = o.id
	r.game_id = module.id()
	r.name = o.name
	r.region = region
	r.league_key = league_key
	r.tactic = module.default_tactic()
	r.chemistry = rng.gauss(52.0, 12.0, 20.0, 88.0)

	var target := ca_for_strength(strength)
	# La composition de départ appartient à la DISCIPLINE : deux duellistes en
	# Valorant, un AWPeur et un lurker en Counter-Strike.
	var roles := module.generated_lineup()
	# Un roster d'élite embarque un ou deux remplaçants ; à l'étage en dessous,
	# rarement.
	var size := module.team_size()
	var extra := rng.range_i(0, 2) if tier1 else rng.range_i(0, 1)
	for _i in mini(extra, maxi(module.max_roster_size() - size, 0)):
		roles.append(str(rng.pick(module.roles())))

	# Un pack de données peut fournir l'effectif RÉEL de cette structure. Il ne
	# donne que des identités : le niveau, les attributs et le potentiel
	# restent générés, parce qu'ils n'existent nulle part dans le monde réel.
	var real := real_roster_for(o.name, module)
	if not real.is_empty():
		# On complète jusqu'au cinq réglementaire. Un pack peut ne connaître
		# que trois titulaires — c'est le cas des écuries dont le classement
		# HLTV n'affiche qu'une partie de l'effectif — et prendre sa taille
		# telle quelle engagerait la section en championnat à trois joueurs,
		# incapable d'aligner un cinq de toute la saison.
		roles = _roles_for_real_roster(module, rng, maxi(real.size(), size), real)

	# Si le pack désigne déjà un capitaine, on ne veut pas en tirer un second.
	var igl_index := -1 if _declares_igl(real) else rng.range_i(0, size - 1)
	for i in roles.size():
		var ca := clampi(int(round(target + rng.gauss(0.0, 9.0, -24.0, 24.0))), 25, 195)
		if i >= size:
			ca = clampi(ca - rng.range_i(5, 18), 25, 195)
		var p := PlayerFactory.create(rng, module, world.ids, world.today, {
			"target_ca": ca, "role": roles[i], "region": region,
			"igl": i == igl_index,
		})
		if i < real.size():
			_apply_real_identity(world, p, real[i])
		p.org_id = o.id
		p.contract = _make_contract(world, o, p, rng, tier1)
		world.players[p.id] = p
		r.add_player(p.id)
		if i < size:
			r.starters.append(p.id)
	r.training = TrainingSystem.DEFAULT_PLAN.duplicate()
	_assign_promises(world, r)
	world.rosters[r.id] = r
	o.add_roster(module.id(), r.id)


# ============================================================================
# Effectifs réels fournis par un pack de données
# ============================================================================

const DATA_ROSTERS := "res://data/world/rosters.json"


## Effectif réel déclaré pour une structure, ou [] s'il n'y en a pas.
## Format attendu (voir docs/DATA_PACKS.md et tools/import_liquipedia.gd) :
##   {"teams": {"Fnatic": {"players": [{"tag", "first", "last", "country",
##                                      "born", "igl", "sub"}]}}}
##
## Le fichier est PROPRE À LA DISCIPLINE (`rosters.json` pour Valorant,
## `rosters_cs2.json` pour Counter-Strike) : deux sections d'une même maison
## n'ont évidemment pas le même effectif.
static func real_roster_for(org_name: String, module: GameModule = null) -> Array:
	var path := module.rosters_path() if module != null else DATA_ROSTERS
	# Aucun pack ne fournit ce fichier dans l'univers fictif : on vérifie avant
	# de charger, sinon la génération crache un avertissement par structure.
	if not FileAccess.file_exists(DataPack.resolve(path)):
		return []
	var d = DataFile.load_json(path, {})
	if not (d is Dictionary):
		return []
	var teams = (d as Dictionary).get("teams", {})
	if not (teams is Dictionary) or not (teams as Dictionary).has(org_name):
		return []
	var entry = (teams as Dictionary)[org_name]
	var players = (entry as Dictionary).get("players", []) if entry is Dictionary else []
	return players if players is Array else []


## Postes d'un effectif réel.
##
## Le pack PEUT déclarer le poste de chaque joueur (`role`), et quand il le
## fait on le suit : en Counter-Strike c'est ce qui se remarque le plus vite,
## parce qu'il n'y a qu'une AWP par équipe et que tout le monde sait qui la
## tient. Voir ZywOo rangé « soutien » pendant qu'apEX tient l'AWP est le genre
## de faute qui décrédibilise tout le reste de la fiche.
##
## Deux garde-fous :
##  - les BORNES DE COMPOSITION de la discipline (`composition_bounds`) sont
##    respectées. Une page de wiki peut annoncer deux AWPeurs dans le même
##    cinq ; le second passe rifleur, comme dans la vraie vie ;
##  - ce qui reste sans poste déclaré est complété par la composition idéale,
##    postes déjà pris retirés, plutôt que tiré au hasard — sinon un effectif
##    à moitié renseigné se retrouverait sans entry ni support.
static func _roles_for_real_roster(module: GameModule, rng: Rng, count: int,
		real: Array = []) -> Array[String]:
	var bounds: Dictionary = module.composition_bounds()
	var used := {}
	var out: Array[String] = []
	out.resize(count)
	out.fill("")

	for i in mini(count, real.size()):
		if not (real[i] is Dictionary):
			continue
		var role := str((real[i] as Dictionary).get("role", "")).strip_edges()
		if role == "" or not module.roles().has(role):
			continue
		var cap := int((bounds.get(role, [0, count]) as Array)[1]) \
			if bounds.has(role) else count
		if int(used.get(role, 0)) >= cap:
			continue
		used[role] = int(used.get(role, 0)) + 1
		out[i] = role

	# Ce qui manque : la composition idéale, moins ce qui est déjà tenu.
	var missing: Array[String] = []
	var ideal: Dictionary = module.ideal_composition()
	for role in ideal:
		for _n in int(ideal[role]) - int(used.get(role, 0)):
			missing.append(str(role))
	for i in count:
		if out[i] != "":
			continue
		out[i] = missing.pop_front() if not missing.is_empty() \
			else str(rng.pick(module.roles()))
	return out


## Remplace l'identité générée par celle du pack. Tout le reste — attributs,
## potentiel, contrat, valeur — continue d'être simulé.
static func _apply_real_identity(world: World, p: Player, entry_v) -> void:
	if not (entry_v is Dictionary):
		return
	var entry: Dictionary = entry_v
	var tag := str(entry.get("tag", "")).strip_edges()
	if tag == "":
		return
	p.gamertag = tag
	world.ids.claim_tag(tag)
	var first := str(entry.get("first", "")).strip_edges()
	var last := str(entry.get("last", "")).strip_edges()
	if first != "":
		p.first_name = first
	if last != "":
		p.last_name = last
	var country := str(entry.get("country", "")).strip_edges()
	if country != "":
		p.nationality = country.to_upper()
	# La date de naissance change l'âge, donc la courbe de progression : il
	# faut la reprendre, sinon un vétéran de 28 ans progresserait comme un
	# espoir de 17.
	var born := str(entry.get("born", "")).strip_edges()
	var day := _parse_iso_day(born)
	if day > 0:
		p.birth_day = day
	if bool(entry.get("igl", false)):
		p.is_igl = true
	# Le rôle d'IGL entre dans le calcul de la capacité : sans ce recalcul, la
	# fiche afficherait un niveau qui ne correspond plus au poste occupé.
	AbilityCalc.refresh(p, world.module_for(p.game_id))


static func _declares_igl(real: Array) -> bool:
	for entry in real:
		if entry is Dictionary and bool((entry as Dictionary).get("igl", false)):
			return true
	return false


## "2003-02-06" -> index de jour, ou -1 si la chaîne n'est pas exploitable.
static func _parse_iso_day(iso: String) -> int:
	var parts := iso.split("-")
	if parts.size() != 3:
		return -1
	var y := int(parts[0])
	var m := int(parts[1])
	var d := int(parts[2])
	if y < 1970 or m < 1 or m > 12 or d < 1 or d > 31:
		return -1
	return GameDate.from_ymd(y, m, d)


## Statut promis à la création du monde : chaque joueur arrive avec un accord
## déjà négocié, sinon tout un effectif se croirait titulaire dès la première
## semaine et le vestiaire exploserait sans que le joueur y soit pour rien.
static func _assign_promises(world: World, r: Roster) -> void:
	var size := world.module_for(r.game_id).team_size()
	var squad := world.players_of(r.id)
	squad.sort_custom(func(a: Player, b: Player):
		return a.current_ability > b.current_ability)
	for i in squad.size():
		var p: Player = squad[i]
		var status := PlayingTime.STARTER
		if i == 0 and squad.size() >= size:
			status = PlayingTime.KEY
		elif i >= size:
			status = PlayingTime.BACKUP
		elif not r.starters.has(p.id):
			status = PlayingTime.ROTATION
		if p.age(world.today) <= 18 and not r.starters.has(p.id):
			status = PlayingTime.PROSPECT
		p.promised_time = status
		p.promise_day = world.today


static func _make_contract(world: World, o: Organization, p: Player, rng: Rng,
		tier1: bool) -> Contract:
	var c := Contract.new()
	c.org_id = o.id
	c.person_id = p.id
	c.salary_yearly = PlayerFactory.salary_for_ca(p.current_ability, p.reputation)
	# Chaque structure paie un peu au-dessus ou en dessous du marché.
	c.salary_yearly = Money.pct(c.salary_yearly, rng.range_f(85.0, 118.0))
	c.start_day = GameDate.add_years(world.today, -rng.range_i(0, 2))
	c.end_day = GameDate.add_months(world.today, rng.range_i(4, 32))
	c.buyout = int(float(p.market_value) * rng.range_f(1.1, 2.4))
	c.prize_share_pct = rng.range_f(9.0, 15.0) if tier1 else rng.range_f(12.0, 18.0)
	c.signed_on_day = c.start_day
	return c


## Encadrement de départ.
##
## Les postes de BANC (entraîneur, analyste, adjoint) sont recrutés par ÉQUIPE :
## une maison à deux sections paie deux entraîneurs, comme dans la réalité —
## et sans ça la section Counter-Strike jouerait toute la saison à 8/20 de
## niveau tactique. Les postes transverses (team manager, préparateur,
## recruteur, responsable contenu, directeur sportif) servent toute la maison
## et ne sont recrutés qu'une fois.
static func _make_staff(world: World, o: Organization, region: String,
		strength: float) -> void:
	var quality := clampf(4.0 + strength / 7.0, 4.0, 19.0)

	# Combien de postes la maison a ouverts AVANT l'arrivée du joueur. La liste
	# est celle de StaffSystem.ROLE_ORDER : une seule priorité dans tout le
	# projet, sinon le monde généré et le monde simulé ne se ressemblent pas.
	# En jeu, c'est ensuite StaffSystem.org_chart qui décide, sur les moyens
	# réels — les recettes n'existent pas encore à cet instant.
	var posts := 1
	for threshold in [45.0, 60.0, 70.0, 78.0, 84.0, 90.0]:
		if strength >= float(threshold):
			posts += 1
	var roles: Array = []
	for i in mini(posts, StaffSystem.ROLE_ORDER.size()):
		roles.append(StaffSystem.ROLE_ORDER[i])

	var teams := world.rosters_of(o.id)
	for role in roles:
		if StaffSystem.TEAM_ROLES.has(int(role)):
			for r in teams:
				_hire_initial(world, o, region, quality, int(role), r)
		else:
			_hire_initial(world, o, region, quality, int(role), null)


static func _hire_initial(world: World, o: Organization, region: String,
		quality: float, role: int, roster: Roster) -> void:
	var rng := world.rng
	# La dispersion est volontairement resserrée et bornée autour du niveau
	# de la structure. Le salaire du staff est exponentiel : deux points de
	# note au-dessus de son marché et une équipe de Challengers se retrouve
	# avec un coach à 190 k$/an qu'elle ne pourrait jamais s'offrir.
	var target := clampf(rng.gauss(quality, 1.5, 3.0, 19.5),
		maxf(quality - 3.0, 3.0), minf(quality + 2.5, 19.5))
	var s := StaffFactory.create(rng, world.ids, world.today,
		role as Staff.Role, {
			"region": region,
			"target_overall": target,
			"game_id": roster.game_id if roster != null else "",
		})
	s.org_id = o.id
	var c := Contract.new()
	c.kind = Contract.Kind.STAFF
	c.org_id = o.id
	c.person_id = s.id
	c.salary_yearly = StaffFactory.salary_for(role, s.overall())
	c.start_day = world.today
	c.end_day = GameDate.add_months(world.today, rng.range_i(8, 30))
	s.contract = c
	world.staff[s.id] = s
	StaffSystem.attach(world, o, s, roster.id if roster != null else "")


## Sponsors déjà en place au démarrage, avec des échéances étalées pour que le
## joueur ne perde pas tous ses partenaires le même mois.
static func _sign_initial_sponsors(world: World, o: Organization,
		strength: float) -> void:
	var rng := world.rng
	# Même une petite structure a plusieurs partenaires : c'est sa seule source
	# de revenus réellement pilotable.
	var wanted := 2
	if strength >= 42.0:
		wanted = 3
	if strength >= 65.0:
		wanted = 4
	if strength >= 80.0:
		wanted = 5

	var offers := SponsorSystem.offers_for(world, o, 10)
	var signed := 0
	for offer_v in offers:
		if signed >= wanted:
			break
		var offer: Dictionary = offer_v
		if float(o.reputation) < float(offer.get("min_reputation", 0)):
			continue
		# Une petite structure ne décroche pas un contrat à sept chiffres.
		var deal := SponsorSystem.sign_deal(world, o, offer)
		deal.start_day = GameDate.add_months(world.today, -rng.range_i(1, 14))
		deal.end_day = GameDate.add_months(deal.start_day,
			int(offer.get("years", 2)) * 12)
		if deal.end_day <= world.today:
			deal.end_day = GameDate.add_months(world.today, rng.range_i(2, 10))
		signed += 1


## Agents libres : un vivier crédible, avec des jeunes à fort potentiel, des
## vétérans en fin de carrière et quelques bons joueurs sans contrat.
##
## La taille du vivier suit celle de la DISCIPLINE dans la région. Un marché
## dimensionné comme celui de Valorant autour d'une Pro League de six équipes
## donnerait un monde où chaque club peut remplacer ses cinq titulaires en une
## semaine — et où plus personne n'a de valeur.
static func _make_free_agents(world: World, module: GameModule) -> void:
	var rng := world.rng
	for region in REGIONS:
		var scale := clampf(float(_teams_in(world, module.id(), region))
			/ REFERENCE_TEAMS_PER_REGION, 0.30, 1.0)
		# Jeunes talents (le vivier de l'académie)
		for _i in int(round(22.0 * scale)):
			var p := PlayerFactory.create(rng, module, world.ids, world.today, {
				"target_ca": rng.gauss_i(66.0, 14.0, 30, 110),
				"age": rng.range_i(16, 19), "region": region,
				"potential_bonus": rng.range_i(0, 25),
			})
			world.players[p.id] = p
		# Joueurs confirmés sans contrat
		for _i in int(round(14.0 * scale)):
			var p2 := PlayerFactory.create(rng, module, world.ids, world.today, {
				"target_ca": rng.gauss_i(102.0, 16.0, 60, 150),
				"age": rng.range_i(20, 25), "region": region,
			})
			world.players[p2.id] = p2
		# Vétérans en fin de parcours
		for _i in int(round(6.0 * scale)):
			var p3 := PlayerFactory.create(rng, module, world.ids, world.today, {
				"target_ca": rng.gauss_i(112.0, 15.0, 70, 160),
				"age": rng.range_i(26, 31), "region": region,
			})
			world.players[p3.id] = p3


static func _teams_in(world: World, game_id: String, region: String) -> int:
	var n := 0
	for rid in world.rosters:
		var r: Roster = world.rosters[rid]
		if r.game_id == game_id and r.region == region and not r.is_academy:
			n += 1
	return n


# ============================================================================
# Prise en main d'une structure par le joueur
# ============================================================================

# ============================================================================
# Fondation d'une structure par le joueur
# ============================================================================

## Étage de la pyramide où entre une structure fondée de zéro.
const OPEN_LEAGUE_PREFIX := "open_"


## Ligue d'entrée d'une discipline dans une région : l'étage le plus bas que
## son fichier de saison déclare. C'est par là que passe une structure fondée
## de zéro, quelle que soit la discipline choisie.
static func entry_league_key(game_id: String, region: String) -> String:
	var best := {}
	for slot_v in SeasonBuilder.league_slots(game_id):
		var slot: Dictionary = slot_v
		if str(slot["region"]) != region:
			continue
		if best.is_empty() or int(slot["tier"]) > int(best["tier"]):
			best = slot
	return str(best.get("key", OPEN_LEAGUE_PREFIX + region.to_lower()))

## Les trois façons de démarrer.
##
## Le capital seul ne serait pas un choix : on prendrait toujours le plus
## gros. Ce qui l'équilibre, c'est la PATIENCE — l'argent d'un investisseur
## vient avec quelqu'un à qui rendre des comptes, et la confiance de la
## direction est ce qui met fin à la partie quand elle tombe à zéro.
##
## `promotion_expected` : la direction exige la montée dès la première saison,
## quel que soit le classement attendu.
const CAPITAL_TIERS := {
	"garage": {"units": 40_000.0, "owner": Organization.Owner.SELF_FUNDED,
		"confidence": 88.0, "promotion_expected": false},
	"seed": {"units": 120_000.0, "owner": Organization.Owner.SELF_FUNDED,
		"confidence": 72.0, "promotion_expected": false},
	"backed": {"units": 320_000.0, "owner": Organization.Owner.INVESTOR,
		"confidence": 56.0, "promotion_expected": true},
}


static func capital_tier(key: String) -> Dictionary:
	return CAPITAL_TIERS.get(key, CAPITAL_TIERS["seed"])


## Pays plausibles d'une région, lus dans la banque de noms : l'écran de
## création ne doit pas embarquer sa propre liste de pays.
static func countries_of(region: String) -> Array[String]:
	var d = DataFile.load_json("res://data/world/names.json", {})
	var out: Array[String] = []
	if not (d is Dictionary):
		return out
	var regions = (d as Dictionary).get("regions", {})
	if not (regions is Dictionary):
		return out
	var entry = (regions as Dictionary).get(region, {})
	if not (entry is Dictionary):
		return out
	for c in (entry as Dictionary).get("countries", []):
		out.append(str(c))
	return out


## Le joueur crée sa propre structure et entre par le circuit ouvert.
##
## Rien n'est hérité : aucun joueur, aucun sponsor, aucune place en Challengers.
## La différence avec `assign_player_org` n'est pas cosmétique — c'est une autre
## courbe de difficulté, où les six premières semaines servent à trouver cinq
## joueurs avant le premier match, sous peine de forfait.
##
## On fonde sur UNE discipline, celle du `game_id` de la configuration : on
## n'ouvre pas une section Counter-Strike le jour où l'on n'a pas encore cinq
## joueurs Valorant sous contrat. Les autres sections viendront quand la maison
## en aura les moyens.
##
## config : {"name", "tag", "country", "region", "color", "owner",
##           "capital_tier", "game_id"}
static func found_org(world: World, config: Dictionary) -> Organization:
	var region := str(config.get("region", "EMEA"))
	var game_id := str(config.get("game_id", "valorant"))
	if not GameRegistry.has(game_id):
		game_id = "valorant"
	var module := GameRegistry.get_module(game_id)
	var league_key := entry_league_key(game_id, region)

	var o := Organization.new()
	o.id = world.ids.next(Ids.ORG)
	o.name = str(config.get("name", "Nouvelle structure")).strip_edges()
	o.tag = str(config.get("tag", "NEW")).strip_edges().to_upper()
	o.region = region
	o.country = str(config.get("country", "FR"))
	o.color_primary = str(config.get("color", "#ff5a3c"))
	o.founded_year = GameDate.year_of(world.today)
	var tier := capital_tier(str(config.get("capital_tier", "seed")))
	o.owner = int(tier["owner"]) as Organization.Owner
	o.games = GameCatalog.sanitize([game_id])
	o.ledger = Ledger.new()
	o.ledger.cash = Money.from_units(float(tier["units"]))

	# Personne ne vous connaît. C'est le vrai handicap du mode : la réputation
	# pèse sur ce qu'un agent libre accepte de signer, sur les sponsors qu'on
	# peut décrocher et sur les revenus de contenu.
	o.reputation = 220
	o.fanbase = 1_800
	o.brand_value = Money.from_units(25_000.0)
	o.facilities = Facilities.default_levels()
	o.board_confidence = float(tier["confidence"])
	o.budgets["marketing"] = Money.from_units(600.0)
	world.orgs[o.id] = o

	var r := Roster.new()
	r.id = world.ids.next(Ids.ROSTER)
	r.org_id = o.id
	r.game_id = module.id()
	r.name = o.name
	r.region = region
	r.league_key = league_key
	r.tactic = module.default_tactic()
	r.training = TrainingSystem.DEFAULT_PLAN.duplicate()
	# Un groupe qui ne s'est jamais entraîné ensemble : la cohésion se
	# construira match après match.
	r.chemistry = 25.0
	world.rosters[r.id] = r
	o.add_roster(module.id(), r.id)

	# Un seul encadrant, et pas un bon : de quoi tenir les premières semaines.
	# Le marché du staff est ouvert dès le premier jour pour faire mieux.
	_make_staff(world, o, region, 18.0)

	_enter_open_circuit(world, r, league_key)

	world.player_org_id = o.id
	world.player_roster_id = r.id
	world.player_game_id = module.id()
	o.is_player_controlled = true
	o.objectives = BoardSystem.season_objectives(world, o)
	if bool(tier["promotion_expected"]):
		# Celui qui a mis l'argent veut voir la montée. Le calcul de rang
		# attendu ne l'aurait jamais formulé pour une équipe sans joueurs.
		o.objectives.insert(0, {"key": "promotion",
			"label": "Décrocher la montée à l'étage supérieur dès la première saison",
			"target": 1, "weight": 2.5, "met": false, "evaluated": false})
	_founding_news(world, o, r)
	return o


## Inscrit l'équipe dans la compétition du circuit ouvert déjà construite.
##
## La saison est bâtie avant que le joueur ne fonde quoi que ce soit : on ne
## peut donc pas compter sur `build_season` pour recruter les participants.
## On refuse d'inscrire une phase déjà lancée — arriver au milieu d'un
## championnat fausserait le calendrier de tout le monde.
static func _enter_open_circuit(world: World, r: Roster,
		league_key: String) -> void:
	for cid in world.competitions:
		var comp: Competition = world.competitions[cid]
		if comp.key != league_key or comp.season_year != world.season_year:
			continue
		if not comp.participants.has(r.id):
			comp.participants.append(r.id)
		if not r.competition_ids.has(comp.id):
			r.competition_ids.append(comp.id)
		for st in comp.stages:
			if st.status == Stage.Status.PENDING and not st.participants.has(r.id):
				st.participants.append(r.id)
		return
	Log.w("worldgen", "Aucun circuit ouvert « %s » : la structure fondée "
		% league_key + "n'est engagée dans aucune compétition.")


static func _founding_news(world: World, o: Organization, r: Roster) -> void:
	var comp_name := "le circuit ouvert"
	for cid in r.competition_ids:
		var c := world.competition(cid)
		if c != null:
			comp_name = c.name
	var first_match := "à la reprise du circuit"
	var day := _first_stage_day(world, r)
	if day > 0:
		first_match = "le %s" % GameDate.format_long(day)
	var size := world.module_for(r.game_id).team_size()
	world.add_news(world.today, "%s est née" % o.name,
		("Vous fondez %s. Personne ne vous attend, et c'est la seule bonne "
		+ "nouvelle : il n'y a rien à défendre.\n\n"
		+ "Discipline : %s\nCapital : %s\nEngagement : %s\n"
		+ "Effectif : aucun joueur sous contrat"
		+ "\n\nLe championnat commence %s. Une équipe qui ne présente pas %d "
		+ "joueurs déclare forfait — le marché des agents libres est votre "
		+ "première urgence, avant même les sponsors.")
		% [o.name, GameCatalog.label(r.game_id), Money.fmt(o.cash()), comp_name,
			first_match, size], "board")


static func _first_stage_day(world: World, r: Roster) -> int:
	var best := 0
	for cid in r.competition_ids:
		var c := world.competition(cid)
		if c == null:
			continue
		for st in c.stages:
			if best == 0 or st.start_day < best:
				best = st.start_day
	return best


## Le joueur reprend une structure existante. On lui donne le contrôle, on fixe
## les objectifs du board et on lui envoie son premier message.
##
## `roster_id` désigne la SECTION par laquelle on entre — celle de la carte
## cliquée. Une maison peut en tenir plusieurs, et reprendre Vantage Six par sa
## ligne de Pro League ne doit pas ouvrir sur son roster Valorant.
static func assign_player_org(world: World, org_id: String,
		roster_id: String = "") -> void:
	var o := world.org(org_id)
	if o == null:
		return
	world.player_org_id = org_id
	var main := world.roster(roster_id)
	if main == null or main.org_id != org_id:
		main = flagship_roster(world, o)
	world.player_roster_id = main.id if main != null else ""
	world.player_game_id = main.game_id if main != null else world.player_game_id
	o.is_player_controlled = true
	o.objectives = BoardSystem.season_objectives(world, o)
	world.add_news(world.today, "Bienvenue chez %s" % o.name,
		("Vous prenez la direction sportive de %s.\n\n"
		+ "Trésorerie : %s\nRéputation : %s\nFans : %s\n\n"
		+ "La direction attend : %s")
		% [o.name, Money.fmt(o.cash()), _stars_text(o.stars()),
			_short_number(o.fanbase), _objectives_text(o.objectives)], "board")


## Section VITRINE d'une structure : l'équipe engagée à l'étage le plus haut.
##
## Sert de repère stable à la direction et à la reprise d'une structure. Ce
## n'est PAS forcément la section que le joueur regarde (voir `my_roster`) :
## c'est celle sur laquelle la maison se juge.
static func flagship_roster(world: World, o: Organization) -> Roster:
	var best: Roster = null
	var best_tier := 99
	for r in world.rosters_of(o.id):
		if r.is_academy:
			continue
		var tier := league_tier(world, r.league_key)
		if best == null or tier < best_tier:
			best = r
			best_tier = tier
	return best


## Étage d'une ligue, lu sur la compétition de la saison en cours. Le JSON de
## saison fait autorité sur la forme du circuit, pas la clé de ligue.
static func league_tier(world: World, league_key: String) -> int:
	for cid in world.competitions:
		var c: Competition = world.competitions[cid]
		if c.key == league_key:
			return c.tier
	return 3


## Structures que le joueur peut choisir au démarrage, triées par difficulté.
##
## Une entrée = une SECTION, pas une structure : une maison qui aligne Valorant
## et Counter-Strike apparaît dans les deux ligues, et la carte cliquée décide
## de l'équipe qu'on prend en main.
static func selectable_orgs(world: World, league_key: String = "") -> Array:
	var out: Array = []
	for oid in world.orgs:
		var o: Organization = world.orgs[oid]
		# Sans filtre de ligue, on ne liste qu'une carte par maison : sa
		# vitrine. Avec un filtre, on liste la section de cette ligue-là.
		var flagship := flagship_roster(world, o)
		var flagship_id := flagship.id if flagship != null else ""
		for r in world.rosters_of(o.id):
			if r.is_academy:
				continue
			if league_key == "":
				if r.id != flagship_id:
					continue
			elif r.league_key != league_key:
				continue
			out.append({
				"org_id": o.id, "roster_id": r.id, "game_id": r.game_id,
				"name": o.name, "tag": o.tag,
				"league_key": r.league_key, "region": o.region,
				"reputation": o.reputation, "cash": o.cash(),
				"games": o.games.duplicate(),
				"fanbase": o.fanbase, "owner": o.owner_label(),
			})
	out.sort_custom(func(a, b): return int(a["reputation"]) > int(b["reputation"]))
	return out


static func _stars_text(stars: float) -> String:
	var full := int(floor(stars))
	var s := ""
	for i in 5:
		s += "*" if i < full else "."
	return s


static func _short_number(n: int) -> String:
	if n >= 1_000_000:
		return "%s M" % String.num(float(n) / 1_000_000.0, 1)
	if n >= 1_000:
		return "%d k" % int(n / 1000)
	return str(n)


static func _objectives_text(objectives: Array) -> String:
	var parts: Array[String] = []
	for o in objectives:
		parts.append(str((o as Dictionary).get("label", "")))
	return ", ".join(parts)
