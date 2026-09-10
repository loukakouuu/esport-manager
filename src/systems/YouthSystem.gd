class_name YouthSystem
extends RefCounted

## Relève : la génération annuelle de jeunes joueurs.
##
## Sans ce système le monde meurt lentement — les retraites vident le vivier
## saison après saison et, au bout de cinq ans, il n'y a plus assez de joueurs
## pour remplir les rosters. C'est aussi ce qui donne un intérêt au long terme :
## repérer un espoir de 17 ans avant les autres est LE plaisir d'un jeu de
## gestion, et il faut donc qu'il en naisse chaque année.
##
## Deux flux :
##  1. les PROMOTIONS D'ACADÉMIE — une structure dotée d'un centre de formation
##     sort ses propres jeunes, d'autant meilleurs que l'infrastructure et le
##     coach le sont ;
##  2. le VIVIER LIBRE — des jeunes sans club, que tout le monde peut signer.
##
## La qualité suit une loi très déséquilibrée : beaucoup de joueurs corrects,
## quelques bons, un ou deux cracks par génération mondiale. C'est ce qui rend
## le scouting précieux : le crack est indiscernable du bon à 17 ans.

## Nombre de jeunes visé par place de roster, vivier libre compris.
const POOL_RATIO := 1.30
## Plancher : même un monde saturé produit une nouvelle génération.
const MIN_INTAKE := 55


## Appelée une fois par saison, après les retraites.
static func yearly_intake(world: World) -> Dictionary:
	var report := {"academy": 0, "free": 0, "gems": 0}
	for game_id in GameRegistry.all_ids():
		var module := GameRegistry.get_module(str(game_id))
		_intake_for_game(world, module, report)
	return report


static func _intake_for_game(world: World, module: GameModule,
		report: Dictionary) -> void:
	var rng := world.rng.derive("youth:%d" % world.today)

	var slots := 0
	var orgs: Array[Organization] = []
	for oid in world.orgs:
		var o: Organization = world.orgs[oid]
		if o.bankrupt:
			continue
		if o.rosters_for(module.id()).is_empty():
			continue
		orgs.append(o)
		slots += module.max_roster_size()
	if orgs.is_empty():
		return

	var active := 0
	for pid in world.players:
		var p: Player = world.players[pid]
		if not p.retired and p.game_id == module.id():
			active += 1

	var target := int(float(slots) * POOL_RATIO)
	var intake := maxi(target - active, MIN_INTAKE)

	# Un tiers du contingent sort des académies, le reste arrive sur le marché.
	var from_academy := int(float(intake) * 0.34)
	_promote_academies(world, module, rng, orgs, from_academy, report)
	_seed_free_agents(world, module, rng, orgs, intake - from_academy, report)


# ============================================================================
# Promotions d'académie
# ============================================================================

## Les places d'académie vont aux structures qui ont investi : niveau du centre
## de formation, qualité du coach sur la formation des jeunes, réputation.
static func _promote_academies(world: World, module: GameModule, rng: Rng,
		orgs: Array[Organization], count: int, report: Dictionary) -> void:
	var weighted: Array = []
	var total := 0.0
	for o in orgs:
		var w := _academy_strength(world, o, module)
		if w <= 0.0:
			continue
		weighted.append({"org": o, "w": w})
		total += w
	if weighted.is_empty() or total <= 0.0:
		return

	for _i in count:
		var roll := rng.randf() * total
		var chosen: Organization = null
		for entry_v in weighted:
			var entry: Dictionary = entry_v
			roll -= float(entry["w"])
			if roll <= 0.0:
				chosen = entry["org"]
				break
		if chosen == null:
			chosen = (weighted[0] as Dictionary)["org"]
		var r := world.main_roster(chosen.id, module.id())
		if r == null or r.size() >= module.max_roster_size():
			# Roster plein : le jeune part sur le marché plutôt que d'être perdu.
			_make_prospect(world, module, rng, chosen.region, null, report)
			continue
		var p := _make_prospect(world, module, rng, chosen.region, chosen, report)
		r.add_player(p.id)
		report["academy"] = int(report["academy"]) + 1
		if chosen.id == world.player_org_id:
			world.add_news(world.today, "Promotion de l'académie : %s"
				% p.display_name(),
				"%s, %d ans, %s, rejoint le groupe professionnel. "
					% [p.long_name(), p.age(world.today),
						module.role_label(p.primary_role)]
				+ "Avis du staff : %s." % _potential_phrase(
					ScoutingSystem.potential_value(world, p)),
				"squad", {"player_id": p.id})


