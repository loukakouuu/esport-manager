extends Screen

## Choix de la structure à reprendre.
##
## Deux temps, comme dans les gestionnaires de football : on parcourt les
## ligues à gauche, on inspecte une maison à droite, et on ne s'engage qu'après
## avoir vu ce qu'on hérite — l'effectif, les moyens, les sections sur les
## autres jeux et ce que la direction attend.
##
## L'écran précédent (StartScreen) a déjà créé le monde : ici, tout est réel.

const LEAGUES := [
	["chal_emea", "Challengers EMEA"],
	["chal_americas", "Challengers Americas"],
	["chal_pacific", "Challengers Pacific"],
	["chal_china", "Challengers China"],
	["vct_emea", "VCT EMEA"],
	["vct_americas", "VCT Americas"],
	["vct_pacific", "VCT Pacific"],
	["vct_china", "VCT China"],
]


func build() -> void:
	add_child(page_header("Choisir une structure",
		"Cliquez une ligne pour l'inspecter, puis confirmez la reprise.", [
			UiKit.ghost("◀ Changer d'univers", func():
				game().abandon_world()),
		]))
	add_child(tab_bar("newgame", LEAGUES, "chal_emea"))

	var parts := split(420)
	var main: VBoxContainer = parts[0]
	var side: VBoxContainer = parts[1]

	var league := current_tab("newgame", "chal_emea")
	var orgs := WorldGenerator.selectable_orgs(world(), league)
	if orgs.is_empty():
		main.add_child(UiKit.empty_state("Aucune structure dans cette ligue.",
			"L'univers actif ne la renseigne peut-être pas."))
		return

	main.add_child(_org_table(orgs))
	main.add_child(UiKit.wrap(
		"Commencez par les Challengers : la campagne consiste à monter en VCT "
		+ "via l'Ascension. Une structure de ligue partenaire donne des moyens "
		+ "immédiats, et une direction bien moins patiente.",
		UiKit.FS_SMALL, UiKit.TEXT_FAINT))

	side.add_child(_detail_card(_selected_id(orgs)))


# ============================================================================
# Liste
# ============================================================================

func _org_table(orgs: Array) -> Control:
	var columns := [
		{"key": "name", "label": "Structure", "width": 168},
		{"key": "country", "label": "Pays", "width": 46},
		{"key": "sections", "label": "Sections", "width": 200},
		{"key": "reputation", "label": "Réputation", "width": 88, "align": "right"},
		{"key": "fans", "label": "Fans", "width": 78, "align": "right"},
		{"key": "cash", "label": "Trésorerie", "width": 104, "align": "right"},
		{"key": "difficulty", "label": "Difficulté", "width": 110},
	]
	# La difficulté se lit PAR RAPPORT À LA LIGUE : en VCT tout le monde a des
	# millions en banque, et une échelle absolue afficherait « confortable »
	# douze fois de suite. Ce qui compte est de savoir où l'on part dans le
	# classement, et combien de mois on tient.
	var reputations: Array = []
	for entry_v in orgs:
		reputations.append(int((entry_v as Dictionary)["reputation"]))
	reputations.sort()

	var rows: Array = []
	for entry_v in orgs:
		var e: Dictionary = entry_v
		var o := world().org(str(e["org_id"]))
		var games: Array = e.get("games", ["valorant"])
		rows.append({
			"_id": str(e["org_id"]),
			"name": {"text": str(e["name"]), "bold": true},
			"country": {"text": o.country},
			"sections": {"text": _sections_text(games), "sort": games.size(),
				"color": UiKit.TEXT_DIM},
			"reputation": {"text": str(int(e["reputation"])),
				"sort": int(e["reputation"])},
			"fans": {"text": _short(int(e["fanbase"])), "sort": int(e["fanbase"])},
			"cash": UiKit.money_cell(int(e["cash"])),
			"difficulty": _difficulty(o,
				_rank_of(reputations, int(e["reputation"]))),
		})
	return sorted_table("newgame.orgs", columns, rows, {
		"row_clicked": func(org_id):
			ui("newgame")["org_id"] = str(org_id)
			refresh(),
	})


