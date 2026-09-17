extends Screen

## Choix de la structure à reprendre.
##
## Deux temps, comme dans les gestionnaires de football : on parcourt les
## maisons à gauche, on en inspecte une à droite, et on ne s'engage qu'après
## avoir vu ce qu'on hérite — l'effectif, les moyens, les sections sur les
## autres jeux et ce que la direction attend.
##
## La navigation est un FILTRE, pas une arborescence : un étage, une région,
## une recherche. Voir `_toolbar` pour ce que ça remplace et pourquoi.
##
## L'écran précédent (StartScreen) a déjà créé le monde : ici, tout est réel.

## Étages proposés. On ne propose que les deux du haut — on reprend une
## structure établie, on ne reprend pas une équipe de circuit ouvert (pour ça,
## il y a « fonder »). Le deuxième d'abord : c'est la campagne que l'écran
## recommande.
const TIERS := [[2, "Deuxième division"], [1, "Élite"]]

const REGIONS := [["", "Toutes régions"], ["EMEA", "EMEA"],
	["AMERICAS", "Amériques"], ["PACIFIC", "Pacifique"], ["CHINA", "Chine"]]


## Les ligues d'un étage, LUES DANS LES DONNÉES : ajouter une discipline n'a
## demandé aucune ligne ici.
func _leagues_of(game_id: String, tier: int) -> Array[String]:
	var out: Array[String] = []
	for slot_v in SeasonBuilder.league_slots(game_id):
		var slot: Dictionary = slot_v
		if int(slot["tier"]) == tier and not out.has(str(slot["key"])):
			out.append(str(slot["key"]))
	return out


func _league_label(game_id: String, key: String) -> String:
	for cid in world().competitions:
		var c: Competition = world().competitions[cid]
		if c.key == key and c.game_id == game_id:
			return c.short_name
	return key


func build() -> void:
	add_child(page_header("Choisir une structure",
		"Cliquez une carte pour l'inspecter, puis confirmez la reprise.", [
			UiKit.ghost("◀ Changer d'univers", func():
				game().abandon_world()),
		]))

	var state := ui("newgame")

	# La discipline d'abord : c'est la seule question qui change vraiment de
	# jeu. Le reste est un filtre, pas une navigation.
	var games: Array = []
	for g in GameRegistry.all_ids():
		games.append([g, GameCatalog.label(str(g))])
	var game_id := str(games[0][0])
	if games.size() > 1:
		add_child(tab_bar("newgame.game", games, game_id))
		game_id = current_tab("newgame.game", game_id)

	add_child(_toolbar(state, game_id))

	var parts := split(420)
	var main: VBoxContainer = parts[0]
	var side: VBoxContainer = parts[1]

	var all := _candidates(game_id, int(str(state.get("tier", "2"))))
	var orgs := _filtered(all, str(state.get("region", "")),
		str(state.get("q", "")))
	if orgs.is_empty():
		main.add_child(UiKit.empty_state(
			"Aucune structure ne correspond." if not all.is_empty()
				else "Aucune structure à cet étage.",
			"Élargissez la région, ou effacez la recherche."
				if not all.is_empty()
				else "L'univers actif ne le renseigne peut-être pas."))
		side.add_child(UiKit.empty_state("Rien à inspecter."))
		return

	main.add_child(_org_grid(orgs, all))
	# Le conseil suit l'étage qu'on regarde : le même texte sur les deux
	# disait « commencez par le deuxième étage » à qui venait justement de
	# choisir l'élite.
	main.add_child(UiKit.wrap(
		"La campagne consiste à monter dans l'élite par le barrage de fin de "
		+ "saison. Moins de moyens, mais une direction patiente : c'est l'étage "
		+ "que cet écran recommande pour une première carrière."
		if int(str(state.get("tier", "2"))) == 2 else
		"L'élite donne des moyens immédiats, un calendrier international et "
		+ "une direction bien moins patiente : ici, finir cinquième est déjà "
		+ "un échec.", UiKit.FS_SMALL, UiKit.TEXT_FAINT))

	side.add_child(_detail_card(_selected_entry(orgs)))


