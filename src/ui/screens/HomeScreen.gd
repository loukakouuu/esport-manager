extends Screen

## Tableau de bord : la seule page qu'on ouvre vingt fois par saison.
##
## Elle doit répondre à quatre questions en un coup d'œil : où en est l'argent,
## où en est l'équipe, qu'est-ce qui m'attend, et qu'est-ce qui va me poser
## problème. Tout ce qui n'aide pas à répondre à l'une des quatre n'a rien à
## faire ici — c'est ce qui distingue un tableau de bord d'un fourre-tout.


func build() -> void:
	var w := world()
	var o: Organization = game().my_org()
	if o == null:
		return
	var r: Roster = game().my_roster()

	add_child(_kpi_strip(w, o, r))

	var parts := split(400)
	var main: VBoxContainer = parts[0]
	var side: VBoxContainer = parts[1]

	main.add_child(_next_matches(w, r))
	main.add_child(_last_result(w))
	main.add_child(_alerts(w, r))
	side.add_child(_finance_card(w, o))
	side.add_child(_board_card(w, o))
	side.add_child(_news_card(w))


# ============================================================================
# Bandeau de chiffres clés
# ============================================================================

func _kpi_strip(w: World, o: Organization, r: Roster) -> Control:
	var panel := UiKit.panel(14)
	var row := UiKit.hbox(30)
	panel.add_child(row)

	var cash := o.cash()
	row.add_child(UiKit.stat_block("Trésorerie", Money.fmt(cash),
		UiKit.GOOD if cash >= 0 else UiKit.BAD, _runway_text(w, o)))

	var monthly := FinanceSystem.projected_monthly_result(w, o)
	row.add_child(UiKit.stat_block("Résultat mensuel",
		Money.fmt_short(monthly), UiKit.GOOD if monthly >= 0 else UiKit.BAD,
		"masse salariale %.0f %% des revenus"
			% (FinanceSystem.wage_ratio(w, o) * 100.0)))

	row.add_child(UiKit.stat_block("Réputation", str(o.reputation),
		UiKit.TEXT, "%s fans" % _short(o.fanbase)))

	if r != null:
		row.add_child(UiKit.stat_block("Cohésion", "%.0f" % r.chemistry,
			UiKit.GOOD if r.chemistry > 65.0 else UiKit.WARN,
			"%d joueurs" % w.players_of(r.id).size()))
		var atm := DynamicsSystem.atmosphere(w, r)
		row.add_child(UiKit.stat_block("Vestiaire",
			DynamicsSystem.atmosphere_label(atm),
			UiKit.GOOD if atm >= 62.0 else (UiKit.WARN if atm >= 40.0
				else UiKit.BAD), _grievance_summary(w, r)))
		row.add_child(UiKit.stat_block("Bilan", _record_text(r), UiKit.TEXT,
			_position_text(w, r)))

	row.add_child(UiKit.spacer())
	return panel


func _runway_text(w: World, o: Organization) -> String:
	var months := FinanceSystem.runway_months(w, o)
	return "rentable" if months < 0 else "%d mois d'autonomie" % months


func _grievance_summary(w: World, r: Roster) -> String:
	var n := 0
	for p in w.players_of(r.id):
		n += p.concerns.size()
	if n == 0:
		return "aucun grief"
	return "%d grief%s à traiter" % [n, "s" if n > 1 else ""]


func _record_text(r: Roster) -> String:
	var win := 0
	var loss := 0
	for cid in r.season_record:
		var rec: Dictionary = r.season_record[cid]
		win += int(rec.get("w", 0))
		loss += int(rec.get("l", 0))
	if win + loss == 0:
		return "—"
	return "%d V – %d D" % [win, loss]


func _position_text(w: World, r: Roster) -> String:
	for cid in r.competition_ids:
		var c := w.competition(cid)
		if c == null or c.kind != Competition.Kind.LEAGUE:
			continue
		return c.short_name if c.short_name != "" else c.name
	return ""


# ============================================================================
# Colonne principale
# ============================================================================

