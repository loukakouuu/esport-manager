class_name FinanceSystem
extends RefCounted

## LE système financier. Objectif assumé : coller au modèle économique réel
## d'une structure esport, où l'immense majorité des organisations perd de
## l'argent et où le vrai jeu consiste à tenir jusqu'à la rentabilité.
##
## Structure des revenus (ordre de grandeur réel d'une org tier 1) :
##   sponsors            50-65 %   ← la colonne vertébrale
##   subvention de ligue 15-25 %   ← réservée aux équipes partenaires (VCT)
##   contenu / média      5-15 %
##   merchandising        5-10 %
##   cashprizes           2-8  %   ← spectaculaire mais marginal
##
## Structure des charges :
##   salaires joueurs    45-60 %   ← poste écrasant
##   salaires staff      10-20 %
##   charges sociales     selon la région
##   infrastructures      5-15 %
##   déplacements         5-10 %
##   marketing            variable
##
## Toutes les écritures passent par le Ledger : le compte de résultat affiché
## au joueur est donc littéralement la somme de ce que le moteur a dépensé.

## Charges patronales par région. Un roster européen coûte structurellement
## plus cher qu'un roster américain à salaire net égal.
const PAYROLL_CHARGE := {
	"EMEA": 0.34,
	"AMERICAS": 0.14,
	"PACIFIC": 0.17,
	"CHINA": 0.20,
}

const CORPORATE_TAX_RATE := 0.25

## Dépense moyenne d'un fan et par mois (cents) — merch et contenu.
const MERCH_PER_FAN := 9        # 0,09 $
const CONTENT_PER_FAN := 6      # 0,06 $


# ============================================================================
# Clôture mensuelle
# ============================================================================

## Passe toutes les écritures récurrentes du mois pour une structure.
## Appelée le 1er de chaque mois par GameSim.
static func monthly_close(world: World, org: Organization) -> Dictionary:
	var day := world.today
	var l := org.ledger
	var summary := {"income": 0, "expense": 0}
	if org.bankrupt:
		return summary

	var before := l.cash

	_post_sponsors(world, org, day)
	_post_league_income(world, org, day)
	_post_merch_and_content(world, org, day)
	_post_salaries(world, org, day)
	_post_facilities(org, day)
	_post_budgets(org, day)
	_post_loans(org, day)

	# Impôt sur les sociétés : une fois par an, sur l'exercice écoulé.
	if GameDate.month_of(day) == 1:
		_post_corporate_tax(org, day)

	summary["income"] = l.total_income(day, day)
	summary["expense"] = l.total_expense(day, day)
	summary["net"] = l.cash - before
	_update_deficit_watch(world, org)
	return summary


static func _post_sponsors(world: World, org: Organization, day: int) -> void:
	# Capacité de production de contenu du mois : le studio et le responsable
	# contenu déterminent combien d'activations la structure peut honorer.
	var capacity := content_capacity(world, org)
	var unmet: Array[String] = []
	var total_penalty := 0
	for deal in org.active_sponsors(day):
		org.ledger.credit(day, deal.monthly_value(), Transaction.Category.SPONSORSHIP,
			"%s — %s" % [deal.sponsor_name, deal.slot_label()], deal.sponsor_name)
		deal.content_delivered_this_month = mini(capacity, deal.content_obligations)
		capacity -= deal.content_delivered_this_month
		# Obligations non tenues : retenue de 15 % et lassitude du partenaire.
		if deal.content_obligations > 0 \
				and deal.content_delivered_this_month < deal.content_obligations:
			var penalty := Money.pct(deal.monthly_value(), 15.0)
			org.ledger.debit(day, penalty, Transaction.Category.MARKETING,
				"Pénalité d'activation — %s" % deal.sponsor_name, deal.sponsor_name)
			deal.renewal_interest = maxf(0.0, deal.renewal_interest - 0.06)
			unmet.append(deal.sponsor_name)
			total_penalty += penalty
		deal.content_delivered_this_month = 0

	# Un seul message par mois plutôt qu'un par partenaire : la boîte de
	# réception doit rester lisible.
	if not unmet.is_empty() and world.player_org_id == org.id:
		world.add_news(day, "Activations sponsors non honorées",
			("Vous ne produisez pas assez de contenu pour %s.\n"
			+ "Retenue totale de %s ce mois-ci.\n\n"
			+ "Un studio de contenu, un responsable dédié ou des joueurs "
			+ "streamers augmentent votre capacité d'activation.")
			% [", ".join(unmet), Money.fmt(total_penalty)], "sponsor")


