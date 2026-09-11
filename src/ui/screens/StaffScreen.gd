extends Screen

## Encadrement : l'organigramme d'un côté, le marché de l'autre.
##
## L'organigramme est la moitié importante. Le staff pesait déjà sur cinq
## systèmes sans que le joueur ne voie jamais la contrepartie de ce qu'il
## payait : chaque ligne annonce donc ce que le poste change dans le moteur, et
## ce que le titulaire en place délivre. Un poste vacant le dit aussi, avec la
## valeur plancher subie à la place.
##
## Le marché ne se négocie pas clause par clause comme pour un joueur : on
## règle un salaire, une durée, et l'intermédiaire répond. L'arbitrage est
## ailleurs — combien de postes ouvrir, et à quel niveau.

const TABS := [
	["chart", "Organigramme"],
	["market", "Marché"],
]

const MONTH_CHOICES := [12, 18, 24, 36]


func build() -> void:
	var o: Organization = game().my_org()
	if o == null:
		return
	var payroll: int = game().staff_payroll()
	add_child(page_header("Encadrement",
		"%d personnes, %s de masse salariale par an (%s / mois)."
			% [o.staff_ids.size(), Money.fmt(payroll),
				Money.fmt_short(int(round(float(payroll) / 12.0)))]))
	add_child(tab_bar("staff", TABS, "chart"))

	if current_tab("staff", "chart") == "chart":
		_build_chart(o)
	else:
		_build_market(o)


# ============================================================================
# Organigramme
# ============================================================================

func _build_chart(o: Organization) -> void:
	var list := UiKit.vbox(6)
	for entry_v in game().staff_chart():
		list.add_child(_role_row(o, entry_v as Dictionary))
	list.add_child(UiKit.gap(4))
	list.add_child(UiKit.wrap(
		"Un poste vacant n'est pas neutre : le moteur applique une valeur "
		+ "plancher à sa place. Sans entraîneur, l'équipe joue avec 8/20 de "
		+ "tactique, quel que soit le niveau des joueurs.",
		UiKit.FS_BODY, UiKit.TEXT_FAINT))
	add_child(UiKit.scroll(list))


func _role_row(o: Organization, e: Dictionary) -> Control:
	var s: Staff = e.get("staff", null)
	var panel := UiKit.panel(10)
	var h := UiKit.hbox(12)
	panel.add_child(h)

	var info := UiKit.vbox(2)
	info.custom_minimum_size = Vector2(300, 0)
	info.add_child(UiKit.label(str(e["label"]), UiKit.FS_LEAD))
	info.add_child(UiKit.wrap(str(e["effect"]), UiKit.FS_SMALL, UiKit.TEXT_DIM))
	h.add_child(info)

	var who := UiKit.vbox(2)
	who.custom_minimum_size = Vector2(230, 0)
	if s == null:
		who.add_child(UiKit.label("Poste vacant", UiKit.FS_BODY_L, UiKit.WARN))
		who.add_child(UiKit.caption(str(e["delivers"]), UiKit.BAD))
	else:
		who.add_child(UiKit.label("%s, %d ans" % [s.display_name(),
			s.age(world().today)], UiKit.FS_BODY_L))
		who.add_child(UiKit.caption(str(e["delivers"]), UiKit.TEXT_DIM))
	h.add_child(who)

	if s != null:
		var note := UiKit.vbox(2)
		note.add_child(UiKit.label("%.1f / 20" % s.overall(), UiKit.FS_BODY_L,
			UiKit.rating_color(s.overall())))
		note.add_child(UiKit.meter(s.overall(), 20.0, 90))
		h.add_child(note)

		var money := UiKit.vbox(2)
		money.custom_minimum_size = Vector2(150, 0)
		var salary := s.contract.salary_yearly if s.contract != null else 0
		money.add_child(UiKit.label("%s / an" % Money.fmt_short(salary),
			UiKit.FS_BODY_L))
		if s.contract != null:
			var left := s.contract.days_remaining(world().today)
			money.add_child(UiKit.caption("Jusqu'en %s (%d j)"
				% [GameDate.format_month_year(s.contract.end_day), left],
				UiKit.WARN if left < 120 else UiKit.TEXT_FAINT))
		h.add_child(money)

	h.add_child(UiKit.spacer())
	h.add_child(_role_actions(o, e, s))
	return panel


