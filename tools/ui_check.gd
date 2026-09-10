extends SceneTree

## Vérification de l'interface en headless.
##
## Deux contrôles :
##  1. chaque écran se CONSTRUIT sans erreur d'exécution sur un monde réel ;
##  2. l'arbre produit respecte les invariants de mise en page de Godot.
##
## Le contrôle 2 existe parce que le contrôle 1 seul est un piège : un écran
## peut se construire parfaitement et s'afficher n'importe comment. Le bug
## typique est d'ajouter plusieurs enfants à un conteneur qui les EMPILE
## (PanelContainer, MarginContainer, ScrollContainer…) : tous les libellés se
## superposent au même endroit. Aucun test « ça ne plante pas » ne l'attrape.

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
	"CalendarScreen": "res://src/ui/screens/CalendarScreen.gd",
	"CompetitionScreen": "res://src/ui/screens/CompetitionScreen.gd",
	"TransfersScreen": "res://src/ui/screens/TransfersScreen.gd",
	"FinanceScreen": "res://src/ui/screens/FinanceScreen.gd",
	"FacilitiesScreen": "res://src/ui/screens/FacilitiesScreen.gd",
	"InboxScreen": "res://src/ui/screens/InboxScreen.gd",
	"MatchScreen": "res://src/ui/screens/MatchScreen.gd",
	"NewGameScreen": "res://src/ui/screens/NewGameScreen.gd",
}


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
	for name in SCREENS:
		var scr: Node = load(SCREENS[name]).new()
		scr.setup(stub)
		stub.add_child(scr)
		if name == "PlayerScreen":
			var r = game.my_roster()
			scr.set("player_id", r.player_ids[0] if not r.player_ids.is_empty() else "")
		scr.refresh()

		var problems: Array[String] = []
		_inspect(scr, problems, name)
		var nodes := _count(scr)
		if scr.get_child_count() == 0:
			problems.append("aucun élément produit")
		if problems.is_empty():
			print("  [OK]   %-20s %4d noeuds" % [name, nodes])
		else:
			failures += 1
			print("  [KO]   %-20s %4d noeuds" % [name, nodes])
			for p in problems:
				print("           - %s" % p)
		scr.queue_free()

	print("\n%d écran(s) en défaut" % failures)
	quit(1 if failures > 0 else 0)


## Parcourt l'arbre et signale les violations d'invariants de mise en page.
func _inspect(node: Node, problems: Array[String], path: String) -> void:
	var cls := node.get_class()
	if SINGLE_CHILD_CONTAINERS.has(cls) and node.get_child_count() > 1:
		problems.append("%s (%s) a %d enfants : ils vont se superposer"
			% [path, cls, node.get_child_count()])
	for i in node.get_child_count():
		var child := node.get_child(i)
		_inspect(child, problems, "%s/%s" % [path, child.get_class()])


func _count(node: Node) -> int:
	var n := 1
	for c in node.get_children():
		n += _count(c)
	return n
