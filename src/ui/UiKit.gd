class_name UiKit
extends RefCounted

## Boîte à outils d'interface.
##
## L'UI est construite EN CODE plutôt qu'en scènes .tscn. Ce n'est pas un
## raccourci : un jeu de gestion affiche des tableaux de données dont les
## colonnes changent avec la discipline (les stats de Valorant ne sont pas
## celles de League of Legends). Une table générée à partir d'une description
## de colonnes reste juste quand on ajoute un jeu ; une scène figée non.
##
## Repère visuel : habillage de DIFFUSION esport. Fond très sombre, panneaux
## étagés sur plusieurs altitudes, titres en capitales condensées, couleur de la
## structure portée par des bandeaux inclinés.
##
## Une règle gouverne tout le reste, et c'est elle qui rend l'habillage tenable
## sur un jeu de gestion : LE SPECTACLE VIT SUR LES SURFACES D'APPARAT, JAMAIS
## DANS LES DONNÉES. Écran-titre, barre haute, en-têtes d'écran, cartes de
## joueur : on y met les bandeaux, les lueurs et les grandes capitales. Un
## tableau de dix-huit colonnes, lui, reste sobre — fond calme, couleur réservée
## à la donnée. Un classement qui brille est un classement qu'on ne lit plus, et
## un jeu de gestion se lit trois heures d'affilée.

# ============================================================================
# Palette
# ============================================================================

# Altitudes. Chaque cran est un plan de profondeur, du fond de l'écran vers le
# joueur : c'est l'étagement — et non les bordures — qui doit dire ce qui est
# posé sur quoi.
const BG := Color("#090b10")            # fond application (plan le plus bas)
const BG_SOFT := Color("#0e121a")       # rails : barre haute, colonne de menu
const BG_PANEL := Color("#151a25")      # cartes
const BG_PANEL_HI := Color("#1d2430")   # en-têtes de tableau, survol
const BG_ELEV := Color("#232c3d")       # éléments détachés, menus, survol haut

const BG_ROW := Color("#121620")
const BG_ROW_ALT := Color("#161b26")
const BG_ROW_HOVER := Color("#242d3e")
const BG_ROW_SEL := Color("#2e2320")

const BORDER := Color("#28313f")
const BORDER_SOFT := Color("#1b2230")
## Filet clair posé sur l'arête haute d'un panneau : une lumière rasante venue
## du haut. C'est ce qui donne l'épaisseur sans dessiner une seule ombre de plus.
const EDGE_LIGHT := Color(1, 1, 1, 0.055)

const ACCENT := Color("#ff5a3c")        # identité esport — action, sélection
const ACCENT_DIM := Color("#8d3527")
const ACCENT_GLOW := Color("#ff7a52")
## Second accent, froid : sert à la DONNÉE qui va bien (pic de forme, record,
## meilleure note) là où l'orange dirait « clique ici ».
const ACCENT_COOL := Color("#2de2c5")
const INFO := Color("#4aa8ff")

const TEXT := Color("#eef1f7")
const TEXT_DIM := Color("#8b95a9")
const TEXT_FAINT := Color("#5c6577")

const GOOD := Color("#3fca6b")
const BAD := Color("#e8494b")
const WARN := Color("#eda63c")

# Échelle typographique : s'y tenir évite le patchwork de tailles.
const FS_MICRO := 10
const FS_SMALL := 11
const FS_BODY := 12
const FS_BODY_L := 13
const FS_LEAD := 15
const FS_H3 := 17
const FS_H2 := 22
const FS_H1 := 30
const FS_HERO := 44                     # écran-titre, score de match

# Interlettrage des capitales. Une capitale non espacée se lit mal en petit :
# les lettres se touchent et le mot devient un bloc. C'est le détail qui
# sépare un intitulé de tableau de bord d'un label de formulaire.
const TRACK_CAPS := 1.2
const TRACK_TITLE := 0.6


# ============================================================================
# Primitives de texte
# ============================================================================

static func label(text: String, size: int = FS_BODY_L, color: Color = TEXT,
		bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font",
		Typography.body_bold() if bold else Typography.body())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Texte en grotesque CONDENSÉE : titres, capitales, grands chiffres.