## Nombre d'activations sponsors réalisables dans le mois.
static func content_capacity(world: World, org: Organization) -> int:
	var capacity := 2 + org.facility_level(Facilities.Kind.CONTENT_STUDIO) * 2
	for sid in org.staff_ids:
		var s := world.staffer(sid)
		if s != null and s.role == Staff.Role.CONTENT_MANAGER:
			capacity += 2 + int(float(s.attr(Staff.MEDIA)) / 5.0)
	# Les joueurs qui créent du contenu comptent aussi.
	for rid in org.all_roster_ids():
		for p in world.players_of(rid):
			if p.has_trait("streamer"):
				capacity += 1
	return capacity


## Subvention de ligue et partage de revenus éditeur (bundles d'équipe).
static func _post_league_income(world: World, org: Organization, day: int) -> void:
	for game_id in org.roster_ids:
		for rid in org.rosters_for(game_id):
			var r := world.roster(rid)
			if r == null:
				continue
			for cid in r.competition_ids:
				var c := world.competition(cid)
				if c == null or c.status == Competition.Status.FINISHED:
					continue
				if c.stipend_yearly > 0:
					org.ledger.credit(day, int(round(float(c.stipend_yearly) / 12.0)),
						Transaction.Category.LEAGUE_STIPEND,
						"Subvention %s" % c.short_name, c.name)
				if c.rev_share_yearly > 0:
					# Le partage éditeur suit la popularité de la structure.
					var share := int(round(float(c.rev_share_yearly) / 12.0
						* clampf(float(org.fanbase) / 500_000.0, 0.25, 2.5)))
					org.ledger.credit(day, share, Transaction.Category.LEAGUE_REV_SHARE,
						"Partage de revenus %s" % c.short_name, c.name)


static func _post_merch_and_content(world: World, org: Organization, day: int) -> void:
	var studio := org.facility_effect(Facilities.Kind.CONTENT_STUDIO)
	var reputation_mult := clampf(float(org.reputation) / 4000.0, 0.35, 2.2)

	var merch := int(round(float(org.fanbase) * float(MERCH_PER_FAN) * reputation_mult))
	if merch > 0:
		org.ledger.credit(day, merch, Transaction.Category.MERCHANDISE,
			"Ventes boutique", "")

	# Le contenu dépend du studio ET des joueurs qui streament.
	var streamer_bonus := 1.0
	for rid in org.all_roster_ids():
		for p in world.players_of(rid):
			if p.has_trait("streamer"):
				streamer_bonus += 0.12
			streamer_bonus += float(p.fan_appeal) / 1000.0
	var content := int(round(float(org.fanbase) * float(CONTENT_PER_FAN)
		* studio * streamer_bonus))
	if content > 0:
		org.ledger.credit(day, content, Transaction.Category.CONTENT,
			"Revenus contenu & stream", "")


static func _post_salaries(world: World, org: Organization, day: int) -> void:
	var charge_rate := float(PAYROLL_CHARGE.get(org.region, 0.20))
	var gross_players := 0
	for rid in org.all_roster_ids():
		for p in world.players_of(rid):
			if p.contract == null or not p.contract.is_active(day):
				continue
			var m := p.contract.monthly_cost()
			gross_players += m
			org.ledger.debit(day, m, Transaction.Category.PLAYER_SALARY,
				"Salaire %s" % p.display_name(), p.id)

	var gross_staff := 0
	for sid in org.staff_ids:
		var s := world.staffer(sid)
		if s == null or s.contract == null or not s.contract.is_active(day):
			continue
		var ms := s.contract.monthly_cost()
		gross_staff += ms
		org.ledger.debit(day, ms, Transaction.Category.STAFF_SALARY,
			"Salaire %s (%s)" % [s.display_name(), s.role_label()], s.id)

	var charges := int(round(float(gross_players + gross_staff) * charge_rate))
	if charges > 0:
		org.ledger.debit(day, charges, Transaction.Category.TAX,
			"Charges sociales (%d %%)" % int(round(charge_rate * 100.0)), org.region)


static func _post_facilities(org: Organization, day: int) -> void:
	var upkeep := Facilities.total_monthly_upkeep(org.facilities)
	if upkeep > 0:
		org.ledger.debit(day, upkeep, Transaction.Category.FACILITY,
			"Entretien des infrastructures", "")


static func _post_budgets(org: Organization, day: int) -> void:
	var mk := int(org.budgets.get("marketing", 0))
	if mk > 0:
		org.ledger.debit(day, mk, Transaction.Category.MARKETING,
			"Budget marketing", "")
	var sc := int(org.budgets.get("scouting", 0))
	if sc > 0:
		org.ledger.debit(day, sc, Transaction.Category.MISC,
			"Budget scouting", "")
	var bc := int(org.budgets.get("bootcamp", 0))
	if bc > 0:
		org.ledger.debit(day, bc, Transaction.Category.BOOTCAMP,
			"Bootcamp", "")


