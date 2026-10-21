extends "res://game/presentation/world/naval_world_view.gd"
## Test instrumentation retains the real renderer and counts whole-world builds.
var world_configurations := 0
func _configure_world() -> bool:
	world_configurations += 1
	return super._configure_world()
