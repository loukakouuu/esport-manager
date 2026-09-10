extends Screen

## Écran de démarrage : pack de données, graine, puis choix de la structure.
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
		_build_setup()
		return
	_build_org_picker()


# ============================================================================
# Création du monde
# ============================================================================

func _build_setup() -> void:
	var parts := split(420)
	var main: VBoxContainer = parts[0]
	var side: VBoxContainer = parts[1]

	var card := UiKit.card("Nouvelle partie", 10, 14)
	main.add_child(card.panel)

	var row := UiKit.hbox(10)
	row.add_child(UiKit.label("Graine du monde", UiKit.FS_BODY_L, UiKit.TEXT_DIM))
	var seed_field := UiKit.line_edit("graine",
		str(Time.get_unix_time_from_system() as int), 170)
	row.add_child(seed_field)
	card.body.add_child(row)
	card.body.add_child(UiKit.label(
		"À graine identique, le monde généré est toujours le même : deux "
		+ "parties comparables se lancent avec la même valeur.",
		UiKit.FS_SMALL, UiKit.TEXT_FAINT))

	card.body.add_child(UiKit.separator())
	card.body.add_child(UiKit.primary("Créer le monde", func():
		_seed_value = int(seed_field.text) if seed_field.text.is_valid_int() \
			else int(Time.get_unix_time_from_system())
		game().new_world(_seed_value)
		refresh()))
	card.body.add_child(UiKit.button("Charger la dernière partie", func():
		if game().load_game("partie1"):
			app.navigate("home")))

	side.add_child(_pack_card())


## Choix du pack de données. Voir src/core/DataPack.gd pour le pourquoi :
## le jeu est livré avec un univers fictif, un pack peut le remplacer.
func _pack_card() -> Control:
	var card := UiKit.card("Univers", 8, 14)
	var packs := DataPack.installed()
	var active := DataPack.active()

	card.body.add_child(_pack_row("", "Univers fictif (livré avec le jeu)",
		"96 structures et environ 700 joueurs inventés.", active == ""))
	for pack_v in packs:
		var pack: Dictionary = pack_v
		card.body.add_child(_pack_row(str(pack["id"]), str(pack.get("name", pack["id"])),
			str(pack.get("description", "")), active == str(pack["id"])))

	if packs.is_empty():
		card.body.add_child(UiKit.separator())
		card.body.add_child(UiKit.wrap(
			"Aucun pack installé. Un pack remplace tout ou partie du contenu : "
			+ "structures, joueurs, noms. Pour en construire un à partir de "
			+ "données publiques, voir docs/DATA_PACKS.md.",
			UiKit.FS_BODY, UiKit.TEXT_FAINT))
	else:
		var attribution := DataPack.attribution_of(active)
		if attribution != "":
			card.body.add_child(UiKit.separator())
			card.body.add_child(UiKit.wrap(attribution, UiKit.FS_SMALL,
				UiKit.TEXT_FAINT))
	return card.panel


func _pack_row(pack_id: String, name: String, description: String,
		is_active: bool) -> Control:
	var panel := UiKit.panel(10, UiKit.BG_PANEL_HI if is_active else UiKit.BG_ROW)
	var v := UiKit.vbox(2)
	panel.add_child(v)
	var head := UiKit.hbox(8)
	head.add_child(UiKit.label(name, UiKit.FS_BODY_L,
		UiKit.ACCENT if is_active else UiKit.TEXT, is_active))
	head.add_child(UiKit.spacer())
	if is_active:
		head.add_child(UiKit.pill("actif", UiKit.ACCENT, true))
	else:
		head.add_child(UiKit.ghost("Utiliser", func():
			DataPack.set_active(pack_id)
			refresh()))
	v.add_child(head)
	if description != "":
		v.add_child(UiKit.label(description, UiKit.FS_SMALL, UiKit.TEXT_DIM))
	return panel


# ============================================================================
# Choix de la structure
# ============================================================================

func _build_org_picker() -> void:
	add_child(tab_bar("newgame", LEAGUES, "chal_emea"))
	_league_filter = current_tab("newgame", "chal_emea")

	var orgs := WorldGenerator.selectable_orgs(world(), _league_filter)
	if orgs.is_empty():
		add_child(UiKit.empty_state("Aucune structure dans cette ligue.",
			"Le pack de données actif ne la renseigne peut-être pas."))
		return

	var columns := [
		{"key": "name", "label": "Structure", "width": 190},
		{"key": "country", "label": "Pays", "width": 50},
		{"key": "reputation", "label": "Réputation", "width": 90, "align": "right"},
		{"key": "fans", "label": "Fans", "width": 90, "align": "right"},
		{"key": "cash", "label": "Trésorerie", "width": 110, "align": "right"},
		{"key": "owner", "label": "Propriétaire", "width": 170},
		{"key": "difficulty", "label": "Difficulté", "width": 120},
	]
	var rows: Array = []
	for entry_v in orgs:
		var e: Dictionary = entry_v
		var o := world().org(str(e["org_id"]))
		rows.append({
			"_id": str(e["org_id"]),
			"name": {"text": str(e["name"]), "bold": true},
			"country": {"text": o.country},
			"reputation": {"text": str(int(e["reputation"])),
				"sort": int(e["reputation"])},
			"fans": {"text": _short(int(e["fanbase"])), "sort": int(e["fanbase"])},
			"cash": UiKit.money_cell(int(e["cash"])),
			"owner": {"text": str(e["owner"])},
			"difficulty": _difficulty(int(e["reputation"]), int(e["cash"])),
		})
	add_child(sorted_table("newgame.orgs", columns, rows, {
		"row_clicked": func(org_id):
			game().choose_org(str(org_id))
			app.navigate("home"),
	}))
	add_child(UiKit.label(
		"Commencez par les Challengers : la campagne consiste à monter en VCT "
		+ "via l'Ascension. Cliquez une ligne pour prendre la structure.",
		UiKit.FS_SMALL, UiKit.TEXT_FAINT))


func _difficulty(reputation: int, cash: int) -> Dictionary:
	var score := float(reputation) / 3000.0 \
		+ float(cash) / float(Money.from_units(400_000.0))
	if score > 2.4:
		return {"text": "Confortable", "color": UiKit.GOOD, "sort": score}
	if score > 1.2:
		return {"text": "Équilibrée", "color": UiKit.TEXT, "sort": score}
	if score > 0.6:
		return {"text": "Exigeante", "color": UiKit.WARN, "sort": score}
	return {"text": "Survie", "color": UiKit.BAD, "sort": score}


func _short(n: int) -> String:
	if n >= 1_000_000:
		return "%s M" % String.num(float(n) / 1_000_000.0, 1)
	if n >= 1000:
		return "%d k" % int(n / 1000)
	return str(n)
