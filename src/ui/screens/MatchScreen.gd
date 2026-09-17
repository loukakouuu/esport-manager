extends Screen

## Compte rendu de match : le veto, le score map par map, le déroulé des
## rounds et les statistiques individuelles.
##
## C'est l'équivalent du « match engine » de Football Manager en version
## texte : on ne montre pas le jeu, on montre pourquoi il a basculé.

var _map_index := 0


func build() -> void:
	var w := world()
	var res: MatchResult = game().last_player_result
	var f: Fixture = game().last_player_fixture
	if res == null:
		add_child(UiKit.subtitle("Aucun match à afficher."))
		return

	var home := _org_name(w, res.home_id)
	var away := _org_name(w, res.away_id)
	var comp := w.competition(res.competition_id)

	add_child(UiKit.title("%s  %d - %d  %s"
		% [home, res.home_score, res.away_score, away]))
	# La DISCIPLINE dans le sous-titre : une maison à deux sections joue deux
	# calendriers, et « dernier match » ne dit pas lequel.
	var home_roster := w.roster(res.home_id)
	var game_id := home_roster.game_id if home_roster != null else ""
	add_child(UiKit.subtitle("%s · %s · %s · %s"
		% [GameCatalog.label(game_id), comp.name if comp != null else "",
			f.round_label if f != null else "",
			GameDate.format_long(res.day)]))
	add_child(UiKit.label(res.headline, 15, UiKit.ACCENT))

	if not res.veto_log.is_empty():
		add_child(UiKit.label("Veto : " + " · ".join(res.veto_log), 12,
			UiKit.TEXT_DIM))

	if res.maps.is_empty():
		add_child(UiKit.subtitle("Aucune carte jouée (forfait)."))
		return

	var tabs := UiKit.hbox(6)
	for i in res.maps.size():
		var m0: MapResult = res.maps[i]
		var idx := i
		var b := UiKit.button("%s %d-%d"
			% [m0.map_name, m0.home_rounds, m0.away_rounds], func():
			_map_index = idx
			refresh())
		if i == _map_index:
			b.add_theme_color_override("font_color", UiKit.ACCENT)
		tabs.add_child(b)
	add_child(tabs)

	var m: MapResult = res.maps[mini(_map_index, res.maps.size() - 1)]
	var body := UiKit.hbox(16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	body.add_child(_rounds_panel(m))
	body.add_child(_stats_panel(w, res))


## Camp tenu par l'équipe à domicile au round N. Stocké tel quel par le
## simulateur, qui emploie le vocabulaire de sa discipline : « atk » et « def »
## en Valorant, « T » et « CT » en Counter-Strike.
func _side_badge(r: Dictionary) -> Control:
	var side := str(r.get("home_side", ""))
	var label := UiKit.label(side.to_upper(), 11,
		UiKit.WARN if side == "atk" or side == "T" else UiKit.INFO)
	label.custom_minimum_size = Vector2(28, 0)
	return label


func _rounds_panel(m: MapResult) -> Control:
	var panel := UiKit.panel(12)
	panel.custom_minimum_size = Vector2(560, 0)
	var v := UiKit.vbox(6)
	panel.add_child(v)
	v.add_child(UiKit.label("%s — %d-%d%s"
		% [m.map_name, m.home_rounds, m.away_rounds,
			"  (prolongation)" if m.overtime else ""], 15, UiKit.ACCENT))
	if m.rounds.is_empty():
		v.add_child(UiKit.subtitle(
			"Le détail round par round n'est conservé que pour vos matchs."))
		return panel

	var list := UiKit.vbox(2)
	for r_v in m.rounds:
		var r: Dictionary = r_v
		var home_won := str(r["winner"]) == "home"
		var line := UiKit.hbox(8)
		var n := UiKit.label("R%d" % int(r["n"]), 12, UiKit.TEXT_DIM)
		n.custom_minimum_size = Vector2(34, 0)
		line.add_child(n)
		var sc := UiKit.label(str(r["score"]), 12,
			UiKit.GOOD if home_won else UiKit.BAD)
		sc.custom_minimum_size = Vector2(46, 0)
		line.add_child(sc)
		line.add_child(_side_badge(r))
		var badge := UiKit.label(_type_label(str(r["type"])), 11,
			_type_color(str(r["type"])))
		badge.custom_minimum_size = Vector2(60, 0)
		line.add_child(badge)
		# Le commentaire prend la place restante et passe à la ligne : sinon la
		# colonne déborde et fait apparaître une barre de défilement horizontale.
		var comment := UiKit.label(str(r.get("text", "")), 12)
		comment.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		comment.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(comment)
		list.add_child(line)
	v.add_child(UiKit.scroll(list))
	return panel


func _type_label(t: String) -> String:
	match t:
		"pistol": return "PISTOL"
		"eco": return "ECO"
		"force": return "FORCE"
		"bonus": return "BONUS"
		"full": return "FULL"
	return t.to_upper()


func _type_color(t: String) -> Color:
	match t:
		"pistol": return UiKit.ACCENT
		"eco": return UiKit.WARN
		"force": return UiKit.WARN
		"bonus": return UiKit.GOOD
	return UiKit.TEXT_DIM


func _org_name(w: World, roster_id: String) -> String:
	var r := w.roster(roster_id)
	var o := w.org(r.org_id) if r != null else null
	return o.name if o != null else "?"


## Les colonnes appartiennent à la DISCIPLINE : ACS en Valorant, ADR et KAST en
## Counter-Strike. Cet écran ne connaît que « Joueur » et « K/D/A », le reste
## est déclaré par le module (`GameModule.stat_columns`).
func _stats_panel(w: World, res: MatchResult) -> Control:
	var panel := UiKit.panel(12)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UiKit.vbox(8)
	panel.add_child(v)
	v.add_child(UiKit.label("Statistiques de la série", 15, UiKit.ACCENT))

	var home := w.roster(res.home_id)
	var module := w.module_for(home.game_id if home != null else "valorant")
	# La note et le triplet K/D/A ont leur propre mise en forme : on retire de
	# la liste du module les colonnes qu'on dessine à la main.
	var extra: Array = []
	for c_v in module.stat_columns():
		var c: Dictionary = c_v
		if ["rating", "kills", "deaths", "assists"].has(str(c["key"])):
			continue
		extra.append(c)

	var columns: Array = [
		{"label": "Joueur", "width": 140},
		{"label": "Note", "width": 55, "align": "right"},
		{"label": "K/D/A", "width": 90, "align": "center"},
	]
	for c_v in extra:
		var c: Dictionary = c_v
		columns.append({"label": str(c["label"]), "width": 52, "align": "right"})

	var sides: Array[String] = [res.home_id, res.away_id]
	for rid in sides:
		v.add_child(UiKit.label(_org_name(w, rid), 14))
		var ids: Array = []
		for pid in res.player_stats:
			if str((res.player_stats[pid] as Dictionary).get("team", "")) == rid:
				ids.append(pid)
		ids.sort_custom(func(a, b):
			return float((res.player_stats[a] as Dictionary).get("rating", 0.0)) \
				> float((res.player_stats[b] as Dictionary).get("rating", 0.0)))
		var rows: Array = []
		for pid in ids:
			var st: Dictionary = res.player_stats[pid]
			var p := w.player(str(pid))
			var name := p.display_name() if p != null else "?"
			if str(pid) == res.mvp_id:
				name += "  *MVP"
			var row: Array = [
				name,
				{"text": "%.2f" % float(st["rating"]),
					"color": UiKit.rating_color(float(st["rating"]))},
				"%d / %d / %d" % [int(st["kills"]), int(st["deaths"]),
					int(st["assists"])],
			]
			for c_v in extra:
				var c: Dictionary = c_v
				row.append(String.num(float(st.get(str(c["key"]), 0.0)),
					int(c.get("digits", 0))))
			rows.append(row)
		v.add_child(UiKit.table(columns, rows))
	return panel