## La barre de navigation : étage, région, recherche.
##
## ELLE REMPLACE UN RUBAN DE HUIT ONGLETS de codes de ligue (« CHAL CN »,
## « PRO PAC »…), et ce n'était pas qu'une question de goût : on ne pouvait
## voir qu'une ligue à la fois, il fallait connaître le circuit pour naviguer,
## et trouver une structure par son nom demandait de deviner sa région.
##
## Les trois contrôles répondent aux trois vraies questions : à quel niveau je
## veux commencer, dans quelle partie du monde, et — si j'ai déjà une idée —
## laquelle. La recherche est ce qui change le plus : elle traverse les quatre
## régions d'un coup.
func _toolbar(state: Dictionary, game_id: String) -> Control:
	var bar := UiKit.hbox(10)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var tiers: Array = []
	for t_v in TIERS:
		var t: Array = t_v
		tiers.append([str(t[0]), str(t[1])])
	bar.add_child(UiKit.tabs(tiers, state, "tier", func(_k):
		refresh(), "2"))
	bar.add_child(UiKit.vrule(18))

	var regions: Array = []
	for r_v in REGIONS:
		var r: Array = r_v
		# Une région sans aucune structure à cet étage ne sert qu'à décevoir.
		if str(r[0]) != "" and _candidates(game_id,
				int(str(state.get("tier", "2"))), str(r[0])).is_empty():
			continue
		regions.append([str(r[0]), str(r[1])])
	bar.add_child(UiKit.tabs(regions, state, "region", func(_k):
		refresh(), ""))

	bar.add_child(UiKit.spacer())
	var q := str(state.get("q", ""))
	var search := UiKit.line_edit("Rechercher une structure…", q, 230)
	# `refresh()` détruit le champ, donc le signal qui est en train de courir :
	# on repousse la reconstruction à la fin de la trame, et on redonne le
	# focus au champ neuf, sinon on ne pourrait taper qu'une lettre à la fois.
	search.text_changed.connect(func(t: String):
		state["q"] = t
		state["q_focus"] = true
		call_deferred("refresh"))
	if bool(state.get("q_focus", false)):
		search.call_deferred("grab_focus")
		search.call_deferred("set", "caret_column", q.length())
	bar.add_child(search)
	if q != "":
		bar.add_child(UiKit.ghost("✕", func():
			state["q"] = ""
			state["q_focus"] = false
			refresh()))
	return bar


## Toutes les structures d'un étage, TOUTES RÉGIONS CONFONDUES.
func _candidates(game_id: String, tier: int, region: String = "") -> Array:
	var out: Array = []
	for key in _leagues_of(game_id, tier):
		for e_v in WorldGenerator.selectable_orgs(world(), key):
			var e: Dictionary = e_v
			if region == "" or str(e.get("region", "")) == region:
				out.append(e)
	out.sort_custom(func(a, b):
		return int(a["reputation"]) > int(b["reputation"]))
	return out


## Filtre de recherche : le nom ou le sigle, sans tenir compte de la casse ni
## des espaces. « nav » trouve Natus Vincere par son sigle.
func _filtered(orgs: Array, region: String, query: String) -> Array:
	var q := query.strip_edges().to_lower()
	var out: Array = []
	for e_v in orgs:
		var e: Dictionary = e_v
		if region != "" and str(e.get("region", "")) != region:
			continue
		if q != "" and not (str(e["name"]).to_lower().contains(q)
				or str(e["tag"]).to_lower().contains(q)):
			continue
		out.append(e)
	return out


# ============================================================================
# Grille de structures
# ============================================================================

