extends Screen

## Tableau de bord : la seule page qu'on ouvre vingt fois par saison.
##
## Elle répond à quatre questions, dans cet ordre exact — c'est l'ordre dans
## lequel un directeur se les pose en arrivant le matin :
##   1. QU'EST-CE QUE JE DOIS FAIRE ? (la liste de tâches)
##   2. C'est quand, le prochain match, et contre qui ?
##   3. Où en sont l'équipe et l'argent ?
##   4. Que s'est-il passé pendant que j'avançais le temps ?
##
## Deux principes de construction, et ils sont la raison de la refonte :
##
## **Rien de ce qui est déjà dans la barre haute.** La trésorerie, le résultat
## mensuel et la date y sont en permanence. Les répéter ici en gros coûtait un
## sixième de l'écran pour zéro information — la place va à ce qu'on ne voit
## nulle part ailleurs : le classement réel, le vestiaire, l'autonomie.
##
## **Tout ce qui est affiché est une PORTE.** Une ligne d'alerte qui dit
## « Emberko — douleur à l'épaule » et qu'on ne peut pas cliquer oblige à
## traverser le menu pour retrouver Emberko. Chaque tâche, chaque rencontre,
## chaque message mène ici d'un clic à l'endroit où on agit. C'est tout ce que
## veut dire « fluide » : ne jamais faire chercher au joueur ce qu'on vient de
## lui montrer.

## Seuils d'urgence de la liste de tâches. Le tri se fait dessus : le rouge
## remonte, et à urgence égale on garde l'ordre de découverte.
const URG_CRITICAL := 0
const URG_HIGH := 1
const URG_MEDIUM := 2
const URG_LOW := 3


func build() -> void:
	var w := world()
	var o: Organization = game().my_org()
	if o == null:
		return
	var r: Roster = game().my_roster()

	add_child(page_header(o.name, _identity_line(w, o, r), [
		UiKit.ghost("Effectif ▸", func(): navigate("squad")),
		UiKit.ghost("Calendrier ▸", func(): navigate("calendar")),
	]))

	add_child(_pulse_strip(w, o, r))

	var parts := _dashboard_split(400)
	var main: VBoxContainer = parts[0]
	var side: VBoxContainer = parts[1]

	main.add_child(_next_match_card(w, r))
	main.add_child(_tasks_card(w, o, r))
	main.add_child(_last_result())
	# La liste des rencontres ferme la colonne et absorbe la hauteur restante :
	# sans cela, la colonne s'arrêtait au tiers de l'écran et le vide se lisait
	# comme un écran inachevé.
	var fixtures := _fixtures_card(w, r)
	fixtures.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(fixtures)

	side.add_child(_sections_card())
	side.add_child(_finance_card(w, o))
	side.add_child(_board_card(w, o))
	side.add_child(_news_card(w))


## Deux colonnes, dont la LATÉRALE DÉFILE.
##
## Les quatre cartes de droite dépassent la hauteur d'une fenêtre de 720 px, et
## avant cette refonte elles étaient simplement coupées par le bas : les
## objectifs de la direction disparaissaient sans le moindre indice qu'il en
## manquait. La colonne principale, elle, garde sa hauteur pleine — c'est là que
## vivent les tâches, et elles ne doivent jamais demander un geste pour être
## vues.
##
## Il n'y a aucun autre ScrollContainer dans cet écran (le tableau des
## rencontres est construit avec `scroll: false`), donc pas de risque de
## défilements imbriqués sur le même axe.
func _dashboard_split(side_width: int) -> Array:
	var body := UiKit.hbox(14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)

	var main := UiKit.vbox(10)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(main)

	var side := UiKit.vbox(10)
	# Piège Godot : un ScrollContainer dimensionne son enfant d'après les
	# SIZE_EXPAND de L'ENFANT, pas les siens. Le défilement horizontal étant
	# désactivé, l'enfant DOIT porter SIZE_EXPAND_FILL horizontal, faute de quoi
	# il retombe à sa largeur minimale et le contenu disparaît sans erreur.
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size = Vector2(side_width, 0)
	sc.add_child(side)
	body.add_child(sc)
	return [main, side]


