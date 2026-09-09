extends Control

## Faux App pour les vérifications headless : expose `game` et `navigate`
## sans construire toute la coquille de l'interface.

var game: Node = null
var navigations: Array[String] = []


func navigate(screen_name: String, _args: Dictionary = {}) -> void:
	navigations.append(screen_name)
