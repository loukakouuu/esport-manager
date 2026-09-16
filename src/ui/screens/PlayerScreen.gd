extends Screen

## Fiche joueur — l'écran le plus consulté d'un jeu de gestion.
##
## Organisé en onglets parce qu'il y a trop à dire pour une page : on ne
## consulte pas les mêmes informations pour aligner une équipe, pour décider
## d'une prolongation ou pour comprendre pourquoi un joueur fait la tête.
##
## Tout ce qui vient des attributs passe par ScoutingSystem : même sur ses
## propres joueurs, on affiche l'estimation du staff, jamais la vérité.

var player_id: String = ""

const TABS := [
	["profile", "Profil"],
	["attributes", "Attributs"],
	["development", "Développement"],
	["roles", "Postes"],
	["contract", "Contrat & statut"],
	["locker", "Vestiaire"],
	["stats", "Statistiques"],
]


func build() -> void:
	var w := world()
	var p := w.player(player_id)
	if p == null:
		add_child(UiKit.empty_state("Joueur introuvable."))
		return
	var module := w.module_for(p.game_id)

	add_child(_identity_card(w, p, module))
	add_child(tab_bar("player", TABS, "profile"))

	var host := UiKit.vbox(12)
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(UiKit.scroll(host))

	match current_tab("player", "profile"):
		"attributes": _tab_attributes(host, w, p, module)
		"development": _tab_development(host, w, p, module)
		"roles": _tab_roles(host, w, p, module)
		"contract": _tab_contract(host, w, p)
		"locker": _tab_locker(host, w, p)
		"stats": _tab_stats(host, w, p, module)
		_: _tab_profile(host, w, p, module)


# ============================================================================
# Bandeau d'identité — visible quel que soit l'onglet
# ============================================================================

func _identity_card(w: World, p: Player, module: GameModule) -> Control:
	var org := w.org(p.org_id)
	# Le cartouche prend les couleurs du CLUB du joueur, pas une teinte tirée de
	# son identifiant : c'est ainsi qu'on lit une incrustation de diffusion — on
	# reconnaît la maison avant de lire le nom. Un agent libre n'en a pas, d'où
	# le repli sur l'accent du jeu.
	var tint := UiKit.org_color(org) if org != null else UiKit.ACCENT
	var panel := Banner.new(tint)
	panel.base = UiKit.BG_PANEL
	panel.spread = 0.38
	panel.pad(30, 13, 14, 13)
	var row := UiKit.hbox(16)
	panel.add_child(row)

	row.add_child(UiKit.crest(org.tag if org != null else p.display_name(),
		tint, 54))

	var ident := UiKit.vbox(2)
	ident.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var name_line := UiKit.hbox(8)
	name_line.add_child(UiKit.display(p.display_name().to_upper(), UiKit.FS_H1,
		UiKit.TEXT, 700, UiKit.TRACK_TITLE))
	if p.is_igl:
		name_line.add_child(UiKit.pill("IGL", UiKit.ACCENT, true))
	if p.wants_out:
		name_line.add_child(UiKit.pill("Veut partir", UiKit.BAD, true))
	if p.transfer_listed:
		name_line.add_child(UiKit.pill("Sur la liste", UiKit.WARN, true))
	ident.add_child(name_line)
	ident.add_child(UiKit.label("%s · %s · %d ans"
		% [p.full_name(), p.nationality, p.age(w.today)], UiKit.FS_BODY_L,
		UiKit.TEXT_DIM))
	ident.add_child(UiKit.label("%s · %s"
		% [module.role_label(p.primary_role),
			org.name if org != null else "Agent libre"], UiKit.FS_BODY_L))
	row.add_child(ident)
	row.add_child(UiKit.spacer())

	# Trois chiffres et rien d'autre : c'est ce qu'on veut voir en arrivant.
	# Les filets les séparent comme les cadrans de la barre haute — même
	# grammaire d'un bout à l'autre du jeu.
	row.add_child(UiKit.stat_block("Niveau estimé",
		ScoutingSystem.ability_text(w, p), UiKit.TEXT,
		ScoutingSystem.confidence_text(w, p)))
	row.add_child(UiKit.vrule(42))
	var pot := ScoutingSystem.potential_value(w, p)
	row.add_child(UiKit.stat_block("Potentiel", UiKit.stars(pot), UiKit.WARN,
		_trend_text(p)))
	row.add_child(UiKit.vrule(42))
	row.add_child(UiKit.stat_block("Valeur", Money.fmt_short(p.market_value),
		UiKit.TEXT, "Salaire %s / an" % Money.fmt_short(
			p.contract.salary_yearly if p.contract != null else 0)))
	return panel


