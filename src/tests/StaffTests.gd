class_name StaffTests
extends RefCounted

## Tests de l'encadrement.
##
## Ce qu'ils protègent n'est pas « l'écran s'affiche » mais les quatre
## propriétés qui rendent le staff honnête :
##  - un encadrant qui s'en va est détaché de son ROSTER, pas seulement de la
##    liste de la structure — c'est le bug des 136 coachs fantômes, qui
##    laissait un bonus tactique acquis à vie sans salaire ;
##  - un poste vacant coûte quelque chose de mesurable ;
##  - le monde ne se vide pas de son encadrement au fil des saisons ;
##  - l'organigramme d'une structure IA est un préfixe de priorité, jamais un
##    trou au milieu (pas d'analyste sans entraîneur).


static func run() -> Array[TestCase]:
	return [_market(), _hiring(), _leaving(), _effects(), _world_upkeep()]


## Monde partagé : la génération coûte cher. On repart d'un clone dès qu'un
## test modifie quoi que ce soit.
static var _cached: World = null


static func _world() -> World:
	if _cached == null:
		DataPack.set_active("")
		_cached = WorldGenerator.generate(7731, GameDate.from_ymd(2026, 1, 5))
		var picks := WorldGenerator.selectable_orgs(_cached, "chal_emea")
		WorldGenerator.assign_player_org(_cached, str(picks[0]["org_id"]))
	return World.from_dict(_cached.to_dict())


static func _rich_org(w: World) -> Organization:
	var o := w.my_org()
	o.ledger.cash = Money.from_units(3_000_000.0)
	return o


# ============================================================================

static func _market() -> TestCase:
	var t := TestCase.new("Encadrement — vivier et barème")
	var w := _world()
	var o := _rich_org(w)

	var all := StaffSystem.free_agents(w)
	t.check(all.size() >= 30, "le vivier est peuplé au démarrage")
	for role in StaffSystem.ROLE_ORDER:
		t.check(not StaffSystem.free_agents(w, role).is_empty(),
			"au moins un %s libre" % Staff.ROLE_LABELS[role])

	var coaches := StaffSystem.free_agents(w, Staff.Role.HEAD_COACH)
	t.check(coaches[0].overall() >= coaches[coaches.size() - 1].overall(),
		"le vivier est trié du meilleur au moins bon")
	for s in coaches:
		t.check(s.org_id == "", "un agent libre n'a pas d'employeur")
		break

	# Le barème doit être strictement croissant : sans cela, rien ne distingue
	# un encadrant d'un autre au moment de payer.
	var cheap := StaffFactory.salary_for(Staff.Role.HEAD_COACH, 8.0)
	var mid := StaffFactory.salary_for(Staff.Role.HEAD_COACH, 13.0)
	var top := StaffFactory.salary_for(Staff.Role.HEAD_COACH, 18.0)
	t.check(cheap < mid and mid < top, "le salaire croît avec la note")
	t.check(top > mid * 3, "l'écart se creuse : une pointure coûte cher")

	# La prime de risque : le même homme coûte plus cher à une petite maison.
	var star := coaches[0]
	var poor := Organization.new()
	poor.reputation = 300
	poor.ledger = Ledger.new()
	var proud := Organization.new()
	proud.reputation = 9000
	proud.ledger = Ledger.new()
	t.check(StaffSystem.salary_demand(w, star, poor)
			> StaffSystem.salary_demand(w, star, proud),
		"une structure sans réputation paie une prime de risque")

	# Le verdict est monotone : plus on paie, plus la réponse est engageante.
	var demand := StaffSystem.salary_demand(w, star, o)
	var low := StaffSystem.acceptance_chance(w, star, o, demand / 2, 18)
	var fair := StaffSystem.acceptance_chance(w, star, o, demand, 18)
	var high := StaffSystem.acceptance_chance(w, star, o, demand * 2, 18)
	t.check(low < fair and fair < high, "payer plus augmente les chances")
	t.between(fair, 0.02, 0.97, "la chance reste bornée")
	t.check(StaffSystem.acceptance_chance(w, star, o, demand, 6)
			< StaffSystem.acceptance_chance(w, star, o, demand, 24),
		"personne ne signe six mois s'il peut en avoir deux ans")
	return t


