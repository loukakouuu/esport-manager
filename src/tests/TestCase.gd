class_name TestCase
extends RefCounted

## Micro-framework de test. Volontairement minuscule : le but est de pouvoir
## lancer `godot --headless --script res://tools/run_tests.gd` et d'avoir un
## verdict en deux secondes, sans dépendance externe.

var name: String = ""
var failures: Array[String] = []
var checks: int = 0


func _init(p_name: String = "") -> void:
	name = p_name


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func eq(a, b, message: String) -> void:
	check(a == b, "%s (attendu %s, obtenu %s)" % [message, str(b), str(a)])


func near(a: float, b: float, tol: float, message: String) -> void:
	check(absf(a - b) <= tol,
		"%s (attendu %s +/- %s, obtenu %s)" % [message, str(b), str(tol), str(a)])


func between(v: float, lo: float, hi: float, message: String) -> void:
	check(v >= lo and v <= hi,
		"%s (attendu entre %s et %s, obtenu %s)" % [message, str(lo), str(hi), str(v)])


func passed() -> bool:
	return failures.is_empty()