func _trend_text(p: Player) -> String:
	var t := p.ca_trend(6)
	if t > 2:
		return "En progression (+%d sur 6 mois)" % t
	if t < -2:
		return "En baisse (%d sur 6 mois)" % t
	return "Stable sur 6 mois"


# ============================================================================
# Onglet Profil
# ============================================================================

func _tab_profile(host: VBoxContainer, w: World, p: Player,
		module: GameModule) -> void:
	var top := UiKit.hbox(14)
	host.add_child(top)

	# Rapport d'observation : la lecture humaine des attributs.
	var rep := ScoutingSystem.report(w, p)
	var c1 := UiKit.card("Rapport du staff", 8, 14)
	c1.panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c1.body.add_child(UiKit.wrap(str(rep["verdict"]), UiKit.FS_BODY_L))
	c1.body.add_child(UiKit.separator())
	c1.body.add_child(_bullets("Points forts", rep["strengths"], UiKit.GOOD))
	c1.body.add_child(_bullets("Points faibles", rep["weaknesses"], UiKit.BAD))
	c1.body.add_child(UiKit.separator())
	c1.body.add_child(UiKit.kv("Personnalité",
		UiKit.label(str(rep["personality"]), UiKit.FS_BODY_L,
			PersonalityCalc.color(p)), 120))
	c1.body.add_child(UiKit.wrap(PersonalityCalc.summary(p), UiKit.FS_BODY,
		UiKit.TEXT_DIM))
	if not p.traits.is_empty():
		var tr := UiKit.hbox(6)
		tr.add_child(UiKit.label("Traits", UiKit.FS_BODY_L, UiKit.TEXT_DIM))
		for t in p.traits:
			tr.add_child(UiKit.pill(PlayerFactory.trait_label(str(t)),
				UiKit.WARN, true))
		c1.body.add_child(tr)
	top.add_child(c1.panel)

	# Radar : la silhouette du joueur en un coup d'œil.
	var c2 := UiKit.card("Profil de jeu", 6, 14)
	c2.panel.custom_minimum_size = Vector2(300, 0)
	c2.body.add_child(_radar(w, p, module))
	top.add_child(c2.panel)

	var bottom := UiKit.hbox(14)
	host.add_child(bottom)
	bottom.add_child(_condition_card(w, p).panel)

	var c3 := UiKit.card("En un coup d'œil", 6, 14)
	c3.panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c3.body.add_child(UiKit.kv("Statut promis",
		UiKit.label(PlayingTime.label(p.promised_time), UiKit.FS_BODY_L,
			PlayingTime.color(p.promised_time)), 150))
	c3.body.add_child(UiKit.kv("Réputation", "%d / 10000" % p.reputation, 150))
	c3.body.add_child(UiKit.kv("Attrait public", "%d / 100" % p.fan_appeal, 150))
	c3.body.add_child(UiKit.kv("Influence vestiaire",
		"%.0f / 100" % p.influence, 150))
	c3.body.add_child(UiKit.kv("Travail individuel",
		module.attribute_label(p.training_focus) if p.training_focus != ""
			else "Confié au coach", 150))
	if not p.concerns.is_empty():
		c3.body.add_child(UiKit.separator())
		c3.body.add_child(UiKit.caption("Points de friction", UiKit.BAD))
		for c in p.concerns:
			c3.body.add_child(UiKit.label("• " + DynamicsSystem.grievance_label(
				str(c)), UiKit.FS_BODY_L, UiKit.BAD))
	bottom.add_child(c3.panel)


func _bullets(title_text: String, items, color: Color) -> Control:
	var v := UiKit.vbox(2)
	v.add_child(UiKit.caption(title_text))
	if (items as Array).is_empty():
		v.add_child(UiKit.label("Rien de saillant.", UiKit.FS_BODY,
			UiKit.TEXT_FAINT))
		return v
	for it in items:
		v.add_child(UiKit.label("• " + UiKit.sentence(str(it)), UiKit.FS_BODY_L,
			color))
	return v


