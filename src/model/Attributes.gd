class_name Attributes
extends RefCounted

## Échelle FM : tout attribut est un entier 1..20.
##
## Deux familles :
##  - les attributs COMMUNS (mental / physique) : identiques quel que soit le
##    jeu esport, ils suivent le joueur s'il change de discipline ;
##  - les attributs SPÉCIFIQUES au jeu : déclarés par le GameModule
##    (voir src/gamemodules/). C'est la clé du multi-jeu.

const MIN := 1
const MAX := 20

# --- Mental (visible, commun à tous les jeux) --------------------------------
const COMPOSURE := "composure"
const COMMUNICATION := "communication"
const LEADERSHIP := "leadership"
const TEAMWORK := "teamwork"
const DISCIPLINE := "discipline"
const WORK_ETHIC := "work_ethic"
const ADAPTABILITY := "adaptability"
const DECISION_MAKING := "decision_making"
const AGGRESSION := "aggression"
const CONCENTRATION := "concentration"

# --- Physique / cognitif (visible, commun) -----------------------------------
const REACTION := "reaction"        # décline nettement après ~25 ans
const STAMINA := "stamina"          # tenue sur un tournoi long / LAN

# --- Cachés (jamais affichés bruts : uniquement estimés par le scouting) -----
const CONSISTENCY := "consistency"
const BIG_MATCH := "big_match"
const PRESSURE := "pressure"
const AMBITION := "ambition"
const LOYALTY := "loyalty"
const EGO := "ego"
const PROFESSIONALISM := "professionalism"
const BURNOUT_RESISTANCE := "burnout_resistance"
const INJURY_PRONENESS := "injury_proneness"
const CONTROVERSY := "controversy"   # risque de sortie de route médiatique

const MENTAL: Array[String] = [
	COMPOSURE, COMMUNICATION, LEADERSHIP, TEAMWORK, DISCIPLINE,
	WORK_ETHIC, ADAPTABILITY, DECISION_MAKING, AGGRESSION, CONCENTRATION,
]

const PHYSICAL: Array[String] = [REACTION, STAMINA]

const HIDDEN: Array[String] = [
	CONSISTENCY, BIG_MATCH, PRESSURE, AMBITION, LOYALTY, EGO,
	PROFESSIONALISM, BURNOUT_RESISTANCE, INJURY_PRONENESS, CONTROVERSY,
]

const LABELS := {
	COMPOSURE: "Sang-froid",
	COMMUNICATION: "Communication",
	LEADERSHIP: "Leadership",
	TEAMWORK: "Esprit d'équipe",
	DISCIPLINE: "Discipline",
	WORK_ETHIC: "Rigueur",
	ADAPTABILITY: "Adaptabilité",
	DECISION_MAKING: "Prise de décision",
	AGGRESSION: "Agressivité",
	CONCENTRATION: "Concentration",
	REACTION: "Temps de réaction",
	STAMINA: "Endurance",
	CONSISTENCY: "Régularité",
	BIG_MATCH: "Grands matchs",
	PRESSURE: "Résistance à la pression",
	AMBITION: "Ambition",
	LOYALTY: "Loyauté",
	EGO: "Ego",
	PROFESSIONALISM: "Professionnalisme",
	BURNOUT_RESISTANCE: "Résistance au burnout",
	INJURY_PRONENESS: "Fragilité physique",
	CONTROVERSY: "Risque médiatique",
}


## Attributs dont une valeur ÉLEVÉE est une mauvaise nouvelle. L'interface doit
## inverser leur code couleur : un ego de 18 affiché en vert ferait croire à
## une qualité, alors que c'est le futur problème de vestiaire.
const NEGATIVE: Array[String] = [EGO, INJURY_PRONENESS, CONTROVERSY]


static func is_negative(key: String) -> bool:
	return NEGATIVE.has(key)


static func label(key: String) -> String:
	return LABELS.get(key, key.capitalize())


static func clamp_value(v: int) -> int:
	return clampi(v, MIN, MAX)


static func common_visible() -> Array[String]:
	var out: Array[String] = []
	out.append_array(MENTAL)
	out.append_array(PHYSICAL)
	return out


static func all_common() -> Array[String]:
	var out: Array[String] = common_visible()
	out.append_array(HIDDEN)
	return out


## Couleur d'affichage FM-like (rouge -> vert) pour une valeur 1..20.
static func color_for(v: int) -> Color:
	var t := clampf((float(v) - 1.0) / 19.0, 0.0, 1.0)
	if t < 0.5:
		return Color(0.85, 0.25, 0.2).lerp(Color(0.9, 0.75, 0.2), t * 2.0)
	return Color(0.9, 0.75, 0.2).lerp(Color(0.35, 0.78, 0.35), (t - 0.5) * 2.0)
