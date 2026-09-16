class_name Screen
extends VBoxContainer

## Base de tous les écrans.
##
## Un écran ne stocke aucun état de jeu : il se reconstruit intégralement à
## partir du World à chaque refresh(). C'est volontairement « bête » — pour un
## jeu de gestion au tour par tour, la simplicité de raisonnement vaut mille
## fois l'optimisation d'un rendu incrémental.
##
## Corollaire : un `var` d'écran ne survit pas à un rafraîchissement. Tout ce
## qui doit persister (onglet actif, tri d'un tableau, filtre) passe par
## `ui()`, qui délègue à App.view_state.

var app: Control = null


func setup(p_app: Control) -> void:
	app = p_app
	add_theme_constant_override("separation", 10)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL


func refresh() -> void:
	for c in get_children():
		c.queue_free()
	build()


func build() -> void:
	pass


func world() -> World:
	return app.get("game").world


func game() -> Node:
	return app.get("game")


func navigate(screen_name: String, args: Dictionary = {}) -> void:
	app.call("navigate", screen_name, args)


## Mémoire d'affichage persistante, propre à une clé (« squad.sort »).
func ui(key: String) -> Dictionary:
	return app.call("ui_state", key)


## Barre d'onglets qui rafraîchit l'écran quand on change de section.
func tab_bar(key: String, items: Array, default_key: String = "") -> Control:
	return UiKit.tabs(items, ui(key), "tab", func(_k): refresh(), default_key)


func current_tab(key: String, default_key: String) -> String:
	return str(ui(key).get("tab", default_key))


## Tableau trié dont l'ordre survit au rafraîchissement.
func sorted_table(key: String, columns: Array, rows: Array,
		opts: Dictionary = {}) -> Control:
	var o := opts.duplicate()
	o["state"] = ui(key)
	o["on_sort"] = func(): refresh()
	return UiKit.data_table(columns, rows, o)


## En-tête d'écran : bandeau aux couleurs de la structure, titre, sous-titre et
## actions alignées à droite. Voir `UiKit.screen_header`.
func page_header(title_text: String, subtitle_text: String = "",
		actions: Array = []) -> Control:
	return UiKit.screen_header(title_text, subtitle_text, actions, tint())


## Couleur de la structure dirigée, qui teinte les bandeaux de l'écran.
##
## Avant la partie il n'y a pas encore de structure : on retombe sur l'accent
## du jeu plutôt que sur du noir — un bandeau invisible se lirait comme un
## défaut d'affichage.
func tint() -> Color:
	var g := game()
	if g == null or not g.has_world():
		return UiKit.ACCENT
	var o: Organization = g.my_org()
	if o == null:
		return UiKit.ACCENT
	return UiKit.org_color(o)


## Deux colonnes : contenu principal extensible + panneau latéral fixe.
## Renvoie [main, side] pour y ajouter directement.
func split(side_width: int = 380, separation: int = 14) -> Array:
	var body := UiKit.hbox(separation)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	var main := UiKit.vbox(10)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(main)
	var side := UiKit.vbox(10)
	side.custom_minimum_size = Vector2(side_width, 0)
	body.add_child(side)
	return [main, side]
