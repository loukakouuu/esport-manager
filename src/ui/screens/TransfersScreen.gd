extends Screen

## Marché : agents libres et joueurs sous contrat.
##
## Le tableau montre l'ESTIMATION du staff, pas la vérité. Deux structures
## regardant le même joueur ne voient donc pas la même chose — c'est là que se
## gagne ou se perd un recrutement.

var _role_filter := ""
var _free_only := true
var _max_salary := 0


func build() -> void:
	var w := world()
	var o: Organization = game().my_org()
	if o == null:
		return
	var module := w.module_for(w.player_game_id)
	add_child(UiKit.title("Marché des joueurs"))
	add_child(UiKit.subtitle(
		"Budget disponible : %s · masse salariale actuelle %s / an · "
		% [Money.fmt(o.cash()), Money.fmt(FinanceSystem.wage_bill_yearly(w, o))]
		+ "résultat prévisionnel %s / mois"
		% Money.fmt(FinanceSystem.projected_monthly_result(w, o))))

	var filters := UiKit.hbox(6)
	var b_all := UiKit.button("Tous les postes", func():
		_role_filter = ""
		refresh())
	if _role_filter == "":
		b_all.add_theme_color_override("font_color", UiKit.ACCENT)
	filters.add_child(b_all)
	for role in module.roles():
		var rid := role
		var b := UiKit.button(module.role_label(role), func():
			_role_filter = rid
			refresh())
		if _role_filter == rid:
			b.add_theme_color_override("font_color", UiKit.ACCENT)
		filters.add_child(b)
	filters.add_child(UiKit.spacer())
	filters.add_child(UiKit.button(
		"Agents libres uniquement" if not _free_only else "Tout le marché", func():
		_free_only = not _free_only
		refresh()))
	add_child(filters)

	var candidates: Array[Player] = []
	for pid in w.players:
		var p: Player = w.players[pid]
		if p.retired or p.game_id != w.player_game_id:
			continue
		if p.org_id == o.id:
			continue
		if _free_only and not p.is_free_agent():
			continue
		if _role_filter != "" and p.primary_role != _role_filter:
			continue
		if not p.is_free_agent() and not p.transfer_listed and not p.wants_out:
			# Un joueur sous contrat n'apparaît que s'il est accessible :
			# clause payable ou envie de partir.
			if p.contract == null or p.contract.buyout > o.ledger.cash:
				continue
		candidates.append(p)
	candidates.sort_custom(func(a: Player, b: Player):
		return ScoutingSystem.estimated_ca(w, a) > ScoutingSystem.estimated_ca(w, b))
	candidates = candidates.slice(0, 120)

	var columns := [
		{"label": "Joueur", "width": 120},
		{"label": "Poste", "width": 100},
		{"label": "Âge", "width": 40, "align": "right"},
		{"label": "Niveau", "width": 70, "align": "right"},
		{"label": "Potentiel", "width": 70},
		{"label": "Région", "width": 80},
		{"label": "Statut", "width": 150},
		{"label": "Salaire demandé", "width": 110, "align": "right"},
		{"label": "Clause", "width": 90, "align": "right"},
		{"label": "Fiabilité", "width": 140},
	]
	var rows: Array = []
	for p in candidates:
		var demand := ContractSystem.salary_demand(w, p, o)
		var affordable := demand <= FinanceSystem.recurring_monthly_income(w, o) * 12
		var current := w.org(p.org_id)
		rows.append([
			p.display_name(),
			module.role_label(p.primary_role) + (" (IGL)" if p.is_igl else ""),
			str(p.age(w.today)),
			ScoutingSystem.ability_text(w, p),
			{"text": ScoutingSystem.potential_stars(w, p), "color": UiKit.ACCENT},
			p.region,
			"Agent libre" if p.is_free_agent()
				else ("%s — veut partir" % current.name if p.wants_out
					else current.name),
			{"text": Money.fmt_short(demand),
				"color": UiKit.TEXT if affordable else UiKit.BAD},
			Money.fmt_short(p.contract.buyout if p.contract != null else 0),
			ScoutingSystem.confidence_text(w, p),
		])
	add_child(UiKit.scroll(UiKit.table(columns, rows, func(i: int):
		navigate("player", {"player_id": candidates[i].id}))))