## Radar agrégé par famille d'attributs : c'est la lecture, pas le détail.
func _radar(w: World, p: Player, module: GameModule) -> Control:
	var groups: Dictionary = module.attribute_groups()
	var labels: Array[String] = []
	var values: Array[float] = []
	for group_name in groups:
		labels.append(str(group_name))
		var total := 0.0
		var keys: Array = groups[group_name]
		for k in keys:
			total += float(ScoutingSystem.estimated_attr(w, p, str(k)))
		values.append(total / maxf(float(keys.size()), 1.0))
	var r := RadarChart.make(labels, values, UiKit.ACCENT, 20.0)
	r.custom_minimum_size = Vector2(270, 250)
	return r


func _condition_card(w: World, p: Player) -> UiKit.Card:
	var c := UiKit.card("Condition", 5, 14)
	c.panel.custom_minimum_size = Vector2(360, 0)
	c.body.add_child(UiKit.bar_row("Forme", p.form, _grade(p.form)))
	c.body.add_child(UiKit.bar_row("Moral", p.morale, _grade(p.morale)))
	c.body.add_child(UiKit.bar_row("Netteté compétitive", p.sharpness,
		_grade(p.sharpness)))
	c.body.add_child(UiKit.bar_row("Satisfaction", p.happiness,
		_grade(p.happiness)))
	c.body.add_child(UiKit.bar_row("Fatigue", p.fatigue,
		UiKit.BAD if p.fatigue > 65.0 else UiKit.WARN))
	c.body.add_child(UiKit.bar_row("Usure mentale", p.burnout,
		UiKit.BAD if p.burnout > 40.0 else UiKit.WARN))
	if p.is_injured(w.today):
		c.body.add_child(UiKit.label("Blessé : %s — retour le %s"
			% [p.injury_label, GameDate.format_long(p.injured_until)],
			UiKit.FS_BODY_L, UiKit.BAD))
	return c


# ============================================================================
# Onglet Attributs
# ============================================================================

func _tab_attributes(host: VBoxContainer, w: World, p: Player,
		module: GameModule) -> void:
	var changes := ProgressionSystem.attribute_changes(p, 6)
	host.add_child(UiKit.subtitle(
		"Valeurs estimées par votre staff. Le chiffre vert ou rouge indique "
		+ "l'évolution sur les six derniers mois."))

	var cols := UiKit.hbox(14)
	host.add_child(cols)
	var groups: Dictionary = module.attribute_groups()
	var col := UiKit.vbox(12)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(col)
	var i := 0
	for group_name in groups:
		# Deux familles par colonne : au-delà, la page devient un mur.
		if i > 0 and i % 2 == 0:
			col = UiKit.vbox(12)
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cols.add_child(col)
		i += 1
		var card := UiKit.card(str(group_name), 3, 12)
		col.add_child(card.panel)
		for key in groups[group_name]:
			card.body.add_child(_attr_row(w, p, module, str(key), changes))


func _attr_row(w: World, p: Player, module: GameModule, key: String,
		changes: Dictionary) -> Control:
	var h := UiKit.hbox(8)
	var name := UiKit.label(module.attribute_label(key), UiKit.FS_BODY_L)
	name.custom_minimum_size = Vector2(168, 0)
	h.add_child(name)
	var est := ScoutingSystem.estimated_attr(w, p, key)
	h.add_child(UiKit.attr_box(est, ScoutingSystem.attr_text(w, p, key),
		Attributes.is_negative(key)))
	h.add_child(UiKit.meter(float(est), 20.0, 74, UiKit.attr_color(est)))
	var delta := int(changes.get(key, 0))
	var d := UiKit.label("%+d" % delta if delta != 0 else "",
		UiKit.FS_SMALL, UiKit.GOOD if delta > 0 else UiKit.BAD)
	d.custom_minimum_size = Vector2(26, 0)
	h.add_child(d)
	return h


# ============================================================================
# Onglet Développement
# ============================================================================

