class_name ValorantModule
extends GameModule

## Discipline VALORANT : 5c5, tactique, tours à économie, MR12.

const DATA_MAPS := "res://data/games/valorant/maps.json"
const DATA_AGENTS := "res://data/games/valorant/agents.json"

# --- Attributs spécifiques (1..20) ------------------------------------------
# Mécanique
const AIM := "aim"                    # précision brute
const CROSSHAIR := "crosshair"        # placement de viseur
const SPRAY := "spray"                # contrôle de recul
const MOVEMENT := "movement"          # déplacement, peek, dodge
const DUELLING := "duelling"          # gagner un duel isolé
# Tactique
const GAME_SENSE := "game_sense"      # lecture de jeu
const POSITIONING := "positioning"
const UTILITY := "utility"            # usage des compétences
const ENTRY := "entry"                # prise d'espace, ouverture de site
const ANCHORING := "anchoring"        # tenue de site en défense
const TRADING := "trading"            # échange de frag
const MID_ROUND := "mid_round"        # adaptation en cours de round
const ECONOMY := "economy"            # gestion de l'économie
const MAP_KNOWLEDGE := "map_knowledge"
const CLUTCH := "clutch"              # situations en infériorité

const MECHANICAL: Array[String] = [AIM, CROSSHAIR, SPRAY, MOVEMENT, DUELLING]
const TACTICAL: Array[String] = [
	GAME_SENSE, POSITIONING, UTILITY, ENTRY, ANCHORING, TRADING,
	MID_ROUND, ECONOMY, MAP_KNOWLEDGE, CLUTCH,
]

const ATTR_LABELS := {
	AIM: "Visée", CROSSHAIR: "Placement de viseur", SPRAY: "Contrôle de recul",
	MOVEMENT: "Déplacement", DUELLING: "Duel",
	GAME_SENSE: "Lecture de jeu", POSITIONING: "Placement",
	UTILITY: "Utilitaires", ENTRY: "Prise d'espace", ANCHORING: "Tenue de site",
	TRADING: "Échange", MID_ROUND: "Adaptation", ECONOMY: "Gestion éco",
	MAP_KNOWLEDGE: "Connaissance des maps", CLUTCH: "Clutch",
}

# --- Rôles -------------------------------------------------------------------
const DUELIST := "duelist"
const INITIATOR := "initiator"
const CONTROLLER := "controller"
const SENTINEL := "sentinel"
const FLEX := "flex"

const ROLE_LABELS := {
	DUELIST: "Duelliste", INITIATOR: "Initiateur", CONTROLLER: "Contrôleur",
	SENTINEL: "Sentinelle", FLEX: "Flex",
}

const ROLE_LIST: Array[String] = [DUELIST, INITIATOR, CONTROLLER, SENTINEL, FLEX]


func id() -> String:
	return "valorant"


func display_name() -> String:
	return "VALORANT"


func team_size() -> int:
	return 5


func max_roster_size() -> int:
	return 7


func roles() -> Array[String]:
	return ROLE_LIST.duplicate()


func role_label(role_id: String) -> String:
	return ROLE_LABELS.get(role_id, role_id.capitalize())


## Composition de référence du méta : 1 contrôleur et 1 sentinelle sont
## quasi obligatoires, le reste module l'agressivité de l'équipe.
func ideal_composition() -> Dictionary:
	return {DUELIST: 1, INITIATOR: 2, CONTROLLER: 1, SENTINEL: 1}


func composition_bounds() -> Dictionary:
	return {
		DUELIST: [1, 2], INITIATOR: [1, 2],
		CONTROLLER: [1, 2], SENTINEL: [1, 2], FLEX: [0, 2],
	}


func attribute_keys() -> Array[String]:
	var out: Array[String] = []
	out.append_array(MECHANICAL)
	out.append_array(TACTICAL)
	return out


func attribute_label(key: String) -> String:
	if ATTR_LABELS.has(key):
		return ATTR_LABELS[key]
	return Attributes.label(key)


