extends "res://tools/capture-native-qa.gd"
## Keep the current reference implementation evidence separate from earlier QA.
func _initialize() -> void:
	directory = "res://docs/migration/evidence/reference-implementation-qa"
	run.call_deferred()
