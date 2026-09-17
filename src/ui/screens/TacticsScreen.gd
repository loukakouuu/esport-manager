extends Screen

## Tactique : composition et réglages d'équipe.
##
## Les curseurs ne sont pas cosmétiques : ils entrent directement dans la
## formule de round (agressivité, discipline utilitaire, politique d'économie,
## part d'anti-strat). Chacun est décrit par son effet réel.
##
## L'écran ne connaît AUCUN curseur : c'est la discipline qui déclare ce qu'on
## peut régler (`GameModule.tactic_sliders`). Counter-Strike expose une
## priorité à l'AWP là où Valorant expose une prise de risque en post-plant,
## et cet écran affiche l'un ou l'autre sans rien savoir des deux.


func build() -> void:
	var w := world()
	var r: Roster = game().my_roster()
	if r == null:
		return
	var module := w.module_for(r.game_id)
	add_child(page_header("Tactique"))

	var body := UiKit.hbox(20)
	add_child(body)

	var left := UiKit.vbox(10)
	left.custom_minimum_size = Vector2(520, 0)
	body.add_child(left)
	left.add_child(UiKit.label("Cinq de départ", 15, UiKit.ACCENT))
	left.add_child(_lineup_editor(w, r, module))

	var right := UiKit.vbox(12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	right.add_child(UiKit.label("Réglages d'équipe — %s"
		% GameCatalog.label(r.game_id), 15, UiKit.ACCENT))
	for entry_v in module.tactic_sliders():
		var entry: Dictionary = entry_v
		right.add_child(_slider(r, str(entry["key"]), str(entry["label"]),
			str(entry.get("hint", ""))))
	right.add_child(_composition_report(w, r, module))


func _lineup_editor(w: World, r: Roster, module: GameModule) -> Control:
	var v := UiKit.vbox(4)
	for p in w.players_of(r.id):
		var row := UiKit.hbox(8)
		var is_starter := r.starters.has(p.id)
		var tag := UiKit.label("TITULAIRE" if is_starter else "REMPLAÇANT", 11,
			UiKit.ACCENT if is_starter else UiKit.TEXT_DIM)
		tag.custom_minimum_size = Vector2(90, 0)
		row.add_child(tag)
		var name := UiKit.label(p.display_name(), 13)
		name.custom_minimum_size = Vector2(120, 0)
		row.add_child(name)
		var role := UiKit.label(module.role_label(p.primary_role), 13, UiKit.TEXT_DIM)
		role.custom_minimum_size = Vector2(110, 0)
		row.add_child(role)
		row.add_child(UiKit.label(ScoutingSystem.ability_text(w, p), 13))
		row.add_child(UiKit.spacer())
		if not p.is_available(w.today):
			row.add_child(UiKit.label("indisponible", 12, UiKit.BAD))
		else:
			var pid := p.id
			row.add_child(UiKit.button("Sortir" if is_starter else "Aligner", func():
				var s := r.starters.duplicate()
				if s.has(pid):
					s.erase(pid)
				elif s.size() < module.team_size():
					s.append(pid)
				game().set_starters(s)))
		v.add_child(row)
	return v


func _slider(r: Roster, key: String, label_text: String, help: String) -> Control:
	var v := UiKit.vbox(2)
	var head := UiKit.hbox(8)
	var l := UiKit.label(label_text, 13)
	l.custom_minimum_size = Vector2(190, 0)
	head.add_child(l)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 5
	slider.value = float(r.tactic.get(key, 50))
	slider.custom_minimum_size = Vector2(220, 0)
	slider.drag_ended.connect(func(_changed):
		game().set_tactic(key, int(slider.value)))
	head.add_child(slider)
	head.add_child(UiKit.label(str(int(r.tactic.get(key, 50))), 13))
	v.add_child(head)
	v.add_child(UiKit.subtitle(help))
	return v


## Contrôle de composition. Les bornes appartiennent à la discipline : le méta
## Valorant impose un contrôleur et une sentinelle, Counter-Strike un AWPeur.
func _composition_report(w: World, r: Roster, module: GameModule) -> Control:
	var counts := {}
	for pid in r.starters:
		var p := w.player(pid)
		if p != null:
			counts[p.primary_role] = int(counts.get(p.primary_role, 0)) + 1
	var panel := UiKit.panel(10)
	var v := UiKit.vbox(4)
	panel.add_child(v)
	v.add_child(UiKit.label("Composition", 14, UiKit.ACCENT))
	var bounds := module.composition_bounds()
	for role in module.roles():
		var n := int(counts.get(role, 0))
		var ok := true
		if bounds.has(role):
			var b: Array = bounds[role]
			ok = n >= int(b[0]) and n <= int(b[1])
		v.add_child(UiKit.label("%s : %d" % [module.role_label(role), n], 13,
			UiKit.TEXT if ok else UiKit.WARN))
	var igls := 0
	for pid in r.starters:
		var p := w.player(pid)
		if p != null and p.is_igl:
			igls += 1
	v.add_child(UiKit.label("Capitaine en jeu : %s"
		% ("oui" if igls > 0 else "AUCUN — l'équipe perdra en lecture de jeu"), 13,
		UiKit.GOOD if igls > 0 else UiKit.BAD))
	return panel
