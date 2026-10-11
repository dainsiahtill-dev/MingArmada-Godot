extends SceneTree

const Original = preload("res://modules/physics_engine/ocean/wave_field.gd")
const Coastal = preload("res://modules/physics_engine/ocean/coastal_wave_field.gd")
const RUNTIMES := [preload("res://game/runtime/sailing_runtime.gd"), preload("res://game/runtime/legacy_runtime.gd"), preload("res://game/runtime/mingqi_runtime.gd"), preload("res://game/runtime/naval_practice_runtime.gd"), preload("res://game/runtime/visual_qa_runtime.gd")]
var assertions := 0
var failures := 0

class TerrainSpy extends RefCounted:
	var calls := 0
	var ground := -4.0
	func height(_x: float, _z: float) -> float:
		calls += 1
		return ground

class ExpiringTerrain extends Node:
	func height(_x: float, _z: float) -> float: return -4.0

class HeightRoutingProbe extends RefCounted:
	var full_calls := 0
	var height_calls := 0
	var last_time := NAN
	func sample(_x: float, _z: float, seconds: float) -> Dictionary:
		full_calls += 1
		last_time = seconds
		return {"height":4.125,"gradient":Vector2.ZERO,"normal":Vector3.UP}
	func sample_height(_x: float, _z: float, seconds: float) -> float:
		height_calls += 1
		last_time = seconds
		return 4.125

func _initialize() -> void: _run.call_deferred()

func check(value: bool, reason: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		if failures < 10: printerr("FAIL: ",reason)

func _run() -> void:
	var original := Original.new()
	var coastal := Coastal.new()
	check(original.has_method("sample_height"), "original waves expose a scalar height path")
	check(coastal.has_method("sample_height"), "coastal waves expose an exact scalar height path")
	if original.has_method("sample_height") and coastal.has_method("sample_height"):
		var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/original-ocean-reference.json"))
		for entry: Dictionary in fixture.samples:
			var scalar: float = original.sample_height(entry.x,entry.z,entry.time)
			check(absf(scalar-float(entry.height)) < 1.0e-12,"scalar height preserves the frozen original ocean fixture")
			check(scalar == float(original.sample(entry.x,entry.z,entry.time).height),"scalar retains exactly the complete sampler double height")
		var random := RandomNumberGenerator.new()
		random.seed = 16611011
		# GDScript scalar floats retain double precision; Vector2 components do not.
		var points: Array[Array] = [[0.0,0.0],[-171.415812345678,-32.729061234567],[1000000000.03125,-1000000000.0625],[1.0e-11,-1.0e-10]]
		for _point in 160: points.append([random.randf_range(-6000,6000),random.randf_range(-6000,6000)])
		var spy := TerrainSpy.new()
		check(coastal.configure(spy.height),"valid injected terrain accepted")
		for ground: float in [-50.0,-8.0,-7.999999999,-4.0,-1.0,-0.00001,0.0,2.0,50.0]:
			spy.ground = ground
			for point: Array in points:
				for seconds: float in [-15.25,0.0,1.0/120.0,7.25,88.125,1000000.03125]:
					var baseline: Dictionary = coastal.sample(point[0],point[1],seconds)
					var scalar: float = coastal.sample_height(point[0],point[1],seconds)
					check(scalar == float(baseline.height),"offshore/shallow/land scalar height remains double-exact over coordinates and accepted times")
					check(original.sample_height(point[0],point[1],seconds) == float(original.sample(point[0],point[1],seconds).height),"original scalar uses precisely the same phase and accumulation order")
		spy.ground = -4.0
		spy.calls = 0
		var complete: Dictionary = coastal.sample(.15,.23,8.25)
		check(spy.calls == 5,"complete shallow sampler keeps its center plus four terrain derivative calls")
		spy.calls = 0
		var scalar: float = coastal.sample_height(.15,.23,8.25)
		check(spy.calls == 1 and scalar == float(complete.height),"height-only shallow sampler uses one center query and omits all four derivative queries")
		for ground: float in [-50.0,0.0,2.0,NAN,INF,-INF]:
			spy.ground = ground
			spy.calls = 0
			var scalar_value: float = coastal.sample_height(.15,.23,8.25)
			check(spy.calls == 1,"offshore/land/nonfinite terrain never needs gradient probes")
			check(scalar_value == float(coastal.sample(.15,.23,8.25).height),"nonfinite terrain uses precisely the original offshore fallback")
		var unconfigured := Coastal.new()
		check(not unconfigured.configure(Callable()),"invalid terrain is rejected")
		check(unconfigured.sample_height(.31,.45,12.25) == float(unconfigured.sample(.31,.45,12.25).height),"unconfigured/invalid sampler retains original height fallback")
		var owner := ExpiringTerrain.new()
		check(unconfigured.configure(owner.height),"temporary terrain target accepted")
		owner.free()
		check(unconfigured.sample_height(.31,.45,12.25) == float(unconfigured.sample(.31,.45,12.25).height),"expired terrain callable retains original height fallback")
		spy.ground = -4.0
		var before: Dictionary = coastal.sample(.15,.23,8.25)
		for _request in 10: coastal.sample_height(.15,.23,8.25)
		var after: Dictionary = coastal.sample(.15,.23,8.25)
		check(before == after,"scalar requests cannot mutate complete gradients or normals")
	for runtime_script: GDScript in RUNTIMES:
		var runtime: RefCounted = runtime_script.new()
		var probe := HeightRoutingProbe.new()
		runtime._waves = probe
		check(runtime.sample_water_height(.15,.23,8.25) == 4.125,"runtime preserves scalar result")
		check(probe.height_calls == 1 and probe.full_calls == 0,"runtime height API selects the scalar path instead of discarded gradient work")
		check(probe.last_time == 8.25,"runtime scalar path forwards the caller accepted time")
	print("WAVE_HEIGHT_FAST_PATH_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
