class_name App
extends Control

## Coquille de l'application : barre supérieure, navigation, zone de contenu.
##
## Trois zones fixes, comme dans les gestionnaires modernes :
##   - une BARRE HAUTE qui ne bouge jamais (identité, date, argent, Continuer) ;
##   - une COLONNE de navigation groupée par thème ;
##   - une zone de contenu précédée d'un fil d'Ariane avec retour arrière.
##
## L'état d'affichage (onglet actif d'un écran, tri d'un tableau, filtre) vit
## ICI et pas dans l'écran : un écran est détruit et reconstruit à chaque
## rafraîchissement, il ne peut donc rien mémoriser. Voir `ui_state()`.

const SCREENS := {
	"home": preload("res://src/ui/screens/HomeScreen.gd"),
	"club": preload("res://src/ui/screens/ClubScreen.gd"),
	"squad": preload("res://src/ui/screens/SquadScreen.gd"),
	"player": preload("res://src/ui/screens/PlayerScreen.gd"),
	"tactics": preload("res://src/ui/screens/TacticsScreen.gd"),
	"training": preload("res://src/ui/screens/TrainingScreen.gd"),
	"dynamics": preload("res://src/ui/screens/DynamicsScreen.gd"),
	"calendar": preload("res://src/ui/screens/CalendarScreen.gd"),
	"competition": preload("res://src/ui/screens/CompetitionScreen.gd"),
	"transfers": preload("res://src/ui/screens/TransfersScreen.gd"),
	"negotiation": preload("res://src/ui/screens/NegotiationScreen.gd"),
	"finance": preload("res://src/ui/screens/FinanceScreen.gd"),
	"staff": preload("res://src/ui/screens/StaffScreen.gd"),
	"facilities": preload("res://src/ui/screens/FacilitiesScreen.gd"),
	"inbox": preload("res://src/ui/screens/InboxScreen.gd"),
	"match": preload("res://src/ui/screens/MatchScreen.gd"),
}

## Navigation : [section, [[clé, libellé, glyphe], …]]
##
## Le glyphe n'est pas décoratif : à treize entrées, un menu de texte seul se
## relit intégralement à chaque fois, alors qu'une forme se reconnaît de loin et
## finit par se cliquer sans lecture. On s'en tient à des symboles présents dans
## les polices système courantes — un glyphe manquant s'afficherait en carré
## vide, ce qui serait pire que pas de glyphe du tout.
const NAV_GROUPS := [
	["Direction", [
		["home", "Accueil", "⌂"],
		["club", "Structure", "◈"],
		["staff", "Encadrement", "✦"],
		["finance", "Finances", "€"],
		["facilities", "Infrastructures", "▦"],
		# Pas d'enveloppe « ✉ » : les polices système la rendent en émoji
		# COULEUR, et une pastille rose au milieu d'un jeu de symboles
		# monochromes saute aux yeux comme une erreur. On reste dans le bloc
		# Geometric Shapes, dont tous les signes ci-dessus sont tirés.
		["inbox", "Messages", "◫"],
	]],
	["Équipe", [
		["squad", "Effectif", "▣"],
		["tactics", "Tactique", "⊞"],
		["training", "Entraînement", "▲"],
		["dynamics", "Vestiaire", "◍"],
	]],
	["Compétition", [
		["calendar", "Calendrier", "▤"],
		["competition", "Classements", "≡"],
	]],
	["Recrutement", [
		["transfers", "Marché", "⇄"],
	]],
]

const TITLES := {
	"home": "Accueil", "club": "Structure",
	"squad": "Effectif", "player": "Fiche joueur",
	"tactics": "Tactique", "training": "Entraînement", "dynamics": "Vestiaire",
	"calendar": "Calendrier", "competition": "Classements",
	"transfers": "Marché", "negotiation": "Négociation",
	"finance": "Finances",
	"staff": "Encadrement",
	"facilities": "Infrastructures", "inbox": "Messages",
	"match": "Compte rendu de match",
}

