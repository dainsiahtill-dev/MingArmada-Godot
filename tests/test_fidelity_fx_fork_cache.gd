extends SceneTree
## Real blueprint constructor count, full mutable fork ownership and existing
## source-oracle output. No wall-time thresholds or synthetic particle counts.
const Runtime = preload("res://modules/scene_engine/fidelity_fx/particle_runtime.gd")
const Math = preload("res://modules/scene_engine/fidelity_fx/native_particle_math.gd")
const ORACLE := "res://build/fidelity-fx-work/runtime/source-oracle.json"
const SOURCE := "res://assets/data/fidelity_fx/particles/assets-json/"

class TracedReplay:
	extends "res://modules/scene_engine/fidelity_fx/native_particle_replay.gd"
	static var blueprint_builds := 0
	func _init(source: Dictionary = {}, seed: int = 1, index: Dictionary = {}) -> void:
		if not source.is_empty(): blueprint_builds += 1
		super(source,seed,index)

var assertions := 0
var failures := 0

func check(ok: bool, detail: String) -> bool:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL FX fork cache: ",detail)
	return ok

func _same(actual: Variant, expected: Variant, tolerance: float = 0.0) -> bool:
	if actual is Dictionary and expected is Dictionary:
		if actual.size() != expected.size(): return false
		for key: Variant in expected:
			if not actual.has(key) or not _same(actual[key],expected[key],tolerance): return false
		return true
	if actual is Array and expected is Array:
		if actual.size() != expected.size(): return false
		for index in expected.size():
			if not _same(actual[index],expected[index],tolerance): return false
		return true
	if (actual is int or actual is float) and (expected is int or expected is float):
		if tolerance == 0.0 and float(expected) != floor(float(expected)):
			return Math.f32(float(actual)) == Math.f32(float(expected))
		return absf(float(actual)-float(expected)) <= tolerance
	return actual == expected

func _controller_state(replay: RefCounted) -> Array:
	var result := []
	for system: Dictionary in replay.get("systems"):
		var controller: RefCounted = system.controller
		var clock: RefCounted = controller.get("clock")
		result.append({"previousMapped":controller.get("previous_mapped"),"previousVisible":controller.get("previous_visible"),
			"lastApp":controller.get("last_app"),"lastMapped":controller.get("last_mapped"),
			"forceUpdate":controller.get("force_update"),"calls":controller.get("calls"),
			"clockLast":clock.get("last"),"clockAccumulated":clock.get("accumulated"),"clockStarted":clock.get("started")})
	return result

func _fixture(oracle: Dictionary, file: String, time: float) -> Dictionary:
	for record: Dictionary in oracle.cases:
		if record.file == file and float(record.time) == time: return record
	return {}

