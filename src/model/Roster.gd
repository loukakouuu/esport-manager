class_name Roster
extends RefCounted

## Une ÉQUIPE : le roster d'une structure sur UN jeu donné.
##
## Distinction structurante du projet : Organization = l'entreprise (une seule
## trésorerie, une seule marque), Roster = une équipe engagée sur une
## discipline. Une org peut donc aligner un roster Valorant, une académie et,
## plus tard, un roster CS2, sans qu'aucune ligne du moteur financier ne change.

var id: String = ""
var org_id: String = ""
var game_id: String = "valorant"
var name: String = ""              # "Team Aurora" ou "Team Aurora Academy"
var is_academy: bool = false
var region: String = "EMEA"
## Ligue d’appartenance stable d’une saison à l’autre ("vct_emea", "chal_emea").
## C’est cette clé qui permet la promotion/relégation entre saisons.
var league_key: String = ""

var player_ids: Array[String] = []
var starters: Array[String] = []   # titulaires, taille = team_size du jeu
var head_coach_id: String = ""
var staff_ids: Array[String] = []

## Réglages tactiques : leur contenu est défini par le GameModule.
var tactic: Dictionary = {}

var chemistry: float = 40.0        # 0..100, cohésion du cinq, monte en jouant
var competition_ids: Array[String] = []
var season_record: Dictionary = {} # comp_id -> {w, l, maps_w, maps_l, rounds_w, rounds_l}


func size() -> int:
	return player_ids.size()


func has_player(pid: String) -> bool:
	return player_ids.has(pid)


func add_player(pid: String) -> void:
	if not player_ids.has(pid):
		player_ids.append(pid)


func remove_player(pid: String) -> void:
	player_ids.erase(pid)
	starters.erase(pid)


func bench_ids() -> Array[String]:
	var out: Array[String] = []
	for pid in player_ids:
		if not starters.has(pid):
			out.append(pid)
	return out


func record_for(comp_id: String) -> Dictionary:
	if not season_record.has(comp_id):
		season_record[comp_id] = {
			"w": 0, "l": 0, "maps_w": 0, "maps_l": 0,
			"rounds_w": 0, "rounds_l": 0,
		}
	return season_record[comp_id]


func to_dict() -> Dictionary:
	return {
		"id": id, "org_id": org_id, "game_id": game_id, "name": name,
		"is_academy": is_academy, "region": region, "league_key": league_key,
		"player_ids": player_ids.duplicate(), "starters": starters.duplicate(),
		"head_coach_id": head_coach_id, "staff_ids": staff_ids.duplicate(),
		"tactic": tactic.duplicate(true), "chemistry": chemistry,
		"competition_ids": competition_ids.duplicate(),
		"season_record": season_record.duplicate(true),
	}


static func from_dict(d: Dictionary) -> Roster:
	var r := Roster.new()
	r.id = d.get("id", "")
	r.org_id = d.get("org_id", "")
	r.game_id = d.get("game_id", "valorant")
	r.name = d.get("name", "")
	r.is_academy = bool(d.get("is_academy", false))
	r.region = d.get("region", "EMEA")
	r.league_key = d.get("league_key", "")
	r.player_ids = _str_array(d.get("player_ids", []))
	r.starters = _str_array(d.get("starters", []))
	r.head_coach_id = d.get("head_coach_id", "")
	r.staff_ids = _str_array(d.get("staff_ids", []))
	r.tactic = (d.get("tactic", {}) as Dictionary).duplicate(true)
	r.chemistry = float(d.get("chemistry", 40.0))
	r.competition_ids = _str_array(d.get("competition_ids", []))
	r.season_record = (d.get("season_record", {}) as Dictionary).duplicate(true)
	return r


static func _str_array(a) -> Array[String]:
	var out: Array[String] = []
	for v in a:
		out.append(str(v))
	return out