var game: Node = null
var current_screen: Screen = null
var current_name := "home"
var current_args := {}

## Mémoire d'affichage, partagée par tous les écrans : "squad.view",
## "squad.sort", "player.tab"… Purement cosmétique, jamais sauvegardée.
var view_state := {}

## Transitions d'écran. Coupées pendant les captures (voir DevShots) : une
## image prise au milieu d'un fondu n'est pas reproductible, et toute la valeur
## des captures tient à ce qu'elles montrent deux fois la même chose.
var transitions := true

var _history: Array = []
var _forward: Array = []

var _identity: HBoxContainer
var _clock: HBoxContainer
var _actions: HBoxContainer
var _crumb: HBoxContainer
var _topbar: Control
var _banner: Banner
var _sidebar: PanelContainer
var _crumb_bar: PanelContainer
var _section_bar: PanelContainer
var _sections: HBoxContainer
var _content: MarginContainer
var _nav_box: VBoxContainer


func _ready() -> void:
	game = get_node("/root/Game")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_shell()
	game.state_changed.connect(_on_state_changed)
	game.world_loaded.connect(_on_state_changed)

	# Mode capture d'écran (développement) : voir src/ui/DevShots.gd
	if DevShots.is_requested():
		await DevShots.run(self, game)
		return

	if game.has_world() and game.world.player_org_id != "":
		navigate("home")
	else:
		show_front()


## Noms des écrans navigables, dans l'ordre du menu.
func screen_names() -> Array[String]:
	var out: Array[String] = []
	for group in NAV_GROUPS:
		for entry in (group as Array)[1]:
			out.append(str((entry as Array)[0]))
	for k in SCREENS:
		if not out.has(str(k)):
			out.append(str(k))
	return out


## Dictionnaire d'état persistant pour un écran (tri, onglet, filtre).
## Toujours passer par ici : un `var` d'écran est perdu au rafraîchissement.
func ui_state(key: String) -> Dictionary:
	if not view_state.has(key):
		view_state[key] = {}
	return view_state[key]


# ============================================================================
# Construction
# ============================================================================

func _build_shell() -> void:
	# Le thème est posé à la RACINE : il descend ensuite dans tout l'arbre, y
	# compris dans les contrôles que l'on ne construit pas soi-même
	# (info-bulles, listes déroulantes). Sans lui, ceux-là garderaient la
	# police par défaut de Godot au milieu du reste.
	theme = Typography.theme()

	var bg := ColorRect.new()
	bg.color = UiKit.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := UiKit.vbox(0)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	root.add_child(_build_topbar())

	var body := UiKit.hbox(0)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	body.add_child(_build_sidebar())

	var right := UiKit.vbox(0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	right.add_child(_build_crumb_bar())
	right.add_child(_build_section_bar())

	_content = MarginContainer.new()
	_content.add_theme_constant_override("margin_left", 16)
	_content.add_theme_constant_override("margin_right", 16)
	_content.add_theme_constant_override("margin_top", 12)
	_content.add_theme_constant_override("margin_bottom", 14)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_content)


## La barre haute est elle-même un BANDEAU incliné : c'est la surface que le
## joueur a sous les yeux en permanence, donc celle qui doit porter la couleur
## de sa structure. Le bandeau étant un MarginContainer, il met en page son
## unique enfant comme n'importe quel conteneur.
func _build_topbar() -> Control:
	_banner = Banner.new(UiKit.ACCENT)
	_banner.base = UiKit.BG_SOFT
	_banner.spread = 0.30
	_banner.edge = 0.0          # le liseré vif est porté par l'écusson
	_banner.pad(14, 0, 14, 0)
	_topbar = _banner

	var h := UiKit.hbox(16)
	h.custom_minimum_size = Vector2(0, 62)
	_banner.add_child(h)

	_identity = UiKit.hbox(11)
	_identity.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_identity)
	h.add_child(UiKit.spacer())
	_clock = UiKit.hbox(16)
	_clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_clock)
	h.add_child(UiKit.spacer())
	_actions = UiKit.hbox(7)
	_actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_actions)
	return _topbar


