class_name BoardSystem
extends RefCounted

## La direction : objectifs de saison et confiance.
##
## Sa fonction de game design est de donner un cap et une pression. Elle juge
## sur DEUX axes indépendants — le sportif et le financier — parce que c'est la
## réalité d'une structure esport : gagner en dépensant trois fois ses revenus
## n'est pas une réussite, et survivre en finissant dernier non plus.

const CONFIDENCE_LABELS := [
	[0.0, "Rupture de confiance"],
	[20.0, "Très mécontente"],
	[40.0, "Mécontente"],
	[55.0, "Circonspecte"],
	[70.0, "Satisfaite"],
	[85.0, "Très satisfaite"],
	[101.0, "Enthousiaste"],
]


static func confidence_label(v: float) -> String:
	for row in CONFIDENCE_LABELS:
		if v < float(row[0]):
			return str(row[1])
	return "Enthousiaste"


## Fixe les objectifs de la saison selon le rang attendu de la structure dans
## sa ligue. Une équipe classée 10e sur 12 n'a pas à viser le titre.
static func season_objectives(world: World, org: Organization) -> Array:
	var r := world.main_roster(org.id, world.player_game_id)
	if r == null:
		return []
	var peers := _league_peers(world, r.league_key)
	var rank := _expected_rank(world, org, peers)
	var total := maxi(peers.size(), 1)
	var tier1 := r.league_key.begins_with("vct")
	var out: Array = []

	var share := float(rank) / float(total)
	if share <= 0.25:
		out.append(_obj("title", "Remporter la ligue" if tier1
			else "Remporter le split", 1, 3.0))
		out.append(_obj("playoffs", "Atteindre les playoffs", 8, 1.0))
	elif share <= 0.55:
		out.append(_obj("top4", "Terminer dans le top 4", 4, 2.0))
		out.append(_obj("playoffs", "Atteindre les playoffs", 8, 1.5))
	else:
		out.append(_obj("playoffs", "Atteindre les playoffs", 8, 2.0))
		out.append(_obj("survive", "Ne pas finir dernier", total - 1, 1.0))

	if tier1:
		out.append(_obj("international", "Se qualifier pour un tournoi international",
			1, 1.5))
	else:
		out.append(_obj("ascension", "Se qualifier pour l'Ascension", 4, 2.0))

	# Objectif financier : toujours présent, jamais négociable.
	out.append(_obj("finance", "Terminer la saison sans déficit", 0, 2.0))
	return out


static func _obj(key: String, label: String, target: int, weight: float) -> Dictionary:
	return {"key": key, "label": label, "target": target, "weight": weight,
		"met": false, "evaluated": false}


static func _league_peers(world: World, league_key: String) -> Array[String]:
	var out: Array[String] = []
	for rid in world.rosters:
		var r: Roster = world.rosters[rid]
		if r.league_key == league_key and not r.is_academy:
			out.append(rid)
	return out


## Rang attendu : on classe les structures de la ligue par force du roster,
## pondérée par la réputation. C'est l'attente « raisonnable » du board.
static func _expected_rank(world: World, org: Organization,
		peers: Array[String]) -> int:
	var scored: Array = []
	for rid in peers:
		var r := world.roster(rid)
		var o := world.org(r.org_id)
		if o == null:
			continue
		var ca := 0.0
		var n := 0
		for p in world.players_of(rid):
			if r.starters.has(p.id):
				ca += float(p.current_ability)
				n += 1
		var strength := (ca / maxf(float(n), 1.0)) * 0.7 + float(o.reputation) / 100.0 * 0.3
		scored.append({"org_id": o.id, "score": strength})
	scored.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))
	for i in scored.size():
		if str(scored[i]["org_id"]) == org.id:
			return i + 1
	return scored.size()


## Bilan de fin de saison : met à jour la confiance et peut mettre fin à la
## partie si la direction perd patience.
static func evaluate_season(world: World, org: Organization) -> Dictionary:
	var r := world.main_roster(org.id, world.player_game_id)
	var report := {"met": 0, "total": 0, "delta": 0.0, "details": []}
	if r == null:
		return report

	var final_rank := _final_rank(world, r)
	var reached_international := _reached_international(world, r)
	var yearly := org.ledger.net(GameDate.add_years(world.today, -1), world.today)

	var score := 0.0
	var weight_total := 0.0
	for obj_v in org.objectives:
		var obj: Dictionary = obj_v
		var met := false
		match str(obj["key"]):
			"title": met = final_rank == 1
			"top4": met = final_rank > 0 and final_rank <= 4
			"playoffs": met = final_rank > 0 and final_rank <= int(obj["target"])
			"survive": met = final_rank > 0 and final_rank <= int(obj["target"])
			"international", "ascension": met = reached_international
			"finance": met = yearly >= 0
		obj["met"] = met
		obj["evaluated"] = true
		var w := float(obj["weight"])
		weight_total += w
		score += w if met else 0.0
		report["total"] = int(report["total"]) + 1
		if met:
			report["met"] = int(report["met"]) + 1
		(report["details"] as Array).append(obj.duplicate())

	var ratio := score / maxf(weight_total, 0.001)
	var delta := (ratio - 0.55) * 45.0
	org.board_confidence = clampf(org.board_confidence + delta, 0.0, 100.0)
	report["delta"] = delta

	if org.board_confidence <= 8.0 and world.player_org_id == org.id:
		world.add_news(world.today, "Fin de mission",
			"La direction de %s met fin à vos fonctions." % org.name, "gameover")
	return report


static func _final_rank(world: World, r: Roster) -> int:
	for cid in world.competitions:
		var c: Competition = world.competitions[cid]
		if c.key != r.league_key or c.status != Competition.Status.FINISHED:
			continue
		var idx := c.final_ranking.find(r.id)
		if idx >= 0:
			return idx + 1
	return 0


static func _reached_international(world: World, r: Roster) -> bool:
	for cid in world.competitions:
		var c: Competition = world.competitions[cid]
		if c.kind != Competition.Kind.INTERNATIONAL \
				and c.kind != Competition.Kind.ASCENSION:
			continue
		if c.participants.has(r.id):
			return true
	return false
