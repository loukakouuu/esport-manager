class_name Ids
extends RefCounted

## Distributeur d'identifiants stables et sérialisables.
## Les IDs sont des String préfixées ("ply_00042") : lisibles dans les logs et
## dans le JSON de sauvegarde, ce qui économise des heures de debug.

var _counters: Dictionary = {}


func next(prefix: String) -> String:
	var n := int(_counters.get(prefix, 0)) + 1
	_counters[prefix] = n
	return "%s_%05d" % [prefix, n]


func to_dict() -> Dictionary:
	return {"counters": _counters.duplicate()}


func from_dict(d: Dictionary) -> void:
	_counters = (d.get("counters", {}) as Dictionary).duplicate()


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