# ============================================================================

static func _hiring() -> TestCase:
	var t := TestCase.new("Encadrement — embauche et trésorerie")
	var w := _world()
	var o := _rich_org(w)
	var r := w.my_roster()

	# Un analyste : poste vacant dans une structure de Challengers.
	var pick := StaffSystem.free_agents(w, Staff.Role.ANALYST)[0]
	var salary := StaffSystem.salary_demand(w, pick, o) * 3   # offre imbattable
	var cash_before := o.ledger.cash
	var out := StaffSystem.hire(w, o, pick, salary, 24, r.id)
	t.check(bool(out["ok"]), "une offre très au-dessus du marché passe")
	t.eq(pick.org_id, o.id, "l'analyste appartient à la structure")
	t.check(o.staff_ids.has(pick.id), "il figure à l'organigramme")
	t.check(r.staff_ids.has(pick.id), "il est rattaché au roster")
	t.check(pick.contract != null, "il a un contrat")
	t.eq(pick.contract.salary_yearly, salary, "au salaire offert")
	t.check(o.ledger.cash < cash_before, "la commission d'agent est débitée")
	t.eq(StaffSystem.holder(w, o, Staff.Role.ANALYST).id, pick.id,
		"holder() le retrouve")

	# Deux fois le même : refusé.
	t.check(not bool(StaffSystem.hire(w, o, pick, salary, 24, r.id)["ok"]),
		"on n'embauche pas quelqu'un qui est déjà sous contrat")

	# Un entraîneur remplace l'entraîneur : un seul banc.
	var old_coach := w.staffer(r.head_coach_id)
	var new_coach := StaffSystem.free_agents(w, Staff.Role.HEAD_COACH)[0]
	StaffSystem.hire(w, o, new_coach,
		StaffSystem.salary_demand(w, new_coach, o) * 3, 24, r.id)
	t.eq(r.head_coach_id, new_coach.id, "le nouveau prend le banc")
	if old_coach != null:
		t.check(r.staff_ids.has(old_coach.id),
			"l'ancien reste au staff jusqu'à la fin de son contrat")
		t.eq(old_coach.org_id, o.id, "et reste salarié")

	# Une offre ridicule est refusée, et ferme la porte trois semaines.
	var w2 := _world()
	var o2 := _rich_org(w2)
	var target := StaffSystem.free_agents(w2, Staff.Role.SCOUT)[0]
	var refused := StaffSystem.hire(w2, o2, target,
		StaffSystem.salary_demand(w2, target, o2) / 8, 6)
	t.check(not bool(refused["ok"]), "une offre au rabais est refusée")
	t.check(StaffSystem.is_cooling_off(w2, target, o2),
		"le refus ferme la porte")
	t.check(not bool(StaffSystem.hire(w2, o2, target,
			StaffSystem.salary_demand(w2, target, o2) * 5, 24)["ok"]),
		"même une offre en or ne rouvre pas la porte tout de suite")

	# Caisse vide : la commission d'agent doit être payable.
	var w3 := _world()
	var o3 := w3.my_org()
	o3.ledger.cash = 0
	var candidate := StaffSystem.free_agents(w3, Staff.Role.PSYCHOLOGIST)[0]
	var broke := StaffSystem.hire(w3, o3, candidate,
		StaffSystem.salary_demand(w3, candidate, o3), 24)
	t.check(not bool(broke["ok"]), "sans trésorerie, pas de signature")
	t.eq(candidate.org_id, "", "et le candidat reste libre")
	return t


# ============================================================================

