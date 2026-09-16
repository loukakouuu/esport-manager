extends Screen

## Porte d'entrée du jeu : reprendre une partie, ou en commencer une.
##
## Trois blocs, dans l'ordre où on s'en sert :
##   1. les PARTIES EN COURS, façon Football Manager — quand on a une carrière
##      en route, c'est ce qu'on vient chercher neuf fois sur dix, et ça doit
##      être la première chose sous le titre ;
##   2. les deux MODES de nouvelle carrière, en grands rectangles cliquables ;
##   3. l'UNIVERS, en pastilles discrètes.
##
## PARTI PRIS : plus aucune graine à l'écran. Le monde reste engendré par une
## graine — c'est ce qui rend une partie rejouable et l'équilibrage comparable
## (voir `src/core/Rng.gd`) — mais la demander au joueur sur l'écran-titre,
## c'était exposer un rouage de développement dans la vitrine. Elle est tirée au
## sort à la création du monde, et les outils headless continuent de la fixer.
##
## Le mode choisi est mémorisé dans l'état d'affichage sous "start"/"mode" :
## c'est lui que lit App pour savoir quel écran présenter après la création du
## monde. Voir WorldGenerator.found_org pour ce que la fondation donne — et
## surtout pour ce qu'elle ne donne pas.

const TAKEOVER_POINTS := [
	"Un effectif, une trésorerie et des sponsors dès le premier jour",
	"Des dizaines de structures, du club de Challengers à l'écurie de VCT",
	"Une direction qui a déjà des attentes",
]

const FOUND_POINTS := [
	"Nom, sigle, couleurs et région à inventer",
	"Effectif à composer parmi les agents libres",
	"Entrée par le circuit ouvert, sans place garantie",
]


func build() -> void:
	# Le fond occupe TOUT l'écran et porte la lumière ; le reste se pose dessus.
	var back := Backdrop.new()
	back.pad(46, 30, 46, 26)
	back.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(back)

	var page := UiKit.vbox(20)
	back.add_child(page)

	page.add_child(_hero())

	var saves := SaveGame.list_slots()
	if not saves.is_empty():
		page.add_child(_continue_block(saves))

	# Les deux rectangles absorbent toute la hauteur restante : ce sont eux
	# l'offre de l'écran, et une carte qui s'arrête au tiers de la page laisse
	# un trou que rien ne justifie.
	page.add_child(_new_career_block())
	page.add_child(_footer())


# ============================================================================
# Frontispice
# ============================================================================

func _hero() -> Control:
	var v := UiKit.vbox(2)
	v.add_child(UiKit.display("GESTION DE STRUCTURE ESPORT · VALORANT",
		UiKit.FS_SMALL, UiKit.ACCENT, 600, UiKit.TRACK_CAPS))

	# Le titre est détouré d'un trait sombre : posé sur un fond dégradé, un
	# texte clair perd son contraste dès que le halo passe dessous. Le contour
	# le tient à distance du fond sans l'alourdir.
	var t := UiKit.display("ESPORT MANAGER", UiKit.FS_HERO, UiKit.TEXT, 700,
		1.4)
	t.add_theme_constant_override("outline_size", 8)
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.45))
	v.add_child(t)

	v.add_child(UiKit.label(
		"Recrutez, entraînez, négociez — et tenez la trésorerie assez "
		+ "longtemps pour gagner.", UiKit.FS_LEAD, UiKit.TEXT_DIM))
	return v


# ============================================================================
# Reprendre une partie
# ============================================================================

## Les carrières en cours, en cartes à écusson.
##
## C'est le bloc que Football Manager met en premier, et il a raison : une fois
## la première partie lancée, l'écran-titre ne sert plus qu'à ça. L'ancienne
## version enterrait les sauvegardes dans une liste déroulante en bas de page,
## au même rang qu'un champ de saisie.
func _continue_block(saves: Array) -> Control:
	var v := UiKit.vbox(9)
	v.add_child(UiKit.caption("Reprendre une partie"))

	var row := UiKit.hbox(12)
	v.add_child(row)
	for slot_v in saves:
		row.add_child(_save_card(slot_v))
	row.add_child(UiKit.spacer())
	return v


