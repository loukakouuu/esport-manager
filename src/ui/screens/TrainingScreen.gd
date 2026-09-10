extends Screen

## Programme d'entraînement de la semaine.
##
## Dix créneaux à répartir entre cinq natures de travail. Le point de cet
## écran est qu'il n'existe PAS de réglage optimal : tout ce qui part en
## scrims ne part pas en récupération, et une équipe qui s'entraîne à fond en
## novembre n'a plus de jambes en mars. On montre donc les conséquences
## (charge, fatigue projetée, ce qui progresse) plutôt qu'un score global.


func build() -> void:
	var w := world()
	var r: Roster = game().my_roster()
	if r == null:
		add_child(UiKit.empty_state("Aucun roster."))
		return
	var module := w.module_for(r.game_id)
	var plan := TrainingSystem.plan_of(r)
	var total := TrainingSystem.plan_total(plan)

	add_child(page_header("Entraînement",
		"Semaine type — %d créneaux répartis" % total, [
			UiKit.button("Programme équilibré", func():
				game().set_training_plan(TrainingSystem.DEFAULT_PLAN)),
			UiKit.button("Avant un gros match", func():
				game().set_training_plan({"scrim": 5, "aim": 1, "theory": 3,
					"physical": 1, "rest": 0})),
			UiKit.button("Semaine de décharge", func():
				game().set_training_plan({"scrim": 2, "aim": 0, "theory": 2,
					"physical": 2, "rest": 4})),
		]))

	var parts := split(400)
	var main: VBoxContainer = parts[0]
	var side: VBoxContainer = parts[1]

	main.add_child(_plan_card(r, plan, total))
	main.add_child(_effect_card(w, r, plan, module))
	side.add_child(_load_card(w, r, plan))
	side.add_child(_staff_card(w, r))


# ============================================================================
# Répartition des créneaux
# ============================================================================

func _plan_card(r: Roster, plan: Dictionary, total: int) -> Control:
	var card := UiKit.card("Répartition hebdomadaire", 8, 14)
	if total != TrainingSystem.UNITS_PER_WEEK:
		card.body.add_child(UiKit.label(
			"%d créneaux répartis sur %d : la semaine n'est pas complète."
			% [total, TrainingSystem.UNITS_PER_WEEK], UiKit.FS_BODY_L,
			UiKit.WARN))

	for unit in TrainingSystem.UNITS:
		card.body.add_child(_unit_row(r, plan, str(unit)))
	card.body.add_child(UiKit.separator())
	card.body.add_child(_distribution_bar(plan))
	return card.panel


func _unit_row(r: Roster, plan: Dictionary, unit: String) -> Control:
	var value := int(plan.get(unit, 0))
	var row := UiKit.hbox(10)

	var head := UiKit.vbox(0)
	head.custom_minimum_size = Vector2(190, 0)
	head.add_child(UiKit.label(TrainingSystem.unit_label(unit),
		UiKit.FS_BODY_L, UiKit.TEXT))
	head.add_child(UiKit.label(TrainingSystem.unit_hint(unit), UiKit.FS_SMALL,
		UiKit.TEXT_FAINT))
	row.add_child(head)

	var minus := UiKit.button("−", func():
		game().set_training_unit(unit, value - 1))
	minus.custom_minimum_size = Vector2(30, 28)
	minus.disabled = value <= 0
	row.add_child(minus)

	var count := UiKit.label(str(value), UiKit.FS_LEAD,
		UiKit.ACCENT if value > 0 else UiKit.TEXT_FAINT, true)
	count.custom_minimum_size = Vector2(26, 0)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(count)

	var plus := UiKit.button("+", func():
		game().set_training_unit(unit, value + 1))
	plus.custom_minimum_size = Vector2(30, 28)
	plus.disabled = value >= TrainingSystem.UNITS_PER_WEEK
	row.add_child(plus)

	row.add_child(UiKit.meter(float(value), float(TrainingSystem.UNITS_PER_WEEK),
		160, _unit_color(unit)))
	return row


## Une seule barre empilée dit d'un coup à quoi ressemble la semaine.
func _distribution_bar(plan: Dictionary) -> Control:
	var total := maxf(float(TrainingSystem.plan_total(plan)), 1.0)
	var bar := UiKit.hbox(2)
	bar.custom_minimum_size = Vector2(0, 16)
	for unit in TrainingSystem.UNITS:
		var share := float(plan.get(unit, 0)) / total
		if share <= 0.0:
			continue
		var seg := PanelContainer.new()
		seg.add_theme_stylebox_override("panel",
			UiKit.box(_unit_color(str(unit)), 3))
		seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.size_flags_stretch_ratio = share
		seg.tooltip_text = "%s : %d créneaux" % [
			TrainingSystem.unit_label(str(unit)), int(plan.get(unit, 0))]
		bar.add_child(seg)
	return bar


func _unit_color(unit: String) -> Color:
	match unit:
		TrainingSystem.SCRIM: return UiKit.ACCENT
		TrainingSystem.AIM: return Color("#e8a33d")
		TrainingSystem.THEORY: return UiKit.INFO
		TrainingSystem.PHYSICAL: return Color("#46c46a")
	return Color("#8a93a6")


# ============================================================================
# Conséquences
# ============================================================================

