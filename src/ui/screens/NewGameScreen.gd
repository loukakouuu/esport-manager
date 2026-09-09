extends Screen

## Écran de démarrage : choix de la structure à diriger.
##
## Le choix par défaut met en avant les structures de Challengers : la campagne
## la plus intéressante consiste à monter en VCT via l'Ascension, pas à hériter
## d'une équipe déjà installée.

var _league_filter := "chal_emea"
var _seed_value := 0

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
	add_child(UiKit.title("Esport Manager"))
	add_child(UiKit.subtitle(
		"Prenez la direction d'une structure esport. Recrutez, entraînez, "
		+ "négociez, et tenez la trésorerie assez longtemps pour gagner."))

	if not game().has_world():
		var row := UiKit.hbox()
		row.add_child(UiKit.label("Graine du monde :", 13, UiKit.TEXT_DIM))
		var seed_field := LineEdit.new()
		seed_field.text = str(Time.get_unix_time_from_system() as int)
		seed_field.custom_minimum_size = Vector2(160, 0)
		row.add_child(seed_field)
		row.add_child(UiKit.button("Créer le monde", func():
			_seed_value = int(seed_field.text) if seed_field.text.is_valid_int() \
				else int(Time.get_unix_time_from_system())
			game().new_world(_seed_value)
			refresh()))
		row.add_child(UiKit.button("Charger la dernière partie", func():
			if game().load_game("partie1"):
				app.navigate("home")))
		add_child(row)
		return

	var filters := UiKit.hbox(6)
	for entry in LEAGUES:
		var key: String = entry[0]
		var b := UiKit.button(entry[1], func():
			_league_filter = key
			refresh())
		if key == _league_filter:
			b.add_theme_color_override("font_color", UiKit.ACCENT)
		filters.add_child(b)
	add_child(filters)

	var orgs := WorldGenerator.selectable_orgs(world(), _league_filter)
	var columns := [
		{"label": "Structure", "width": 180},
		{"label": "Pays", "width": 50},
		{"label": "Réputation", "width": 90, "align": "right"},
		{"label": "Fans", "width": 90, "align": "right"},
		{"label": "Trésorerie", "width": 110, "align": "right"},
		{"label": "Propriétaire", "width": 160},
		{"label": "Difficulté", "width": 110},
	]
	var rows: Array = []
	for entry_v in orgs:
		var e: Dictionary = entry_v
		var o := world().org(str(e["org_id"]))
		rows.append([
			str(e["name"]), o.country,
			str(int(e["reputation"])),
			_short(int(e["fanbase"])),
			UiKit.money_cell(int(e["cash"])),
			str(e["owner"]),
			_difficulty(int(e["reputation"]), int(e["cash"])),
		])
	add_child(UiKit.scroll(UiKit.table(columns, rows, func(i: int):
		game().choose_org(str(orgs[i]["org_id"]))
		app.navigate("home"))))


func _difficulty(reputation: int, cash: int) -> Dictionary:
	var score := float(reputation) / 3000.0 + float(cash) / float(Money.from_units(400_000.0))
	if score > 2.4:
		return {"text": "Confortable", "color": UiKit.GOOD}
	if score > 1.2:
		return {"text": "Équilibrée", "color": UiKit.TEXT}
	if score > 0.6:
		return {"text": "Exigeante", "color": UiKit.WARN}
	return {"text": "Survie", "color": UiKit.BAD}


func _short(n: int) -> String:
	if n >= 1_000_000:
		return "%s M" % String.num(float(n) / 1_000_000.0, 1)
	if n >= 1000:
		return "%d k" % int(n / 1000)
	return str(n)