func _build_sidebar() -> Control:
	_sidebar = PanelContainer.new()
	var p := _sidebar
	p.add_theme_stylebox_override("panel", _flat(UiKit.BG_SOFT, 1, 0))
	p.custom_minimum_size = Vector2(186, 0)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 8)
	m.add_theme_constant_override("margin_right", 8)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_bottom", 10)
	p.add_child(m)
	_nav_box = UiKit.vbox(2)
	m.add_child(_nav_box)
	return p


func _build_crumb_bar() -> Control:
	_crumb_bar = PanelContainer.new()
	var p := _crumb_bar
	p.add_theme_stylebox_override("panel", _flat(UiKit.BG, 0, 1))
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 12)
	m.add_theme_constant_override("margin_right", 12)
	m.add_theme_constant_override("margin_top", 5)
	m.add_theme_constant_override("margin_bottom", 5)
	p.add_child(m)
	_crumb = UiKit.hbox(8)
	_crumb.custom_minimum_size = Vector2(0, 26)
	m.add_child(_crumb)
	return p


## Barre des SECTIONS de la structure : une structure esport aligne plusieurs
## équipes (autres disciplines, académie), et toute la partie « Équipe » du
## menu s'applique à celle qui est sélectionnée ici.
##
## La barre est masquée quand il n'y a qu'une section : une barre d'onglets à
## un seul onglet n'apprend rien et vole de la hauteur.
func _build_section_bar() -> Control:
	_section_bar = PanelContainer.new()
	_section_bar.add_theme_stylebox_override("panel", _flat(UiKit.BG_SOFT, 0, 1))
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 12)
	m.add_theme_constant_override("margin_right", 12)
	m.add_theme_constant_override("margin_top", 4)
	m.add_theme_constant_override("margin_bottom", 4)
	_section_bar.add_child(m)
	_sections = UiKit.hbox(6)
	m.add_child(_sections)
	_section_bar.visible = false
	return _section_bar


func _rebuild_sections() -> void:
	if _sections == null:
		return
	for c in _sections.get_children():
		c.queue_free()
	if not game.has_world() or game.my_org() == null:
		_section_bar.visible = false
		return
	var entries: Array = game.sections()
	_section_bar.visible = entries.size() > 1
	if entries.size() <= 1:
		return

	_sections.add_child(UiKit.caption("Sections"))
	for entry_v in entries:
		var entry: Dictionary = entry_v
		_sections.add_child(_section_chip(entry))
	_sections.add_child(UiKit.spacer())
	if current_name != "club":
		_sections.add_child(UiKit.ghost("Voir la structure",
			func(): navigate("club")))


func _section_chip(entry: Dictionary) -> Control:
	var game_id := str(entry["game_id"])
	var playable := bool(entry["playable"])
	var current := bool(entry["current"])
	var color := GameCatalog.color(game_id)

	var b := Button.new()
	b.text = "  %s · %s  " % [GameCatalog.short(game_id), str(entry["detail"])]
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 24)
	b.add_theme_font_size_override("font_size", UiKit.FS_SMALL)
	var bg := Color(color.r, color.g, color.b, 0.20) if current else UiKit.BG_ROW
	var sb := UiKit.box(bg, 4, 4, color if current else UiKit.BORDER_SOFT, 1)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", UiKit.box(UiKit.BG_PANEL_HI, 4, 4,
		color, 1))
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_stylebox_override("disabled", UiKit.box(UiKit.BG, 4, 4,
		UiKit.BORDER_SOFT, 1))
	b.add_theme_color_override("font_color",
		UiKit.TEXT if current else UiKit.TEXT_DIM)
	b.add_theme_color_override("font_hover_color", UiKit.TEXT)
	b.add_theme_color_override("font_disabled_color", UiKit.TEXT_FAINT)
	if not playable:
		b.disabled = true
		b.tooltip_text = "%s : section de la structure, pas encore simulée." \
			% GameCatalog.label(game_id)
		return b
	var rid := str(entry["roster_id"])
	b.tooltip_text = "Diriger cette équipe"
	b.pressed.connect(func():
		if game.select_roster(rid):
			navigate("squad"))
	return b


