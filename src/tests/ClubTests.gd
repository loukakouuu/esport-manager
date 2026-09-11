class_name ClubTests
extends RefCounted

## Tests de la STRUCTURE multi-sections.
##
## Ce qui se joue ici : une structure esport aligne plusieurs disciplines, le
## moteur n'en simule qu'une, et l'interface doit présenter les deux sans
## mentir. Les pièges sont silencieux — une discipline inconnue qui crée une
## section fantôme, une sélection de section qui laisse les écrans « Équipe »
## sur l'équipe précédente, une sauvegarde qui oublie l'équipe dirigée.

const PACK := "__club_test_pack__"


static func run() -> Array[TestCase]:
	return [_catalog(), _declared_games(), _sections_and_selection()]


# ============================================================================

static func _catalog() -> TestCase:
	var t := TestCase.new("Catalogue — disciplines connues")

	t.check(GameCatalog.known("valorant"), "Valorant est au catalogue")
	t.check(not GameCatalog.known("pong"), "une discipline inventée ne l'est pas")
	t.check(GameCatalog.playable("valorant"), "Valorant est simulé")
	t.check(not GameCatalog.playable("lol"),
		"League of Legends est connu mais pas encore simulé")
	t.eq(GameCatalog.short("cs2"), "CS2", "le sigle est celui du catalogue")

	# sanitize() est la seule porte d'entrée des données : une faute de frappe
	# dans un pack ne doit jamais devenir une section.
	var clean := GameCatalog.sanitize(["LoL", "pong", "cs2", "lol", "valorant"])
	t.eq(clean.size(), 3, "les inconnus sont écartés et les doublons fusionnés")
	t.eq(clean[0], "valorant", "Valorant passe en premier")
	t.check(clean.has("cs2") and clean.has("lol"), "le reste est conservé")
	t.eq(GameCatalog.sanitize("pas un tableau").size(), 0,
		"une valeur qui n'est pas un tableau donne une liste vide")

	# L'ordre doit être stable, sinon les onglets de section dansent d'un
	# rafraîchissement à l'autre.
	t.eq(GameCatalog.sanitize(["cs2", "lol"]), GameCatalog.sanitize(["lol", "cs2"]),
		"l'ordre ne dépend pas de celui des données")
	return t


# ============================================================================

static func _declared_games() -> TestCase:
	var t := TestCase.new("Structure — disciplines déclarées")
	_cleanup()
	# Un pack qui déclare explicitement les sections de deux structures.
	_write_pack({"world/orgs.json": _orgs_with([
		{"name": "Testonia", "tag": "TST", "country": "FR", "strength": 84,
			"owner": "investor", "games": ["lol", "valorant", "pong"]},
		{"name": "Monojeu", "tag": "MNO", "country": "FR", "strength": 60,
			"owner": "self_funded", "games": ["valorant"]},
	])})
	DataPack.set_active(PACK)

	var world := WorldGenerator.generate(4242, GameDate.from_ymd(2026, 1, 5))
	var multi := _org_named(world, "Testonia")
	var solo := _org_named(world, "Monojeu")
	t.check(multi != null and solo != null, "les deux structures existent")
	if multi == null or solo == null:
		DataPack.set_active("")
		_cleanup()
		return t

	t.eq(multi.games.size(), 2, "la discipline inconnue du pack est ignorée")
	t.eq(multi.games[0], "valorant", "Valorant reste en tête")
	t.check(multi.has_game("lol"), "la section LoL déclarée est retenue")
	t.eq(multi.playable_games(), ["valorant"] as Array[String],
		"seule la discipline simulée est jouable")
	t.eq(multi.upcoming_games(), ["lol"] as Array[String],
		"LoL est annoncé, pas jouable")
	t.eq(solo.games.size(), 1, "une structure mono-jeu le reste")

	# Une section non simulée ne doit surtout PAS créer de roster : elle
	# entrerait dans le calendrier, les finances et les classements.
	t.eq(world.rosters_of(multi.id).size(), 1,
		"une seule équipe est créée, celle de la discipline simulée")
	t.eq(world.rosters_of(multi.id)[0].game_id, "valorant",
		"et c'est bien l'équipe Valorant")

	# Aller-retour de sérialisation : le champ est jeune, c'est exactement le
	# genre d'oubli qui ne se voit qu'au rechargement d'une vieille partie.
	var back := Organization.from_dict(multi.to_dict())
	t.eq(back.games, multi.games, "les disciplines survivent à la sauvegarde")
	var legacy := Organization.from_dict({"id": "o1", "name": "Ancienne"})
	t.eq(legacy.games, ["valorant"] as Array[String],
		"une sauvegarde d'avant les sections retombe sur Valorant")

	DataPack.set_active("")
	_cleanup()
	return t


# ============================================================================

