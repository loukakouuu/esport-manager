class_name WorldGenerator
extends RefCounted

## Création d'un monde de départ complet et cohérent.
##
## Cohérent veut dire : le niveau des rosters, la réputation, la fanbase, la
## trésorerie, les sponsors signés et les infrastructures d'une structure
## découlent tous d'un même indice de puissance. Un club du bas de tableau de
## Challengers ne peut donc pas se retrouver avec la trésorerie d'une équipe
## VCT — la simulation économique reste crédible dès le premier jour.

const ORGS_PATH := "res://data/world/orgs.json"

## Correspondance indice de puissance (0-100) -> capacité moyenne du roster.
## 40 -> CA 78 (Challengers bas de tableau) · 88 -> CA 158 (top mondial)
static func ca_for_strength(strength: float) -> float:
	return 45.0 + strength * 1.28


static func generate(seed_value: int, start_day: int,
		player_org_name: String = "") -> World:
	var world := World.new()
	world.seed_value = seed_value
	# On grave le pack utilisé : rejouer une sauvegarde avec un autre contenu
	# afficherait des noms qui ne correspondraient plus à rien.
	world.data_pack = DataPack.active()
	world.rng = Rng.new(seed_value)
	world.today = start_day
	world.start_day = start_day
	world.season_year = GameDate.year_of(start_day)

	var module := GameRegistry.get_module("valorant")
	var data := DataFile.load_json(ORGS_PATH, {"leagues": {}}) as Dictionary
	var leagues: Dictionary = data.get("leagues", {})

	for league_key in leagues:
		var region := _region_of(league_key)
		var entries: Array = leagues[league_key]
		var spread := _uniform_strength(entries)
		for entry_v in entries:
			_make_org(world, module, str(league_key), region, entry_v, spread)

	SeasonBuilder.build_season(world, world.season_year)
	_make_free_agents(world, module)
	Log.i("worldgen", "Monde généré : %d structures, %d joueurs, %d compétitions"
		% [world.orgs.size(), world.players.size(), world.competitions.size()])
	return world


## Un pack qui donne la MÊME force à toutes les équipes d'une ligue ne déclare
## aucune hiérarchie — c'est le cas du pack VCT, parce que « Fnatic est plus
## fort que BBL » n'est pas une donnée publique et que l'inventer dans les
## données reviendrait à l'affirmer.
##
## Le jeu en fabrique donc une, dérivée de la graine, exactement comme il
## fabrique les attributs : elle change d'une partie à l'autre, ce qui dit bien
## qu'elle est inventée. Sans ça les douze équipes d'une ligue seraient
## rigoureusement interchangeables — même réputation, même trésorerie, même
## niveau — et le championnat n'aurait plus aucun relief.
static func _uniform_strength(entries: Array) -> bool:
	if entries.size() < 3:
		return false
	var first := float((entries[0] as Dictionary).get("strength", 50))
	for e in entries:
		if absf(float((e as Dictionary).get("strength", 50)) - first) > 0.01:
			return false
	return true


static func _spread_strength(rng: Rng, name: String, base: float) -> float:
	return clampf(base + rng.derive("strength:%s" % name).gauss(0.0, 6.0, -13.0, 13.0),
		20.0, 96.0)


static func _region_of(league_key: String) -> String:
	if league_key.ends_with("emea"):
		return "EMEA"
	if league_key.ends_with("americas"):
		return "AMERICAS"
	if league_key.ends_with("pacific"):
		return "PACIFIC"
	return "CHINA"


const OWNER_MAP := {
	"self_funded": Organization.Owner.SELF_FUNDED,
	"investor": Organization.Owner.INVESTOR,
	"endemic": Organization.Owner.ENDEMIC_BRAND,
	"celebrity": Organization.Owner.CELEBRITY,
	"corporate": Organization.Owner.CORPORATE,
}


