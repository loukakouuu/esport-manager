class_name Ids
extends RefCounted

## Distributeur d'identifiants stables et sérialisables.
## Les IDs sont des String préfixées ("ply_00042") : lisibles dans les logs et
## dans le JSON de sauvegarde, ce qui économise des heures de debug.

var _counters: Dictionary = {}

## Pseudos déjà attribués. Deux joueurs nommés « Karma » dans le même monde
## cassent l'immersion et rendent les tableaux ambigus : l'unicité des pseudos
## est donc gérée ici, au même endroit que celle des identifiants.
var _taken_tags: Dictionary = {}


func next(prefix: String) -> String:
	var n := int(_counters.get(prefix, 0)) + 1
	_counters[prefix] = n
	return "%s_%05d" % [prefix, n]


## Réserve un pseudo. Renvoie false s'il est déjà pris.
func claim_tag(tag: String) -> bool:
	var key := tag.to_lower()
	if _taken_tags.has(key):
		return false
	_taken_tags[key] = true
	return true


func tag_is_free(tag: String) -> bool:
	return not _taken_tags.has(tag.to_lower())


func to_dict() -> Dictionary:
	return {"counters": _counters.duplicate(),
		"taken_tags": _taken_tags.duplicate()}


func from_dict(d: Dictionary) -> void:
	_counters = (d.get("counters", {}) as Dictionary).duplicate()
	_taken_tags = (d.get("taken_tags", {}) as Dictionary).duplicate()


const PLAYER := "ply"
const STAFF := "stf"
const ORG := "org"
const ROSTER := "rst"
const COMP := "cmp"
const FIXTURE := "fix"
const MATCH := "mch"
const DEAL := "spo"
const TX := "tx"
const NEWS := "nws"
const OFFER := "ofr"
const LOAN := "lon"
