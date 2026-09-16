extends Screen

## La STRUCTURE : ce que possède la maison, par-dessus les équipes.
##
## Distinction structurante du projet (voir src/model/Organization.gd) : la
## structure est l'entreprise — une trésorerie, une marque, une direction — et
## chaque Roster est une équipe engagée sur une discipline. Cet écran est le
## seul endroit où l'on voit la maison entière : ses sections, son palmarès,
## son propriétaire. C'est aussi d'ici qu'on choisit l'équipe à diriger.

const TABS := [
	["sections", "Sections"],
	["identity", "Identité"],
	["history", "Palmarès"],
]


func build() -> void:
	var o: Organization = game().my_org()
	if o == null:
		add_child(UiKit.empty_state("Aucune structure dirigée."))
		return

	add_child(page_header(o.name, "%s · %s · fondée en %d"
		% [o.owner_label(), o.country, o.founded_year]))
	add_child(tab_bar("club", TABS, "sections"))

	match current_tab("club", "sections"):
		"identity":
			_tab_identity(o)
		"history":
			_tab_history(o)
		_:
			_tab_sections(o)


# ============================================================================
# Sections
# ============================================================================

func _tab_sections(o: Organization) -> void:
	var parts := split(340)
	var main: VBoxContainer = parts[0]
	var side: VBoxContainer = parts[1]

	var entries: Array = game().sections()
	for entry_v in entries:
		main.add_child(_section_card(entry_v))

	if o.upcoming_games().size() > 0:
		main.add_child(UiKit.wrap(
			"Les sections grisées font partie de la structure — elles pèsent "
			+ "sur sa réputation et sur son budget — mais le moteur ne simule "
			+ "encore que Valorant. Elles s'ouvriront quand la discipline "
			+ "correspondante sera jouable, sans qu'il faille recommencer une "
			+ "carrière.", UiKit.FS_SMALL, UiKit.TEXT_FAINT))
	main.add_child(UiKit.vspacer())

	side.add_child(_summary_card(o))


func _section_card(entry_v) -> Control:
	var entry: Dictionary = entry_v
	var w := world()
	var game_id := str(entry["game_id"])
	var playable := bool(entry["playable"])
	var current := bool(entry["current"])
	var color := GameCatalog.color(game_id)

	var card := UiKit.card("", 7, 12)
	if current:
		card.panel.add_theme_stylebox_override("panel",
			UiKit.box(UiKit.BG_PANEL, 8, 12, color, 1))

	var head := UiKit.hbox(10)
	head.add_child(UiKit.crest(GameCatalog.short(game_id), color, 34))
	var idn := UiKit.vbox(1)
	idn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := UiKit.hbox(7)
	title.add_child(UiKit.label(GameCatalog.label(game_id), UiKit.FS_LEAD,
		UiKit.TEXT if playable else UiKit.TEXT_DIM, true))
	title.add_child(UiKit.pill(str(entry["detail"]),
		color if playable else UiKit.TEXT_FAINT, current))
	if current:
		title.add_child(UiKit.pill("dirigée", UiKit.ACCENT, true))
	idn.add_child(title)
	idn.add_child(UiKit.label(GameCatalog.publisher(game_id), UiKit.FS_SMALL,
		UiKit.TEXT_FAINT))
	head.add_child(idn)

	if not playable:
		head.add_child(UiKit.pill("non simulée", UiKit.TEXT_FAINT))
		card.body.add_child(head)
		return card.panel

	var rid := str(entry["roster_id"])
	if not current:
		head.add_child(UiKit.button("Diriger cette équipe", func():
			if game().select_roster(rid):
				navigate("squad")))
	head.add_child(UiKit.ghost("Effectif ▸", func():
		if game().select_roster(rid):
			navigate("squad")))
	card.body.add_child(head)

	var r := w.roster(rid)
	if r == null:
		return card.panel
	card.body.add_child(UiKit.separator())
	card.body.add_child(_roster_line(r))
	return card.panel


## Ligne de synthèse d'une équipe : les quatre chiffres qui disent son état.
func _roster_line(r: Roster) -> Control:
	var w := world()
	var h := UiKit.hbox(18)
	h.add_child(UiKit.stat_block("Joueurs", str(r.size())))
	h.add_child(UiKit.stat_block("Niveau moyen", _avg_ca_text(r)))
	h.add_child(UiKit.stat_block("Cohésion", "%d %%" % int(r.chemistry)))
	h.add_child(UiKit.stat_block("Ligue", _league_of(r)))
	var record := _season_record(r)
	if record != "":
		h.add_child(UiKit.stat_block("Bilan", record))
	h.add_child(UiKit.spacer())
	var atm := DynamicsSystem.atmosphere(w, r)
	h.add_child(UiKit.pill(DynamicsSystem.atmosphere_label(atm),
		UiKit.GOOD if atm >= 62.0 else (UiKit.WARN if atm >= 40.0 else UiKit.BAD)))
	return h


func _avg_ca_text(r: Roster) -> String:
	var w := world()
	var total := 0.0
	var n := 0
	for p in w.players_of(r.id):
		total += float(p.current_ability)
		n += 1
	if n == 0:
		return "—"
	return UiKit.stars(total / float(n) / 40.0)


func _league_of(r: Roster) -> String:
	var w := world()
	for cid in r.competition_ids:
		var c := w.competition(cid)
		if c != null and c.kind == Competition.Kind.LEAGUE:
			return c.name
	return r.region