static func _make_org(world: World, module: GameModule, league_key: String,
		region: String, entry_v, spread: bool = false) -> Organization:
	var entry: Dictionary = entry_v
	var rng := world.rng
	var strength := float(entry.get("strength", 50))
	if spread:
		strength = _spread_strength(rng, str(entry["name"]), strength)
	var tier1 := league_key.begins_with("vct")

	var o := Organization.new()
	o.id = world.ids.next(Ids.ORG)
	o.name = str(entry["name"])
	o.tag = str(entry["tag"])
	o.region = region
	o.country = str(entry.get("country", "FR"))
	o.color_primary = str(entry.get("color", "#e04141"))
	o.founded_year = GameDate.year_of(world.today) - rng.range_i(2, 14)
	o.owner = OWNER_MAP.get(str(entry.get("owner", "self_funded")),
		Organization.Owner.SELF_FUNDED)
	o.games = _declared_games(entry, strength, rng, o.name)
	o.ledger = Ledger.new()

	# Réputation et audience : exponentielles, comme dans la réalité — l'écart
	# entre le 1er et le 10e mondial est bien plus grand qu'entre le 40e et le 50e.
	o.reputation = int(clampf(pow(strength / 100.0, 2.8) * 12500.0, 90.0, 9800.0))
	o.fanbase = int(clampf(pow(strength / 100.0, 6.6) * 5_800_000.0, 1_500.0, 4_000_000.0))
	o.facilities = _facilities_for(strength, rng)

	o.brand_value = Money.from_units(pow(strength / 100.0, 2.4) * 22_000_000.0)
	o.board_confidence = rng.gauss(62.0, 8.0, 35.0, 88.0)

	world.orgs[o.id] = o
	_make_roster(world, module, o, league_key, region, strength, tier1)
	_make_staff(world, o, region, strength)
	_sign_initial_sponsors(world, o, strength)

	# La trésorerie de départ est calculée APRÈS le roster, le staff et les
	# sponsors : elle vaut un nombre de mois de charges RÉELLES. Une estimation
	# à priori se décorrèle immédiatement des salaires effectivement générés et
	# condamne les petites structures à la faillite dès la première saison.
	var monthly_cost := FinanceSystem.fixed_monthly_cost(world, o)
	var months := rng.range_f(2.5, 4.5) if strength < 55.0 else rng.range_f(4.5, 9.0)
	o.ledger.cash = int(float(monthly_cost) * months)
	o.budgets["marketing"] = Money.pct(monthly_cost, rng.range_f(2.0, 6.0))
	return o


## Disciplines alignées par la structure.
##
## Un pack de données peut les déclarer ("games": ["valorant", "lol"]) — c'est
## le cas du pack VCT, alimenté par les portails Liquipedia de chaque jeu.
## Sinon on en tire un jeu plausible à partir de la puissance : une écurie
## majeure aligne plusieurs sections, un club de Challengers une seule.
##
## Le tirage passe par un RNG DÉRIVÉ et non par le flux principal : ajouter
## cette information ne devait pas décaler tous les mondes existants à graine
## identique.
static func _declared_games(entry: Dictionary, strength: float,
		rng: Rng, org_name: String) -> Array[String]:
	var declared := GameCatalog.sanitize(entry.get("games", []))
	if not declared.is_empty():
		# La discipline simulée est celle des ligues du monde : une structure
		# engagée en VCT aligne forcément Valorant, quoi que dise le pack.
		if not declared.has("valorant"):
			declared.insert(0, "valorant")
		return declared

	var side := rng.derive("games:%s" % org_name)
	var extra := 0
	if strength >= 82.0:
		extra = side.range_i(2, 4)
	elif strength >= 72.0:
		extra = side.range_i(1, 3)
	elif strength >= 62.0:
		extra = side.range_i(0, 2)
	elif strength >= 52.0:
		extra = side.range_i(0, 1)
	var pool: Array = ["cs2", "lol", "rl", "apex", "r6", "dota2", "ow2"]
	side.shuffle(pool)
	var picked: Array = pool.slice(0, extra)
	picked.append("valorant")
	return GameCatalog.sanitize(picked)