func _save_card(slot_v) -> Control:
	var slot: Dictionary = slot_v
	var key := str(slot.get("slot", "partie1"))
	var org_name := str(slot.get("org_name", ""))
	var title_text := org_name if org_name != "" else key
	# Les sauvegardes d'avant l'ajout du sigle et de la couleur n'ont pas ces
	# champs : on retombe sur le nom du fichier et l'accent du jeu plutôt que de
	# dessiner un écusson vide.
	var tag := str(slot.get("org_tag", ""))
	if tag == "":
		tag = title_text
	var raw := str(slot.get("org_color", ""))
	var tint := UiKit.readable(Color(raw)) if raw.begins_with("#") \
		else UiKit.ACCENT

	# La suppression est une action DESTRUCTRICE posée sur une carte qu'on
	# clique par ailleurs pour JOUER : elle exige donc une confirmation, et la
	# carte se transforme pour la porter. Tant qu'elle est armée, la carte ne
	# charge plus la partie — sinon un clic à côté du « Oui » lancerait le jeu.
	var pending := str(ui("start").get("delete", "")) == key
	if pending:
		return _delete_confirm_card(key, title_text, tint)

	var card := UiKit.clickable(func():
		if game().load_game(key):
			navigate("home"), UiKit.BG_PANEL, tint, 0, 11)
	card.custom_minimum_size = Vector2(268, 0)

	var b := Banner.new(tint)
	b.spread = 0.95
	b.intensity = 0.13
	b.edge = 3.0
	b.underline = false
	b.pad(20, 12, 14, 12)
	card.add_child(b)

	var row := UiKit.hbox(11)
	b.add_child(row)
	row.add_child(UiKit.crest(tag, tint, 42))

	var info := UiKit.vbox(1)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_child(UiKit.display(title_text.to_upper(), UiKit.FS_BODY_L,
		UiKit.TEXT, 700, 0.3))
	var date := str(slot.get("date", ""))
	if date != "":
		info.add_child(UiKit.label(date, UiKit.FS_SMALL, UiKit.TEXT_DIM))
	var cash := int(slot.get("cash", 0))
	if slot.has("cash"):
		info.add_child(UiKit.label(Money.fmt_short(cash), UiKit.FS_SMALL,
			UiKit.GOOD if cash >= 0 else UiKit.BAD))
	row.add_child(info)

	var del := UiKit.ghost("✕", func():
		ui("start")["delete"] = key
		refresh())
	del.custom_minimum_size = Vector2(26, 26)
	del.tooltip_text = "Supprimer cette sauvegarde"
	del.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(del)
	return card


## La même carte, retournée sur sa demande de confirmation.
func _delete_confirm_card(key: String, title_text: String,
		tint: Color) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
		UiKit.box(Color(UiKit.BAD.r, UiKit.BAD.g, UiKit.BAD.b, 0.10), 11, 14,
			UiKit.BAD, 1))
	panel.custom_minimum_size = Vector2(268, 0)

	var v := UiKit.vbox(8)
	panel.add_child(v)
	v.add_child(UiKit.wrap("Supprimer la partie « %s » ?" % title_text,
		UiKit.FS_BODY_L, UiKit.TEXT))
	v.add_child(UiKit.label("Cette action est définitive.", UiKit.FS_SMALL,
		UiKit.TEXT_DIM))
	v.add_child(UiKit.vspacer())

	var row := UiKit.hbox(7)
	var yes := UiKit.danger("Supprimer", func():
		SaveGame.delete_slot(key)
		ui("start")["delete"] = ""
		refresh())
	yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(yes)
	var no := UiKit.button("Annuler", func():
		ui("start")["delete"] = ""
		refresh())
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(no)
	v.add_child(row)
	return panel


# ============================================================================
# Nouvelle carrière
# ============================================================================

func _new_career_block() -> Control:
	var v := UiKit.vbox(9)
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(UiKit.caption("Nouvelle carrière"))

	var modes := UiKit.hbox(14)
	modes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	modes.add_child(_mode_card(
		"01", "Reprendre une structure",
		"Vous héritez d'une maison qui existe déjà. Tout est en place — à vous "
		+ "de faire mieux que ce qu'on attend de vous.",
		TAKEOVER_POINTS, "Choisir une structure", UiKit.ACCENT, "takeover",
		"recommandé"))
	modes.add_child(_mode_card(
		"02", "Fonder votre structure",
		"Partir de rien : une marque à inventer, un capital à placer, et "
		+ "aucune place garantie en compétition.",
		FOUND_POINTS, "Créer ma structure", UiKit.INFO, "found",
		"mode difficile"))
	v.add_child(modes)
	return v


