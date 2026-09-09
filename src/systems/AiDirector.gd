class_name AiDirector
extends RefCounted

## Décisions mensuelles des structures gérées par l'ordinateur : sponsors,
## infrastructures, budgets, financement d'urgence.
##
## L'IA n'a AUCUN privilège : elle utilise exactement les mêmes fonctions que
## le joueur (SponsorSystem.sign, FinanceSystem.take_loan…). Un monde où l'IA
## triche produit une économie incohérente au bout de trois saisons.


static func monthly_decisions(world: World, o: Organization) -> void:
	if o.bankrupt:
		return
	var rng := world.rng.derive("ai:%s:%d" % [o.id, world.today])
	_manage_sponsors(world, o, rng)
	_manage_cash(world, o, rng)
	_manage_facilities(world, o, rng)


## Une structure signe ce qu'elle peut. Les structures endettées acceptent les
## sponsors « à risque » que les autres refusent — comme dans la réalité.
static func _manage_sponsors(world: World, o: Organization, rng: Rng) -> void:
	var free_slots := 0
	for slot in SponsorDeal.Slot.values():
		if not o.sponsor_slot_taken(slot, world.today):
			free_slots += 1
	if free_slots == 0:
		return
	var desperate := FinanceSystem.projected_monthly_result(world, o) < 0

	# On ne signe pas plus d'activations qu'on ne peut en produire : au-delà,
	# chaque contrat supplémentaire génère surtout des pénalités.
	var capacity := FinanceSystem.content_capacity(world, o)
	var committed := 0
	for d in o.active_sponsors(world.today):
		committed += d.content_obligations

	for offer_v in SponsorSystem.offers_for(world, o, 3):
		var offer: Dictionary = offer_v
		if float(o.reputation) < float(offer.get("min_reputation", 0)):
			continue
		if committed + int(offer.get("content_obligations", 1)) > capacity \
				and not desperate:
			continue
		var risk := float(offer.get("brand_risk", 0.0))
		if risk > 0.3 and not desperate and rng.chance(0.8):
			continue
		if rng.chance(0.45 if not desperate else 0.85):
			SponsorSystem.sign_deal(world, o, offer)
			return


## Gestion de trésorerie : emprunter, couper les budgets, vendre un joueur.
static func _manage_cash(world: World, o: Organization, rng: Rng) -> void:
	var monthly := FinanceSystem.projected_monthly_result(world, o)
	var runway := FinanceSystem.runway_months(world, o)

	if runway >= 0 and runway <= 3:
		# 1) couper les budgets non essentiels
		for k in ["bootcamp", "marketing", "scouting"]:
			if int(o.budgets.get(k, 0)) > 0:
				o.budgets[k] = 0
		# 2) emprunter si la banque suit
		var capacity := FinanceSystem.max_loan_for(world, o)
		if capacity > 0 and o.total_debt() <= 0:
			FinanceSystem.take_loan(world, o,
				mini(capacity, -monthly * 10), 24)
		# 3) vendre le joueur le plus cher si toujours à sec
		elif o.ledger.cash < 0:
			_emergency_sale(world, o, rng)
	elif monthly > 0 and o.ledger.cash > monthly * 10:
		# Structure saine : elle réinvestit un peu en marketing.
		o.budgets["marketing"] = Money.pct(monthly, 12.0)


static func _emergency_sale(world: World, o: Organization, rng: Rng) -> void:
	var r := world.main_roster(o.id, "valorant")
	if r == null or r.player_ids.size() <= 5:
		return
	var best: Player = null
	for p in world.players_of(r.id):
		if best == null or p.market_value > best.market_value:
			best = p
	if best == null:
		return
	for oid in world.orgs:
		var buyer: Organization = world.orgs[oid]
		if buyer.id == o.id or buyer.is_player_controlled or buyer.bankrupt:
			continue
		if buyer.ledger.cash < best.contract.buyout:
			continue
		var salary := ContractSystem.salary_demand(world, best, buyer)
		var c := ContractSystem.make_offer(world, buyer, best, salary,
			rng.range_i(12, 24), Contract.SquadRole.STARTER)
		if ContractSystem.buyout(world, buyer, best, c):
			return


## Investissement en infrastructures : seulement avec plus de six mois de
## trésorerie devant soi, et jamais au détriment des salaires.
static func _manage_facilities(world: World, o: Organization, rng: Rng) -> void:
	var monthly := FinanceSystem.projected_monthly_result(world, o)
	if monthly <= 0 or not rng.chance(0.15):
		return
	var kinds := Facilities.Kind.values()
	rng.shuffle(kinds)
	for k in kinds:
		var lvl := o.facility_level(k)
		if lvl >= Facilities.MAX_LEVEL:
			continue
		var cost := Facilities.upgrade_cost(k, lvl + 1)
		var new_upkeep := Facilities.monthly_upkeep(k, lvl + 1) \
			- Facilities.monthly_upkeep(k, lvl)
		if o.ledger.cash < cost * 3 or monthly < new_upkeep * 3:
			continue
		o.ledger.debit(world.today, cost, Transaction.Category.FACILITY,
			"Investissement — %s niveau %d" % [Facilities.label(k), lvl + 1], "")
		o.facilities[k] = lvl + 1
		return
