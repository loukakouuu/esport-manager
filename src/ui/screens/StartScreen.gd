extends Screen

## Porte d'entrée du jeu : choix du MODE de carrière, puis de l'univers.
##
## Deux modes, comme dans les gestionnaires de football :
##   - reprendre une structure existante, avec son histoire, ses moyens et ses
##     contraintes ;
##   - fonder la sienne, sans effectif ni place garantie, et entrer par le
##     circuit ouvert.
##
## Le mode choisi est mémorisé dans l'état d'affichage sous "start"/"mode" :
## c'est lui que lit App pour savoir quel écran présenter après la création du
## monde. Voir WorldGenerator.found_org pour ce que la fondation donne — et
## surtout pour ce qu'elle ne donne pas.

const FOUND_FEATURES := [
	"Nom, sigle, couleurs, région et pays de la structure",
	"Trois capitaux de départ, du garage au fonds d'investissement",
	"Effectif à composer entièrement parmi les agents libres",
	"Entrée par le circuit ouvert, sans place garantie en Challengers",
	"Une réputation nulle : les bons joueurs commenceront par dire non",
]


func build() -> void:
	var head := UiKit.vbox(2)
	head.add_child(UiKit.title("Esport Manager"))
	head.add_child(UiKit.subtitle(
		"Prenez la direction d'une structure esport. Recrutez, entraînez, "
		+ "négociez, et tenez la trésorerie assez longtemps pour gagner."))
	add_child(head)

	var modes := UiKit.hbox(14)
	modes.add_child(_takeover_card())
	modes.add_child(_found_card())
	add_child(modes)

	var bottom := UiKit.hbox(14)
	bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom.add_child(_universe_card())
	bottom.add_child(_options_card())
	add_child(bottom)


# ============================================================================
# Les deux modes
# ============================================================================

func _takeover_card() -> Control:
	var card := UiKit.card("", 9, 16)
	card.panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.panel.add_theme_stylebox_override("panel",
		UiKit.box(UiKit.BG_PANEL, 8, 16, UiKit.ACCENT, 1))

	var head := UiKit.hbox(8)
	head.add_child(UiKit.heading("Reprendre une structure"))
	head.add_child(UiKit.spacer())
	head.add_child(UiKit.pill("disponible", UiKit.GOOD, true))
	card.body.add_child(head)

	card.body.add_child(UiKit.wrap(
		"Vous héritez d'une maison qui existe déjà : son effectif, sa "
		+ "trésorerie, ses sponsors, ses sections sur les autres jeux et une "
		+ "direction qui a des attentes. Tout est en place dès le premier "
		+ "jour — à vous de faire mieux que ce qu'on attend de vous.",
		UiKit.FS_BODY_L, UiKit.TEXT_DIM))

	card.body.add_child(UiKit.gap(2))
	for line in [
		"Des dizaines de structures sur quatre régions",
		"Du club de Challengers à l'écurie installée en ligue partenaire",
		"Objectifs fixés par la direction dès la reprise",
	]:
		card.body.add_child(_bullet(str(line), UiKit.TEXT_DIM))

	card.body.add_child(UiKit.vspacer())
	card.body.add_child(UiKit.separator())
	var go := UiKit.primary("Choisir une structure  ▶", func():
		ui("start")["mode"] = "takeover"
		game().new_world(_seed()))
	go.custom_minimum_size = Vector2(0, 36)
	card.body.add_child(go)
	return card.panel


func _found_card() -> Control:
	var card := UiKit.card("", 9, 16)
	card.panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.panel.add_theme_stylebox_override("panel",
		UiKit.box(UiKit.BG_PANEL, 8, 16, UiKit.INFO, 1))

	var head := UiKit.hbox(8)
	head.add_child(UiKit.heading("Fonder votre structure"))
	head.add_child(UiKit.spacer())
	head.add_child(UiKit.pill("mode difficile", UiKit.INFO, true))
	card.body.add_child(head)

	card.body.add_child(UiKit.wrap(
		"Partir de rien : une marque à inventer, un capital à placer, un "
		+ "effectif à composer parmi les agents libres, et aucune place "
		+ "garantie en compétition. Vous entrez par le circuit ouvert, au "
		+ "troisième étage de la pyramide, et vous remontez.",
		UiKit.FS_BODY_L, UiKit.TEXT_DIM))

	card.body.add_child(UiKit.gap(2))
	for line in FOUND_FEATURES:
		card.body.add_child(_bullet(str(line), UiKit.TEXT_DIM))

	card.body.add_child(UiKit.vspacer())
	card.body.add_child(UiKit.separator())
	var go := UiKit.button("Créer ma structure  ▶", func():
		ui("start")["mode"] = "found"
		game().new_world(_seed()))
	go.custom_minimum_size = Vector2(0, 36)
	card.body.add_child(go)
	return card.panel


func _bullet(text: String, color: Color) -> Control:
	var h := UiKit.hbox(7)
	h.add_child(UiKit.label("—", UiKit.FS_BODY, UiKit.TEXT_FAINT))
	var l := UiKit.wrap(text, UiKit.FS_BODY, color)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	return h


# ============================================================================
# Univers : contenu livré ou pack de données
# ============================================================================

