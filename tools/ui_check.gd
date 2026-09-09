extends SceneTree

## Vérification de l'interface en headless.
##
## On ne peut pas cliquer dans une interface depuis un test, mais on peut
## l'INSTANCIER : chaque écran est construit sur un monde réel, ce qui attrape
## la quasi-totalité des erreurs d'exécution (champ manquant, mauvais type,
## division par zéro sur une équipe vide) avant de lancer le jeu.

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
	# Quelques semaines pour avoir des matchs joués, des news et des stats.
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
		var children: int = scr.get_child_count()
		if children == 0:
			print("  [VIDE] %s n'a produit aucun élément" % name)
			failures += 1
		else:
			print("  [OK]   %-20s %d éléments" % [name, children])
		scr.queue_free()
	print("\n%d écran(s) en défaut" % failures)
	quit(1 if failures > 0 else 0)


