extends SceneTree
## Cheap path checks only. Never creates or advances a Runtime.
var assertions := 0
var failures := 0
func check(value: bool, detail: String) -> void:
	assertions += 1
	if not value: failures += 1; printerr("FAIL: ", detail)
func _initialize() -> void:
	var script = load("res://tools/qa-journey-paths.gd")
	check(script != null, "journey guard exists")
	if script != null:
		var fresh := "res://docs/migration/evidence/opening-story/qa-guard-unused-" + str(Time.get_ticks_usec()) + ".json"
		check(script.output(["--output=" + fresh]).ok, "fresh workspace evidence path accepted without creating it")
		check(not FileAccess.file_exists(fresh), "validation creates no output")
		check(not script.output([]).ok, "explicit output required")
		check(not script.output(["--output=" + fresh,"--output=" + fresh]).ok, "duplicate output rejected")
		check(not script.output(["--output=user://save.json"]).ok, "user slots rejected")
		check(not script.output(["--output=C:/outside.json"]).ok, "absolute outside path rejected")
		check(not script.output(["--output=res://docs/migration/evidence/opening-story/../outside.json"]).ok, "traversal rejected")
		check(not script.output(["--output=res://docs/migration/evidence/opening-story/new\\outside.json"]).ok, "backslash ambiguity rejected")
		check(not script.output(["--output=res://docs/migration/evidence/opening-story/journey-formal-manual-fire-return.json"]).ok, "historical journey overwrite rejected")
		check(not script.output(["--output=res://docs/migration/evidence/opening-story/new.txt"]).ok, "JSON evidence extension required")
		check(not script.output(["--output=res://docs/migration/evidence/opening-story/empty//new.json"]).ok, "empty path component rejected")
		check(not script.output(["--output=res://docs/migration/evidence/opening-story/CON.json"]).ok, "Windows device name rejected")
		check(not script.output(["--output=res://docs/migration/evidence/opening-story/new:stream.json"]).ok, "Windows alternate stream rejected")
		check(not script.input_journey([]).ok, "explicit input journey required")
		check(not script.input_journey(["--journey=user://save.json"]).ok, "input confined to workspace evidence")
		check(not script.input_journey(["--journey=" + fresh]).ok, "missing input rejected")
		check(script.input_journey(["--journey=res://docs/migration/evidence/opening-story/journey-formal-manual-fire-return.json"]).ok, "existing historical evidence readable without mutation")
	print("JOURNEY_OUTPUT_GUARD_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
