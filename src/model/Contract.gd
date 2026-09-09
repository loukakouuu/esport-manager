class_name Contract
extends RefCounted

## Contrat joueur ou staff.
##
## Modélisé sur la réalité esport, qui diffère du football :
##  - il n'y a pas de "transfert" au sens strict mais une CLAUSE DE RACHAT
##    (buyout) que l'org acheteuse paie à l'org vendeuse ;
##  - le joueur touche une PART DES GAINS de tournoi (prize split), souvent
##    la moitié à 80 % de la cagnotte répartie sur le roster ;
##  - beaucoup de revenus annexes (stream, image) sont partagés.

enum Kind { PLAYER, STAFF }
enum SquadRole { STARTER, SUBSTITUTE, ACADEMY, INACTIVE }

var kind: Kind = Kind.PLAYER
var org_id: String = ""
var person_id: String = ""

var salary_yearly: int = 0        # cents / an (brut employeur hors charges)
var signing_bonus: int = 0        # cents versés à la signature
var start_day: int = 0
var end_day: int = 0

var buyout: int = 0               # cents ; 0 = pas de clause => négociation libre
var prize_share_pct: float = 12.0 # % de la cagnotte revenant au joueur
var stream_share_pct: float = 0.0 # % des revenus de contenu reversés au joueur
var agent_fee_pct: float = 8.0    # % du salaire annuel prélevé à la signature

var squad_role: SquadRole = SquadRole.STARTER
var bonuses: Dictionary = {}      # clé d'objectif -> cents (ex: "title_tier1")

var signed_on_day: int = 0


func days_remaining(today: int) -> int:
	return end_day - today


func is_expired(today: int) -> bool:
	return today > end_day


func is_active(today: int) -> bool:
	return today >= start_day and today <= end_day


## Coût mensuel employeur (le salaire annuel lissé sur 12).
func monthly_cost() -> int:
	return int(round(float(salary_yearly) / 12.0))


func upfront_cost() -> int:
	return signing_bonus + int(round(float(salary_yearly) * agent_fee_pct / 100.0))


func to_dict() -> Dictionary:
	return {
		"kind": int(kind), "org_id": org_id, "person_id": person_id,
		"salary_yearly": salary_yearly, "signing_bonus": signing_bonus,
		"start_day": start_day, "end_day": end_day, "buyout": buyout,
		"prize_share_pct": prize_share_pct, "stream_share_pct": stream_share_pct,
		"agent_fee_pct": agent_fee_pct, "squad_role": int(squad_role),
		"bonuses": bonuses.duplicate(), "signed_on_day": signed_on_day,
	}


static func from_dict(d: Dictionary) -> Contract:
	var c := Contract.new()
	c.kind = int(d.get("kind", 0)) as Kind
	c.org_id = d.get("org_id", "")
	c.person_id = d.get("person_id", "")
	c.salary_yearly = int(d.get("salary_yearly", 0))
	c.signing_bonus = int(d.get("signing_bonus", 0))
	c.start_day = int(d.get("start_day", 0))
	c.end_day = int(d.get("end_day", 0))
	c.buyout = int(d.get("buyout", 0))
	c.prize_share_pct = float(d.get("prize_share_pct", 12.0))
	c.stream_share_pct = float(d.get("stream_share_pct", 0.0))
	c.agent_fee_pct = float(d.get("agent_fee_pct", 8.0))
	c.squad_role = int(d.get("squad_role", 0)) as SquadRole
	c.bonuses = (d.get("bonuses", {}) as Dictionary).duplicate()
	c.signed_on_day = int(d.get("signed_on_day", 0))
	return c