## Infrastructures de départ. Elles sont volontairement modestes : une équipe
## de Challengers n'a ni team house ni académie, et leurs charges d'entretien
## représenteraient à elles seules la moitié de son budget.
static func _facilities_for(strength: float, rng: Rng) -> Dictionary:
	var levels := Facilities.default_levels()
	var base := clampi(int(floor(strength / 26.0)), 0, 3)
	for k in Facilities.Kind.values():
		var lvl := clampi(base + rng.range_i(-1, 1), 0, Facilities.MAX_LEVEL)
		# Le confort coûte cher : réservé aux structures qui en ont les moyens.
		if k == Facilities.Kind.TEAM_HOUSE and strength < 68.0:
			lvl = 0
		if k == Facilities.Kind.ACADEMY and strength < 72.0:
			lvl = 0
		if k == Facilities.Kind.CONTENT_STUDIO and strength < 55.0:
			lvl = mini(lvl, 1)
		levels[k] = lvl
	return levels


static func _make_roster(world: World, module: GameModule, o: Organization,
		league_key: String, region: String, strength: float, tier1: bool) -> void:
	var rng := world.rng
	var r := Roster.new()
	r.id = world.ids.next(Ids.ROSTER)
	r.org_id = o.id
	r.game_id = module.id()
	r.name = o.name
	r.region = region
	r.league_key = league_key
	r.tactic = module.default_tactic()
	r.chemistry = rng.gauss(52.0, 12.0, 20.0, 88.0)

	var target := ca_for_strength(strength)
	var roles: Array[String] = [
		ValorantModule.DUELIST, ValorantModule.DUELIST, ValorantModule.INITIATOR,
		ValorantModule.CONTROLLER, ValorantModule.SENTINEL,
	]
	# Un roster VCT embarque un ou deux remplaçants ; en Challengers, rarement.
	var extra := rng.range_i(0, 2) if tier1 else rng.range_i(0, 1)
	for _i in extra:
		roles.append(str(rng.pick(module.roles())))

	# Un pack de données peut fournir l'effectif RÉEL de cette structure. Il ne
	# donne que des identités : le niveau, les attributs et le potentiel
	# restent générés, parce qu'ils n'existent nulle part dans le monde réel.
	var real := real_roster_for(o.name)
	if not real.is_empty():
		roles = _roles_for_real_roster(module, rng, real.size())

	# Si le pack désigne déjà un capitaine, on ne veut pas en tirer un second.
	var igl_index := -1 if _declares_igl(real) else rng.range_i(0, 4)
	for i in roles.size():
		var ca := clampi(int(round(target + rng.gauss(0.0, 9.0, -24.0, 24.0))), 25, 195)
		if i >= 5:
			ca = clampi(ca - rng.range_i(5, 18), 25, 195)
		var p := PlayerFactory.create(rng, module, world.ids, world.today, {
			"target_ca": ca, "role": roles[i], "region": region,
			"igl": i == igl_index,
		})
		if i < real.size():
			_apply_real_identity(world, p, real[i])
		p.org_id = o.id
		p.contract = _make_contract(world, o, p, rng, tier1)
		world.players[p.id] = p
		r.add_player(p.id)
		if i < 5:
			r.starters.append(p.id)
	r.training = TrainingSystem.DEFAULT_PLAN.duplicate()
	_assign_promises(world, r)
	world.rosters[r.id] = r
	o.add_roster(module.id(), r.id)


# ============================================================================
# Effectifs réels fournis par un pack de données
# ============================================================================

const DATA_ROSTERS := "res://data/world/rosters.json"


## Effectif réel déclaré pour une structure, ou [] s'il n'y en a pas.
## Format attendu (voir docs/DATA_PACKS.md et tools/import_liquipedia.gd) :
##   {"teams": {"Fnatic": {"players": [{"tag", "first", "last", "country",
##                                      "born", "igl", "sub"}]}}}
static func real_roster_for(org_name: String) -> Array:
	# Aucun pack ne fournit ce fichier dans l'univers fictif : on vérifie avant
	# de charger, sinon la génération crache un avertissement par structure.
	if not FileAccess.file_exists(DataPack.resolve(DATA_ROSTERS)):
		return []
	var d = DataFile.load_json(DATA_ROSTERS, {})
	if not (d is Dictionary):
		return []
	var teams = (d as Dictionary).get("teams", {})
	if not (teams is Dictionary) or not (teams as Dictionary).has(org_name):
		return []
	var entry = (teams as Dictionary)[org_name]
	var players = (entry as Dictionary).get("players", []) if entry is Dictionary else []
	return players if players is Array else []