## Bordure fine sur un seul côté : droite pour la colonne, bas pour les barres.
func _flat(bg: Color, right: int, bottom: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = UiKit.BORDER
	sb.border_width_right = right
	sb.border_width_bottom = bottom
	return sb


# ============================================================================
# Navigation
# ============================================================================

## Marges de la zone de contenu. `-1` rétablit les marges de jeu ; `0` colle le
## contenu aux bords, pour les écrans d'avant-partie qui posent leur propre fond.
func _set_content_margins(value: int) -> void:
	if _content == null:
		return
	var sides := {"left": 16, "right": 16, "top": 12, "bottom": 14}
	for side in sides:
		_content.add_theme_constant_override("margin_" + str(side),
			int(sides[side]) if value < 0 else value)


## Barre haute, menu et fil d'Ariane : visibles en partie, cachés avant.
func _set_chrome_visible(on: bool) -> void:
	for panel in [_topbar, _sidebar, _crumb_bar]:
		if panel != null:
			panel.visible = on
	if not on and _section_bar != null:
		_section_bar.visible = false


func navigate(screen_name: String, args: Dictionary = {}) -> void:
	if not SCREENS.has(screen_name):
		return
	if current_screen != null and is_instance_valid(current_screen):
		_history.append([current_name, current_args.duplicate()])
		if _history.size() > 30:
			_history.pop_front()
		_forward.clear()
	_show(screen_name, args)


func go_back() -> void:
	if _history.is_empty():
		return
	_forward.append([current_name, current_args.duplicate()])
	var entry: Array = _history.pop_back()
	_show(str(entry[0]), entry[1])


func go_forward() -> void:
	if _forward.is_empty():
		return
	_history.append([current_name, current_args.duplicate()])
	var entry: Array = _forward.pop_back()
	_show(str(entry[0]), entry[1])


func _show(screen_name: String, args: Dictionary) -> void:
	_set_chrome_visible(true)
	_set_content_margins(-1)
	current_name = screen_name
	current_args = args
	for c in _content.get_children():
		c.queue_free()
	var scr: Screen = SCREENS[screen_name].new()
	scr.setup(self)
	for k in args:
		scr.set(k, args[k])
	_content.add_child(scr)
	current_screen = scr
	scr.refresh()
	_rebuild_chrome()
	_play_enter(scr)


## Fondu d'entrée d'un écran.
##
## Un écran est reconstruit INTÉGRALEMENT à chaque navigation (voir Screen) :
## sans transition, le remplacement est un à-coup sec, et en parcourant une
## barre d'onglets on a l'impression que l'interface clignote. Cent vingt
## millisecondes suffisent à lier les deux états — au-delà, on attend
## l'interface au lieu de la piloter.
##
## Seule l'opacité est animée : la position d'un écran est décidée par le
## MarginContainer qui le contient, et la lui disputer dans un tween produirait
## un tremblement à chaque redimensionnement.
func _play_enter(scr: Control) -> void:
	if not transitions:
		return
	scr.modulate.a = 0.0
	var t := create_tween()
	t.set_ease(Tween.EASE_OUT)
	t.set_trans(Tween.TRANS_CUBIC)
	t.tween_property(scr, "modulate:a", 1.0, 0.12)


func _on_state_changed() -> void:
	if not game.has_world() or game.world.player_org_id == "":
		show_front()
		return
	if current_screen != null and is_instance_valid(current_screen):
		current_screen.refresh()
	_rebuild_chrome()


func _rebuild_chrome() -> void:
	_rebuild_topbar()
	_rebuild_nav()
	_rebuild_crumb()
	_rebuild_sections()


# ============================================================================
# Barre supérieure
# ============================================================================

func _rebuild_topbar() -> void:
	for box in [_identity, _clock, _actions]:
		for c in box.get_children():
			c.queue_free()
	if not game.has_world():
		return
	var w: World = game.world
	var o: Organization = game.my_org()
	if o == null:
		return

	# La barre porte la couleur de la maison : c'est le fil qui relie tous les
	# écrans entre eux et qui fait qu'on reconnaît « sa » partie au premier
	# coup d'œil.
	var tint := UiKit.org_color(o)
	if _banner != null:
		_banner.tint = tint

	_identity.add_child(UiKit.crest(o.tag, tint, 38))
	var idn := UiKit.vbox(1)
	idn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	idn.add_child(UiKit.display(o.name, UiKit.FS_H3, UiKit.TEXT, 700,
		UiKit.TRACK_TITLE))
	idn.add_child(UiKit.label(_identity_line(w, o), UiKit.FS_SMALL,
		UiKit.TEXT_DIM))
	_identity.add_child(idn)

	# Les indicateurs sont séparés par des filets : quatre cadrans qu'on lit
	# d'un regard valent mieux qu'une ligne de texte où tout se confond.
	_clock.add_child(UiKit.kpi("Date", GameDate.format_full(w.today)))
	_clock.add_child(UiKit.vrule())

	var cash := o.cash()
	_clock.add_child(UiKit.kpi("Trésorerie", Money.fmt(cash),
		UiKit.GOOD if cash >= 0 else UiKit.BAD))
	_clock.add_child(UiKit.vrule())

	var monthly := FinanceSystem.projected_monthly_result(w, o)
	_clock.add_child(UiKit.kpi("Résultat mensuel",
		"%s / mois" % Money.fmt_short(monthly),
		UiKit.GOOD if monthly >= 0 else UiKit.BAD))

	var next := _next_match_label(w)
	if next != "":
		_clock.add_child(UiKit.vrule())
		_clock.add_child(UiKit.kpi("Prochain match", next, UiKit.ACCENT))

	_actions.add_child(UiKit.ghost("Sauvegarder",
		func(): game.save_game("partie1")))
	_actions.add_child(UiKit.button("1 semaine", func(): game.advance_days(7)))
	_actions.add_child(UiKit.button("Prochain match",
		func(): game.advance_to_next_match()))
	var go := UiKit.primary("CONTINUER  ▶", func(): game.advance_day())
	go.custom_minimum_size = Vector2(132, 36)
	_actions.add_child(go)


## Deuxième ligne de la barre haute : la compétition, et la section dirigée dès
## qu'il y en a plusieurs — sinon on ne saurait pas de quelle équipe parlent
## les écrans « Effectif » ou « Entraînement ».
func _identity_line(w: World, o: Organization) -> String:
	var league := _league_name(w, o)
	var r: Roster = game.my_roster()
	if r == null:
		return league
	var extra: Array[String] = []
	if o.games.size() > 1:
		extra.append(GameCatalog.label(r.game_id))
	if r.is_academy:
		extra.append("académie")
	if extra.is_empty():
		return league
	return "%s · %s" % [league, " · ".join(extra)]


func _league_name(w: World, o: Organization) -> String:
	var r: Roster = game.my_roster()
	if r == null:
		return "—"
	for cid in r.competition_ids:
		var c := w.competition(cid)
		if c != null and c.kind == Competition.Kind.LEAGUE:
			return c.name
	var c2 := w.competition(r.competition_ids[0]) if not r.competition_ids.is_empty() else null
	return c2.name if c2 != null else r.region


func _next_match_label(w: World) -> String:
	var r: Roster = game.my_roster()
	if r == null:
		return ""
	var best: Fixture = null
	for fid in w.fixtures:
		var f: Fixture = w.fixtures[fid]
		if f.played or f.day < w.today:
			continue
		if f.home_id != r.id and f.away_id != r.id:
			continue
		if best == null or f.day < best.day:
			best = f
	if best == null:
		return ""
	var other_id := best.away_id if best.home_id == r.id else best.home_id
	var other := w.roster(other_id)
	var other_org := w.org(other.org_id) if other != null else null
	var days := best.day - w.today
	var when := "aujourd'hui" if days == 0 else ("demain" if days == 1
		else "dans %d j" % days)
	return "%s · %s" % [other_org.name if other_org != null else "à définir", when]


# ============================================================================
# Colonne de navigation
# ============================================================================

func _rebuild_nav() -> void:
	for c in _nav_box.get_children():
		c.queue_free()
	if not game.has_world():
		return
	var tint := UiKit.org_color(game.my_org())
	for group in NAV_GROUPS:
		var section := str((group as Array)[0])
		_nav_box.add_child(UiKit.gap(3))
		var head := UiKit.caption(section)
		head.custom_minimum_size = Vector2(0, 19)
		_nav_box.add_child(head)
		for entry in (group as Array)[1]:
			var e: Array = entry
			var key := str(e[0])
			var text := str(e[1])
			var icon := str(e[2]) if e.size() > 2 else "·"
			var badge := ""
			if key == "inbox":
				var n: int = game.unread_count()
				if n > 0:
					badge = str(n)
			_nav_box.add_child(_nav_button(key, text, icon, badge, tint))
		_nav_box.add_child(UiKit.gap(7))

	_nav_box.add_child(UiKit.vspacer())
	if game.last_player_result != null:
		_nav_box.add_child(_nav_button("match", "Dernier match", "★", "", tint))


## Une entrée de menu est un HBox (glyphe · libellé · pastille) posé DANS un
## bouton, et non un `Button.text` : il n'y a pas d'autre façon de teinter le
## glyphe indépendamment du libellé, ni d'aligner tous les libellés sur la même
## colonne quelle que soit la largeur du symbole.
func _nav_button(key: String, text: String, icon: String, badge: String,
		tint: Color) -> Control:
	var active := key == current_name

	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 30)
	var sb := UiKit.box(UiKit.BG_PANEL if active else Color(0, 0, 0, 0), 5, 0)
	if active:
		# Le liseré gauche prend la couleur de la structure : la page courante
		# est marquée par la maison du joueur, pas par une couleur de logiciel.
		sb.border_color = tint
		sb.border_width_left = 3
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover",
		UiKit.box(UiKit.BG_PANEL_HI if not active else UiKit.BG_PANEL, 5, 0))
	b.add_theme_stylebox_override("pressed", sb)
	b.pressed.connect(func(): navigate(key))

	var row := UiKit.hbox(9)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 9)
	m.add_theme_constant_override("margin_right", 8)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(row)
	b.add_child(m)
	# Un Button n'est PAS un conteneur : il ne redimensionne pas ses enfants, qui
	# resteraient à une taille nulle. L'ancrage plein cadre est ce qui fait que
	# la ligne occupe le bouton.
	m.set_anchors_preset(Control.PRESET_FULL_RECT)

	var g := UiKit.label(icon, UiKit.FS_BODY_L,
		tint if active else UiKit.TEXT_FAINT)
	g.custom_minimum_size = Vector2(14, 0)
	g.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	g.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(g)

	var l := UiKit.label(text, UiKit.FS_BODY_L,
		UiKit.TEXT if active else UiKit.TEXT_DIM)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)

	if badge != "":
		row.add_child(UiKit.spacer())
		var p := UiKit.pill(badge, UiKit.ACCENT, true)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(p)
	return b


