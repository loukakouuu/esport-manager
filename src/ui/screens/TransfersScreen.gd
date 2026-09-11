extends Screen

## Marché : agents libres et joueurs sous contrat.
##
## Le tableau montre l'ESTIMATION du staff, pas la vérité. Deux structures
## regardant le même joueur ne voient donc pas la même chose — c'est là que se
## gagne ou se perd un recrutement.

func build() -> void:
	var w := world()
	var o: Organization = game().my_org()
	if o == null:
		return
	var module := w.module_for(w.player_game_id)
	# Les filtres survivent au rafraîchissement : sinon changer de tri les
	# remettrait à zéro à chaque clic.
	var state := ui("transfers")
	var role_filter := str(state.get("role", ""))
	var free_only := bool(state.get("free_only", true))

	add_child(page_header("Marché des joueurs",
		"Budget disponible : %s · masse salariale actuelle %s / an · "
		% [Money.fmt(o.cash()), Money.fmt(FinanceSystem.wage_bill_yearly(w, o))]
		+ "résultat prévisionnel %s / mois"
		% Money.fmt(FinanceSystem.projected_monthly_result(w, o)), [
			UiKit.button("Agents libres uniquement" if not free_only
				else "Tout le marché", func():
				state["free_only"] = not free_only
				refresh()),
		]))

	add_child(_open_talks())

	var roles: Array = [["", "Tous les postes"]]
	for role in module.roles():
		roles.append([role, module.role_label(role)])
	add_child(UiKit.tabs(roles, state, "role", func(_k): refresh(), ""))

	var candidates: Array[Player] = []
	for pid in w.players:
		var p: Player = w.players[pid]
		if p.retired or p.game_id != w.player_game_id:
			continue
		if p.org_id == o.id:
			continue
		if free_only and not p.is_free_agent():
			continue
		if role_filter != "" and p.primary_role != role_filter:
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
		{"key": "name", "label": "Joueur", "width": 122},
		{"key": "role", "label": "Poste", "width": 108},
		{"key": "age", "label": "Âge", "width": 40, "align": "right"},
		{"key": "ca", "label": "Niveau", "width": 72, "align": "right"},
		{"key": "pot", "label": "Potentiel", "width": 78},
		{"key": "region", "label": "Région", "width": 80},
		{"key": "status", "label": "Statut", "width": 176},
		{"key": "demand", "label": "Salaire demandé", "width": 116, "align": "right"},
		{"key": "buyout", "label": "Clause", "width": 90, "align": "right"},
		{"key": "confidence", "label": "Fiabilité", "width": 150},
	]
	var rows: Array = []
	for p in candidates:
		var demand := ContractSystem.salary_demand(w, p, o)
		# « Tenable » ne veut pas dire « couvert par les revenus » : une
		# structure qui démarre n'en a aucun et peut pourtant signer sur son
		# capital. Tout afficher en rouge dans ce cas ne dirait plus rien.
		var affordable := demand <= maxi(
			FinanceSystem.recurring_monthly_income(w, o) * 12,
			int(float(o.cash()) * 0.45))
		var current := w.org(p.org_id)
		var est := ScoutingSystem.estimated_ca(w, p)
		rows.append({
			"_id": p.id,
			"name": {"text": p.display_name(), "bold": true},
			"role": {"text": module.role_label(p.primary_role)
				+ (" · IGL" if p.is_igl else ""), "sort": p.primary_role},
			"age": {"text": str(p.age(w.today)), "sort": p.age(w.today)},
			"ca": {"text": ScoutingSystem.ability_text(w, p), "sort": est},
			"pot": {"text": UiKit.stars(ScoutingSystem.potential_value(w, p)),
				"color": UiKit.WARN,
				"sort": ScoutingSystem.potential_value(w, p)},
			"region": {"text": p.region},
			"status": {"text": "Agent libre" if p.is_free_agent()
					else ("%s — veut partir" % current.name if p.wants_out
						else current.name),
				"color": UiKit.GOOD if p.is_free_agent() else UiKit.TEXT},
			"demand": {"text": Money.fmt_short(demand), "sort": demand,
				"color": UiKit.TEXT if affordable else UiKit.BAD},
			"buyout": {"text": Money.fmt_short(p.contract.buyout)
					if p.contract != null else "—",
				"sort": p.contract.buyout if p.contract != null else 0},
			# La fiabilité est la colonne la plus importante de l'écran : elle
			# dit à quel point les autres chiffres méritent d'être crus.
			"confidence": {"text": ScoutingSystem.confidence_text(w, p),
				"sort": ScoutingSystem.knowledge(w, p),
				"color": UiKit.TEXT_DIM if ScoutingSystem.knowledge(w, p) < 0.5
					else UiKit.TEXT},
		})
	add_child(sorted_table("transfers.sort", columns, rows, {
		"row_clicked": func(pid): navigate("player", {"player_id": pid}),
	}))
	add_child(UiKit.label(
		"Les niveaux affichés sont l'estimation de votre staff. Un recruteur "
		+ "compétent et un budget de scouting réduisent la marge d'erreur — "
		+ "c'est là que se gagne un recrutement.", UiKit.FS_SMALL,
		UiKit.TEXT_FAINT))


## Discussions en cours. Une négociation vit plusieurs jours : sans rappel
## ici, on l'oublierait et l'agent s'en irait tout seul au bout de trois
## semaines.
func _open_talks() -> Control:
	var w := world()
	var live: Array[Negotiation] = []
	for n in game().my_negotiations():
		if n.is_live():
			live.append(n)
	if live.is_empty():
		return UiKit.gap(0)

	var card := UiKit.card("Négociations en cours", 5, 12)
	for n in live:
		var p := w.player(n.player_id)
		if p == null:
			continue
		var row := UiKit.hbox(8)
		row.add_child(UiKit.label(p.display_name(), UiKit.FS_BODY_L,
			UiKit.TEXT, true))
		row.add_child(UiKit.pill("%d tour%s" % [n.rounds,
			"s" if n.rounds > 1 else ""], UiKit.TEXT_DIM))
		if n.status == Negotiation.Status.COUNTERED:
			row.add_child(UiKit.pill("contre-proposition", UiKit.WARN, true))
		row.add_child(UiKit.label("Patience", UiKit.FS_SMALL, UiKit.TEXT_DIM))
		row.add_child(UiKit.meter(n.mood, 100.0, 90,
			UiKit.GOOD if n.mood > 55.0
				else (UiKit.WARN if n.mood > 25.0 else UiKit.BAD)))
		row.add_child(UiKit.spacer())
		var nid := n.id
		row.add_child(UiKit.button("Reprendre la discussion ▸", func():
			navigate("negotiation", {"negotiation_id": nid})))
		card.body.add_child(row)
	return card.panel