func _next_matches(w: World, r: Roster) -> Control:
	var card := UiKit.card("Prochaines rencontres", 6, 12)
	if r == null:
		card.body.add_child(UiKit.label("Aucun roster.", UiKit.FS_BODY_L,
			UiKit.TEXT_DIM))
		return card.panel
	var upcoming := w.upcoming_for_roster(r.id, 6)
	if upcoming.is_empty():
		card.body.add_child(UiKit.label(
			"Rien de programmé. La prochaine phase de compétition n'a pas "
			+ "encore été tirée.", UiKit.FS_BODY_L, UiKit.TEXT_DIM))
		return card.panel

	var rows: Array = []
	for f in upcoming:
		var opp := w.roster(f.opponent_of(r.id))
		var opp_org := w.org(opp.org_id) if opp != null else null
		var comp := w.competition(f.competition_id)
		var days := f.day - w.today
		rows.append({
			"when": {"text": GameDate.format_day_month(f.day),
				"color": UiKit.ACCENT if days <= 1 else UiKit.TEXT,
				"sort": f.day},
			"in": {"text": "aujourd'hui" if days == 0
					else ("demain" if days == 1 else "dans %d j" % days),
				"color": UiKit.TEXT_DIM, "sort": days},
			"opponent": {"text": opp_org.name if opp_org != null
				else "à déterminer", "bold": true},
			"strength": _opponent_strength(w, opp),
			"format": {"text": "BO%d" % f.best_of},
			"comp": {"text": comp.short_name if comp != null else ""},
			"round": {"text": f.round_label + ("  · LAN" if f.is_lan else "")},
		})
	card.body.add_child(sorted_table("home.matches", [
		{"key": "when", "label": "Date", "width": 76},
		{"key": "in", "label": "", "width": 84, "sortable": false},
		{"key": "opponent", "label": "Adversaire", "width": 170},
		{"key": "strength", "label": "Niveau", "width": 74, "align": "right"},
		{"key": "format", "label": "Format", "width": 56},
		{"key": "comp", "label": "Compétition", "width": 110},
		{"key": "round", "label": "Tour", "width": 150, "expand": true},
	], rows, {"scroll": false}))
	return card.panel


## Niveau moyen estimé du cinq adverse : ce qu'un analyste dirait avant match.
func _opponent_strength(w: World, opp: Roster) -> Dictionary:
	if opp == null:
		return {"text": "—", "sort": 0}
	var total := 0
	var n := 0
	for p in w.players_of(opp.id):
		if not opp.starters.has(p.id):
			continue
		total += ScoutingSystem.estimated_ca(w, p)
		n += 1
	if n == 0:
		return {"text": "—", "sort": 0}
	var avg := int(round(float(total) / float(n)))
	return {"text": str(avg), "sort": avg,
		"color": UiKit.BAD if avg >= 140 else (UiKit.GOOD if avg < 100
			else UiKit.TEXT)}


func _last_result(w: World) -> Control:
	var card := UiKit.card("Dernier résultat", 6, 12)
	var res: MatchResult = game().last_player_result
	if res == null:
		card.body.add_child(UiKit.label("Aucun match joué.", UiKit.FS_BODY_L,
			UiKit.TEXT_DIM))
		return card.panel
	card.body.add_child(UiKit.wrap(res.headline, UiKit.FS_LEAD))
	card.body.add_child(UiKit.label(res.map_score_text(), UiKit.FS_BODY,
		UiKit.TEXT_DIM))
	var mvp := w.player(res.mvp_id)
	if mvp != null:
		var line := UiKit.hbox(8)
		line.add_child(UiKit.label("MVP", UiKit.FS_BODY_L, UiKit.TEXT_DIM))
		line.add_child(UiKit.label(mvp.display_name(), UiKit.FS_BODY_L))
		line.add_child(UiKit.pill("%.2f" % res.rating_of(mvp.id),
			UiKit.rating_color(res.rating_of(mvp.id)), true))
		card.body.add_child(line)
	card.body.add_child(UiKit.button("Voir le détail du match",
		func(): navigate("match")))
	return card.panel


## Ce qui va poser problème, trié par urgence. Un tableau de bord qui ne dit
## que les bonnes nouvelles ne sert à rien.
func _alerts(w: World, r: Roster) -> Control:
	var card := UiKit.card("Ce qui demande votre attention", 4, 12)
	if r == null:
		return card.panel
	var alerts: Array = []
	for p in w.players_of(r.id):
		if p.is_injured(w.today):
			alerts.append([0, UiKit.BAD, "%s — %s, retour le %s"
				% [p.display_name(), p.injury_label,
					GameDate.format_day_month(p.injured_until)]])
		elif p.wants_out:
			alerts.append([0, UiKit.BAD, "%s a demandé à partir."
				% p.display_name()])
		elif p.burnout > 55.0:
			alerts.append([1, UiKit.BAD,
				"%s montre des signes d'épuisement (usure %.0f)."
					% [p.display_name(), p.burnout]])
		elif not p.concerns.is_empty():
			alerts.append([2, UiKit.WARN, "%s : %s."
				% [p.display_name(),
					DynamicsSystem.grievance_label(str(p.concerns[0])).to_lower()]])
		elif p.contract != null and p.contract.days_remaining(w.today) < 90:
			alerts.append([3, UiKit.WARN,
				"%s arrive en fin de contrat (%s)."
					% [p.display_name(), GameDate.format_duration_days(
						p.contract.days_remaining(w.today))]])
	if r.starters.size() < w.module_for(r.game_id).team_size():
		alerts.append([0, UiKit.BAD, "Le cinq de départ est incomplet."])

	if alerts.is_empty():
		card.body.add_child(UiKit.label(
			"Rien à signaler. Profitez-en pour préparer la suite.",
			UiKit.FS_BODY_L, UiKit.GOOD))
		return card.panel
	alerts.sort_custom(func(a, b): return int(a[0]) < int(b[0]))
	for a in alerts:
		card.body.add_child(UiKit.label("• " + str((a as Array)[2]),
			UiKit.FS_BODY_L, (a as Array)[1]))
	return card.panel