func _tab_development(host: VBoxContainer, w: World, p: Player,
		module: GameModule) -> void:
	var mine := p.org_id == w.player_org_id

	var top := UiKit.hbox(14)
	host.add_child(top)
	var chart_card := UiKit.card("Capacité actuelle et potentielle", 6, 14)
	chart_card.panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart_card.body.add_child(_development_chart(p))
	top.add_child(chart_card.panel)

	var cond := UiKit.card("Rythme de progression", 6, 14)
	cond.panel.custom_minimum_size = Vector2(320, 0)
	cond.body.add_child(UiKit.kv("Marge restante",
		"%.0f %%" % (p.growth_headroom() * 100.0), 160))
	cond.body.add_child(UiKit.kv("Évolution 6 mois", _trend_text(p), 160))
	cond.body.add_child(UiKit.kv("Âge", "%d ans" % p.age(w.today), 160))
	cond.body.add_child(UiKit.kv("Courbe d'âge",
		_age_curve_text(p.age(w.today)), 160))
	cond.body.add_child(UiKit.separator())
	cond.body.add_child(UiKit.bar_row("Rigueur",
		float(ScoutingSystem.estimated_attr(w, p, Attributes.WORK_ETHIC)) * 5.0,
		UiKit.GOOD, 100.0, 130))
	cond.body.add_child(UiKit.bar_row("Usure mentale", p.burnout,
		UiKit.BAD if p.burnout > 40.0 else UiKit.WARN, 100.0, 130))
	top.add_child(cond.panel)

	if mine:
		host.add_child(_training_controls(w, p, module))

	var changes := ProgressionSystem.attribute_changes(p, 6)
	if changes.is_empty():
		host.add_child(UiKit.subtitle(
			"Pas encore assez d'historique pour détailler les évolutions "
			+ "attribut par attribut : revenez dans quelques mois."))
		return
	var rows: Array = []
	for key in changes:
		var k := str(key)
		rows.append({
			"attr": {"text": module.attribute_label(k)},
			"now": {"attr": p.attr(k), "sort": p.attr(k)},
			"delta": {"text": "%+d" % int(changes[key]),
				"color": UiKit.GOOD if int(changes[key]) > 0 else UiKit.BAD,
				"sort": int(changes[key])},
		})
	var card := UiKit.card("Évolutions sur six mois", 6, 12)
	card.body.add_child(sorted_table("player.dev", [
		{"key": "attr", "label": "Attribut", "width": 200},
		{"key": "now", "label": "Actuel", "width": 60, "align": "center"},
		{"key": "delta", "label": "Évolution", "width": 80, "align": "right"},
	], rows, {"scroll": false}))
	host.add_child(card.panel)


func _development_chart(p: Player) -> Control:
	if p.development.size() < 2:
		return UiKit.label("Historique insuffisant — un point est enregistré "
			+ "chaque mois.", UiKit.FS_BODY, UiKit.TEXT_FAINT)
	var ca: Array = []
	var pa: Array = []
	var labels: Array[String] = []
	for snap_v in p.development:
		var snap: Dictionary = snap_v
		ca.append(float(snap.get("ca", 0)))
		pa.append(float(snap.get("pa", 0)))
		labels.append(GameDate.format_month_year(int(snap.get("day", 0))))
	var chart := LineChart.make(ca, UiKit.ACCENT, labels)
	chart.add_series(pa, UiKit.TEXT_FAINT, "Potentiel")
	chart.custom_minimum_size = Vector2(420, 190)
	return chart


func _age_curve_text(age: int) -> String:
	if age <= 18:
		return "Explosion : progression très rapide"
	if age <= 21:
		return "Montée en puissance"
	if age <= 24:
		return "Pic de carrière"
	if age <= 26:
		return "Déclin mécanique, gain tactique"
	return "Fin de carrière — reconversion IGL/coach"


