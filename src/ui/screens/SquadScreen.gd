extends Screen

## Effectif : la page centrale du jeu.
##
## Six VUES sur le même effectif plutôt qu'un tableau fourre-tout. C'est le
## choix de Football Manager et il est bon : on ne se pose jamais toutes les
## questions en même temps. « Qui aligner ce soir » et « qui prolonger cet
## été » ne demandent pas les mêmes colonnes.
##
## Rappel : les niveaux affichés sont l'ESTIMATION du staff, pas la vérité.
## Même pour ses propres joueurs, on connaît bien mais pas parfaitement.

const VIEWS := [
	["general", "Général"],
	["contract", "Contrats"],
	["stats", "Statistiques"],
	["attrs", "Attributs"],
	["training", "Entraînement"],
	["dynamics", "Vestiaire"],
]


func build() -> void:
	var w := world()
	var r: Roster = game().my_roster()
	if r == null:
		add_child(UiKit.empty_state("Aucun roster."))
		return
	var module := w.module_for(r.game_id)
	var players := w.players_of(r.id)

	add_child(page_header("Effectif", "%d joueurs · %s · cohésion %.0f"
		% [players.size(), r.name, r.chemistry], [
			UiKit.button("Aligner les 5 meilleurs", func(): _auto_lineup(w, r)),
			UiKit.button("Tactique", func(): navigate("tactics")),
			UiKit.button("Entraînement", func(): navigate("training")),
		]))

	add_child(_lineup_strip(w, r, module, players))
	add_child(tab_bar("squad", VIEWS, "general"))

	var view := current_tab("squad", "general")
	# Le tri est mémorisé par vue : trier par salaire dans « Contrats » ne doit
	# pas réordonner « Statistiques » quand on y revient.
	var sort_key := "squad.sort." + view
	players.sort_custom(func(a: Player, b: Player):
		var sa := 1 if r.starters.has(a.id) else 0
		var sb := 1 if r.starters.has(b.id) else 0
		if sa != sb:
			return sa > sb
		return a.current_ability > b.current_ability)

	var cols: Array = []
	var rows: Array = []
	match view:
		"contract":
			cols = _contract_columns()
			rows = _contract_rows(w, r, players)
		"stats":
			cols = _stat_columns(module)
			rows = _stat_rows(module, players)
		"attrs":
			cols = _attr_columns(module)
			rows = _attr_rows(w, module, players)
		"training":
			cols = _training_columns()
			rows = _training_rows(w, module, players)
		"dynamics":
			cols = _dynamics_columns()
			rows = _dynamics_rows(w, r, players)
		_:
			cols = _general_columns()
			rows = _general_rows(w, r, module, players)

	add_child(sorted_table(sort_key, cols, rows, {
		"row_clicked": func(pid): navigate("player", {"player_id": pid}),
		"compact": view == "attrs",
	}))
	add_child(_legend(view))


# ============================================================================
# Bandeau du cinq de départ
# ============================================================================

func _lineup_strip(w: World, r: Roster, module: GameModule,
		players: Array) -> Control:
	var card := UiKit.card("Cinq de départ", 6, 10)
	var line := UiKit.hbox(8)
	card.body.add_child(line)
	if r.starters.is_empty():
		line.add_child(UiKit.label("Aucun titulaire désigné.", UiKit.FS_BODY_L,
			UiKit.BAD))
		return card.panel

	for pid in r.starters:
		var p := w.player(pid)
		if p == null:
			continue
		line.add_child(_lineup_slot(w, r, module, p))
	# Un rappel visible de ce qui manque : composition incomplète ou déséquilibrée.
	var warn := _composition_warning(w, r, module)
	if warn != "":
		line.add_child(UiKit.spacer())
		line.add_child(UiKit.pill(warn, UiKit.WARN, true))
	return card.panel


func _lineup_slot(w: World, r: Roster, module: GameModule, p: Player) -> Control:
	var role := r.role_of(p)
	var slot := UiKit.panel(8)
	var v := UiKit.vbox(1)
	slot.add_child(v)
	slot.custom_minimum_size = Vector2(150, 0)

	var top := UiKit.hbox(6)
	top.add_child(UiKit.label(p.display_name(), UiKit.FS_BODY_L, UiKit.TEXT, true))
	if p.is_igl:
		top.add_child(UiKit.pill("IGL", UiKit.ACCENT, true))
	v.add_child(top)
	v.add_child(UiKit.label(module.role_label(role), UiKit.FS_SMALL,
		RoleFamiliarity.color(p, role)))

	var cond := UiKit.hbox(5)
	cond.add_child(UiKit.meter(p.form, 100.0, 44, _grade(p.form)))
	cond.add_child(UiKit.meter(100.0 - p.fatigue, 100.0, 44,
		UiKit.GOOD if p.fatigue < 45.0 else UiKit.WARN))
	v.add_child(cond)
	if not p.is_available(w.today):
		v.add_child(UiKit.label("Indisponible", UiKit.FS_SMALL, UiKit.BAD))
	return slot