# ============================================================================
# Colonne latérale
# ============================================================================

func _finance_card(w: World, o: Organization) -> Control:
	var card := UiKit.card("Situation financière", 6, 12)
	var monthly := FinanceSystem.projected_monthly_result(w, o)
	var runway := FinanceSystem.runway_months(w, o)

	# La courbe vaut tous les tableaux : elle répond à « ça monte ou ça
	# descend », qui est la seule question qu'on se pose vraiment ici.
	if o.history.size() >= 2:
		var cash: Array = []
		var labels: Array[String] = []
		var start := maxi(0, o.history.size() - 24)
		for i in range(start, o.history.size()):
			var snap: Dictionary = o.history[i]
			cash.append(float(int(snap.get("cash", 0))) / 100.0)
			labels.append(GameDate.format_month_year(int(snap.get("day", 0))))
		var chart := LineChart.make(cash, UiKit.ACCENT, labels)
		chart.zero_line = true
		chart.custom_minimum_size = Vector2(340, 120)
		card.body.add_child(chart)

	card.body.add_child(UiKit.kv("Trésorerie",
		UiKit.label(Money.fmt(o.cash()), UiKit.FS_BODY_L,
			UiKit.GOOD if o.cash() >= 0 else UiKit.BAD), 150))
	card.body.add_child(UiKit.kv("Résultat prévisionnel",
		UiKit.label("%s / mois" % Money.fmt(monthly), UiKit.FS_BODY_L,
			UiKit.GOOD if monthly >= 0 else UiKit.BAD), 150))
	card.body.add_child(UiKit.kv("Autonomie",
		UiKit.label("rentable" if runway < 0 else "%d mois" % runway,
			UiKit.FS_BODY_L, UiKit.GOOD if runway < 0
				else (UiKit.BAD if runway <= 3 else UiKit.WARN)), 150))
	card.body.add_child(UiKit.kv("Masse salariale",
		"%s / an" % Money.fmt(FinanceSystem.wage_bill_yearly(w, o)), 150))
	card.body.add_child(UiKit.kv("Sponsors actifs",
		str(o.active_sponsors(w.today).size()), 150))
	card.body.add_child(UiKit.button("Ouvrir les finances",
		func(): navigate("finance")))
	return card.panel


func _board_card(w: World, o: Organization) -> Control:
	var card := UiKit.card("Direction", 5, 12)
	var confidence := o.board_confidence
	var color := UiKit.GOOD if confidence > 60.0 \
		else (UiKit.BAD if confidence < 35.0 else UiKit.WARN)
	var head := UiKit.hbox(8)
	head.add_child(UiKit.label("Confiance", UiKit.FS_BODY_L, UiKit.TEXT_DIM))
	head.add_child(UiKit.spacer())
	head.add_child(UiKit.label(BoardSystem.confidence_label(confidence),
		UiKit.FS_BODY_L, color))
	card.body.add_child(head)
	card.body.add_child(UiKit.meter(confidence, 100.0, 340, color))

	for obj_v in o.objectives:
		var obj: Dictionary = obj_v
		var c := UiKit.TEXT_DIM
		var prefix := "•"
		if bool(obj.get("evaluated", false)):
			c = UiKit.GOOD if bool(obj["met"]) else UiKit.BAD
			prefix = "✓" if bool(obj["met"]) else "✗"
		card.body.add_child(UiKit.label("%s %s" % [prefix, obj["label"]],
			UiKit.FS_BODY_L, c))
	return card.panel


func _news_card(w: World) -> Control:
	var card := UiKit.card("Derniers messages", 4, 12)
	if w.inbox.is_empty():
		card.body.add_child(UiKit.label("Boîte vide.", UiKit.FS_BODY_L,
			UiKit.TEXT_DIM))
	var start := maxi(w.inbox.size() - 6, 0)
	for i in range(w.inbox.size() - 1, start - 1, -1):
		var n: Dictionary = w.inbox[i]
		var unread := not bool(n.get("read", false))
		var line := UiKit.hbox(6)
		var when := UiKit.label(GameDate.format_day_month(int(n["day"])),
			UiKit.FS_SMALL, UiKit.TEXT_FAINT)
		when.custom_minimum_size = Vector2(58, 0)
		line.add_child(when)
		line.add_child(UiKit.label(str(n["title"]), UiKit.FS_BODY_L,
			UiKit.TEXT if unread else UiKit.TEXT_DIM, unread))
		card.body.add_child(line)
	card.body.add_child(UiKit.button("Ouvrir la boîte",
		func(): navigate("inbox")))
	return card.panel


func _short(n: int) -> String:
	if n >= 1_000_000:
		return "%s M" % String.num(float(n) / 1_000_000.0, 1)
	if n >= 1000:
		return "%d k" % int(n / 1000)
	return str(n)
