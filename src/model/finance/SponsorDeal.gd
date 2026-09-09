class_name SponsorDeal
extends RefCounted

## Contrat de sponsoring.
##
## Fidèle au réel : une structure esport vit d'abord de ses sponsors, pas des
## cashprizes. Chaque emplacement (maillot, manche, périphériques…) est exclusif,
## la valeur dépend de la réputation ET de l'audience, et les sponsors « à
## risque » (paris, crypto) paient plus cher en échange d'un coût d'image.

enum Slot { TITLE, JERSEY_MAIN, JERSEY_SLEEVE, PERIPHERALS, HARDWARE,
	ENERGY_DRINK, APPAREL, BETTING, CRYPTO, AUTOMOTIVE, TELECOM }

const SLOT_LABELS := {
	Slot.TITLE: "Naming",
	Slot.JERSEY_MAIN: "Maillot (face)",
	Slot.JERSEY_SLEEVE: "Maillot (manche)",
	Slot.PERIPHERALS: "Périphériques",
	Slot.HARDWARE: "Matériel / PC",
	Slot.ENERGY_DRINK: "Boisson énergisante",
	Slot.APPAREL: "Textile",
	Slot.BETTING: "Paris sportifs",
	Slot.CRYPTO: "Crypto",
	Slot.AUTOMOTIVE: "Automobile",
	Slot.TELECOM: "Télécom",
}

var id: String = ""
var sponsor_name: String = ""
var slot: Slot = Slot.JERSEY_MAIN
var org_id: String = ""

var annual_value: int = 0          # cents / an, versés mensuellement
var start_day: int = 0
var end_day: int = 0

## Bonus de performance : clé d'objectif -> cents.
var performance_bonuses: Dictionary = {}

## Obligations de contenu : nb de livrables par mois. Non tenues => pénalité.
var content_obligations: int = 0
var content_delivered_this_month: int = 0

var brand_risk: float = 0.0        # 0..1, impact négatif sur l'image
var min_reputation: int = 0        # réputation exigée pour signer
var renewal_interest: float = 0.5  # 0..1, probabilité de reconduction


func monthly_value() -> int:
	return int(round(float(annual_value) / 12.0))


func is_active(today: int) -> bool:
	return today >= start_day and today <= end_day


func days_remaining(today: int) -> int:
	return end_day - today


func slot_label() -> String:
	return SLOT_LABELS.get(slot, "Sponsor")


func to_dict() -> Dictionary:
	return {
		"id": id, "sponsor_name": sponsor_name, "slot": int(slot),
		"org_id": org_id, "annual_value": annual_value,
		"start_day": start_day, "end_day": end_day,
		"performance_bonuses": performance_bonuses.duplicate(),
		"content_obligations": content_obligations,
		"content_delivered_this_month": content_delivered_this_month,
		"brand_risk": brand_risk, "min_reputation": min_reputation,
		"renewal_interest": renewal_interest,
	}


static func from_dict(d: Dictionary) -> SponsorDeal:
	var s := SponsorDeal.new()
	s.id = d.get("id", "")
	s.sponsor_name = d.get("sponsor_name", "")
	s.slot = int(d.get("slot", 0)) as Slot
	s.org_id = d.get("org_id", "")
	s.annual_value = int(d.get("annual_value", 0))
	s.start_day = int(d.get("start_day", 0))
	s.end_day = int(d.get("end_day", 0))
	s.performance_bonuses = (d.get("performance_bonuses", {}) as Dictionary).duplicate()
	s.content_obligations = int(d.get("content_obligations", 0))
	s.content_delivered_this_month = int(d.get("content_delivered_this_month", 0))
	s.brand_risk = float(d.get("brand_risk", 0.0))
	s.min_reputation = int(d.get("min_reputation", 0))
	s.renewal_interest = float(d.get("renewal_interest", 0.5))
	return s
