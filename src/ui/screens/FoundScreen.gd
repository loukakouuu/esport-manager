extends Screen

## Création d'une structure de zéro.
##
## L'autre porte d'entrée du jeu, en face de « reprendre une structure ». Ce
## qu'on choisit ici est court par exigence : une identité, une région, un
## capital. Tout le reste — les joueurs, les sponsors, la place en
## compétition — se gagne en jouant, et c'est précisément l'intérêt du mode.
##
## Voir WorldGenerator.found_org pour ce que la structure reçoit vraiment.

const REGIONS := [
	["EMEA", "EMEA", "Circuit ouvert EMEA"],
	["AMERICAS", "Americas", "Circuit ouvert Americas"],
	["PACIFIC", "Pacific", "Circuit ouvert Pacific"],
	["CHINA", "China", "Circuit ouvert China"],
]

## Palette proposée. Une couleur d'écusson n'a pas d'effet en jeu : c'est de
## l'attachement, et ça n'a pas besoin d'autre justification.
const COLORS := [
	"#ff5a3c", "#4aa8ff", "#46c46a", "#e8a33d", "#a78bfa",
	"#ec4899", "#14b8a6", "#f5f5f5", "#8a93a6", "#c0392b",
]

const TIERS := [
	["garage", "Garage", "40 k$ · personne à qui rendre des comptes",
		"Vous financez tout. La direction, c'est vous : sa confiance ne "
		+ "s'effondrera pas pour une mauvaise saison. Mais 40 000 $ couvrent "
		+ "à peine quelques mois de salaires — la trésorerie sera votre "
		+ "adversaire permanent."],
	["seed", "Amorçage", "120 k$ · l'équilibre",
		"De quoi constituer un cinq correct et tenir la première saison sans "
		+ "vendre l'âme de la structure. Ni filet, ni pression particulière."],
	["backed", "Investisseur", "320 k$ · la montée exigée dès la première saison",
		"L'argent d'un fonds. Vous pouvez recruter tout de suite, mais la "
		+ "montée en Challengers devient un objectif contractuel, et la "
		+ "patience de départ est nettement plus courte."],
]


## Conteneur de l'aperçu, reconstruit seul à chaque frappe. Reconstruire tout
## l'écran replacerait le curseur au début du champ de saisie à chaque lettre.
var _preview: VBoxContainer = null


func build() -> void:
	add_child(page_header("Fonder votre structure",
		"Une marque, une région, un capital. Le reste se gagne.", [
			UiKit.ghost("◀ Retour", func(): game().abandon_world()),
		]))

	var parts := split(400)
	var main: VBoxContainer = parts[0]
	var side: VBoxContainer = parts[1]

	main.add_child(_identity_card())
	main.add_child(_region_card())
	main.add_child(_capital_card())
	main.add_child(UiKit.vspacer())

	_preview = UiKit.vbox(10)
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(_preview)
	_rebuild_preview()


# ============================================================================
# Formulaire
# ============================================================================

func _identity_card() -> Control:
	var card := UiKit.card("Identité", 8, 14)
	var st := ui("found")

	var name_row := UiKit.hbox(10)
	name_row.add_child(_field_label("Nom de la structure"))
	var name_field := UiKit.line_edit("Aurora Collective", _name(), 260)
	name_field.text_changed.connect(func(t: String):
		st["name"] = t
		# Le sigle suit le nom tant que le joueur n'y a pas touché lui-même.
		if not bool(st.get("tag_edited", false)):
			st["tag"] = _auto_tag(t)
		_rebuild_preview())
	name_row.add_child(name_field)
	card.body.add_child(name_row)

	var tag_row := UiKit.hbox(10)
	tag_row.add_child(_field_label("Sigle"))
	var tag_field := UiKit.line_edit("AUR", _tag(), 90)
	tag_field.max_length = 4
	tag_field.text_changed.connect(func(t: String):
		st["tag"] = t.to_upper()
		st["tag_edited"] = true
		_rebuild_preview())
	tag_row.add_child(tag_field)
	tag_row.add_child(UiKit.label("2 à 4 caractères, affiché sur l'écusson",
		UiKit.FS_SMALL, UiKit.TEXT_FAINT))
	card.body.add_child(tag_row)

	var color_row := UiKit.hbox(10)
	color_row.add_child(_field_label("Couleur"))
	for c in COLORS:
		color_row.add_child(_color_swatch(str(c)))
	card.body.add_child(color_row)
	return card.panel


