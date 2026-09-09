class_name Screen
extends VBoxContainer

## Base de tous les écrans.
##
## Un écran ne stocke aucun état de jeu : il se reconstruit intégralement à
## partir du World à chaque refresh(). C'est volontairement « bête » — pour un
## jeu de gestion au tour par tour, la simplicité de raisonnement vaut mille
## fois l'optimisation d'un rendu incrémental.

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
