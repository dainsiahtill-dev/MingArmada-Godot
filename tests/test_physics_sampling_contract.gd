extends SceneTree
## CPU contracts for height-only buoyancy sampling and allocation-free stepping.
const Body = preload("res://modules/physics_engine/ships/ship_dynamics.gd")
const Coastal = preload("res://modules/physics_engine/ocean/coastal_wave_field.gd")
const Types = preload("res://modules/contracts/physics_types.gd")
const Manual = preload("res://modules/physics_engine/ships/manual_handling.gd")
const ADAPTER_PATH := "res://modules/physics_engine/ocean/ocean_adapter.gd"
const STEP := 1.0 / 60.0
var assertions := 0
var failures := 0
var metrics: Array = []

class TerrainCounter:
	extends RefCounted
	var calls := 0
	var depth := 4.0
	func sample_height(_x: float, _z: float) -> float:
		calls += 1
		return -depth

class FullSampler:
	extends RefCounted
	var coastal: RefCounted
	var calls := 0
	func sample(x: float, z: float, seconds: float) -> Dictionary:
		calls += 1
		return coastal.sample(x, z, seconds)

class HeightSampler:
	extends RefCounted
	var coastal: RefCounted
	var full_calls := 0
	var height_calls := 0
	var invalid := false
	func sample(x: float, z: float, seconds: float) -> Dictionary:
		full_calls += 1
		return {"height": NAN} if invalid else coastal.sample(x, z, seconds)
	func sample_height(x: float, z: float, seconds: float) -> float:
		height_calls += 1
		return NAN if invalid else coastal.sample_height(x, z, seconds)

class SharedFullSampler:
	extends RefCounted
	var result := {"height":4.0}
	func sample(_x: float, _z: float, _seconds: float) -> Dictionary:
		return result

class SnapshotCountBody:
	extends "res://modules/physics_engine/ships/ship_dynamics.gd"
	var snapshot_calls := 0
	func get_snapshot() -> Dictionary:
		snapshot_calls += 1
		return super.get_snapshot()

