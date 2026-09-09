extends Screen

## Tableau de bord : la seule page qu'on ouvre vingt fois par saison.
## Elle doit répondre à trois questions en un coup d'oeil : où en est
## l'équipe, où en est l'argent, et qu'est-ce qui m'attend.


func build() -> void:
	var w := world()
	var o: Organization = game().my_org()
	if o == null:
		return
	var r: Roster = game().my_roster()

	add_child(UiKit.title("%s — %s" % [o.name, GameDate.format_long(w.today)]))

	var cols := UiKit.hbox(14)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(cols)

	var left := UiKit.vbox(12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	var right := UiKit.vbox(12)
	right.custom_minimum_size = Vector2(360, 0)
	cols.add_child(right)

	left.add_child(_next_matches(w, r))
	left.add_child(_last_result(w))
	left.add_child(_squad_alerts(w, r))

	right.add_child(_finance_card(w, o))
	right.add_child(_board_card(w, o))
	right.add_child(_news_card(w))


func _card(title_text: String) -> Array:
	var p := UiKit.panel(12)
	var v := UiKit.vbox(8)
	p.add_child(v)
	v.add_child(UiKit.label(title_text, 15, UiKit.ACCENT))
	return [p, v]


func _next_matches(w: World, r: Roster) -> Control:
	var card := _card("Prochaines rencontres")
	var v: VBoxContainer = card[1]
	if r == null:
		v.add_child(UiKit.subtitle("Aucun roster."))
		return card[0]
	var upcoming := w.upcoming_for_roster(r.id, 5)
	if upcoming.is_empty():
		v.add_child(UiKit.subtitle("Rien de programmé pour l'instant."))
		return card[0]
	var rows: Array = []
	for f in upcoming:
		var opp := w.roster(f.opponent_of(r.id))
		var opp_org := w.org(opp.org_id) if opp != null else null
		var comp := w.competition(f.competition_id)
		rows.append([
			GameDate.format_day_month(f.day),
			opp_org.name if opp_org != null else "à déterminer",
			"BO%d" % f.best_of,
			comp.short_name if comp != null else "",
			f.round_label,
		])
	v.add_child(UiKit.table([
		{"label": "Date", "width": 80},
		{"label": "Adversaire", "width": 180},
		{"label": "Format", "width": 60},
		{"label": "Compétition", "width": 120},
		{"label": "Tour", "width": 150, "expand": true},
	], rows))
	return card[0]


func _last_result(w: World) -> Control:
	var card := _card("Dernier résultat")
	var v: VBoxContainer = card[1]
	var res: MatchResult = game().last_player_result
	if res == null:
		v.add_child(UiKit.subtitle("Aucun match joué."))
		return card[0]
	v.add_child(UiKit.label(res.headline, 15))
	v.add_child(UiKit.subtitle(res.map_score_text()))
	var mvp := w.player(res.mvp_id)
	if mvp != null:
		v.add_child(UiKit.label("MVP : %s (note %.2f)"
			% [mvp.display_name(), res.rating_of(mvp.id)], 13, UiKit.GOOD))
	v.add_child(UiKit.button("Voir le détail du match",
		func(): navigate("match")))
	return card[0]


func _squad_alerts(w: World, r: Roster) -> Control:
	var card := _card("Point d'effectif")
	var v: VBoxContainer = card[1]
	if r == null:
		return card[0]
	var alerts: Array[String] = []
	for p in w.players_of(r.id):
		if p.is_injured(w.today):
			alerts.append("%s — %s, retour le %s"
				% [p.display_name(), p.injury_label,
					GameDate.format_day_month(p.injured_until)])
		elif p.burnout > 55.0:
			alerts.append("%s montre des signes d'épuisement." % p.display_name())
		elif p.wants_out:
			alerts.append("%s souhaite quitter la structure." % p.display_name())
		elif p.contract != null and p.contract.days_remaining(w.today) < 90:
			alerts.append("%s arrive en fin de contrat (%d jours)."
				% [p.display_name(), p.contract.days_remaining(w.today)])
	if alerts.is_empty():
		v.add_child(UiKit.label("Rien à signaler. Cohésion %.0f / 100."
			% r.chemistry, 13, UiKit.GOOD))
	else:
		for a in alerts:
			v.add_child(UiKit.label("• " + a, 13, UiKit.WARN))
	return card[0]


func _finance_card(w: World, o: Organization) -> Control:
	var card := _card("Situation financière")
	var v: VBoxContainer = card[1]
	var monthly := FinanceSystem.projected_monthly_result(w, o)
	var runway := FinanceSystem.runway_months(w, o)
	v.add_child(_kv("Trésorerie", Money.fmt(o.cash()),
		UiKit.GOOD if o.cash() >= 0 else UiKit.BAD))
	v.add_child(_kv("Résultat prévisionnel", "%s / mois" % Money.fmt(monthly),
		UiKit.GOOD if monthly >= 0 else UiKit.BAD))
	v.add_child(_kv("Autonomie",
		"rentable" if runway < 0 else "%d mois" % runway,
		UiKit.GOOD if runway < 0 else (UiKit.BAD if runway <= 3 else UiKit.WARN)))
	v.add_child(_kv("Masse salariale",
		"%s / an" % Money.fmt(FinanceSystem.wage_bill_yearly(w, o))))
	v.add_child(_kv("Sponsors actifs", str(o.active_sponsors(w.today).size())))
	v.add_child(_kv("Fans", str(o.fanbase)))
	v.add_child(UiKit.button("Ouvrir les finances", func(): navigate("finance")))
	return card[0]


func _board_card(w: World, o: Organization) -> Control:
	var card := _card("Direction")
	var v: VBoxContainer = card[1]
	v.add_child(_kv("Confiance",
		BoardSystem.confidence_label(o.board_confidence),
		UiKit.GOOD if o.board_confidence > 60.0
			else (UiKit.BAD if o.board_confidence < 35.0 else UiKit.WARN)))
	v.add_child(UiKit.meter(o.board_confidence, 100.0, 300,
		UiKit.GOOD if o.board_confidence > 55.0 else UiKit.WARN))
	for obj_v in o.objectives:
		var obj: Dictionary = obj_v
		var color := UiKit.TEXT_DIM
		var prefix := "•"
		if bool(obj.get("evaluated", false)):
			color = UiKit.GOOD if bool(obj["met"]) else UiKit.BAD
			prefix = "✓" if bool(obj["met"]) else "✗"
		v.add_child(UiKit.label("%s %s" % [prefix, obj["label"]], 13, color))
	return card[0]


func _news_card(w: World) -> Control:
	var card := _card("Derniers messages")
	var v: VBoxContainer = card[1]
	var start := maxi(w.inbox.size() - 6, 0)
	if w.inbox.is_empty():
		v.add_child(UiKit.subtitle("Boîte vide."))
	for i in range(w.inbox.size() - 1, start - 1, -1):
		var n: Dictionary = w.inbox[i]
		var color := UiKit.TEXT if not bool(n.get("read", false)) else UiKit.TEXT_DIM
		v.add_child(UiKit.label("%s — %s"
			% [GameDate.format_day_month(int(n["day"])), n["title"]], 13, color))
	v.add_child(UiKit.button("Ouvrir la boîte", func(): navigate("inbox")))
	return card[0]


func _kv(key: String, value: String, color: Color = UiKit.TEXT) -> Control:
	var h := UiKit.hbox(8)
	var k := UiKit.label(key, 13, UiKit.TEXT_DIM)
	k.custom_minimum_size = Vector2(160, 0)
	h.add_child(k)
	h.add_child(UiKit.label(value, 13, color))
	return h