func _field_label(text: String) -> Control:
	var l := UiKit.label(text, UiKit.FS_BODY_L, UiKit.TEXT_DIM)
	l.custom_minimum_size = Vector2(150, 0)
	return l


func _color_swatch(hex: String) -> Control:
	var chosen := hex == _color()
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(26, 26)
	var col := Color(hex)
	var sb := UiKit.box(col, 5, 0, UiKit.TEXT if chosen else UiKit.BORDER,
		2 if chosen else 1)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", UiKit.box(col.lightened(0.15), 5, 0,
		UiKit.TEXT, 2))
	b.add_theme_stylebox_override("pressed", sb)
	b.pressed.connect(func():
		ui("found")["color"] = hex
		refresh())
	return b


func _region_card() -> Control:
	var card := UiKit.card("Région et pays", 8, 14)
	var st := ui("found")

	var items: Array = []
	for r in REGIONS:
		items.append([str((r as Array)[0]), str((r as Array)[1])])
	card.body.add_child(UiKit.tabs(items, st, "region", func(_k): refresh(),
		"EMEA"))
	card.body.add_child(UiKit.label(_league_label(),
		UiKit.FS_BODY, UiKit.TEXT_DIM))

	var countries := WorldGenerator.countries_of(_region())
	if countries.is_empty():
		return card.panel
	var row := UiKit.hbox(10)
	row.add_child(_field_label("Pays"))
	var idx := countries.find(_country())
	row.add_child(UiKit.dropdown(countries, maxi(idx, 0), func(i: int):
		ui("found")["country"] = str(countries[i])
		_rebuild_preview()))
	card.body.add_child(row)

	card.body.add_child(UiKit.wrap(
		"La région décide du circuit où vous êtes engagé, du vivier d'agents "
		+ "libres accessible et, plus tard, de la ligue Challengers que vous "
		+ "viserez.", UiKit.FS_SMALL, UiKit.TEXT_FAINT))
	return card.panel


func _capital_card() -> Control:
	var card := UiKit.card("Capital de départ", 8, 14)
	var current := _tier()
	for t in TIERS:
		var row: Array = t
		card.body.add_child(_tier_row(str(row[0]), str(row[1]), str(row[2]),
			str(row[3]), str(row[0]) == current))
	return card.panel


func _tier_row(key: String, title: String, headline: String, detail: String,
		chosen: bool) -> Control:
	var panel := UiKit.panel(11, UiKit.BG_PANEL_HI if chosen else UiKit.BG_ROW)
	if chosen:
		panel.add_theme_stylebox_override("panel",
			UiKit.box(UiKit.BG_PANEL_HI, 8, 11, UiKit.ACCENT, 1))
	var v := UiKit.vbox(3)
	panel.add_child(v)

	var head := UiKit.hbox(8)
	head.add_child(UiKit.label(title, UiKit.FS_LEAD,
		UiKit.ACCENT if chosen else UiKit.TEXT, true))
	head.add_child(UiKit.label(headline, UiKit.FS_BODY, UiKit.TEXT_DIM))
	head.add_child(UiKit.spacer())
	if chosen:
		head.add_child(UiKit.pill("choisi", UiKit.ACCENT, true))
	else:
		head.add_child(UiKit.ghost("Choisir", func():
			ui("found")["tier"] = key
			refresh()))
	v.add_child(head)
	v.add_child(UiKit.wrap(detail, UiKit.FS_SMALL, UiKit.TEXT_DIM))
	return panel


# ============================================================================
# Aperçu et validation
# ============================================================================

