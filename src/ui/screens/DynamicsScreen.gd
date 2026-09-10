extends Screen

## Vestiaire : hiérarchie, clans, conflits, griefs.
##
## L'écran qui explique pourquoi une équipe sur le papier ne gagne pas. On y
## lit qui pèse dans le groupe (rarement le meilleur joueur), qui parle à qui,
## et ce que chacun reproche à la structure. Tout y est actionnable : chaque
## grief se discute depuis la fiche du joueur.


func build() -> void:
	var w := world()
	var r: Roster = game().my_roster()
	if r == null:
		add_child(UiKit.empty_state("Aucun roster."))
		return
	var squad := w.players_of(r.id)
	var atm := DynamicsSystem.atmosphere(w, r)

	add_child(page_header("Vestiaire",
		"Ambiance %s · cohésion %.0f · entente moyenne %+.0f"
		% [DynamicsSystem.atmosphere_label(atm).to_lower(), r.chemistry,
			DynamicsSystem.average_relation(w, r)], [
			UiKit.button("Effectif", func(): navigate("squad")),
		]))

	var parts := split(400)
	var main: VBoxContainer = parts[0]
	var side: VBoxContainer = parts[1]

	main.add_child(_hierarchy_card(w, r))
	main.add_child(_relations_card(w, r, squad))
	side.add_child(_atmosphere_card(w, r, atm))
	side.add_child(_groups_card(w, r))
	side.add_child(_grievances_card(w, squad))


# ============================================================================
# Hiérarchie
# ============================================================================

func _hierarchy_card(w: World, r: Roster) -> Control:
	var card := UiKit.card("Hiérarchie du groupe", 6, 12)
	var rows: Array = []
	for entry_v in DynamicsSystem.hierarchy(w, r):
		var e: Dictionary = entry_v
		var p: Player = e["player"]
		rows.append({
			"_id": p.id,
			"name": {"text": p.display_name(), "bold": r.starters.has(p.id)},
			"tier": {"text": str(e["tier"]),
				"color": UiKit.ACCENT if str(e["tier"]).begins_with("Patron")
					else (UiKit.INFO if str(e["tier"]).begins_with("Cadre")
						else UiKit.TEXT_DIM)},
			"influence": {"meter": float(e["influence"]),
				"text": "%.0f" % float(e["influence"]), "color": UiKit.INFO,
				"sort": float(e["influence"])},
			"personality": {"text": PersonalityCalc.label(p),
				"color": PersonalityCalc.color(p)},
			"leader": {"attr": p.attr(Attributes.LEADERSHIP),
				"sort": p.attr(Attributes.LEADERSHIP)},
			"ego": {"attr": p.attr(Attributes.EGO), "inverted": true,
				"sort": p.attr(Attributes.EGO)},
			"morale": {"meter": p.morale, "text": "%.0f" % p.morale,
				"color": UiKit.GOOD if p.morale > 60.0 else (UiKit.BAD
					if p.morale < 38.0 else UiKit.WARN), "sort": p.morale},
		})
	card.body.add_child(sorted_table("dynamics.hierarchy", [
		{"key": "name", "label": "Joueur", "width": 116},
		{"key": "tier", "label": "Statut social", "width": 150},
		{"key": "influence", "label": "Influence", "width": 100},
		{"key": "personality", "label": "Personnalité", "width": 180},
		{"key": "leader", "label": "Lead.", "width": 48, "align": "center"},
		{"key": "ego", "label": "Ego", "width": 44, "align": "center"},
		{"key": "morale", "label": "Moral", "width": 90},
	], rows, {"scroll": false,
		"row_clicked": func(pid): navigate("player", {"player_id": pid})}))
	card.body.add_child(UiKit.label(
		"L'influence combine leadership, ancienneté, réputation et statut. "
		+ "Un cadre mécontent contamine tout le groupe ; un remplaçant, non.",
		UiKit.FS_SMALL, UiKit.TEXT_FAINT))
	return card.panel


# ============================================================================
# Matrice des affinités
# ============================================================================

## Tableau croisé : la lecture la plus rapide de « qui s'entend avec qui ».
func _relations_card(w: World, r: Roster, squad: Array) -> Control:
	var card := UiKit.card("Affinités", 6, 12)
	if squad.size() < 2:
		card.body.add_child(UiKit.label("Effectif trop réduit.",
			UiKit.FS_BODY_L, UiKit.TEXT_DIM))
		return card.panel

	var cols: Array = [{"key": "name", "label": "", "width": 116,
		"sortable": false}]
	for p_v in squad:
		var p: Player = p_v
		cols.append({"key": p.id, "label": p.display_name().substr(0, 6),
			"width": 54, "align": "center", "sortable": false})

	var rows: Array = []
	for a_v in squad:
		var a: Player = a_v
		var row := {"_id": a.id, "name": {"text": a.display_name()}}
		for b_v in squad:
			var b: Player = b_v
			if a.id == b.id:
				row[b.id] = {"text": "—", "color": UiKit.TEXT_FAINT}
			else:
				var v := a.relation_with(b.id)
				row[b.id] = {"text": "%+d" % v, "color": _relation_color(v),
					"tooltip": "%s et %s : %s" % [a.display_name(),
						b.display_name(), _relation_label(v)]}
		rows.append(row)
	card.body.add_child(UiKit.data_table(cols, rows, {"scroll": false,
		"compact": true,
		"row_clicked": func(pid): navigate("player", {"player_id": pid})}))
	card.body.add_child(UiKit.label(
		"Les affinités bougent lentement : il faut des mois de résultats "
		+ "communs pour souder un duo, et un poste disputé pour le briser.",
		UiKit.FS_SMALL, UiKit.TEXT_FAINT))
	return card.panel