## Signale une composition impossible ou hors des bornes du méta, sans
## l'interdire : le joueur a le droit de tenter un cinq à deux duellistes.
func _composition_warning(w: World, r: Roster, module: GameModule) -> String:
	if r.starters.size() < module.team_size():
		return "Composition incomplète (%d/%d)" % [r.starters.size(),
			module.team_size()]
	var count := {}
	var unavailable := 0
	for pid in r.starters:
		var p := w.player(pid)
		if p == null:
			continue
		if not p.is_available(w.today):
			unavailable += 1
		var role := r.role_of(p)
		count[role] = int(count.get(role, 0)) + 1
	if unavailable > 0:
		return "%d titulaire(s) indisponible(s)" % unavailable
	for role in module.composition_bounds():
		var bounds: Array = module.composition_bounds()[role]
		var n := int(count.get(role, 0))
		if n < int(bounds[0]):
			return "Aucun %s aligné" % module.role_label(str(role)).to_lower()
	var igl := false
	for pid in r.starters:
		var p2 := w.player(pid)
		if p2 != null and p2.is_igl:
			igl = true
	if not igl:
		return "Pas d'IGL dans le cinq"
	return ""


# ============================================================================
# Vue générale
# ============================================================================

func _general_columns() -> Array:
	return [
		{"key": "slot", "label": "", "width": 28, "sortable": false},
		{"key": "name", "label": "Joueur", "width": 118},
		{"key": "role", "label": "Poste", "width": 122},
		{"key": "age", "label": "Âge", "width": 38, "align": "right"},
		{"key": "ca", "label": "Niveau", "width": 62, "align": "right"},
		{"key": "pot", "label": "Potentiel", "width": 78},
		{"key": "form", "label": "Forme", "width": 92},
		{"key": "morale", "label": "Moral", "width": 92},
		{"key": "cond", "label": "Condition", "width": 92},
		{"key": "status", "label": "État", "width": 168},
		{"key": "rating", "label": "Note", "width": 52, "align": "right"},
		{"key": "value", "label": "Valeur", "width": 78, "align": "right"},
	]


func _general_rows(w: World, r: Roster, module: GameModule,
		players: Array) -> Array:
	var rows: Array = []
	for p_v in players:
		var p: Player = p_v
		var rating := float(p.season_stats.get("rating", 0.0))
		var role := r.role_of(p)
		rows.append({
			"_id": p.id,
			"slot": {"text": "T" if r.starters.has(p.id) else "R",
				"color": UiKit.ACCENT if r.starters.has(p.id) else UiKit.TEXT_FAINT},
			"name": {"text": p.display_name(), "bold": r.starters.has(p.id)},
			"role": {"text": module.role_label(role)
					+ (" · IGL" if p.is_igl else ""),
				"color": RoleFamiliarity.color(p, role), "sort": role},
			"age": {"text": str(p.age(w.today)), "sort": p.age(w.today)},
			"ca": {"text": ScoutingSystem.ability_text(w, p),
				"sort": ScoutingSystem.estimated_ca(w, p)},
			"pot": {"text": UiKit.stars(ScoutingSystem.potential_value(w, p)),
				"color": UiKit.WARN,
				"sort": ScoutingSystem.potential_value(w, p)},
			"form": {"meter": p.form, "text": "%.0f" % p.form,
				"color": _grade(p.form), "sort": p.form},
			"morale": {"meter": p.morale, "text": "%.0f" % p.morale,
				"color": _grade(p.morale), "sort": p.morale},
			"cond": {"meter": 100.0 - p.fatigue, "text": "%.0f" % (100.0 - p.fatigue),
				"color": UiKit.GOOD if p.fatigue < 45.0 else UiKit.WARN,
				"sort": -p.fatigue},
			"status": _status(w, p),
			"rating": {"text": "%.2f" % rating if rating > 0.0 else "—",
				"color": UiKit.rating_color(rating), "sort": rating},
			"value": UiKit.money_cell(p.market_value),
		})
	return rows


# ============================================================================
# Vue contrats
# ============================================================================