# ============================================================================
# Fil d'Ariane
# ============================================================================

func _rebuild_crumb() -> void:
	for c in _crumb.get_children():
		c.queue_free()
	if not game.has_world():
		return
	var back := UiKit.ghost("◀", func(): go_back())
	back.custom_minimum_size = Vector2(30, 24)
	back.disabled = _history.is_empty()
	_crumb.add_child(back)
	var fwd := UiKit.ghost("▶", func(): go_forward())
	fwd.custom_minimum_size = Vector2(30, 24)
	fwd.disabled = _forward.is_empty()
	_crumb.add_child(fwd)

	_crumb.add_child(UiKit.label(str(TITLES.get(current_name, current_name)),
		UiKit.FS_BODY_L, UiKit.TEXT))
	var sub := _crumb_detail()
	if sub != "":
		_crumb.add_child(UiKit.label("›", UiKit.FS_BODY_L, UiKit.TEXT_FAINT))
		_crumb.add_child(UiKit.label(sub, UiKit.FS_BODY_L, UiKit.ACCENT))
	_crumb.add_child(UiKit.spacer())

	var r: Roster = game.my_roster()
	if r != null:
		_crumb.add_child(UiKit.label("Cohésion", UiKit.FS_SMALL, UiKit.TEXT_DIM))
		_crumb.add_child(UiKit.meter(r.chemistry, 100.0, 80,
			UiKit.GOOD if r.chemistry > 65.0 else UiKit.WARN))
		var atm := DynamicsSystem.atmosphere(game.world, r)
		_crumb.add_child(UiKit.label("Vestiaire", UiKit.FS_SMALL, UiKit.TEXT_DIM))
		_crumb.add_child(UiKit.pill(DynamicsSystem.atmosphere_label(atm),
			UiKit.GOOD if atm >= 62.0 else (UiKit.WARN if atm >= 40.0 else UiKit.BAD)))


