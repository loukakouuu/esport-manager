class_name ContractSystem
extends RefCounted

## Contrats : échéances, prolongations, ruptures, rachats.
##
## Spécificité esport reproduite : il n'y a pas de mercato fermé. Un joueur
## sous contrat se recrute en payant sa CLAUSE DE RACHAT à sa structure ; un
## joueur en fin de contrat part libre. Les fenêtres de mouvement existent
## quand même, imposées par l'éditeur autour des splits.

## Exigence salariale d'un joueur : ce qu'il demandera pour signer ou prolonger.
static func salary_demand(world: World, p: Player, offering_org: Organization) -> int:
	var base := PlayerFactory.salary_for_ca(p.current_ability, p.reputation)
	var mult := 1.0
	# Ambition et ego font monter les prétentions ; la loyauté les fait baisser.
	mult += float(p.attr(Attributes.AMBITION) - 10) / 45.0
	mult += float(p.attr(Attributes.EGO) - 10) / 55.0
	mult -= float(p.attr(Attributes.LOYALTY) - 10) / 70.0
	# Rejoindre une structure prestigieuse se paie en nature.
	if offering_org != null:
		var prestige_gap := float(offering_org.reputation - p.reputation) / 6000.0
		mult -= clampf(prestige_gap, -0.25, 0.22)
	# Un joueur en forme se sait désirable.
	mult += (p.form - 50.0) / 320.0
	return Money.pct(base, clampf(mult, 0.55, 2.2) * 100.0)


## Ce qui pousse un joueur vers une structure INDÉPENDAMMENT des clauses : le
## prestige, l'attachement à sa maison actuelle, la santé financière.
##
## Isolé parce que la négociation interactive (NegotiationSystem) a besoin de
## séparer ce qui se discute de ce qui ne se discute pas. Deux formules
## concurrentes finiraient par diverger.
static func context_score(world: World, p: Player, org: Organization) -> float:
	var ambition := float(p.attr(Attributes.AMBITION)) / 20.0
	var prestige := clampf(float(org.reputation) / 8000.0, 0.0, 1.2)
	var score := (prestige - 0.45) * ambition * 1.4
	if p.org_id == org.id:
		score += float(p.attr(Attributes.LOYALTY)) / 30.0
		score += (p.happiness - 50.0) / 60.0
	if org.bankrupt or org.ledger.cash < 0:
		score -= 0.8
	return score


## Probabilité qu'un joueur accepte une offre. Le salaire compte, mais le
## projet sportif et le temps de jeu comptent autant.
##
## Utilisée par l'IA, qui décide en un coup. Le joueur humain, lui, passe par
## NegotiationSystem et discute clause par clause.
static func acceptance_chance(world: World, p: Player, org: Organization,
		salary: int, squad_role: Contract.SquadRole) -> float:
	var demand := salary_demand(world, p, org)
	var money := clampf(float(salary) / maxf(float(demand), 1.0), 0.4, 2.0)
	var score := (money - 1.0) * 1.6 + context_score(world, p, org)

	var ambition := float(p.attr(Attributes.AMBITION)) / 20.0
	if squad_role == Contract.SquadRole.STARTER:
		score += 0.35
	elif squad_role == Contract.SquadRole.SUBSTITUTE:
		score -= 0.30 * ambition
	else:
		score -= 0.65 * ambition
	return clampf(Rng.logistic(score, 1.6), 0.02, 0.97)


static func make_offer(world: World, org: Organization, p: Player, salary: int,
		months: int, squad_role: Contract.SquadRole, buyout: int = 0,
		signing_bonus: int = 0) -> Contract:
	var c := Contract.new()
	c.org_id = org.id
	c.person_id = p.id
	c.salary_yearly = salary
	c.signing_bonus = signing_bonus
	c.start_day = world.today
	c.end_day = GameDate.add_months(world.today, months)
	c.squad_role = squad_role
	c.buyout = buyout if buyout > 0 else int(float(p.market_value) * 1.8)
	c.prize_share_pct = 12.0
	# Le directeur sportif se paie sur ce qu'il fait économiser à la maison.
	c.agent_fee_pct *= 1.0 - StaffSystem.negotiation_edge(world, org) * 0.5
	c.signed_on_day = world.today
	return c


