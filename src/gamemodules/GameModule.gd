class_name GameModule
extends RefCounted

## INTERFACE d'une discipline esport. C'est LA couture qui rend le jeu
## multi-titres.
##
## Tout ce qui diffère entre Valorant, CS2 ou League of Legends est déclaré ici :
## taille d'équipe, rôles, attributs spécifiques, format de match, tactiques,
## colonnes de statistiques, simulateur. Le reste du moteur (finances, contrats,
## calendrier, progression, sauvegarde) est écrit une seule fois et ne connaît
## que cette interface.
##
## Ajouter une discipline = créer src/gamemodules/<jeu>/<Jeu>Module.gd + son
## simulateur, l'enregistrer dans GameRegistry, et fournir les données JSON
## (`data/games/<jeu>/` et `data/world/season_<jeu>.json`). Aucune modification
## du coeur — c'est exactement ce qu'a coûté l'arrivée de Counter-Strike 2.

func id() -> String:
	return "abstract"


func display_name() -> String:
	return "Discipline"


## Nombre de titulaires (5 pour Valorant/CS2/LoL, 3 pour Rocket League…).
func team_size() -> int:
	return 5


## Taille maximale du roster déclaré en compétition.
func max_roster_size() -> int:
	return 7


func roles() -> Array[String]:
	return []


func role_label(role_id: String) -> String:
	return role_id.capitalize()


## Composition attendue : role_id -> nombre idéal de joueurs dans le cinq.
func ideal_composition() -> Dictionary:
	return {}


## Postes attribués aux titulaires d'un effectif GÉNÉRÉ, dans l'ordre. Par
## défaut on déroule `ideal_composition` ; une discipline dont le méta réel
## diffère de son idéal théorique surcharge cette méthode.
func generated_lineup() -> Array[String]:
	var out: Array[String] = []
	var ideal := ideal_composition()
	for role in ideal:
		for _n in int(ideal[role]):
			out.append(str(role))
	return out


## Bornes acceptables par poste dans le cinq : role_id -> [min, max].
## Sert à prévenir le joueur qu'une composition est injouable ; à ne pas
## confondre avec `ideal_composition`, qui décrit le méta et pas la légalité.
func composition_bounds() -> Dictionary:
	return {}


## Attributs SPÉCIFIQUES à la discipline (hors attributs communs).
func attribute_keys() -> Array[String]:
	return []


func attribute_label(key: String) -> String:
	return key.capitalize()


## Groupes d'affichage pour la fiche joueur : "Mécanique" -> [clés…]
func attribute_groups() -> Dictionary:
	return {}


## Poids d'un attribut dans le calcul de la Capacité Actuelle, par rôle.
## Somme des poids libre : elle est normalisée par AbilityCalc.
func role_weights(role_id: String) -> Dictionary:
	return {}


## Attributs qui DÉCLINENT avec l'âge : les qualités purement mécaniques.
## Lus par ProgressionSystem — sans cette liste, le déclin serait le même
## partout et un AWPeur de 29 ans perdrait sa lecture de jeu.
func declining_attributes() -> Array[String]:
	return [Attributes.REACTION]


## Attributs qui continuent de progresser passé le pic : la compréhension.
func ageing_attributes() -> Array[String]:
	return [Attributes.LEADERSHIP, Attributes.COMPOSURE,
		Attributes.DECISION_MAKING]


## Réglages tactiques par défaut d'une équipe de cette discipline.
func default_tactic() -> Dictionary:
	return {}


## Curseurs tactiques exposés au joueur, dans l'ordre d'affichage :
## [{"key", "label", "hint"}, …]. L'écran Tactique n'en connaît aucun : c'est
## la discipline qui dit ce qu'on peut régler et ce que ça change.
func tactic_sliders() -> Array:
	return []


## Pool de cartes actif de la discipline. Vide = la simulation n'en utilise pas.
func map_pool() -> Array[String]:
	return []


## Fichier décrivant la structure compétitive de la discipline.
## Convention : res://data/world/season_<id>.json.
func season_path() -> String:
	return "res://data/world/season_%s.json" % id()


## Fichier décrivant les structures engagées dans la discipline.
## Convention : res://data/world/orgs_<id>.json (Valorant garde orgs.json,
## qui est le fichier historique et celui que remplacent les packs).
func orgs_path() -> String:
	return "res://data/world/orgs_%s.json" % id()


## Fichier d'effectifs RÉELS fourni par un pack, s'il en existe un.
func rosters_path() -> String:
	return "res://data/world/rosters_%s.json" % id()


## Métadonnées spécifiques au joueur (pool d'agents, maps préférées…).
func generate_game_data(player: Player, rng: Rng) -> Dictionary:
	return {}


## Colonnes de statistiques affichées dans les tableaux.
## [{"key": "acs", "label": "ACS", "digits": 0}, …]
func stat_columns() -> Array:
	return []


## Nom du camp attaquant / défenseur — « attaque » et « défense » en Valorant,
## « terroristes » et « anti-terroristes » en Counter-Strike.
func side_label(_attacking: bool) -> String:
	return "attaque" if _attacking else "défense"


## Instancie un simulateur de match pour cette discipline.
func create_simulator() -> MatchSimulator:
	return null


## Formats de série possibles (BO) et durée typique d'une rencontre.
func series_formats() -> Array[int]:
	return [1, 3, 5]


## Recalcule les statistiques dérivées (note, indices agrégés) d'un bilan.
## Utilisée pour les cumuls de saison et de carrière, en dehors du match.
func compute_derived_stats(_st: Dictionary) -> void:
	pass
