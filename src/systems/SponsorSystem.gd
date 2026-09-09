class_name SponsorSystem
extends RefCounted

## Marché du sponsoring — la principale source de revenus du jeu.
##
## Un sponsor n'achète pas des victoires, il achète de l'EXPOSITION. La valeur
## d'un contrat suit donc la réputation (crédibilité) et la fanbase (audience),
## pas directement le classement. D'où une tension de gestion très réelle :
## une structure peut être sportivement excellente et financièrement pauvre si
## elle néglige sa marque, et l'inverse est vrai aussi.

const DATA_PATH := "res://data/world/sponsors.json"

## Références de calibrage : la base_value du JSON correspond à ce profil.
const REF_REPUTATION := 5000.0
const REF_FANBASE := 250_000.0


static func catalogue() -> Array:
	var d = DataFile.load_json(DATA_PATH, {"sponsors": []})
	return (d as Dictionary).get("sponsors", [])


static func slot_from_name(s: String) -> SponsorDeal.Slot:
	var idx: int = SponsorDeal.Slot.keys().find(s)
	return (idx if idx >= 0 else 1) as SponsorDeal.Slot


## Valeur annuelle qu'une marque est prête à payer à cette structure.
static func offer_value(org: Organization, entry: Dictionary,
		recent_form: float = 0.0) -> int:
	var base := float(entry.get("base_value", 50_000))
	var rep_f := pow(clampf(float(org.reputation) / REF_REPUTATION, 0.05, 3.0), 0.65)
	var fan_f := pow(clampf(float(org.fanbase) / REF_FANBASE, 0.05, 4.0), 0.45)
	var value := base * (0.55 * rep_f + 0.45 * fan_f)
	# Les résultats récents ajoutent au plus 20 % : un sponsor signe une marque,
	# pas un classement.
	value *= 1.0 + clampf(recent_form, -0.25, 0.20)
	return Money.from_units(value)


## Génère les propositions disponibles pour une structure, emplacement par
## emplacement. Un emplacement déjà occupé n'est pas reproposé.
static func offers_for(world: World, org: Organization, count: int = 4) -> Array:
	var out: Array = []
	var rng := world.rng.derive("sponsor:%s:%d" % [org.id, world.today])
	var pool: Array = []
	for e in catalogue():
		var entry: Dictionary = e
		var slot := slot_from_name(str(entry.get("slot", "JERSEY_MAIN")))
		if org.sponsor_slot_taken(slot, world.today):
			continue
		# Une marque ne descend pas trop bas : marge de 15 % sous son seuil.
		if float(org.reputation) < float(entry.get("min_reputation", 0)) * 0.85:
			continue
		pool.append(entry)
	rng.shuffle(pool)

	for entry_v in pool.slice(0, count):
		var entry: Dictionary = entry_v
		var years := rng.range_i(1, 3)
		var value := offer_value(org, entry, _recent_form(world, org))
		# Un contrat long se paie un peu moins cher par an : c'est le prix
		# de la sécurité.
		if years >= 3:
			value = Money.pct(value, 92.0)
		elif years == 1:
			value = Money.pct(value, 106.0)
		out.append({
			"sponsor_name": str(entry["name"]),
			"slot": int(slot_from_name(str(entry.get("slot", "JERSEY_MAIN")))),
			"annual_value": value,
			"years": years,
			"content_obligations": int(entry.get("content", 1)),
			"brand_risk": float(entry.get("brand_risk", 0.0)),
			"min_reputation": int(entry.get("min_reputation", 0)),
			"bonus_title": Money.pct(value, 12.0),
		})
	return out


static func sign_deal(world: World, org: Organization, offer: Dictionary) -> SponsorDeal:
	var deal := SponsorDeal.new()
	deal.id = world.ids.next(Ids.DEAL)
	deal.org_id = org.id
	deal.sponsor_name = str(offer["sponsor_name"])
	deal.slot = int(offer["slot"]) as SponsorDeal.Slot
	deal.annual_value = int(offer["annual_value"])
	deal.start_day = world.today
	deal.end_day = GameDate.add_years(world.today, int(offer.get("years", 2)))
	deal.content_obligations = int(offer.get("content_obligations", 1))
	deal.brand_risk = float(offer.get("brand_risk", 0.0))
	deal.min_reputation = int(offer.get("min_reputation", 0))
	deal.performance_bonuses = {"tier1_title": int(offer.get("bonus_title", 0))}
	org.sponsor_deals.append(deal)

	# Un sponsor « à risque » rapporte gros mais abîme l'image : la fanbase
	# recule et les marques premium deviennent plus difficiles à décrocher.
	if deal.brand_risk > 0.0:
		org.fanbase = maxi(500, int(round(float(org.fanbase)
			* (1.0 - deal.brand_risk * 0.05))))
		org.reputation = maxi(50, org.reputation - int(deal.brand_risk * 60.0))
	return deal


## Renouvellements et fins de contrat, passés une fois par mois.
static func monthly_review(world: World, org: Organization) -> void:
	var rng := world.rng.derive("sponsor_review:%s:%d" % [org.id, world.today])
	for deal in org.sponsor_deals:
		if deal.end_day > world.today + 30:
			continue
		if deal.end_day < world.today:
			continue
		# À un mois de l'échéance, la marque décide de proposer ou non une suite.
		var wants := deal.renewal_interest + _recent_form(world, org) * 0.5
		if org.id == world.player_org_id:
			if rng.chance(clampf(wants, 0.05, 0.95)):
				world.add_news(world.today, "Renouvellement proposé — %s"
					% deal.sponsor_name,
					"%s souhaite prolonger son partenariat (%s / an)."
						% [deal.sponsor_name, Money.fmt(deal.annual_value)],
					"sponsor", {"deal_id": deal.id})
			else:
				world.add_news(world.today, "Fin de partenariat — %s"
					% deal.sponsor_name,
					"%s ne prolongera pas. L'emplacement %s se libère."
						% [deal.sponsor_name, deal.slot_label()], "sponsor")


## Forme récente de la structure, normalisée entre -1 et +1.
static func _recent_form(world: World, org: Organization) -> float:
	var w := 0
	var l := 0
	for rid in org.all_roster_ids():
		var r := world.roster(rid)
		if r == null:
			continue
		for cid in r.season_record:
			var rec: Dictionary = r.season_record[cid]
			w += int(rec.get("w", 0))
			l += int(rec.get("l", 0))
	if w + l == 0:
		return 0.0
	return clampf((float(w) / float(w + l) - 0.5) * 2.0, -1.0, 1.0)
