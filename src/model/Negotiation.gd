class_name Negotiation
extends RefCounted

## Une négociation de contrat en cours, côté données.
##
## Elle existe comme entité sauvegardée — et pas comme un état d'écran —
## parce qu'une discussion se poursuit d'un jour à l'autre : l'agent prend le
## temps de répondre, sa patience s'use, et une partie rechargée doit
## retrouver la table telle qu'on l'a laissée.
##
## Les CLAUSES sont un dictionnaire plutôt que des champs nommés : l'agent, la
## simulation et l'interface manipulent la même structure, et ajouter une
## clause (bonus d'objectif, part de stream) ne demande de toucher ni à la
## sauvegarde ni à l'écran.

enum Status {
	OPEN,       # en cours, c'est au joueur de proposer
	COUNTERED,  # l'agent a fait une contre-proposition
	ACCEPTED,   # signé
	REFUSED,    # l'agent a claqué la porte
	EXPIRED,    # la discussion s'est éteinte faute d'échanges
}

## Une offre trop basse fait perdre plus de patience qu'un simple refus poli.
const MOOD_START := 72.0

var id: String = ""
var org_id: String = ""
var player_id: String = ""
var opened_day: int = 0
var last_day: int = 0
var status: Status = Status.OPEN

## Nombre d'offres déjà soumises par le joueur.
var rounds: int = 0

## Patience de l'agent, 0..100. À zéro, il s'en va.
var mood: float = MOOD_START

## Clauses proposées par le joueur au dernier tour, et celles que l'agent
## réclame. Mêmes clés dans les deux : voir `Terms`.
var offer: Dictionary = {}
var demand: Dictionary = {}

## Fil de la discussion : [{"day", "who", "text"}] — who vaut "org" ou "agent".
var log: Array = []


## Clés de clause et valeurs par défaut. Tout le reste du code passe par ici.
class Terms:
	const SALARY := "salary"        # cents / an
	const MONTHS := "months"        # durée
	const ROLE := "role"            # Contract.SquadRole
	const BONUS := "bonus"          # prime à la signature, cents
	const BUYOUT := "buyout"        # clause de rachat, cents
	const PRIZE := "prize"          # part des gains, %

	static func keys() -> Array[String]:
		return [SALARY, MONTHS, ROLE, BONUS, BUYOUT, PRIZE]


func is_live() -> bool:
	return status == Status.OPEN or status == Status.COUNTERED


func say(day: int, who: String, text: String) -> void:
	log.append({"day": day, "who": who, "text": text})


func to_dict() -> Dictionary:
	return {
		"id": id, "org_id": org_id, "player_id": player_id,
		"opened_day": opened_day, "last_day": last_day, "status": int(status),
		"rounds": rounds, "mood": mood,
		"offer": offer.duplicate(), "demand": demand.duplicate(),
		"log": log.duplicate(true),
	}


static func from_dict(d: Dictionary) -> Negotiation:
	var n := Negotiation.new()
	n.id = str(d.get("id", ""))
	n.org_id = str(d.get("org_id", ""))
	n.player_id = str(d.get("player_id", ""))
	n.opened_day = int(d.get("opened_day", 0))
	n.last_day = int(d.get("last_day", 0))
	n.status = int(d.get("status", 0)) as Status
	n.rounds = int(d.get("rounds", 0))
	n.mood = float(d.get("mood", MOOD_START))
	n.offer = (d.get("offer", {}) as Dictionary).duplicate()
	n.demand = (d.get("demand", {}) as Dictionary).duplicate()
	n.log = (d.get("log", []) as Array).duplicate(true)
	return n