func _contract_columns() -> Array:
	return [
		{"key": "name", "label": "Joueur", "width": 118},
		{"key": "age", "label": "Âge", "width": 38, "align": "right"},
		{"key": "promise", "label": "Statut promis", "width": 118},
		{"key": "salary", "label": "Salaire", "width": 88, "align": "right"},
		{"key": "share", "label": "Part masse", "width": 78, "align": "right"},
		{"key": "end", "label": "Échéance", "width": 92, "align": "right"},
		{"key": "buyout", "label": "Clause", "width": 84, "align": "right"},
		{"key": "prize", "label": "Gains", "width": 58, "align": "right"},
		{"key": "value", "label": "Valeur", "width": 80, "align": "right"},
		{"key": "happy", "label": "Satisfaction", "width": 88},
	]


func _contract_rows(w: World, r: Roster, players: Array) -> Array:
	var payroll := 0
	for p_v in players:
		var pl: Player = p_v
		payroll += pl.contract.salary_yearly if pl.contract != null else 0
	var rows: Array = []
	for p_v in players:
		var p: Player = p_v
		var c := p.contract
		var salary := c.salary_yearly if c != null else 0
		var left := c.days_remaining(w.today) if c != null else 0
		rows.append({
			"_id": p.id,
			"name": {"text": p.display_name()},
			"age": {"text": str(p.age(w.today)), "sort": p.age(w.today)},
			"promise": {"text": PlayingTime.label(p.promised_time),
				"color": PlayingTime.color(p.promised_time),
				"sort": p.promised_time},
			"salary": UiKit.money_cell(salary),
			"share": {"text": "%.0f %%" % (float(salary)
					/ maxf(float(payroll), 1.0) * 100.0),
				"sort": salary},
			"end": {"text": GameDate.format_duration_days(left),
				"color": UiKit.BAD if left < 120 else UiKit.TEXT, "sort": left},
			"buyout": UiKit.money_cell(c.buyout if c != null else 0),
			"prize": {"text": "%.0f %%" % (c.prize_share_pct if c != null else 0.0),
				"sort": c.prize_share_pct if c != null else 0.0},
			"value": UiKit.money_cell(p.market_value),
			"happy": {"meter": p.happiness, "text": "%.0f" % p.happiness,
				"color": _grade(p.happiness), "sort": p.happiness},
		})
	return rows


# ============================================================================
# Vue statistiques
# ============================================================================

func _stat_columns(module: GameModule) -> Array:
	var cols: Array = [
		{"key": "name", "label": "Joueur", "width": 118},
		{"key": "series", "label": "Séries", "width": 52, "align": "right"},
	]
	for c in module.stat_columns():
		var d: Dictionary = c
		cols.append({"key": str(d["key"]), "label": str(d["label"]),
			"width": 58, "align": "right"})
	cols.append({"key": "kd", "label": "K/D", "width": 54, "align": "right"})
	return cols


func _stat_rows(module: GameModule, players: Array) -> Array:
	var rows: Array = []
	for p_v in players:
		var p: Player = p_v
		var st: Dictionary = p.season_stats
		var series := int(st.get("series", 0))
		var row := {"_id": p.id, "name": {"text": p.display_name()},
			"series": {"text": str(series), "sort": series}}
		for c in module.stat_columns():
			var d: Dictionary = c
			var key := str(d["key"])
			var v := float(st.get(key, 0.0))
			var digits := int(d.get("digits", 0))
			var cell := {"text": ("—" if series == 0
				else ("%.*f" % [digits, v])), "sort": v}
			if key == "rating":
				cell["color"] = UiKit.rating_color(v)
			row[key] = cell
		var kd := float(st.get("kills", 0)) / maxf(float(st.get("deaths", 0)), 1.0)
		row["kd"] = {"text": "—" if series == 0 else "%.2f" % kd, "sort": kd,
			"color": UiKit.GOOD if kd >= 1.1 else (UiKit.BAD if kd < 0.9 else UiKit.TEXT)}
		rows.append(row)
	return rows


# ============================================================================
# Vue attributs
# ============================================================================

func _attr_columns(module: GameModule) -> Array:
	var cols: Array = [{"key": "name", "label": "Joueur", "width": 106}]
	for group_name in module.attribute_groups():
		for key in module.attribute_groups()[group_name]:
			cols.append({"key": str(key),
				"label": _short_label(module.attribute_label(str(key))),
				"width": 38, "align": "center"})
	return cols


