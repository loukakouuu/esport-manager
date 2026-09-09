class_name MatchContext
extends RefCounted

## Tout ce dont un simulateur a besoin — et rien d'autre.

var home: TeamSheet = null
var away: TeamSheet = null
var best_of: int = 3
var day: int = 0
var rng: Rng = null

var competition_name: String = ""
var competition_id: String = ""
var stage_name: String = ""
var round_label: String = ""
var prestige: int = 5000          # 0..10000
var is_lan: bool = false
var importance: float = 1.0       # 1.0 = match normal, 2.0 = finale

## Pool de maps actif (noms). Fourni par le module via les données.
var map_pool: Array[String] = []

## true => on conserve le log round par round (match du joueur).
var detailed: bool = false