## Postes à distribuer sur un effectif réel dont on ne connaît pas les rôles.
## On garde une composition jouable (un contrôleur, une sentinelle…) puis on
## complète, plutôt que de tirer au hasard cinq duellistes.
static func _roles_for_real_roster(module: GameModule, rng: Rng,
		count: int) -> Array[String]:
	var out: Array[String] = []
	var ideal: Dictionary = module.ideal_composition()
	for role in ideal:
		for _n in int(ideal[role]):
			if out.size() < count:
				out.append(str(role))
	while out.size() < count:
		out.append(str(rng.pick(module.roles())))
	return out


## Remplace l'identité générée par celle du pack. Tout le reste — attributs,
## potentiel, contrat, valeur — continue d'être simulé.
static func _apply_real_identity(world: World, p: Player, entry_v) -> void:
	if not (entry_v is Dictionary):
		return
	var entry: Dictionary = entry_v
	var tag := str(entry.get("tag", "")).strip_edges()
	if tag == "":
		return
	p.gamertag = tag
	world.ids.claim_tag(tag)
	var first := str(entry.get("first", "")).strip_edges()
	var last := str(entry.get("last", "")).strip_edges()
	if first != "":
		p.first_name = first
	if last != "":
		p.last_name = last
	var country := str(entry.get("country", "")).strip_edges()
	if country != "":
		p.nationality = country.to_upper()
	# La date de naissance change l'âge, donc la courbe de progression : il
	# faut la reprendre, sinon un vétéran de 28 ans progresserait comme un
	# espoir de 17.
	var born := str(entry.get("born", "")).strip_edges()
	var day := _parse_iso_day(born)
	if day > 0:
		p.birth_day = day
	if bool(entry.get("igl", false)):
		p.is_igl = true
	# Le rôle d'IGL entre dans le calcul de la capacité : sans ce recalcul, la
	# fiche afficherait un niveau qui ne correspond plus au poste occupé.
	AbilityCalc.refresh(p, world.module_for(p.game_id))


static func _declares_igl(real: Array) -> bool:
	for entry in real:
		if entry is Dictionary and bool((entry as Dictionary).get("igl", false)):
			return true
	return false


## "2003-02-06" -> index de jour, ou -1 si la chaîne n'est pas exploitable.
static func _parse_iso_day(iso: String) -> int:
	var parts := iso.split("-")
	if parts.size() != 3:
		return -1
	var y := int(parts[0])
	var m := int(parts[1])
	var d := int(parts[2])
	if y < 1970 or m < 1 or m > 12 or d < 1 or d > 31:
		return -1
	return GameDate.from_ymd(y, m, d)


## Statut promis à la création du monde : chaque joueur arrive avec un accord
## déjà négocié, sinon tout un effectif se croirait titulaire dès la première
## semaine et le vestiaire exploserait sans que le joueur y soit pour rien.
static func _assign_promises(world: World, r: Roster) -> void:
	var squad := world.players_of(r.id)
	squad.sort_custom(func(a: Player, b: Player):
		return a.current_ability > b.current_ability)
	for i in squad.size():
		var p: Player = squad[i]
		var status := PlayingTime.STARTER
		if i == 0 and squad.size() >= 5:
			status = PlayingTime.KEY
		elif i >= 5:
			status = PlayingTime.BACKUP
		elif not r.starters.has(p.id):
			status = PlayingTime.ROTATION
		if p.age(world.today) <= 18 and not r.starters.has(p.id):
			status = PlayingTime.PROSPECT
		p.promised_time = status
		p.promise_day = world.today