static func _sections_and_selection() -> TestCase:
	var t := TestCase.new("Structure — sections et bascule d'équipe")
	_cleanup()
	_write_pack({"world/orgs.json": _orgs_with([
		{"name": "Testonia", "tag": "TST", "country": "FR", "strength": 84,
			"owner": "investor", "games": ["valorant", "cs2", "rl"]},
		{"name": "Rivale", "tag": "RIV", "country": "FR", "strength": 70,
			"owner": "investor", "games": ["valorant"]},
	])})
	DataPack.set_active(PACK)

	# La façade est un Node non typé pour l'analyseur : sans variable typée
	# pour le monde, aucune inférence ne fonctionne dans ce test.
	var facade: Node = load("res://autoload/Game.gd").new()
	var w: World = WorldGenerator.generate(31337, GameDate.from_ymd(2026, 1, 5))
	facade.world = w
	var mine := _org_named(w, "Testonia")
	var rival := _org_named(w, "Rivale")
	if mine == null or rival == null:
		t.check(false, "les structures de test existent")
		facade.free()
		DataPack.set_active("")
		_cleanup()
		return t
	facade.choose_org(mine.id)

	var sections: Array = facade.sections()
	t.eq(sections.size(), 3, "une entrée par discipline de la structure")
	var current := 0
	var playable := 0
	for s_v in sections:
		var s: Dictionary = s_v
		if bool(s["current"]):
			current += 1
		if bool(s["playable"]):
			playable += 1
			t.check(str(s["roster_id"]) != "",
				"une section jouable désigne une équipe")
		else:
			t.eq(str(s["roster_id"]), "",
				"une section non simulée ne désigne aucune équipe")
	t.eq(current, 1, "exactement une section est dirigée")
	t.eq(playable, 1, "une seule discipline est simulée aujourd'hui")

	# La bascule doit rester dans la maison : sinon c'est une porte dérobée
	# vers l'effectif d'un rival.
	var rival_roster := w.main_roster(rival.id, "valorant")
	t.check(not facade.select_roster(rival_roster.id),
		"on ne peut pas prendre la main sur l'équipe d'un rival")
	t.eq(w.my_roster().org_id, mine.id, "l'équipe dirigée n'a pas changé")
	t.check(not facade.select_roster("roster_inexistant"),
		"un identifiant inconnu est refusé")

	var own := w.main_roster(mine.id, "valorant")
	t.check(facade.select_roster(own.id), "sa propre équipe est acceptée")
	t.eq(w.player_roster_id, own.id, "la sélection est enregistrée")
	t.eq(w.my_roster().id, own.id,
		"my_roster() suit la sélection — c'est ce que lisent tous les écrans")

	# La section dirigée fait partie de la partie, pas de l'affichage : elle
	# doit survivre à une sauvegarde.
	var reloaded := World.from_dict(w.to_dict())
	t.eq(reloaded.player_roster_id, own.id,
		"l'équipe dirigée survit à la sauvegarde")
	t.eq(reloaded.my_roster().id, own.id, "et se retrouve au rechargement")

	# Sans sélection explicite, on retombe sur l'équipe principale.
	reloaded.player_roster_id = ""
	t.eq(reloaded.my_roster().id, own.id,
		"une partie sans section choisie ouvre sur l'équipe principale")

	facade.free()
	DataPack.set_active("")
	_cleanup()
	return t


# ============================================================================
# Pack jetable
# ============================================================================

## Fichier de structures qui REPREND celui livré et n'y remplace que les
## premières entrées de VCT EMEA.
##
## Un pack qui ne contiendrait que deux équipes ferait disparaître les huit
## ligues et toute la pyramide : le monde généré ne ressemblerait à rien de ce
## que voit un joueur, et le test ne prouverait plus grand-chose.
static func _orgs_with(entries: Array) -> Dictionary:
	DataPack.set_active("")
	var base = DataFile.load_json("res://data/world/orgs.json", {})
	var out: Dictionary = (base as Dictionary).duplicate(true)
	var leagues: Dictionary = out.get("leagues", {})
	var vct: Array = (leagues.get("vct_emea", []) as Array).duplicate(true)
	for i in entries.size():
		if i < vct.size():
			vct[i] = entries[i]
	leagues["vct_emea"] = vct
	out["leagues"] = leagues
	return out


static func _org_named(world: World, name: String) -> Organization:
	for oid in world.orgs:
		if (world.orgs[oid] as Organization).name == name:
			return world.orgs[oid]
	return null


static func _write_pack(files: Dictionary) -> void:
	var root := DataPack.user_root_of(PACK)
	DirAccess.make_dir_recursive_absolute(root + "/world")
	DataFile.save_json(root + "/" + DataPack.MANIFEST, {
		"name": "Pack de test (sections)",
		"author": "suite de tests",
	})
	for path in files:
		DataFile.save_json("%s/%s" % [root, str(path)], files[path])
	DataPack.forget()


static func _cleanup() -> void:
	DataPack.set_active("")
	DataPack.forget()
	_remove_recursive(DataPack.user_root_of(PACK))


static func _remove_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)
	for sub in dir.get_directories():
		_remove_recursive("%s/%s" % [path, sub])
	DirAccess.remove_absolute(path)
