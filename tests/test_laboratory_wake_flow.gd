extends SceneTree
var assertions := 0
var failures := 0
func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL wake flow lab: ", detail)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var path := "res://game/research/demos/wake_flow_experiment.gd"
	check(ResourceLoader.exists(path), "independent wake flow experiment exists")
	if failures: finish(); return
	var demo = load(path).new()
	check(not demo.configure({"flow_enabled": 1}).ok, "nonboolean flow factor rejected")
	check(demo.configure({}).ok and demo.get_child_count() == 0, "pre-tree configuration owns no scene resources")
	var viewport := SubViewport.new(); viewport.size = Vector2i(960,640); viewport.own_world_3d = true
	root.add_child(viewport); viewport.add_child(demo)
	var initial: Dictionary = demo.inspection_snapshot()
	check(initial.ready and initial.topic == "wake-flow" and not initial.parameters.flow_enabled, "default is unchanged baseline flow")
	check(initial.native_owner == "SailingRuntime" and initial.crew.visible > 0, "real native runtime and 3D sailors remain")
	var packet: Dictionary = demo.get("_last_packet")
	var trail: Dictionary = packet.ships[0].sourceWake.targetTrail
	var attachment: Dictionary = demo.get("_ship").source_water_attachment()
	check(attachment.has("flowStern") and trail.position == attachment.flowStern and trail.position.y == 0.0, "actual yaw-only waterline stern used instead of inboard Dummy_Wake")
	var native: Dictionary = initial.native_ship
	var expected_forward := Vector3(cos(float(native.heading)),0,sin(float(native.heading)))
	check(trail.forward.is_equal_approx(expected_forward), "forward derives from native heading")
	check(is_equal_approx(trail.speed, Vector2(native.velocity.x,native.velocity.z).length()), "speed derives from actual velocity")
	check(is_equal_approx(trail.beam, attachment.surfaceProfile.beam * attachment.surfaceProfile.hullToWorld.basis.x.length()), "local profile beam converted to world metres")
	check(trail.length == native.dimensions.length and trail.hullAlive, "native length and living experiment vessel reported")
	for camera in ["side", "high", "front"]:
		demo.set_camera_mode(camera)
		var observer: Camera3D = demo.get("_camera")
		var focus: Vector3 = attachment.flowStern - expected_forward * trail.length * 0.45
		focus.y = demo.get("_runtime").sample_water_height(focus.x,focus.z,initial.time)
		check((-observer.global_basis.z).angle_to((focus-observer.global_position).normalized()) < 0.00001, camera+" aims relative to actual stern in both baseline and candidate")
		for point: Vector3 in [trail.position, trail.position - trail.forward * trail.length * 2.0]:
			var pixel := observer.unproject_position(point)
			check(not observer.is_position_behind(point) and pixel.x >= 8 and pixel.x <= 952 and pixel.y >= 8 and pixel.y <= 632, camera + " frames stern and at least two ship lengths behind")
		var vessel_fits := true
		for mesh_node: Node in demo.get("_ship").get_model().find_children("*","MeshInstance3D",true,false):
			if not mesh_node.is_visible_in_tree(): continue
			var box: AABB = mesh_node.get_aabb()
			for corner in 8:
				var world_point: Vector3 = mesh_node.global_transform * box.get_endpoint(corner)
				var pixel := observer.unproject_position(world_point)
				vessel_fits = vessel_fits and not observer.is_position_behind(world_point) and pixel.x >= 0 and pixel.x <= 960 and pixel.y >= 0 and pixel.y <= 640
		check(vessel_fits,camera+" keeps the actual model including mast and bowsprit in frame")
	demo.set_paused(true)
	var frozen: Dictionary = demo.inspection_snapshot()
	demo.advance(1.0)
	check(demo.inspection_snapshot().time == frozen.time and demo.inspection_snapshot().native_ship == frozen.native_ship, "pause preserves native timeline")
	var request: Dictionary = demo.set_parameter("flow_enabled", true)
	check(request.ok and request.reset_required and not demo.inspection_snapshot().parameters.flow_enabled, "factor requests clean reset without mutating current history")
	check(demo.reset_experiment({"flow_enabled": true,"paused":false,"camera_mode":"side"}).ok, "candidate reset rebuilds same initial state")
	check(demo.inspection_snapshot().native_ship == initial.native_ship, "candidate changes no initial native state")
	demo.advance(1.0/32.0)
	var advanced: Dictionary = demo.inspection_snapshot()
	check(advanced.time > 0 and advanced.tick == 1 and advanced.target_trail.enabled, "single step submits actual accepted time and candidate packet")
	check(advanced.has("flow") and advanced.has("renderer"), "candidate public diagnostics are observable")
	for scenario in ["slow", "turn", "stop", "reentry"]:
		check(demo.set_parameter("scenario",scenario).reset_required, "scenario changes use reset contract: " + scenario)
		check(demo.reset_experiment({"scenario":scenario,"flow_enabled":false}).ok, "existing real scenario configures: " + scenario)
		demo.advance(1.0/32.0)
		check(demo.inspection_snapshot().scenario == scenario and demo.inspection_snapshot().time > 0, "scenario consumes native time: " + scenario)
	demo.dispose()
	check(not demo.inspection_snapshot().ready and demo.get_child_count() == 0, "dispose releases owned runtime/world/renderers")
	viewport.free(); finish()
func finish() -> void:
	print("LABORATORY_WAKE_FLOW_PASS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