## Sous-titre du bandeau : ce qu'un commentateur dirait en une phrase.
func _identity_line(w: World, o: Organization, r: Roster) -> String:
	var bits: Array[String] = []
	var rank := _league_rank(w, r)
	if not rank.is_empty():
		bits.append("%s · %de/%d" % [rank["comp"], rank["pos"], rank["total"]])
	elif r != null:
		var league := _league_name(w, r)
		if league != "":
			bits.append(league)
	if r != null:
		var rec := _record_text(r)
		if rec != "—":
			bits.append(rec)
	bits.append("%s fans" % _short(o.fanbase))
	return " · ".join(bits)


# ============================================================================
# Bandeau de pouls
# ============================================================================

## Cinq chiffres, et AUCUN qui figure déjà dans la barre haute.
##
## L'ancien bandeau répétait trésorerie et résultat mensuel, qui sont affichés
## en permanence deux centimètres plus haut. Ici on ne met que ce qu'on ne peut
## pas voir autrement : où on en est au classement, comment va le groupe,
## combien de temps la caisse tient.
func _pulse_strip(w: World, o: Organization, r: Roster) -> Control:
	var panel := UiKit.panel(13)
	var row := UiKit.hbox(0)
	panel.add_child(row)

	var cells: Array = []

	var rank := _league_rank(w, r)
	if not rank.is_empty():
		cells.append(UiKit.stat_block("Classement",
			"%de" % rank["pos"], _rank_color(int(rank["pos"]),
				int(rank["total"])), "%s · %d équipes"
					% [rank["comp"], rank["total"]]))
	elif r != null:
		cells.append(UiKit.stat_block("Bilan", _record_text(r), UiKit.TEXT,
			_league_name(w, r)))

	if r != null:
		cells.append(UiKit.stat_block("Cohésion", "%.0f" % r.chemistry,
			UiKit.GOOD if r.chemistry > 65.0 else UiKit.WARN,
			"%d joueurs" % w.players_of(r.id).size()))
		var atm := DynamicsSystem.atmosphere(w, r)
		cells.append(UiKit.stat_block("Vestiaire",
			DynamicsSystem.atmosphere_label(atm),
			UiKit.GOOD if atm >= 62.0 else (UiKit.WARN if atm >= 40.0
				else UiKit.BAD), _grievance_summary(w, r)))

	var runway := FinanceSystem.runway_months(w, o)
	cells.append(UiKit.stat_block("Autonomie", UiKit.runway_text(runway),
		UiKit.runway_color(runway), "masse salariale %.0f %% des recettes"
			% (FinanceSystem.wage_ratio(w, o) * 100.0)))

	cells.append(UiKit.stat_block("Réputation", str(o.reputation), UiKit.TEXT,
		"%s fans" % _short(o.fanbase)))

	for i in cells.size():
		if i > 0:
			row.add_child(UiKit.gap(0))
			row.add_child(UiKit.vrule(38))
		var holder := MarginContainer.new()
		holder.add_theme_constant_override("margin_left", 0 if i == 0 else 20)
		holder.add_theme_constant_override("margin_right", 20)
		holder.add_child(cells[i])
		row.add_child(holder)
	row.add_child(UiKit.spacer())
	return panel


func _rank_color(pos: int, total: int) -> Color:
	if pos <= maxi(1, total / 4):
		return UiKit.GOOD
	if pos > total - maxi(1, total / 4):
		return UiKit.BAD
	return UiKit.TEXT


# ============================================================================
# Prochain match
# ============================================================================