## Un mode de carrière. La carte entière est un bouton ; le bouton du bas n'est
## que le rappel de ce qui se passera au clic.
func _mode_card(number: String, title_text: String, pitch: String,
		points: Array, cta: String, tint: Color, mode: String,
		tag: String) -> Control:
	var choose := func():
		ui("start")["mode"] = mode
		game().new_world(_fresh_seed())

	var card := UiKit.clickable(choose, UiKit.BG_PANEL, tint, 0, 12)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var b := Banner.new(tint)
	b.spread = 0.85
	b.intensity = 0.13
	b.edge = 4.0
	b.underline = false
	# La marge gauche doit dépasser l'inclinaison ET son liseré, sinon le
	# numéro vient se poser dessus et les deux se disputent le même pixel.
	b.pad(46, 18, 22, 18)
	card.add_child(b)

	var v := UiKit.vbox(9)
	b.add_child(v)

	var head := UiKit.hbox(10)
	head.add_child(UiKit.spacer())
	head.add_child(UiKit.pill(tag, tint, true))
	v.add_child(head)

	# Le numéro vit sur la LIGNE du titre : isolé, il ouvrait un trou entre lui
	# et le titre qu'il est censé annoncer.
	var title_row := UiKit.hbox(12)
	var num := UiKit.display(number, UiKit.FS_H1, tint, 700, 1.0)
	num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(num)
	var t := UiKit.display(title_text.to_upper(), UiKit.FS_H2, UiKit.TEXT,
		700, UiKit.TRACK_TITLE)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(t)
	v.add_child(title_row)
	v.add_child(UiKit.wrap(pitch, UiKit.FS_BODY_L, UiKit.TEXT_DIM))
	v.add_child(UiKit.gap(2))

	for line in points:
		var row := UiKit.hbox(8)
		row.add_child(UiKit.label("—", UiKit.FS_BODY, tint))
		var l := UiKit.wrap(str(line), UiKit.FS_BODY, UiKit.TEXT_DIM)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		v.add_child(row)

	# Le bouton est poussé en bas de la carte, et l'espace ainsi libéré porte le
	# NUMÉRO en très grand, à peine visible. C'est le procédé de l'affiche : un
	# chiffre fantôme donne de l'échelle et du rythme là où il n'y a rien à
	# lire. Sans lui, la carte se terminait sur trois cents pixels de vide.
	var ghost := UiKit.display(number, 190,
		Color(tint.r, tint.g, tint.b, 0.07), 700, 0.0)
	ghost.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ghost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ghost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(ghost)
	var go := UiKit.button("%s  ▶" % cta, choose,
		UiKit.BtnStyle.PRIMARY if mode == "takeover" else UiKit.BtnStyle.NORMAL)
	go.custom_minimum_size = Vector2(0, 40)
	v.add_child(go)
	return card


# ============================================================================
# Univers
# ============================================================================

## L'univers en PASTILLES plutôt qu'en liste déroulante.
##
## Un `OptionButton` porte le dessin du système d'exploitation — flèche grise,
## cadre carré — et c'est précisément ce qui trahit un jeu. Il y a deux ou trois
## univers : autant les montrer tous, et rendre le choix visible d'un coup d'œil
## au lieu de le cacher derrière un déroulé.
func _footer() -> Control:
	var v := UiKit.vbox(7)

	var row := UiKit.hbox(8)
	row.add_child(UiKit.caption("Univers"))
	row.add_child(UiKit.gap(4))

	var active := DataPack.active()
	row.add_child(_universe_chip("", "Univers fictif", active == ""))
	var packs := DataPack.installed()
	# Deux imports successifs portent souvent le même nom (« VCT 2026 ») : sans
	# l'identifiant, deux pastilles seraient rigoureusement identiques et le
	# choix n'aurait plus de sens.
	var duplicated := _duplicated_names(packs)
	for pack_v in packs:
		var pack: Dictionary = pack_v
		var pack_id := str(pack["id"])
		var name := str(pack.get("name", pack_id))
		if duplicated.has(name):
			name = "%s (%s)" % [name, pack_id]
		row.add_child(_universe_chip(pack_id, name, active == pack_id))
	row.add_child(UiKit.spacer())
	v.add_child(row)

	# Mention légale : le pack VCT vient de Liquipedia sous licence CC-BY-SA,
	# qui EXIGE l'attribution. Elle reste affichée quel que soit l'univers actif.
	var attribution := DataPack.attribution_of(active)
	if attribution != "":
		v.add_child(UiKit.wrap(attribution, UiKit.FS_MICRO, UiKit.TEXT_FAINT))
	return v


func _universe_chip(pack_id: String, name: String, is_active: bool) -> Control:
	var b := Button.new()
	b.text = "  %s  " % name
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 28)
	b.add_theme_font_override("font", Typography.display(600))
	b.add_theme_font_size_override("font_size", UiKit.FS_BODY)
	var tint := UiKit.ACCENT
	var bg := Color(tint.r, tint.g, tint.b, 0.16) if is_active \
		else Color(1, 1, 1, 0.03)
	var sb := UiKit.box(bg, 14, 6, tint if is_active else UiKit.BORDER_SOFT, 1)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_stylebox_override("hover",
		UiKit.box(Color(1, 1, 1, 0.07), 14, 6, tint, 1))
	b.add_theme_color_override("font_color",
		UiKit.TEXT if is_active else UiKit.TEXT_DIM)
	b.add_theme_color_override("font_hover_color", UiKit.TEXT)
	if not is_active:
		b.pressed.connect(func():
			DataPack.set_active(pack_id)
			refresh())
	return b


func _duplicated_names(packs: Array) -> Dictionary:
	var seen := {}
	var dup := {}
	for pack_v in packs:
		var name := str((pack_v as Dictionary).get("name", ""))
		if seen.has(name):
			dup[name] = true
		seen[name] = true
	return dup


# ============================================================================

## Graine d'un nouveau monde, tirée au sort.
##
## Elle n'est plus demandée au joueur (voir l'en-tête du fichier) mais elle
## existe toujours : c'est elle qui rend une partie rejouable à l'identique et
## l'équilibrage comparable. Les outils headless la fixent en dur de leur côté.
func _fresh_seed() -> int:
	return int(Time.get_unix_time_from_system()) ^ (randi() & 0xFFFF)