## Avis du staff en toutes lettres. Les systèmes ne connaissent pas l'interface
## (règle d'architecture) : on ne peut donc pas renvoyer d'étoiles ici.
static func _potential_phrase(stars: float) -> String:
	if stars >= 4.5:
		return "un talent générationnel, s'il tient la distance"
	if stars >= 3.5:
		return "de quoi jouer en ligue partenaire d'ici deux ou trois ans"
	if stars >= 2.5:
		return "un bon élément de Challengers en devenir"
	if stars >= 1.5:
		return "correct, sans plus, mais il ne coûte rien"
	return "peu de marge, un joueur de complément"


## Poids d'une structure dans le tirage des promotions d'académie.
static func _academy_strength(world: World, o: Organization,
		module: GameModule) -> float:
	var level := float(o.facility_level(Facilities.Kind.ACADEMY))
	if level <= 0.0:
		# Sans centre de formation, on ne forme personne — mais une grosse
		# structure attire quand même quelques jeunes par sa seule réputation.
		return clampf(float(o.reputation) / 10000.0, 0.0, 1.0) * 0.35
	var youth := 0.0
	var r := world.main_roster(o.id, module.id())
	if r != null:
		var coach := world.staffer(r.head_coach_id)
		if coach != null:
			youth = float(coach.attr(Staff.YOUTH_DEVELOPMENT)) / 20.0
	return level * (0.6 + youth * 0.8) \
		+ clampf(float(o.reputation) / 10000.0, 0.0, 1.0) * 0.5


# ============================================================================
# Vivier libre
# ============================================================================

static func _seed_free_agents(world: World, module: GameModule, rng: Rng,
		orgs: Array[Organization], count: int, report: Dictionary) -> void:
	# On répartit par région au prorata du nombre de structures : une région
	# à quatre ligues produit plus de joueurs qu'une région à une.
	var regions: Array[String] = []
	for o in orgs:
		regions.append(o.region)
	if regions.is_empty():
		regions = ["EMEA"]
	for _i in count:
		_make_prospect(world, module, rng, str(rng.pick(regions)), null, report)


# ============================================================================
# Fabrication d'un espoir
# ============================================================================

## Répartition du potentiel d'une génération. Volontairement très inégale :
## un crack par centaine, et rien ne le distingue d'un bon joueur à 17 ans
## autrement que par le travail d'un recruteur.
const POTENTIAL_TIERS := [
	[0.52, 0],      # 52 % : plafond ordinaire (jamais tier 1)
	[0.32, 14],     # 32 % : bon joueur de Challengers
	[0.13, 30],     # 13 % : titulaire VCT crédible
	[0.03, 48],     #  3 % : candidat au top mondial
]


static func _make_prospect(world: World, module: GameModule, rng: Rng,
		region: String, org: Organization, report: Dictionary) -> Player:
	var bonus := 0
	var roll := rng.randf()
	var acc := 0.0
	for tier_v in POTENTIAL_TIERS:
		var tier: Array = tier_v
		acc += float(tier[0])
		if roll <= acc:
			bonus = int(tier[1])
			break
	if bonus >= 48:
		report["gems"] = int(report["gems"]) + 1

	# Un jeune formé dans une bonne académie démarre plus haut : il a travaillé
	# avec de meilleurs outils et de meilleurs coéquipiers.
	var head_start := 0
	if org != null:
		head_start = int(float(org.facility_level(Facilities.Kind.ACADEMY)) * 3.5)

	var age := rng.range_i(16, 18)
	var p := PlayerFactory.create(rng, module, world.ids, world.today, {
		"region": region,
		"age": age,
		"target_ca": rng.gauss_i(62.0 + float(head_start), 11.0, 35, 105),
		"potential_bonus": bonus + head_start / 2,
	})
	# Un joueur de 17 ans n'a pas de nom : sa réputation se construit en jouant.
	p.reputation = clampi(int(float(p.reputation) * 0.35), 5, 900)
	p.market_value = PlayerFactory.market_value_for(p.current_ability,
		p.potential_ability, age, p.reputation)
	p.promised_time = PlayingTime.PROSPECT
	p.promise_day = world.today
	world.players[p.id] = p

	if org != null:
		p.org_id = org.id
		p.contract = _academy_contract(world, org, p)
	else:
		report["free"] = int(report["free"]) + 1
	return p


## Contrat d'académie : court, peu cher, et sans clause de rachat — c'est ce
## qui rend une pépite maison si rentable, et si facile à se faire piquer.
static func _academy_contract(world: World, org: Organization,
		p: Player) -> Contract:
	var c := Contract.new()
	c.org_id = org.id
	c.person_id = p.id
	c.salary_yearly = int(float(PlayerFactory.salary_for_ca(
		p.current_ability, p.reputation)) * 0.55)
	c.start_day = world.today
	c.end_day = GameDate.add_months(world.today, 24)
	c.buyout = int(float(p.market_value) * 1.8)
	c.prize_share_pct = 8.0
	c.squad_role = Contract.SquadRole.ACADEMY
	c.signed_on_day = world.today
	return c