func _load_card(w: World, r: Roster, plan: Dictionary) -> Control:
	var load := TrainingSystem.plan_load(plan)
	var card := UiKit.card("Charge de travail", 7, 14)
	card.body.add_child(UiKit.label("%.0f %%" % (load * 100.0), UiKit.FS_H1,
		_load_color(load), true))
	card.body.add_child(UiKit.wrap(TrainingSystem.plan_summary(plan),
		UiKit.FS_BODY_L, _load_color(load)))
	card.body.add_child(UiKit.separator())

	# Moyennes de l'effectif : c'est là qu'on voit qu'on tire trop sur la corde.
	var squad := w.players_of(r.id)
	var fatigue := 0.0
	var burnout := 0.0
	var sharp := 0.0
	for p_v in squad:
		var p: Player = p_v
		fatigue += p.fatigue
		burnout += p.burnout
		sharp += p.sharpness
	var n := maxf(float(squad.size()), 1.0)
	card.body.add_child(UiKit.bar_row("Fatigue moyenne", fatigue / n,
		UiKit.BAD if fatigue / n > 60.0 else UiKit.WARN, 100.0, 140))
	card.body.add_child(UiKit.bar_row("Usure mentale", burnout / n,
		UiKit.BAD if burnout / n > 35.0 else UiKit.WARN, 100.0, 140))
	card.body.add_child(UiKit.bar_row("Netteté", sharp / n, UiKit.GOOD,
		100.0, 140))
	card.body.add_child(UiKit.bar_row("Cohésion", r.chemistry,
		UiKit.GOOD if r.chemistry > 65.0 else UiKit.WARN, 100.0, 140))

	if fatigue / n > 62.0 and load > 1.0:
		card.body.add_child(UiKit.label(
			"L'effectif est déjà entamé : réduisez les scrims ou ajoutez du repos.",
			UiKit.FS_BODY, UiKit.BAD))
	return card.panel


func _load_color(load: float) -> Color:
	if load >= 1.3:
		return UiKit.BAD
	if load >= 1.05:
		return UiKit.WARN
	if load < 0.6:
		return UiKit.INFO
	return UiKit.GOOD


## Ce que le programme fait progresser, exprimé en attributs et non en jargon.
func _effect_card(w: World, r: Roster, plan: Dictionary,
		module: GameModule) -> Control:
	var card := UiKit.card("Ce que la semaine développe", 6, 14)
	var weights: Dictionary = {}
	var total := maxf(float(TrainingSystem.plan_total(plan)), 1.0)
	for unit in TrainingSystem.UNITS:
		var share := float(plan.get(unit, 0)) / total
		if share <= 0.0:
			continue
		for key in TrainingSystem.FOCUS_GROUPS.get(unit, []):
			weights[key] = float(weights.get(key, 0.0)) + share

	if weights.is_empty():
		card.body.add_child(UiKit.label(
			"Aucun travail technique programmé cette semaine.", UiKit.FS_BODY_L,
			UiKit.TEXT_DIM))
		return card.panel

	var keys := weights.keys()
	keys.sort_custom(func(a, b): return float(weights[a]) > float(weights[b]))
	var top := maxf(float(weights[keys[0]]), 0.001)
	var grid := UiKit.hbox(24)
	card.body.add_child(grid)
	var col := UiKit.vbox(3)
	grid.add_child(col)
	for i in keys.size():
		if i > 0 and i % 8 == 0:
			col = UiKit.vbox(3)
			grid.add_child(col)
		var k := str(keys[i])
		var line := UiKit.hbox(8)
		var l := UiKit.label(module.attribute_label(k), UiKit.FS_BODY)
		l.custom_minimum_size = Vector2(170, 0)
		line.add_child(l)
		line.add_child(UiKit.meter(float(weights[k]) / top * 100.0, 100.0, 90,
			UiKit.ACCENT))
		col.add_child(line)

	card.body.add_child(UiKit.label(
		"Le travail individuel de chaque joueur (fiche joueur → Développement) "
		+ "s'ajoute à ce socle collectif.", UiKit.FS_SMALL, UiKit.TEXT_FAINT))
	return card.panel


func _staff_card(w: World, r: Roster) -> Control:
	var card := UiKit.card("Encadrement", 5, 14)
	var coach := w.staffer(r.head_coach_id)
	if coach == null:
		card.body.add_child(UiKit.label("Aucun entraîneur principal.",
			UiKit.FS_BODY_L, UiKit.BAD))
	else:
		card.body.add_child(UiKit.kv("Entraîneur", coach.display_name(), 130))
		card.body.add_child(UiKit.bar_row("Coaching mécanique",
			float(coach.attr(Staff.MECHANICAL_COACHING)) * 5.0, UiKit.GOOD,
			100.0, 130))
		card.body.add_child(UiKit.bar_row("Gestion humaine",
			float(coach.attr(Staff.MAN_MANAGEMENT)) * 5.0, UiKit.GOOD,
			100.0, 130))
		card.body.add_child(UiKit.bar_row("Formation des jeunes",
			float(coach.attr(Staff.YOUTH_DEVELOPMENT)) * 5.0, UiKit.GOOD,
			100.0, 130))
	card.body.add_child(UiKit.separator())
	var o: Organization = game().my_org()
	if o != null:
		card.body.add_child(UiKit.bar_row("Salle d'entraînement",
			o.facility_effect(Facilities.Kind.TRAINING_ROOM) * 100.0 - 50.0,
			UiKit.INFO, 100.0, 130))
		card.body.add_child(UiKit.bar_row("Bien-être",
			o.facility_effect(Facilities.Kind.WELLNESS) * 100.0 - 50.0,
			UiKit.INFO, 100.0, 130))
		card.body.add_child(UiKit.ghost("Voir les infrastructures",
			func(): navigate("facilities")))
	return card.panel
