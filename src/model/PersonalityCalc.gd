class_name PersonalityCalc
extends RefCounted

## Personnalité déduite des attributs cachés, façon Football Manager.
##
## Pourquoi une étiquette plutôt que les chiffres bruts : le joueur ne doit
## jamais lire « Professionnalisme 17 / Ambition 4 ». Il doit lire « Modèle de
## professionnalisme » et en tirer une décision — celui-là, on peut le mettre
## à côté d'un jeune de 17 ans. L'étiquette est un RÉSUMÉ ORIENTÉ ACTION.
##
## Elle est aussi imparfaitement connue : c'est ScoutingSystem qui décide si
## on l'affiche, et à quel point.

## Ordre de priorité : la première règle qui passe l'emporte. Les
## personnalités les plus fortes (donc les plus utiles à connaître) d'abord.
const RULES := [
	{"label": "Modèle de professionnalisme", "good": true,
		"req": {"professionalism": 18, "work_ethic": 16}},
	{"label": "Perfectionniste", "good": true,
		"req": {"professionalism": 16, "ambition": 16, "work_ethic": 15}},
	{"label": "Leader né", "good": true,
		"req": {"leadership": 17, "composure": 14}},
	{"label": "Nerfs d'acier", "good": true,
		"req": {"pressure": 17, "composure": 16}},
	{"label": "Homme des grands rendez-vous", "good": true,
		"req": {"big_match": 17}},
	{"label": "Déterminé", "good": true,
		"req": {"work_ethic": 16, "ambition": 14}},
	{"label": "Loyal", "good": true,
		"req": {"loyalty": 17}},
	{"label": "Fiable", "good": true,
		"req": {"consistency": 16, "professionalism": 13}},
	{"label": "Ambitieux", "good": true,
		"req": {"ambition": 17}},
	{"label": "Tempérament explosif", "good": false,
		"req": {"ego": 16, "discipline": -8}},
	{"label": "Ego surdimensionné", "good": false,
		"req": {"ego": 17}},
	{"label": "Sujet à la polémique", "good": false,
		"req": {"controversy": 16}},
	{"label": "Fragile sous pression", "good": false,
		"req": {"pressure": -7}},
	{"label": "Irrégulier", "good": false,
		"req": {"consistency": -7}},
	{"label": "Peu professionnel", "good": false,
		"req": {"professionalism": -7}},
	{"label": "Mercenaire", "good": false,
		"req": {"loyalty": -6, "ambition": 14}},
	{"label": "Nonchalant", "good": false,
		"req": {"work_ethic": -7}},
	{"label": "Discret", "good": true,
		"req": {"ego": -7, "teamwork": 14}},
	{"label": "Bon coéquipier", "good": true,
		"req": {"teamwork": 16}},
]


## Étiquette principale. Une valeur positive dans `req` est un minimum,
## une valeur négative est un MAXIMUM (on écrit -8 pour « au plus 8 »).
static func label(p: Player) -> String:
	for rule in RULES:
		if _matches(p, (rule as Dictionary)["req"]):
			return str((rule as Dictionary)["label"])
	return "Tempérament équilibré"


static func is_positive(p: Player) -> bool:
	for rule in RULES:
		if _matches(p, (rule as Dictionary)["req"]):
			return bool((rule as Dictionary)["good"])
	return true


static func color(p: Player) -> Color:
	return Color("#46c46a") if is_positive(p) else Color("#dd8038")


static func _matches(p: Player, req: Dictionary) -> bool:
	for key in req:
		var threshold := int(req[key])
		var v := p.attr(str(key))
		if threshold >= 0:
			if v < threshold:
				return false
		elif v > -threshold:
			return false
	return true


## Étiquettes secondaires : traits notables qui ne sont pas la personnalité
## principale. Affichées en petit sous la fiche.
static func secondary_labels(p: Player) -> Array[String]:
	var main := label(p)
	var out: Array[String] = []
	for rule in RULES:
		var d: Dictionary = rule
		if str(d["label"]) == main:
			continue
		if _matches(p, d["req"]):
			out.append(str(d["label"]))
		if out.size() >= 2:
			break
	return out


## Une phrase de synthèse pour la fiche joueur : ce qu'un directeur sportif
## dirait du bonhomme en trente secondes.
static func summary(p: Player) -> String:
	var bits: Array[String] = []
	var ethic := p.attr(Attributes.WORK_ETHIC)
	if ethic >= 16:
		bits.append("travailleur acharné")
	elif ethic <= 7:
		bits.append("s'entraîne a minima")
	var amb := p.attr(Attributes.AMBITION)
	if amb >= 16:
		bits.append("veut aller au sommet et le fera savoir")
	elif amb <= 6:
		bits.append("se satisfait de sa situation")
	var loy := p.attr(Attributes.LOYALTY)
	if loy >= 16:
		bits.append("attaché à sa structure")
	elif loy <= 6:
		bits.append("partira pour la meilleure offre")
	var cons := p.attr(Attributes.CONSISTENCY)
	if cons >= 16:
		bits.append("d'une régularité remarquable")
	elif cons <= 7:
		bits.append("capable du meilleur comme du pire")
	var big := p.attr(Attributes.BIG_MATCH)
	if big >= 16:
		bits.append("monte en puissance dans les grands matchs")
	elif big <= 7:
		bits.append("s'efface quand l'enjeu grandit")
	if bits.is_empty():
		return "Profil sans aspérité particulière."
	return bits[0].capitalize() + (", " + ", ".join(bits.slice(1)) if bits.size() > 1 else "") + "."
