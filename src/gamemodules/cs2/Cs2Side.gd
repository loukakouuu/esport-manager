class_name Cs2Side
extends RefCounted

## Vue d'une équipe PENDANT un match de Counter-Strike : notes agrégées au coup
## d'envoi, plus l'état qui évolue round après round (argent, série de défaites,
## momentum, temps morts, AWP en main).
##
## Séparée du simulateur pour la même raison que ValorantSide : `Side` est déjà
## une énumération globale de Godot, et un fichier de 800 lignes qui porte aussi
## l'état d'équipe devient illisible.

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
var lurk := 10.0
var clutch := 10.0
var eco_iq := 10.0
var composure := 10.0
var prep := 0.5

## Niveau du meilleur AWPeur du cinq (1..20) et son index dans `players`.
## Le garder à part est ce qui permet de faire vivre l'arme dans l'économie :
## une équipe à sec ne rachète pas l'AWP, et perd le duel d'ouverture.
var awp_skill := 8.0
var awp_index := -1

# État de la map en cours
var money := 800
var saved_value := 0
var loss_streak := 0
var momentum := 0.0
var timeouts := 1
var last_buy := "eco"
## L'AWP est-elle en jeu ce round ? Décidée à l'achat, perdue si son porteur
## meurt sans que l'arme soit sauvée.
var has_awp := false


func reset_economy(start_money: int) -> void:
	money = start_money
	saved_value = 0
	loss_streak = 0
	momentum = 0.0
	timeouts = 1
	last_buy = "eco"
	has_awp = false


## Effet de tilt : une équipe au mental fragile subit bien plus le momentum.
func tilt() -> float:
	return momentum * (1.6 - composure / 20.0)