func _role_actions(o: Organization, e: Dictionary, s: Staff) -> Control:
	var col := UiKit.vbox(4)
	var role := int(e["role"])
	if s == null:
		col.add_child(UiKit.button("Recruter", func():
			ui("staff")["tab"] = "market"
			ui("staff.market")["role"] = role
			refresh()))
		return col

	var row := UiKit.hbox(6)
	var demand: int = game().staff_demand(s.id)
	var current := s.contract.salary_yearly if s.contract != null else 0
	if demand > current:
		row.add_child(UiKit.button("Prolonger à %s" % Money.fmt_short(demand),
			func(): _renew(s, demand)))
	else:
		row.add_child(UiKit.button("Prolonger", func(): _renew(s, maxi(demand, current))))
	var cost: int = game().staff_severance(s.id)
	var fire := UiKit.danger("Licencier", func(): _dismiss(s))
	fire.disabled = o.ledger.cash < cost
	row.add_child(fire)
	col.add_child(row)
	col.add_child(UiKit.caption("Indemnité de rupture : %s" % Money.fmt_short(cost)))
	return col


func _renew(s: Staff, salary: int) -> void:
	var out: Dictionary = game().renew_staff(s.id, salary, StaffSystem.DEFAULT_MONTHS)
	ui("staff.market")["message"] = str(out.get("reason", ""))
	if bool(out.get("ok", false)):
		ui("staff.market")["message"] = "%s prolonge de %d mois." % [
			s.display_name(), StaffSystem.DEFAULT_MONTHS]
	refresh()


func _dismiss(s: Staff) -> void:
	var cost: int = game().dismiss_staff(s.id)
	ui("staff.market")["message"] = "%s quitte la structure (%s d'indemnité)." % [
		s.display_name(), Money.fmt(cost)]
	refresh()


# ============================================================================
# Marché
# ============================================================================

func _build_market(o: Organization) -> void:
	var state := ui("staff.market")
	var role := int(state.get("role", Staff.Role.HEAD_COACH))

	var filters := UiKit.hbox(2)
	for r_v in StaffSystem.ROLE_ORDER:
		var r: int = r_v
		var occupied := StaffSystem.holder(world(), o, r) != null
		var text := str(Staff.ROLE_LABELS.get(r, "?"))
		if occupied:
			text += " •"
		var b := UiKit.button(text, func():
			state["role"] = r
			state.erase("selected")
			refresh())
		b.add_theme_color_override("font_color",
			UiKit.ACCENT if r == role else UiKit.TEXT_DIM)
		filters.add_child(b)
	add_child(UiKit.scroll_h(filters))

	var msg := str(state.get("message", ""))
	if msg != "":
		add_child(UiKit.label(msg, UiKit.FS_BODY_L, UiKit.INFO))

	var pool: Array[Staff] = game().staff_market(role)
	var parts: Array = split(392)
	var main: VBoxContainer = parts[0]
	var side: VBoxContainer = parts[1]

	if pool.is_empty():
		main.add_child(UiKit.label("Personne de libre à ce poste actuellement.",
			UiKit.FS_BODY_L, UiKit.TEXT_DIM))
		return

	var months := int(state.get("months", StaffSystem.DEFAULT_MONTHS))
	var rows: Array = []
	for s in pool:
		var demand: int = game().staff_demand(s.id)
		rows.append({
			"name": s.display_name(),
			"age": s.age(world().today),
			"nat": s.nationality,
			"note": {"text": "%.1f" % s.overall(), "sort": s.overall(),
				"color": UiKit.rating_color(s.overall())},
			"key": _key_attr(s),
			"salary": UiKit.money_cell(demand),
			"answer": _verdict_cell(s, demand, months),
			"_id": s.id,
		})
	var selected := int(state.get("selected", 0))
	main.add_child(sorted_table("staff.table", [
		{"key": "name", "label": "Nom", "expand": true},
		{"key": "age", "label": "Âge", "width": 46, "align": "right"},
		{"key": "nat", "label": "Pays", "width": 52},
		{"key": "note", "label": "Note", "width": 54, "align": "right"},
		{"key": "key", "label": "Point fort", "width": 150},
		{"key": "salary", "label": "Demande", "width": 100, "align": "right"},
		{"key": "answer", "label": "Réponse", "width": 130},
	], rows, {
		"row_clicked": func(i: int):
			state["selected"] = i
			refresh(),
		"selected": selected,
	}))

	var pick: Staff = pool[selected] if selected < pool.size() else pool[0]
	# Le panneau défile : la fiche est plus haute que l'écran, et le bouton
	# qui compte est tout en bas. Défilement latéral, jamais imbriqué dans
	# celui du tableau — voir l'invariant de tools/ui_check.gd.
	var panel := UiKit.scroll(_candidate_card(o, pick, months))
	# Verticalement seulement : une barre horizontale sous la fiche mangerait
	# de la hauteur pour rien.
	panel.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(panel)


## L'attribut qui compte le plus à son poste, dit en clair : c'est ce qu'on
## regarde avant la note globale quand on cherche un profil précis.
func _key_attr(s: Staff) -> String:
	var best := ""
	var best_v := -1
	for k in s.role_weights():
		if s.attr(k) > best_v:
			best_v = s.attr(k)
			best = str(k)
	return "%s %d" % [Staff.ATTR_LABELS.get(best, best), best_v]


