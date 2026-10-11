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
	var crew_path := "res://game/presentation/crew/crew_view.gd"
	var pool_path := "res://modules/physics_engine/impacts/impact_pool.gd"
	check(FileAccess.file_exists(crew_path), "native visible CrewView is required")
	check(FileAccess.file_exists(pool_path), "native articulated Jolt impact pool is required")
	if FileAccess.file_exists(crew_path) and FileAccess.file_exists(pool_path):
		var crew_script = load(crew_path)
		var pool_script = load(pool_path)
		check(crew_script != null and pool_script != null, "crew and impact scripts compile")
		if crew_script and pool_script:
			await _test_crew(crew_script)
			await _test_impacts(pool_script)
	for message in failures:
		printerr("FAIL: ", message)
	print("CREW_IMPACT_TESTS assertions=", assertions, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _test_crew(crew_script) -> void:
	var library = load("res://modules/scene_engine/assets/asset_library.gd").new()
	var ship := Node3D.new()
	root.add_child(ship)
	var model = library.instantiate_model("res://assets/models/ships/fuchuan-lod0.glb")
	ship.add_child(model)
	var crew = crew_script.new()
	ship.add_child(crew)
	check(crew.configure("fuchuan", model, library), "crew derives stations from actual GLB deck")
	var state := {"id": "crew-test", "time": 20.0, "hull": 100.0, "crew": 100.0, "sailDeployment": 1.0, "sailAngle": 0.0, "rudder": 0.3, "visual": {"velocity": {"x": 2.0, "z": 0.0}}, "cooldownSeconds": {"port": 0.0, "starboard": 0.0}}
	crew.apply_snapshot(state, {}, 0.0)
	check(crew.get_visible_count() == 24, "near healthy vessel shows twenty-four actual colored sailors")
	check(crew.diagnostics().accepted_time == 20.0, "first render samples supplied current accepted clock")
	var skeletons: Array = []
	for instance: Dictionary in crew.get_instances():
		var skeleton: Skeleton3D = instance.skeleton
		check(skeleton.get_bone_count() == 18, "every drawn sailor retains eighteen live bones")
		check(not skeletons.has(skeleton), "each drawn sailor owns separate live skeleton")
		skeletons.append(skeleton)
		var player: AnimationPlayer = instance.player
		for clip in ["idle", "helm", "haul", "load-cannon", "walk", "lookout"]:
			check(player.has_animation(clip), "authored animation retained: " + clip)
		var support: Dictionary = crew.sample_deck(instance.root.position.x, instance.root.position.z)
		check(not support.is_empty(), "feet have actual triangle support, never water/freeboard guess")
		if not support.is_empty():
			check(absf(instance.root.position.y - support.point.y - 0.005) < 0.04, "standing feet clear actual plank deck")
		var mesh: MeshInstance3D = instance.root.find_children("*", "MeshInstance3D", true, false)[0]
		check(mesh != null and mesh.mesh.surface_get_material(0).vertex_color_use_as_albedo, "original colored cloth remains enabled")
	var first: Dictionary = crew.get_instances()[0]
	var paused_pose: Transform3D = first.skeleton.get_bone_pose(3)
	await physics_frame
	await physics_frame
	crew.apply_snapshot(state, {}, 0.0)
	check(first.skeleton.get_bone_pose(3).is_equal_approx(paused_pose), "wall frames cannot advance paused clip")
	state.time = 21.0
	crew.apply_snapshot(state, {}, 1.0 / 60.0)
	var current_pose: Transform3D = first.skeleton.get_bone_pose(3)
	check(not current_pose.is_equal_approx(paused_pose), "supplied accepted time advances actual bone pose")
	crew.set_lod_distance(350.0)
	crew.apply_snapshot(state, {}, 0.0)
	check(crew.get_visible_count() == 2, "far LOD caps visible crew at two")
	crew.set_lod_distance(1900.0)
	check(crew.get_visible_count() == 0, "beyond 1800m releases standing crew")
	crew.set_lod_distance(50.0)
	crew.apply_snapshot(state, {}, 0.0)
	check(crew.get_visible_count() == 24, "near LOD restores crew without new accepted time")
	check(crew.diagnostics().accepted_time == 21.0, "LOD transition keeps accepted animation phase")
	var accepted_first: Dictionary = crew.get_instances()[0]
	var phase_pose: Transform3D = accepted_first.skeleton.get_bone_pose(3)
	crew.set_reduced_motion(true)
	var reduced_pose: Transform3D = accepted_first.skeleton.get_bone_pose(3)
	state.time = 22.0
	crew.apply_snapshot(state, {}, 1.0 / 60.0)
	check(accepted_first.skeleton.get_bone_pose(3).is_equal_approx(reduced_pose), "reduced motion holds authored quarter clip phase")
	crew.set_reduced_motion(false)
	state.time = 21.0
	crew.apply_snapshot(state, {}, 0.0)
	check(accepted_first.skeleton.get_bone_pose(3).is_equal_approx(phase_pose), "reduced-motion round trip recovers same accepted phase")
	state.sailAngle = 0.1
	crew.apply_snapshot(state, {}, 0.0)
	crew.apply_events([{"type": "fire", "id": "work-fire", "shipId": "crew-test", "side": "port", "projectileId": "work-projectile", "velocity": {"x": 10.0, "y": 0.0, "z": 0.0}}])
	var clips: Array = []
	for role: Dictionary in crew.diagnostics().roles:
		clips.append(role.clip)
	for clip in ["helm", "haul", "load-cannon", "walk", "lookout", "idle"]:
		check(clips.has(clip), "real helm/sail/fire/motion selects authored clip: " + clip)
	var requests: Array = []
	for ship_index in 8:
		requests.append({"id": "ship-%d" % ship_index, "distance": float(ship_index), "requested": 24})
	var allocation: Dictionary = crew_script.allocate_sailors(requests)
	var allocated := 0
	for value: int in allocation.values():
		allocated += value
		check(value >= 1, "global standing budget reserves visible coverage for each vessel")
	check(allocated == 120, "standing allocation respects shared 120 sailor budget")
	var deck_support: Dictionary = crew.sample_deck(0.0, -6.0)
	var old_contact: Vector3 = crew.global_transform * (deck_support.point + Vector3.UP * 0.08)
	ship.position.y = 10.0
	crew.apply_snapshot(state, {}, 1.0 / 60.0)
	var moving_support: Dictionary = crew._sample_impact_deck("crew-test", old_contact + Vector3.UP * 9.99, old_contact, state.time, state.time - 1.0 / 60.0)
	check(not moving_support.is_empty(), "moving-deck contact transforms previous point with previous vessel frame")
	ship.position.y = 0.0
	crew.apply_snapshot(state, {}, 0.0)
	var hit := {"type": "hit", "id": "nonlethal-hit", "targetId": "crew-test", "projectileId": "work-projectile", "position": {"x": 0.0, "y": 2.0, "z": 0.0}, "ammo": "solid", "damage": {"crew": 0.5}}
	crew.apply_events([hit])
	check(crew.get_visible_count() == 23 and crew.get_impact_pool().get_body_count() == 1, "nonlethal hit transfers one animated sailor to native articulated rig")
	crew.apply_events([hit])
	check(crew.get_impact_pool().get_body_count() == 1, "duplicate hit cannot spawn another body or duplicate crew damage")
	state.time = 22.25
	crew.apply_snapshot(state, {}, 1.25)
	check(crew.get_visible_count() == 24 and crew.get_impact_pool().get_body_count() == 0, "nonlethal expiry returns visible original animated sailor")
	state.crew = 99.0
	state.time = 22.2666666667
	crew.apply_snapshot(state, {}, 1.0 / 60.0)
	hit.id = "casualty-hit"
	hit.damage.crew = 1.0
	crew.apply_events([hit])
	check(crew.get_impact_pool().diagnostics().bodies[0].casualty, "only authoritative crew loss makes hit a casualty")
	for frame in 3:
		state.time += 1.0 / 60.0
		crew.apply_snapshot(state, {}, 1.0 / 60.0)
		await physics_frame
		await process_frame
	crew.apply_snapshot(state, {}, 0.0)
	var casualty: Dictionary = crew.get_impact_pool().diagnostics().bodies[0]
	var ragdoll_skeletons: Array = crew.get_impact_pool().find_children("*", "Skeleton3D", true, false)
	check(ragdoll_skeletons.size() == 1, "rendered colored original skin travels with native ragdoll")
	if not ragdoll_skeletons.is_empty():
		var rig: Skeleton3D = ragdoll_skeletons[0]
		check((rig.global_transform * rig.get_bone_global_pose(1)).origin.distance_to(casualty.transforms[1].origin) < 0.01, "native physical pose drives visible sailor bones")
	state.crew = 3.9
	crew.apply_snapshot(state, {}, 0.0)
	check(crew.get_visible_count() == 3, "actual fractional crew count is floored")
	state.hull = 0.0
	crew.apply_snapshot(state, {}, 0.0)
	check(crew.get_visible_count() == 0, "destroyed ship cannot show standing personnel")
	crew.dispose()
	crew.dispose()
	check(crew.get_visible_count() == 0, "crew disposal is idempotent")
	ship.free()
	for kind in ["fuchuan", "fisherman", "merchant", "voc", "patrol", "heavy"]:
		var vessel := Node3D.new()
		root.add_child(vessel)
		var crew_view = crew_script.new()
		vessel.add_child(crew_view)
		for lod in 3:
			var active: Node3D = library.instantiate_model("res://assets/models/ships/%s-lod%d.glb" % [kind, lod])
			vessel.add_child(active)
			if lod == 0:
				check(crew_view.configure(kind, active, library), "actual deck stations available for " + kind)
			else:
				check(crew_view.set_ship_model(active), "active original ship LOD updates deck support: %s-%d" % [kind, lod])
			crew_view.set_lod_distance([50.0, 200.0, 700.0][lod])
			crew_view.apply_snapshot({"id": kind, "time": 31.0, "crew": 100.0, "hull": 100.0}, {}, 0.0)
			var visible: int = crew_view.get_visible_count()
			check(visible > 0 and visible <= [24, 8, 2][lod], "six-kind/three-LOD visible count follows actual stations")
			for sailor: Dictionary in crew_view.get_instances():
				var support: Dictionary = crew_view.sample_deck(sailor.root.position.x, sailor.root.position.z)
				check(not support.is_empty() and absf(sailor.root.position.y - support.point.y - 0.005) < 0.04, "all native GLB LOD crew feet follow actual loaded triangles")
		crew_view.dispose()
		vessel.free()
	var wiped_vessel := Node3D.new()
	root.add_child(wiped_vessel)
	var wiped_model: Node3D = library.instantiate_model("res://assets/models/ships/fuchuan-lod0.glb")
	wiped_vessel.add_child(wiped_model)
	var wiped_crew = crew_script.new()
	wiped_vessel.add_child(wiped_crew)
	wiped_crew.configure("fuchuan", wiped_model, library)
	wiped_crew.apply_snapshot({"id": "wiped", "time": 1.0, "crew": 2.0, "hull": 100.0}, {}, 0.0)
	wiped_crew.apply_snapshot({"id": "wiped", "time": 1.0 + 1.0 / 60.0, "crew": 0.0, "hull": 0.0}, {}, 1.0 / 60.0)
	check(wiped_crew.get_visible_count() == 0, "terminal snapshot immediately clears standing crew")
	wiped_crew.apply_events([{"type": "hit", "id": "terminal-hit", "targetId": "wiped", "position": {"x": 0.0, "y": 2.0, "z": 0.0}, "velocity": {"x": 10.0, "y": 0.0, "z": 0.0}, "damage": {"crew": 2.0}}])
	check(wiped_crew.get_impact_pool().get_body_count() == 2, "terminal cannon hit transfers retiring drawn sailors before releasing their skins")
	wiped_crew.dispose()
	wiped_vessel.free()
	library.dispose()

func _definition(offset := Vector3.ZERO) -> Dictionary:
	var library = load("res://modules/scene_engine/assets/asset_library.gd").new()
	var model = library.instantiate_model("res://assets/models/sailors/sailor-lod0.glb")
	root.add_child(model)
	model.position = offset
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var player: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.play("helm")
	player.seek(0.87, true)
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

func _test_impacts(pool_script) -> void:
	check(ProjectSettings.get_setting("physics/3d/physics_engine") == "Jolt Physics", "test uses native Jolt engine")
	var pool = pool_script.new()
	root.add_child(pool)
	pool.set_environment(func(_x, _z, _time): return -100.0)
	var definition := _definition(Vector3(0, 5, 0))
	var id: String = pool.spawn(definition, {"target_id": "test", "event_id": "native", "slot": 0, "velocity": Vector3(10, 0, 0), "casualty": true})
	check(not id.is_empty(), "sampled animated pose spawns articulated native impact")
	var entry: Dictionary = pool.diagnostics().bodies[0]
	check(entry.bone_count == 18 and entry.joint_count == 17, "actual eighteen native rigid bodies joined by seventeen joints")
	for index in 18:
		check(entry.transforms[index].origin.is_equal_approx(definition.transforms[index].origin), "ragdoll starts sampled animated world pose")
	var before: Vector3 = entry.transforms[1].origin
	for frame in 8:
		pool.advance(1.0 / 60.0, (frame + 1) / 60.0)
		await physics_frame
		await process_frame
	entry = pool.diagnostics().bodies[0]
	print("NATIVE_JOLT_SAMPLE before=", before, " after=", entry.transforms[1].origin)
	check(entry.transforms[1].origin.x > before.x + 0.3, "real native Jolt impulse visibly moves casualty")
	pool.advance(0.0, 8.0 / 60.0)
	var frozen: Transform3D = entry.transforms[1]
	await physics_frame
	await physics_frame
	check(pool.diagnostics().bodies[0].transforms[1].is_equal_approx(frozen), "paused accepted clock freezes native ragdoll")
	print("NATIVE_JOLT_PAUSE frozen=", frozen.origin, " after=", pool.diagnostics().bodies[0].transforms[1].origin)
	for slot in 11:
		check(not pool.spawn(definition, {"target_id": "test", "event_id": "cap-%d" % slot, "slot": slot + 1, "velocity": Vector3(10, 0, 0)}).is_empty(), "available impact budget spawns")
	check(pool.spawn(definition, {"target_id": "test", "event_id": "overflow", "slot": 99, "velocity": Vector3(10, 0, 0)}).is_empty(), "thirteenth impact rejected without another crew damage")
	check(pool.get_body_count() == 12, "total articulated impact cap is twelve")
	var second_pool = pool_script.new()
	root.add_child(second_pool)
	check(second_pool.spawn(definition, {"target_id": "other", "event_id": "cross-pool-overflow", "slot": 0, "velocity": Vector3(10, 0, 0)}).is_empty(), "twelve-body budget holds across vessel-owned native pools")
	second_pool.dispose()
	second_pool.free()
	pool.advance(7.0, 7.2)
	check(pool.get_body_count() == 0, "accepted lifetime releases all casualty physics")
	var release_flags: Array = []
	pool.spawn(definition, {"target_id": "test", "event_id": "recover", "slot": 1, "velocity": Vector3(10, 0, 0), "casualty": false, "release": func(recover): release_flags.append(recover)})
	pool.advance(1.25, 8.45)
	check(release_flags == [true], "nonlethal impact restores animation after 1.25 accepted seconds")
	pool.spawn(definition, {"target_id": "test", "event_id": "death", "slot": 1, "velocity": Vector3(10, 0, 0), "release": func(recover): release_flags.append(recover)})
	pool.advance(7.0, 15.45)
	check(release_flags == [true, false], "death expires without restoring standing sailor")
	pool.set_environment(func(_x, _z, _time): return 0.0)
	var submerged := _definition(Vector3(0, -5, 0))
	pool.spawn(submerged, {"target_id": "water", "event_id": "submerged", "slot": 0, "velocity": Vector3(0.4, 0, 0), "casualty": false})
	for frame in 4:
		pool.advance(1.0 / 60.0, 15.45 + (frame + 1) / 60.0)
		await physics_frame
		await process_frame
	check(pool.diagnostics().bodies[0].transforms[1].origin.y < -3.0, "spawned underwater never teleports up onto water")
	pool.advance(1.2, 16.72)
	check(pool.get_body_count() == 0, "wet lifetime releases submerged impact")
	pool.dispose()
	pool.dispose()
	check(pool.get_body_count() == 0, "native physics disposal idempotent and releases global budget")
	pool.free()
	await _test_native_deck_contact(pool_script)
	await _test_current_water_phase(pool_script)
	await _test_above_water_support(pool_script)

func _test_native_deck_contact(pool_script) -> void:
	var pool = pool_script.new()
	root.add_child(pool)
	pool.set_environment(func(_x, _z, _time): return -100.0)
	var deck_faces := PackedVector3Array([Vector3(-20, 0, -20), Vector3(-20, 0, 20), Vector3(20, 0, 20), Vector3(-20, 0, -20), Vector3(20, 0, 20), Vector3(20, 0, -20)])
	pool.register_deck("collision", deck_faces, Transform3D.IDENTITY)
	var definition := _definition(Vector3(0, 1, 0))
	pool.spawn(definition, {"target_id": "collision", "event_id": "deck-contact", "slot": 0, "velocity": Vector3(0.4, 0, 0), "casualty": true})
	for frame in 90:
		pool.advance(1.0 / 60.0, (frame + 1) / 60.0)
		await physics_frame
		await process_frame
	var transforms: Array = pool.diagnostics().bodies[0].transforms
	var minimum_y := INF
	var max_anchor_error := 0.0
	for index in 18:
		minimum_y = minf(minimum_y, transforms[index].origin.y)
		if transforms[index].origin.y < 0.0:
			print("NATIVE_DECK_PENETRATION bone=", definition.names[index], " y=", transforms[index].origin.y)
		if index > 0:
			var parent_index: int = definition.parents[index]
			var local_anchor: Vector3 = definition.transforms[parent_index].affine_inverse() * definition.transforms[index].origin
			max_anchor_error = maxf(max_anchor_error, (transforms[parent_index] * local_anchor).distance_to(transforms[index].origin))
	check(minimum_y >= -0.02, "native Jolt concave deck collision keeps ragdoll above actual deck triangles")
	check(max_anchor_error < 0.10, "native articulated pin anchors preserve bone connectivity without stretch")
	print("NATIVE_JOLT_DECK minimum_y=", minimum_y, " max_anchor_error=", max_anchor_error)
	pool.dispose()
	pool.free()

func _test_current_water_phase(pool_script) -> void:
	var pool = pool_script.new()
	root.add_child(pool)
	var phases: Array = []
	pool.set_environment(func(_x, _z, phase): phases.append(phase); return -100.0)
	pool.advance(0.0, 80.0)
	pool.spawn(_definition(Vector3(0, 5, 0)), {"target_id": "late-spawn", "event_id": "late-phase", "slot": 0, "velocity": Vector3(10, 0, 0)})
	pool.advance(1.0 / 60.0, 80.0 + 1.0 / 60.0)
	await physics_frame
	await process_frame
	await physics_frame
	await process_frame
	check(not phases.is_empty() and phases.has(80.0), "new impact previous wave phase starts at current accepted clock")
	check(not phases.has(0.0), "late-spawn ragdoll cannot query water at reset wall-clock phase")
	pool.dispose()
	pool.free()

func _test_above_water_support(pool_script) -> void:
	var pool = pool_script.new()
	root.add_child(pool)
	pool.set_environment(func(_x, _z, _time): return 0.0)
	pool.spawn(_definition(Vector3(0, 0.15, 0)), {"target_id": "above-water", "event_id": "water-crossing", "slot": 0, "velocity": Vector3(0.4, 0, 0)})
	for frame in 100:
		pool.advance(1.0 / 60.0, (frame + 1) / 60.0)
		await physics_frame
		await process_frame
	check(pool.get_body_count() == 1, "above-water falling casualty retains native body before wet expiry")
	if pool.get_body_count() == 1:
		var entry: Dictionary = pool.diagnostics().bodies[0]
		check(entry.wet > 0.0, "native fall crosses water and records accepted wet lifetime")
		var minimum_y := INF
		for frame: Transform3D in entry.transforms:
			minimum_y = minf(minimum_y, frame.origin.y)
		check(minimum_y > -1.0, "previously above-water nodes receive single-way surface support and bounded wet sinking")
		print("NATIVE_JOLT_WATER wet=", entry.wet, " minimum_y=", minimum_y)
	pool.dispose()
	pool.free()
