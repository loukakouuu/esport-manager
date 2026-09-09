class_name ValorantSide
extends RefCounted

## Vue d'une équipe PENDANT un match : notes agrégées une fois pour toutes au
## coup d'envoi, plus l'état qui évolue round après round (crédits, série de
## défaites, momentum, temps morts).
##
## Séparée du simulateur pour rester lisible et testable — et parce que `Side`
## est déjà une énumération globale de Godot.

var sheet: TeamSheet = null
var players: Array[Player] = []
var power: Array[float] = []       # poids d'impact individuel (frags)

# Notes d'équipe (échelle 1..20)
var firepower := 10.0
var utility := 10.0
var tactical := 10.0
var cohesion := 10.0
var anchoring := 10.0
var positioning := 10.0
var entry := 10.0
var clutch := 10.0
var eco_iq := 10.0
var composure := 10.0
var prep := 0.5

# État de la map en cours
var credits := 800
var saved_value := 0
var loss_streak := 0
var momentum := 0.0
var timeouts := 1
var last_buy := "eco"


func reset_economy(start_credits: int) -> void:
	credits = start_credits
	saved_value = 0
	loss_streak = 0
	momentum = 0.0
	timeouts = 1
	last_buy = "eco"


## Effet de tilt : une équipe au mental fragile subit bien plus le momentum.
func tilt() -> float:
	return momentum * (1.6 - composure / 20.0)