## Les structures en CARTES plutôt qu'en lignes de tableau.
##
## Choisir sa maison se fait une fois par carrière, et c'est le moment le plus
## chargé du jeu : on ne compare pas des nombres, on choisit une identité. Un
## tableau de sept colonnes répond parfaitement à « laquelle a le plus de
## trésorerie » et très mal à « laquelle ai-je envie de diriger » — il n'y
## montrait ni couleurs, ni écusson, et douze structures s'y ressemblaient
## toutes. La carte porte l'écusson et la couleur de la marque ; les chiffres
## qui départagent restent dessous, et la fiche complète est à droite.
func _org_grid(orgs: Array, all: Array) -> Control:
	# La difficulté se lit PAR RAPPORT À L'ÉTAGE : en VCT tout le monde a des
	# millions en banque, et une échelle absolue afficherait « confortable »
	# douze fois de suite. Ce qui compte est de savoir où l'on part dans le
	# classement, et combien de mois on tient.
	#
	# Le barème vient de TOUT l'étage, pas des seules cartes affichées : sinon
	# filtrer sur une région ferait de sa lanterne rouge une reprise
	# « confortable », et chercher une structure par son nom la ferait changer
	# de difficulté sous le curseur.
	var reputations: Array = []
	for entry_v in all:
		reputations.append(int((entry_v as Dictionary)["reputation"]))
	reputations.sort()
	var total := all.size()

	var box := UiKit.vbox(8)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(UiKit.caption("%d structure%s affichée%s%s"
		% [orgs.size(), "s" if orgs.size() > 1 else "",
			"s" if orgs.size() > 1 else "",
			"" if orgs.size() == total else " sur %d" % total]))

	var selected := _selected_id(orgs)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	for entry_v in orgs:
		var e: Dictionary = entry_v
		var org_id := str(e["org_id"])
		grid.add_child(_org_card(e,
			_difficulty(world().org(org_id),
				_rank_of(reputations, int(e["reputation"]))),
			org_id == selected))
	box.add_child(UiKit.scroll(grid))
	return box


func _org_card(entry: Dictionary, difficulty: Dictionary,
		selected: bool) -> Control:
	var w := world()
	var org_id := str(entry["org_id"])
	var o := w.org(org_id)
	var tint := UiKit.org_color(o)

	var card := UiKit.clickable(func():
		ui("newgame")["org_id"] = org_id
		# On rend le focus à la page : sans ça, cliquer une carte le laisserait
		# dans le champ de recherche, et la frappe suivante irait filtrer la
		# liste au lieu de faire ce qu'on croit.
		ui("newgame")["q_focus"] = false
		refresh(), UiKit.BG_PANEL, tint, 0, 8, selected)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var b := Banner.new(tint)
	b.spread = 0.9
	b.intensity = 0.10
	b.edge = 3.0
	b.underline = false
	b.pad(18, 10, 12, 10)
	card.add_child(b)

	var v := UiKit.vbox(7)
	b.add_child(v)

	var head := UiKit.hbox(9)
	head.add_child(UiKit.crest(o.tag, tint, 34))
	var idn := UiKit.vbox(1)
	idn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	idn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	idn.add_child(UiKit.display(o.name.to_upper(), UiKit.FS_BODY_L,
		UiKit.TEXT, 700, 0.3))
	# La LIGUE sur la carte : la grille traverse maintenant les quatre régions
	# d'un coup, et sans elle on ne saurait plus quel championnat on reprend.
	idn.add_child(UiKit.label("%s · %s" % [o.country,
		_league_label(str(entry.get("game_id", "")),
			str(entry.get("league_key", "")))],
		UiKit.FS_SMALL, UiKit.TEXT_DIM))
	head.add_child(idn)
	v.add_child(head)

	var stars := UiKit.hbox(6)
	stars.add_child(UiKit.label(UiKit.stars(o.stars()), UiKit.FS_BODY,
		UiKit.WARN))
	stars.add_child(UiKit.spacer())
	stars.add_child(UiKit.pill(str(difficulty["text"]), difficulty["color"],
		true))
	v.add_child(stars)

	var figures := UiKit.hbox(10)
	figures.add_child(UiKit.label("%s fans" % _short(o.fanbase),
		UiKit.FS_SMALL, UiKit.TEXT_DIM))
	figures.add_child(UiKit.vrule(12))
	figures.add_child(UiKit.label(Money.fmt_short(o.cash()), UiKit.FS_SMALL,
		UiKit.GOOD if o.cash() >= 0 else UiKit.BAD))
	figures.add_child(UiKit.spacer())
	for g in o.games:
		figures.add_child(UiKit.pill(GameCatalog.short(str(g)),
			GameCatalog.color(str(g))))
	v.add_child(figures)
	return card



