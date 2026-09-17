class_name Cs2Module
extends GameModule

## Discipline COUNTER-STRIKE 2 : 5c5, MR12, économie en dollars, pas de
## compétences actives — le talent y est plus brut qu'en Valorant.
##
## Ce que CS2 partage avec Valorant, et pourquoi : les deux jeux sont des FPS
## tactiques à sites et à bombe. Viser, placer son viseur, tenir un angle,
## échanger un frag, lire un round : ce sont les MÊMES compétences humaines, et
## un joueur qui change de discipline les emporte avec lui. Les clés
## d'attributs sont donc communes (`aim`, `utility`, `clutch`…), ce qui rend
## les fiches comparables d'une section à l'autre.
##
## Ce que CS2 ne partage PAS, et c'est là que vit la discipline :
##   * l'AWP. Une arme à 4 750 $ qui décide des rounds et qu'un seul joueur
##     tient : aucun équivalent en Valorant. D'où l'attribut `sniping` et le
##     poste d'AWPeur, qui pèse plus lourd que n'importe quel autre.
##   * le LURK. Un joueur qui part seul couper la rotation adverse ; c'est un
##     poste à part entière en CS, pas une option.
##   * l'économie. Dix-sept mille dollars de plafond, un bonus de défaite qui
##     monte à 3 400 $, et une pose de bombe qui rapporte même en perdant :
##     l'arbitrage éco/force est plus profond, et plus punitif.
##   * pas d'utilitaires rechargeables : la grenade achetée est dépensée. Le
##     poids de `utility` est donc plus faible qu'en Valorant, sauf sur Inferno.
##   * les maps sont CT-sided. Toutes. Voir data/games/cs2/maps.json.

const DATA_MAPS := "res://data/games/cs2/maps.json"
const DATA_WEAPONS := "res://data/games/cs2/weapons.json"

# --- Attributs (1..20) -------------------------------------------------------
# Mécanique — clés communes avec les autres FPS tactiques, plus le sniping.
const AIM := "aim"                    # précision brute
const CROSSHAIR := "crosshair"        # placement de viseur
const SPRAY := "spray"                # contrôle de recul
const MOVEMENT := "movement"          # counter-strafe, peek, jiggle
const DUELLING := "duelling"          # gagner un duel isolé
const SNIPING := "sniping"            # AWP : le seul attribut vraiment à part

# Tactique
const GAME_SENSE := "game_sense"
const POSITIONING := "positioning"
const UTILITY := "utility"            # smokes, flashs, molotovs : des lineups
const ENTRY := "entry"                # ouvrir un site
const ANCHORING := "anchoring"        # tenir un site en CT
const TRADING := "trading"
const LURKING := "lurking"            # jouer seul, couper les rotations
const MID_ROUND := "mid_round"
const ECONOMY := "economy"
const MAP_KNOWLEDGE := "map_knowledge"
const CLUTCH := "clutch"

const MECHANICAL: Array[String] = [AIM, CROSSHAIR, SPRAY, MOVEMENT, DUELLING,
	SNIPING]
const TACTICAL: Array[String] = [
	GAME_SENSE, POSITIONING, UTILITY, ENTRY, ANCHORING, TRADING, LURKING,
	MID_ROUND, ECONOMY, MAP_KNOWLEDGE, CLUTCH,
]

const ATTR_LABELS := {
	AIM: "Visée", CROSSHAIR: "Placement de viseur", SPRAY: "Contrôle de recul",
	MOVEMENT: "Déplacement", DUELLING: "Duel", SNIPING: "AWP",
	GAME_SENSE: "Lecture de jeu", POSITIONING: "Placement",
	UTILITY: "Grenades", ENTRY: "Prise de site", ANCHORING: "Tenue de site",
	TRADING: "Échange", LURKING: "Lurk", MID_ROUND: "Adaptation",
	ECONOMY: "Gestion éco", MAP_KNOWLEDGE: "Connaissance des maps",
	CLUTCH: "Clutch",
}

# --- Postes ------------------------------------------------------------------
# L'IGL n'est PAS un poste : c'est un rôle porté par l'un des cinq
# (Player.is_igl), exactement comme dans la vraie vie où l'IGL est souvent
# aussi le support ou le lurker.
const AWPER := "awper"
const ENTRY_FRAGGER := "entry_fragger"
const SUPPORT := "support"
const LURKER := "lurker"
const RIFLER := "rifler"

