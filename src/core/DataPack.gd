class_name DataPack
extends RefCounted

## Packs de données : remplacer le contenu du jeu sans toucher au code.
##
## POURQUOI CE SYSTÈME EXISTE
##
## Le jeu est livré avec un univers entièrement fictif. Les vrais noms de
## structures esport sont des marques déposées et les vrais joueurs ont un
## droit à l'image : les embarquer dans le dépôt exposerait le projet, et
## aucun éditeur ne le fait — Football Manager lui-même sort avec des noms
## inventés là où il n'a pas la licence, et laisse sa communauté installer des
## fichiers de correction.
##
## On reprend exactement ce modèle. Le jeu lit ses données à travers une
## CHAÎNE DE RÉSOLUTION :
##
##     user://packs/<pack>/world/orgs.json     ← si présent, il gagne
##     res://data/world/orgs.json              ← sinon, le contenu livré
##
## Un pack peut donc ne remplacer QUE les structures, ou que les prénoms, ou
## tout. Le dépôt reste propre, l'utilisateur reste libre, et un pack se
## partage comme un simple dossier.
##
## Voir docs/DATA_PACKS.md pour le format, et tools/import_liquipedia.gd pour
## un générateur de pack à partir de données publiques.

const PACKS_DIR := "user://packs"
const MANIFEST := "pack.json"
## Préfixe des chemins de données du jeu, remplacé par la racine du pack.
const DATA_ROOT := "res://data/"

## Identifiant du pack actif ; "" = contenu livré avec le jeu.
static var _active := ""
static var _manifest_cache: Dictionary = {}


static func active() -> String:
	return _active


static func set_active(pack_id: String) -> void:
	if _active == pack_id:
		return
	_active = pack_id
	# Les fichiers déjà lus viennent de l'ancienne chaîne : sans purge, le
	# monde suivant mélangerait deux univers.
	DataFile.clear_cache()


static func root_of(pack_id: String) -> String:
	return "%s/%s" % [PACKS_DIR, pack_id]


## Chemin effectif d'un fichier de données, pack actif pris en compte.
static func resolve(path: String) -> String:
	if _active == "" or not path.begins_with(DATA_ROOT):
		return path
	var candidate := "%s/%s" % [root_of(_active), path.substr(DATA_ROOT.length())]
	return candidate if FileAccess.file_exists(candidate) else path


## Le pack actif remplace-t-il ce fichier ?
static func overrides(path: String) -> bool:
	return resolve(path) != path


# ============================================================================
# Découverte
# ============================================================================

## Packs installés, manifeste compris.
## Renvoie [{"id", "name", "author", "version", "description", "license",
##           "attribution", "files": [chemins relatifs remplacés]}]
static func installed() -> Array:
	var out: Array = []
	var dir := DirAccess.open(PACKS_DIR)
	if dir == null:
		return out
	for name in dir.get_directories():
		var m := manifest(name)
		if m.is_empty():
			continue
		out.append(m)
	out.sort_custom(func(a, b): return str(a["name"]) < str(b["name"]))
	return out


static func manifest(pack_id: String) -> Dictionary:
	if _manifest_cache.has(pack_id):
		return _manifest_cache[pack_id]
	var path := "%s/%s" % [root_of(pack_id), MANIFEST]
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		f.close()
		Log.e("pack", "Manifeste illisible : %s" % path)
		return {}
	f.close()
	var d: Dictionary = json.data if json.data is Dictionary else {}
	d["id"] = pack_id
	d["files"] = _files_of(pack_id)
	_manifest_cache[pack_id] = d
	return d


## Fichiers de données remplacés par un pack, en chemins relatifs à data/.
static func _files_of(pack_id: String) -> Array:
	var out: Array = []
	_walk(root_of(pack_id), "", out)
	out.sort()
	return out


static func _walk(base: String, relative: String, out: Array) -> void:
	var full := base if relative == "" else "%s/%s" % [base, relative]
	var dir := DirAccess.open(full)
	if dir == null:
		return
	for file in dir.get_files():
		if file == MANIFEST or not file.ends_with(".json"):
			continue
		out.append(file if relative == "" else "%s/%s" % [relative, file])
	for sub in dir.get_directories():
		_walk(base, sub if relative == "" else "%s/%s" % [relative, sub], out)


static func exists(pack_id: String) -> bool:
	return pack_id != "" and not manifest(pack_id).is_empty()


## Ligne d'attribution à afficher quand un pack l'exige (licence CC-BY-SA par
## exemple). Vide si le pack n'en demande pas.
static func attribution_of(pack_id: String) -> String:
	var m := manifest(pack_id)
	if m.is_empty():
		return ""
	var bits: Array[String] = []
	if str(m.get("source", "")) != "":
		bits.append("Source : %s" % str(m["source"]))
	if str(m.get("license", "")) != "":
		bits.append("Licence : %s" % str(m["license"]))
	if str(m.get("attribution", "")) != "":
		bits.append(str(m["attribution"]))
	return " · ".join(bits)


static func forget() -> void:
	_manifest_cache.clear()
