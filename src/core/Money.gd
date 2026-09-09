class_name Money
extends RefCounted

## Toute somme d'argent du jeu est un ENTIER de cents (int64).
## Jamais de float : les arrondis flottants dérivent et un système financier
## qui dérive n'est plus crédible. 1 $ = 100 cents.

const CENT := 1
const UNIT := 100          # 1 dollar
const K := 100_000         # 1 000 $
const M := 100_000_000     # 1 000 000 $

const SYMBOL := "$"


static func from_units(units: float) -> int:
	return int(round(units * float(UNIT)))


static func to_units(cents: int) -> float:
	return float(cents) / float(UNIT)


## Applique un pourcentage (0..100) avec arrondi correct, sans float parasite.
static func pct(cents: int, percent: float) -> int:
	return int(round(float(cents) * percent / 100.0))


## Répartit `cents` selon des poids, sans perdre le moindre cent (le reste
## va aux premiers de la liste). Utilisé pour les cashprizes et les splits.
static func split(cents: int, weights: Array) -> Array[int]:
	var total_w := 0.0
	for w in weights:
		total_w += float(w)
	var out: Array[int] = []
	if total_w <= 0.0:
		out.resize(weights.size())
		out.fill(0)
		return out
	var allocated := 0
	for w in weights:
		var part := int(floor(float(cents) * float(w) / total_w))
		out.append(part)
		allocated += part
	var remainder := cents - allocated
	var i := 0
	while remainder > 0 and out.size() > 0:
		out[i % out.size()] += 1
		remainder -= 1
		i += 1
	return out


## "1 250 000 $"
static func fmt(cents: int) -> String:
	var neg := cents < 0
	var units := int(abs(cents)) / UNIT
	var s := _group(units)
	if neg:
		s = "-" + s
	return s + " " + SYMBOL


## Format compact pour les tableaux : "1,25 M$", "45 k$"
static func fmt_short(cents: int) -> String:
	var neg := cents < 0
	var a := int(abs(cents))
	var s := ""
	if a >= M:
		s = String.num(float(a) / float(M), 2) + " M"
	elif a >= 10 * K:
		s = String.num(float(a) / float(K), 0) + " k"
	elif a >= K:
		s = String.num(float(a) / float(K), 1) + " k"
	else:
		s = String.num(float(a) / float(UNIT), 0)
	if neg:
		s = "-" + s
	return s + SYMBOL


static func _group(n: int) -> String:
	var s := str(n)
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = " " + out
	return out
