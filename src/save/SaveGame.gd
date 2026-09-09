class_name SaveGame
extends RefCounted

## Sauvegarde et chargement.
##
## Format : JSON compressé (gzip) sous user://saves/. Choix assumé contre les
## ressources .tres de Godot :
##   - un World est un graphe de milliers de RefCounted ; le sérialiseur de
##     ressources y est lent et produit des fichiers énormes ;
##   - le JSON est inspectable et diffable, ce qui divise par dix le temps de
##     debug d'un bug de sauvegarde ;
##   - la migration de version se code en quelques lignes (voir migrate()),
##     alors qu'un .tres cassé par un renommage de champ est irrécupérable.

const SAVE_DIR := "user://saves"
const EXTENSION := ".emsave"
const SCHEMA_VERSION := 1


static func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)


static func path_for(slot_name: String) -> String:
	return "%s/%s%s" % [SAVE_DIR, slot_name.validate_filename(), EXTENSION]


static func save(world: World, slot_name: String) -> bool:
	_ensure_dir()
	var payload := {
		"schema_version": SCHEMA_VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"meta": _meta(world),
		"world": world.to_dict(),
	}
	var f := FileAccess.open_compressed(path_for(slot_name), FileAccess.WRITE,
		FileAccess.COMPRESSION_GZIP)
	if f == null:
		Log.e("save", "Écriture impossible : %s" % path_for(slot_name))
		return false
	f.store_string(JSON.stringify(payload))
	f.close()
	Log.i("save", "Partie sauvegardée dans %s" % path_for(slot_name))
	return true


static func load_slot(slot_name: String) -> World:
	var path := path_for(slot_name)
	if not FileAccess.file_exists(path):
		Log.w("save", "Sauvegarde introuvable : %s" % path)
		return null
	var f := FileAccess.open_compressed(path, FileAccess.READ,
		FileAccess.COMPRESSION_GZIP)
	if f == null:
		Log.e("save", "Lecture impossible : %s" % path)
		return null
	var text := f.get_as_text()
	f.close()

	var json := JSON.new()
	if json.parse(text) != OK:
		Log.e("save", "Sauvegarde corrompue (ligne %d) : %s"
			% [json.get_error_line(), json.get_error_message()])
		return null
	var payload: Dictionary = json.data
	var version := int(payload.get("schema_version", 0))
	if version != SCHEMA_VERSION:
		payload = migrate(payload, version)
		if payload.is_empty():
			return null
	return World.from_dict(payload.get("world", {}))


## Migration entre versions de schéma. Chaque palier est une fonction pure qui
## transforme le payload ; on les enchaîne jusqu'à la version courante.
static func migrate(payload: Dictionary, from_version: int) -> Dictionary:
	var v := from_version
	while v < SCHEMA_VERSION:
		match v:
			# 0 -> 1 : première version publiée, rien à faire.
			0:
				pass
			_:
				Log.e("save", "Aucune migration connue depuis la version %d" % v)
				return {}
		v += 1
	payload["schema_version"] = SCHEMA_VERSION
	return payload


static func list_slots() -> Array:
	_ensure_dir()
	var out: Array = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return out
	for file in dir.get_files():
		if not file.ends_with(EXTENSION):
			continue
		out.append({
			"slot": file.trim_suffix(EXTENSION),
			"path": "%s/%s" % [SAVE_DIR, file],
		})
	return out


static func delete_slot(slot_name: String) -> bool:
	var path := path_for(slot_name)
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(path) == OK


static func _meta(world: World) -> Dictionary:
	var o := world.my_org()
	return {
		"org_name": o.name if o != null else "",
		"date": GameDate.format_long(world.today),
		"season": world.season_year,
		"cash": o.cash() if o != null else 0,
	}