## Carte d'affiche du prochain match, à la manière d'une incrustation d'avant
## rencontre : les deux écussons face à face, le niveau estimé de chaque cinq,
## et le bouton qui mène là où on prépare vraiment le match.
##
## C'est la première chose sous le bandeau parce que c'est la seule échéance
## que le joueur ne choisit pas : tout le reste peut attendre demain.
func _next_match_card(w: World, r: Roster) -> Control:
	if r == null:
		return UiKit.gap(0)
	var upcoming := w.upcoming_for_roster(r.id, 1)
	if upcoming.is_empty():
		var card := UiKit.card("Prochaine échéance", 6, 12)
		card.body.add_child(UiKit.label(_next_stage_text(w, r),
			UiKit.FS_BODY_L, UiKit.TEXT_DIM))
		return card.panel

	var f: Fixture = upcoming[0]
	var opp := w.roster(f.opponent_of(r.id))
	var opp_org := w.org(opp.org_id) if opp != null else null
	var comp := w.competition(f.competition_id)
	var me_org := w.org(r.org_id)
	var days := f.day - w.today
	var tint := UiKit.org_color(me_org)

	var b := Banner.new(tint)
	b.base = UiKit.BG_PANEL
	b.spread = 0.5
	b.pad(26, 12, 14, 12)
	var row := UiKit.hbox(14)
	b.add_child(row)

	var when := UiKit.vbox(1)
	when.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	when.add_child(UiKit.caption("Prochain match"))
	when.add_child(UiKit.display(_countdown(days), UiKit.FS_H2,
		UiKit.ACCENT if days <= 1 else UiKit.TEXT, 700, 0.2))
	when.add_child(UiKit.label("%s · BO%d"
		% [GameDate.format_day_month(f.day), f.best_of], UiKit.FS_SMALL,
		UiKit.TEXT_DIM))
	row.add_child(when)
	row.add_child(UiKit.vrule(44))

	row.add_child(_side_block(me_org, r, w, true))
	var vs := UiKit.display("VS", UiKit.FS_H3, UiKit.TEXT_FAINT, 700, 1.0)
	vs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(vs)
	row.add_child(_side_block(opp_org, opp, w, false))

	row.add_child(UiKit.spacer())
	var meta := UiKit.vbox(1)
	meta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meta.add_child(UiKit.caption(comp.short_name if comp != null else ""))
	meta.add_child(UiKit.label(f.round_label
		+ ("  · LAN" if f.is_lan else ""), UiKit.FS_BODY_L, UiKit.TEXT))
	row.add_child(meta)

	var actions := UiKit.hbox(6)
	actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	actions.add_child(UiKit.ghost("Tactique", func(): navigate("tactics")))
	actions.add_child(UiKit.button("Jouer  ▶",
		func(): game().advance_to_next_match()))
	row.add_child(actions)
	return b


## Un camp de l'affiche : écusson, nom, niveau estimé du cinq.
func _side_block(org: Organization, roster: Roster, w: World,
		mine: bool) -> Control:
	var v := UiKit.vbox(2)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var line := UiKit.hbox(8)
	var color := UiKit.org_color(org) if org != null else UiKit.TEXT_FAINT
	line.add_child(UiKit.crest(org.tag if org != null else "?", color, 30))
	var names := UiKit.vbox(0)
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	names.add_child(UiKit.display(
		(org.name if org != null else "À déterminer").to_upper(),
		UiKit.FS_BODY_L, UiKit.TEXT, 700, 0.3))
	var strength := _lineup_strength(w, roster)
	names.add_child(UiKit.label(
		"niveau %s" % ("—" if strength <= 0 else str(strength)),
		UiKit.FS_SMALL, UiKit.TEXT_DIM))
	line.add_child(names)
	v.add_child(line)
	return v


## Niveau moyen ESTIMÉ du cinq : ce qu'un analyste dirait avant match. Passe
## par ScoutingSystem, donc reste faillible sur l'adversaire — c'est voulu.
func _lineup_strength(w: World, roster: Roster) -> int:
	if roster == null:
		return 0
	var total := 0
	var n := 0
	for p in w.players_of(roster.id):
		if not roster.starters.has(p.id):
			continue
		total += ScoutingSystem.estimated_ca(w, p)
		n += 1
	if n == 0:
		return 0
	return int(round(float(total) / float(n)))


func _countdown(days: int) -> String:
	if days <= 0:
		return "AUJOURD'HUI"
	if days == 1:
		return "DEMAIN"
	return "DANS %d JOURS" % days


# ============================================================================
# Liste de tâches
# ============================================================================

