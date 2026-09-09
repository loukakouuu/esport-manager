class_name GameRegistry
extends RefCounted

## Annuaire des disciplines disponibles.
##
## Ajouter un jeu = ajouter UNE ligne ici. Tout le reste du moteur passe par
## GameRegistry.get_module(game_id) et ignore l'existence de Valorant.

static var _modules: Dictionary = {}
static var _initialised := false


static func _ensure() -> void:
	if _initialised:
		return
	_initialised = true
	register(ValorantModule.new())
	# register(Cs2Module.new())      <- à venir
	# register(LolModule.new())      <- à venir


static func register(m: GameModule) -> void:
	_modules[m.id()] = m


static func get_module(game_id: String) -> GameModule:
	_ensure()
	if not _modules.has(game_id):
		push_error("Discipline inconnue : %s" % game_id)
		return null
	return _modules[game_id]


static func has(game_id: String) -> bool:
	_ensure()
	return _modules.has(game_id)


static func all_ids() -> Array[String]:
	_ensure()
	var out: Array[String] = []
	for k in _modules:
		out.append(str(k))
	return out


static func all_modules() -> Array[GameModule]:
	_ensure()
	var out: Array[GameModule] = []
	for k in _modules:
		out.append(_modules[k])
	return out
