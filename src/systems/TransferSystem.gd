class_name TransferSystem
extends RefCounted

## Marché des joueurs, côté IA.
##
## Objectif : que le monde vive sans le joueur. Chaque semaine, les structures
## IA comblent leurs trous, prolongent ceux qu'elles veulent garder, se
## séparent de ceux qu'elles paient trop cher, et vont chercher un renfort si
## leur roster est en dessous du niveau de leur ligue.
##
## L'IA respecte les mêmes règles que le joueur : elle paie les clauses, les
## commissions d'agent, et elle peut se ruiner en surpayant.


static func weekly_tick(world: World) -> void:
	for oid in world.orgs:
		var o: Organization = world.orgs[oid]
		if o.is_player_controlled or o.bankrupt:
			continue
		_renew_expiring(world, o)
		_fill_roster(world, o)
		_seek_upgrade(world, o)
	_poach_from_player(world)


## Prolongation des joueurs que la structure veut garder.
static func _renew_expiring(world: World, o: Organization) -> void:
	var rng := world.rng.derive("renew:%s:%d" % [o.id, world.today])
	var r := world.main_roster(o.id, "valorant")
	if r == null:
		return
	for p in world.players_of(r.id):
		if p.contract == null:
			continue
		var left := p.contract.days_remaining(world.today)
		if left > 120 or left < 0:
			continue
		var demand := ContractSystem.salary_demand(world, p, o)
		var affordable := FinanceSystem.projected_monthly_result(world, o) \
			+ p.contract.monthly_cost() - int(round(float(demand) / 12.0))
		if affordable < -Money.from_units(15_000.0) and rng.chance(0.7):
			continue   # trop cher : on le laisse partir
		var months := rng.range_i(12, 30)
		var c := ContractSystem.make_offer(world, o, p, demand, months,
			p.contract.squad_role, int(float(p.market_value) * 1.9))
		if rng.chance(ContractSystem.acceptance_chance(world, p, o, demand,
				c.squad_role)):
			p.contract = c


## Complète un roster incomplet avec des agents libres du bon poste.
static func _fill_roster(world: World, o: Organization) -> void:
	var r := world.main_roster(o.id, "valorant")
	if r == null:
		return
	var module := world.module_for("valorant")
	while r.player_ids.size() < module.team_size():
		var missing := _missing_role(world, r, module)
		var target := _best_free_agent(world, o, missing)
		if target == null:
			break
		var salary := ContractSystem.salary_demand(world, target, o)
		# Compléter le cinq est prioritaire : un forfait coûte plus cher qu'un
		# salaire. On ne renonce que si la structure est vraiment exsangue.
		if FinanceSystem.recurring_monthly_income(world, o) * 12 < salary:
			break
		var c := ContractSystem.make_offer(world, o, target, salary,
			world.rng.range_i(12, 24), Contract.SquadRole.STARTER)
		ContractSystem.sign_contract(world, o, target, c, r.id)


static func _missing_role(world: World, r: Roster, module: GameModule) -> String:
	var counts := {}
	for p in world.players_of(r.id):
		counts[p.primary_role] = int(counts.get(p.primary_role, 0)) + 1
	var ideal: Dictionary = module.ideal_composition()
	for role in ideal:
		if int(counts.get(role, 0)) < int(ideal[role]):
			return str(role)
	return str(module.roles()[0])


static func _best_free_agent(world: World, o: Organization, role: String) -> Player:
	var best: Player = null
	var best_score := -INF
	# La capacité d'embauche se juge sur les revenus annuels, pas sur la
	# trésorerie : une structure momentanément dans le rouge doit quand même
	# pouvoir compléter son cinq, sinon elle déclare forfait et meurt d'un
	# problème passager.
	var ceiling := float(FinanceSystem.recurring_monthly_income(world, o)) * 12.0 * 0.30
	ceiling = maxf(ceiling, float(o.ledger.cash) * 0.5)
	for p in world.free_agents("valorant"):
		if p.retired or p.region != o.region:
			continue
		var fit := 1.0 if p.primary_role == role else 0.55
		var salary := float(ContractSystem.salary_demand(world, p, o))
		if salary > ceiling:
			continue
		var score := float(p.current_ability) * fit \
			+ float(p.potential_ability - p.current_ability) * 0.25
		if score > best_score:
			best_score = score
			best = p
	return best