## Ce qu'il y a à faire, trié par urgence, et CLIQUABLE.
##
## C'est le cœur de l'écran. L'ancienne version affichait les mêmes constats en
## texte mort : on lisait « Glimar ne joue pas assez », puis on ouvrait le menu,
## puis l'effectif, puis on cherchait Glimar. Chaque ligne mène maintenant
## directement là où le problème se règle.
func _tasks_card(w: World, o: Organization, r: Roster) -> Control:
	var tasks := _collect_tasks(w, o, r)
	var card := UiKit.card("", 7, 12)

	var head := UiKit.hbox(8)
	head.add_child(UiKit.caption("Ce qui demande votre attention"))
	head.add_child(UiKit.spacer())
	if not tasks.is_empty():
		head.add_child(UiKit.pill("%d" % tasks.size(),
			UiKit.BAD if int(tasks[0]["urgency"]) == URG_CRITICAL
				else UiKit.WARN, true))
	card.body.add_child(head)

	if tasks.is_empty():
		card.body.add_child(UiKit.label(
			"Rien à signaler. Profitez-en pour préparer la suite.",
			UiKit.FS_BODY_L, UiKit.GOOD))
		return card.panel

	for t in tasks:
		card.body.add_child(_task_row(t))
	return card.panel


## Une tâche : pastille d'urgence, phrase, et flèche. La ligne entière est
## cliquable — pas seulement la flèche, qui ne sert que d'indice visuel.
func _task_row(t: Dictionary) -> Control:
	var color: Color = t["color"]
	var line := PanelContainer.new()
	var base := UiKit.box(UiKit.BG_ROW, 5, 0, UiKit.BORDER_SOFT, 1)
	base.content_margin_left = 10
	base.content_margin_right = 10
	base.content_margin_top = 6
	base.content_margin_bottom = 6
	line.add_theme_stylebox_override("panel", base)
	var hover := UiKit.box(UiKit.BG_ROW_HOVER, 5, 0, color, 1)
	hover.content_margin_left = 10
	hover.content_margin_right = 10
	hover.content_margin_top = 6
	hover.content_margin_bottom = 6

	var row := UiKit.hbox(9)
	line.add_child(row)

	var dot := UiKit.label("▍", UiKit.FS_BODY_L, color)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(dot)

	var text := UiKit.label(str(t["text"]), UiKit.FS_BODY_L, UiKit.TEXT)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)

	var go := UiKit.label(str(t.get("action_label", "")) + "  ›",
		UiKit.FS_SMALL, color)
	go.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(go)

	var action: Callable = t["action"]
	line.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	line.mouse_entered.connect(func():
		line.add_theme_stylebox_override("panel", hover))
	line.mouse_exited.connect(func():
		line.add_theme_stylebox_override("panel", base))
	line.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed \
				and ev.button_index == MOUSE_BUTTON_LEFT and action.is_valid():
			action.call())
	return line


