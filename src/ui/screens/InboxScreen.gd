extends Screen

## Boîte de réception : le fil narratif de la partie.


func build() -> void:
	var w := world()
	var head := UiKit.hbox(10)
	head.add_child(UiKit.title("Messages"))
	head.add_child(UiKit.spacer())
	head.add_child(UiKit.button("Tout marquer comme lu", func():
		for n in w.inbox:
			(n as Dictionary)["read"] = true
		refresh()))
	add_child(head)

	var list := UiKit.vbox(6)
	for i in range(w.inbox.size() - 1, -1, -1):
		var n: Dictionary = w.inbox[i]
		var panel := UiKit.panel(10)
		var v := UiKit.vbox(4)
		panel.add_child(v)
		var title_row := UiKit.hbox(8)
		title_row.add_child(UiKit.label(str(n["title"]), 15,
			UiKit.TEXT if not bool(n.get("read", false)) else UiKit.TEXT_DIM))
		title_row.add_child(UiKit.spacer())
		title_row.add_child(UiKit.label(GameDate.format_long(int(n["day"])), 12,
			UiKit.TEXT_DIM))
		title_row.add_child(_kind_badge(str(n.get("kind", "info"))))
		v.add_child(title_row)
		v.add_child(UiKit.label(str(n["body"]), 13, UiKit.TEXT_DIM))
		var meta: Dictionary = n.get("meta", {})
		if meta.has("player_id"):
			var pid := str(meta["player_id"])
			v.add_child(UiKit.button("Voir la fiche du joueur", func():
				navigate("player", {"player_id": pid})))
		list.add_child(panel)
	add_child(UiKit.scroll(list))


func _kind_badge(kind: String) -> Control:
	var colors := {
		"warning": UiKit.WARN, "gameover": UiKit.BAD, "board": UiKit.ACCENT,
		"result": UiKit.GOOD, "transfer": UiKit.ACCENT, "finance": UiKit.GOOD,
		"squad": UiKit.WARN, "contract": UiKit.TEXT, "sponsor": UiKit.GOOD,
	}
	var labels := {
		"warning": "ALERTE", "gameover": "CRITIQUE", "board": "DIRECTION",
		"result": "RÉSULTAT", "transfer": "MARCHÉ", "finance": "FINANCES",
		"squad": "EFFECTIF", "contract": "CONTRAT", "sponsor": "SPONSOR",
		"season": "SAISON", "info": "INFO",
	}
	return UiKit.label(str(labels.get(kind, "INFO")), 11,
		colors.get(kind, UiKit.TEXT_DIM))