func attribute_groups() -> Dictionary:
	return {
		"Mécanique": MECHANICAL.duplicate(),
		"Tactique": TACTICAL.duplicate(),
		"Mental": Attributes.MENTAL.duplicate(),
		"Physique": Attributes.PHYSICAL.duplicate(),
	}


func role_weights(role_id: String) -> Dictionary:
	match role_id:
		DUELIST:
			return {
				AIM: 3.0, DUELLING: 3.0, ENTRY: 2.8, MOVEMENT: 2.2, CROSSHAIR: 2.0,
				Attributes.REACTION: 1.8, SPRAY: 1.2, GAME_SENSE: 1.4, TRADING: 1.0,
				CLUTCH: 1.2, POSITIONING: 0.8, UTILITY: 0.8, MAP_KNOWLEDGE: 0.8,
				Attributes.AGGRESSION: 1.2, Attributes.COMPOSURE: 1.0,
				Attributes.DECISION_MAKING: 1.0, Attributes.CONCENTRATION: 0.8,
				Attributes.TEAMWORK: 0.7, Attributes.COMMUNICATION: 0.7,
				Attributes.STAMINA: 0.5,
			}
		INITIATOR:
			return {
				UTILITY: 3.0, GAME_SENSE: 2.6, TRADING: 2.2, AIM: 2.0,
				Attributes.COMMUNICATION: 2.0, MID_ROUND: 1.6, CROSSHAIR: 1.6,
				MAP_KNOWLEDGE: 1.5, ENTRY: 1.4, DUELLING: 1.4, POSITIONING: 1.3,
				Attributes.TEAMWORK: 1.5, Attributes.DECISION_MAKING: 1.5,
				Attributes.REACTION: 1.2, SPRAY: 1.0, CLUTCH: 1.0,
				Attributes.COMPOSURE: 1.0, Attributes.CONCENTRATION: 1.0,
				Attributes.STAMINA: 0.5,
			}
		CONTROLLER:
			return {
				UTILITY: 3.0, GAME_SENSE: 2.6, MAP_KNOWLEDGE: 2.2, POSITIONING: 1.9,
				MID_ROUND: 1.7, Attributes.DECISION_MAKING: 1.8, TRADING: 1.3,
				Attributes.TEAMWORK: 1.5, Attributes.COMMUNICATION: 1.5, AIM: 1.5,
				CROSSHAIR: 1.4, ECONOMY: 1.2, SPRAY: 1.0, DUELLING: 1.0,
				Attributes.COMPOSURE: 1.2, Attributes.CONCENTRATION: 1.2,
				CLUTCH: 1.0, Attributes.REACTION: 1.0, Attributes.STAMINA: 0.5,
			}
		SENTINEL:
			return {
				ANCHORING: 3.0, POSITIONING: 2.6, UTILITY: 2.2, CLUTCH: 2.2,
				GAME_SENSE: 2.0, AIM: 1.9, CROSSHAIR: 1.9,
				Attributes.COMPOSURE: 1.8, Attributes.CONCENTRATION: 1.6,
				MAP_KNOWLEDGE: 1.5, SPRAY: 1.2, DUELLING: 1.2,
				Attributes.DECISION_MAKING: 1.2, Attributes.COMMUNICATION: 1.0,
				TRADING: 1.0, Attributes.REACTION: 1.2, Attributes.STAMINA: 0.5,
			}
		_:
			return {
				AIM: 2.0, CROSSHAIR: 1.8, DUELLING: 1.8, UTILITY: 2.0,
				GAME_SENSE: 2.2, POSITIONING: 1.8, TRADING: 1.6, ENTRY: 1.4,
				ANCHORING: 1.4, MID_ROUND: 1.4, MAP_KNOWLEDGE: 1.6, CLUTCH: 1.4,
				MOVEMENT: 1.4, SPRAY: 1.2, ECONOMY: 1.0,
				Attributes.ADAPTABILITY: 2.0, Attributes.TEAMWORK: 1.4,
				Attributes.COMMUNICATION: 1.2, Attributes.DECISION_MAKING: 1.4,
				Attributes.REACTION: 1.2, Attributes.COMPOSURE: 1.2,
				Attributes.CONCENTRATION: 1.0, Attributes.STAMINA: 0.5,
			}


