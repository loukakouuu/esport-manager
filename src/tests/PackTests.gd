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
	return [_resolution(), _world_override()]


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
	var root := DataPack.root_of(TEST_PACK)
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
	var root := DataPack.root_of(TEST_PACK)
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