## Trois lettres suffisent en en-tête d'une colonne de 38 px ; le nom complet
## reste lisible sur la fiche du joueur.
func _short_label(text: String) -> String:
	var parts := text.split(" ")
	if parts.size() >= 2:
		return (parts[0].substr(0, 2) + parts[1].substr(0, 1)).to_upper()
	return text.substr(0, 3).to_upper()


func _attr_rows(w: World, module: GameModule, players: Array) -> Array:
	var rows: Array = []
	for p_v in players:
		var p: Player = p_v
		var row := {"_id": p.id, "name": {"text": p.display_name()}}
		for group_name in module.attribute_groups():
			for key in module.attribute_groups()[group_name]:
				var k := str(key)
				var est := ScoutingSystem.estimated_attr(w, p, k)
				row[k] = {"attr": est, "text": ScoutingSystem.attr_text(w, p, k),
					"inverted": Attributes.is_negative(k),
					"sort": est}
		rows.append(row)
	return rows


# ============================================================================
# Vue entraînement
# ============================================================================

func _training_columns() -> Array:
	return [
		{"key": "name", "label": "Joueur", "width": 118},
		{"key": "age", "label": "Âge", "width": 38, "align": "right"},
		{"key": "focus", "label": "Travail individuel", "width": 150},
		{"key": "intensity", "label": "Intensité", "width": 96},
		{"key": "trend", "label": "Niveau 6 mois", "width": 92, "align": "right"},
		{"key": "head", "label": "Marge", "width": 70, "align": "right"},
		{"key": "fatigue", "label": "Fatigue", "width": 82},
		{"key": "burnout", "label": "Usure mentale", "width": 92},
		{"key": "sharp", "label": "Netteté", "width": 82},
	]


func _training_rows(w: World, module: GameModule, players: Array) -> Array:
	var rows: Array = []
	for p_v in players:
		var p: Player = p_v
		var trend := p.ca_trend(6)
		rows.append({
			"_id": p.id,
			"name": {"text": p.display_name()},
			"age": {"text": str(p.age(w.today)), "sort": p.age(w.today)},
			"focus": {"text": module.attribute_label(p.training_focus)
					if p.training_focus != "" else "Confié au coach",
				"color": UiKit.TEXT if p.training_focus != "" else UiKit.TEXT_FAINT,
				"sort": p.training_focus},
			"intensity": {"text": _intensity_label(p.training_intensity),
				"color": UiKit.WARN if p.training_intensity > 1.15
					else (UiKit.INFO if p.training_intensity < 0.85 else UiKit.TEXT),
				"sort": p.training_intensity},
			"trend": {"text": ("%+d" % trend) if trend != 0 else "—",
				"color": UiKit.GOOD if trend > 0 else (UiKit.BAD if trend < 0
					else UiKit.TEXT_DIM), "sort": trend},
			"head": {"text": "%.0f %%" % (p.growth_headroom() * 100.0),
				"sort": p.growth_headroom()},
			"fatigue": {"meter": p.fatigue, "text": "%.0f" % p.fatigue,
				"color": UiKit.BAD if p.fatigue > 65.0 else UiKit.WARN
					if p.fatigue > 40.0 else UiKit.GOOD, "sort": p.fatigue},
			"burnout": {"meter": p.burnout, "text": "%.0f" % p.burnout,
				"color": UiKit.BAD if p.burnout > 40.0 else UiKit.TEXT_DIM,
				"sort": p.burnout},
			"sharp": {"meter": p.sharpness, "text": "%.0f" % p.sharpness,
				"color": _grade(p.sharpness), "sort": p.sharpness},
		})
	return rows


func _intensity_label(v: float) -> String:
	if v >= 1.3:
		return "Maximale"
	if v >= 1.1:
		return "Soutenue"
	if v <= 0.7:
		return "Ménagé"
	if v <= 0.9:
		return "Allégée"
	return "Normale"


# ============================================================================
# Vue vestiaire
# ============================================================================

func _dynamics_columns() -> Array:
	return [
		{"key": "name", "label": "Joueur", "width": 118},
		{"key": "tier", "label": "Statut social", "width": 148},
		{"key": "influence", "label": "Influence", "width": 96},
		{"key": "personality", "label": "Personnalité", "width": 176},
		{"key": "relation", "label": "Entente moyenne", "width": 108},
		{"key": "concerns", "label": "Griefs", "width": 230, "expand": true},
	]