## Surcouche appliquée au capitaine en jeu (IGL) : son apport tactique compte
## davantage que ses frags.
func igl_weights() -> Dictionary:
	return {
		Attributes.LEADERSHIP: 3.0, MID_ROUND: 2.5, GAME_SENSE: 2.0,
		Attributes.COMMUNICATION: 2.0, ECONOMY: 1.5,
		Attributes.DECISION_MAKING: 1.5, MAP_KNOWLEDGE: 1.2,
	}


func default_tactic() -> Dictionary:
	return {
		"aggression": 50,       # 0 = tour lent/défaut, 100 = rush permanent
		"tempo": 50,            # rythme d'exécution
		"util_discipline": 60,  # usage rigoureux des utilitaires
		"eco_policy": 50,       # 0 = save systématique, 100 = force buy
		"anti_strat": 50,       # part de la prépa consacrée à l'adversaire
		"risk": 50,             # prise de risque en post-plant / retake
	}


func stat_columns() -> Array:
	return [
		{"key": "rating", "label": "Note", "digits": 2},
		{"key": "acs", "label": "ACS", "digits": 0},
		{"key": "kills", "label": "K", "digits": 0},
		{"key": "deaths", "label": "D", "digits": 0},
		{"key": "assists", "label": "A", "digits": 0},
		{"key": "first_kills", "label": "FK", "digits": 0},
		{"key": "clutches", "label": "CL", "digits": 0},
	]


func series_formats() -> Array[int]:
	return [1, 3, 5]


func create_simulator() -> MatchSimulator:
	return ValorantSim.new(self)


# --- Données de contenu ------------------------------------------------------

func all_maps() -> Array:
	var d = DataFile.load_json(DATA_MAPS, {"maps": []})
	return (d as Dictionary).get("maps", [])


func active_map_pool() -> Array[String]:
	var out: Array[String] = []
	for m in all_maps():
		if bool((m as Dictionary).get("active", false)):
			out.append(str((m as Dictionary)["name"]))
	return out


func map_info(map_name: String) -> Dictionary:
	for m in all_maps():
		if str((m as Dictionary)["name"]) == map_name:
			return m
	return {"name": map_name, "atk_win_rate": 0.5, "openness": 0.5, "util_weight": 1.0}


func agents_for_role(role_id: String) -> Array[String]:
	var d = DataFile.load_json(DATA_AGENTS, {"agents": []})
	var out: Array[String] = []
	for a in (d as Dictionary).get("agents", []):
		if str((a as Dictionary).get("role", "")) == role_id:
			out.append(str((a as Dictionary)["name"]))
	return out


## Pool d'agents + confort par map d'un joueur, généré à sa création.
func generate_game_data(player: Player, rng: Rng) -> Dictionary:
	var pool: Dictionary = {}
	var candidates := agents_for_role(player.primary_role)
	if candidates.is_empty():
		candidates = agents_for_role(DUELIST)
	for a in rng.pick_many(candidates, rng.range_i(2, 3)):
		pool[a] = rng.gauss_i(15.0, 2.5, 8, 20)
	if rng.chance(0.45):
		var others: Array[String] = []
		for r in ROLE_LIST:
			if r != player.primary_role and r != FLEX:
				others.append(r)
		var other_role := str(rng.pick(others))
		for a in rng.pick_many(agents_for_role(other_role), 1):
			pool[a] = rng.gauss_i(11.0, 2.5, 5, 18)

	var maps: Dictionary = {}
	var base := float(player.current_ability) / 12.0
	for m in all_maps():
		var mn := str((m as Dictionary)["name"])
		maps[mn] = Attributes.clamp_value(rng.gauss_i(base, 2.6, 1, 20))
	return {"agents": pool, "maps": maps}


func compute_derived_stats(st: Dictionary) -> void:
	ValorantSim.compute_derived(st)
