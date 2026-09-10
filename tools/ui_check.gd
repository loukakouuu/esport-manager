extends SceneTree

## Vérification de l'interface en headless.
##
## Trois contrôles :
##  1. chaque écran se CONSTRUIT sans erreur d'exécution sur un monde réel ;
##  2. chaque ONGLET de chaque écran se construit aussi — sinon on ne teste
##     qu'un sixième de la fiche joueur ;
##  3. l'arbre produit respecte les invariants de mise en page de Godot.
##
## Le contrôle 3 existe parce que le contrôle 1 seul est un piège : un écran
## peut se construire parfaitement et s'afficher n'importe comment. Le bug
## typique est d'ajouter plusieurs enfants à un conteneur qui les EMPILE
## (PanelContainer, MarginContainer, ScrollContainer…) : tous les libellés se
## superposent au même endroit. Aucun test « ça ne plante pas » ne l'attrape.
##
## Ces contrôles ne remplacent PAS de regarder les captures d'écran
## (`godot --path . -- --shots=all`) : ils attrapent les fautes de structure,
## pas les fautes de goût.

## Conteneurs qui n'acceptent qu'un seul enfant : au-delà, les enfants se
## superposent dans le même rectangle.
const SINGLE_CHILD_CONTAINERS := [
	"PanelContainer", "MarginContainer", "CenterContainer",
	"ScrollContainer", "AspectRatioContainer",
]

const SCREENS := {
	"HomeScreen": "res://src/ui/screens/HomeScreen.gd",
	"SquadScreen": "res://src/ui/screens/SquadScreen.gd",
	"PlayerScreen": "res://src/ui/screens/PlayerScreen.gd",
	"TacticsScreen": "res://src/ui/screens/TacticsScreen.gd",
	"TrainingScreen": "res://src/ui/screens/TrainingScreen.gd",
	"DynamicsScreen": "res://src/ui/screens/DynamicsScreen.gd",
	"CalendarScreen": "res://src/ui/screens/CalendarScreen.gd",
	"CompetitionScreen": "res://src/ui/screens/CompetitionScreen.gd",
	"TransfersScreen": "res://src/ui/screens/TransfersScreen.gd",
	"FinanceScreen": "res://src/ui/screens/FinanceScreen.gd",
	"FacilitiesScreen": "res://src/ui/screens/FacilitiesScreen.gd",
	"InboxScreen": "res://src/ui/screens/InboxScreen.gd",
	"MatchScreen": "res://src/ui/screens/MatchScreen.gd",
	"NewGameScreen": "res://src/ui/screens/NewGameScreen.gd",
}

## Constantes d'écran décrivant une barre d'onglets, dans l'ordre de recherche.
const TAB_CONSTANTS := ["TABS", "VIEWS"]


func _initialize() -> void:
	var game := preload("res://autoload/Game.gd").new()
	game.name = "Game"
	root.add_child(game)

	print("Génération du monde de test…")
	game.new_world(4242)
	var candidates := WorldGenerator.selectable_orgs(game.world, "chal_emea")
	game.choose_org(str(candidates[0]["org_id"]))
	for _i in 70:
		game.advance_day()

	var stub := preload("res://tools/AppStub.gd").new()
	stub.game = game
	root.add_child(stub)

	var failures := 0
	var views_checked := 0
	for name in SCREENS:
		var script: GDScript = load(SCREENS[name])
		if script == null:
			failures += 1
			print("  [KO]   %-20s script illisible" % name)
			continue
		var scr: Node = script.new()
		scr.setup(stub)
		stub.add_child(scr)
		if name == "PlayerScreen":
			var r = game.my_roster()
			scr.set("player_id", r.player_ids[0] if not r.player_ids.is_empty() else "")

		var tabs := _tabs_of(script)
		var screen_failed := false
		for tab in tabs:
			stub.force_tab = str(tab)
			scr.refresh()
			views_checked += 1
			var label: String = name if str(tab) == "" else "%s · %s" % [name, tab]
			var problems: Array[String] = []
			_inspect(scr, problems, name)
			if scr.get_child_count() == 0:
				problems.append("aucun élément produit")
			if problems.is_empty():
				print("  [OK]   %-32s %4d noeuds" % [label, _count(scr)])
			else:
				screen_failed = true
				print("  [KO]   %-32s %4d noeuds" % [label, _count(scr)])
				for p in problems:
					print("           - %s" % p)
		if screen_failed:
			failures += 1
		stub.force_tab = ""
		scr.queue_free()

	print("\n%d vue(s) vérifiée(s), %d écran(s) en défaut"
		% [views_checked, failures])
	quit(1 if failures > 0 else 0)


## Clés d'onglets déclarées par un écran, ou [""] s'il n'en a pas.
func _tabs_of(script: GDScript) -> Array:
	var consts := script.get_script_constant_map()
	for key in TAB_CONSTANTS:
		if not consts.has(key):
			continue
		var out: Array = []
		for entry in consts[key]:
			out.append(str((entry as Array)[0]))
		if not out.is_empty():
			return out
	return [""]


## Parcourt l'arbre et signale les violations d'invariants de mise en page.
func _inspect(node: Node, problems: Array[String], path: String) -> void:
	var cls := node.get_class()
	if SINGLE_CHILD_CONTAINERS.has(cls) and node.get_child_count() > 1:
		problems.append("%s (%s) a %d enfants : ils vont se superposer"
			% [path, cls, node.get_child_count()])
	if node is ScrollContainer:
		_check_scroll(node as ScrollContainer, problems, path)
	for i in node.get_child_count():
		var child := node.get_child(i)
		_inspect(child, problems, "%s/%s" % [path, child.get_class()])


## Un ScrollContainer dimensionne son enfant d'après les SIZE_EXPAND de
## L'ENFANT, jamais les siens. Sur un axe où le défilement est DÉSACTIVÉ, un
## enfant sans SIZE_EXPAND retombe donc à sa taille minimale — c'est-à-dire
## qu'il disparaît, silencieusement et sans la moindre erreur.
func _check_scroll(sc: ScrollContainer, problems: Array[String],
		path: String) -> void:
	for i in sc.get_child_count():
		var child := sc.get_child(i)
		if not (child is Control) or child is ScrollBar:
			continue
		var c := child as Control
		if sc.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED \
				and not (c.size_flags_horizontal & Control.SIZE_EXPAND):
			problems.append("%s : défilement horizontal désactivé mais l'enfant "
				% path + "%s n'a pas SIZE_EXPAND — il sera réduit à sa largeur "
				% c.get_class() + "minimale")
		if sc.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED \
				and not (c.size_flags_vertical & Control.SIZE_EXPAND):
			problems.append("%s : défilement vertical désactivé mais l'enfant "
				% path + "%s n'a pas SIZE_EXPAND — il sera réduit à sa hauteur "
				% c.get_class() + "minimale")


func _count(node: Node) -> int:
	var n := 1
	for c in node.get_children():
		n += _count(c)
	return n
