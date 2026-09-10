extends Screen

## Effectif : la page centrale du jeu.
##
## Elle n'affiche PAS les attributs réels mais l'estimation issue du scouting
## interne — même pour ses propres joueurs, on connaît bien mais pas
## parfaitement. Les valeurs sûres sont les stats de match, pas les notes.


func build() -> void:
	var w := world()
	var r: Roster = game().my_roster()
	if r == null:
		add_child(UiKit.subtitle("Aucun roster."))
		return

	var header := UiKit.hbox(14)
	header.add_child(UiKit.title("Effectif"))
	header.add_child(UiKit.button("Aligner les 5 meilleurs", func():
		_auto_lineup(w, r)))
	header.add_child(UiKit.button("Régler la tactique",
		func(): navigate("tactics")))
	header.add_child(UiKit.spacer())
	header.add_child(UiKit.label("Cohésion", 13, UiKit.TEXT_DIM))
	header.add_child(UiKit.meter(r.chemistry, 100.0, 120,
		UiKit.GOOD if r.chemistry > 65.0 else UiKit.WARN))
	header.add_child(UiKit.label("%.0f" % r.chemistry, 13))
	add_child(header)
	add_child(UiKit.subtitle(
		"Le « niveau » est une estimation de votre staff, pas une valeur exacte. "
		+ "Un recruteur compétent réduit la marge d'erreur."))

	var players := w.players_of(r.id)
	players.sort_custom(func(a: Player, b: Player):
		var sa := 1 if r.starters.has(a.id) else 0
		var sb := 1 if r.starters.has(b.id) else 0
		if sa != sb:
			return sa > sb
		return a.current_ability > b.current_ability)

	var columns := [
		{"label": "", "width": 26},
		{"label": "Joueur", "width": 120},
		{"label": "Poste", "width": 125},
		{"label": "Âge", "width": 40, "align": "right"},
		{"label": "Niveau", "width": 60, "align": "right"},
		{"label": "Forme", "width": 55, "align": "right"},
		{"label": "Moral", "width": 55, "align": "right"},
		{"label": "État", "width": 140},
		{"label": "Note", "width": 55, "align": "right"},
		{"label": "ACS", "width": 55, "align": "right"},
		{"label": "Salaire", "width": 85, "align": "right"},
		{"label": "Contrat", "width": 80, "align": "right"},
		{"label": "Valeur", "width": 85, "align": "right"},
	]
	var rows: Array = []
	for p in players:
		var st: Dictionary = p.season_stats
		var rating := float(st.get("rating", 0.0))
		rows.append([
			{"text": "T" if r.starters.has(p.id) else "R",
				"color": UiKit.ACCENT if r.starters.has(p.id) else UiKit.TEXT_DIM},
			p.display_name(),
			(world().module_for(p.game_id) as GameModule).role_label(p.primary_role)
				+ (" (IGL)" if p.is_igl else ""),
			str(p.age(w.today)),
			ScoutingSystem.ability_text(world(), p),
			{"text": "%.0f" % p.form, "color": _grade(p.form)},
			{"text": "%.0f" % p.morale, "color": _grade(p.morale)},
			_status(w, p),
			{"text": "%.2f" % rating if rating > 0.0 else "-",
				"color": UiKit.rating_color(rating)},
			"%.0f" % float(st.get("acs", 0.0)) if rating > 0.0 else "-",
			Money.fmt_short(p.contract.salary_yearly if p.contract != null else 0),
			GameDate.format_duration_days(
				p.contract.days_remaining(w.today) if p.contract != null else -1),
			Money.fmt_short(p.market_value),
		])

	add_child(UiKit.scroll(UiKit.table(columns, rows, func(i: int):
		navigate("player", {"player_id": players[i].id}))))



## Sélection automatique : meilleure note à chaque poste de la composition type.
func _auto_lineup(w: World, r: Roster) -> void:
	var module := w.module_for(r.game_id)
	var pool := w.players_of(r.id).filter(func(p: Player):
		return p.is_available(w.today))
	var chosen: Array[String] = []
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
	# On complète si la composition idéale ne remplit pas les cinq places.
	for p in pool:
		if chosen.size() >= module.team_size():
			break
		if not chosen.has(p.id):
			chosen.append(p.id)
	game().set_starters(chosen)


func _status(w: World, p: Player) -> Dictionary:
	if p.is_injured(w.today):
		return {"text": p.injury_label, "color": UiKit.BAD}
	if p.wants_out:
		return {"text": "Veut partir", "color": UiKit.BAD}
	if p.burnout > 55.0:
		return {"text": "Épuisement", "color": UiKit.BAD}
	if p.fatigue > 65.0:
		return {"text": "Fatigué", "color": UiKit.WARN}
	if p.burnout > 30.0:
		return {"text": "Usé", "color": UiKit.WARN}
	return {"text": "Disponible", "color": UiKit.GOOD}


func _grade(v: float) -> Color:
	if v >= 65.0:
		return UiKit.GOOD
	if v <= 40.0:
		return UiKit.BAD
	return UiKit.TEXT
