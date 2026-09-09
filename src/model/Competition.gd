class_name Competition
extends RefCounted

## Une compétition d'une saison donnée.
##
## La pyramide Valorant est reproduite telle quelle :
##   Tier 1  VCT International (ligue partenaire, 12 équipes, subvention annuelle)
##   Tier 1  Masters / Champions (international, sur invitation via les points)
##   Tier 2  Challengers national (2 splits) -> Ascension -> promotion en VCT
##   Tier 3  Open qualifiers / circuits amateurs
##
## Une compétition ne contient AUCUNE logique : elle décrit. Le moteur qui la
## fait vivre est CompetitionEngine.

enum Kind { LEAGUE, TOURNAMENT, INTERNATIONAL, QUALIFIER, ASCENSION }
enum Status { SCHEDULED, RUNNING, FINISHED }

const KIND_LABELS := {
	Kind.LEAGUE: "Ligue",
	Kind.TOURNAMENT: "Tournoi",
	Kind.INTERNATIONAL: "International",
	Kind.QUALIFIER: "Qualification",
	Kind.ASCENSION: "Ascension",
}

var id: String = ""
var key: String = ""               # identifiant stable inter-saisons ("vct_emea")
var name: String = ""
var short_name: String = ""
var game_id: String = "valorant"
var region: String = "EMEA"
var country: String = ""           # renseigné pour les ligues nationales
var tier: int = 1                  # 1 = élite
var kind: Kind = Kind.LEAGUE
var season_year: int = 2026
var status: Status = Status.SCHEDULED

var prestige: int = 5000           # 0..10000, pilote le gain de réputation
var is_lan: bool = false
var travel_cost_per_team: int = 0  # cents, facturé aux participants

## Économie de la compétition
var prize_pool: int = 0            # cents
var prize_distribution: Array = [] # pourcentages par place : [40, 20, 12, …]
var stipend_yearly: int = 0        # subvention annuelle aux équipes partenaires
var entry_fee: int = 0             # frais d'engagement
var rev_share_yearly: int = 0      # partage éditeur (bundles d'équipe)

var participants: Array[String] = []
var stages: Array[Stage] = []
var current_stage: int = 0

## Classement final (roster_id ordonnés) une fois la compétition terminée.
var final_ranking: Array[String] = []

## Points de circuit attribués (roster_id -> points), pour la qualif Champions.
var circuit_points: Dictionary = {}

## Règles d'accès à d'autres compétitions :
## [{"places": 2, "to": "masters_1", "label": "Masters"}]
var qualification_rules: Array = []


func kind_label() -> String:
	return KIND_LABELS.get(kind, "Compétition")


func active_stage() -> Stage:
	if current_stage >= 0 and current_stage < stages.size():
		return stages[current_stage]
	return null


func stage_by_id(sid: String) -> Stage:
	for s in stages:
		if s.id == sid:
			return s
	return null


func is_partnered() -> bool:
	return stipend_yearly > 0


## Cashprize revenant à la place `placement` (1 = vainqueur).
func prize_for_placement(placement: int) -> int:
	if placement < 1 or placement > prize_distribution.size():
		return 0
	return Money.pct(prize_pool, float(prize_distribution[placement - 1]))


func to_dict() -> Dictionary:
	var st: Array = []
	for s in stages:
		st.append(s.to_dict())
	return {
		"id": id, "key": key, "name": name, "short_name": short_name,
		"game_id": game_id, "region": region, "country": country,
		"tier": tier, "kind": int(kind), "season_year": season_year,
		"status": int(status), "prestige": prestige, "is_lan": is_lan,
		"travel_cost_per_team": travel_cost_per_team,
		"prize_pool": prize_pool, "prize_distribution": prize_distribution.duplicate(),
		"stipend_yearly": stipend_yearly, "entry_fee": entry_fee,
		"rev_share_yearly": rev_share_yearly,
		"participants": participants.duplicate(), "stages": st,
		"current_stage": current_stage,
		"final_ranking": final_ranking.duplicate(),
		"circuit_points": circuit_points.duplicate(),
		"qualification_rules": qualification_rules.duplicate(true),
	}


static func from_dict(d: Dictionary) -> Competition:
	var c := Competition.new()
	c.id = d.get("id", "")
	c.key = d.get("key", "")
	c.name = d.get("name", "")
	c.short_name = d.get("short_name", "")
	c.game_id = d.get("game_id", "valorant")
	c.region = d.get("region", "EMEA")
	c.country = d.get("country", "")
	c.tier = int(d.get("tier", 1))
	c.kind = int(d.get("kind", 0)) as Kind
	c.season_year = int(d.get("season_year", 2026))
	c.status = int(d.get("status", 0)) as Status
	c.prestige = int(d.get("prestige", 5000))
	c.is_lan = bool(d.get("is_lan", false))
	c.travel_cost_per_team = int(d.get("travel_cost_per_team", 0))
	c.prize_pool = int(d.get("prize_pool", 0))
	c.prize_distribution = (d.get("prize_distribution", []) as Array).duplicate()
	c.stipend_yearly = int(d.get("stipend_yearly", 0))
	c.entry_fee = int(d.get("entry_fee", 0))
	c.rev_share_yearly = int(d.get("rev_share_yearly", 0))
	c.participants = Roster._str_array(d.get("participants", []))
	for sd in d.get("stages", []):
		c.stages.append(Stage.from_dict(sd))
	c.current_stage = int(d.get("current_stage", 0))
	c.final_ranking = Roster._str_array(d.get("final_ranking", []))
	c.circuit_points = (d.get("circuit_points", {}) as Dictionary).duplicate()
	c.qualification_rules = (d.get("qualification_rules", []) as Array).duplicate(true)
	return c
