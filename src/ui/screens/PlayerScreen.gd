extends Screen

## Fiche joueur : identité, attributs estimés, contrat, statistiques.

var player_id: String = ""


func build() -> void:
	var w := world()
	var p := w.player(player_id)
	if p == null:
		add_child(UiKit.subtitle("Joueur introuvable."))
		return
	var module := w.module_for(p.game_id)
	var org := w.org(p.org_id)

	var head := UiKit.hbox(16)
	var ident := UiKit.vbox(2)
	ident.add_child(UiKit.label(p.display_name(), 24))
	ident.add_child(UiKit.subtitle("%s · %s · %d ans · %s"
		% [p.full_name(), p.nationality, p.age(w.today),
			module.role_label(p.primary_role) + (" · IGL" if p.is_igl else "")]))
	ident.add_child(UiKit.subtitle(org.name if org != null else "Agent libre"))
	head.add_child(ident)
	head.add_child(UiKit.spacer())

	var eval := UiKit.vbox(2)
	eval.add_child(UiKit.label("Niveau estimé : %s"
		% ScoutingSystem.ability_text(w, p), 15))
	eval.add_child(UiKit.label("Potentiel : %s"
		% UiKit.stars(ScoutingSystem.potential_value(w, p)), 15, UiKit.ACCENT))
	eval.add_child(UiKit.subtitle(ScoutingSystem.confidence_text(w, p)))
	head.add_child(eval)
	add_child(head)

	if not p.traits.is_empty():
		var traits := UiKit.hbox(6)
		traits.add_child(UiKit.label("Traits :", 13, UiKit.TEXT_DIM))
		for t in p.traits:
			traits.add_child(UiKit.label(PlayerFactory.trait_label(t), 13, UiKit.WARN))
		add_child(traits)

	var body := UiKit.hbox(16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	body.add_child(_attributes_panel(w, p, module))

	var right := UiKit.vbox(12)
	right.custom_minimum_size = Vector2(380, 0)
	body.add_child(right)
	right.add_child(_condition_panel(w, p))
	right.add_child(_contract_panel(w, p))
	right.add_child(_stats_panel(w, p, module))

	add_child(UiKit.button("Retour à l'effectif", func(): navigate("squad")))


func _attributes_panel(w: World, p: Player, module: GameModule) -> Control:
	var panel := UiKit.panel(12)
	var v := UiKit.vbox(10)
	panel.add_child(v)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UiKit.label("Attributs", 15, UiKit.ACCENT))

	var groups: Dictionary = module.attribute_groups()
	var cols := UiKit.hbox(20)
	v.add_child(cols)
	var i := 0
	var col := UiKit.vbox(10)
	cols.add_child(col)
	for group_name in groups:
		if i == 2:
			col = UiKit.vbox(10)
			cols.add_child(col)
		i += 1
		col.add_child(UiKit.label(str(group_name), 13, UiKit.TEXT_DIM))
		for key in groups[group_name]:
			var row := UiKit.hbox(8)
			var l := UiKit.label(module.attribute_label(str(key)), 13)
			l.custom_minimum_size = Vector2(170, 0)
			row.add_child(l)
			var est := ScoutingSystem.estimated_attr(w, p, str(key))
			row.add_child(UiKit.meter(float(est), 20.0, 70,
				Attributes.color_for(est)))
			var val := UiKit.label(ScoutingSystem.attr_text(w, p, str(key)), 13,
				Attributes.color_for(est))
			val.custom_minimum_size = Vector2(52, 0)
			val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			row.add_child(val)
			col.add_child(row)
	return panel


func _condition_panel(w: World, p: Player) -> Control:
	var panel := UiKit.panel(12)
	var v := UiKit.vbox(6)
	panel.add_child(v)
	v.add_child(UiKit.label("Condition", 15, UiKit.ACCENT))
	v.add_child(_bar("Forme", p.form, UiKit.GOOD))
	v.add_child(_bar("Moral", p.morale, UiKit.GOOD))
	v.add_child(_bar("Netteté", p.sharpness, UiKit.GOOD))
	v.add_child(_bar("Fatigue", p.fatigue, UiKit.WARN))
	v.add_child(_bar("Usure mentale", p.burnout, UiKit.BAD))
	v.add_child(_bar("Satisfaction", p.happiness, UiKit.GOOD))
	if p.is_injured(w.today):
		v.add_child(UiKit.label("Blessé : %s (retour le %s)"
			% [p.injury_label, GameDate.format_long(p.injured_until)], 13, UiKit.BAD))
	return panel


