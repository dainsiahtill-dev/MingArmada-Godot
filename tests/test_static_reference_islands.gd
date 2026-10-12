extends SceneTree

const STATIC_PATH := "res://modules/scene_engine/fidelity_island/static_islands.gd"
var assertions := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, reason: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", reason)

func _run() -> void:
	check(FileAccess.file_exists(STATIC_PATH), "source height-grid static island builder exists")
	print("STATIC_REFERENCE_ISLANDS_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
