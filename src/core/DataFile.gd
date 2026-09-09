class_name DataFile
extends RefCounted

## Chargement des données de contenu (JSON sous res://data/).
##
## Principe : AUCUNE donnée de contenu en dur dans le code. Maps, agents,
## sponsors, prénoms, structures, formats de compétition — tout est éditable
## sans recompiler, ce qui rend l'équilibrage et les mods possibles.

static var _cache: Dictionary = {}


static func load_json(path: String, fallback: Variant = null) -> Variant:
	if _cache.has(path):
		return _cache[path]
	if not FileAccess.file_exists(path):
		Log.w("data", "Fichier introuvable : %s" % path)
		return fallback
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		Log.e("data", "Lecture impossible : %s" % path)
		return fallback
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		Log.e("data", "JSON invalide dans %s ligne %d : %s"
			% [path, json.get_error_line(), json.get_error_message()])
		return fallback
	_cache[path] = json.data
	return json.data


static func clear_cache() -> void:
	_cache.clear()


static func save_json(path: String, data: Variant, pretty: bool = true) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		Log.e("data", "Écriture impossible : %s" % path)
		return false
	f.store_string(JSON.stringify(data, "\t" if pretty else ""))
	f.close()
	return true