func _bar(name: String, value: float, color: Color) -> Control:
	var h := UiKit.hbox(8)
	var l := UiKit.label(name, 13, UiKit.TEXT_DIM)
	l.custom_minimum_size = Vector2(120, 0)
	h.add_child(l)
	h.add_child(UiKit.meter(value, 100.0, 150, color))
	h.add_child(UiKit.label("%.0f" % value, 13))
	return h


func _contract_panel(w: World, p: Player) -> Control:
	var panel := UiKit.panel(12)
	var v := UiKit.vbox(6)
	panel.add_child(v)
	v.add_child(UiKit.label("Contrat", 15, UiKit.ACCENT))
	if p.contract == null:
		v.add_child(UiKit.label("Agent libre", 13, UiKit.GOOD))
		v.add_child(UiKit.label("Demande salariale estimée : %s / an"
			% Money.fmt(ContractSystem.salary_demand(w, p, game().my_org())), 13))
	else:
		var c := p.contract
		v.add_child(_kv("Salaire", "%s / an" % Money.fmt(c.salary_yearly)))
		v.add_child(_kv("Échéance", "%s (%s)"
			% [GameDate.format_long(c.end_day),
				GameDate.format_duration_days(c.days_remaining(w.today))]))
		v.add_child(_kv("Clause de rachat", Money.fmt(c.buyout)))
		v.add_child(_kv("Part des gains", "%.0f %%" % c.prize_share_pct))
	v.add_child(_kv("Valeur estimée", Money.fmt(p.market_value)))
	v.add_child(_kv("Réputation", str(p.reputation)))

	var org: Organization = game().my_org()
	if org != null and p.org_id == org.id:
		v.add_child(UiKit.button("Libérer le joueur", func():
			game().release_player(p.id)
			navigate("squad")))
	elif org != null:
		var salary := ContractSystem.salary_demand(w, p, org)
		v.add_child(UiKit.button("Proposer %s / an sur 2 ans"
			% Money.fmt_short(salary), func():
			if game().offer_contract(p.id, salary, 24,
					Contract.SquadRole.STARTER):
				navigate("squad")))
	return panel


func _stats_panel(w: World, p: Player, module: GameModule) -> Control:
	var panel := UiKit.panel(12)
	var v := UiKit.vbox(6)
	panel.add_child(v)
	v.add_child(UiKit.label("Statistiques de la saison", 15, UiKit.ACCENT))
	var st: Dictionary = p.season_stats
	if int(st.get("series", 0)) == 0:
		v.add_child(UiKit.subtitle("Aucun match joué cette saison."))
		return panel
	v.add_child(_kv("Séries jouées", str(int(st.get("series", 0)))))
	v.add_child(_kv("Note moyenne", "%.2f" % float(st.get("rating", 0.0))))
	v.add_child(_kv("ACS", "%.0f" % float(st.get("acs", 0.0))))
	v.add_child(_kv("K / D / A", "%d / %d / %d"
		% [int(st.get("kills", 0)), int(st.get("deaths", 0)),
			int(st.get("assists", 0))]))
	v.add_child(_kv("Ouvertures", "%d (perdues %d)"
		% [int(st.get("first_kills", 0)), int(st.get("first_deaths", 0))]))
	v.add_child(_kv("Clutchs", "%d / %d"
		% [int(st.get("clutches", 0)), int(st.get("clutch_attempts", 0))]))
	v.add_child(_kv("Aces", str(int(st.get("aces", 0)))))
	return panel


func _kv(key: String, value: String) -> Control:
	var h := UiKit.hbox(8)
	var k := UiKit.label(key, 13, UiKit.TEXT_DIM)
	k.custom_minimum_size = Vector2(150, 0)
	h.add_child(k)
	h.add_child(UiKit.label(value, 13))
	return h