func _season_record(r: Roster) -> String:
	var wins := 0
	var losses := 0
	for cid in r.season_record:
		var rec: Dictionary = r.season_record[cid]
		wins += int(rec.get("w", 0))
		losses += int(rec.get("l", 0))
	if wins + losses == 0:
		return ""
	return "%d V — %d D" % [wins, losses]


# ============================================================================
# Synthèse
# ============================================================================

func _summary_card(o: Organization) -> Control:
	var w := world()
	var card := UiKit.card("La maison", 7, 12)
	card.body.add_child(UiKit.kv("Propriétaire", o.owner_label()))
	card.body.add_child(UiKit.kv("Réputation", UiKit.stars(o.stars())))
	card.body.add_child(UiKit.kv("Fans", _short(o.fanbase)))
	card.body.add_child(UiKit.kv("Trésorerie", Money.fmt(o.cash())))
	card.body.add_child(UiKit.kv("Valorisation", Money.fmt_short(o.brand_value)))
	card.body.add_child(UiKit.kv("Masse salariale",
		"%s / an" % Money.fmt_short(FinanceSystem.wage_bill_yearly(w, o))))
	card.body.add_child(UiKit.separator())
	card.body.add_child(UiKit.caption("Confiance de la direction"))
	card.body.add_child(UiKit.meter(o.board_confidence, 100.0, 220,
		UiKit.GOOD if o.board_confidence > 55.0
			else (UiKit.WARN if o.board_confidence > 30.0 else UiKit.BAD)))
	card.body.add_child(UiKit.separator())
	card.body.add_child(UiKit.caption("Objectifs de la saison"))
	if o.objectives.is_empty():
		card.body.add_child(UiKit.label("Aucun objectif en cours.",
			UiKit.FS_BODY, UiKit.TEXT_FAINT))
	for obj_v in o.objectives:
		var obj: Dictionary = obj_v
		card.body.add_child(UiKit.wrap("— %s" % str(obj.get("label", "")),
			UiKit.FS_BODY, UiKit.TEXT_DIM))
	return card.panel


# ============================================================================
# Identité
# ============================================================================

func _tab_identity(o: Organization) -> void:
	var parts := split(380)
	var main: VBoxContainer = parts[0]
	var side: VBoxContainer = parts[1]

	var card := UiKit.card("Identité", 7, 14)
	var head := UiKit.hbox(12)
	head.add_child(UiKit.crest(o.tag, UiKit.org_color(o), 56))
	var v := UiKit.vbox(2)
	v.add_child(UiKit.label(o.name, UiKit.FS_H2, UiKit.TEXT, true))
	var chips := UiKit.hbox(6)
	chips.add_child(UiKit.pill(o.tag, UiKit.ACCENT, true))
	chips.add_child(UiKit.pill(o.country))
	chips.add_child(UiKit.pill(o.region, UiKit.INFO))
	v.add_child(chips)
	head.add_child(v)
	card.body.add_child(head)
	card.body.add_child(UiKit.separator())
	card.body.add_child(UiKit.kv("Fondée en", str(o.founded_year)))
	card.body.add_child(UiKit.kv("Propriétaire", o.owner_label()))
	card.body.add_child(UiKit.kv("Disciplines", _games_text(o)))
	card.body.add_child(UiKit.kv("Équipes", str(world().rosters_of(o.id).size())))
	card.body.add_child(UiKit.kv("Membres du staff", str(o.staff_ids.size())))
	main.add_child(card.panel)
	main.add_child(UiKit.vspacer())

	side.add_child(_facilities_card(o))


func _games_text(o: Organization) -> String:
	var parts: Array[String] = []
	for g in o.games:
		parts.append(GameCatalog.label(str(g)))
	return ", ".join(parts)


func _facilities_card(o: Organization) -> Control:
	var card := UiKit.card("Infrastructures", 6, 12)
	for kind in Facilities.Kind.values():
		var lvl := o.facility_level(kind)
		card.body.add_child(UiKit.bar_row(Facilities.label(kind),
			float(lvl) / float(Facilities.MAX_LEVEL) * 100.0,
			UiKit.GOOD if lvl >= 3 else (UiKit.WARN if lvl >= 1 else UiKit.BAD)))
	card.body.add_child(UiKit.ghost("Gérer les infrastructures ▸",
		func(): navigate("facilities")))
	return card.panel


# ============================================================================
# Palmarès
# ============================================================================

func _tab_history(o: Organization) -> void:
	var w := world()
	var rows: Array = []
	for entry_v in w.history:
		var entry: Dictionary = entry_v
		if str(entry.get("champion_org_id", "")) != o.id:
			continue
		rows.append({
			"year": {"text": str(entry.get("year", "")),
				"sort": int(entry.get("year", 0))},
			"title": {"text": str(entry.get("comp_name",
				entry.get("comp_key", "—"))), "bold": true},
		})
	if rows.is_empty():
		add_child(UiKit.empty_state("Aucun titre pour l'instant.",
			"Les trophées remportés apparaîtront ici, saison par saison."))
		return
	add_child(sorted_table("club.history", [
		{"key": "year", "label": "Saison", "width": 80},
		{"key": "title", "label": "Titre", "width": 320},
	], rows))


# ============================================================================

func _short(n: int) -> String:
	if n >= 1_000_000:
		return "%s M" % String.num(float(n) / 1_000_000.0, 1)
	if n >= 1000:
		return "%d k" % int(n / 1000)
	return str(n)