func _source_contract(oracle: Dictionary, file: String) -> void:
	var asset: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOURCE+file))
	var external := asset.duplicate(true)
	var runtime := Runtime.new()
	if not check(runtime.configure(asset,1), "actual source configures: "+file): return
	var prepared: Dictionary = runtime.get("_asset")
	var prepared_before := prepared.duplicate(true)
	TracedReplay.blueprint_builds = 0
	var canonical := TracedReplay.new(prepared,1,runtime.get("_blocks"))
	canonical.advance(0.0)
	runtime.set("_canonical",canonical)
	check(TracedReplay.blueprint_builds == 1, "tracer records the one real immutable blueprint initialization: "+file)
	var builds := TracedReplay.blueprint_builds
	runtime.seek(0.35)
	check(TracedReplay.blueprint_builds == builds,
		"actual facade seek forks mutable state without reinitializing the complete blueprint: "+file)
	var expected := _fixture(oracle,file,0.35)
	if not check(not expected.is_empty(), "existing physical source oracle contains the measured frame: "+file): return
	check(_same(runtime.source_state(),{"rng":expected.rng,"systems":expected.systems}),
		"120Hz seek retains exact source CRT and all capacity slots: "+file)
	var meshes: Array = runtime.meshes(oracle.camera)
	check(_same(meshes,expected.meshes,0.000002), "source mesh/UV/material output matches the existing oracle: "+file)
	var state_bytes := var_to_bytes(runtime.source_state())
	var mesh_bytes := var_to_bytes(meshes)
	builds = TracedReplay.blueprint_builds
	runtime.seek(0.35)
	check(TracedReplay.blueprint_builds == builds,
		"same-time observation does not rebuild immutable blueprint resources: "+file)
	check(var_to_bytes(runtime.source_state()) == state_bytes and var_to_bytes(runtime.meshes(oracle.camera)) == mesh_bytes,
		"same-time seek preserves full state and mesh bytes: "+file)
	var drawn: RefCounted = runtime.get("_replay")
	var clocks_before := var_to_bytes(_controller_state(drawn))
	var canonical_before := var_to_bytes(canonical.source_state())
	builds = TracedReplay.blueprint_builds
	var child: RefCounted = drawn.call("fork")
	var nested: RefCounted = child.call("fork")
	check(TracedReplay.blueprint_builds == builds,
		"fork and nested fork use mutable-state construction without full blueprint initialization: "+file)
	check(var_to_bytes(child.source_state()) == state_bytes and var_to_bytes(nested.source_state()) == state_bytes,
		"fork and nested fork initially retain every source pool byte and CRT state: "+file)
	check(var_to_bytes(_controller_state(child)) == clocks_before and var_to_bytes(child.meshes(oracle.camera)) == mesh_bytes,
		"fork initially retains exact controller clocks and generated mesh bytes: "+file)
	var systems: Array = child.get("systems")
	var active := Vector2i(-1,-1)
	var inactive := Vector2i(-1,-1)
	for index in systems.size():
		var pool: RefCounted = systems[index].pool
		if active.x < 0 and int(pool.get("num_active")) > 0: active = Vector2i(index,0)
		if inactive.x < 0 and int(pool.get("num_active")) < int(pool.get("capacity")):
			inactive = Vector2i(index,int(pool.get("capacity"))-1)
	if check(active.x >= 0 and inactive.x >= 0, "real source frame exercises both active and inactive pool slots: "+file):
		systems[active.x].pool.particles[active.y].position[0] += 123.0
		systems[inactive.x].pool.particles[inactive.y].position[1] += 321.0
	child.get("rng").call("next")
	systems[0].controller.clock.advance(0.5)
	systems[0].world.translation[0] += 12.0
	systems[0].bounds.center[0] += 34.0
	check(var_to_bytes(drawn.source_state()) == state_bytes and var_to_bytes(canonical.source_state()) == canonical_before,
		"fork mutations isolate active/inactive pool slots, CRT, world transform and bounds from both owners: "+file)
	check(var_to_bytes(_controller_state(drawn)) == clocks_before,
		"fork controller clock mutation cannot alter the retained display controller: "+file)
	check(var_to_bytes(nested.source_state()) == state_bytes,
		"nested fork remains isolated from later mutations of its parent: "+file)
	child.advance(0.4)
	check(var_to_bytes(drawn.source_state()) == state_bytes and var_to_bytes(canonical.source_state()) == canonical_before,
		"advancing an independent fork cannot consume the retained canonical source state: "+file)
	runtime.seek(0.4)
	var continued := _fixture(oracle,file,0.4)
	check(not continued.is_empty() and _same(runtime.source_state(),{"rng":continued.get("rng",{}),"systems":continued.get("systems",[])}),
		"retained canonical owner continues to the original next physical frame: "+file)
	check(asset == external and prepared == prepared_before,
		"forking, observing and mutating mutable state leave both caller and prepared immutable blueprint unchanged: "+file)

func _run() -> void:
	if not check(FileAccess.file_exists(ORACLE), "existing full physical source oracle is available"):
		_finish(); return
	var oracle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ORACLE))
	if not check(oracle.has_all(["cases","camera"]), "source oracle supplies actual native frames and camera basis"):
		_finish(); return
	for file: String in ["fx_cannon_fire_01.nif.json","cannon_ball_splash_01.nif.json","cannon_ball_splash_02.nif.json","cannon_ball_splash_03.nif.json"]:
		_source_contract(oracle,file)
	_finish()

func _finish() -> void:
	print("FIDELITY_FX_FORK_CACHE_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)

func _initialize() -> void: _run.call_deferred()