## Réglages d'entraînement individuel. C'est le seul endroit du jeu où le
## manager décide de CE QUE travaille un joueur en particulier.
func _training_controls(w: World, p: Player, module: GameModule) -> Control:
	var card := UiKit.card("Travail individuel", 8, 14)
	card.body.add_child(UiKit.subtitle(
		"Un domaine choisi progresse nettement plus vite, au détriment du reste. "
		+ "L'intensité arbitre entre progression et fraîcheur."))

	var keys: Array[String] = ["" ]
	var labels: Array = ["Confié au coach"]
	for group_name in module.attribute_groups():
		for k in module.attribute_groups()[group_name]:
			keys.append(str(k))
			labels.append("%s — %s" % [str(group_name),
				module.attribute_label(str(k))])
	var selected := maxi(0, keys.find(p.training_focus))

	var row := UiKit.hbox(10)
	row.add_child(UiKit.label("Domaine", UiKit.FS_BODY_L, UiKit.TEXT_DIM))
	row.add_child(UiKit.dropdown(labels, selected, func(idx: int):
		game().set_player_focus(p.id, keys[idx]), 280))
	card.body.add_child(row)

	var levels := [["Ménagé", 0.7], ["Allégée", 0.85], ["Normale", 1.0],
		["Soutenue", 1.15], ["Maximale", 1.35]]
	var intensity := UiKit.hbox(6)
	intensity.add_child(UiKit.label("Intensité", UiKit.FS_BODY_L, UiKit.TEXT_DIM))
	for lv in levels:
		var value := float((lv as Array)[1])
		var active := absf(p.training_intensity - value) < 0.06
		var b := UiKit.button(str((lv as Array)[0]), func():
			game().set_player_intensity(p.id, value),
			UiKit.BtnStyle.PRIMARY if active else UiKit.BtnStyle.NORMAL)
		intensity.add_child(b)
	card.body.add_child(intensity)
	if p.training_intensity > 1.15 and p.burnout > 35.0:
		card.body.add_child(UiKit.label(
			"Attention : usure mentale déjà élevée, cette charge est risquée.",
			UiKit.FS_BODY, UiKit.BAD))
	return card.panel


# ============================================================================
# Onglet Postes
# ============================================================================

func _tab_roles(host: VBoxContainer, w: World, p: Player,
		module: GameModule) -> void:
	host.add_child(UiKit.subtitle(
		"L'aisance s'acquiert en jouant le poste ; l'aptitude vient des "
		+ "attributs. Un joueur peut avoir le profil d'un duelliste sans en "
		+ "avoir jamais joué — c'est une reconversion à tenter, pas un acquis."))

	var r: Roster = game().my_roster()
	var mine := r != null and r.has_player(p.id)
	var current := r.role_of(p) if mine else p.primary_role

	var rows: Array = []
	for entry_v in RoleFamiliarity.ranking(p, module):
		var e: Dictionary = entry_v
		var role := str(e["role"])
		rows.append({
			"_id": role,
			"role": {"text": module.role_label(role)
					+ ("  ← actuel" if role == current else ""),
				"bold": role == current},
			"level": {"text": str(e["label"]), "color": e["color"],
				"sort": -int(e["level"])},
			"apt": {"meter": float(e["aptitude"]) * 100.0,
				"text": "%.0f" % (float(e["aptitude"]) * 100.0),
				"color": UiKit.INFO, "sort": float(e["aptitude"])},
			"mastery": {"attr": p.role_rating(role), "sort": p.role_rating(role)},
			"ca": {"text": str(int(e["ca"])), "sort": int(e["ca"]),
				"color": UiKit.GOOD if int(e["ca"]) >= p.current_ability
					else UiKit.TEXT},
		})
	var card := UiKit.card("Aisance par poste", 6, 12)
	card.body.add_child(sorted_table("player.roles", [
		{"key": "role", "label": "Poste", "width": 160},
		{"key": "level", "label": "Aisance", "width": 130},
		{"key": "apt", "label": "Aptitude", "width": 110},
		{"key": "mastery", "label": "Maîtrise", "width": 70, "align": "center"},
		{"key": "ca", "label": "Niveau au poste", "width": 110, "align": "right"},
	], rows, {"scroll": false, "row_clicked": func(role):
		if mine:
			game().set_player_role(p.id, str(role))}))
	host.add_child(card.panel)
	if mine:
		host.add_child(UiKit.label(
			"Cliquez un poste pour y aligner le joueur dans le cinq.",
			UiKit.FS_SMALL, UiKit.TEXT_FAINT))

	if not mine:
		return
	var actions := UiKit.hbox(8)
	actions.add_child(UiKit.button("Poste naturel",
		func(): game().set_player_role(p.id, "")))
	if not p.is_igl:
		actions.add_child(UiKit.button("Nommer IGL",
			func(): game().set_igl(p.id)))
	host.add_child(actions)


# ============================================================================
# Onglet Contrat & statut
# ============================================================================