## Signature effective : écritures comptables comprises.
static func sign_contract(world: World, org: Organization, p: Player, c: Contract,
		roster_id: String = "") -> void:
	var upfront := c.upfront_cost()
	if c.signing_bonus > 0:
		org.ledger.debit(world.today, c.signing_bonus,
			Transaction.Category.SIGNING_BONUS,
			"Prime à la signature %s" % p.display_name(), p.id)
	var agent := int(round(float(c.salary_yearly) * c.agent_fee_pct / 100.0))
	if agent > 0:
		org.ledger.debit(world.today, agent, Transaction.Category.AGENT_FEE,
			"Commission d'agent %s" % p.display_name(), p.id)

	p.org_id = org.id
	p.contract = c
	p.wants_out = false
	p.happiness = clampf(p.happiness + 12.0, 0.0, 100.0)
	p.morale = clampf(p.morale + 8.0, 0.0, 100.0)
	# Une signature emporte une promesse de temps de jeu : c'est elle que le
	# joueur invoquera dans six mois s'il ne joue pas.
	p.promised_time = _promise_for(c.squad_role)
	p.promise_day = world.today
	p.concerns.clear()

	var r := world.roster(roster_id) if roster_id != "" \
		else world.main_roster(org.id, p.game_id)
	if r != null:
		r.add_player(p.id)
		if c.squad_role == Contract.SquadRole.STARTER and r.starters.size() < 5:
			r.starters.append(p.id)


## Correspondance entre le rôle inscrit au contrat et la promesse orale.
static func _promise_for(role: Contract.SquadRole) -> int:
	match role:
		Contract.SquadRole.STARTER:
			return PlayingTime.STARTER
		Contract.SquadRole.SUBSTITUTE:
			return PlayingTime.BACKUP
		Contract.SquadRole.ACADEMY:
			return PlayingTime.PROSPECT
	return PlayingTime.SURPLUS


## Rachat d'un joueur sous contrat : la structure vendeuse encaisse la clause.
static func buyout(world: World, buyer: Organization, p: Player,
		new_contract: Contract) -> bool:
	var seller := world.org(p.org_id)
	if seller == null or p.contract == null:
		return false
	var fee := p.contract.buyout
	if fee <= 0 or buyer.ledger.cash < fee:
		return false
	buyer.ledger.debit(world.today, fee, Transaction.Category.BUYOUT_OUT,
		"Rachat de %s à %s" % [p.display_name(), seller.name], seller.id)
	seller.ledger.credit(world.today, fee, Transaction.Category.BUYOUT_IN,
		"Vente de %s à %s" % [p.display_name(), buyer.name], buyer.id)

	var old_roster := world.main_roster(seller.id, p.game_id)
	if old_roster != null:
		old_roster.remove_player(p.id)
	sign_contract(world, buyer, p, new_contract)
	if world.player_org_id == seller.id or world.player_org_id == buyer.id:
		world.add_news(world.today, "Transfert : %s" % p.display_name(),
			"%s rejoint %s pour %s." % [p.long_name(), buyer.name, Money.fmt(fee)],
			"transfer", {"player_id": p.id})
	return true


## Résiliation anticipée : coûte les salaires restants (négociés à la baisse).
static func terminate(world: World, org: Organization, p: Player) -> int:
	if p.contract == null:
		return 0
	var remaining := maxi(p.contract.days_remaining(world.today), 0)
	var cost := int(round(float(p.contract.salary_yearly)
		* float(remaining) / 365.0 * 0.65))
	org.ledger.debit(world.today, cost, Transaction.Category.PLAYER_SALARY,
		"Indemnité de rupture %s" % p.display_name(), p.id)
	var r := world.main_roster(org.id, p.game_id)
	if r != null:
		r.remove_player(p.id)
	p.org_id = ""
	p.contract = null
	p.morale = clampf(p.morale - 10.0, 0.0, 100.0)
	return cost


# ============================================================================
# Passe quotidienne
# ============================================================================

## Les contrats du STAFF sont traités par StaffSystem.daily_tick : lui seul
## sait détacher un encadrant de son roster sans laisser de référence morte.
static func daily_tick(world: World) -> void:
	for pid in world.players:
		var p: Player = world.players[pid]
		if p.contract == null or p.retired:
			continue
		var left := p.contract.days_remaining(world.today)
		if left < 0:
			_expire(world, p)
		elif world.player_org_id == p.org_id and (left == 90 or left == 30):
			world.add_news(world.today, "Contrat : %s" % p.display_name(),
				"Le contrat de %s expire dans %d jours (%s / an)."
					% [p.display_name(), left, Money.fmt(p.contract.salary_yearly)],
				"contract", {"player_id": p.id})


static func _expire(world: World, p: Player) -> void:
	var o := world.org(p.org_id)
	if o != null:
		var r := world.main_roster(o.id, p.game_id)
		if r != null:
			r.remove_player(p.id)
		if world.player_org_id == o.id:
			world.add_news(world.today, "%s est libre" % p.display_name(),
				"Le contrat de %s est arrivé à échéance. Il quitte la structure."
					% p.long_name(), "contract", {"player_id": p.id})
	p.org_id = ""
	p.contract = null
