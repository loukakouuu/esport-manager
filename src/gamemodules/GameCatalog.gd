class_name GameCatalog
extends RefCounted

## Catalogue des DISCIPLINES connues du jeu — simulées ou non.
##
## À ne pas confondre avec GameRegistry, qui n'annonce que les disciplines
## SIMULABLES (celles qui ont un GameModule). La distinction est le cœur du
## mode « reprendre une structure réelle » : Karmine Corp aligne une section
## League of Legends, et le jeu doit pouvoir l'afficher honnêtement — présente
## dans la structure, pas encore simulée — plutôt que de faire comme si elle
## n'existait pas.
##
## Ajouter un module dans GameRegistry suffit à rendre la discipline jouable :
## rien ici ne change.

const GAMES := {
	"valorant": {"label": "Valorant", "short": "VAL", "color": "#ff4655",
		"publisher": "Riot Games", "team_size": 5},
	"cs2": {"label": "Counter-Strike 2", "short": "CS2", "color": "#f0a500",
		"publisher": "Valve", "team_size": 5},
	"lol": {"label": "League of Legends", "short": "LoL", "color": "#c8aa6e",
		"publisher": "Riot Games", "team_size": 5},
	"rl": {"label": "Rocket League", "short": "RL", "color": "#1d9bf0",
		"publisher": "Psyonix", "team_size": 3},
	"apex": {"label": "Apex Legends", "short": "APX", "color": "#da292a",
		"publisher": "Respawn", "team_size": 3},
	"r6": {"label": "Rainbow Six Siege", "short": "R6", "color": "#5f9ea0",
		"publisher": "Ubisoft", "team_size": 5},
	"dota2": {"label": "Dota 2", "short": "DOTA", "color": "#a4302a",
		"publisher": "Valve", "team_size": 5},
	"ow2": {"label": "Overwatch 2", "short": "OW2", "color": "#f99e1a",
		"publisher": "Blizzard", "team_size": 5},
}

## Ordre d'affichage : Valorant d'abord (seule discipline simulée aujourd'hui),
## puis les autres dans l'ordre du catalogue.
const ORDER: Array[String] = ["valorant", "cs2", "lol", "rl", "apex", "r6",
	"dota2", "ow2"]


static func known(game_id: String) -> bool:
	return GAMES.has(game_id)


static func label(game_id: String) -> String:
	return str((GAMES.get(game_id, {}) as Dictionary).get("label", game_id))


static func short(game_id: String) -> String:
	return str((GAMES.get(game_id, {}) as Dictionary).get("short",
		game_id.to_upper()))


static func color(game_id: String) -> Color:
	return Color(str((GAMES.get(game_id, {}) as Dictionary).get("color",
		"#8a93a6")))


static func publisher(game_id: String) -> String:
	return str((GAMES.get(game_id, {}) as Dictionary).get("publisher", ""))


## La discipline est-elle réellement simulée ? Seul GameRegistry fait foi.
static func playable(game_id: String) -> bool:
	return GameRegistry.has(game_id)


## Nettoie et ordonne une liste de disciplines venue des données : on écarte
## les identifiants inconnus (une faute de frappe dans un pack ne doit pas
## créer une section fantôme) et on garantit un ordre stable.
static func sanitize(ids) -> Array[String]:
	var seen := {}
	var out: Array[String] = []
	if not (ids is Array):
		return out
	for v in ids:
		var g := str(v).strip_edges().to_lower()
		if known(g) and not seen.has(g):
			seen[g] = true
	for g in ORDER:
		if seen.has(g):
			out.append(g)
	return out
