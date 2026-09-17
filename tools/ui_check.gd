extends SceneTree

## Vérification de l'interface en headless.
##
## Quatre contrôles :
##  1. chaque écran se CONSTRUIT sans erreur d'exécution sur un monde réel ;
##  2. chaque ONGLET de chaque écran se construit aussi — sinon on ne teste
##     qu'un sixième de la fiche joueur ;
##  3. l'arbre produit respecte les invariants de mise en page de Godot ;
##  4. le tout sur DEUX états du monde — une structure installée et une
##     structure fondée le matin même, qui seule passe par les branches
##     « il n'y a rien à montrer ».
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
	"StartScreen": "res://src/ui/screens/StartScreen.gd",
	"NewGameScreen": "res://src/ui/screens/NewGameScreen.gd",
	"FoundScreen": "res://src/ui/screens/FoundScreen.gd",
	"HomeScreen": "res://src/ui/screens/HomeScreen.gd",
	"ClubScreen": "res://src/ui/screens/ClubScreen.gd",
	"SquadScreen": "res://src/ui/screens/SquadScreen.gd",
	"PlayerScreen": "res://src/ui/screens/PlayerScreen.gd",
	"TacticsScreen": "res://src/ui/screens/TacticsScreen.gd",
	"TrainingScreen": "res://src/ui/screens/TrainingScreen.gd",
	"DynamicsScreen": "res://src/ui/screens/DynamicsScreen.gd",
	"CalendarScreen": "res://src/ui/screens/CalendarScreen.gd",
	"CompetitionScreen": "res://src/ui/screens/CompetitionScreen.gd",
	"TransfersScreen": "res://src/ui/screens/TransfersScreen.gd",
	"NegotiationScreen": "res://src/ui/screens/NegotiationScreen.gd",
	"FinanceScreen": "res://src/ui/screens/FinanceScreen.gd",
	"StaffScreen": "res://src/ui/screens/StaffScreen.gd",
	"FacilitiesScreen": "res://src/ui/screens/FacilitiesScreen.gd",
	"InboxScreen": "res://src/ui/screens/InboxScreen.gd",
	"MatchScreen": "res://src/ui/screens/MatchScreen.gd",
}

## Constantes d'écran décrivant une barre d'onglets, dans l'ordre de recherche.
const TAB_CONSTANTS := ["TABS", "VIEWS"]


## Deux états du monde, parce qu'un seul ne prouve pas grand-chose.
##
## La plupart des défauts d'affichage vivent dans les branches « il n'y a rien
## à montrer » : pas de match programmé, effectif vide, phase pas commencée,
## aucun classement. Une structure installée depuis deux mois ne passe jamais
## par ces branches ; une structure fondée le matin même n'y passe que par là.
## Le troisième scénario existe depuis l'arrivée d'une deuxième discipline :
## une maison à deux sections, DIRIGÉE PAR SA SECTION COUNTER-STRIKE. Les
## écrans d'équipe lisent le module de la discipline dirigée — colonnes de
## statistiques, postes, curseurs tactiques — et un balayage qui ne verrait
## jamais que Valorant ne prouverait rien sur eux.
const SCENARIOS := [
	["reprise", "structure de Challengers, deux mois de jeu"],
	["fondation", "structure fondée de zéro, avant le premier match"],
	["cs2", "maison à deux sections, dirigée côté Counter-Strike"],
]


func _initialize() -> void:
	var failures := 0
	var views := 0
	for entry_v in SCENARIOS:
		var entry: Array = entry_v
		print("\n### %s — %s" % [str(entry[0]), str(entry[1])])
		var result := _pass(str(entry[0]))
		views += int(result[0])
		failures += int(result[1])

	print("\n%d vue(s) vérifiée(s), %d écran(s) en défaut" % [views, failures])
	quit(1 if failures > 0 else 0)