func _preview_card() -> Control:
	var card := UiKit.card("", 9, 14)
	card.panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var head := UiKit.hbox(10)
	head.add_child(UiKit.crest(_tag(), Color(_color()), 46))
	var idn := UiKit.vbox(1)
	idn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	idn.add_child(UiKit.label(_name() if _name() != "" else "Sans nom",
		UiKit.FS_H3, UiKit.TEXT if _name() != "" else UiKit.TEXT_FAINT, true))
	var chips := UiKit.hbox(6)
	chips.add_child(UiKit.pill(_country()))
	chips.add_child(UiKit.pill(_region(), UiKit.INFO))
	idn.add_child(chips)
	head.add_child(idn)
	card.body.add_child(head)

	var tier := WorldGenerator.capital_tier(_tier())
	card.body.add_child(UiKit.separator())
	card.body.add_child(UiKit.kv("Capital",
		Money.fmt(Money.from_units(float(tier["units"])))))
	card.body.add_child(UiKit.kv("Engagement", _league_label()))
	card.body.add_child(UiKit.kv("Effectif", "aucun joueur"))
	card.body.add_child(UiKit.kv("Encadrement", "un entraîneur, débutant"))

	card.body.add_child(UiKit.separator())
	card.body.add_child(UiKit.caption("Ce que vous n'avez pas"))
	for line in [
		"Aucun joueur sous contrat : cinq à signer avant le premier match",
		"Aucun sponsor, aucune subvention de ligue",
		"Une réputation nulle — les bons agents libres diront non",
		"Aucune place garantie : la montée passe par le barrage",
	]:
		card.body.add_child(_bullet(str(line)))

	card.body.add_child(UiKit.vspacer())
	var problem := _validation_error()
	if problem != "":
		card.body.add_child(UiKit.label(problem, UiKit.FS_SMALL, UiKit.WARN))
	var go := UiKit.primary("Fonder la structure  ▶", func():
		if _validation_error() != "":
			return
		game().found_org({
			"name": _name(), "tag": _tag(), "region": _region(),
			"country": _country(), "color": _color(), "capital_tier": _tier(),
		})
		navigate("home"))
	go.custom_minimum_size = Vector2(0, 38)
	go.disabled = problem != ""
	card.body.add_child(go)
	return card.panel


func _bullet(text: String) -> Control:
	var h := UiKit.hbox(7)
	h.add_child(UiKit.label("—", UiKit.FS_BODY, UiKit.TEXT_FAINT))
	var l := UiKit.wrap(text, UiKit.FS_BODY, UiKit.TEXT_DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	return h


## Message bloquant, ou "" si la structure peut être fondée.
func _validation_error() -> String:
	if _name().length() < 3:
		return "Donnez un nom d'au moins trois caractères."
	if _tag().length() < 2:
		return "Le sigle doit faire au moins deux caractères."
	if _name_taken():
		return "Une structure porte déjà ce nom dans ce monde."
	return ""


func _name_taken() -> bool:
	var wanted := _name().to_lower()
	for oid in world().orgs:
		if (world().orgs[oid] as Organization).name.to_lower() == wanted:
			return true
	return false


func _rebuild_preview() -> void:
	if _preview == null or not is_instance_valid(_preview):
		return
	for c in _preview.get_children():
		c.queue_free()
	_preview.add_child(_preview_card())


# ============================================================================
# État du formulaire
# ============================================================================

func _name() -> String:
	return str(ui("found").get("name", "")).strip_edges()


func _tag() -> String:
	var t := str(ui("found").get("tag", "")).strip_edges().to_upper()
	return t if t != "" else _auto_tag(_name())


func _region() -> String:
	return str(ui("found").get("region", "EMEA"))


func _country() -> String:
	var stored := str(ui("found").get("country", ""))
	var countries := WorldGenerator.countries_of(_region())
	if countries.has(stored):
		return stored
	return countries[0] if not countries.is_empty() else "FR"


func _color() -> String:
	return str(ui("found").get("color", COLORS[0]))


func _tier() -> String:
	return str(ui("found").get("tier", "seed"))


func _league_label() -> String:
	for r in REGIONS:
		if str((r as Array)[0]) == _region():
			return str((r as Array)[2])
	return "Circuit ouvert"


## Sigle déduit du nom : initiales des mots, sinon les trois premières lettres.
func _auto_tag(name: String) -> String:
	var words := name.strip_edges().split(" ", false)
	if words.size() >= 2:
		var out := ""
		for w in words:
			out += str(w).substr(0, 1)
		return out.substr(0, 4).to_upper()
	return name.strip_edges().substr(0, 3).to_upper()
