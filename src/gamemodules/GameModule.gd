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
## Ajouter CS2 = créer src/gamemodules/cs2/Cs2Module.gd + son simulateur,
## l'enregistrer dans GameRegistry, et fournir les données JSON. Aucune
## modification du coeur.

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


## Réglages tactiques par défaut d'une équipe de cette discipline.
func default_tactic() -> Dictionary:
	return {}


## Métadonnées spécifiques au joueur (pool d'agents, maps préférées…).
func generate_game_data(player: Player, rng: Rng) -> Dictionary:
	return {}


## Colonnes de statistiques affichées dans les tableaux.
## [{"key": "acs", "label": "ACS", "digits": 0}, …]
func stat_columns() -> Array:
	return []


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