func _tab_contract(host: VBoxContainer, w: World, p: Player) -> void:
	var org: Organization = game().my_org()
	var mine := org != null and p.org_id == org.id

	var row := UiKit.hbox(14)
	host.add_child(row)

	var c := UiKit.card("Contrat", 6, 14)
	c.panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if p.contract == null:
		c.body.add_child(UiKit.label("Agent libre", UiKit.FS_LEAD, UiKit.GOOD))
		if org != null:
			c.body.add_child(UiKit.kv("Demande salariale estimée",
				"%s / an" % Money.fmt(ContractSystem.salary_demand(w, p, org)), 190))
	else:
		var ct := p.contract
		var left := ct.days_remaining(w.today)
		c.body.add_child(UiKit.kv("Salaire annuel",
			Money.fmt(ct.salary_yearly), 190))
		c.body.add_child(UiKit.kv("Coût mensuel employeur",
			Money.fmt(ct.monthly_cost()), 190))
		c.body.add_child(UiKit.kv("Échéance", UiKit.label("%s (%s)"
			% [GameDate.format_long(ct.end_day),
				GameDate.format_duration_days(left)], UiKit.FS_BODY_L,
			UiKit.BAD if left < 120 else UiKit.TEXT), 190))
		c.body.add_child(UiKit.kv("Clause de rachat", Money.fmt(ct.buyout), 190))
		c.body.add_child(UiKit.kv("Part des gains",
			"%.0f %%" % ct.prize_share_pct, 190))
		c.body.add_child(UiKit.kv("Part du contenu",
			"%.0f %%" % ct.stream_share_pct, 190))
	c.body.add_child(UiKit.separator())
	c.body.add_child(UiKit.kv("Valeur estimée", Money.fmt(p.market_value), 190))
	c.body.add_child(UiKit.kv("Réputation", str(p.reputation), 190))
	row.add_child(c.panel)

	var s := UiKit.card("Statut dans l'effectif", 6, 14)
	s.panel.custom_minimum_size = Vector2(360, 0)
	s.body.add_child(UiKit.kv("Promesse actuelle",
		UiKit.label(PlayingTime.label(p.promised_time), UiKit.FS_LEAD,
			PlayingTime.color(p.promised_time)), 150))
	s.body.add_child(UiKit.subtitle(
		"Le joueur attend environ %.0f %% des séries. Ne pas tenir la promesse "
		% (PlayingTime.expected_share(p.promised_time) * 100.0)
		+ "coûte du moral et finit par une demande de départ."))
	if mine:
		var grid := UiKit.vbox(4)
		var line := UiKit.hbox(4)
		for status in PlayingTime.ALL:
			if line.get_child_count() >= 3:
				grid.add_child(line)
				line = UiKit.hbox(4)
			var st := status
			line.add_child(UiKit.button(PlayingTime.label(st), func():
				var out: Dictionary = game().set_promised_time(p.id, st)
				ui("player.talk")["last"] = str(out.get("text", ""))
				refresh(),
				UiKit.BtnStyle.PRIMARY if st == p.promised_time
					else UiKit.BtnStyle.NORMAL))
		grid.add_child(line)
		s.body.add_child(grid)
	row.add_child(s.panel)

	if not mine:
		if org != null:
			host.add_child(UiKit.primary("Ouvrir une négociation  ▶", func():
				var n: Negotiation = game().open_negotiation(p.id)
				if n != null:
					navigate("negotiation", {"negotiation_id": n.id})))
			host.add_child(UiKit.label(
				"Salaire, prime, durée, statut, clause de rachat et part des "
				+ "gains se discutent séparément — et son agent n'a pas une "
				+ "patience infinie.", UiKit.FS_SMALL, UiKit.TEXT_FAINT))
		return
	var actions := UiKit.hbox(8)
	actions.add_child(UiKit.danger("Libérer le joueur", func():
		game().release_player(p.id)
		navigate("squad")))
	host.add_child(actions)


# ============================================================================
# Onglet Vestiaire
# ============================================================================