## Recense tout ce qui mérite l'attention du joueur, du plus grave au plus
## anodin. Chaque entrée porte SA destination : c'est ce qui rend la liste
## utile plutôt que décorative.
func _collect_tasks(w: World, o: Organization, r: Roster) -> Array:
	var out: Array = []

	# --- Argent : une structure en faillite n'a plus de problème d'effectif.
	var runway := FinanceSystem.runway_months(w, o)
	if o.cash() < 0:
		out.append(_task(URG_CRITICAL, UiKit.BAD,
			"Trésorerie dans le rouge : %s." % Money.fmt(o.cash()),
			"Finances", func(): navigate("finance")))
	elif runway >= 0 and runway <= 3:
		out.append(_task(URG_CRITICAL, UiKit.BAD,
			"Il reste %s d'autonomie au rythme actuel."
				% UiKit.runway_text(runway),
			"Finances", func(): navigate("finance")))

	if r != null:
		var module := w.module_for(r.game_id)
		if r.starters.size() < module.team_size():
			out.append(_task(URG_CRITICAL, UiKit.BAD,
				"Le cinq de départ est incomplet (%d/%d)."
					% [r.starters.size(), module.team_size()],
				"Composer", func(): navigate("squad")))

		# --- Joueurs : un par ligne, et la ligne mène à SA fiche.
		for p in w.players_of(r.id):
			var pid := p.id
			if p.is_injured(w.today):
				out.append(_task(URG_HIGH, UiKit.BAD,
					"%s — %s, retour le %s" % [p.display_name(),
						p.injury_label,
						GameDate.format_day_month(p.injured_until)],
					"Fiche", func(): navigate("player", {"player_id": pid})))
			elif p.wants_out:
				out.append(_task(URG_HIGH, UiKit.BAD,
					"%s a demandé à partir." % p.display_name(),
					"Fiche", func(): navigate("player", {"player_id": pid})))
			elif p.burnout > 55.0:
				out.append(_task(URG_HIGH, UiKit.BAD,
					"%s montre des signes d'épuisement (usure %.0f)."
						% [p.display_name(), p.burnout],
					"Entraînement", func(): navigate("training")))
			elif not p.concerns.is_empty():
				out.append(_task(URG_MEDIUM, UiKit.WARN, "%s : %s."
					% [p.display_name(), DynamicsSystem.grievance_label(
						str(p.concerns[0])).to_lower()],
					"Vestiaire", func(): navigate("dynamics")))
			elif p.contract != null \
					and p.contract.days_remaining(w.today) < 90:
				out.append(_task(URG_MEDIUM, UiKit.WARN,
					"%s arrive en fin de contrat (%s)."
						% [p.display_name(), GameDate.format_duration_days(
							p.contract.days_remaining(w.today))],
					"Contrat", func(): navigate("player",
						{"player_id": pid})))

		# --- Encadrement : un roster sans entraîneur progresse moins vite, et
		# rien d'autre dans l'interface ne le signale.
		if r.head_coach_id == "":
			out.append(_task(URG_MEDIUM, UiKit.WARN,
				"Aucun entraîneur principal en poste.",
				"Encadrement", func(): navigate("staff")))

	# --- Occasions : moins urgentes qu'un problème, mais périssables.
	var offers: Array = game().sponsor_offers()
	if not offers.is_empty():
		out.append(_task(URG_LOW, UiKit.INFO,
			"%d proposition(s) de sponsor en attente." % offers.size(),
			"Finances", func(): navigate("finance")))

	var unread: int = game().unread_count()
	if unread > 0:
		out.append(_task(URG_LOW, UiKit.INFO,
			"%d message(s) non lu(s)." % unread,
			"Messages", func(): navigate("inbox")))

	# Tri STABLE : `sort_custom` ne l'est pas, donc on trie sur un rang composé
	# de l'urgence et de l'ordre de découverte. Sans cela, deux rafraîchissements
	# de suite pourraient réordonner deux lignes de même urgence, et une liste
	# qui bouge toute seule sous le curseur est pénible à cliquer.
	for i in out.size():
		(out[i] as Dictionary)["_rank"] = int(out[i]["urgency"]) * 1000 + i
	out.sort_custom(func(a, b): return int(a["_rank"]) < int(b["_rank"]))
	return out


func _task(urgency: int, color: Color, text: String, action_label: String,
		action: Callable) -> Dictionary:
	return {"urgency": urgency, "color": color, "text": text,
		"action_label": action_label, "action": action}


# ============================================================================
# Rencontres et résultat
# ============================================================================

func _fixtures_card(w: World, r: Roster) -> Control:
	var card := UiKit.card("Prochaines rencontres", 6, 12)
	if r == null:
		card.body.add_child(UiKit.label("Aucun roster.", UiKit.FS_BODY_L,
			UiKit.TEXT_DIM))
		return card.panel
	var upcoming := w.upcoming_for_roster(r.id, 8)
	# Sans rencontre programmée, la carte « Prochaine échéance » dit déjà, plus
	# haut et mot pour mot, quand la phase s'ouvre. Répéter la phrase deux fois
	# dans le même écran ne renseigne pas : ça donne l'impression que l'un des
	# deux blocs n'a pas fini de se charger.
	if upcoming.is_empty():
		return UiKit.gap(0)

	var rows: Array = []
	for f in upcoming:
		var opp := w.roster(f.opponent_of(r.id))
		var opp_org := w.org(opp.org_id) if opp != null else null
		var comp := w.competition(f.competition_id)
		var days := f.day - w.today
		rows.append({
			"_id": f.competition_id,
			"when": {"text": GameDate.format_day_month(f.day),
				"color": UiKit.ACCENT if days <= 1 else UiKit.TEXT,
				"sort": f.day},
			"in": {"text": "aujourd'hui" if days == 0
					else ("demain" if days == 1 else "dans %d j" % days),
				"color": UiKit.TEXT_DIM, "sort": days},
			"opponent": {"text": opp_org.name if opp_org != null
				else "à déterminer", "bold": true},
			"strength": _strength_cell(w, opp),
			"format": {"text": "BO%d" % f.best_of},
			"comp": {"text": comp.short_name if comp != null else ""},
			"round": {"text": f.round_label + ("  · LAN" if f.is_lan else "")},
		})
	# Cliquer une rencontre ouvre SA compétition : c'est là qu'on trouve le
	# classement, l'arbre et les autres résultats du tour.
	card.body.add_child(sorted_table("home.matches", [
		{"key": "when", "label": "Date", "width": 76},
		{"key": "in", "label": "", "width": 84, "sortable": false},
		{"key": "opponent", "label": "Adversaire", "width": 170},
		{"key": "strength", "label": "Niveau", "width": 74, "align": "right"},
		{"key": "format", "label": "Format", "width": 56},
		{"key": "comp", "label": "Compétition", "width": 110},
		{"key": "round", "label": "Tour", "width": 150, "expand": true},
	], rows, {
		"scroll": false,
		"row_clicked": func(cid): navigate("competition",
			{"competition_id": cid}),
	}))
	return card.panel


