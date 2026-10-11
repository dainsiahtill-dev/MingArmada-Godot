extends SceneTree

var failures: Array[String] = []
var assertions := 0

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await _test_pool()
	_test_crew_rewind()
	for failure in failures:
		printerr("FAIL: ", failure)
	print("REFERENCE_CREW_LIFECYCLE assertions=", assertions, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _definition(height: float) -> Dictionary:
	var library = load("res://modules/scene_engine/assets/asset_library.gd").new()
	var model: Node3D = library.instantiate_model("res://assets/models/sailors/sailor-lod0.glb")
	root.add_child(model)
	model.position.y = height
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var transforms: Array = []
	var parents: Array = []
	var names: Array = []
	for index in skeleton.get_bone_count():
		transforms.append(skeleton.global_transform * skeleton.get_bone_global_pose(index))
		parents.append(skeleton.get_bone_parent(index))
		names.append(skeleton.get_bone_name(index))
	model.free()
	library.dispose()
	return {"transforms": transforms, "parents": parents, "names": names}

func _test_pool() -> void:
	var pool = load("res://modules/physics_engine/impacts/impact_pool.gd").new()
	root.add_child(pool)
	pool.set_environment(func(_x, _z, _time): return 0.0)
	pool.advance(0.0, 10.0)
	var events: Array = []
	var releases: Array = []
	pool.visual_event.connect(func(event): events.append(event))
	var source := {"target_id": "wet", "event_id": "one-hit", "slot": 1, "velocity": Vector3(0.4, 0, 0), "casualty": true, "release": func(recover): releases.append(recover)}
	var definition := _definition(0.15)
	check(not pool.spawn(definition, source).is_empty(), "real eighteen-bone impact spawns")
	check(pool.spawn(definition, source).is_empty(), "same hit and slot cannot own two physical rigs")
	check(pool.get_body_count() == 1, "duplicate rejection preserves one body budget")
	for frame in 90:
		pool.advance(1.0 / 60.0, 10.0 + (frame + 1) / 60.0)
		await physics_frame
		await process_frame
	var splashes := events.filter(func(event): return event.type == "crew-water-entry")
	check(splashes.size() == 1, "eighteen water contacts produce single entry splash")
	if not splashes.is_empty():
		check(splashes[0].time >= 10.0 and splashes[0].position is Vector3, "water event carries accepted phase and world contact")
	var age: float = pool.diagnostics().bodies[0].age
	pool.advance(0.5, 11.5)
	check(is_equal_approx(float(pool.diagnostics().bodies[0].age), age), "repeated accepted phase cannot age same impact twice")
	pool.advance(0.0, 3.0)
	check(pool.get_body_count() == 0 and releases == [false], "clock rewind releases all old impacts without recovery")
	check(pool.diagnostics().global_count == 0, "rewind returns global articulated budget")
	check(not pool.spawn(definition, source).is_empty(), "rewind permits new timeline event identity")
	pool.dispose()
	pool.free()

func _test_crew_rewind() -> void:
	var library = load("res://modules/scene_engine/assets/asset_library.gd").new()
	var vessel := Node3D.new()
	root.add_child(vessel)
	var model: Node3D = library.instantiate_model("res://assets/models/ships/fuchuan-lod0.glb")
	vessel.add_child(model)
	var crew = load("res://game/presentation/crew/crew_view.gd").new()
	vessel.add_child(crew)
	crew.configure("fuchuan", model, library)
	var state := {"id": "rewound", "time": 20.0, "crew": 24.0, "hull": 100.0}
	crew.apply_snapshot(state, {}, 0.0)
	var support: Dictionary = crew.sample_deck(0.0, -6.0)
	var previous: Vector3 = model.global_transform * (support.point + Vector3.UP * 0.08)
	model.position.y = -4.0
	state.time += 1.0 / 60.0
	crew.apply_snapshot(state, {}, 1.0 / 60.0)
	var expected: Vector3 = model.global_transform * support.point
	var actual: Dictionary = crew._sample_impact_deck("rewound", expected + Vector3.UP * 0.01, previous, state.time, 20.0)
	check(not actual.is_empty() and actual.point.is_equal_approx(expected), "physical impact deck follows actual sinking model offset")
	model.position.y = 0.0
	crew.apply_snapshot(state, {}, 0.0)
	crew.apply_events([{"id": "strike", "type": "hit", "targetId": "rewound", "position": {"x": 0, "y": 3, "z": 0}, "velocity": {"x": 10, "y": 0, "z": 0}, "damage": {"crew": 0.5}}])
	check(crew.get_impact_pool().get_body_count() == 1, "nonlethal impact transfers actual skin")
	state.time = 2.0
	crew.apply_snapshot(state, {}, 0.0)
	check(crew.get_impact_pool().get_body_count() == 0 and crew.get_visible_count() == 24, "crew rewind clears physics and restores current authority coverage")
	check(crew.diagnostics().accepted_time == 2.0, "crew samples restored accepted time")
	crew.dispose()
	vessel.free()
	library.dispose()
