class_name UiKit
extends RefCounted

## Boîte à outils d'interface.
##
## L'UI est construite EN CODE plutôt qu'en scènes .tscn. Ce n'est pas un
## raccourci : un jeu de gestion affiche des tableaux de données dont les
## colonnes changent avec la discipline (les stats de Valorant ne sont pas
## celles de League of Legends). Une table générée à partir d'une description
## de colonnes reste juste quand on ajoute un jeu ; une scène figée non.

# Palette sombre, lisible pendant de longues sessions.
const BG := Color("#12141a")
const BG_PANEL := Color("#1a1d26")
const BG_ROW := Color("#20242f")
const BG_ROW_ALT := Color("#1b1f28")
const ACCENT := Color("#e0563f")
const TEXT := Color("#e6e8ee")
const TEXT_DIM := Color("#8b93a5")
const GOOD := Color("#4fbf6a")
const BAD := Color("#e05252")
const WARN := Color("#e0a33f")


static func label(text: String, size: int = 14, color: Color = TEXT,
		bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_constant_override("outline_size", 0)
	return l


static func title(text: String) -> Label:
	var l := label(text, 22, TEXT)
	l.add_theme_constant_override("line_spacing", 6)
	return l


static func subtitle(text: String) -> Label:
	return label(text, 12, TEXT_DIM)


static func panel(margin: int = 12) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_PANEL
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin
	sb.content_margin_bottom = margin
	p.add_theme_stylebox_override("panel", sb)
	return p


static func button(text: String, on_pressed: Callable = Callable()) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 30)
	if on_pressed.is_valid():
		b.pressed.connect(on_pressed)
	return b


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
	return c


static func separator() -> HSeparator:
	return HSeparator.new()


## Construit un tableau à partir de colonnes et de lignes.
## columns : [{"label": "Joueur", "width": 140, "align": "left"}]
## rows    : [[valeur|{"text":..,"color":..}, …]]
static func table(columns: Array, rows: Array, row_clicked: Callable = Callable()) -> Control:
	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", 1)

	# Tableau sans en-tête (arbres de tournoi) : on n'affiche pas une ligne
	# d'intitulés vides.
	var has_labels := false
	for c in columns:
		if str((c as Dictionary).get("label", "")) != "":
			has_labels = true
	if has_labels:
		var header := _row_container(BG_PANEL)
		for c in columns:
			_cells_of(header).add_child(_cell(str((c as Dictionary).get("label", "")),
				c, TEXT_DIM, 12))
		grid.add_child(header)

	for i in rows.size():
		var bg := BG_ROW if i % 2 == 0 else BG_ROW_ALT
		var line := _row_container(bg)
		var cells := _cells_of(line)
		var row: Array = rows[i]
		for j in columns.size():
			var v = row[j] if j < row.size() else ""
			var color := TEXT
			var text := ""
			if v is Dictionary:
				text = str((v as Dictionary).get("text", ""))
				color = (v as Dictionary).get("color", TEXT)
			else:
				text = str(v)
			cells.add_child(_cell(text, columns[j], color, 13))
		if row_clicked.is_valid():
			# Ligne cliquable sans bouton superposé : le panneau intercepte le
			# clic, les libellés laissent passer la souris.
			var idx := i
			line.mouse_filter = Control.MOUSE_FILTER_STOP
			line.gui_input.connect(func(event: InputEvent):
				if event is InputEventMouseButton \
						and (event as InputEventMouseButton).pressed \
						and (event as InputEventMouseButton).button_index \
							== MOUSE_BUTTON_LEFT:
					row_clicked.call(idx))
		grid.add_child(line)
	return grid


## Une ligne de tableau = un PanelContainer (le fond) contenant UN SEUL enfant,
## la HBoxContainer des cellules.
##
## Piège Godot à ne jamais réintroduire : un PanelContainer empile TOUS ses
## enfants dans le même rectangle. Y ajouter les cellules directement les
## superpose au lieu de les aligner. On passe donc toujours par _cells_of().
static func _row_container(bg: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	p.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	return p


static func _cells_of(row: PanelContainer) -> HBoxContainer:
	return row.get_child(0) as HBoxContainer


static func _cell(text: String, col, color: Color, size: int) -> Control:
	var c: Dictionary = col
	var l := label(text, size, color)
	var w := int(c.get("width", 100))
	l.custom_minimum_size = Vector2(w, 0)
	l.clip_text = true
	match str(c.get("align", "left")):
		"right":
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		"center":
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if bool(c.get("expand", false)):
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## Barre de progression compacte (forme, moral, cohésion…).
static func meter(value: float, max_value: float = 100.0, width: int = 90,
		color: Color = ACCENT) -> Control:
	var pb := ProgressBar.new()
	pb.min_value = 0
	pb.max_value = max_value
	pb.value = clampf(value, 0.0, max_value)
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(width, 12)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.corner_radius_top_left = 3
	fill.corner_radius_bottom_left = 3
	fill.corner_radius_top_right = 3
	fill.corner_radius_bottom_right = 3
	var bg := StyleBoxFlat.new()
	bg.bg_color = BG_ROW_ALT
	bg.corner_radius_top_left = 3
	bg.corner_radius_bottom_left = 3
	bg.corner_radius_top_right = 3
	bg.corner_radius_bottom_right = 3
	pb.add_theme_stylebox_override("fill", fill)
	pb.add_theme_stylebox_override("background", bg)
	return pb


static func money_cell(cents: int) -> Dictionary:
	return {"text": Money.fmt_short(cents),
		"color": GOOD if cents >= 0 else BAD}


static func rating_color(v: float) -> Color:
	if v >= 1.15:
		return GOOD
	if v <= 0.88:
		return BAD
	return TEXT


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
	s.add_child(child)
	return s


## Étoiles de potentiel, façon Football Manager.
static func stars(value: float, max_stars: int = 5) -> String:
	var full := int(round(clampf(value, 0.0, float(max_stars))))
	var out := ""
	for i in max_stars:
		out += "★" if i < full else "☆"
	return out