## Structure inspectée : celle qu'on a cliquée, sinon la première de la liste.
## On garde l'ENTRÉE entière et pas seulement l'identifiant de structure : une
## maison peut aligner deux sections, et c'est la carte cliquée qui dit laquelle
## on vient diriger.
func _selected_entry(orgs: Array) -> Dictionary:
	var wanted := str(ui("newgame").get("org_id", ""))
	for e_v in orgs:
		var e: Dictionary = e_v
		if str(e["org_id"]) == wanted:
			return e
	return orgs[0] as Dictionary


func _selected_id(orgs: Array) -> String:
	return str(_selected_entry(orgs)["org_id"])


# ============================================================================
# Fiche de la structure
# ============================================================================

func _detail_card(entry: Dictionary) -> Control:
	var w := world()
	var org_id := str(entry.get("org_id", ""))
	var roster_id := str(entry.get("roster_id", ""))
	var o := w.org(org_id)
	if o == null:
		return UiKit.empty_state("Sélectionnez une structure.")

	var card := UiKit.card("", 9, 14)
	card.panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var head := UiKit.hbox(10)
	head.add_child(UiKit.crest(o.tag, UiKit.org_color(o), 44))
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
	card.body.add_child(_sections_block(o, roster_id))

	card.body.add_child(UiKit.separator())
	card.body.add_child(_squad_block(o, roster_id))

	card.body.add_child(UiKit.separator())
	card.body.add_child(_board_block(o))

	card.body.add_child(UiKit.vspacer())
	var take := UiKit.primary("Prendre la direction de %s" % o.name, func():
		game().choose_org(o.id, roster_id)
		navigate("home"))
	take.custom_minimum_size = Vector2(0, 38)
	card.body.add_child(take)
	return card.panel


## Les disciplines de la maison. Une structure esport est rarement mono-jeu :
## on affiche donc TOUTES ses sections, y compris celles que le moteur ne sait
## pas encore simuler — les cacher donnerait une image fausse de ce qu'on
## reprend.
func _sections_block(o: Organization, roster_id: String) -> Control:
	var w := world()
	var taken := w.roster(roster_id)
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
		# Dire laquelle on reprend : une maison à deux sections se dirige
		# entièrement, mais on entre par une équipe, et c'est celle-là qui
		# s'ouvre au premier écran.
		if taken != null and taken.game_id == game_id:
			row.add_child(UiKit.pill("vous entrez ici", UiKit.ACCENT, true))
		else:
			row.add_child(UiKit.pill("jouable" if playable else "non simulée",
				UiKit.GOOD if playable else UiKit.TEXT_FAINT, playable))
		v.add_child(row)
	if not o.upcoming_games().is_empty():
		v.add_child(UiKit.wrap(
			"Les sections non simulées existent dans la structure et pèsent "
			+ "sur son image, mais ne se dirigent pas encore.",
			UiKit.FS_SMALL, UiKit.TEXT_FAINT))
	return v


func _squad_block(o: Organization, roster_id: String) -> Control:
	var w := world()
	var v := UiKit.vbox(4)
	var r := w.roster(roster_id)
	if r == null or r.org_id != o.id:
		r = WorldGenerator.flagship_roster(w, o)
	if r == null:
		v.add_child(UiKit.label("Aucun effectif.", UiKit.FS_BODY,
			UiKit.TEXT_FAINT))
		return v

	var module := w.module_for(r.game_id)
	var head := UiKit.hbox(8)
	head.add_child(UiKit.caption("Effectif %s" % GameCatalog.label(r.game_id)))
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
