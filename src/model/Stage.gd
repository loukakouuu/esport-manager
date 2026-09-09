class_name Stage
extends RefCounted

## Une phase d'une compétition (poules, saison régulière, bracket…).
##
## Une compétition réelle enchaîne plusieurs phases avec des formats différents
## — VCT Kickoff = poules puis playoffs à double élimination. Le moteur
## compose donc des Stage plutôt que de coder chaque tournoi en dur.

enum Format {
	ROUND_ROBIN,     # chacun contre chacun (1 ou 2 tours)
	GROUPS,          # N poules en round robin
	SINGLE_ELIM,
	DOUBLE_ELIM,
	SWISS,           # à la Challengers / Majors
}

enum Status { PENDING, RUNNING, FINISHED }

const FORMAT_LABELS := {
	Format.ROUND_ROBIN: "Championnat",
	Format.GROUPS: "Phase de poules",
	Format.SINGLE_ELIM: "Élimination directe",
	Format.DOUBLE_ELIM: "Double élimination",
	Format.SWISS: "Système suisse",
}

var id: String = ""
var competition_id: String = ""
var name: String = ""
var format: Format = Format.ROUND_ROBIN
var status: Status = Status.PENDING

var start_day: int = 0
var end_day: int = 0
var best_of: int = 3
var final_best_of: int = 5

var participants: Array[String] = []   # roster_id
var fixture_ids: Array[String] = []

## Nombre d'équipes qui passent à la phase suivante.
var qualifiers: int = 8
## Nombre d'équipes éliminées/reléguées à l'issue de la phase.
var relegated: int = 0

## Paramètres propres au format : {"groups": 2}, {"wins_to_qualify": 3, "losses_out": 3},
## {"double_round": true}
var config: Dictionary = {}

## Classement calculé : Array de Dictionary triés.
var standings: Array = []
## Classement final de la phase (roster_id ordonnés), rempli à la clôture.
var ranking: Array[String] = []


func format_label() -> String:
	return FORMAT_LABELS.get(format, "Phase")


func is_bracket() -> bool:
	return format == Format.SINGLE_ELIM or format == Format.DOUBLE_ELIM


static func new_standing(roster_id: String) -> Dictionary:
	return {
		"roster_id": roster_id, "w": 0, "l": 0,
		"map_w": 0, "map_l": 0, "round_w": 0, "round_l": 0,
		"group": "", "pts": 0,
	}


func standing_for(roster_id: String) -> Dictionary:
	for s in standings:
		if s["roster_id"] == roster_id:
			return s
	var ns := new_standing(roster_id)
	standings.append(ns)
	return ns


func to_dict() -> Dictionary:
	return {
		"id": id, "competition_id": competition_id, "name": name,
		"format": int(format), "status": int(status),
		"start_day": start_day, "end_day": end_day,
		"best_of": best_of, "final_best_of": final_best_of,
		"participants": participants.duplicate(),
		"fixture_ids": fixture_ids.duplicate(),
		"qualifiers": qualifiers, "relegated": relegated,
		"config": config.duplicate(true),
		"standings": standings.duplicate(true),
		"ranking": ranking.duplicate(),
	}


static func from_dict(d: Dictionary) -> Stage:
	var s := Stage.new()
	s.id = d.get("id", "")
	s.competition_id = d.get("competition_id", "")
	s.name = d.get("name", "")
	s.format = int(d.get("format", 0)) as Format
	s.status = int(d.get("status", 0)) as Status
	s.start_day = int(d.get("start_day", 0))
	s.end_day = int(d.get("end_day", 0))
	s.best_of = int(d.get("best_of", 3))
	s.final_best_of = int(d.get("final_best_of", 5))
	s.participants = Roster._str_array(d.get("participants", []))
	s.fixture_ids = Roster._str_array(d.get("fixture_ids", []))
	s.qualifiers = int(d.get("qualifiers", 8))
	s.relegated = int(d.get("relegated", 0))
	s.config = (d.get("config", {}) as Dictionary).duplicate(true)
	s.standings = (d.get("standings", []) as Array).duplicate(true)
	s.ranking = Roster._str_array(d.get("ranking", []))
	return s