func _tab_locker(host: VBoxContainer, w: World, p: Player) -> void:
	var r: Roster = game().my_roster()
	var mine := r != null and r.has_player(p.id)

	var row := UiKit.hbox(14)
	host.add_child(row)

	var c := UiKit.card("Place dans le groupe", 6, 14)
	c.panel.custom_minimum_size = Vector2(340, 0)
	c.body.add_child(UiKit.bar_row("Influence", p.influence, UiKit.INFO))
	c.body.add_child(UiKit.kv("Personnalité",
		UiKit.label(PersonalityCalc.label(p), UiKit.FS_BODY_L,
			PersonalityCalc.color(p)), 130))
	for sec in PersonalityCalc.secondary_labels(p):
		c.body.add_child(UiKit.label("• " + sec, UiKit.FS_BODY, UiKit.TEXT_DIM))
	c.body.add_child(UiKit.separator())
	if p.concerns.is_empty():
		c.body.add_child(UiKit.label("Aucun grief. Le joueur est en paix.",
			UiKit.FS_BODY_L, UiKit.GOOD))
	else:
		c.body.add_child(UiKit.caption("Griefs", UiKit.BAD))
		for g in p.concerns:
			c.body.add_child(UiKit.label("• "
				+ DynamicsSystem.grievance_label(str(g)), UiKit.FS_BODY_L,
				UiKit.BAD))
	row.add_child(c.panel)

	if mine:
		var rel := UiKit.card("Affinités", 4, 14)
		rel.panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var others := w.players_of(r.id)
		others.sort_custom(func(a: Player, b: Player):
			return p.relation_with(a.id) > p.relation_with(b.id))
		for other_v in others:
			var other: Player = other_v
			if other.id == p.id:
				continue
			var v := p.relation_with(other.id)
			rel.body.add_child(_relation_row(other, v))
		row.add_child(rel.panel)

	if mine:
		host.add_child(_conversation_panel(w, p))


func _relation_row(other: Player, v: int) -> Control:
	var h := UiKit.hbox(8)
	var n := UiKit.label(other.display_name(), UiKit.FS_BODY_L)
	n.custom_minimum_size = Vector2(120, 0)
	h.add_child(n)
	h.add_child(UiKit.meter(float(v) + 100.0, 200.0, 130,
		UiKit.GOOD if v > 30 else (UiKit.BAD if v < -25 else UiKit.WARN)))
	h.add_child(UiKit.label(_relation_label(v), UiKit.FS_BODY,
		UiKit.GOOD if v > 30 else (UiKit.BAD if v < -25 else UiKit.TEXT_DIM)))
	return h


func _relation_label(v: int) -> String:
	if v >= 70:
		return "Inséparables"
	if v >= 45:
		return "Complices"
	if v >= 20:
		return "Bonne entente"
	if v > -25:
		return "Neutres"
	if v > -55:
		return "Frictions"
	return "Conflit ouvert"


## Conversation : sujet + ton. Le résultat s'affiche et reste visible jusqu'à
## la prochaine action, sinon le joueur ne saurait jamais si ça a marché.
func _conversation_panel(w: World, p: Player) -> Control:
	var state := ui("player.talk")
	var card := UiKit.card("Parler à %s" % p.display_name(), 8, 14)

	if not InteractionSystem.can_talk(w, p):
		card.body.add_child(UiKit.label(
			"Vous lui avez déjà parlé cette semaine — encore %d jour(s)."
			% InteractionSystem.days_until_talk(w, p), UiKit.FS_BODY_L,
			UiKit.TEXT_DIM))
	else:
		var topics := InteractionSystem.available_topics(w, p)
		if topics.is_empty():
			card.body.add_child(UiKit.label(
				"Rien à lui dire pour l'instant.", UiKit.FS_BODY_L,
				UiKit.TEXT_DIM))
		else:
			card.body.add_child(UiKit.subtitle(
				"Le ton compte autant que le sujet : la fermeté fonctionne sur "
				+ "un professionnel, elle braque un ego et casse un joueur fragile."))
			for t_v in topics:
				var t: Dictionary = t_v
				card.body.add_child(_topic_row(p, t, state))
	if str(state.get("last", "")) != "":
		card.body.add_child(UiKit.separator())
		card.body.add_child(UiKit.wrap(str(state["last"]), UiKit.FS_BODY_L,
			state.get("last_color", UiKit.TEXT)))
	return card.panel


