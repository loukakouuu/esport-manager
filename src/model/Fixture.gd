class_name Fixture
extends RefCounted

## Une rencontre programmée (une « série » : BO1, BO3, BO5).
##
## Les brackets sont modélisés par RÉFÉRENCE : un match de demi-finale connaît
## ses deux sources ("winner:fix_00031") avant même que les quarts soient joués.
## Le calendrier complet d'une saison est donc généré une seule fois, en amont,
## et se remplit au fil des résultats.

enum SlotKind { FIXED, WINNER_OF, LOSER_OF, SEED_OF_STAGE }

var id: String = ""
var competition_id: String = ""
var stage_id: String = ""
var day: int = 0
var round_index: int = 0
var round_label: String = ""
var best_of: int = 3

# Participants : soit un roster_id direct, soit une référence à résoudre.
var home_id: String = ""
var away_id: String = ""
var home_source: Dictionary = {}   # {kind:SlotKind, ref:String, seed:int}
var away_source: Dictionary = {}

var bracket: String = ""           # "upper", "lower", "group_a", ""
var played: bool = false
var result: MatchResult = null
var is_lan: bool = false           # déplacement => coûts de voyage
var importance: float = 1.0        # pondère pression, fatigue, réputation


func is_ready() -> bool:
	return home_id != "" and away_id != ""


func involves(roster_id: String) -> bool:
	return home_id == roster_id or away_id == roster_id


func opponent_of(roster_id: String) -> String:
	if home_id == roster_id:
		return away_id
	if away_id == roster_id:
		return home_id
	return ""


static func source(kind: SlotKind, ref: String, seed: int = 0) -> Dictionary:
	return {"kind": int(kind), "ref": ref, "seed": seed}


func to_dict() -> Dictionary:
	return {
		"id": id, "competition_id": competition_id, "stage_id": stage_id,
		"day": day, "round_index": round_index, "round_label": round_label,
		"best_of": best_of, "home_id": home_id, "away_id": away_id,
		"home_source": home_source.duplicate(), "away_source": away_source.duplicate(),
		"bracket": bracket, "played": played,
		"result": result.to_dict() if result != null else null,
		"is_lan": is_lan, "importance": importance,
	}


static func from_dict(d: Dictionary) -> Fixture:
	var f := Fixture.new()
	f.id = d.get("id", "")
	f.competition_id = d.get("competition_id", "")
	f.stage_id = d.get("stage_id", "")
	f.day = int(d.get("day", 0))
	f.round_index = int(d.get("round_index", 0))
	f.round_label = d.get("round_label", "")
	f.best_of = int(d.get("best_of", 3))
	f.home_id = d.get("home_id", "")
	f.away_id = d.get("away_id", "")
	f.home_source = (d.get("home_source", {}) as Dictionary).duplicate()
	f.away_source = (d.get("away_source", {}) as Dictionary).duplicate()
	f.bracket = d.get("bracket", "")
	f.played = bool(d.get("played", false))
	var r = d.get("result", null)
	f.result = MatchResult.from_dict(r) if r != null else null
	f.is_lan = bool(d.get("is_lan", false))
	f.importance = float(d.get("importance", 1.0))
	return f