static func _post_loans(org: Organization, day: int) -> void:
	for loan in org.loans:
		if loan.is_settled():
			continue
		var split := loan.split_payment()
		if split[0] > 0:
			org.ledger.debit(day, split[0], Transaction.Category.LOAN_INTEREST,
				"Intérêts — %s" % loan.lender, loan.lender)
		if split[1] > 0:
			org.ledger.debit(day, split[1], Transaction.Category.LOAN_REPAYMENT,
				"Remboursement — %s" % loan.lender, loan.lender)
			loan.outstanding -= split[1]
		loan.months_paid += 1


## Impôt sur les bénéfices de l'exercice écoulé (12 mois glissants).
static func _post_corporate_tax(org: Organization, day: int) -> void:
	var from_day := GameDate.add_years(day, -1)
	var profit := org.ledger.net(from_day, day - 1)
	# On neutralise l'impôt et les mouvements de financement du calcul.
	var pnl := org.ledger.pnl(from_day, day - 1)
	profit -= int(pnl.get(int(Transaction.Category.TAX), 0))
	profit -= int(pnl.get(int(Transaction.Category.INVESTMENT), 0))
	profit -= int(pnl.get(int(Transaction.Category.LOAN_IN), 0))
	profit -= int(pnl.get(int(Transaction.Category.LOAN_REPAYMENT), 0))
	if profit <= 0:
		return
	var tax := int(round(float(profit) * CORPORATE_TAX_RATE))
	org.ledger.debit(day, tax, Transaction.Category.TAX,
		"Impôt sur les sociétés %d" % (GameDate.year_of(day) - 1), "")


# ============================================================================
# Gains de tournoi
# ============================================================================

## Répartit un cashprize. Dans le vrai esport, le prize money n'est PAS
## entièrement pour la structure : le roster en touche une part contractuelle
## (souvent 50 à 80 % au total), et le coach une part réduite.
static func award_prize(world: World, roster_id: String, amount: int,
		label: String, comp_name: String) -> void:
	var r := world.roster(roster_id)
	if r == null or amount <= 0:
		return
	var o := world.org(r.org_id)
	if o == null:
		return
	var day := world.today

	o.ledger.credit(day, amount, Transaction.Category.PRIZE_MONEY,
		"%s — %s" % [comp_name, label], comp_name)

	var to_players := 0
	for p in world.players_of(roster_id):
		if p.contract == null or not r.starters.has(p.id):
			continue
		var share := Money.pct(amount, p.contract.prize_share_pct)
		if share <= 0:
			continue
		to_players += share
		o.ledger.debit(day, share, Transaction.Category.PRIZE_SHARE,
			"Part de gains %s" % p.display_name(), p.id)
		# Toucher un gros chèque remonte le moral, tout simplement.
		p.morale = clampf(p.morale + clampf(float(share) / 2_000_000.0, 0.5, 8.0),
			0.0, 100.0)
	if to_players > 0 and world.player_org_id == o.id:
		world.add_news(day, "Gains de %s" % comp_name,
			"%s encaissés, dont %s reversés au roster."
				% [Money.fmt(amount), Money.fmt(to_players)], "finance")


# ============================================================================
# Financement et survie
# ============================================================================

static func take_loan(world: World, org: Organization, principal: int,
		term_months: int, annual_rate: float = -1.0) -> Loan:
	var loan := Loan.new()
	loan.id = world.ids.next(Ids.LOAN)
	loan.principal = principal
	loan.outstanding = principal
	loan.term_months = term_months
	loan.start_day = world.today
	# Le taux dépend de la solidité perçue de la structure.
	loan.annual_rate = annual_rate if annual_rate > 0.0 else _rate_for(org)
	org.loans.append(loan)
	org.ledger.credit(world.today, principal, Transaction.Category.LOAN_IN,
		"Emprunt sur %d mois" % term_months, loan.lender)
	return loan


static func _rate_for(org: Organization) -> float:
	var risk := 1.0 - clampf(float(org.reputation) / 8000.0, 0.0, 1.0)
	var debt_ratio := clampf(float(org.total_debt()) / maxf(float(absi(org.cash())) + 1.0,
		1.0), 0.0, 3.0)
	return clampf(0.055 + risk * 0.09 + debt_ratio * 0.02, 0.04, 0.24)


## Capacité d'emprunt : les banques ne prêtent pas à une structure exsangue.
static func max_loan_for(world: World, org: Organization) -> int:
	var annual_revenue := org.ledger.total_income(
		GameDate.add_years(world.today, -1), world.today)
	var cap := int(round(float(annual_revenue) * 0.45)) - org.total_debt()
	return maxi(cap, 0)