## C'est la police qui porte l'identité « diffusion » — voir Typography.
static func display(text: String, size: int = FS_H2, color: Color = TEXT,
		weight: int = 700, tracking: float = 0.0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Typography.display(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if tracking != 0.0:
		l.add_theme_constant_override("font_spacing_glyph", int(round(tracking)))
	return l


## Chiffre à chasse fixe. À utiliser dès qu'un nombre est EMPILÉ sous un autre
## (colonne de tableau, bilan) : sinon la virgule se déplace d'une ligne à
## l'autre et la colonne cesse d'être comparable d'un coup d'œil.
static func numeral(text: String, size: int = FS_BODY_L, color: Color = TEXT,
		bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Typography.mono(700 if bold else 400))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Titre d'écran : grandes capitales condensées.
static func title(text: String) -> Label:
	return display(text.to_upper(), FS_H1, TEXT, 700, TRACK_TITLE)


static func heading(text: String) -> Label:
	return display(text, FS_H3, TEXT, 700)


static func subtitle(text: String) -> Label:
	return label(text, FS_BODY, TEXT_DIM)


## Intitulé de section : petites capitales espacées, façon tableau de bord.
## L'interlettrage n'est pas un ornement — sans lui, dix pixels de capitales
## forment un pâté que l'œil saute au lieu de lire.
static func caption(text: String, color: Color = TEXT_FAINT) -> Label:
	return display(text.to_upper(), FS_MICRO, color, 600, TRACK_CAPS)


static func wrap(text: String, size: int = FS_BODY_L,
		color: Color = TEXT) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


# ============================================================================
# Conteneurs
# ============================================================================

static func vbox(separation: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	return v


static func hbox(separation: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	return h


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func vspacer() -> Control:
	var c := Control.new()
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func gap(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Filet VERTICAL séparant deux groupes sur une même ligne.
## Sert à découper la barre haute en cadrans lisibles : sans lui, les
## indicateurs forment une bouillie de texte alignée à la même hauteur.
static func vrule(height: int = 26, color: Color = BORDER) -> Control:
	var r := PanelContainer.new()
	r.custom_minimum_size = Vector2(1, height)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_stylebox_override("panel", box(color, 0))
	return r


## Indicateur de barre haute : intitulé en petites capitales, valeur en
## condensée. Le couple intitulé/valeur est ce qui rend un chiffre lisible sans
## le lire — on repère « TRÉSORERIE » du coin de l'œil et on ne lit que si le
## montant a changé de couleur.
static func kpi(caption_text: String, value: String,
		color: Color = TEXT, size: int = FS_LEAD) -> Control:
	var v := vbox(1)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_child(caption(caption_text))
	v.add_child(display(value, size, color, 700, 0.2))
	return v


static func separator() -> HSeparator:
	var s := HSeparator.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = BORDER
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	s.add_theme_stylebox_override("separator", sb)
	s.add_theme_constant_override("separation", 9)
	return s


## Fabrique un StyleBoxFlat arrondi et bordé, la brique visuelle du jeu.
static func box(bg: Color, radius: int = 8, margin: int = 0,
		border: Color = Color(0, 0, 0, 0), border_width: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin
	sb.content_margin_bottom = margin
	if border_width > 0:
		sb.border_color = border
		sb.set_border_width_all(border_width)
	return sb


## Variante ÉTAGÉE de `box` : ombre portée plus filet clair sur l'arête haute.
##
## Les deux vont ensemble et c'est le couple qui fait l'épaisseur. L'ombre
## décolle le panneau du fond ; le filet clair simule une lumière rasante venue
## du haut de l'écran, donc une arête. Avec l'ombre seule, un panneau sombre sur
## fond sombre paraît sale plutôt que surélevé.
static func raised(bg: Color, radius: int = 9, margin: int = 0,
		depth: int = 10, border: Color = BORDER) -> StyleBoxFlat:
	var sb := box(bg, radius, margin, border, 1)
	sb.shadow_size = depth
	sb.shadow_color = Color(0, 0, 0, 0.42)
	sb.shadow_offset = Vector2(0, depth * 0.35)
	sb.border_width_top = 1
	sb.border_color = border
	return sb


## Style de carte par défaut : coins généreux, bordure DISCRÈTE, ombre douce.
##
## Le trait d'un pixel bien contrasté autour de chaque rectangle est la
## signature visuelle du formulaire — c'est ce qui datait l'interface plus que
## tout le reste. On garde une bordure, parce qu'elle sépare deux cartes
## voisines, mais on la rend presque invisible et on confie la séparation à
## l'OMBRE : c'est ce que fait un objet posé sur un autre, et l'œil le lit sans
## qu'on ait à tracer un trait.
static func soft(bg: Color, radius: int = 11, margin: int = 12) -> StyleBoxFlat:
	var sb := box(bg, radius, margin, BORDER_SOFT, 1)
	sb.shadow_size = 12
	sb.shadow_color = Color(0, 0, 0, 0.30)
	sb.shadow_offset = Vector2(0, 3)
	return sb


## ATTENTION : un PanelContainer empile TOUS ses enfants dans le même
## rectangle. Ne lui donner qu'UN enfant (une box), jamais plusieurs.
static func panel(margin: int = 12, bg: Color = BG_PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", soft(bg, 11, margin))
	return p


## Panneau détaché du fond : à réserver aux blocs qui doivent attirer l'œil en
## premier (bandeau de tête, carte de match, encadré de décision). Tout étager
## revient à ne rien étager.
static func panel_raised(margin: int = 12, bg: Color = BG_PANEL,
		depth: int = 10) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", raised(bg, 9, margin, depth))
	return p


## Panneau CLIQUABLE, qui s'éclaire au survol.
##
## Godot n'offre rien de tel : un `Button` ne met pas ses enfants en page, un
## `PanelContainer` ne réagit pas à la souris. On combine donc les deux — un
## panneau qui écoute `gui_input` — en ne lui donnant qu'UN enfant, comme
## l'exige l'invariant de mise en page vérifié par `tools/ui_check.gd`.
##
## Rendre la CARTE ENTIÈRE cliquable, et pas seulement son bouton, est ce qui
## fait la différence entre un formulaire et un jeu : on vise une grande forme,
## pas une petite cible.
static func clickable(on_click: Callable, bg: Color = BG_PANEL,
		accent: Color = ACCENT, margin: int = 12, radius: int = 9,
		selected: bool = false) -> PanelContainer:
	var p := PanelContainer.new()
	var idle := box(bg, radius, margin, accent if selected else BORDER,
		2 if selected else 1)
	var over := box(BG_PANEL_HI, radius, margin, accent, 2)
	if selected:
		idle.shadow_size = 10
		idle.shadow_color = Color(accent.r, accent.g, accent.b, 0.28)
	p.add_theme_stylebox_override("panel", idle)
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	p.mouse_entered.connect(func():
		p.add_theme_stylebox_override("panel", over))
	p.mouse_exited.connect(func():
		p.add_theme_stylebox_override("panel", idle))
	p.gui_input.connect(func(ev: InputEvent):
		if _is_left_click(ev) and on_click.is_valid():
			on_click.call())
	return p


## Carte titrée. Renvoie le PanelContainer ; le contenu s'ajoute dans `body`.
## Usage : var c := UiKit.card("Contrat") ; c.body.add_child(...)
##         parent.add_child(c.panel)
class Card:
	var panel: PanelContainer
	var body: VBoxContainer

	func add(node: Control) -> Control:
		body.add_child(node)
		return node


static func card(title_text: String = "", separation: int = 7,
		margin: int = 12) -> Card:
	var c := Card.new()
	c.panel = panel(margin)
	var v := vbox(separation)
	c.panel.add_child(v)
	if title_text != "":
		v.add_child(caption(title_text, TEXT_DIM))
	c.body = v
	return c


# ============================================================================
# Boutons
# ============================================================================

enum BtnStyle { NORMAL, PRIMARY, GHOST, DANGER }


static func button(text: String, on_pressed: Callable = Callable(),
		style: BtnStyle = BtnStyle.NORMAL) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 30)
	b.add_theme_font_size_override("font_size", FS_BODY_L)

	var bg := BG_PANEL_HI
	var bg_hover := Color("#2b3346")
	var fg := TEXT
	match style:
		BtnStyle.PRIMARY:
			bg = ACCENT
			bg_hover = Color("#ff7358")
			fg = Color("#12151c")
		BtnStyle.GHOST:
			bg = Color(0, 0, 0, 0)
			bg_hover = BG_PANEL_HI
			fg = TEXT_DIM
		BtnStyle.DANGER:
			bg = Color("#3a1f1f")
			bg_hover = Color("#4f2727")
			fg = BAD

	var normal := box(bg, 6, 9)
	if style == BtnStyle.PRIMARY:
		# L'action principale est la seule chose de l'écran qui a le droit de
		# projeter une lueur : c'est ainsi qu'on la trouve sans la chercher.
		# Étendue à tous les boutons, la lueur ne signalerait plus rien.
		normal.shadow_size = 9
		normal.shadow_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.33)
		normal.shadow_offset = Vector2(0, 2)
		b.add_theme_font_override("font", Typography.display(700))
		b.add_theme_constant_override("font_spacing_glyph", 1)
	elif style == BtnStyle.NORMAL:
		normal.border_color = BORDER
		normal.set_border_width_all(1)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", box(bg_hover, 6, 9))
	b.add_theme_stylebox_override("pressed", box(bg_hover.darkened(0.15), 6, 9))
	b.add_theme_stylebox_override("disabled", box(BG_SOFT, 6, 9))
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_disabled_color", TEXT_FAINT)
	if on_pressed.is_valid():
		b.pressed.connect(on_pressed)
	return b


static func primary(text: String, on_pressed: Callable = Callable()) -> Button:
	return button(text, on_pressed, BtnStyle.PRIMARY)


static func ghost(text: String, on_pressed: Callable = Callable()) -> Button:
	return button(text, on_pressed, BtnStyle.GHOST)


static func danger(text: String, on_pressed: Callable = Callable()) -> Button:
	return button(text, on_pressed, BtnStyle.DANGER)


## En-tête d'écran : bandeau incliné, écusson, grand titre en capitales
## condensées, actions à droite.
##
## C'est la pièce qui fait le plus pour l'impression d'ensemble, parce qu'elle
## se répète sur les dix-neuf écrans : le joueur la voit à chaque navigation.
## Un titre posé nu sur le fond donne une page d'administration ; le même titre
## sur un bandeau aux couleurs de la maison donne un écran de jeu.
##
## `tint` est la couleur de la STRUCTURE dirigée, pas une couleur de marque du
## jeu : d'un écran à l'autre, c'est la maison du joueur qu'on doit reconnaître.
static func screen_header(title_text: String, subtitle_text: String = "",
		actions: Array = [], tint: Color = ACCENT,
		badge: Control = null) -> Control:
	var b := Banner.new(tint)
	# La marge gauche doit DÉPASSER l'inclinaison, sinon le titre vient se poser
	# sur le liseré vif et les deux se disputent le même pixel. Le bandeau fait
	# une soixantaine de pixels de haut, donc une vingtaine d'avancée : trente
	# laissent respirer.
	b.pad(30, 11, 16, 11)
	b.spread = 0.42
	b.base = BG_PANEL
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var row := hbox(13)
	b.add_child(row)

	if badge != null:
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(badge)

	var left := vbox(0)
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var t := display(title_text.to_upper(), FS_H1, TEXT, 700, TRACK_TITLE)
	left.add_child(t)
	if subtitle_text != "":
		left.add_child(label(subtitle_text, FS_BODY, TEXT_DIM))
	row.add_child(left)

	row.add_child(spacer())
	var right := hbox(6)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for a in actions:
		right.add_child(a)
	row.add_child(right)
	return b


## Étiquette colorée compacte (statut, ligue, rôle…).
static func pill(text: String, color: Color = TEXT_DIM,
		filled: bool = false) -> Control:
	var p := PanelContainer.new()
	var bg := Color(color.r, color.g, color.b, 0.18) if filled else Color(0, 0, 0, 0)
	var sb := box(bg, 4, 0, color.darkened(0.2), 1)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_child(label(text, FS_SMALL, color))
	return p


# ============================================================================
# Onglets
# ============================================================================

## Barre d'onglets pilotée par un dictionnaire d'état persistant.
## items : [["key", "Libellé"], …]  ·  state[state_key] contient l'onglet actif.
static func tabs(items: Array, state: Dictionary, state_key: String,
		on_change: Callable, default_key: String = "") -> Control:
	var active := str(state.get(state_key,
		default_key if default_key != "" else (str(items[0][0]) if not items.is_empty() else "")))
	var bar := hbox(2)
	for entry in items:
		var key := str((entry as Array)[0])
		var text := str((entry as Array)[1])
		var b := Button.new()
		b.text = text
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 29)
		b.add_theme_font_size_override("font_size", FS_BODY_L)
		var is_active := key == active
		var sb := box(BG_PANEL if is_active else Color(0, 0, 0, 0), 5, 10)
		if is_active:
			# Le liseré du bas est ce qui rend l'onglet actif lisible d'un coup
			# d'œil, bien plus que la couleur du texte.
			sb.border_color = ACCENT
			sb.border_width_bottom = 2
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", box(BG_PANEL_HI, 5, 10))
		b.add_theme_stylebox_override("pressed", sb)
		b.add_theme_color_override("font_color", TEXT if is_active else TEXT_DIM)
		b.add_theme_color_override("font_hover_color", TEXT)
		var k := key
		b.pressed.connect(func():
			state[state_key] = k
			if on_change.is_valid():
				on_change.call(k))
		bar.add_child(b)
	return bar


# ============================================================================
# Tableaux
# ============================================================================

## Tableau positionnel historique (lignes = Array de cellules).
## Conservé pour les écrans simples ; préférer `data_table` ailleurs.
static func table(columns: Array, rows: Array,
		row_clicked: Callable = Callable()) -> Control:
	var keyed: Array = []
	for row in rows:
		var d := {}
		for j in columns.size():
			d[str(j)] = (row as Array)[j] if j < (row as Array).size() else ""
		keyed.append(d)
	var cols: Array = []
	for j in columns.size():
		var c: Dictionary = (columns[j] as Dictionary).duplicate()
		c["key"] = str(j)
		c["sortable"] = false
		cols.append(c)
	return data_table(cols, keyed, {"row_clicked": row_clicked, "scroll": false})


## Tableau trié, survolé, sélectionnable.
##
## columns : [{"key", "label", "width", "align", "sortable", "expand"}]
## rows    : [{col_key: cellule, …, "_id": identifiant facultatif}]
## cellule : valeur brute, ou {"text", "color", "sort", "bold", "dim"}
## opts    : {
##   "row_clicked": Callable(index),   "scroll": bool (défaut true),
##   "state": Dictionary persistant,   "on_sort": Callable() de rafraîchissement,
##   "selected": index surligné,       "max_height": int,
##   "compact": bool }
static func data_table(columns: Array, rows: Array,
		opts: Dictionary = {}) -> Control:
	var state: Dictionary = opts.get("state", {})
	var on_sort: Callable = opts.get("on_sort", Callable())
	var sort_key := str(state.get("sort_key", ""))
	var sort_desc := bool(state.get("sort_desc", true))
	var compact := bool(opts.get("compact", false))
	var row_h := 22 if compact else 26

	var view := rows.duplicate()
	if sort_key != "":
		view.sort_custom(func(a, b):
			var va = _sort_value((a as Dictionary).get(sort_key, ""))
			var vb = _sort_value((b as Dictionary).get(sort_key, ""))
			if typeof(va) == TYPE_STRING or typeof(vb) == TYPE_STRING:
				var sa := str(va).to_lower()
				var sb2 := str(vb).to_lower()
				return sa > sb2 if sort_desc else sa < sb2
			return float(va) > float(vb) if sort_desc else float(va) < float(vb))

	var head := _row_container(BG_PANEL_HI, row_h)
	var head_cells := _cells_of(head)
	var has_labels := false
	for c in columns:
		if str((c as Dictionary).get("label", "")) != "":
			has_labels = true
	for c in columns:
		var col: Dictionary = c
		var key := str(col.get("key", ""))
		var text := str(col.get("label", ""))
		var sortable := bool(col.get("sortable", true)) and key != "" and on_sort.is_valid()
		if sortable and key == sort_key:
			text += "  ▼" if sort_desc else "  ▲"
		var cell := _cell(text, col, ACCENT if key == sort_key else TEXT_DIM,
			FS_SMALL)
		if sortable:
			cell.mouse_filter = Control.MOUSE_FILTER_STOP
			cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			var k := key
			cell.gui_input.connect(func(ev: InputEvent):
				if not _is_left_click(ev):
					return
				# Reclic sur la même colonne : on inverse le sens.
				if str(state.get("sort_key", "")) == k:
					state["sort_desc"] = not bool(state.get("sort_desc", true))
				else:
					state["sort_key"] = k
					state["sort_desc"] = true
				on_sort.call())
		head_cells.add_child(cell)

	var body := vbox(1)
	var selected := int(opts.get("selected", -1))
	var row_clicked: Callable = opts.get("row_clicked", Callable())
	for i in view.size():
		var row: Dictionary = view[i]
		var base := BG_ROW if i % 2 == 0 else BG_ROW_ALT
		if i == selected:
			base = BG_ROW_SEL
		var line := _row_container(base, row_h)
		var cells := _cells_of(line)
		for c2 in columns:
			var col2: Dictionary = c2
			cells.add_child(_build_cell(row.get(str(col2.get("key", "")), ""),
				col2, compact))
		# Le survol est ce qui fait qu'un tableau dense reste lisible : on
		# repeint le fond plutôt que d'ajouter un contrôle par-dessus.
		var hover_bg := BG_ROW_HOVER if i != selected else BG_ROW_SEL.lightened(0.06)
		line.mouse_filter = Control.MOUSE_FILTER_STOP
		line.mouse_entered.connect(func():
			line.add_theme_stylebox_override("panel", _row_style(hover_bg, row_h)))
		line.mouse_exited.connect(func():
			line.add_theme_stylebox_override("panel", _row_style(base, row_h)))
		if row_clicked.is_valid():
			line.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			var idx := i
			var payload = row.get("_id", idx)
			line.gui_input.connect(func(ev: InputEvent):
				if _is_left_click(ev):
					row_clicked.call(payload if row.has("_id") else idx))
		body.add_child(line)

	if not bool(opts.get("scroll", true)):
		var plain := vbox(1)
		if has_labels:
			plain.add_child(head)
		plain.add_child(body)
		return plain

	# Défilement : l'en-tête reste visible verticalement (il est hors du
	# ScrollContainer vertical) mais suit le défilement horizontal (les deux
	# sont dans le même ScrollContainer horizontal).
	#
	# Piège Godot : un ScrollContainer dimensionne son enfant d'après les
	# SIZE_EXPAND de L'ENFANT, pas les siens. Sans SIZE_EXPAND_FILL vertical
	# sur `inner`, celui-ci retombe à sa hauteur minimale (l'en-tête seul) et
	# le corps du tableau disparaît sans la moindre erreur.
	var inner := vbox(1)
	if has_labels:
		inner.add_child(head)
	var vscroll := ScrollContainer.new()
	vscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vscroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if opts.has("max_height"):
		vscroll.custom_minimum_size = Vector2(0, int(opts["max_height"]))
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vscroll.add_child(body)
	inner.add_child(vscroll)

	var hscroll := ScrollContainer.new()
	hscroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hscroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hscroll.add_child(inner)

	# Le tableau occupe toute la hauteur restante, mais six joueurs ne
	# remplissent pas neuf cents pixels. Sans fond propre, le vide sous la
	# dernière ligne laisse voir le fond de l'application : ça ne se lit pas
	# comme « le tableau est fini », ça se lit comme un trou dans l'écran.
	# Le cadre referme la zone et dit où le tableau s'arrête.
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", box(BG_ROW, 7, 0, BORDER, 1))
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.clip_contents = true
	frame.add_child(hscroll)
	return frame


static func _is_left_click(ev: InputEvent) -> bool:
	return ev is InputEventMouseButton \
		and (ev as InputEventMouseButton).pressed \
		and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT


static func _sort_value(v):
	if v is Dictionary:
		var d: Dictionary = v
		if d.has("sort"):
			return d["sort"]
		return str(d.get("text", ""))
	return v


static func _row_style(bg: Color, height: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	return sb


## Une ligne de tableau = un PanelContainer (le fond) contenant UN SEUL enfant,
## la HBoxContainer des cellules.
##
## Piège Godot à ne jamais réintroduire : un PanelContainer empile TOUS ses
## enfants dans le même rectangle. Y ajouter les cellules directement les
## superpose au lieu de les aligner. On passe donc toujours par _cells_of().
static func _row_container(bg: Color, height: int = 26) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _row_style(bg, height))
	p.custom_minimum_size = Vector2(0, height)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	return p


static func _cells_of(row: PanelContainer) -> HBoxContainer:
	return row.get_child(0) as HBoxContainer


## Construit une cellule : texte simple, ou descripteur enrichi.
static func _build_cell(v, col: Dictionary, compact: bool) -> Control:
	var size := FS_BODY if compact else FS_BODY_L
	if v is Control:
		var ctrl: Control = v
		ctrl.custom_minimum_size = Vector2(int(col.get("width", 100)),
			ctrl.custom_minimum_size.y)
		return ctrl
	var color := TEXT
	var text := ""
	if v is Dictionary:
		var d: Dictionary = v
		if d.has("attr"):
			return _attr_cell(d, col)
		if d.has("meter"):
			return _meter_cell(d, col)
		text = str(d.get("text", ""))
		color = d.get("color", TEXT)
		if bool(d.get("dim", false)):
			color = TEXT_DIM
		var l := _cell(text, col, color, size)
		if bool(d.get("bold", false)):
			(l as Label).add_theme_constant_override("outline_size", 3)
			(l as Label).add_theme_color_override("font_outline_color", color)
		if d.has("tooltip"):
			l.tooltip_text = str(d["tooltip"])
			l.mouse_filter = Control.MOUSE_FILTER_STOP
		return l
	return _cell(str(v), col, color, size)


static func _cell(text: String, col: Dictionary, color: Color,
		size: int) -> Control:
	var l := label(text, size, color)
	l.custom_minimum_size = Vector2(int(col.get("width", 100)), 0)
	l.clip_text = true
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	match str(col.get("align", "left")):
		"right":
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		"center":
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if bool(col.get("expand", false)):
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func _attr_cell(d: Dictionary, col: Dictionary) -> Control:
	var c := attr_box(int(d["attr"]), str(d.get("text", "")),
		bool(d.get("inverted", false)))
	c.custom_minimum_size.x = int(col.get("width", 34))
	return c


static func _meter_cell(d: Dictionary, col: Dictionary) -> Control:
	var h := hbox(6)
	h.custom_minimum_size = Vector2(int(col.get("width", 90)), 0)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var w := int(col.get("width", 90)) - 34
	h.add_child(meter(float(d["meter"]), float(d.get("max", 100.0)), w,
		d.get("color", ACCENT)))
	var l := label(str(d.get("text", "")), FS_BODY, TEXT_DIM)
	l.custom_minimum_size = Vector2(28, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(l)
	return h


# ============================================================================
# Cellules spécialisées
# ============================================================================

## Attribut 1..20 dans une pastille colorée, façon Football Manager.
## `override_text` permet d'afficher une fourchette de scouting ("12-15").
## `inverted` sert aux attributs où une valeur haute est mauvaise (ego,
## fragilité, risque médiatique) : voir Attributes.NEGATIVE.
static func attr_box(value: int, override_text: String = "",
		inverted: bool = false) -> Control:
	var p := PanelContainer.new()
	var c := attr_color(21 - value) if inverted else attr_color(value)
	var sb := box(Color(c.r, c.g, c.b, 0.16), 4, 0, Color(c.r, c.g, c.b, 0.55), 1)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(34, 19)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := label(override_text if override_text != "" else str(value),
		FS_BODY, c)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p


## Cinq paliers plutôt qu'un dégradé continu : l'œil compare des catégories
## bien plus vite que des nuances.
static func attr_color(v: int) -> Color:
	if v <= 5:
		return Color("#d64545")
	if v <= 9:
		return Color("#dd8038")
	if v <= 12:
		return Color("#d9c04a")
	if v <= 15:
		return Color("#8fc44f")
	if v <= 17:
		return Color("#46c46a")
	return Color("#37d6c0")


## Autonomie financière en toutes lettres, avec sa couleur.
##
## Au-delà de deux ans le chiffre exact n'apprend plus rien — et une structure
## qui n'a pas encore de salaires en afficherait des centaines de mois, ce qui
## se lirait comme « tout va bien » alors qu'elle n'a pas d'équipe.
static func runway_text(months: int, with_suffix: bool = false) -> String:
	if months < 0:
		return "rentable"
	var suffix := " d'autonomie" if with_suffix else ""
	if months > 24:
		return "plus de 2 ans" + suffix
	return "%d mois%s" % [months, suffix]


static func runway_color(months: int) -> Color:
	if months < 0:
		return GOOD
	return BAD if months <= 3 else (WARN if months <= 12 else TEXT)


static func money_cell(cents: int) -> Dictionary:
	return {"text": Money.fmt_short(cents), "sort": cents,
		"color": GOOD if cents >= 0 else BAD}


static func rating_color(v: float) -> Color:
	if v >= 1.18:
		return Color("#37d6c0")
	if v >= 1.05:
		return GOOD
	if v <= 0.85:
		return BAD
	if v <= 0.95:
		return WARN
	return TEXT


## Barre de progression compacte (forme, moral, cohésion…).
static func meter(value: float, max_value: float = 100.0, width: int = 90,
		color: Color = ACCENT) -> Control:
	var pb := ProgressBar.new()
	pb.min_value = 0
	pb.max_value = max_value
	pb.value = clampf(value, 0.0, max_value)
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(width, 8)
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pb.add_theme_stylebox_override("fill", box(color, 3))
	pb.add_theme_stylebox_override("background", box(Color("#0e1117"), 3))
	return pb


## Ligne « libellé + jauge + valeur », utilisée partout dans les fiches.
static func bar_row(name: String, value: float, color: Color = GOOD,
		max_value: float = 100.0, label_width: int = 120,
		suffix: String = "") -> Control:
	var h := hbox(8)
	var l := label(name, FS_BODY_L, TEXT_DIM)
	l.custom_minimum_size = Vector2(label_width, 0)
	h.add_child(l)
	h.add_child(meter(value, max_value, 130, color))
	var v := label("%.0f%s" % [value, suffix], FS_BODY_L, TEXT)
	v.custom_minimum_size = Vector2(40, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(v)
	return h


static func kv(key: String, value, key_width: int = 150,
		color: Color = TEXT) -> Control:
	var h := hbox(8)
	var k := label(key, FS_BODY_L, TEXT_DIM)
	k.custom_minimum_size = Vector2(key_width, 0)
	h.add_child(k)
	if value is Control:
		h.add_child(value)
	else:
		h.add_child(label(str(value), FS_BODY_L, color))
	return h


## Grande valeur avec son intitulé : brique des tableaux de bord.
static func stat_block(caption_text: String, value: String,
		color: Color = TEXT, hint: String = "") -> Control:
	var v := vbox(1)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_child(caption(caption_text))
	v.add_child(display(value, FS_H2, color, 700, 0.2))
	if hint != "":
		v.add_child(label(hint, FS_SMALL, TEXT_FAINT))
	return v


## Étoiles de potentiel, façon Football Manager (demi-étoiles comprises).
static func stars(value: float, max_stars: int = 5) -> String:
	var halves := int(round(clampf(value, 0.0, float(max_stars)) * 2.0))
	var out := ""
	for i in max_stars:
		if halves >= (i + 1) * 2:
			out += "★"
		elif halves == i * 2 + 1:
			out += "⯪"
		else:
			out += "☆"
	return out


static func star_control(value: float, max_stars: int = 5,
		color: Color = WARN) -> Control:
	return label(stars(value, max_stars), FS_BODY_L, color)


# ============================================================================
# Défilement
# ============================================================================

## Zone défilante qui occupe la place restante (listes longues).
static func scroll(child: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(child)
	return s


## Défilement HORIZONTAL seul, sur une seule ligne de haut.
## À utiliser pour les barres d'onglets : un `scroll()` normal réclamerait
## toute la hauteur restante et laisserait un trou béant sous les onglets.
static func scroll_h(child: Control, height: int = 34) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	s.custom_minimum_size = Vector2(0, height)
	# Le défilement vertical étant désactivé, l'enfant doit porter SIZE_EXPAND
	# vertical : sinon Godot le réduit à sa hauteur minimale (voir data_table).
	child.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.add_child(child)
	return s


# ============================================================================
# Champs de saisie
# ============================================================================

static func line_edit(placeholder: String, text: String = "",
		width: int = 200) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.text = text
	e.custom_minimum_size = Vector2(width, 30)
	e.add_theme_font_size_override("font_size", FS_BODY_L)
	e.add_theme_stylebox_override("normal", box(BG, 6, 8, BORDER, 1))
	e.add_theme_stylebox_override("focus", box(BG, 6, 8, ACCENT, 1))
	e.add_theme_color_override("font_color", TEXT)
	e.add_theme_color_override("font_placeholder_color", TEXT_FAINT)
	return e


static func slider(value: float, min_v: float, max_v: float,
		on_change: Callable, width: int = 180) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.value = value
	s.step = 1.0
	s.custom_minimum_size = Vector2(width, 18)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.add_theme_stylebox_override("slider", box(Color("#0e1117"), 3))
	s.add_theme_stylebox_override("grabber_area", box(ACCENT, 3))
	s.add_theme_stylebox_override("grabber_area_highlight", box(ACCENT, 3))
	if on_change.is_valid():
		s.value_changed.connect(on_change)
	return s


static func dropdown(items: Array, selected: int, on_change: Callable,
		width: int = 180) -> OptionButton:
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(width, 30)
	o.focus_mode = Control.FOCUS_NONE
	o.add_theme_font_size_override("font_size", FS_BODY_L)
	o.add_theme_stylebox_override("normal", box(BG_PANEL_HI, 6, 8, BORDER, 1))
	o.add_theme_stylebox_override("hover", box(Color("#2b3346"), 6, 8, BORDER, 1))
	o.add_theme_stylebox_override("pressed", box(BG_PANEL_HI, 6, 8, ACCENT, 1))
	o.add_theme_color_override("font_color", TEXT)
	for it in items:
		o.add_item(str(it))
	if selected >= 0 and selected < items.size():
		o.select(selected)
	if on_change.is_valid():
		o.item_selected.connect(on_change)
	return o


# ============================================================================
# Divers
# ============================================================================

## Message d'état centré : liste vide, écran non applicable…
static func empty_state(text: String, hint: String = "") -> Control:
	var v := vbox(4)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var l := label(text, FS_LEAD, TEXT_DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	if hint != "":
		var h := label(hint, FS_BODY, TEXT_FAINT)
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(h)
	return v


## Écusson d'une structure : sigle sur pastille aux couleurs de la marque.
##
## Les deux coins coupés en diagonale ne sont pas une coquetterie : c'est la
## forme des cartouches d'équipe d'une diffusion, et c'est ce qui fait lire la
## pastille comme un blason plutôt que comme une icône d'application. Un carré
## arrondi de façon égale ressemble à un bouton.
static func crest(text: String, color: Color, size: int = 34) -> Control:
	var p := PanelContainer.new()
	var sb := box(Color(color.r, color.g, color.b, 0.20), 0, 0, color, 1)
	var cut := maxi(5, size / 4)
	sb.corner_radius_top_left = cut
	sb.corner_radius_bottom_right = cut
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2
	sb.shadow_size = 5
	sb.shadow_color = Color(color.r, color.g, color.b, 0.22)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(size, size)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := display(text.substr(0, 3).to_upper(), maxi(11, int(size * 0.38)),
		color, 700, 0.5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p


## Met une MAJUSCULE INITIALE, et rien d'autre.
##
## À ne pas confondre avec `String.capitalize()` de Godot, qui met une majuscule
## à CHAQUE mot : une phrase française rédigée par le moteur (« très bon niveau
## en visée ») en ressortait en « Très Bon Niveau En Visée », c'est-à-dire dans
## une convention anglaise, et sur un écran entier de puces ça se voyait.
static func sentence(text: String) -> String:
	if text.is_empty():
		return text
	return text.substr(0, 1).to_upper() + text.substr(1)


## Couleur stable dérivée d'une chaîne : deux structures n'ont jamais la même
## teinte, et elle ne change pas d'une session à l'autre.
static func color_from_id(s: String) -> Color:
	var h := 0
	for i in s.length():
		h = (h * 31 + s.unicode_at(i)) % 100000
	return Color.from_hsv(float(h % 360) / 360.0, 0.55, 0.85)


## Couleur d'une STRUCTURE : sa vraie couleur de marque.
##
## Chaque structure de `data/world/orgs.json` et du pack VCT porte un champ
## `color`, que `WorldGenerator` range dans `color_primary` — et que l'interface
## ignorait jusqu'ici au profit d'une teinte tirée au hasard de l'identifiant.
## C'est dommage deux fois : la couleur choisie par le joueur qui FONDE sa
## structure n'apparaissait nulle part, et les couleurs réelles des équipes du
## pack non plus. On repasse donc par la marque, et le hachage ne sert plus que
## de filet.
static func org_color(o) -> Color:
	if o == null:
		return ACCENT
	var raw := str(o.color_primary)
	if raw == "" or not raw.begins_with("#"):
		return color_from_id(str(o.id))
	return readable(Color(raw))


## Remonte une couleur de marque jusqu'à ce qu'elle tienne sur fond très sombre.
##
## Une vraie identité d'équipe est souvent noire, bleu nuit ou bordeaux foncé :
## posée telle quelle sur un fond à 5 % de luminosité, elle ne se voit tout
## simplement pas, et le bandeau paraît cassé. On préserve la TEINTE — c'est
## elle qu'on reconnaît — en garantissant un minimum de saturation et de clarté.
static func readable(c: Color) -> Color:
	var h := c.h
	var s := maxf(c.s, 0.45)
	var v := maxf(c.v, 0.72)
	return Color.from_hsv(h, s, v)
