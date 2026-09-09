class_name TeamSheet
extends RefCounted

## Photo d'une équipe au moment d'un match, prête à être simulée.
##
## Le simulateur ne connaît NI le World, NI les systèmes : on lui remet une
## feuille de match complète. Conséquence directe : on peut simuler 10 000
## matchs dans un test unitaire sans instancier le reste du jeu.

var roster: Roster = null
var org: Organization = null
var lineup: Array[Player] = []      # les titulaires, dans l'ordre
var bench: Array[Player] = []
var coach: Staff = null
var analyst: Staff = null
var tactic: Dictionary = {}
var chemistry: float = 50.0
var reputation: int = 2000

## Familiarité avec l'adversaire (préparation) : 0..1, produit par l'analyste.
var prep_level: float = 0.5


func name() -> String:
	if org != null:
		return org.name
	return roster.name if roster != null else "?"


func tag() -> String:
	if org != null and org.tag != "":
		return org.tag
	return name().substr(0, 3).to_upper()


func id() -> String:
	return roster.id if roster != null else ""


func igl() -> Player:
	for p in lineup:
		if p.is_igl:
			return p
	return lineup[0] if not lineup.is_empty() else null