func _crumb_detail() -> String:
	if current_name == "player":
		var pid := str(current_args.get("player_id", ""))
		var p: Player = game.world.player(pid)
		return p.display_name() if p != null else ""
	if current_name == "competition":
		var cid := str(current_args.get("competition_id", ""))
		var c: Competition = game.world.competition(cid)
		return c.name if c != null else ""
	if current_name == "negotiation":
		var n: Negotiation = game.negotiation(
			str(current_args.get("negotiation_id", "")))
		if n == null:
			return ""
		var target: Player = game.world.player(n.player_id)
		return target.display_name() if target != null else ""
	return ""


# ============================================================================
# Avant la partie
# ============================================================================

## Écrans d'avant-partie, hors navigation : la coquille est vidée et l'écran
## occupe toute la place. L'étape est choisie par l'état du monde plus le mode
## demandé — pas de machine à états séparée à tenir à jour.
const START_SCREEN := preload("res://src/ui/screens/StartScreen.gd")
const PICKER_SCREEN := preload("res://src/ui/screens/NewGameScreen.gd")
const FOUND_SCREEN := preload("res://src/ui/screens/FoundScreen.gd")


## Mode de carrière choisi sur l'écran de démarrage : "takeover" ou "found".
## Il ne sert qu'entre la création du monde et le choix de la structure.
func _front_script() -> GDScript:
	if not game.has_world():
		return START_SCREEN
	if str(ui_state("start").get("mode", "takeover")) == "found":
		return FOUND_SCREEN
	return PICKER_SCREEN


func show_front() -> void:
	for c in _content.get_children():
		c.queue_free()
	for box in [_nav_box, _identity, _clock, _actions, _crumb, _sections]:
		for c in box.get_children():
			c.queue_free()
	# Les écrans d'avant-partie occupent tout l'écran : une barre haute vide
	# et un menu inutilisable au-dessus feraient croire à un bug d'affichage.
	_set_chrome_visible(false)
	# ET jusqu'au bord : l'écran-titre pose un fond dégradé, qu'une marge
	# encadrerait d'un liseré de fond d'application — exactement l'effet
	# « fenêtre dans une fenêtre » qu'on cherche à éviter ici.
	_set_content_margins(0)
	_history.clear()
	_forward.clear()
	var scr: Screen = _front_script().new()
	scr.setup(self)
	_content.add_child(scr)
	current_screen = scr
	scr.refresh()
