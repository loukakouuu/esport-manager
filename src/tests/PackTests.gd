class_name PackTests
extends RefCounted

## Tests des packs de données.
##
## Ce système décide de QUEL contenu le jeu charge : une erreur ici ne se voit
## pas comme un plantage mais comme un monde silencieusement faux. On vérifie
## donc la chaîne complète, du fichier posé sur le disque jusqu'au joueur
## présent dans le monde généré avec le bon nom.
##
## Le pack de test s'écrit sous un identifiant réservé et se supprime à la fin :
## les packs réels de l'utilisateur ne sont jamais touchés.

const TEST_PACK := "__test_pack__"
const TEST_TEAM := "Vantage Six"    # structure livrée, ligue vct_emea


static func run() -> Array[TestCase]:
	return [_resolution(), _world_override(), _bundled_pack(), _bundled_cs2()]


# ============================================================================

## Le circuit Counter-Strike RÉEL du pack livré, bâti sur le classement
## mondial HLTV (voir tools/import_hltv.gd).
##
## Ce que ce test garde, et qu'aucun autre ne garderait :
##
##  1. l'IDENTITÉ arrive bien jusqu'au monde généré — un vrai joueur, dans sa
##     vraie écurie, sur la bonne discipline. C'est toute la promesse du pack ;
##  2. la HIÉRARCHIE survit. Contrairement au circuit Valorant, l'ordre du CS
##     est publié : si toutes les équipes d'une ligue se retrouvaient à la
##     même force, le jeu en réinventerait une au hasard
##     (WorldGenerator._uniform_strength) et le classement HLTV n'aurait servi
##     à rien — sans qu'aucun test ne s'en plaigne ;
##  3. l'ÉCART ENTRE RÉGIONS survit lui aussi. Une Pro League chinoise aussi
##     forte que l'européenne voudrait dire que la force ne vient plus du rang
##     mondial mais de la place dans sa propre ligue, et un Major se jouerait
##     à pile ou face ;
##  4. une maison à deux sections n'a toujours qu'UNE trésorerie, et les
##     salaires de sa section CS y passent.
static func _bundled_cs2() -> TestCase:
	var t := TestCase.new("Packs — le circuit Counter-Strike réel")
	var module := GameRegistry.get_module("cs2")
	if not DataPack.exists(DataPack.DEFAULT_PACK) or module == null:
		t.check(true, "aucun pack livré dans ce dépôt : rien à vérifier")
		return t
	DataPack.set_active(DataPack.DEFAULT_PACK)
	if not DataPack.overrides(module.orgs_path()):
		t.check(true, "le pack livré n'apporte pas de circuit Counter-Strike")
		DataPack.set_active("")
		return t
	var world := WorldGenerator.generate(20260105, GameDate.from_ymd(2026, 1, 5))

	# 1. L'identité jusqu'au monde généré.
	var real_players := 0
	var misplaced := 0
	var d = DataFile.load_json(module.rosters_path(), {})
	var teams: Dictionary = (d as Dictionary).get("teams", {}) if d is Dictionary else {}
	for team_name in teams:
		var o := _org_named(world, str(team_name))
		if o == null:
			continue
		var r := world.main_roster(o.id, "cs2")
		if r == null:
			continue
		var tags := {}
		for p in world.players_of(r.id):
			tags[p.gamertag] = true
		for entry_v in (teams[team_name] as Dictionary).get("players", []):
			var tag := str((entry_v as Dictionary).get("tag", ""))
			if tags.has(tag):
				real_players += 1
			else:
				misplaced += 1
	t.check(real_players >= 250,
		"les joueurs réels du circuit CS sont dans le monde (%d)" % real_players)
	t.eq(misplaced, 0, "et aucun n'a été perdu en route")

	# 2. et 3. La hiérarchie publiée, à l'intérieur d'une ligue et entre régions.
	var emea := _league_strength(world, "cs_pro_emea")
	var china := _league_strength(world, "cs_pro_china")
	t.check(emea.size() >= 6, "la Pro League EMEA est peuplée (%d)" % emea.size())
	t.check(china.size() >= 4, "la Pro League China aussi (%d)" % china.size())
	t.check(_spread_of(emea) > 12.0,
		"la Pro League EMEA garde un vrai écart de niveau (%.0f points de CA)"
			% _spread_of(emea))
	t.check(_mean_of(emea) > _mean_of(china) + 8.0,
		"et l'EMEA reste au-dessus de la Chine (%.0f contre %.0f de CA moyen)"
			% [_mean_of(emea), _mean_of(china)])

	# 4. Deux sections, une seule trésorerie.
	var houses := 0
	var one_ledger := 0
	var cs_in_wages := 0
	for oid in world.orgs:
		var o: Organization = world.orgs[oid]
		var val_r := world.main_roster(o.id, "valorant")
		var cs_r := world.main_roster(o.id, "cs2")
		if val_r == null or cs_r == null:
			continue
		houses += 1
		if o.ledger != null and o.all_roster_ids().has(cs_r.id) \
				and o.all_roster_ids().has(val_r.id):
			one_ledger += 1
		var cs_wages := 0
		for p in world.players_of(cs_r.id):
			if p.contract != null:
				cs_wages += p.contract.salary_yearly
		if cs_wages > 0 \
				and FinanceSystem.wage_bill_yearly(world, o) >= cs_wages:
			cs_in_wages += 1
	t.check(houses >= 8,
		"des maisons tiennent les deux disciplines (%d)" % houses)
	t.eq(one_ledger, houses, "chacune sur un seul grand livre")
	t.eq(cs_in_wages, houses,
		"et la masse salariale de la maison porte la section CS")

	DataPack.set_active("")
	return t