func _sections_text(games: Array) -> String:
	var parts: Array[String] = []
	for g in games:
		parts.append(GameCatalog.short(str(g)))
	return " ".join(parts)


## Structure inspectée : celle qu'on a cliquée, sinon la première de la liste.
func _selected_id(orgs: Array) -> String:
	var wanted := str(ui("newgame").get("org_id", ""))
	for e_v in orgs:
		if str((e_v as Dictionary)["org_id"]) == wanted:
			return wanted
	return str((orgs[0] as Dictionary)["org_id"])


# ============================================================================
# Fiche de la structure
# ============================================================================

func _detail_card(org_id: String) -> Control:
	var w := world()
	var o := w.org(org_id)
	if o == null:
		return UiKit.empty_state("Sélectionnez une structure.")

	var card := UiKit.card("", 9, 14)
	card.panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var head := UiKit.hbox(10)
	head.add_child(UiKit.crest(o.tag, UiKit.color_from_id(o.id), 44))
	var idn := UiKit.vbox(1)
	idn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	idn.add_child(UiKit.label(o.name, UiKit.FS_H3, UiKit.TEXT, true))
	var sub := UiKit.hbox(6)
	sub.add_child(UiKit.pill(o.country))
	sub.add_child(UiKit.pill(o.owner_label(), UiKit.INFO))
	sub.add_child(UiKit.label("fondée en %d" % o.founded_year, UiKit.FS_SMALL,
		UiKit.TEXT_FAINT))
	idn.add_child(sub)
	head.add_child(idn)
	card.body.add_child(head)

	var stats := UiKit.hbox(14)
	stats.add_child(UiKit.stat_block("Réputation", UiKit.stars(o.stars())))
	stats.add_child(UiKit.stat_block("Fans", _short(o.fanbase)))
	stats.add_child(UiKit.stat_block("Trésorerie", Money.fmt_short(o.cash())))
	card.body.add_child(stats)

	card.body.add_child(UiKit.separator())
	card.body.add_child(_sections_block(o))

	card.body.add_child(UiKit.separator())
	card.body.add_child(_squad_block(o))

	card.body.add_child(UiKit.separator())
	card.body.add_child(_board_block(o))

	card.body.add_child(UiKit.vspacer())
	var take := UiKit.primary("Prendre la direction de %s" % o.name, func():
		game().choose_org(o.id)
		navigate("home"))
	take.custom_minimum_size = Vector2(0, 38)
	card.body.add_child(take)
	return card.panel


## Les disciplines de la maison. Une structure esport est rarement mono-jeu :
## on affiche donc TOUTES ses sections, y compris celles que le moteur ne sait
## pas encore simuler — les cacher donnerait une image fausse de ce qu'on
## reprend.
func _sections_block(o: Organization) -> Control:
	var v := UiKit.vbox(5)
	v.add_child(UiKit.caption("Sections de la structure"))
	for g in o.games:
		var game_id := str(g)
		var playable := GameCatalog.playable(game_id)
		var row := UiKit.hbox(8)
		row.add_child(UiKit.pill(GameCatalog.short(game_id),
			GameCatalog.color(game_id), true))
		var l := UiKit.label(GameCatalog.label(game_id), UiKit.FS_BODY_L,
			UiKit.TEXT if playable else UiKit.TEXT_DIM)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(UiKit.pill("jouable" if playable else "non simulée",
			UiKit.GOOD if playable else UiKit.TEXT_FAINT, playable))
		v.add_child(row)
	if not o.upcoming_games().is_empty():
		v.add_child(UiKit.wrap(
			"Les sections non simulées existent dans la structure et pèsent "
			+ "sur son image, mais ne se dirigent pas encore.",
			UiKit.FS_SMALL, UiKit.TEXT_FAINT))
	return v


