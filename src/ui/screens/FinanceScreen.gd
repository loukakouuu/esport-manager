extends Screen

## Écran Finances : compte de résultat, sponsors, budgets, emprunts.
## C'est la page qui doit rendre lisible la phrase « votre structure perd
## 18 000 $ par mois » et donner les leviers pour y remédier.

var _period := 0   # 0 = saison en cours, 1 = 12 derniers mois


func build() -> void:
	var w := world()
	var o: Organization = game().my_org()
	if o == null:
		return
	add_child(UiKit.title("Finances — %s" % o.name))

	var from_day := w.start_day if _period == 0 else GameDate.add_years(w.today, -1)
	var monthly := FinanceSystem.projected_monthly_result(w, o)
	var runway := FinanceSystem.runway_months(w, o)

	var kpis := UiKit.hbox(10)
	kpis.add_child(_kpi("Trésorerie", Money.fmt(o.cash()),
		UiKit.GOOD if o.cash() >= 0 else UiKit.BAD))
	kpis.add_child(_kpi("Résultat mensuel", Money.fmt(monthly),
		UiKit.GOOD if monthly >= 0 else UiKit.BAD))
	kpis.add_child(_kpi("Autonomie",
		"rentable" if runway < 0 else "%d mois" % runway,
		UiKit.GOOD if runway < 0 else (UiKit.BAD if runway <= 3 else UiKit.WARN)))
	kpis.add_child(_kpi("Masse salariale",
		"%s / an" % Money.fmt_short(FinanceSystem.wage_bill_yearly(w, o)),
		_wage_color(FinanceSystem.wage_ratio(w, o))))
	kpis.add_child(_kpi("Poids des salaires",
		"%.0f %% des revenus" % (FinanceSystem.wage_ratio(w, o) * 100.0),
		_wage_color(FinanceSystem.wage_ratio(w, o))))
	kpis.add_child(_kpi("Dette", Money.fmt_short(o.total_debt()),
		UiKit.BAD if o.total_debt() > 0 else UiKit.TEXT))
	add_child(kpis)

	var body := UiKit.hbox(16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)

	var left := UiKit.vbox(12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(left)
	left.add_child(_pnl_panel(w, o, from_day))

	var right := UiKit.vbox(12)
	right.custom_minimum_size = Vector2(420, 0)
	body.add_child(right)
	right.add_child(_sponsors_panel(w, o))
	right.add_child(_budgets_panel(w, o))
	right.add_child(_loans_panel(w, o))


func _wage_color(ratio: float) -> Color:
	if ratio > 0.75:
		return UiKit.BAD
	if ratio > 0.55:
		return UiKit.WARN
	return UiKit.GOOD


func _kpi(title_text: String, value: String, color: Color) -> Control:
	var p := UiKit.panel(10)
	var v := UiKit.vbox(2)
	p.add_child(v)
	v.add_child(UiKit.label(title_text, 12, UiKit.TEXT_DIM))
	v.add_child(UiKit.label(value, 17, color))
	return p


func _pnl_panel(w: World, o: Organization, from_day: int) -> Control:
	var panel := UiKit.panel(12)
	var v := UiKit.vbox(8)
	panel.add_child(v)
	var head := UiKit.hbox(8)
	head.add_child(UiKit.label("Compte de résultat", 15, UiKit.ACCENT))
	head.add_child(UiKit.spacer())
	head.add_child(UiKit.button("Saison en cours" if _period == 1
		else "12 derniers mois", func():
		_period = 1 - _period
		refresh()))
	v.add_child(head)
	v.add_child(UiKit.subtitle("Du %s au %s"
		% [GameDate.format_long(from_day), GameDate.format_long(w.today)]))

	var pnl := o.ledger.pnl(from_day, w.today)
	var income: Array = []
	var expense: Array = []
	for cat in pnl:
		var amount := int(pnl[cat])
		var row := [Transaction.category_label(cat as Transaction.Category),
			UiKit.money_cell(amount)]
		if amount >= 0:
			income.append(row)
		else:
			expense.append(row)
	income.sort_custom(func(a, b): return _cell_value(a[1]) > _cell_value(b[1]))
	expense.sort_custom(func(a, b): return _cell_value(a[1]) < _cell_value(b[1]))

	var cols := [{"label": "Poste", "width": 280, "expand": true},
		{"label": "Montant", "width": 120, "align": "right"}]
	v.add_child(UiKit.label("Produits", 13, UiKit.GOOD))
	v.add_child(UiKit.table(cols, income))
	v.add_child(UiKit.label("Charges", 13, UiKit.BAD))
	v.add_child(UiKit.table(cols, expense))

	var net := o.ledger.net(from_day, w.today)
	v.add_child(UiKit.label("Résultat de la période : %s" % Money.fmt(net), 15,
		UiKit.GOOD if net >= 0 else UiKit.BAD))
	return panel


func _cell_value(cell) -> int:
	if cell is Dictionary:
		var t := str((cell as Dictionary).get("text", "0"))
		return 1 if not t.begins_with("-") else -1
	return 0


func _sponsors_panel(w: World, o: Organization) -> Control:
	var panel := UiKit.panel(12)
	var v := UiKit.vbox(8)
	panel.add_child(v)
	v.add_child(UiKit.label("Sponsors", 15, UiKit.ACCENT))
	var active := o.active_sponsors(w.today)
	if active.is_empty():
		v.add_child(UiKit.subtitle("Aucun partenaire actif."))
	var rows: Array = []
	for d in active:
		rows.append([d.sponsor_name, d.slot_label(),
			Money.fmt_short(d.annual_value),
			GameDate.format_duration_days(d.days_remaining(w.today))])
	v.add_child(UiKit.table([
		{"label": "Marque", "width": 130},
		{"label": "Emplacement", "width": 120},
		{"label": "Par an", "width": 80, "align": "right"},
		{"label": "Reste", "width": 70, "align": "right"},
	], rows))

	v.add_child(UiKit.label("Propositions", 13, UiKit.TEXT_DIM))
	var offers: Array = game().sponsor_offers()
	for offer_v in offers:
		var offer: Dictionary = offer_v
		var risky := float(offer.get("brand_risk", 0.0)) > 0.3
		var h := UiKit.hbox(8)
		var text := "%s — %s · %s / an · %d an(s)" % [
			offer["sponsor_name"],
			SponsorDeal.SLOT_LABELS.get(int(offer["slot"]), ""),
			Money.fmt_short(int(offer["annual_value"])),
			int(offer["years"])]
		h.add_child(UiKit.label(text, 13, UiKit.WARN if risky else UiKit.TEXT))
		h.add_child(UiKit.spacer())
		h.add_child(UiKit.button("Signer", func():
			game().sign_sponsor(offer)))
		v.add_child(h)
		if risky:
			v.add_child(UiKit.subtitle(
				"   Partenaire à risque : plus rémunérateur, mais coûte en image."))
	return panel


func _budgets_panel(w: World, o: Organization) -> Control:
	var panel := UiKit.panel(12)
	var v := UiKit.vbox(8)
	panel.add_child(v)
	v.add_child(UiKit.label("Budgets mensuels", 15, UiKit.ACCENT))
	for entry in [["marketing", "Marketing", "développe la fanbase"],
			["scouting", "Scouting", "affine l'évaluation des joueurs"],
			["bootcamp", "Bootcamp", "cohésion et netteté, au prix de la fatigue"]]:
		var key: String = entry[0]
		var h := UiKit.hbox(8)
		var l := UiKit.label(entry[1], 13)
		l.custom_minimum_size = Vector2(100, 0)
		h.add_child(l)
		var value := UiKit.label(Money.fmt_short(int(o.budgets.get(key, 0))), 13)
		value.custom_minimum_size = Vector2(80, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(value)
		h.add_child(UiKit.button("-", func():
			game().set_budget(key, int(o.budgets.get(key, 0))
				- Money.from_units(2_500.0))))
		h.add_child(UiKit.button("+", func():
			game().set_budget(key, int(o.budgets.get(key, 0))
				+ Money.from_units(2_500.0))))
		h.add_child(UiKit.subtitle(entry[2]))
		v.add_child(h)
	return panel


func _loans_panel(w: World, o: Organization) -> Control:
	var panel := UiKit.panel(12)
	var v := UiKit.vbox(8)
	panel.add_child(v)
	v.add_child(UiKit.label("Financement", 15, UiKit.ACCENT))
	for loan in o.loans:
		if loan.is_settled():
			continue
		v.add_child(UiKit.label("%s — reste %s, %s / mois à %.1f %%"
			% [loan.lender, Money.fmt_short(loan.outstanding),
				Money.fmt_short(loan.monthly_payment()),
				loan.annual_rate * 100.0], 13))
	var capacity := FinanceSystem.max_loan_for(w, o)
	v.add_child(UiKit.subtitle("Capacité d'emprunt : %s" % Money.fmt(capacity)))
	if capacity > 0:
		var amount := mini(capacity, Money.from_units(150_000.0))
		v.add_child(UiKit.button("Emprunter %s sur 24 mois" % Money.fmt_short(amount),
			func(): game().take_loan(amount, 24)))
	return panel
