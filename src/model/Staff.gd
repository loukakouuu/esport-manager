class_name Staff
extends RefCounted

## Membre du staff. Dans une vraie structure esport, le staff pèse autant que
## le roster : un bon coach transforme cinq bons joueurs en équipe, un analyste
## gagne des rounds sur la préparation adverse, un psy évite un burnout à
## 400 k$ de dégâts.

enum Role {
	HEAD_COACH,        # prépare les stratégies, gère le groupe
	ASSISTANT_COACH,   # travail mécanique / individuel
	ANALYST,           # préparation adverse, VOD review
	TEAM_MANAGER,      # logistique, discipline, admin
	PSYCHOLOGIST,      # moral, burnout, gestion de la pression
	PERFORMANCE_COACH, # sommeil, physique, prévention des blessures
	SCOUT,             # découverte et évaluation des joueurs
	CONTENT_MANAGER,   # contenu, image, revenus annexes
	GENERAL_MANAGER,   # négociations, sponsors
}

const ROLE_LABELS := {
	Role.HEAD_COACH: "Entraîneur principal",
	Role.ASSISTANT_COACH: "Entraîneur adjoint",
	Role.ANALYST: "Analyste",
	Role.TEAM_MANAGER: "Team manager",
	Role.PSYCHOLOGIST: "Préparateur mental",
	Role.PERFORMANCE_COACH: "Préparateur physique",
	Role.SCOUT: "Recruteur",
	Role.CONTENT_MANAGER: "Responsable contenu",
	Role.GENERAL_MANAGER: "Directeur sportif",
}

# Attributs de staff (1..20)
const TACTICAL := "tactical"
const MECHANICAL_COACHING := "mechanical_coaching"
const MAN_MANAGEMENT := "man_management"
const ANALYSIS := "analysis"
const YOUTH_DEVELOPMENT := "youth_development"
const JUDGEMENT := "judgement"       # fiabilité de son évaluation des joueurs
const NEGOTIATION := "negotiation"
const MEDIA := "media"
const DISCIPLINE := "discipline"
const WELLNESS := "wellness"

const ATTR_KEYS: Array[String] = [
	TACTICAL, MECHANICAL_COACHING, MAN_MANAGEMENT, ANALYSIS, YOUTH_DEVELOPMENT,
	JUDGEMENT, NEGOTIATION, MEDIA, DISCIPLINE, WELLNESS,
]

const ATTR_LABELS := {
	TACTICAL: "Tactique",
	MECHANICAL_COACHING: "Coaching mécanique",
	MAN_MANAGEMENT: "Gestion humaine",
	ANALYSIS: "Analyse",
	YOUTH_DEVELOPMENT: "Formation",
	JUDGEMENT: "Jugement",
	NEGOTIATION: "Négociation",
	MEDIA: "Médias",
	DISCIPLINE: "Autorité",
	WELLNESS: "Bien-être",
}

var id: String = ""
var first_name: String = ""
var last_name: String = ""
var nickname: String = ""
var nationality: String = "FR"
var birth_day: int = 0

var role: Role = Role.HEAD_COACH
var game_id: String = "valorant"     # "" = polyvalent (GM, manager…)
var attributes: Dictionary = {}
var reputation: int = 200

var org_id: String = ""
var contract: Contract = null


func display_name() -> String:
	if nickname != "":
		return nickname
	return "%s %s" % [first_name, last_name]


func full_name() -> String:
	return "%s %s" % [first_name, last_name]


func age(today: int) -> int:
	return GameDate.age_at(birth_day, today)


func attr(key: String) -> int:
	return int(attributes.get(key, 10))


func role_label() -> String:
	return ROLE_LABELS.get(role, "Staff")


## Note globale 1..20 pondérée selon le poste : sert au marché et à l'affichage.
func overall() -> float:
	var w := _weights_for_role()
	var total := 0.0
	var sum_w := 0.0
	for k in w:
		total += float(attr(k)) * float(w[k])
		sum_w += float(w[k])
	return total / maxf(sum_w, 0.001)


func _weights_for_role() -> Dictionary:
	match role:
		Role.HEAD_COACH:
			return {TACTICAL: 3.0, MAN_MANAGEMENT: 2.0, ANALYSIS: 1.5, DISCIPLINE: 1.0}
		Role.ASSISTANT_COACH:
			return {MECHANICAL_COACHING: 3.0, YOUTH_DEVELOPMENT: 1.5, MAN_MANAGEMENT: 1.0}
		Role.ANALYST:
			return {ANALYSIS: 4.0, TACTICAL: 1.5}
		Role.TEAM_MANAGER:
			return {DISCIPLINE: 2.0, MAN_MANAGEMENT: 2.0, MEDIA: 1.0}
		Role.PSYCHOLOGIST:
			return {WELLNESS: 3.0, MAN_MANAGEMENT: 2.5}
		Role.PERFORMANCE_COACH:
			return {WELLNESS: 4.0}
		Role.SCOUT:
			return {JUDGEMENT: 4.0, YOUTH_DEVELOPMENT: 1.0}
		Role.CONTENT_MANAGER:
			return {MEDIA: 4.0}
		Role.GENERAL_MANAGER:
			return {NEGOTIATION: 3.0, JUDGEMENT: 2.0, MEDIA: 1.0}
	return {TACTICAL: 1.0}


func to_dict() -> Dictionary:
	return {
		"id": id, "first_name": first_name, "last_name": last_name,
		"nickname": nickname, "nationality": nationality, "birth_day": birth_day,
		"role": int(role), "game_id": game_id,
		"attributes": attributes.duplicate(), "reputation": reputation,
		"org_id": org_id,
		"contract": contract.to_dict() if contract != null else null,
	}


static func from_dict(d: Dictionary) -> Staff:
	var s := Staff.new()
	s.id = d.get("id", "")
	s.first_name = d.get("first_name", "")
	s.last_name = d.get("last_name", "")
	s.nickname = d.get("nickname", "")
	s.nationality = d.get("nationality", "FR")
	s.birth_day = int(d.get("birth_day", 0))
	s.role = int(d.get("role", 0)) as Role
	s.game_id = d.get("game_id", "valorant")
	s.attributes = (d.get("attributes", {}) as Dictionary).duplicate()
	s.reputation = int(d.get("reputation", 200))
	s.org_id = d.get("org_id", "")
	var c = d.get("contract", null)
	s.contract = Contract.from_dict(c) if c != null else null
	return s