func _relation_color(v: int) -> Color:
	if v >= 45:
		return UiKit.GOOD
	if v >= 20:
		return Color("#8fc44f")
	if v > -25:
		return UiKit.TEXT_DIM
	if v > -55:
		return UiKit.WARN
	return UiKit.BAD


func _relation_label(v: int) -> String:
	if v >= 70:
		return "inséparables"
	if v >= 45:
		return "complices"
	if v >= 20:
		return "bonne entente"
	if v > -25:
		return "neutres"
	if v > -55:
		return "frictions"
	return "conflit ouvert"


# ============================================================================
# Panneaux latéraux
# ============================================================================

func _atmosphere_card(w: World, r: Roster, atm: float) -> Control:
	var card := UiKit.card("Ambiance", 7, 14)
	var color := UiKit.GOOD if atm >= 62.0 else (UiKit.WARN if atm >= 40.0
		else UiKit.BAD)
	card.body.add_child(UiKit.label(DynamicsSystem.atmosphere_label(atm),
		UiKit.FS_H1, color, true))
	card.body.add_child(UiKit.meter(atm, 100.0, 330, color))
	card.body.add_child(UiKit.separator())
	card.body.add_child(UiKit.kv("Cohésion du cinq", "%.0f / 100" % r.chemistry,
		170))
	card.body.add_child(UiKit.kv("Effet sur la progression",
		"× %.2f" % DynamicsSystem.chemistry_modifier(w, r), 170))
	card.body.add_child(UiKit.wrap(
		"L'ambiance multiplie ce que l'équipe tire de son entraînement. "
		+ "Un vestiaire tendu peut annuler une saison de travail.",
		UiKit.FS_BODY, UiKit.TEXT_DIM))
	return card.panel


func _groups_card(w: World, r: Roster) -> Control:
	var card := UiKit.card("Clans et conflits", 6, 14)
	var groups := DynamicsSystem.cliques(w, r)
	var squad_size := w.players_of(r.id).size()

	if groups.is_empty():
		card.body.add_child(UiKit.label(
			"Aucun groupe soudé ne s'est encore formé.", UiKit.FS_BODY_L,
			UiKit.TEXT_DIM))
	for g_v in groups:
		var g: Array = g_v
		var names: Array[String] = []
		for p_v in g:
			names.append((p_v as Player).display_name())
		# Un clan qui rassemble presque tout le monde est une force ; deux
		# clans de taille voisine sont une équipe coupée en deux.
		var unifying := g.size() >= squad_size - 1
		card.body.add_child(UiKit.label(
			"%s%s" % ["Groupe soudé : " if unifying else "Clan : ",
				" · ".join(names)],
			UiKit.FS_BODY_L, UiKit.GOOD if unifying else UiKit.WARN))
	if groups.size() >= 2:
		card.body.add_child(UiKit.label(
			"Deux clans distincts : la communication en match en souffre.",
			UiKit.FS_BODY, UiKit.WARN))

	var conflicts := DynamicsSystem.conflicts(w, r)
	if conflicts.is_empty():
		return card.panel
	card.body.add_child(UiKit.separator())
	card.body.add_child(UiKit.caption("Conflits ouverts", UiKit.BAD))
	for c_v in conflicts:
		var c: Dictionary = c_v
		var a: Player = c["a"]
		var b: Player = c["b"]
		var line := UiKit.hbox(6)
		line.add_child(UiKit.label("%s ✕ %s" % [a.display_name(),
			b.display_name()], UiKit.FS_BODY_L, UiKit.BAD))
		line.add_child(UiKit.spacer())
		line.add_child(UiKit.ghost("Arbitrer", func():
			navigate("player", {"player_id": a.id})))
		card.body.add_child(line)
	card.body.add_child(UiKit.label(
		"Un conflit se traite en parlant à l'un des deux, ou en vendant l'un "
		+ "des deux. Il ne se résout pas tout seul.", UiKit.FS_SMALL,
		UiKit.TEXT_FAINT))
	return card.panel


func _grievances_card(w: World, squad: Array) -> Control:
	var card := UiKit.card("Griefs à traiter", 5, 14)
	var any := false
	for p_v in squad:
		var p: Player = p_v
		if p.concerns.is_empty():
			continue
		any = true
		var line := UiKit.vbox(1)
		var head := UiKit.hbox(6)
		head.add_child(UiKit.label(p.display_name(), UiKit.FS_BODY_L,
			UiKit.TEXT, true))
		if p.influence >= 55.0:
			head.add_child(UiKit.pill("cadre", UiKit.INFO, true))
		if p.wants_out:
			head.add_child(UiKit.pill("veut partir", UiKit.BAD, true))
		head.add_child(UiKit.spacer())
		head.add_child(UiKit.ghost("Parler", func():
			# On ouvre directement l'onglet vestiaire de sa fiche.
			ui("player")["tab"] = "locker"
			navigate("player", {"player_id": p.id})))
		line.add_child(head)
		for g in p.concerns:
			line.add_child(UiKit.label("   • "
				+ DynamicsSystem.grievance_label(str(g)), UiKit.FS_BODY,
				UiKit.BAD))
		card.body.add_child(line)
	if not any:
		card.body.add_child(UiKit.label("Personne n'a rien à redire. Profitez-en.",
			UiKit.FS_BODY_L, UiKit.GOOD))
	return card.panel
