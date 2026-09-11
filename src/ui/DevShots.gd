class_name DevShots
extends RefCounted

## Harnais de capture d'écran pour le développement.
##
## Raison d'être : une interface qui « se construit sans erreur » peut très
## bien s'afficher n'importe comment. Les tests headless ne rendent rien ; il
## faut donc pouvoir produire des images réelles automatiquement, sinon la
## seule vérification possible est de cliquer soi-même dans chaque écran.
##
## Usage :
##   godot --path . -- --shots=home,squad,finance
##   godot --path . -- --shots=all
##
## Les PNG sont écrits dans user://shots/ et le chemin absolu est imprimé.

const SETUP_DAYS := 80
const SETTLE_FRAMES := 4


static func requested() -> Array[String]:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			var list := arg.substr(8)
			var out: Array[String] = []
			for s in list.split(","):
				if s.strip_edges() != "":
					out.append(s.strip_edges())
			return out
	return []


static func is_requested() -> bool:
	return not requested().is_empty()


## Prépare une partie jouable puis capture les écrans demandés.
static func run(app: Control, game: Node) -> void:
	var names := requested()
	var dir := "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)

	# Écrans d'AVANT-PARTIE : ils ne figurent pas dans SCREENS (ils n'ont ni
	# navigation ni barre haute) et doivent être photographiés au bon moment —
	# l'accueil avant que le monde existe, le sélecteur juste après.
	var want_all := names.size() == 1 and names[0] == "all"
	if want_all or names.has("start"):
		await _shoot_front(app, dir, "start")

	print("[shots] préparation du monde…")
	game.new_world(20260105)
	if want_all or names.has("picker"):
		# Deux ligues : les Challengers sont fictifs, le VCT vient du pack de
		# données. Une seule capture ne montrerait pas les vraies sections.
		for league in ["chal_emea", "vct_emea"]:
			app.call("ui_state", "newgame")["tab"] = league
			await _shoot_front(app, dir, "picker-%s" % league)
	var candidates := WorldGenerator.selectable_orgs(game.world, "chal_emea")
	game.choose_org(str(candidates[candidates.size() / 2]["org_id"]))
	for _i in SETUP_DAYS:
		game.advance_day()
	print("[shots] %s — %s" % [game.my_org().name,
		GameDate.format_long(game.world.today)])

	var all: Array[String] = app.call("screen_names")
	if want_all:
		names = all
	# Déjà photographiés plus haut : les retirer évite un « écran inconnu ».
	names.erase("start")
	names.erase("picker")

	for name in names:
		if not all.has(name):
			print("[shots] écran inconnu : %s" % name)
			continue
		var args := {}
		if name == "player":
			var r = game.my_roster()
			if not r.player_ids.is_empty():
				args = {"player_id": r.player_ids[0]}
		app.navigate(name, args)

		# Un écran à onglets n'est pas photographié par sa seule page d'accueil :
		# c'est exactement là que les défauts d'affichage se cachent.
		for tab in _tabs_of(app, name):
			if tab != "":
				app.call("ui_state", _state_key(name))["tab"] = tab
				app.call("navigate", name, args)
			for _f in SETTLE_FRAMES:
				await RenderingServer.frame_post_draw
			var img := app.get_viewport().get_texture().get_image()
			var suffix: String = "" if tab == "" else "-" + str(tab)
			var path := "%s/%s%s.png" % [dir, name, suffix]
			img.save_png(path)
			print("[shots] %s%s -> %s" % [name, suffix, path])

	print("[shots] dossier : %s/shots" % OS.get_user_data_dir())
	app.get_tree().quit(0)


## Capture un écran d'avant-partie. `show_front()` choisit lui-même entre
## l'accueil et le sélecteur selon qu'un monde existe : le nom passé ici ne
## sert qu'à nommer le fichier.
static func _shoot_front(app: Control, dir: String, name: String) -> void:
	app.call("show_front")
	for _f in SETTLE_FRAMES:
		await RenderingServer.frame_post_draw
	var img := app.get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [dir, name]
	img.save_png(path)
	print("[shots] %s -> %s" % [name, path])


## Clé d'état d'affichage utilisée par un écran. Convention du projet : le nom
## de l'écran, sauf pour l'effectif dont la barre s'appelle "squad".
static func _state_key(screen_name: String) -> String:
	return screen_name


## Onglets déclarés par l'écran (const TABS ou VIEWS), ou [""] s'il n'en a pas.
static func _tabs_of(app: Control, screen_name: String) -> Array:
	var screens: Dictionary = app.get("SCREENS")
	if not screens.has(screen_name):
		return [""]
	var script: GDScript = screens[screen_name]
	var consts := script.get_script_constant_map()
	for key in ["TABS", "VIEWS"]:
		if not consts.has(key):
			continue
		var out: Array = []
		for entry in consts[key]:
			out.append(str((entry as Array)[0]))
		if not out.is_empty():
			return out
	return [""]
