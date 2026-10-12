extends SceneTree
const Crew = preload("res://game/presentation/crew/crew_view.gd")
const Library = preload("res://modules/scene_engine/assets/asset_library.gd")
const STEP := 1.0 / 60.0

class TracedPool:
	extends "res://modules/physics_engine/impacts/impact_pool.gd"
	var advances: Array[Vector2] = []
	var registered_frames: Array[Transform3D] = []
	func advance(consumed: float, phase: float) -> void:
		advances.append(Vector2(consumed, phase))
		super.advance(consumed, phase)
	func register_deck(id: String, faces: PackedVector3Array, frame: Transform3D) -> void:
		registered_frames.append(frame)
		super.register_deck(id, faces, frame)

var assertions := 0
var failures := 0
func check(value: bool, detail: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL: ", detail)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var library := Library.new()
	var ship := Node3D.new()
	root.add_child(ship)
	var model: Node3D = library.instantiate_model("res://assets/models/ships/fuchuan-lod0.glb")
	ship.add_child(model)
	var crew := Crew.new()
	ship.add_child(crew)
	check(crew.configure("fuchuan", model, library), "actual source deck configures a real CrewView")
	# Instrument a real ImpactPool, retaining all native bodies and methods.
	# The crew owns this replacement exactly as it owns its configured pool.
	var pool := TracedPool.new()
	crew.add_child(pool)
	crew.set_impact_pool(pool)
	crew._own_pool = true
	pool.set_environment(func(_x, _z, _time): return -100.0, crew._sample_impact_deck)
	var state := {"id":"scheduled-crew","time":20.0,"hull":100.0,"crew":100.0,"sailDeployment":1.0,"sailAngle":0.0}
	crew.apply_snapshot(state, {}, 0.0)
	check(crew.get_visible_count() == 24, "fixture contains actual skinned sailors on real source triangles")
	check(crew.has_method("advance_impacts"), "CrewView exposes physics-owned impact stepping")
	if crew.has_method("advance_impacts"):
		_test_managed(crew, pool, model, state)
	crew.dispose()
	ship.free()
	# The existing standalone API remains usable without opting into management.
	var legacy_ship := Node3D.new()
	root.add_child(legacy_ship)
	var legacy_model: Node3D = library.instantiate_model("res://assets/models/ships/fuchuan-lod0.glb")
	legacy_ship.add_child(legacy_model)
	var legacy := Crew.new()
	legacy_ship.add_child(legacy)
	check(legacy.configure("fuchuan", legacy_model, library), "standalone crew configures normally")
	var legacy_pool := TracedPool.new()
	legacy.add_child(legacy_pool)
	legacy.set_impact_pool(legacy_pool)
	legacy._own_pool = true
	legacy.apply_snapshot(state, {}, 0.0)
	var calls := legacy_pool.advances.size()
	state.time += STEP
	legacy.apply_snapshot(state, {}, STEP)
	check(legacy_pool.advances.size() == calls + 1 and absf(legacy_pool._phase - state.time) < 1.0e-8, "legacy direct apply_snapshot still advances the actual impact pool")
	legacy.dispose()
	legacy_ship.free()
	library.dispose()
	print("CREW_IMPACT_SCHEDULE_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)

func _test_managed(crew: Node3D, pool: Node3D, model: Node3D, state: Dictionary) -> void:
	var rest: Transform3D = model.global_transform
	var calls: int = pool.advances.size()
	crew.call("advance_impacts", 20.0, 0.0, rest)
	check(pool.advances.size() == calls + 1 and pool.get_body_count() == 0, "empty pool still records the real accepted phase and deck")
	check(pool._decks[state.id].global_transform.is_equal_approx(rest), "empty pool has actual native deck collision at authoritative transform")
	crew.apply_events([{"type":"hit","id":"scheduled-hit","targetId":state.id,"position":{"x":0.0,"y":2.0,"z":0.0},"velocity":{"x":10.0,"y":0.0,"z":0.0},"damage":{"crew":0.5}}])
	check(pool.get_body_count() == 1, "real nonlethal hit transfers a drawn source skin to eighteen native bones")
	if pool.get_body_count() != 1:
		return
	var entry: Dictionary = pool._bodies.values()[0]
	var bone: RigidBody3D = entry.bones[1]
	calls = pool.advances.size()
	var registers: int = pool.registered_frames.size()
	for tick in 8:
		var phase := 20.0 + (tick + 1) * STEP
		var frame := rest.translated(Vector3(0.0, (tick + 1) * 0.25, 0.0))
		crew.call("advance_impacts", phase, STEP, frame)
		check(absf(bone.accepted_delta - STEP) < 1.0e-8, "each physics callback requests one native fixed interval, never a render sum")
	check(pool.advances.size() == calls + 8 and pool.registered_frames.size() == registers + 8, "all eight physics callbacks maintain pool and real collision frame")
	check(absf(entry.age - 8.0 * STEP) < 1.0e-8, "native impact lifetime consumes all accepted physics intervals")
	check(absf(crew._time - 20.0) < 1.0e-8, "light impact stepping leaves standing animation presentation untouched")
	check(crew._previous_deck_frame.is_equal_approx(rest.translated(Vector3(0.0, 1.75, 0.0))) and crew._deck_frame.is_equal_approx(rest.translated(Vector3(0.0, 2.0, 0.0))), "moving deck retains adjacent physics frames, not the previous render frame")
	check(pool._decks[state.id].global_transform.is_equal_approx(crew._deck_frame) and model.global_transform.is_equal_approx(rest), "deck collision uses supplied authoritative pose while the drawn model remains unpresented")
	calls = pool.advances.size()
	registers = pool.registered_frames.size()
	state.time = 20.0 + 8.0 * STEP
	crew.apply_snapshot(state, {}, 8.0 * STEP)
	check(pool.advances.size() == calls and pool.registered_frames.size() == registers, "same-phase render never advances or re-registers managed impact physics")
	check(absf(bone.accepted_delta - STEP) < 1.0e-8 and absf(entry.age - 8.0 * STEP) < 1.0e-8, "render preserves the unconsumed Jolt request and accepted lifetime")
	crew.apply_snapshot(state, {}, 0.0)
	check(pool.advances.size() == calls and absf(bone.accepted_delta - STEP) < 1.0e-8, "duplicate zero-delta render cannot overwrite a pending physics step")
	crew.call("advance_impacts", state.time, 0.0, crew._deck_frame)
	check(bone.accepted_delta == 0.0 and bone.freeze, "an explicit paused physics callback freezes the native body")
	var age_before: float = entry.age
	crew.apply_snapshot(state, {}, 0.0)
	check(entry.age == age_before, "paused render leaves native accepted lifetime unchanged")
	# Capture callers bypass scene physics and provide a new accepted phase.
	state.time += STEP
	calls = pool.advances.size()
	crew.apply_snapshot(state, {}, STEP)
	check(pool.advances.size() == calls + 1 and absf(bone.accepted_delta - STEP) < 1.0e-8, "manual new-phase apply_snapshot keeps the original impact fallback")
	crew.apply_snapshot(state, {}, 0.0)
	check(pool.advances.size() == calls + 1 and absf(bone.accepted_delta - STEP) < 1.0e-8, "manual fallback marks its phase so duplicate render cannot zero the request")
	crew.call("advance_impacts", 0.0, 0.0, rest)
	check(pool.get_body_count() == 0 and pool._phase == 0.0, "physics-owned rewind releases old native impacts and accepts phase zero")
	check(crew._seen.is_empty() and crew._fire_velocities.is_empty() and crew._loss_budget == 0, "rewind clears stale event and casualty budgets")
	crew.dispose()
	check(not crew.has_method("advance_impacts") or crew.get_impact_pool() == null, "disposal releases managed pool ownership")
	check(crew.configure("fuchuan", model, crew._library), "disposed crew can reconfigure an independent physics schedule")
	state.time = 0.0
	crew.apply_snapshot(state, {}, 0.0)
	check(crew.get_impact_pool()._phase == 0.0, "newly configured standalone first phase zero remains valid")