func _verdict_cell(s: Staff, salary: int, months: int) -> Dictionary:
	var text: String = game().staff_verdict(s.id, salary, months)
	var color := UiKit.TEXT_DIM
	if text.begins_with("Signera"):
		color = UiKit.GOOD
	elif text.begins_with("Intéressé"):
		color = UiKit.TEXT
	elif text.begins_with("Refusera") or text.begins_with("A décliné"):
		color = UiKit.BAD
	elif text.begins_with("Peu"):
		color = UiKit.WARN
	return {"text": text, "color": color, "sort": text}


func _candidate_card(o: Organization, s: Staff, months: int) -> Control:
	# UiKit.card() renvoie un Card (panel + body), pas un Control.
	var state := ui("staff.market")
	var demand: int = game().staff_demand(s.id)
	var salary := int(state.get("salary", demand))
	# Une offre chiffrée pour quelqu'un d'autre n'a aucun sens : dès qu'on
	# change de candidat, on repart de sa demande.
	if str(state.get("salary_for", "")) != s.id:
		salary = demand
		state["salary"] = salary
		state["salary_for"] = s.id

	var card := UiKit.card("%s, %d ans" % [s.display_name(), s.age(world().today)])
	card.body.add_child(UiKit.subtitle("%s — %s"
		% [s.role_label(), s.nationality]))
	card.body.add_child(UiKit.kv("Note globale", "%.1f / 20" % s.overall(), 130))
	card.body.add_child(UiKit.kv("Réputation", str(s.reputation), 130))
	card.body.add_child(UiKit.separator())

	# Sur 20, comme partout ailleurs dans le jeu : un attribut de staff et un
	# attribut de joueur se lisent sur la même échelle.
	for k in Staff.ATTR_KEYS:
		card.body.add_child(UiKit.bar_row(
			str(Staff.ATTR_LABELS.get(k, k)), float(s.attr(k)),
			UiKit.attr_color(s.attr(k)), 20.0, 130))
	card.body.add_child(UiKit.separator())

	card.body.add_child(UiKit.kv("Demande", "%s / an" % Money.fmt(demand), 130))
	card.body.add_child(_salary_row(s, salary, demand))
	card.body.add_child(_months_row(months))
	card.body.add_child(UiKit.kv("Commission d'agent",
		Money.fmt(StaffSystem.agent_fee(world(), o, salary)), 130))
	card.body.add_child(UiKit.kv("Réponse probable",
		game().staff_verdict(s.id, salary, months), 130))

	var offer := UiKit.primary("Proposer le contrat", func():
		var out: Dictionary = game().hire_staff(s.id, salary, months)
		state["message"] = str(out.get("reason", ""))
		if bool(out.get("ok", false)):
			state["message"] = "%s rejoint la structure." % s.display_name()
		state.erase("salary_for")
		refresh())
	offer.disabled = o.ledger.cash < StaffSystem.agent_fee(world(), o, salary)
	card.body.add_child(offer)
	card.body.add_child(UiKit.caption(
		"Un refus ferme la porte trois semaines."))
	return card.panel


func _salary_row(s: Staff, salary: int, demand: int) -> Control:
	var state := ui("staff.market")
	var h := UiKit.hbox(4)
	h.add_child(UiKit.label("Offre", UiKit.FS_BODY_L, UiKit.TEXT_DIM))
	h.add_child(UiKit.spacer())
	for step in [-Money.from_units(5_000.0), -Money.from_units(1_000.0),
			Money.from_units(1_000.0), Money.from_units(5_000.0)]:
		var d: int = step
		var b := UiKit.ghost("%+d k" % int(float(d) / 100_000.0), func():
			state["salary"] = maxi(salary + d, Money.from_units(1_000.0))
			refresh())
		b.custom_minimum_size = Vector2(42, 0)
		h.add_child(b)
	var color := UiKit.GOOD if salary >= demand else UiKit.WARN
	h.add_child(UiKit.label(Money.fmt_short(salary), UiKit.FS_BODY_L, color))
	return h


func _months_row(months: int) -> Control:
	var state := ui("staff.market")
	var h := UiKit.hbox(4)
	h.add_child(UiKit.label("Durée", UiKit.FS_BODY_L, UiKit.TEXT_DIM))
	h.add_child(UiKit.spacer())
	for m_v in MONTH_CHOICES:
		var m: int = m_v
		var b := UiKit.ghost("%d m" % m, func():
			state["months"] = m
			refresh())
		b.add_theme_color_override("font_color",
			UiKit.ACCENT if m == months else UiKit.TEXT_DIM)
		h.add_child(b)
	return h