## Voir src/core/DataPack.gd. Le pack « vraies équipes » est livré avec le jeu
## et actif par défaut ; l'univers fictif reste à un clic.
func _universe_card() -> Control:
	var card := UiKit.card("Univers", 8, 14)
	card.panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var active := DataPack.active()

	card.body.add_child(_pack_row("", "Univers fictif (livré avec le jeu)",
		"Structures et joueurs entièrement inventés.", active == "", false))
	var packs := DataPack.installed()
	# Deux imports successifs portent souvent le même nom (« VCT 2026 »). Sans
	# l'identifiant, la liste devient deux lignes rigoureusement identiques et
	# le choix n'a plus de sens.
	var duplicated := _duplicated_names(packs)
	for pack_v in packs:
		var pack: Dictionary = pack_v
		var pack_id := str(pack["id"])
		var name := str(pack.get("name", pack_id))
		if duplicated.has(name):
			name = "%s  (%s)" % [name, pack_id]
		card.body.add_child(_pack_row(pack_id, name,
			str(pack.get("description", "")),
			active == pack_id, bool(pack.get("bundled", false))))

	var attribution := DataPack.attribution_of(active)
	if attribution != "":
		card.body.add_child(UiKit.separator())
		card.body.add_child(UiKit.wrap(attribution, UiKit.FS_SMALL,
			UiKit.TEXT_FAINT))
	card.body.add_child(UiKit.wrap(
		"L'univers est gravé dans la partie : une sauvegarde se recharge "
		+ "toujours avec le contenu qui l'a créée.",
		UiKit.FS_SMALL, UiKit.TEXT_FAINT))
	return card.panel


func _duplicated_names(packs: Array) -> Dictionary:
	var seen := {}
	var dup := {}
	for pack_v in packs:
		var name := str((pack_v as Dictionary).get("name", ""))
		if seen.has(name):
			dup[name] = true
		seen[name] = true
	return dup


func _pack_row(pack_id: String, name: String, description: String,
		is_active: bool, bundled: bool) -> Control:
	var panel := UiKit.panel(10, UiKit.BG_PANEL_HI if is_active else UiKit.BG_ROW)
	var v := UiKit.vbox(2)
	panel.add_child(v)
	var head := UiKit.hbox(8)
	head.add_child(UiKit.label(name, UiKit.FS_BODY_L,
		UiKit.ACCENT if is_active else UiKit.TEXT, is_active))
	if bundled:
		head.add_child(UiKit.pill("livré", UiKit.TEXT_FAINT))
	head.add_child(UiKit.spacer())
	if is_active:
		head.add_child(UiKit.pill("actif", UiKit.ACCENT, true))
	else:
		head.add_child(UiKit.ghost("Utiliser", func():
			DataPack.set_active(pack_id)
			refresh()))
	v.add_child(head)
	if description != "":
		v.add_child(UiKit.wrap(description, UiKit.FS_SMALL, UiKit.TEXT_DIM))
	return panel


# ============================================================================
# Options et reprise de partie
# ============================================================================

func _options_card() -> Control:
	var card := UiKit.card("Options", 8, 14)
	card.panel.custom_minimum_size = Vector2(360, 0)

	var row := UiKit.hbox(10)
	row.add_child(UiKit.label("Graine du monde", UiKit.FS_BODY_L, UiKit.TEXT_DIM))
	row.add_child(UiKit.spacer())
	var field := UiKit.line_edit("graine", str(_seed()), 140)
	field.text_changed.connect(func(t: String): ui("start")["seed"] = t)
	row.add_child(field)
	card.body.add_child(row)
	card.body.add_child(UiKit.wrap(
		"À graine identique, le monde généré est toujours le même : deux "
		+ "parties comparables se lancent avec la même valeur.",
		UiKit.FS_SMALL, UiKit.TEXT_FAINT))

	card.body.add_child(UiKit.separator())
	card.body.add_child(UiKit.caption("Reprendre une partie"))
	var slots := SaveGame.list_slots()
	if slots.is_empty():
		card.body.add_child(UiKit.label("Aucune sauvegarde.", UiKit.FS_BODY,
			UiKit.TEXT_FAINT))
	else:
		for slot_v in slots:
			card.body.add_child(_save_row(slot_v))
	return card.panel


func _save_row(slot_v) -> Control:
	var slot: Dictionary = slot_v
	var name := str(slot.get("slot", "partie1"))
	var org_name := str(slot.get("org_name", ""))
	var h := UiKit.hbox(8)
	var v := UiKit.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UiKit.label(org_name if org_name != "" else name,
		UiKit.FS_BODY_L))
	var detail := str(slot.get("date", ""))
	if detail != "":
		v.add_child(UiKit.label(detail, UiKit.FS_SMALL, UiKit.TEXT_DIM))
	h.add_child(v)
	h.add_child(UiKit.button("Charger", func():
		if game().load_game(name):
			navigate("home")))
	return h


# ============================================================================

## Graine courante. Mémorisée dans l'état d'affichage : l'écran est reconstruit
## à chaque clic sur « Utiliser », et une graine qui change toute seule entre
## deux clics rendrait le champ inutilisable.
func _seed() -> int:
	var stored := str(ui("start").get("seed", ""))
	if stored.is_valid_int():
		return int(stored)
	var s := int(Time.get_unix_time_from_system())
	ui("start")["seed"] = str(s)
	return s
