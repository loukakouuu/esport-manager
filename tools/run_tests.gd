extends SceneTree

## Lanceur de tests headless.
##
##   godot --headless --path . --script res://tools/run_tests.gd
##
## Aucune scène, aucun autoload : les systèmes sont testables isolément, ce qui
## est la contrepartie de la règle « la logique ne connaît pas l'UI ».


func _initialize() -> void:
	var suites: Array[TestCase] = []
	suites.append_array(CoreTests.run())
	suites.append_array(SimTests.run())
	suites.append_array(SquadTests.run())
	suites.append_array(PackTests.run())
	suites.append_array(ClubTests.run())

	var total := 0
	var failed := 0
	var checks := 0
	print("")
	print("==============================================")
	print("  Esport Manager — tests")
	print("==============================================")
	for tc in suites:
		total += 1
		checks += tc.checks
		if tc.passed():
			print("  [OK]   %s  (%d verifications)" % [tc.name, tc.checks])
		else:
			failed += 1
			print("  [ECHEC] %s" % tc.name)
			for f in tc.failures:
				print("          - %s" % f)
	print("----------------------------------------------")
	print("  %d suites, %d verifications, %d echec(s)" % [total, checks, failed])
	print("==============================================")
	print("")
	quit(1 if failed > 0 else 0)
