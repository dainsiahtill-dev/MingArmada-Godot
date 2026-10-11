extends SceneTree

const Coastal = preload("res://modules/physics_engine/ocean/coastal_wave_field.gd")
const COUNT := 20000
var ground := -50.0
func height(_x: float, _z: float) -> float: return ground
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var waves := Coastal.new()
	waves.configure(height)
	var results := []
	for depth: float in [-50.0,-4.0,2.0]:
		ground = depth
		for trial in 3:
			var full_sum := 0.0
			var scalar_sum := 0.0
			var before := Time.get_ticks_usec()
			for index in COUNT:
				full_sum += float(waves.sample(0.125 + index * .0078125,-0.0625 + index * .00390625,75.0 + index * .0009765625).height)
			var full_usec := Time.get_ticks_usec()-before
			before = Time.get_ticks_usec()
			for index in COUNT:
				scalar_sum += waves.sample_height(0.125 + index * .0078125,-0.0625 + index * .00390625,75.0 + index * .0009765625)
			var scalar_usec := Time.get_ticks_usec()-before
			results.append({"ground":ground,"trial":trial,"queries":COUNT,"fullUsecPerQuery":float(full_usec)/COUNT,"scalarUsecPerQuery":float(scalar_usec)/COUNT,"exactChecksum":full_sum==scalar_sum})
	print("WAVE_HEIGHT_MICROPROBE ",JSON.stringify({"headlessCpuOnly":true,"realTerrain":false,"results":results}))
	quit()
