extends Screen

## Compétition : classements, arbres, résultats. Le joueur doit pouvoir suivre
## sa ligue mais aussi ce qui se passe ailleurs dans le monde.

var comp_id: String = ""


func build() -> void:
	var w := world()
	var r: Roster = game().my_roster()
	if comp_id == "" and r != null and not r.competition_ids.is_empty():
		comp_id = r.competition_ids[0]

	var head := UiKit.hbox(6)
	head.add_child(UiKit.title("Compétitions"))
	add_child(head)

	var picker := UiKit.hbox(6)
	var comps: Array[Competition] = []
	for cid in w.competitions:
		var c: Competition = w.competitions[cid]
		if c.season_year == w.season_year:
			comps.append(c)
	comps.sort_custom(func(a: Competition, b: Competition):
		if a.tier != b.tier:
			return a.tier < b.tier
		return a.name < b.name)
	for c in comps:
		var cid := c.id
		var b := UiKit.button(c.short_name, func():
			comp_id = cid
			refresh())
		if cid == comp_id:
			b.add_theme_color_override("font_color", UiKit.ACCENT)
		picker.add_child(b)
	add_child(UiKit.scroll_h(picker))

	var comp := w.competition(comp_id)
	if comp == null:
		add_child(UiKit.subtitle("Sélectionnez une compétition."))
		return

	add_child(UiKit.label("%s — %s · dotation %s"
		% [comp.name, comp.kind_label(), Money.fmt(comp.prize_pool)], 15))
	if comp.stipend_yearly > 0:
		add_child(UiKit.subtitle("Ligue partenaire : subvention de %s / an par équipe."
			% Money.fmt(comp.stipend_yearly)))

	if not comp.final_ranking.is_empty():
		add_child(_final_ranking(w, comp))
		return
	var stage := comp.active_stage()
	if stage == null:
		add_child(UiKit.subtitle("Compétition non démarrée."))
		return
	add_child(UiKit.label("Phase en cours : %s (%s)"
		% [stage.name, stage.format_label()], 14, UiKit.TEXT_DIM))
	if stage.is_bracket():
		add_child(UiKit.scroll(_bracket(w, comp, stage)))
	else:
		add_child(UiKit.scroll(_standings(w, stage)))


func _standings(w: World, stage: Stage) -> Control:
	var ranking := CompetitionEngine.compute_ranking(w, stage)
	var columns := [
		{"label": "#", "width": 30, "align": "right"},
		{"label": "Équipe", "width": 190},
		{"label": "Poule", "width": 80},
		{"label": "V", "width": 40, "align": "right"},
		{"label": "D", "width": 40, "align": "right"},
		{"label": "Maps", "width": 70, "align": "right"},
		{"label": "Rounds", "width": 80, "align": "right"},
	]
	var rows: Array = []
	var my: Roster = game().my_roster()
	for i in ranking.size():
		var rid := ranking[i]
		var st := stage.standing_for(rid)
		var r := w.roster(rid)
		var o := w.org(r.org_id) if r != null else null
		var name := o.name if o != null else "?"
		var color := UiKit.ACCENT if (my != null and rid == my.id) else UiKit.TEXT
		var qualified := i < stage.qualifiers
		rows.append([
			{"text": str(i + 1), "color": UiKit.GOOD if qualified else UiKit.TEXT_DIM},
			{"text": name, "color": color},
			str(st.get("group", "")),
			str(int(st["w"])), str(int(st["l"])),
			"%d-%d" % [int(st["map_w"]), int(st["map_l"])],
			"%+d" % (int(st["round_w"]) - int(st["round_l"])),
		])
	var v := UiKit.vbox(6)
	v.add_child(UiKit.table(columns, rows))
	v.add_child(UiKit.subtitle("Les %d premiers se qualifient pour la phase suivante."
		% stage.qualifiers))
	return v


func _bracket(w: World, comp: Competition, stage: Stage) -> Control:
	var v := UiKit.vbox(10)
	var by_round := {}
	for fid in stage.fixture_ids:
		var f: Fixture = w.fixtures[fid]
		if not by_round.has(f.round_index):
			by_round[f.round_index] = []
		(by_round[f.round_index] as Array).append(f)
	var keys := by_round.keys()
	keys.sort()
	for k in keys:
		var fixtures: Array = by_round[k]
		v.add_child(UiKit.label(str((fixtures[0] as Fixture).round_label), 14,
			UiKit.ACCENT))
		var rows: Array = []
		for f_v in fixtures:
			var f: Fixture = f_v
			rows.append([
				GameDate.format_day_month(f.day),
				_team_name(w, f.home_id),
				_score_cell(f, true),
				_score_cell(f, false),
				_team_name(w, f.away_id),
				"BO%d" % f.best_of,
			])
		v.add_child(UiKit.table([
			{"label": "", "width": 70},
			{"label": "", "width": 170, "align": "right"},
			{"label": "", "width": 25, "align": "center"},
			{"label": "", "width": 25, "align": "center"},
			{"label": "", "width": 170},
			{"label": "", "width": 50},
		], rows))
	return v


func _team_name(w: World, rid: String) -> Dictionary:
	if rid == "":
		return {"text": "—", "color": UiKit.TEXT_DIM}
	var r := w.roster(rid)
	var o := w.org(r.org_id) if r != null else null
	var my: Roster = game().my_roster()
	return {"text": o.name if o != null else "?",
		"color": UiKit.ACCENT if (my != null and rid == my.id) else UiKit.TEXT}


func _score_cell(f: Fixture, home: bool) -> Dictionary:
	if not f.played or f.result == null:
		return {"text": "-", "color": UiKit.TEXT_DIM}
	var s: int = f.result.home_score if home else f.result.away_score
	var won := (f.result.winner_id == f.home_id) == home
	return {"text": str(s), "color": UiKit.GOOD if won else UiKit.TEXT_DIM}


func _final_ranking(w: World, comp: Competition) -> Control:
	var v := UiKit.vbox(6)
	v.add_child(UiKit.label("Classement final", 15, UiKit.ACCENT))
	var rows: Array = []
	for i in comp.final_ranking.size():
		var r := w.roster(comp.final_ranking[i])
		var o := w.org(r.org_id) if r != null else null
		rows.append([
			str(i + 1),
			_team_name(w, comp.final_ranking[i]),
			Money.fmt(comp.prize_for_placement(i + 1)),
		])
	v.add_child(UiKit.table([
		{"label": "#", "width": 40, "align": "right"},
		{"label": "Équipe", "width": 220},
		{"label": "Gains", "width": 130, "align": "right"},
	], rows))
	return v