## Surveillance de la trésorerie. Trois mois dans le rouge et la direction
## impose des mesures ; six mois et la structure dépose le bilan.
static func _update_deficit_watch(world: World, org: Organization) -> void:
	if org.ledger.cash < 0:
		org.months_in_deficit += 1
	else:
		org.months_in_deficit = 0

	if org.months_in_deficit == 0:
		return
	var is_player := world.player_org_id == org.id

	if org.months_in_deficit == 1 and is_player:
		world.add_news(world.today, "Trésorerie négative",
			("La structure est dans le rouge de %s. Réduisez les charges ou "
			+ "trouvez un financement.") % Money.fmt(org.ledger.cash), "warning")
	elif org.months_in_deficit == 3:
		org.board_confidence = maxf(0.0, org.board_confidence - 20.0)
		if is_player:
			world.add_news(world.today, "Avertissement de la direction",
				"Trois mois de déficit consécutifs. La direction exige un "
				+ "retour à l'équilibre sous 90 jours.", "board")
	elif org.months_in_deficit >= 6:
		declare_bankruptcy(world, org)


static func declare_bankruptcy(world: World, org: Organization) -> void:
	org.bankrupt = true
	org.board_confidence = 0.0
	for rid in org.all_roster_ids():
		for p in world.players_of(rid):
			p.org_id = ""
			p.contract = null
		var r := world.roster(rid)
		if r != null:
			r.player_ids.clear()
			r.starters.clear()
	if world.player_org_id == org.id:
		world.add_news(world.today, "Dépôt de bilan",
			"%s cesse ses activités. Le roster est libéré de ses contrats."
				% org.name, "gameover")


# ============================================================================
# Projections (alimentent l'écran Finances)
# ============================================================================

## Charges fixes mensuelles incompressibles à court terme.
static func fixed_monthly_cost(world: World, org: Organization) -> int:
	var total := 0
	var charge_rate := float(PAYROLL_CHARGE.get(org.region, 0.20))
	var payroll := 0
	for rid in org.all_roster_ids():
		for p in world.players_of(rid):
			if p.contract != null and p.contract.is_active(world.today):
				payroll += p.contract.monthly_cost()
	for sid in org.staff_ids:
		var s := world.staffer(sid)
		if s != null and s.contract != null and s.contract.is_active(world.today):
			payroll += s.contract.monthly_cost()
	total += payroll + int(round(float(payroll) * charge_rate))
	total += Facilities.total_monthly_upkeep(org.facilities)
	for k in ["marketing", "scouting", "bootcamp"]:
		total += int(org.budgets.get(k, 0))
	for loan in org.loans:
		if not loan.is_settled():
			total += loan.monthly_payment()
	return total


## Revenus récurrents mensuels (hors cashprizes, par nature imprévisibles).
static func recurring_monthly_income(world: World, org: Organization) -> int:
	var total := 0
	for deal in org.active_sponsors(world.today):
		total += deal.monthly_value()
	for rid in org.all_roster_ids():
		var r := world.roster(rid)
		if r == null:
			continue
		for cid in r.competition_ids:
			var c := world.competition(cid)
			if c == null:
				continue
			total += int(round(float(c.stipend_yearly) / 12.0))
			total += int(round(float(c.rev_share_yearly) / 12.0
				* clampf(float(org.fanbase) / 500_000.0, 0.25, 2.5)))
	var reputation_mult := clampf(float(org.reputation) / 4000.0, 0.35, 2.2)
	total += int(round(float(org.fanbase) * float(MERCH_PER_FAN) * reputation_mult))
	total += int(round(float(org.fanbase) * float(CONTENT_PER_FAN)
		* org.facility_effect(Facilities.Kind.CONTENT_STUDIO)))
	return total


## Résultat mensuel prévisionnel (peut être négatif — c'est même le cas le
## plus courant dans l'esport réel).
static func projected_monthly_result(world: World, org: Organization) -> int:
	return recurring_monthly_income(world, org) - fixed_monthly_cost(world, org)


## Nombre de mois de survie à trésorerie et charges constantes.
## -1 signifie « structure rentable ».
static func runway_months(world: World, org: Organization) -> int:
	var result := projected_monthly_result(world, org)
	if result >= 0:
		return -1
	return int(floor(float(maxi(org.ledger.cash, 0)) / float(-result)))


## Masse salariale annuelle, et son poids par rapport aux revenus : l'indicateur
## que regarde en premier n'importe quel dirigeant de structure.
static func wage_bill_yearly(world: World, org: Organization) -> int:
	var total := 0
	for rid in org.all_roster_ids():
		for p in world.players_of(rid):
			if p.contract != null and p.contract.is_active(world.today):
				total += p.contract.salary_yearly
	return total


static func wage_ratio(world: World, org: Organization) -> float:
	var income := recurring_monthly_income(world, org) * 12
	if income <= 0:
		return 999.0
	return float(wage_bill_yearly(world, org)) / float(income)