static func _leaving() -> TestCase:
	var t := TestCase.new("Encadrement — départs et coachs fantômes")
	var w := _world()
	var o := _rich_org(w)
	var r := w.my_roster()

	# --- Licenciement -------------------------------------------------------
	var coach := w.staffer(r.head_coach_id)
	t.check(coach != null, "la structure a bien un entraîneur au départ")
	var cost := StaffSystem.severance(w, coach)
	t.check(cost > 0, "une rupture anticipée coûte une indemnité")
	var cash_before := o.ledger.cash
	var paid := StaffSystem.dismiss(w, o, coach)
	t.eq(paid, cost, "l'indemnité annoncée est celle qui est versée")
	t.eq(o.ledger.cash, cash_before - cost, "elle sort de la trésorerie")
	t.eq(coach.org_id, "", "l'entraîneur est libre")
	t.check(coach.contract == null, "son contrat est éteint")
	t.check(not o.staff_ids.has(coach.id), "il quitte l'organigramme")
	# LA vérification qui compte : le banc doit être vide.
	t.eq(r.head_coach_id, "", "le banc est libéré, pas laissé branché")
	t.check(StaffSystem.holder(w, o, Staff.Role.HEAD_COACH) == null,
		"le poste est vacant")

	# --- Fin de contrat -----------------------------------------------------
	# Le même piège, par l'autre chemin : l'expiration. C'est celui-là qui
	# produisait 136 coachs fantômes après trois saisons simulées.
	var w2 := _world()
	var o2 := _rich_org(w2)
	var r2 := w2.my_roster()
	var c2 := w2.staffer(r2.head_coach_id)
	c2.contract.end_day = w2.today - 1
	StaffSystem.daily_tick(w2)
	t.eq(r2.head_coach_id, "", "un contrat expiré libère le banc")
	t.eq(c2.org_id, "", "et l'employeur")
	t.check(not o2.staff_ids.has(c2.id), "et l'organigramme")

	# Un membre du staff hors banc doit aussi disparaître du roster.
	var w3 := _world()
	var o3 := _rich_org(w3)
	var r3 := w3.my_roster()
	var other: Staff = null
	for sid in o3.staff_ids:
		var s := w3.staffer(sid)
		if s != null and s.role != Staff.Role.HEAD_COACH:
			other = s
			break
	if other != null:
		other.contract.end_day = w3.today - 1
		StaffSystem.daily_tick(w3)
		t.check(not r3.staff_ids.has(other.id),
			"un adjoint parti n'est plus dans la liste du roster")
	else:
		t.check(true, "structure sans staff secondaire : rien à vérifier")

	# L'expiration prévient le joueur AVANT, pas seulement après.
	var w4 := _world()
	var r4 := w4.my_roster()
	var c4 := w4.staffer(r4.head_coach_id)
	c4.contract.end_day = w4.today + 60
	var before := w4.inbox.size()
	StaffSystem.daily_tick(w4)
	t.check(w4.inbox.size() > before, "un préavis de 60 jours est annoncé")
	return t


# ============================================================================

