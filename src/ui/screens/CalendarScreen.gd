extends Screen

## Calendrier : rencontres passées et à venir de la structure.


func build() -> void:
	var w := world()
	var r: Roster = game().my_roster()
	if r == null:
		return
	add_child(UiKit.title("Calendrier"))

	var all: Array[Fixture] = []
	for fid in w.fixtures:
		var f: Fixture = w.fixtures[fid]
		if f.involves(r.id):
			all.append(f)
	all.sort_custom(func(a: Fixture, b: Fixture): return a.day < b.day)

	var columns := [
		{"label": "Date", "width": 110},
		{"label": "Compétition", "width": 150},
		{"label": "Tour", "width": 170},
		{"label": "Adversaire", "width": 170},
		{"label": "Format", "width": 55},
		{"label": "Résultat", "width": 80, "align": "center"},
		{"label": "Détail", "width": 220, "expand": true},
	]
	var rows: Array = []
	for f in all:
		var comp := w.competition(f.competition_id)
		var opp := w.roster(f.opponent_of(r.id))
		var opp_org := w.org(opp.org_id) if opp != null else null
		var score := {"text": "à venir", "color": UiKit.TEXT_DIM}
		var detail := ""
		if f.played and f.result != null:
			var won := f.result.winner_id == r.id
			var mine: int = f.result.home_score if f.home_id == r.id \
				else f.result.away_score
			var theirs: int = f.result.away_score if f.home_id == r.id \
				else f.result.home_score
			score = {"text": "%d-%d" % [mine, theirs],
				"color": UiKit.GOOD if won else UiKit.BAD}
			detail = f.result.map_score_text()
		rows.append([
			GameDate.format_full(f.day),
			comp.short_name if comp != null else "",
			f.round_label,
			opp_org.name if opp_org != null else "à déterminer",
			"BO%d" % f.best_of,
			score, detail,
		])
	add_child(UiKit.scroll(UiKit.table(columns, rows, func(i: int):
		if all[i].played:
			game().last_player_result = all[i].result
			game().last_player_fixture = all[i]
			navigate("match"))))
