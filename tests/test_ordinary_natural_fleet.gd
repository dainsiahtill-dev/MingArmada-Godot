extends "res://tests/fixtures/ordinary_natural_world_case.gd"
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	await run_practice("fleet")
	print("ORDINARY_NATURAL_FLEET_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