func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	_test_probe_cost()
	_test_adapter()
	_test_trajectories()
	_test_invalid_and_repeated_time()
	_test_in_place()
	print("PHYSICS_SAMPLING_METRICS ", JSON.stringify(metrics))
	print("PHYSICS_SAMPLING_CONTRACT_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)

func _coastal(terrain: RefCounted) -> RefCounted:
	var waves := Coastal.new()
	check(waves.configure(terrain.sample_height), "coastal fixture configured")
	return waves

func _test_probe_cost() -> void:
	var full_terrain := TerrainCounter.new()
	var height_terrain := TerrainCounter.new()
	var full := FullSampler.new(); full.coastal = _coastal(full_terrain)
	var height := HeightSampler.new(); height.coastal = _coastal(height_terrain)
	var baseline := Body.new(); var candidate := Body.new()
	var spec := {"kind":"fuchuan", "sailDeployment":0.0, "config":{"waterRelativeBuoyancy":true}}
	check(baseline.configure(spec, full_terrain.sample_height, full), "full-only body configured")
	check(candidate.configure(spec, height_terrain.sample_height, height), "height-capable body configured")
	full_terrain.calls = 0; height_terrain.calls = 0; full.calls = 0; height.full_calls = 0; height.height_calls = 0
	baseline.step(STEP, {"time":STEP}); candidate.step(STEP, {"time":STEP})
	check(baseline.get_snapshot() == candidate.get_snapshot(), "four-point height optimization preserves the full numerical state")
	check(full_terrain.calls == 25, "full shallow-water tick samples four buoyancy probes plus the existing center fallback")
	check(height_terrain.calls == 5, "height-only shallow-water tick preserves all five water samples with five terrain queries")
	check(height.height_calls == 5 and height.full_calls == 0, "buoyancy requests scalar height without discarded normals")
	metrics.append({"case":"one-shallow-tick", "full_terrain_calls":full_terrain.calls, "scalar_terrain_calls":height_terrain.calls, "full_surface_calls":full.calls, "scalar_height_calls":height.height_calls, "candidate_full_calls":height.full_calls})
	full_terrain.calls = 0; height_terrain.calls = 0; full.calls = 0; height.full_calls = 0; height.height_calls = 0
	check(baseline.get_wave_debug() == candidate.get_wave_debug(), "four-probe inspection retains the full sampled values")
	check(full_terrain.calls == 20 and height_terrain.calls == 4, "four buoyancy probes reduce measured terrain queries from twenty to four")
	metrics.append({"case":"four-buoyancy-probes", "full_terrain_calls":full_terrain.calls, "scalar_terrain_calls":height_terrain.calls, "full_surface_calls":full.calls, "scalar_height_calls":height.height_calls, "candidate_full_calls":height.full_calls})

func _adapter() -> RefCounted:
	check(ResourceLoader.exists(ADAPTER_PATH), "ocean height adapter exists in physics engine")
	if not ResourceLoader.exists(ADAPTER_PATH): return null
	var script: Script = load(ADAPTER_PATH)
	var adapter: RefCounted = script.new()
	check(adapter.has_method("sample_height"), "ocean adapter exposes scalar height")
	return adapter if adapter.has_method("sample_height") else null

func _test_adapter() -> void:
	var adapter := _adapter()
	if adapter == null: return
	var terrain := TerrainCounter.new()
	var height := HeightSampler.new(); height.coastal = _coastal(terrain)
	adapter.sampler = height; adapter.sea_level = 2.25; adapter.accepted_time = 7.5
	for point: Vector2 in [Vector2.ZERO, Vector2(-24.5, 13.25), Vector2(1.0e5, -2.0e5)]:
		var expected: float = height.coastal.sample(point.x, point.y, 7.5).height + 2.25
		check(adapter.sample_height(point.x, point.y, 900.0) == expected, "adapter scalar path uses accepted time and sea level")
		check(adapter.sample(point.x, point.y, -90.0).height == expected, "full and scalar adapter share their accepted surface")
	var full := FullSampler.new(); full.coastal = height.coastal
	adapter.sampler = full
	check(adapter.sample_height(1.25, -4.5, 90.0) == full.coastal.sample(1.25, -4.5, 7.5).height + 2.25 and full.calls == 1, "sample-only injected samplers keep the existing fallback contract")
	var shared := SharedFullSampler.new(); adapter.sampler = shared
	check(adapter.sample_height(1.0, 2.0, 30.0) == 6.25 and shared.result.height == 6.25, "sample-only fallback retains the full adapter result handling for a shared sampler dictionary")
	adapter.sampler = null; adapter.set_heading({"x":0.7,"y":-0.4})
	for seconds: float in [0.0, -5.0, 17.25]:
		adapter.accepted_time = seconds
		check(adapter.sample_height(-17.0, 3.5, 900.0) == adapter.sample(-17.0, 3.5, -900.0).height, "descriptor-only scalar fallback retains exact accumulation order")
	adapter.waves = []
	check(adapter.sample_height(1.0, 2.0, 3.0) == 2.25, "empty waves preserve a nonzero sea level")
	height.invalid = true; adapter.sampler = height
	check(is_nan(adapter.sample_height(1.0, 2.0, 3.0)), "invalid trusted scalar samples remain invalid for the solver guard")

func _test_trajectories() -> void:
	for kind: String in Types.SHIP_SPECS:
		for depth: float in [4.0, 24.0]:
			var terrain := TerrainCounter.new(); terrain.depth = depth
			var waves := _coastal(terrain)
			var full := FullSampler.new(); full.coastal = waves
			var height := HeightSampler.new(); height.coastal = waves
			var baseline := Body.new(); var candidate := Body.new()
			var spec := {"kind":kind,"position":{"x":-160.0,"z":-60.0},"heading":0.45,"speed":2.0,"sailDeployment":0.85,"wind":{"direction":{"x":-0.8,"z":-0.6},"speed":14.0},"config":{"waterRelativeBuoyancy":true}}
			check(baseline.configure(spec, terrain.sample_height, full) and candidate.configure(spec, terrain.sample_height, height), "paired ship configured " + kind)
			var equal_ticks := 0
			for tick in 600:
				if tick == 180:
					check(baseline.set_cargo_mass(200.0) and candidate.set_cargo_mass(200.0), "live cargo accepted " + kind)
				if tick == 300:
					var draft: float = Types.ship_spec(kind).draft * 0.9
					check(baseline.set_draft_meters(draft) and candidate.set_draft_meters(draft), "live draft accepted " + kind)
				var previous: Dictionary = baseline.get_snapshot()
				var turn := 0.35 if tick < 360 else -0.2
				var speed := sqrt(float(previous.velocity.x) ** 2 + float(previous.velocity.z) ** 2)
				var controls := {"time":(tick + 1) * STEP,"rudderAngleDeg":turn * 30.0,"crewSteeringForce":10000.0,"sailDeployment":0.85,"manualAssist":Manual.build(kind, turn, speed, 1.0, 1.0, 1.0, false, 0.85, true)}
				baseline.step(STEP, controls); candidate.step(STEP, controls)
				var equal: bool = baseline.get_snapshot() == candidate.get_snapshot() and baseline.get_buoyancy_debug() == candidate.get_buoyancy_debug()
				check(equal, "full/scalar exact trajectory " + kind + " depth=" + str(depth) + " tick=" + str(tick))
				if equal: equal_ticks += 1
			metrics.append({"case":"paired-trajectory","kind":kind,"depth_m":depth,"ticks":600,"exact_ticks":equal_ticks,"cargo_change_tick":180,"draft_change_tick":300})

func _test_invalid_and_repeated_time() -> void:
	var terrain := TerrainCounter.new()
	var waves := HeightSampler.new(); waves.coastal = _coastal(terrain)
	var body := Body.new()
	check(body.configure({"kind":"fisherman","config":{"waterRelativeBuoyancy":true}}, terrain.sample_height, waves), "guard fixture configured")
	body.step(STEP, {"time":STEP})
	var before: Dictionary = body.get_snapshot()
	var calls := waves.height_calls
	for seconds: float in [0.0, -1.0, NAN, INF]: body.step(seconds, {"time":2.0})
	body.step(STEP, {"time":STEP,"rudderAngleDeg":30.0}); body.step(STEP, {"time":-1.0})
	check(body.get_snapshot() == before and waves.height_calls == calls, "invalid, paused/repeated and rewind times cannot mutate or sample the hull")
	waves.invalid = true
	body.step(STEP, {"time":STEP * 2.0})
	var after: Dictionary = body.get_snapshot()
	check(is_finite(after.position.y) and is_finite(after.pitch) and is_finite(after.heel), "invalid scalar water follows the existing finite no-wave guard")
	var detached: Dictionary = body.get_snapshot(); detached.position.x = 9999.0; detached.sailDebug.clear()
	check(body.get_snapshot() == after, "public snapshots remain detached after scalar sampling")

func _test_in_place() -> void:
	var baseline := SnapshotCountBody.new(); var candidate := SnapshotCountBody.new()
	check(candidate.has_method("step_in_place"), "marine solver exposes a no-snapshot step")
	if not candidate.has_method("step_in_place"): return
	var terrain := TerrainCounter.new()
	var waves := _coastal(terrain)
	var spec := {"kind":"fuchuan","sailDeployment":0.8,"config":{"waterRelativeBuoyancy":true}}
	check(baseline.configure(spec, terrain.sample_height, waves) and candidate.configure(spec, terrain.sample_height, waves), "in-place pair configured")
	baseline.snapshot_calls = 0; candidate.snapshot_calls = 0
	var controls := {"time":STEP,"rudderAngleDeg":15.0,"sailDeployment":0.8}
	var public: Dictionary = baseline.step(STEP, controls)
	candidate.call("step_in_place", STEP, controls)
	check(baseline.snapshot_calls == 1 and candidate.snapshot_calls == 0, "internal stepping constructs no discarded full snapshot while public step retains one")
	check(public == candidate.get_snapshot(), "in-place and public steps produce identical numerical state")
	var before: Dictionary = candidate.get_snapshot()
	for seconds: float in [0.0, -1.0, NAN, INF]: candidate.call("step_in_place", seconds, {"time":3.0})
	candidate.call("step_in_place", STEP, controls)
	check(candidate.get_snapshot() == before, "in-place step retains all rejected-time guards")