## Prochaine phase à s'ouvrir pour cette équipe, en toutes lettres.
func _next_stage_text(w: World, r: Roster) -> String:
	var best: Stage = null
	var best_comp: Competition = null
	for cid in r.competition_ids:
		var c := w.competition(cid)
		if c == null:
			continue
		for st in c.stages:
			if st.status != Stage.Status.PENDING or st.start_day < w.today:
				continue
			if best == null or st.start_day < best.start_day:
				best = st
				best_comp = c
	if best == null:
		return "Rien de programmé pour l'instant."
	var days := best.start_day - w.today
	return "%s — %s s'ouvre le %s (dans %d jours)." \
		% [best_comp.short_name, best.name,
			GameDate.format_long(best.start_day), days]


func _strength_cell(w: World, opp: Roster) -> Dictionary:
	var avg := _lineup_strength(w, opp)
	if avg <= 0:
		return {"text": "—", "sort": 0}
	return {"text": str(avg), "sort": avg,
		"color": UiKit.BAD if avg >= 140 else (UiKit.GOOD if avg < 100
			else UiKit.TEXT)}


func _last_result() -> Control:
	var res: MatchResult = game().last_player_result
	if res == null:
		return UiKit.gap(0)
	var w := world()
	var card := UiKit.card("Dernier résultat", 6, 12)
	card.body.add_child(UiKit.wrap(res.headline, UiKit.FS_LEAD))
	var line := UiKit.hbox(10)
	line.add_child(UiKit.label(res.map_score_text(), UiKit.FS_BODY,
		UiKit.TEXT_DIM))
	var mvp := w.player(res.mvp_id)
	if mvp != null:
		line.add_child(UiKit.vrule(16))
		line.add_child(UiKit.label("MVP", UiKit.FS_BODY_L, UiKit.TEXT_DIM))
		line.add_child(UiKit.label(mvp.display_name(), UiKit.FS_BODY_L))
		line.add_child(UiKit.pill("%.2f" % res.rating_of(mvp.id),
			UiKit.rating_color(res.rating_of(mvp.id)), true))
	line.add_child(UiKit.spacer())
	line.add_child(UiKit.ghost("Compte rendu ▸", func(): navigate("match")))
	card.body.add_child(line)
	return card.panel


# ============================================================================
# Colonne latérale
# ============================================================================

## Rappel permanent que la maison ne se résume pas à l'équipe affichée. Absent
## quand il n'y a qu'une section : une carte qui répète l'évidence encombre.
func _sections_card() -> Control:
	var entries: Array = game().sections()
	if entries.size() <= 1:
		return UiKit.gap(0)
	var card := UiKit.card("Sections de la structure", 5, 12)
	for entry_v in entries:
		var entry: Dictionary = entry_v
		var game_id := str(entry["game_id"])
		var playable := bool(entry["playable"])
		var row := UiKit.hbox(8)
		row.add_child(UiKit.pill(GameCatalog.short(game_id),
			GameCatalog.color(game_id), bool(entry["current"])))
		var l := UiKit.label(GameCatalog.label(game_id), UiKit.FS_BODY_L,
			UiKit.TEXT if playable else UiKit.TEXT_FAINT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if bool(entry["current"]):
			row.add_child(UiKit.pill("dirigée", UiKit.ACCENT, true))
		elif playable:
			var rid := str(entry["roster_id"])
			row.add_child(UiKit.ghost("Diriger", func():
				if game().select_roster(rid):
					navigate("squad")))
		else:
			row.add_child(UiKit.label("non simulée", UiKit.FS_SMALL,
				UiKit.TEXT_FAINT))
		card.body.add_child(row)
	card.body.add_child(UiKit.ghost("Voir la structure ▸",
		func(): navigate("club")))
	return card.panel


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
		UiKit.label(UiKit.runway_text(runway), UiKit.FS_BODY_L,
			UiKit.runway_color(runway)), 150))
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