const ROLE_LABELS := {
	AWPER: "AWPeur", ENTRY_FRAGGER: "Entry fragger", SUPPORT: "Soutien",
	LURKER: "Lurker", RIFLER: "Rifleur",
}

const ROLE_LIST: Array[String] = [AWPER, ENTRY_FRAGGER, SUPPORT, LURKER, RIFLER]


func id() -> String:
	return "cs2"


func display_name() -> String:
	return "COUNTER-STRIKE 2"


func team_size() -> int:
	return 5


## Un roster CS déclare six joueurs au plus : la sixième place est celle du
## coach-joueur ou du remplaçant, pas un banc de sept comme en VCT.
func max_roster_size() -> int:
	return 6


func roles() -> Array[String]:
	return ROLE_LIST.duplicate()


func role_label(role_id: String) -> String:
	return ROLE_LABELS.get(role_id, role_id.capitalize())


## La composition canonique de Counter-Strike depuis vingt ans : un AWPeur, un
## entry, un support, un lurker, un rifleur libre. Elle bouge très peu, et
## c'est ce qui distingue CS du méta tournant de Valorant.
func ideal_composition() -> Dictionary:
	return {AWPER: 1, ENTRY_FRAGGER: 1, SUPPORT: 1, LURKER: 1, RIFLER: 1}


## Une équipe sans AWPeur existe, mais elle est handicapée sur toutes les maps
## ouvertes : on l'autorise, on ne la conseille pas. Deux AWP, en revanche,
## sont un vrai choix d'équipe (double AWP), pas une erreur.
func composition_bounds() -> Dictionary:
	return {
		AWPER: [1, 2], ENTRY_FRAGGER: [1, 2], SUPPORT: [1, 2],
		LURKER: [0, 2], RIFLER: [0, 3],
	}


## Un AWPeur, un entry, un support, un lurker, un rifleur : la composition
## qu'on génère est exactement l'idéal, parce qu'en CS c'est le cas.
func generated_lineup() -> Array[String]:
	return [AWPER, ENTRY_FRAGGER, SUPPORT, LURKER, RIFLER]


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


