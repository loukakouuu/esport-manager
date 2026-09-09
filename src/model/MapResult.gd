class_name MapResult
extends RefCounted

## Résultat d'une carte au sein d'une série.

var map_name: String = ""
var picked_by: String = ""          # roster_id ayant choisi la map ("" = decider)
var home_rounds: int = 0
var away_rounds: int = 0
var home_started_attack: bool = true
var overtime: bool = false

## Log round par round. Chaque entrée :
## {n:int, winner:"home"/"away", type:"pistol"/"eco"/"force"/"full"/"bonus",
##  side:"atk"/"def", plant:bool, defuse:bool, fk:player_id, text:String}
var rounds: Array = []

## player_id -> stats de CETTE map (mêmes clés que MatchResult.player_stats)
var player_stats: Dictionary = {}


func winner_is_home() -> bool:
	return home_rounds > away_rounds


func score_text() -> String:
	return "%d-%d" % [home_rounds, away_rounds]


## Retire le détail round par round (utilisé pour les matchs entre équipes IA :
## on garde le score et les stats, on jette 24 lignes de log par map).
func compact() -> void:
	rounds.clear()


func to_dict() -> Dictionary:
	return {
		"map_name": map_name, "picked_by": picked_by,
		"home_rounds": home_rounds, "away_rounds": away_rounds,
		"home_started_attack": home_started_attack, "overtime": overtime,
		"rounds": rounds.duplicate(true),
		"player_stats": player_stats.duplicate(true),
	}


static func from_dict(d: Dictionary) -> MapResult:
	var m := MapResult.new()
	m.map_name = d.get("map_name", "")
	m.picked_by = d.get("picked_by", "")
	m.home_rounds = int(d.get("home_rounds", 0))
	m.away_rounds = int(d.get("away_rounds", 0))
	m.home_started_attack = bool(d.get("home_started_attack", true))
	m.overtime = bool(d.get("overtime", false))
	m.rounds = (d.get("rounds", []) as Array).duplicate(true)
	m.player_stats = (d.get("player_stats", {}) as Dictionary).duplicate(true)
	return m
