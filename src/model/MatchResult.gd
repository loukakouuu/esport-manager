class_name MatchResult
extends RefCounted

## Résultat complet d'une série, avec les statistiques individuelles.
##
## Les clés de stats sont volontairement génériques (kills/deaths/assists…) :
## chaque GameModule décide de celles qu'il remplit et de la façon dont il
## calcule la note. Le coeur du moteur ne connaît que `rating`.

const STAT_KEYS: Array[String] = [
	"rounds", "kills", "deaths", "assists", "first_kills", "first_deaths",
	"plants", "defuses", "clutches", "clutch_attempts", "aces", "multikills",
	"damage", "kast_rounds", "headshots",
]

var fixture_id: String = ""
var competition_id: String = ""
var day: int = 0

var home_id: String = ""
var away_id: String = ""
var home_score: int = 0            # maps gagnées
var away_score: int = 0
var winner_id: String = ""
var loser_id: String = ""

var maps: Array[MapResult] = []
var veto_log: Array = []           # ["AUR ban Split", "NVA pick Ascent", …]

## player_id -> { clé de STAT_KEYS -> int } + {"rating": float, "acs": float}
var player_stats: Dictionary = {}
var mvp_id: String = ""
var headline: String = ""          # phrase de résumé prête à afficher


static func empty_stats() -> Dictionary:
	var d := {}
	for k in STAT_KEYS:
		d[k] = 0
	d["rating"] = 0.0
	d["acs"] = 0.0
	return d


static func add_stats(into: Dictionary, from: Dictionary) -> void:
	for k in STAT_KEYS:
		into[k] = int(into.get(k, 0)) + int(from.get(k, 0))


func total_rounds(roster_id: String) -> int:
	var n := 0
	for m in maps:
		n += m.home_rounds if roster_id == home_id else m.away_rounds
	return n


func score_text() -> String:
	return "%d-%d" % [home_score, away_score]


func map_score_text() -> String:
	var parts: Array[String] = []
	for m in maps:
		parts.append("%s %s" % [m.map_name, m.score_text()])
	return " · ".join(parts)


func rating_of(player_id: String) -> float:
	return float((player_stats.get(player_id, {}) as Dictionary).get("rating", 0.0))


## Version allégée : on jette les logs de round et on ne garde que l'essentiel.
func compact() -> void:
	for m in maps:
		m.compact()
		m.player_stats.clear()


func to_dict() -> Dictionary:
	var ms: Array = []
	for m in maps:
		ms.append(m.to_dict())
	return {
		"fixture_id": fixture_id, "competition_id": competition_id, "day": day,
		"home_id": home_id, "away_id": away_id,
		"home_score": home_score, "away_score": away_score,
		"winner_id": winner_id, "loser_id": loser_id,
		"maps": ms, "veto_log": veto_log.duplicate(),
		"player_stats": player_stats.duplicate(true),
		"mvp_id": mvp_id, "headline": headline,
	}


static func from_dict(d: Dictionary) -> MatchResult:
	var r := MatchResult.new()
	r.fixture_id = d.get("fixture_id", "")
	r.competition_id = d.get("competition_id", "")
	r.day = int(d.get("day", 0))
	r.home_id = d.get("home_id", "")
	r.away_id = d.get("away_id", "")
	r.home_score = int(d.get("home_score", 0))
	r.away_score = int(d.get("away_score", 0))
	r.winner_id = d.get("winner_id", "")
	r.loser_id = d.get("loser_id", "")
	for md in d.get("maps", []):
		r.maps.append(MapResult.from_dict(md))
	r.veto_log = (d.get("veto_log", []) as Array).duplicate()
	r.player_stats = (d.get("player_stats", {}) as Dictionary).duplicate(true)
	r.mvp_id = d.get("mvp_id", "")
	r.headline = d.get("headline", "")
	return r
