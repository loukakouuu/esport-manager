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
## Une structure fondée n'a pas encore joué : on s'arrête avant son premier
## match, là où le mode a son vrai visage — un effectif à composer.
const FOUNDED_DAYS := 20
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

	# Pas de fondu d'entrée pendant une capture : l'image serait prise au milieu
	# de la transition, à une opacité qui dépend de la cadence de la machine.
	# Deux exécutions ne donneraient pas le même PNG, et comparer deux captures
	# est précisément ce à quoi elles servent.
	app.set("transitions", false)

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
	if want_all or names.has("found"):
		app.call("ui_state", "start")["mode"] = "found"
		app.call("ui_state", "found")["name"] = "Atelier Neuf"
		await _shoot_front(app, dir, "found")
		app.call("ui_state", "start")["mode"] = "takeover"

	# « founded » remplace la reprise par une fondation : l'état du jeu est
	# radicalement différent — effectif vide, aucune réputation — et c'est
	# précisément ce qu'on veut pouvoir regarder.
	if names.has("founded"):
		names.erase("founded")
		game.found_org({
			"name": "Atelier Neuf", "tag": "AT9", "region": "EMEA",
			"country": "FR", "color": "#4aa8ff", "capital_tier": "seed",
		})
		for _i in FOUNDED_DAYS:
			game.advance_day()
	else:
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
	names.erase("found")

	for name in names:
		if not all.has(name):
			print("[shots] écran inconnu : %s" % name)
			continue
		var args := {}
		if name == "player":
			var r = game.my_roster()
			if not r.player_ids.is_empty():
				args = {"player_id": r.player_ids[0]}
		elif name == "negotiation":
			# La table de négociation n'existe qu'attachée à une discussion :
			# on en ouvre une avec le meilleur agent libre du moment.
			var target := _best_free_agent(game.world)
			if target != null:
				var n = game.open_negotiation(target.id)
				if n != null:
					args = {"negotiation_id": n.id}
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


## Meilleur agent libre de la discipline jouée : une capture d'écran vaut mieux
## avec un joueur qu'on aurait vraiment envie de signer.
static func _best_free_agent(world: World) -> Player:
	var best: Player = null
	for p in world.free_agents(world.player_game_id):
		if best == null or p.current_ability > best.current_ability:
			best = p
	return best
