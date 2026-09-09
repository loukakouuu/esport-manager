class_name BracketBuilder
extends RefCounted

## Génération des calendriers et des arbres de tournoi.
##
## Toutes les rencontres d'une phase sont créées d'un coup, y compris celles
## dont on ne connaît pas encore les participants : un match de finale est créé
## avec des SOURCES ("vainqueur de fix_00031"). Le joueur voit donc l'arbre
## complet dès le départ, et la résolution consiste juste à remplir des cases.


## Ronde à l'italienne (méthode du cercle). Renvoie une liste de journées,
## chaque journée étant une liste de paires [home, away].
static func round_robin(participants: Array[String], double_round: bool = false) -> Array:
	var teams := participants.duplicate()
	if teams.size() % 2 == 1:
		teams.append("")   # exempt
	var n := teams.size()
	var days: Array = []
	for r in n - 1:
		var pairs: Array = []
		for i in n / 2:
			var a: String = teams[i]
			var b: String = teams[n - 1 - i]
			if a == "" or b == "":
				continue
			# On alterne la nomination domicile/extérieur pour équilibrer
			# les avantages de side pick sur la saison.
			if r % 2 == 0:
				pairs.append([a, b])
			else:
				pairs.append([b, a])
		days.append(pairs)
		# rotation : le premier reste fixe
		var last = teams.pop_back()
		teams.insert(1, last)
	if double_round:
		var second: Array = []
		for d in days:
			var rev: Array = []
			for p in d:
				rev.append([p[1], p[0]])
			second.append(rev)
		days.append_array(second)
	return days


## Arbre à élimination directe. `seeds` doit être trié du meilleur au moins bon.
## Renvoie une liste de rounds ; chaque entrée décrit un match par ses sources.
static func single_elim(seeds: Array[String]) -> Array:
	var size := _next_pow2(seeds.size())
	var slots := _seed_order(size)
	var rounds: Array = []

	var first: Array = []
	for i in range(0, size, 2):
		var a: String = seeds[slots[i]] if slots[i] < seeds.size() else ""
		var b: String = seeds[slots[i + 1]] if slots[i + 1] < seeds.size() else ""
		first.append({"home": a, "away": b, "home_src": {}, "away_src": {}})
	rounds.append(first)

	var count := first.size()
	var round_index := 0
	while count > 1:
		var next: Array = []
		for i in range(0, count, 2):
			next.append({
				"home": "", "away": "",
				"home_src": {"kind": "winner", "round": round_index, "match": i},
				"away_src": {"kind": "winner", "round": round_index, "match": i + 1},
			})
		rounds.append(next)
		count = next.size()
		round_index += 1
	return rounds


## Double élimination à 8 équipes — le format des playoffs VCT.
## 14 matchs : 7 en bracket haut, 6 en bracket bas, 1 grande finale.
static func double_elim_8(seeds: Array[String]) -> Array:
	var s := seeds.duplicate()
	while s.size() < 8:
		s.append("")
	var rounds: Array = []

	# Bracket haut — quarts (seeding 1v8, 4v5, 2v7, 3v6)
	rounds.append([
		{"b": "upper", "label": "Quart de finale", "home": s[0], "away": s[7]},
		{"b": "upper", "label": "Quart de finale", "home": s[3], "away": s[4]},
		{"b": "upper", "label": "Quart de finale", "home": s[1], "away": s[6]},
		{"b": "upper", "label": "Quart de finale", "home": s[2], "away": s[5]},
	])
	# Bracket haut — demies
	rounds.append([
		{"b": "upper", "label": "Demi-finale haute",
			"home_src": ["winner", 0, 0], "away_src": ["winner", 0, 1]},
		{"b": "upper", "label": "Demi-finale haute",
			"home_src": ["winner", 0, 2], "away_src": ["winner", 0, 3]},
	])
	# Bracket bas — tour 1 (perdants des quarts)
	rounds.append([
		{"b": "lower", "label": "Bracket bas — tour 1",
			"home_src": ["loser", 0, 0], "away_src": ["loser", 0, 1]},
		{"b": "lower", "label": "Bracket bas — tour 1",
			"home_src": ["loser", 0, 2], "away_src": ["loser", 0, 3]},
	])
	# Bracket haut — finale
	rounds.append([
		{"b": "upper", "label": "Finale haute",
			"home_src": ["winner", 1, 0], "away_src": ["winner", 1, 1]},
	])
	# Bracket bas — tour 2 (perdants des demies hautes)
	rounds.append([
		{"b": "lower", "label": "Bracket bas — tour 2",
			"home_src": ["loser", 1, 0], "away_src": ["winner", 2, 1]},
		{"b": "lower", "label": "Bracket bas — tour 2",
			"home_src": ["loser", 1, 1], "away_src": ["winner", 2, 0]},
	])
	# Bracket bas — demi-finale
	rounds.append([
		{"b": "lower", "label": "Demi-finale basse",
			"home_src": ["winner", 4, 0], "away_src": ["winner", 4, 1]},
	])
	# Bracket bas — finale
	rounds.append([
		{"b": "lower", "label": "Finale basse",
			"home_src": ["loser", 3, 0], "away_src": ["winner", 5, 0]},
	])
	# Grande finale
	rounds.append([
		{"b": "final", "label": "Grande finale",
			"home_src": ["winner", 3, 0], "away_src": ["winner", 6, 0]},
	])
	return rounds


static func _next_pow2(n: int) -> int:
	var p := 1
	while p < n:
		p *= 2
	return maxi(p, 2)


## Ordre de seeding classique : 1 affronte le dernier, 2 l'avant-dernier, etc.
static func _seed_order(size: int) -> Array[int]:
	var order: Array[int] = [0, 1]
	while order.size() < size:
		var next: Array[int] = []
		var n := order.size() * 2
		for v in order:
			next.append(v)
			next.append(n - 1 - v)
		order = next
	return order
