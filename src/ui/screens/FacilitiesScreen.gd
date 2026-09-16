extends Screen

## Infrastructures : l'arbitrage long terme du jeu.
## Chaque niveau améliore un système précis mais alourdit les charges fixes.

const EFFECTS := {
	Facilities.Kind.OFFICE: "Crédibilité auprès des sponsors et des joueurs",
	Facilities.Kind.TRAINING_ROOM: "Progression des joueurs et cohésion",
	Facilities.Kind.TEAM_HOUSE: "Récupération de la fatigue",
	Facilities.Kind.ANALYTICS: "Efficacité de la préparation adverse",
	Facilities.Kind.WELLNESS: "Prévention des blessures et du burnout",
	Facilities.Kind.CONTENT_STUDIO: "Revenus de contenu et fanbase",
	Facilities.Kind.ACADEMY: "Développement des jeunes joueurs",
}


func build() -> void:
	var w := world()
	var o: Organization = game().my_org()
	if o == null:
		return
	add_child(page_header("Infrastructures"))
	add_child(UiKit.subtitle(
		"Charges d'entretien actuelles : %s / mois. Un investissement se "
		% Money.fmt(Facilities.total_monthly_upkeep(o.facilities))
		+ "rentabilise sur plusieurs saisons — jamais sur une."))

	var list := UiKit.vbox(8)
	for k_v in Facilities.Kind.values():
		var k: int = k_v
		var lvl := o.facility_level(k)
		var panel := UiKit.panel(10)
		var h := UiKit.hbox(12)
		panel.add_child(h)

		var info := UiKit.vbox(2)
		info.custom_minimum_size = Vector2(320, 0)
		info.add_child(UiKit.label(Facilities.label(k), 15))
		info.add_child(UiKit.subtitle(str(EFFECTS.get(k, ""))))
		h.add_child(info)

		var levels := UiKit.vbox(2)
		levels.add_child(UiKit.label("Niveau %d / %d" % [lvl, Facilities.MAX_LEVEL], 13))
		levels.add_child(UiKit.meter(float(lvl), float(Facilities.MAX_LEVEL), 140))
		h.add_child(levels)

		h.add_child(UiKit.label("Entretien %s / mois"
			% Money.fmt_short(Facilities.monthly_upkeep(k, lvl)), 13, UiKit.TEXT_DIM))
		h.add_child(UiKit.spacer())

		if lvl < Facilities.MAX_LEVEL:
			var cost := Facilities.upgrade_cost(k, lvl + 1)
			var extra := Facilities.monthly_upkeep(k, lvl + 1) \
				- Facilities.monthly_upkeep(k, lvl)
			var affordable := o.ledger.cash >= cost
			var col := UiKit.vbox(2)
			col.add_child(UiKit.label("Investir %s" % Money.fmt(cost), 13,
				UiKit.TEXT if affordable else UiKit.BAD))
			col.add_child(UiKit.subtitle("+%s / mois de charges"
				% Money.fmt_short(extra)))
			h.add_child(col)
			var kind: int = k
			var b := UiKit.button("Améliorer", func():
				game().upgrade_facility(kind))
			b.disabled = not affordable
			h.add_child(b)
		else:
			h.add_child(UiKit.label("Niveau maximum", 13, UiKit.GOOD))
		list.add_child(panel)
	add_child(UiKit.scroll(list))