static func _make_contract(world: World, o: Organization, p: Player, rng: Rng,
		tier1: bool) -> Contract:
	var c := Contract.new()
	c.org_id = o.id
	c.person_id = p.id
	c.salary_yearly = PlayerFactory.salary_for_ca(p.current_ability, p.reputation)
	# Chaque structure paie un peu au-dessus ou en dessous du marché.
	c.salary_yearly = Money.pct(c.salary_yearly, rng.range_f(85.0, 118.0))
	c.start_day = GameDate.add_years(world.today, -rng.range_i(0, 2))
	c.end_day = GameDate.add_months(world.today, rng.range_i(4, 32))
	c.buyout = int(float(p.market_value) * rng.range_f(1.1, 2.4))
	c.prize_share_pct = rng.range_f(9.0, 15.0) if tier1 else rng.range_f(12.0, 18.0)
	c.signed_on_day = c.start_day
	return c


static func _make_staff(world: World, o: Organization, region: String,
		strength: float) -> void:
	var rng := world.rng
	var r := world.main_roster(o.id, "valorant")
	var quality := clampf(4.0 + strength / 7.0, 4.0, 19.0)

	var roles: Array = [Staff.Role.HEAD_COACH]
	if strength >= 45.0:
		roles.append(Staff.Role.ANALYST)
	if strength >= 60.0:
		roles.append(Staff.Role.TEAM_MANAGER)
	if strength >= 70.0:
		roles.append(Staff.Role.ASSISTANT_COACH)
	if strength >= 78.0:
		roles.append(Staff.Role.PERFORMANCE_COACH)
	if strength >= 84.0:
		roles.append(Staff.Role.PSYCHOLOGIST)

	for role in roles:
		# La dispersion est volontairement resserrée et bornée autour du niveau
		# de la structure. Le salaire du staff est exponentiel : deux points de
		# note au-dessus de son marché et une équipe de Challengers se retrouve
		# avec un coach à 190 k$/an qu'elle ne pourrait jamais s'offrir.
		var target := clampf(rng.gauss(quality, 1.5, 3.0, 19.5),
			maxf(quality - 3.0, 3.0), minf(quality + 2.5, 19.5))
		var s := StaffFactory.create(rng, world.ids, world.today, role, {
			"region": region,
			"target_overall": target,
		})
		s.org_id = o.id
		var c := Contract.new()
		c.kind = Contract.Kind.STAFF
		c.org_id = o.id
		c.person_id = s.id
		c.salary_yearly = StaffFactory.salary_for(role, s.overall())
		c.start_day = world.today
		c.end_day = GameDate.add_months(world.today, rng.range_i(8, 30))
		s.contract = c
		world.staff[s.id] = s
		o.staff_ids.append(s.id)
		if r != null:
			if role == Staff.Role.HEAD_COACH:
				r.head_coach_id = s.id
			else:
				r.staff_ids.append(s.id)


## Sponsors déjà en place au démarrage, avec des échéances étalées pour que le
## joueur ne perde pas tous ses partenaires le même mois.
static func _sign_initial_sponsors(world: World, o: Organization,
		strength: float) -> void:
	var rng := world.rng
	# Même une petite structure a plusieurs partenaires : c'est sa seule source
	# de revenus réellement pilotable.
	var wanted := 2
	if strength >= 42.0:
		wanted = 3
	if strength >= 65.0:
		wanted = 4
	if strength >= 80.0:
		wanted = 5

	var offers := SponsorSystem.offers_for(world, o, 10)
	var signed := 0
	for offer_v in offers:
		if signed >= wanted:
			break
		var offer: Dictionary = offer_v
		if float(o.reputation) < float(offer.get("min_reputation", 0)):
			continue
		# Une petite structure ne décroche pas un contrat à sept chiffres.
		var deal := SponsorSystem.sign_deal(world, o, offer)
		deal.start_day = GameDate.add_months(world.today, -rng.range_i(1, 14))
		deal.end_day = GameDate.add_months(deal.start_day,
			int(offer.get("years", 2)) * 12)
		if deal.end_day <= world.today:
			deal.end_day = GameDate.add_months(world.today, rng.range_i(2, 10))
		signed += 1