## Poids par poste. Deux écarts volontaires avec Valorant :
##   * `sniping` pèse 3,4 chez l'AWPeur — plus que n'importe quel attribut de
##     n'importe quel poste du jeu. Un AWPeur qui ne tient pas son arme ne
##     sert à rien, et sa fiche doit le dire.
##   * `utility` plafonne à 2,4 au lieu de 3,0 : en CS les grenades sont des
##     lineups appris, pas des compétences rechargeables.
func role_weights(role_id: String) -> Dictionary:
	match role_id:
		AWPER:
			return {
				SNIPING: 3.4, AIM: 2.4, CROSSHAIR: 2.2, POSITIONING: 2.2,
				Attributes.REACTION: 2.0, GAME_SENSE: 1.8, MOVEMENT: 1.6,
				DUELLING: 1.6, ANCHORING: 1.4, CLUTCH: 1.4,
				Attributes.COMPOSURE: 1.4, MAP_KNOWLEDGE: 1.2, TRADING: 1.0,
				Attributes.CONCENTRATION: 1.0, ECONOMY: 0.9, SPRAY: 0.6,
				UTILITY: 0.6, Attributes.TEAMWORK: 0.8,
				Attributes.DECISION_MAKING: 1.0, Attributes.STAMINA: 0.5,
			}
		ENTRY_FRAGGER:
			return {
				ENTRY: 3.0, DUELLING: 2.8, AIM: 2.8, MOVEMENT: 2.2,
				CROSSHAIR: 2.0, Attributes.REACTION: 1.8, SPRAY: 1.6,
				TRADING: 1.4, Attributes.AGGRESSION: 1.4, GAME_SENSE: 1.2,
				UTILITY: 1.0, MAP_KNOWLEDGE: 0.9, POSITIONING: 0.8,
				CLUTCH: 0.9, SNIPING: 0.5, LURKING: 0.4,
				Attributes.COMPOSURE: 1.0, Attributes.TEAMWORK: 0.9,
				Attributes.DECISION_MAKING: 0.9, Attributes.STAMINA: 0.5,
			}
		SUPPORT:
			return {
				UTILITY: 2.4, TRADING: 2.4, GAME_SENSE: 2.2,
				Attributes.TEAMWORK: 2.0, MAP_KNOWLEDGE: 2.0, AIM: 1.8,
				Attributes.COMMUNICATION: 1.8, SPRAY: 1.5, CROSSHAIR: 1.5,
				POSITIONING: 1.4, ENTRY: 1.2, MID_ROUND: 1.2, ECONOMY: 1.2,
				DUELLING: 1.0, ANCHORING: 1.0, CLUTCH: 0.8, SNIPING: 0.5,
				Attributes.DISCIPLINE: 1.2, Attributes.DECISION_MAKING: 1.2,
				Attributes.REACTION: 1.0, Attributes.STAMINA: 0.5,
			}
		LURKER:
			return {
				LURKING: 3.0, CLUTCH: 2.6, GAME_SENSE: 2.4, POSITIONING: 2.2,
				AIM: 2.0, Attributes.COMPOSURE: 1.9, MAP_KNOWLEDGE: 1.8,
				Attributes.CONCENTRATION: 1.6, CROSSHAIR: 1.6, DUELLING: 1.4,
				MID_ROUND: 1.4, SPRAY: 1.2, TRADING: 0.8, UTILITY: 0.8,
				ANCHORING: 1.0, SNIPING: 0.6, ENTRY: 0.5,
				Attributes.DECISION_MAKING: 1.4, Attributes.STAMINA: 0.5,
			}
		_:
			# Rifleur : le poste le plus complet, celui qui bouche les trous.
			return {
				AIM: 2.6, SPRAY: 2.0, CROSSHAIR: 2.0, DUELLING: 1.9,
				GAME_SENSE: 1.9, POSITIONING: 1.7, TRADING: 1.7, ANCHORING: 1.5,
				UTILITY: 1.5, MAP_KNOWLEDGE: 1.5, ENTRY: 1.3, CLUTCH: 1.3,
				MOVEMENT: 1.4, MID_ROUND: 1.2, LURKING: 1.0, ECONOMY: 0.9,
				SNIPING: 0.8, Attributes.ADAPTABILITY: 1.8,
				Attributes.TEAMWORK: 1.3, Attributes.COMMUNICATION: 1.1,
				Attributes.DECISION_MAKING: 1.2, Attributes.REACTION: 1.2,
				Attributes.COMPOSURE: 1.1, Attributes.STAMINA: 0.5,
			}


## Surcouche appliquée au capitaine en jeu. En CS l'IGL porte l'économie bien
## plus qu'en Valorant : il décide de forcer à 2 400 $ ou d'attendre, et une
## mauvaise décision coûte trois rounds au lieu de deux.
func igl_weights() -> Dictionary:
	return {
		Attributes.LEADERSHIP: 3.0, MID_ROUND: 2.6, ECONOMY: 2.2,
		GAME_SENSE: 2.0, Attributes.COMMUNICATION: 2.0,
		Attributes.DECISION_MAKING: 1.6, MAP_KNOWLEDGE: 1.4,
	}


func declining_attributes() -> Array[String]:
	# Le sniping part avec les réflexes : c'est le cliché de l'AWPeur de 29 ans
	# reconverti en rifleur ou en IGL, et il est vrai.
	return [AIM, MOVEMENT, DUELLING, ENTRY, SNIPING, Attributes.REACTION]


func ageing_attributes() -> Array[String]:
	return [GAME_SENSE, MAP_KNOWLEDGE, MID_ROUND, ECONOMY, POSITIONING,
		LURKING, Attributes.LEADERSHIP, Attributes.COMPOSURE,
		Attributes.DECISION_MAKING]


func default_tactic() -> Dictionary:
	return {
		"aggression": 45,       # CS se joue plus lentement que Valorant
		"tempo": 45,            # 0 = default patient, 100 = rush systématique
		"util_discipline": 60,  # lineups appris plutôt que grenades à l'instinct
		"eco_policy": 45,       # 0 = save systématique, 100 = force buy
		"anti_strat": 55,       # part de la prépa consacrée à l'adversaire
		"awp_priority": 55,     # budget et espace accordés à l'AWP
	}