func _squad_block(o: Organization) -> Control:
	var w := world()
	var v := UiKit.vbox(4)
	var r := w.main_roster(o.id, "valorant")
	if r == null:
		v.add_child(UiKit.label("Aucun effectif Valorant.", UiKit.FS_BODY,
			UiKit.TEXT_FAINT))
		return v

	var module := w.module_for(r.game_id)
	var head := UiKit.hbox(8)
	head.add_child(UiKit.caption("Effectif Valorant"))
	head.add_child(UiKit.spacer())
	head.add_child(UiKit.label("%d joueurs" % r.size(), UiKit.FS_SMALL,
		UiKit.TEXT_FAINT))
	v.add_child(head)

	# Avant la reprise, on montre l'effectif tel qu'il est : le brouillard du
	# scouting ne commence qu'une fois la structure entre vos mains.
	var players := w.players_of(r.id)
	players.sort_custom(func(a: Player, b: Player):
		return a.current_ability > b.current_ability)
	for p in players.slice(0, 6):
		var row := UiKit.hbox(8)
		row.add_child(UiKit.label(p.display_name(), UiKit.FS_BODY_L,
			UiKit.TEXT if r.starters.has(p.id) else UiKit.TEXT_DIM,
			r.starters.has(p.id)))
		if p.is_igl:
			row.add_child(UiKit.pill("IGL", UiKit.INFO))
		row.add_child(UiKit.spacer())
		row.add_child(UiKit.label(module.role_label(r.role_of(p)),
			UiKit.FS_SMALL, UiKit.TEXT_DIM))
		row.add_child(UiKit.label("%d ans" % p.age(w.today), UiKit.FS_SMALL,
			UiKit.TEXT_FAINT))
		v.add_child(row)
	return v


func _board_block(o: Organization) -> Control:
	var v := UiKit.vbox(4)
	v.add_child(UiKit.caption("Ce que la direction attendra"))
	var objectives := BoardSystem.season_objectives(world(), o)
	if objectives.is_empty():
		v.add_child(UiKit.label("Aucun objectif formulé.", UiKit.FS_BODY,
			UiKit.TEXT_FAINT))
	for obj_v in objectives:
		var obj: Dictionary = obj_v
		v.add_child(_bullet(str(obj.get("label", ""))))
	return v


func _bullet(text: String) -> Control:
	var h := UiKit.hbox(7)
	h.add_child(UiKit.label("—", UiKit.FS_BODY, UiKit.TEXT_FAINT))
	var l := UiKit.wrap(text, UiKit.FS_BODY, UiKit.TEXT_DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	return h


# ============================================================================

## Position d'une valeur dans une liste triée, ramenée à 0..1.
func _rank_of(sorted_values: Array, value: int) -> float:
	if sorted_values.size() < 2:
		return 0.5
	return float(sorted_values.find(value)) / float(sorted_values.size() - 1)


## Deux ingrédients : le rang dans la ligue, et le nombre de mois que la
## trésorerie couvre. Une écurie bien classée mais à sec reste un piège, et un
## petit club solvable reste jouable.
func _difficulty(o: Organization, rank: float) -> Dictionary:
	var monthly := FinanceSystem.fixed_monthly_cost(world(), o)
	var runway := float(o.cash()) / float(maxi(monthly, 1))
	var score := rank * 0.62 + clampf(runway / 9.0, 0.0, 1.0) * 0.38
	if score > 0.72:
		return {"text": "Confortable", "color": UiKit.GOOD, "sort": score}
	if score > 0.48:
		return {"text": "Équilibrée", "color": UiKit.TEXT, "sort": score}
	if score > 0.26:
		return {"text": "Exigeante", "color": UiKit.WARN, "sort": score}
	return {"text": "Survie", "color": UiKit.BAD, "sort": score}


func _short(n: int) -> String:
	if n >= 1_000_000:
		return "%s M" % String.num(float(n) / 1_000_000.0, 1)
	if n >= 1000:
		return "%d k" % int(n / 1000)
	return str(n)