## Agents libres : un vivier crédible, avec des jeunes à fort potentiel, des
## vétérans en fin de carrière et quelques bons joueurs sans contrat.
static func _make_free_agents(world: World, module: GameModule) -> void:
	var rng := world.rng
	var regions := ["EMEA", "AMERICAS", "PACIFIC", "CHINA"]
	for region in regions:
		# Jeunes talents (le vivier de l'académie)
		for _i in 22:
			var p := PlayerFactory.create(rng, module, world.ids, world.today, {
				"target_ca": rng.gauss_i(66.0, 14.0, 30, 110),
				"age": rng.range_i(16, 19), "region": region,
				"potential_bonus": rng.range_i(0, 25),
			})
			world.players[p.id] = p
		# Joueurs confirmés sans contrat
		for _i in 14:
			var p2 := PlayerFactory.create(rng, module, world.ids, world.today, {
				"target_ca": rng.gauss_i(102.0, 16.0, 60, 150),
				"age": rng.range_i(20, 25), "region": region,
			})
			world.players[p2.id] = p2
		# Vétérans en fin de parcours
		for _i in 6:
			var p3 := PlayerFactory.create(rng, module, world.ids, world.today, {
				"target_ca": rng.gauss_i(112.0, 15.0, 70, 160),
				"age": rng.range_i(26, 31), "region": region,
			})
			world.players[p3.id] = p3


# ============================================================================
# Prise en main d'une structure par le joueur
# ============================================================================

## Le joueur reprend une structure existante. On lui donne le contrôle, on fixe
## les objectifs du board et on lui envoie son premier message.
static func assign_player_org(world: World, org_id: String) -> void:
	var o := world.org(org_id)
	if o == null:
		return
	world.player_org_id = org_id
	# On ouvre sur la section principale : le joueur peut ensuite basculer sur
	# une autre équipe de la maison (académie, autre discipline).
	var main := world.main_roster(org_id, world.player_game_id)
	world.player_roster_id = main.id if main != null else ""
	o.is_player_controlled = true
	o.objectives = BoardSystem.season_objectives(world, o)
	world.add_news(world.today, "Bienvenue chez %s" % o.name,
		("Vous prenez la direction sportive de %s.\n\n"
		+ "Trésorerie : %s\nRéputation : %s\nFans : %s\n\n"
		+ "La direction attend : %s")
		% [o.name, Money.fmt(o.cash()), _stars_text(o.stars()),
			_short_number(o.fanbase), _objectives_text(o.objectives)], "board")


## Structures que le joueur peut choisir au démarrage, triées par difficulté.
static func selectable_orgs(world: World, league_key: String = "") -> Array:
	var out: Array = []
	for oid in world.orgs:
		var o: Organization = world.orgs[oid]
		var r := world.main_roster(o.id, "valorant")
		if r == null:
			continue
		if league_key != "" and r.league_key != league_key:
			continue
		out.append({
			"org_id": o.id, "name": o.name, "tag": o.tag,
			"league_key": r.league_key, "region": o.region,
			"reputation": o.reputation, "cash": o.cash(),
			"games": o.games.duplicate(),
			"fanbase": o.fanbase, "owner": o.owner_label(),
		})
	out.sort_custom(func(a, b): return int(a["reputation"]) > int(b["reputation"]))
	return out


static func _stars_text(stars: float) -> String:
	var full := int(floor(stars))
	var s := ""
	for i in 5:
		s += "*" if i < full else "."
	return s


static func _short_number(n: int) -> String:
	if n >= 1_000_000:
		return "%s M" % String.num(float(n) / 1_000_000.0, 1)
	if n >= 1_000:
		return "%d k" % int(n / 1000)
	return str(n)


static func _objectives_text(objectives: Array) -> String:
	var parts: Array[String] = []
	for o in objectives:
		parts.append(str((o as Dictionary).get("label", "")))
	return ", ".join(parts)
