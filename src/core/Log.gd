class_name Log
extends RefCounted

## Journalisation minimale, filtrable par canal.
## Volontairement statique et sans dépendance : utilisable depuis un test
## headless comme depuis le jeu.

enum Level { DEBUG, INFO, WARN, ERROR }

static var min_level: Level = Level.INFO
static var enabled_channels: Array[String] = []   # vide = tous
static var capture: Array[String] = []            # utilisé par les tests
static var capturing := false


static func d(channel: String, msg: String) -> void:
	_emit(Level.DEBUG, channel, msg)


static func i(channel: String, msg: String) -> void:
	_emit(Level.INFO, channel, msg)


static func w(channel: String, msg: String) -> void:
	_emit(Level.WARN, channel, msg)


static func e(channel: String, msg: String) -> void:
	_emit(Level.ERROR, channel, msg)


static func _emit(lvl: Level, channel: String, msg: String) -> void:
	if lvl < min_level:
		return
	if not enabled_channels.is_empty() and not enabled_channels.has(channel):
		return
	var tag: String = ["DBG", "INF", "WRN", "ERR"][int(lvl)]
	var line := "[%s][%s] %s" % [tag, channel, msg]
	if capturing:
		capture.append(line)
	if lvl >= Level.WARN:
		printerr(line)
	else:
		print(line)