static func _org_named(world: World, name: String) -> Organization:
	for oid in world.orgs:
		if (world.orgs[oid] as Organization).name == name:
			return world.orgs[oid]
	return null


## Capacité actuelle moyenne des titulaires de chaque équipe d'une ligue.
## On mesure le RÉSULTAT (des joueurs) et pas le fichier : c'est la chaîne
## complète qu'on veut garder, pas la lecture d'un JSON.
static func _league_strength(world: World, league_key: String) -> Array[float]:
	var out: Array[float] = []
	for rid in world.rosters:
		var r: Roster = world.rosters[rid]
		if r.league_key != league_key or r.is_academy:
			continue
		var sum := 0.0
		var n := 0
		for p in world.players_of(r.id):
			sum += float(p.current_ability)
			n += 1
		if n > 0:
			out.append(sum / float(n))
	return out


static func _mean_of(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var sum := 0.0
	for v in values:
		sum += v
	return sum / float(values.size())


static func _spread_of(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var lo := values[0]
	var hi := values[0]
	for v in values:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	return hi - lo


# ============================================================================

## Le pack RÉELLEMENT LIVRÉ, celui qui est actif par défaut en jeu.
##
## Ce test existe pour une raison précise : le pack déclare, pour une douzaine
## de structures réelles, une section Counter-Strike lue sur les portails
## Liquipedia — alors que ses ligues, elles, sont Valorant. Si la génération
## n'ouvrait pas ces sections, le jeu afficherait « Counter-Strike 2 — non
## simulée » sur la fiche de Vitality pendant qu'il simule une saison CS
## complète à côté. C'est exactement le genre d'incohérence qu'aucun test
## d'unité n'attrape.
static func _bundled_pack() -> TestCase:
	var t := TestCase.new("Packs — le pack livré, sections comprises")
	if not DataPack.exists(DataPack.DEFAULT_PACK):
		t.check(true, "aucun pack livré dans ce dépôt : rien à vérifier")
		return t
	DataPack.set_active(DataPack.DEFAULT_PACK)
	var world := WorldGenerator.generate(20260105, GameDate.from_ymd(2026, 1, 5))

	var declaring := 0
	var honoured := 0
	var empty_squads := 0
	for oid in world.orgs:
		var o: Organization = world.orgs[oid]
		if not o.games.has("cs2"):
			continue
		declaring += 1
		var r := world.main_roster(o.id, "cs2")
		if r == null:
			continue
		honoured += 1
		if r.player_ids.size() < 5:
			empty_squads += 1
	t.check(declaring >= 5,
		"le pack déclare des sections Counter-Strike (%d)" % declaring)
	t.eq(honoured, declaring,
		"chaque section déclarée par le pack a une vraie équipe")
	t.eq(empty_squads, 0, "et un effectif complet")

	# Les structures du pack gardent leurs vrais joueurs Valorant : ouvrir une
	# deuxième section ne doit pas avoir écrasé la première.
	var real_names := 0
	for oid in world.orgs:
		var o: Organization = world.orgs[oid]
		var r := world.main_roster(o.id, "valorant")
		if r == null:
			continue
		if not WorldGenerator.real_roster_for(o.name,
				GameRegistry.get_module("valorant")).is_empty():
			real_names += 1
	t.check(real_names >= 20,
		"les effectifs réels du pack sont toujours chargés (%d)" % real_names)

	DataPack.set_active("")
	return t


# ============================================================================

static func _resolution() -> TestCase:
	var t := TestCase.new("Packs — résolution des fichiers")
	_cleanup()
	_write_pack({
		"world/names.json": {"regions": {"EMEA": {
			"countries": ["FR"], "first": ["Test"], "last": ["Pack"]}}},
	})

	# Découverte
	var found := false
	for m in DataPack.installed():
		if str((m as Dictionary)["id"]) == TEST_PACK:
			found = true
			t.eq(str((m as Dictionary)["name"]), "Pack de test",
				"le manifeste est lu")
			t.eq(((m as Dictionary)["files"] as Array).size(), 1,
				"un seul fichier est remplacé")
	t.check(found, "le pack installé est découvert")
	t.check(DataPack.exists(TEST_PACK), "exists() reconnaît le pack")

	# Sans pack actif, rien ne change.
	DataPack.set_active("")
	t.eq(DataPack.resolve("res://data/world/names.json"),
		"res://data/world/names.json",
		"sans pack actif, le chemin d'origine est conservé")

	# Avec le pack actif, seul le fichier fourni est détourné.
	DataPack.set_active(TEST_PACK)
	t.check(DataPack.overrides("res://data/world/names.json"),
		"le fichier fourni par le pack est bien détourné")
	t.check(not DataPack.overrides("res://data/world/orgs.json"),
		"un fichier absent du pack retombe sur le contenu livré")
	t.check(not DataPack.overrides("res://data/games/valorant/maps.json"),
		"les données de discipline aussi")

	# Le contenu lu vient réellement du pack.
	var names = DataFile.load_json("res://data/world/names.json", {})
	var emea: Dictionary = ((names as Dictionary).get("regions", {})
		as Dictionary).get("EMEA", {})
	t.eq(str((emea.get("first", []) as Array)[0]), "Test",
		"le contenu chargé provient du pack")

	# L'attribution exigée par la licence est exposée.
	t.check(DataPack.attribution_of(TEST_PACK).contains("CC-BY-SA"),
		"l'attribution du pack est restituée")

	# Revenir au contenu livré doit purger le cache.
	DataPack.set_active("")
	var back = DataFile.load_json("res://data/world/names.json", {})
	var back_emea: Dictionary = ((back as Dictionary).get("regions", {})
		as Dictionary).get("EMEA", {})
	t.check(str((back_emea.get("first", []) as Array)[0]) != "Test",
		"désactiver le pack restitue le contenu livré")

	_cleanup()
	return t


# ============================================================================

static func _world_override() -> TestCase:
	var t := TestCase.new("Packs — effectifs réels dans le monde généré")
	_cleanup()
	_write_pack({
		"world/rosters.json": {"teams": {TEST_TEAM: {"players": [
			{"tag": "TestOne", "first": "Jean", "last": "Dupont",
				"country": "BE", "born": "2004-03-15", "igl": true},
			{"tag": "TestTwo", "first": "Ana", "last": "Silva",
				"country": "PT", "born": "2006-09-01"},
			{"tag": "TestThree"},
		]}}},
	})
	DataPack.set_active(TEST_PACK)

	var world := WorldGenerator.generate(999, GameDate.from_ymd(2026, 1, 5))
	t.eq(world.data_pack, TEST_PACK,
		"le monde retient le pack avec lequel il a été créé")

	var target: Organization = null
	for oid in world.orgs:
		if (world.orgs[oid] as Organization).name == TEST_TEAM:
			target = world.orgs[oid]
	t.check(target != null, "la structure visée existe dans le monde")
	if target == null:
		DataPack.set_active("")
		_cleanup()
		return t

	var roster := world.main_roster(target.id, "valorant")
	var by_tag := {}
	for p in world.players_of(roster.id):
		by_tag[p.display_name()] = p

	t.check(by_tag.has("TestOne"), "le premier joueur du pack est dans l'effectif")
	t.check(by_tag.has("TestTwo"), "le deuxième aussi")
	t.check(by_tag.has("TestThree"), "et celui qui n'a qu'un pseudo")

	if by_tag.has("TestOne"):
		var one: Player = by_tag["TestOne"]
		t.eq(one.full_name(), "Jean Dupont", "le nom civil est repris")
		t.eq(one.nationality, "BE", "la nationalité est reprise")
		t.eq(one.age(world.today), 21, "la date de naissance donne le bon âge")
		t.check(one.is_igl, "le capitaine désigné par le pack est l'IGL")
		# Ce que le pack N'apporte PAS doit rester simulé.
		t.between(float(one.current_ability), 1.0, 200.0,
			"la capacité reste générée par le moteur")
		t.check(not one.attributes.is_empty(),
			"les attributs restent générés par le moteur")

	if by_tag.has("TestThree"):
		var three: Player = by_tag["TestThree"]
		t.check(three.full_name().strip_edges() != "",
			"un joueur sans nom civil en reçoit un généré")

	# Un seul IGL malgré le tirage habituel.
	var igls := 0
	for p in world.players_of(roster.id):
		if p.is_igl:
			igls += 1
	t.eq(igls, 1, "le pack ne crée pas un second capitaine")

	# Une structure absente du pack garde un effectif entièrement généré.
	var other: Roster = null
	for rid in world.rosters:
		var r: Roster = world.rosters[rid]
		if r.org_id != target.id and r.league_key == "vct_emea":
			other = r
			break
	if other != null:
		t.check(world.players_of(other.id).size() >= 5,
			"une structure hors pack garde un effectif complet")

	DataPack.set_active("")
	_cleanup()
	return t


# ============================================================================
# Fabrique de pack jetable
# ============================================================================

static func _write_pack(files: Dictionary) -> void:
	var root := DataPack.user_root_of(TEST_PACK)
	DirAccess.make_dir_recursive_absolute(root + "/world")
	DataFile.save_json(root + "/" + DataPack.MANIFEST, {
		"name": "Pack de test",
		"author": "suite de tests",
		"license": "CC-BY-SA 3.0",
		"source": "aucune",
		"attribution": "pack de test",
	})
	for path in files:
		DataFile.save_json("%s/%s" % [root, str(path)], files[path])
	DataPack.forget()


static func _cleanup() -> void:
	DataPack.set_active("")
	DataPack.forget()
	var root := DataPack.user_root_of(TEST_PACK)
	_remove_recursive(root)


static func _remove_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)
	for sub in dir.get_directories():
		_remove_recursive("%s/%s" % [path, sub])
	DirAccess.remove_absolute(path)