func _topic_row(p: Player, t: Dictionary, state: Dictionary) -> Control:
	var line := UiKit.hbox(8)
	var v := UiKit.vbox(0)
	v.custom_minimum_size = Vector2(290, 0)
	v.add_child(UiKit.label(str(t["label"]), UiKit.FS_BODY_L,
		UiKit.WARN if bool(t.get("risky", false)) else UiKit.TEXT))
	v.add_child(UiKit.label(str(t.get("hint", "")), UiKit.FS_SMALL,
		UiKit.TEXT_FAINT))
	line.add_child(v)
	var tones: Array[int] = [InteractionSystem.Tone.CALM,
		InteractionSystem.Tone.FIRM, InteractionSystem.Tone.WARM]
	for tone in tones:
		var key := str(t["key"])
		var tn: int = tone
		line.add_child(UiKit.button(InteractionSystem.tone_label(tn), func():
			var out: Dictionary = game().talk_to_player(p.id, key, tn)
			state["last"] = str(out.get("text", ""))
			state["last_color"] = UiKit.GOOD if float(out.get("morale", 0.0)) > 0.0 \
				else (UiKit.BAD if float(out.get("morale", 0.0)) < 0.0 else UiKit.TEXT)
			refresh()))
	return line


# ============================================================================
# Onglet Statistiques
# ============================================================================

func _tab_stats(host: VBoxContainer, w: World, p: Player,
		module: GameModule) -> void:
	var st: Dictionary = p.season_stats
	var series := int(st.get("series", 0))
	if series == 0:
		host.add_child(UiKit.empty_state("Aucun match joué cette saison.",
			"Les statistiques apparaissent après la première série."))
	else:
		var strip := UiKit.hbox(26)
		var card := UiKit.card("Saison en cours", 8, 14)
		card.body.add_child(strip)
		strip.add_child(UiKit.stat_block("Séries", str(series)))
		strip.add_child(UiKit.stat_block("Note moyenne",
			"%.2f" % float(st.get("rating", 0.0)),
			UiKit.rating_color(float(st.get("rating", 0.0)))))
		strip.add_child(UiKit.stat_block("ACS", "%.0f" % float(st.get("acs", 0.0))))
		strip.add_child(UiKit.stat_block("K / D / A", "%d / %d / %d"
			% [int(st.get("kills", 0)), int(st.get("deaths", 0)),
				int(st.get("assists", 0))]))
		strip.add_child(UiKit.stat_block("Ouvertures", "%d"
			% int(st.get("first_kills", 0)),
			UiKit.TEXT, "perdues : %d" % int(st.get("first_deaths", 0))))
		strip.add_child(UiKit.stat_block("Clutchs", "%d / %d"
			% [int(st.get("clutches", 0)), int(st.get("clutch_attempts", 0))]))
		strip.add_child(UiKit.stat_block("Aces", str(int(st.get("aces", 0)))))
		host.add_child(card.panel)

	if p.career.is_empty():
		host.add_child(UiKit.subtitle("Aucune saison achevée à ce jour."))
		return
	var rows: Array = []
	for line_v in p.career:
		var line: Dictionary = line_v
		rows.append({
			"year": {"text": str(line.get("year", "")), "sort": int(line.get("year", 0))},
			"org": {"text": str(line.get("org", ""))},
			"series": {"text": str(int(line.get("series", 0))),
				"sort": int(line.get("series", 0))},
			"rating": {"text": "%.2f" % float(line.get("rating", 0.0)),
				"color": UiKit.rating_color(float(line.get("rating", 0.0))),
				"sort": float(line.get("rating", 0.0))},
			"acs": {"text": "%.0f" % float(line.get("acs", 0.0)),
				"sort": float(line.get("acs", 0.0))},
			"ca": {"text": str(int(line.get("ca", 0))), "sort": int(line.get("ca", 0))},
		})
	var hist := UiKit.card("Carrière", 6, 12)
	hist.body.add_child(sorted_table("player.career", [
		{"key": "year", "label": "Saison", "width": 70},
		{"key": "org", "label": "Structure", "width": 170},
		{"key": "series", "label": "Séries", "width": 60, "align": "right"},
		{"key": "rating", "label": "Note", "width": 60, "align": "right"},
		{"key": "acs", "label": "ACS", "width": 60, "align": "right"},
		{"key": "ca", "label": "Niveau", "width": 60, "align": "right"},
	], rows, {"scroll": false}))
	host.add_child(hist.panel)


func _grade(v: float) -> Color:
	if v >= 65.0:
		return UiKit.GOOD
	if v <= 40.0:
		return UiKit.BAD
	return UiKit.WARN