func _dynamics_rows(w: World, r: Roster, players: Array) -> Array:
	var tiers := {}
	for entry in DynamicsSystem.hierarchy(w, r):
		var d: Dictionary = entry
		tiers[(d["player"] as Player).id] = str(d["tier"])

	var rows: Array = []
	for p_v in players:
		var p: Player = p_v
		var rel := 0.0
		var n := 0
		for other_v in players:
			var other: Player = other_v
			if other.id == p.id:
				continue
			rel += float(p.relation_with(other.id))
			n += 1
		rel = rel / maxf(float(n), 1.0)
		var grief := ""
		for c in p.concerns:
			grief += ("  ·  " if grief != "" else "") \
				+ DynamicsSystem.grievance_label(str(c))
		rows.append({
			"_id": p.id,
			"name": {"text": p.display_name()},
			"tier": {"text": str(tiers.get(p.id, "Suiveur")),
				"color": UiKit.ACCENT if str(tiers.get(p.id, "")).begins_with("Patron")
					else UiKit.TEXT},
			"influence": {"meter": p.influence, "text": "%.0f" % p.influence,
				"color": UiKit.INFO, "sort": p.influence},
			"personality": {"text": PersonalityCalc.label(p),
				"color": PersonalityCalc.color(p)},
			"relation": {"meter": rel + 100.0, "max": 200.0,
				"text": "%+.0f" % rel, "sort": rel,
				"color": UiKit.GOOD if rel > 25.0 else (UiKit.BAD if rel < -15.0
					else UiKit.WARN)},
			"concerns": {"text": grief if grief != "" else "—",
				"color": UiKit.BAD if grief != "" else UiKit.TEXT_FAINT,
				"sort": p.concerns.size()},
		})
	return rows


# ============================================================================
# Divers
# ============================================================================

func _legend(view: String) -> Control:
	var text := ""
	match view:
		"attrs":
			text = "Valeurs estimées par votre staff. Une fourchette signale " \
				+ "une incertitude ; un recruteur compétent la réduit."
		"dynamics":
			text = "L'influence pèse sur le vestiaire indépendamment du niveau. " \
				+ "Un cadre mécontent contamine le groupe."
		"training":
			text = "« Niveau 6 mois » compare la capacité actuelle à celle " \
				+ "d'il y a six mois. Réglez le travail individuel sur la fiche du joueur."
		"contract":
			text = "Un contrat sous 120 jours devient urgent : au-delà, le " \
				+ "joueur discute librement avec la concurrence."
		_:
			text = "Cliquez une ligne pour ouvrir la fiche du joueur."
	return UiKit.label(text, UiKit.FS_SMALL, UiKit.TEXT_FAINT)


## Sélection automatique : meilleure note à chaque poste de la composition type.
func _auto_lineup(w: World, r: Roster) -> void:
	var module := w.module_for(r.game_id)
	var pool := w.players_of(r.id).filter(func(p: Player):
		return p.is_available(w.today))
	var chosen: Array[String] = []
	var assigned := {}
	var ideal: Dictionary = module.ideal_composition()
	for role in ideal:
		for _n in int(ideal[role]):
			var best: Player = null
			for p in pool:
				if chosen.has(p.id):
					continue
				var score := AbilityCalc.ca_as_role(p, module, str(role))
				if best == null or score > AbilityCalc.ca_as_role(best, module, str(role)):
					best = p
			if best != null:
				chosen.append(best.id)
				assigned[best.id] = str(role)
	# On complète si la composition idéale ne remplit pas les cinq places.
	for p in pool:
		if chosen.size() >= module.team_size():
			break
		if not chosen.has(p.id):
			chosen.append(p.id)
	game().set_starters(chosen)
	for pid in assigned:
		game().set_player_role(str(pid), str(assigned[pid]))


func _status(w: World, p: Player) -> Dictionary:
	if p.is_injured(w.today):
		return {"text": p.injury_label, "color": UiKit.BAD, "sort": 0}
	if p.wants_out:
		return {"text": "Veut partir", "color": UiKit.BAD, "sort": 1}
	if p.burnout > 55.0:
		return {"text": "Épuisement", "color": UiKit.BAD, "sort": 2}
	if not p.concerns.is_empty():
		return {"text": DynamicsSystem.grievance_label(str(p.concerns[0])),
			"color": UiKit.WARN, "sort": 3}
	if p.fatigue > 65.0:
		return {"text": "Fatigué", "color": UiKit.WARN, "sort": 4}
	if p.burnout > 30.0:
		return {"text": "Usé", "color": UiKit.WARN, "sort": 5}
	return {"text": "Disponible", "color": UiKit.GOOD, "sort": 9}


func _grade(v: float) -> Color:
	if v >= 65.0:
		return UiKit.GOOD
	if v <= 40.0:
		return UiKit.BAD
	return UiKit.WARN