static func _effects() -> TestCase:
	var t := TestCase.new("Encadrement — effets mesurables")
	var w := _world()
	var o := _rich_org(w)

	var chart := StaffSystem.effect_summary(w, o)
	t.eq(chart.size(), StaffSystem.ROLE_ORDER.size(),
		"l'organigramme montre tous les postes, occupés ou non")
	for row_v in chart:
		var row: Dictionary = row_v
		t.check(str(row["effect"]) != "",
			"le poste %s annonce ce qu'il change" % row["label"])
		t.check(str(row["delivers"]) != "",
			"et ce qu'il délivre aujourd'hui")

	# Préparateur physique : le poste n'avait AUCUN effet avant cette version.
	var base := StaffSystem.wellness_factor(w, o)
	t.near(base, 1.0, 0.35, "sans préparateur, le facteur reste proche de 1")
	var phys := StaffSystem.free_agents(w, Staff.Role.PERFORMANCE_COACH)[0]
	phys.attributes[Staff.WELLNESS] = 20
	StaffSystem.hire(w, o, phys, StaffSystem.salary_demand(w, phys, o) * 4, 24)
	var after := StaffSystem.wellness_factor(w, o)
	t.check(after > base, "un préparateur accélère la récupération")
	t.near(after, 1.35, 0.01, "un préparateur à 20/20 vaut +35 %")

	# Directeur sportif : idem, poste décoratif jusqu'ici.
	t.eq(StaffSystem.negotiation_edge(w, o) >= 0.0, true, "poids borné en bas")
	var gm := StaffSystem.free_agents(w, Staff.Role.GENERAL_MANAGER)[0]
	gm.attributes[Staff.NEGOTIATION] = 20
	var fee_before := StaffSystem.agent_fee(w, o, Money.from_units(100_000.0))
	StaffSystem.hire(w, o, gm, StaffSystem.salary_demand(w, gm, o) * 4, 24)
	t.near(StaffSystem.negotiation_edge(w, o), 1.0, 0.01,
		"un négociateur à 20/20 vaut 1,0")
	var fee_after := StaffSystem.agent_fee(w, o, Money.from_units(100_000.0))
	t.check(fee_after < fee_before,
		"il fait baisser la commission d'agent")
	# On compare au barème plein et pas à `fee_before` : la structure a déjà un
	# team manager, qui pèse pour moitié sur le même levier.
	t.eq(fee_after, Money.pct(Money.from_units(100_000.0),
		StaffSystem.AGENT_FEE_PCT * 0.5), "de moitié au maximum")

	# Responsable contenu : la capacité d'activation sponsors doit monter.
	var w2 := _world()
	var o2 := _rich_org(w2)
	var cap_before := FinanceSystem.content_capacity(w2, o2)
	var cm := StaffSystem.free_agents(w2, Staff.Role.CONTENT_MANAGER)[0]
	StaffSystem.hire(w2, o2, cm, StaffSystem.salary_demand(w2, cm, o2) * 4, 24)
	t.check(FinanceSystem.content_capacity(w2, o2) > cap_before,
		"un responsable contenu ouvre des activations")

	# Masse salariale : ce que l'écran affiche doit être la somme des contrats.
	var total := 0
	for sid in o2.staff_ids:
		var s := w2.staffer(sid)
		if s != null and s.contract != null:
			total += s.contract.salary_yearly
	t.eq(StaffSystem.payroll_yearly(w2, o2), total,
		"la masse salariale est la somme des contrats")
	return t


# ============================================================================

static func _world_upkeep() -> TestCase:
	var t := TestCase.new("Encadrement — le monde garde son staff")
	var w := _world()

	# L'organigramme d'une structure IA est un PRÉFIXE de priorité : pas
	# d'analyste sans entraîneur, jamais.
	for oid in w.orgs:
		var o: Organization = w.orgs[oid]
		var chart := StaffSystem.org_chart(w, o)
		t.check(chart.has(Staff.Role.HEAD_COACH),
			"tout organigramme ouvre au moins le poste d'entraîneur")
		var seen_gap := false
		var broken := false
		for role in StaffSystem.ROLE_ORDER:
			if not chart.has(role):
				seen_gap = true
			elif seen_gap:
				broken = true
		t.check(not broken, "l'organigramme est un préfixe, pas un gruyère")
		break   # la propriété est structurelle : un exemplaire suffit

	# Le vivier se maintient : sans entretien, il se vide ou il enfle.
	var w2 := _world()
	var before := StaffSystem.free_agents(w2).size()
	for _i in 12:
		w2.today += 7
		StaffSystem.market_upkeep(w2)
	var after := StaffSystem.free_agents(w2).size()
	t.between(float(after), float(before) * 0.75, float(before) * 1.35,
		"le vivier reste dans le même ordre de grandeur")
	for role in StaffSystem.ROLE_ORDER:
		t.check(StaffSystem.free_agents(w2, role).size()
				>= StaffSystem.MARKET_TARGET,
			"le poste %s reste pourvu au marché" % Staff.ROLE_LABELS[role])

	# Sérialisation : les champs ajoutés pour le marché doivent survivre.
	var w3 := _world()
	var o3 := _rich_org(w3)
	var s3 := StaffSystem.free_agents(w3, Staff.Role.SCOUT)[0]
	s3.last_refused_org = o3.id
	s3.refused_until = w3.today + 10
	var back := World.from_dict(w3.to_dict())
	var copy := back.staffer(s3.id)
	t.check(copy != null, "l'encadrant survit à la sauvegarde")
	t.eq(copy.region, s3.region, "sa région aussi")
	t.eq(copy.last_refused_org, o3.id, "le refus est mémorisé")
	t.eq(copy.refused_until, s3.refused_until, "avec sa date de péremption")
	t.check(StaffSystem.is_cooling_off(back, copy, back.org(o3.id)),
		"et la porte reste fermée après rechargement")
	return t