## Une structure ambitieuse va chercher un joueur meilleur que son maillon
## faible — en payant la clause s'il le faut.
static func _seek_upgrade(world: World, o: Organization) -> void:
	var rng := world.rng.derive("upgrade:%s:%d" % [o.id, world.today])
	if not rng.chance(0.06):
		return
	var r := world.main_roster(o.id, "valorant")
	if r == null or r.starters.size() < 5:
		return
	var weakest: Player = null
	for p in world.players_of(r.id):
		if not r.starters.has(p.id):
			continue
		if weakest == null or p.current_ability < weakest.current_ability:
			weakest = p
	if weakest == null:
		return

	var candidate := _best_free_agent(world, o, weakest.primary_role)
	if candidate == null or candidate.current_ability <= weakest.current_ability + 8:
		return
	var salary := ContractSystem.salary_demand(world, candidate, o)
	var monthly_after := FinanceSystem.projected_monthly_result(world, o) \
		- int(round(float(salary) / 12.0))
	# Une structure IA accepte de creuser son déficit, mais pas de se suicider.
	if monthly_after < 0 and o.ledger.cash < -monthly_after * 8:
		return
	var c := ContractSystem.make_offer(world, o, candidate, salary,
		rng.range_i(18, 30), Contract.SquadRole.STARTER)
	if rng.chance(ContractSystem.acceptance_chance(world, candidate, o, salary,
			c.squad_role)):
		ContractSystem.sign_contract(world, o, candidate, c, r.id)
		if r.starters.size() >= 5:
			r.starters.erase(weakest.id)
			r.starters.append(candidate.id)


## Les structures IA convoitent les joueurs du club du joueur : une offre de
## rachat arrive dans sa boîte de réception, à lui d'accepter ou non.
static func _poach_from_player(world: World) -> void:
	if world.player_org_id == "":
		return
	var rng := world.rng.derive("poach:%d" % world.today)
	if not rng.chance(0.18):
		return
	var my_org := world.my_org()
	var r := world.main_roster(my_org.id, world.player_game_id)
	if r == null:
		return
	var squad := world.players_of(r.id)
	if squad.is_empty():
		return
	# On cible les meilleurs éléments : c'est la rançon du succès.
	squad.sort_custom(func(a, b): return a.current_ability > b.current_ability)
	var target: Player = squad[rng.range_i(0, mini(2, squad.size() - 1))]
	if target.contract == null:
		return

	var suitors: Array[Organization] = []
	for oid in world.orgs:
		var o: Organization = world.orgs[oid]
		if o.is_player_controlled or o.bankrupt:
			continue
		if o.reputation < my_org.reputation - 500:
			continue
		if o.ledger.cash > target.contract.buyout:
			suitors.append(o)
	if suitors.is_empty():
		return
	var buyer: Organization = rng.pick(suitors)
	world.add_news(world.today, "Offre pour %s" % target.display_name(),
		("%s propose de lever la clause de %s pour %s.\n"
		+ "Salaire proposé au joueur : %s / an.")
			% [buyer.name, target.display_name(), Money.fmt(target.contract.buyout),
				Money.fmt(ContractSystem.salary_demand(world, target, buyer))],
		"transfer", {"player_id": target.id, "buyer_org_id": buyer.id,
			"fee": target.contract.buyout})


## Gestion automatique d'une structure — la même que celle de l'IA.
## Sert d'« adjoint » : utilisée par les outils d'équilibrage, et disponible
## si le joueur veut déléguer le recrutement.
static func auto_manage(world: World, o: Organization) -> void:
	if o == null or o.bankrupt:
		return
	_renew_expiring(world, o)
	_fill_roster(world, o)
	_seek_upgrade(world, o)