func tactic_sliders() -> Array:
	return [
		{"key": "aggression", "label": "Agressivité",
			"hint": "Prendre l'espace tôt : plus d'ouvertures, plus de morts gratuites."},
		{"key": "tempo", "label": "Tempo",
			"hint": "0 = default patient et contrôle de map, 100 = exécutions rapides."},
		{"key": "util_discipline", "label": "Discipline des grenades",
			"hint": "Lineups appris et smokes coordonnées plutôt qu'à l'instinct."},
		{"key": "eco_policy", "label": "Politique d'économie",
			"hint": "0 = épargner systématiquement, 100 = forcer l'achat."},
		{"key": "anti_strat", "label": "Préparation adverse",
			"hint": "Part du travail hebdomadaire consacrée à l'adversaire."},
		{"key": "awp_priority", "label": "Priorité à l'AWP",
			"hint": "Racheter l'AWP en priorité et jouer autour. Coûteux si l'AWPeur tombe tôt."},
	]


## En Counter-Strike on ne dit pas « attaque » : on dit T et CT, et le compte
## rendu de match doit parler la langue de la discipline.
func side_label(attacking: bool) -> String:
	return "T" if attacking else "CT"


## Colonnes du compte rendu : l'ADR remplace l'ACS, et le pourcentage de
## têtes est une statistique culturellement CS.
func stat_columns() -> Array:
	return [
		{"key": "rating", "label": "Note", "digits": 2},
		{"key": "adr", "label": "ADR", "digits": 0},
		{"key": "kast", "label": "KAST", "digits": 0},
		{"key": "kills", "label": "K", "digits": 0},
		{"key": "deaths", "label": "D", "digits": 0},
		{"key": "assists", "label": "A", "digits": 0},
		{"key": "first_kills", "label": "OK", "digits": 0},
		{"key": "clutches", "label": "CL", "digits": 0},
	]


func series_formats() -> Array[int]:
	return [1, 3, 5]


func create_simulator() -> MatchSimulator:
	return Cs2Sim.new(self)


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


func map_pool() -> Array[String]:
	return active_map_pool()


func map_info(map_name: String) -> Dictionary:
	for m in all_maps():
		if str((m as Dictionary)["name"]) == map_name:
			return m
	return {"name": map_name, "atk_win_rate": 0.47, "openness": 0.5,
		"util_weight": 1.0, "awp_weight": 1.0}


func weapons_for_role(role_id: String) -> Array[String]:
	var d = DataFile.load_json(DATA_WEAPONS, {"weapons": []})
	var out: Array[String] = []
	for w in (d as Dictionary).get("weapons", []):
		if str((w as Dictionary).get("role", "")) == role_id:
			out.append(str((w as Dictionary)["name"]))
	return out


## Maîtrise d'armes + confort par map, tirés à la création du joueur.
## Même mécanique que le pool d'agents de Valorant : ce qui change, c'est que
## l'AWP est une arme qu'on possède ou pas, pas un personnage qu'on choisit.
func generate_game_data(player: Player, rng: Rng) -> Dictionary:
	var pool: Dictionary = {}
	var candidates := weapons_for_role(player.primary_role)
	if candidates.is_empty():
		candidates = weapons_for_role(RIFLER)
	for w in rng.pick_many(candidates, rng.range_i(2, 3)):
		pool[w] = rng.gauss_i(15.0, 2.5, 8, 20)
	# Tout le monde tient un AK et un M4 : ce sont les armes du jeu, pas une
	# spécialité. Les ajouter évite des fiches où un rifleur ne « possède »
	# que le Tec-9.
	for staple in ["AK-47", "M4A4"]:
		if not pool.has(staple):
			pool[staple] = rng.gauss_i(13.0, 2.6, 6, 20)
	if rng.chance(0.40):
		var others: Array[String] = []
		for r in ROLE_LIST:
			if r != player.primary_role:
				others.append(r)
		var other_role := str(rng.pick(others))
		for w2 in rng.pick_many(weapons_for_role(other_role), 1):
			pool[w2] = rng.gauss_i(11.0, 2.5, 5, 18)

	var maps: Dictionary = {}
	var base := float(player.current_ability) / 12.0
	for m in all_maps():
		var mn := str((m as Dictionary)["name"])
		maps[mn] = Attributes.clamp_value(rng.gauss_i(base, 2.6, 1, 20))
	return {"weapons": pool, "maps": maps}


func compute_derived_stats(st: Dictionary) -> void:
	Cs2Sim.compute_derived(st)