## Derniers messages, cliquables : un titre qu'on lit sans pouvoir l'ouvrir
## oblige à repasser par le menu pour retrouver ce qu'on vient de voir.
func _news_card(w: World) -> Control:
	var card := UiKit.card("Derniers messages", 4, 12)
	if w.inbox.is_empty():
		card.body.add_child(UiKit.label("Boîte vide.", UiKit.FS_BODY_L,
			UiKit.TEXT_DIM))
	var start := maxi(w.inbox.size() - 6, 0)
	for i in range(w.inbox.size() - 1, start - 1, -1):
		var n: Dictionary = w.inbox[i]
		var unread := not bool(n.get("read", false))
		var line := PanelContainer.new()
		var base := UiKit.box(Color(0, 0, 0, 0), 4, 0)
		base.content_margin_left = 4
		base.content_margin_right = 4
		base.content_margin_top = 2
		base.content_margin_bottom = 2
		var hover := UiKit.box(UiKit.BG_ROW_HOVER, 4, 0)
		hover.content_margin_left = 4
		hover.content_margin_right = 4
		hover.content_margin_top = 2
		hover.content_margin_bottom = 2
		line.add_theme_stylebox_override("panel", base)
		line.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		line.mouse_entered.connect(func():
			line.add_theme_stylebox_override("panel", hover))
		line.mouse_exited.connect(func():
			line.add_theme_stylebox_override("panel", base))
		line.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed \
					and ev.button_index == MOUSE_BUTTON_LEFT:
				navigate("inbox"))

		var row := UiKit.hbox(6)
		line.add_child(row)
		var when := UiKit.label(GameDate.format_day_month(int(n["day"])),
			UiKit.FS_SMALL, UiKit.TEXT_FAINT)
		when.custom_minimum_size = Vector2(58, 0)
		when.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(when)
		var title := UiKit.label(str(n["title"]), UiKit.FS_BODY_L,
			UiKit.TEXT if unread else UiKit.TEXT_DIM, unread)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(title)
		card.body.add_child(line)
	card.body.add_child(UiKit.button("Ouvrir la boîte",
		func(): navigate("inbox")))
	return card.panel


# ============================================================================
# Calculs d'appoint
# ============================================================================

## Position RÉELLE dans la phase en cours de la ligue.
##
## L'ancien `_position_text` renvoyait le nom de la compétition sous
## l'intitulé « position » : on croyait lire un classement, on lisait une
## étiquette. Ici on passe par le classement calculé par le moteur.
func _league_rank(w: World, r: Roster) -> Dictionary:
	if r == null:
		return {}
	for cid in r.competition_ids:
		var c := w.competition(cid)
		if c == null or c.kind != Competition.Kind.LEAGUE:
			continue
		for st in c.stages:
			if st.status != Stage.Status.RUNNING:
				continue
			var ranking := CompetitionEngine.compute_ranking(w, st)
			var idx := ranking.find(r.id)
			if idx < 0:
				continue
			return {"pos": idx + 1, "total": ranking.size(),
				"comp": c.short_name if c.short_name != "" else c.name}
	return {}


func _league_name(w: World, r: Roster) -> String:
	if r == null:
		return ""
	for cid in r.competition_ids:
		var c := w.competition(cid)
		if c != null and c.kind == Competition.Kind.LEAGUE:
			return c.short_name if c.short_name != "" else c.name
	return ""


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


func _short(n: int) -> String:
	if n >= 1_000_000:
		return "%s M" % String.num(float(n) / 1_000_000.0, 1)
	if n >= 1000:
		return "%d k" % int(n / 1000)
	return str(n)
