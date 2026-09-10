extends Control

## Faux App pour les vérifications headless : expose `game`, `navigate` et la
## mémoire d'affichage, sans construire toute la coquille de l'interface.

var game: Node = null
var navigations: Array[String] = []
var view_state := {}

## Quand ce champ est renseigné, TOUTES les clés d'état renvoient cet onglet.
## C'est ce qui permet à ui_check de balayer les onglets d'un écran sans
## connaître la clé que chacun utilise ("player", "squad", "finance"…).
var force_tab := ""


func navigate(screen_name: String, _args: Dictionary = {}) -> void:
	navigations.append(screen_name)


func ui_state(key: String) -> Dictionary:
	if not view_state.has(key):
		view_state[key] = {}
	var d: Dictionary = view_state[key]
	if force_tab != "":
		d["tab"] = force_tab
	return d