## Construit un monde selon le scénario puis balaie tous les écrans.
## Renvoie [vues vérifiées, écrans en défaut].
func _pass(kind: String) -> Array:
	var game := preload("res://autoload/Game.gd").new()
	game.name = "Game_" + kind
	root.add_child(game)
	game.new_world(4242)
	if kind == "fondation":
		game.found_org({
			"name": "Atelier Test", "tag": "ATT", "region": "EMEA",
			"country": "FR", "color": "#4aa8ff", "capital_tier": "seed",
		})
	elif kind == "cs2":
		# On cherche une maison qui tient VRAIMENT deux sections : c'est elle
		# qui met les écrans en difficulté, pas une structure 100 % CS.
		var pick := _two_section_org(game.world)
		game.choose_org(str(pick[0]), str(pick[1]))
		for _i in 70:
			game.advance_day()
	else:
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
			# Effectif vide : la fiche joueur doit encaisser un identifiant
			# absent sans planter — c'est l'état d'une structure fondée.
			var r = game.my_roster()
			scr.set("player_id", r.player_ids[0] if not r.player_ids.is_empty() else "")

		if name == "NegotiationScreen":
			# La table de négociation a besoin d'une discussion ouverte : on en
			# entame une avec le premier agent libre venu.
			var target := _some_free_agent(game.world)
			if target != null:
				var n = game.open_negotiation(target.id)
				scr.set("negotiation_id", n.id if n != null else "")

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

	stub.queue_free()
	game.queue_free()
	return [views_checked, failures]


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
	_check_nested_scroll(sc, sc, problems, path)


## Deux ScrollContainer imbriqués qui défilent sur LE MÊME AXE : l'extérieur
## donne à l'intérieur sa hauteur (ou largeur) minimale, c'est-à-dire zéro, et
## le contenu disparaît sans erreur.
##
## L'imbrication reste légitime sur des axes DIFFÉRENTS — c'est exactement ce
## que fait UiKit.data_table, dont le défilement horizontal contient le
## défilement vertical. On ne signale donc que le recouvrement d'axe.
func _check_nested_scroll(outer: ScrollContainer, node: Node,
		problems: Array[String], path: String) -> void:
	for i in node.get_child_count():
		var child := node.get_child(i)
		if child is ScrollBar:
			continue
		if child is ScrollContainer:
			var inner := child as ScrollContainer
			var shared := _shared_axes(outer, inner)
			for axis in shared:
				problems.append("%s : deux ScrollContainer imbriqués défilent "
					% path + "en %s — l'intérieur sera écrasé à zéro" % axis)
			if not shared.is_empty():
				continue   # déjà signalé, inutile de descendre plus loin
		# On descend même à travers un ScrollContainer d'axe compatible : la
		# hauteur se transmet, et le conflit peut apparaître deux niveaux plus
		# bas (data_table place son défilement vertical sous l'horizontal).
		_check_nested_scroll(outer, child, problems, path)


func _shared_axes(a: ScrollContainer, b: ScrollContainer) -> Array[String]:
	var out: Array[String] = []
	if a.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED \
			and b.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		out.append("vertical")
	if a.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED \
			and b.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		out.append("horizontal")
	return out


func _count(node: Node) -> int:
	var n := 1
	for c in node.get_children():
		n += _count(c)
	return n


## Premier agent libre de la discipline jouée, ou null.
func _some_free_agent(world: World) -> Player:
	for p in world.free_agents(world.player_game_id):
		return p
	return null


## Une maison qui aligne au moins deux sections, et l'équipe de sa discipline
## la moins « historique » — celle qu'on veut voir à l'écran.
## Renvoie [org_id, roster_id].
func _two_section_org(world: World) -> Array:
	var fallback := ["", ""]
	for oid in world.orgs:
		var o: Organization = world.orgs[oid]
		var rosters := world.rosters_of(o.id)
		if rosters.size() < 2:
			continue
		for r in rosters:
			if r.game_id != "valorant" and not r.is_academy:
				return [o.id, r.id]
		fallback = [o.id, rosters[0].id]
	return fallback
