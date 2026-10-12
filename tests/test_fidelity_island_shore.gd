extends SceneTree

const Native = preload("res://modules/scene_engine/fidelity_island/native_math.gd")
const Shore = preload("res://modules/scene_engine/fidelity_island/shore.gd")
const Asset = preload("res://modules/scene_engine/fidelity_island/mesh_asset.gd")
var assertions := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, reason: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", reason)

func _run() -> void:
	var source := Asset.read_json("res://assets/data/fidelity_island/shore-scene.json")
	var oracle := Asset.read_json("res://build/fidelity-island-work/shore-oracle.json")
	check(source.meshes.size() == 8 and not oracle.is_empty(), "original eight independent short meshes and external JS oracle present")
	for sample: Dictionary in oracle.get("samples", []):
		var state := Shore.authored_state(source.meshes[0], source.curves, float(sample.time))
		for key: String in ["translationU", "scaleU", "alpha"]:
			check(float(state[key]) == Native.f32(float(sample[key])), "original controller float stores " + key + " at " + str(sample.time))
		var actual: PackedFloat32Array = Native.texture_transform(source.meshes[0].texture, state)
		for i in 9:
			check(float(actual[i]) == Native.f32(float(sample.matrix[i])), "original Type1 texture matrix coefficient")
	var clock := Native.ControllerClock.new({"flags":9, "frequency":1.0, "phase":0.0, "start_time":0.0, "stop_time":10.0})
	for step: Dictionary in oracle.relativeClock:
		check(clock.advance(float(step.time)) == float(step.value), "relative controller preserves accumulated epoch and reverse-time behavior")
	check(Native.interpolate_float_keys({"interpolation":1,"keys":[{"time":0.0,"value":2.0},{"time":10.0,"value":4.0}]},5.0) == 3.0, "linear source key interpolation also supported")
	var exact := Shore.new()
	check(exact.configure({}, Callable(), {"mode":"exact", "native_origin":Vector3(269925.21875,202766.25,0.0)}), "exact source scene accepts original origin removal")
	check(exact.diagnostics().meshCount == 8 and exact.diagnostics().triangles == 300, "exact mode preserves all original independent triangles")
	check(exact.diagnostics().waterPlaneY == -1.2366943359375, "exact mode preserves original Surf height instead of adopting gameplay height")
	exact.apply_snapshot(12.0)
	check(float(exact.diagnostics().states[0].alpha) == 1.0, "actual shader receives original nonzero noon-time shore state")
	exact.dispose()
	check(exact.get_child_count() == 0, "explicit disposal clears nodes and private mutable materials")
	exact.free()
	var mapping := {"sourceCenter":Vector2(60,70),"sourceOutward":Vector2.UP,"islandCenter":Vector2.ZERO,"inward":Vector2.RIGHT,"scale":1.0}
	var mapped := Shore.new()
	check(mapped.configure(mapping, func(_x: float, _z: float) -> float: return -1.0, {"mode":"mapped"}), "gameplay mapping uses only existing horizontal authority")
	check(mapped.diagnostics().waterPlaneY == 0.035 and mapped.diagnostics().triangles == 300, "mapped visible wave height is an explicit .035 adaptation; open-water triangles retained")
	mapped.dispose()
	check(mapped.configure(mapping, func(_x: float, _z: float) -> float: return 10.0, {"mode":"mapped"}), "land filter remains a valid empty overlay")
	check(mapped.diagnostics().triangles == 0 and mapped.diagnostics().landRejectedTriangles == 300, "all land-bound waves are rejected rather than painted over terrain")
	mapped.dispose()
	mapped.free()
	# Runtime presentation follows the same material/clock as the retained water,
	# without changing source UV/alpha curves or disabling land depth testing.
	var follow := Shore.new()
	check(follow.configure(mapping,func(_x: float,_z: float)->float:return -1.0,{"mode":"mapped"}), "mapped shoreline accepts source-bound surface-follow adaptation")
	var ocean := ShaderMaterial.new()
	ocean.shader = load("res://modules/scene_engine/ocean/reference_game_water.gdshader")
	var waves := PackedVector4Array([Vector4(0.2,0.01,0.02,0.4),Vector4(0.1,-0.03,0.04,0.5),Vector4.ZERO,Vector4.ZERO,Vector4.ZERO,Vector4.ZERO,Vector4.ZERO,Vector4.ZERO])
	ocean.set_shader_parameter("wave_components",waves)
	ocean.set_shader_parameter("wave_count",2)
	ocean.set_shader_parameter("simulation_time",17.25)
	ocean.set_shader_parameter("has_shore_field",false)
	ocean.set_shader_parameter("coastal_attenuation",true)
	check(follow.has_method("sync_surface_state"), "surface-follow API exists before root snapshot wiring")
	if follow.has_method("sync_surface_state"):
		check(bool(follow.call("sync_surface_state",ocean)), "same real water shader state is accepted")
		var info: Dictionary = follow.diagnostics()
		check(info.followSurface and info.surfaceState.simulation_time == 17.25 and info.surfaceState.wave_count == 2, "presentation uses copied wave count and authoritative water time")
		check(info.surfaceState.wave_components == waves, "every original wave component is retained without a new wave profile")
		follow.apply_snapshot(12.0)
		check(follow.diagnostics().surfaceState.simulation_time == 17.25, "UV clock seek does not overwrite the water owner's simulation clock")
		check(bool(follow.call("sync_surface_state",ocean)), "pause repeats the identical water state")
		ocean.set_shader_parameter("simulation_time",4.5)
		check(bool(follow.call("sync_surface_state",ocean)) and follow.diagnostics().surfaceState.simulation_time == 4.5, "rewind copies the actual new owner time instead of accumulated delta")
		var original_before: Variant = ocean.get_shader_parameter("wave_components")
		check(not bool(follow.call("sync_surface_state",null)), "missing water owner disables following and rejects stale surface state")
		check(not follow.diagnostics().followSurface and ocean.get_shader_parameter("wave_components") == original_before, "surface adaptation never mutates water and cannot keep stale following active")
	follow.dispose()
	follow.free()
	print("FIDELITY_ISLAND_SHORE_VERIFY assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures > 0 else 0)
