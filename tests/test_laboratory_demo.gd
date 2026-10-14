extends SceneTree
## Real experiment owners: reset determinism, accepted-clock pause and local A/B.
var assertions := 0
var failures := 0
var _demo_script: Script

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

func fixture(options: Dictionary = {}) -> Array:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 640)
	viewport.own_world_3d = true
	root.add_child(viewport)
	var demo: Node3D = _demo_script.new()
	var receipt: Dictionary = demo.configure(options)
	check(receipt.get("ok", false) and receipt.get("pending", false), "configuration before tree attachment stores validated options")
	check(demo.get_child_count() == 0, "pre-tree configure allocates no scene owners")
	viewport.add_child(demo)
	check(demo.inspection_snapshot().get("ready", false), "ready builds configured experiment synchronously")
	return [demo, viewport]

func release(pair: Array) -> void:
	pair[0].dispose()
	pair[1].free()

func deterministic_state(demo: Node3D) -> PackedByteArray:
	var state: Dictionary = demo.inspection_snapshot()
	return var_to_bytes({"tick": state.tick, "time": state.time, "ship": state.ship, "native_ship": state.native_ship, "tail": state.tail, "contact": state.contact, "crew": state.crew})

func run() -> void:
	var path := "res://game/research/demos/hull_contact_experiment.gd"
	check(ResourceLoader.exists(path), "registered hull-contact experiment exists")
	if failures:
		finish()
		return
	_demo_script = load(path)
	var invalid: Node3D = _demo_script.new()
	check(not invalid.configure({"kind": "unsupported"}).get("ok", true), "unknown hull rejects before scene allocation")
	check(not invalid.configure({"scenario": "unsupported"}).get("ok", true), "unknown scenario rejects")
	check(not invalid.configure({"camera_mode": "unsupported"}).get("ok", true), "unknown camera rejects")
	check(not invalid.configure({"orbit_yaw": NAN}).get("ok", true), "nonfinite replay orbit rejects before allocation")
	check(not invalid.configure({"zoom": 0.0}).get("ok", true), "zero replay zoom rejects before allocation")
	check(not invalid.configure({"quality": "unsupported"}).get("ok", true), "unsupported replay surface quality rejects")
	check(not invalid.configure({"carrier_extent": NAN}).get("ok", true), "nonfinite carrier extent rejects before allocation")
	check(not invalid.configure({"carrier_extent": 256.0}).get("ok", true), "unregistered carrier extent rejects before allocation")
	check(invalid.get_child_count() == 0, "invalid configuration has no resource owners")
	invalid.free()
	var pair := fixture({"kind": "fuchuan", "scenario": "cruise", "camera_mode": "side"})
	var demo: Node3D = pair[0]
	var initial: Dictionary = demo.inspection_snapshot()
	check(initial.time == 0.0 and initial.tick == 0, "reset initial accepted time is zero")
	check(initial.native_owner == "SailingRuntime" and initial.resources.runtime == 1, "one real native sailing runtime owns physics")
	check(initial.crew.visible > 0, "real three-dimensional sailors retained")
	check(initial.scope.contains("1200") and initial.scope.contains("production"), "uniform carrier scope states production material reuse")
	check(initial.get("carrier_extent", 0.0) == 1200.0 and absf(float(initial.get("carrier_spacing_m", 0.0)) - 1200.0 / 513.0) < 0.000001, "default carrier receipt retains original 1200m experiment geometry")
	check(not demo.is_processing() and not demo.is_physics_processing(), "host alone advances experiment")
	demo.advance(1.0 / 64.0)
	check(demo.inspection_snapshot().tick == 0, "sub-step delta cannot advance a source call")
	demo.advance(1.0 / 64.0)
	check(demo.inspection_snapshot().tick == 1 and demo.inspection_snapshot().time > 0.0, "two half-deltas consume one 32Hz source call")
	check(demo.reset_experiment().ok, "same experiment resets")
	for _tick in 32:
		demo.advance(1.0 / 32.0)
	var replay := deterministic_state(demo)
	var active: Dictionary = demo.inspection_snapshot()
	check(active.tick == 32 and absf(active.time - 1.0) < 0.000001, "32 fixed source calls accept one native second")
	demo.set_paused(true)
	var frozen := deterministic_state(demo)
	demo.advance(0.2)
	for _frame in 2:
		await process_frame
	check(deterministic_state(demo) == frozen, "pause freezes physics, ocean, crew, tail and contact")
	var before: Dictionary = demo.inspection_snapshot()
	demo.set_contact_enabled(false)
	var disabled: Dictionary = demo.inspection_snapshot()
	check(disabled.time == before.time and disabled.ship == before.ship and disabled.tail == before.tail, "A/B disable preserves same pose, time and exact tail receipt")
	check(disabled.contact == before.contact and disabled.native_runtime_id == before.native_runtime_id, "A/B retains contact evolution and native runtime owner")
	check(not disabled.contact_visible and disabled.tail_visible, "only local contact container is hidden")
	demo.set_contact_enabled(true)
	check(demo.inspection_snapshot().contact_visible, "A/B restores current contact container without reinitializing")
	demo.set_camera_mode("front")
	demo.orbit_camera(0.15, 0.1)
	demo.zoom_camera(-0.2)
	var camera_changed: Dictionary = demo.inspection_snapshot()
	check(camera_changed.camera_mode == "front" and camera_changed.ship == before.ship and camera_changed.tail == before.tail and camera_changed.time == before.time and camera_changed.contact.flow_distance == before.contact.flow_distance and camera_changed.contact.target_births == before.contact.target_births and camera_changed.contact.visual_time == before.contact.visual_time, "paused camera redraw preserves physics, tail, contact flow and births")
	var camera_transform: Array = camera_changed.get("camera_transform", [])
	var camera_projection: Array = camera_changed.get("camera_projection", [])
	check(camera_transform.size() == 16 and camera_projection.size() == 16, "replay receipt exposes numeric actual camera transform and projection matrices")
	if camera_transform.size() == 16:
		var point: Vector3 = camera_changed.camera_position
		check(absf(float(camera_transform[12]) - point.x) < 0.00001 and absf(float(camera_transform[13]) - point.y) < 0.00001 and absf(float(camera_transform[14]) - point.z) < 0.00001 and camera_transform[15] == 1.0, "camera matrix records actual world-space eye in column-major affine layout")
	var parameters: Dictionary = camera_changed.get("camera_parameters", {})
	check(parameters.get("fov", 0.0) == 45.0 and absf(float(parameters.get("near", 0.0)) - 0.1) < 0.000001 and parameters.get("far", 0.0) == 3000.0 and camera_changed.get("viewport_size", []) == [960, 640] and camera_changed.get("quality", "") == "balanced", "replay receipt records actual projection parameters, viewport and surface quality")
	check(absf(float(camera_changed.get("orbit_yaw", -1.0)) - 0.15) < 0.00001 and absf(float(camera_changed.get("orbit_pitch", -1.0)) - 0.1) < 0.00001 and absf(float(camera_changed.get("zoom", 0.0)) - exp(-0.2)) < 0.00001, "receipt captures nondefault orbit and zoom")
	var real_rng: RandomNumberGenerator = demo.get("_renderer")._actors.player.froth.get("_rng")
	check(camera_changed.get("waterpacket_seed") is int and camera_changed.get("waterpacket_seed") == real_rng.seed and camera_changed.get("froth_rng_state") is int and camera_changed.get("froth_rng_state") == real_rng.state, "replay receipt records concrete packet seed and current production froth RNG state")
	check(camera_changed.get("froth_rng_state") == before.get("froth_rng_state") and camera_changed.native_runtime_id == before.native_runtime_id, "paused inspection and camera redraw cannot change RNG or native owner")
	print("LABORATORY_REPLAY_METADATA ", JSON.stringify({"waterpacket_seed": camera_changed.get("waterpacket_seed"), "froth_rng_state": camera_changed.get("froth_rng_state"), "froth_rng_state_decimal": camera_changed.get("froth_rng_state_decimal"), "camera_parameters": parameters, "viewport_size": camera_changed.get("viewport_size"), "quality": camera_changed.get("quality")}))
	var mirror: Camera3D = demo.get_node("ExperimentWorld/Ocean").get_reflection_camera()
	var eye: Vector3 = camera_changed.camera_position
	check(mirror.global_position.distance_to(Vector3(eye.x, -eye.y, eye.z)) < 0.00001, "paused camera changes refresh production planar reflection at same accepted time")
	demo.set_camera_mode("high")
	check(demo.inspection_snapshot().camera_position.y > before.camera_position.y, "high preset observes contact from above")
	var restore_options := {"kind": "fuchuan", "scenario": "cruise", "camera_mode": "front", "orbit_yaw": 0.15, "orbit_pitch": 0.1, "zoom": exp(-0.2), "quality": "balanced", "paused": false}
	check(demo.reset_experiment(restore_options).ok, "reset accepts concrete nondefault camera replay inputs")
	for _tick in 32:
		demo.advance(1.0 / 32.0)
	demo.set_paused(true)
	var restored: Dictionary = demo.inspection_snapshot()
	check(restored.get("camera_transform", []) == camera_transform and restored.get("camera_projection", []) == camera_projection and restored.native_ship == camera_changed.native_ship and restored.get("waterpacket_seed") == camera_changed.get("waterpacket_seed") and restored.get("froth_rng_state") == camera_changed.get("froth_rng_state"), "reset and fixed ticks reproduce saved orbit view, native pose, seed and RNG state")
	var high_quality := fixture({"quality": "high", "orbit_yaw": 0.2, "orbit_pitch": 0.3, "zoom": 1.4})
	var configured_camera: Dictionary = high_quality[0].inspection_snapshot()
	check(configured_camera.get("quality", "") == "high" and absf(float(configured_camera.get("orbit_yaw", -1.0)) - 0.2) < 0.00001 and absf(float(configured_camera.get("zoom", 0.0)) - 1.4) < 0.00001, "pre-tree configure restores camera replay inputs and actual requested quality")
	release(high_quality)
	check(demo.reset_experiment({"paused": false, "camera_mode": "side", "orbit_yaw": 0.0, "orbit_pitch": 0.0, "zoom": 1.0}).ok, "reset clears paused native owner")
	for _tick in 32:
		demo.advance(1.0 / 32.0)
	check(deterministic_state(demo) == replay, "fresh reset reproduces real pose, contact, crew and tail")
	var local_pair := fixture({"kind": "fuchuan", "scenario": "cruise", "camera_mode": "side", "carrier_extent": 384.0})
	var local_demo: Node3D = local_pair[0]
	for _tick in 32:
		local_demo.advance(1.0 / 32.0)
	var local_state: Dictionary = local_demo.inspection_snapshot()
	var local_mesh: PlaneMesh = local_demo.get_node("ExperimentWorld/Ocean").mesh
	check(local_mesh.size == Vector2(384.0, 384.0) and local_mesh.subdivide_width == 512 and local_mesh.subdivide_depth == 512 and local_state.get("carrier_extent", 0.0) == 384.0 and absf(float(local_state.get("carrier_spacing_m", 0.0)) - 384.0 / 513.0) < 0.000001, "controlled local carrier changes actual dimensions and spacing with same subdivisions")
	check(local_state.scope.contains("384") and local_state.scope.contains("192") and local_state.scope.contains("experimental"), "local carrier explicitly limits experimental coverage to plus-minus 192m")
	check(deterministic_state(local_demo) == replay and local_state.froth_rng_state == demo.inspection_snapshot().froth_rng_state, "same 32 native ticks on different carriers preserve exact pose, tail, contact evolution and RNG")
	check(local_demo.reset_experiment({"carrier_extent": 1200.0}).ok and local_demo.inspection_snapshot().get("carrier_extent", 0.0) == 1200.0, "reset switches registered carrier under the same initial conditions")
	release(local_pair)
	var oracle_pair := fixture({"kind": "fuchuan", "scenario": "cruise", "camera_mode": "side"})
	var oracle: Node3D = oracle_pair[0]
	for _tick in 33:
		oracle.advance(1.0 / 32.0)
	demo.set_contact_enabled(false)
	demo.advance(1.0 / 32.0)
	check(deterministic_state(demo) == deterministic_state(oracle), "disabled contact keeps exact active native pose, tail history and contact evolution")
	check(not demo.inspection_snapshot().contact_visible and demo.inspection_snapshot().tail_visible, "advance cannot restore hidden contact or hide source tail")
	demo.set_contact_enabled(true)
	check(deterministic_state(demo) == deterministic_state(oracle), "reenabling contact retains continuously advanced comparison state")
	release(oracle_pair)
	demo.advance(50.0)
	check(demo.inspection_snapshot().tick == 41, "large frame catches up at most eight 32Hz calls")
	var bounded: Dictionary = demo.inspection_snapshot()
	demo.advance(NAN)
	demo.advance(-1.0)
	check(demo.inspection_snapshot().tick == bounded.tick, "invalid deltas cannot advance time")
	var old_runtime_id: int = bounded.native_runtime_id
	check(demo.configure({"kind": "merchant", "scenario": "slow", "camera_mode": "high"}).ok, "live configure replaces experiment")
	var replaced: Dictionary = demo.inspection_snapshot()
	check(replaced.kind == "merchant" and replaced.scenario == "slow" and replaced.tick == 0, "live configure resets requested hull and scenario")
	check(replaced.native_runtime_id != old_runtime_id and replaced.resources.world == 1 and demo.get_child_count() == 1, "reconfigure leaves one world and fresh native owner")
	var rejected_time: float = replaced.time
	check(not demo.configure({"kind": "invalid"}).ok and demo.inspection_snapshot().time == rejected_time and demo.inspection_snapshot().ready, "bad live configuration preserves working experiment")
	for kind: String in ["fuchuan", "fisherman", "merchant", "voc", "patrol", "heavy"]:
		check(demo.reset_experiment({"kind": kind, "scenario": "cruise"}).ok, kind + " real hull configures")
		demo.advance(0.03125)
		var state: Dictionary = demo.inspection_snapshot()
		check(state.kind == kind and state.crew.visible > 0 and state.resources.wake == 1, kind + " retains crew and sole production wake owner")
	for scenario: String in ["cruise", "slow", "turn", "stop", "reentry"]:
		check(demo.reset_experiment({"kind": "fuchuan", "scenario": scenario}).ok, scenario + " reproducible scenario configures")
		for _tick in 136:
			demo.advance(0.03125)
		var state: Dictionary = demo.inspection_snapshot()
		if scenario == "turn":
			check(state.native_ship.rudder == 0.45, "turn sends native rudder after four seconds")
		elif scenario == "stop":
			check(state.native_ship.sailDeployment == 0.0, "stop sends native furl command after four seconds")
		elif scenario == "reentry":
			check(state.diagnostic_overlay_m > 0.0 and state.ship.position.y > state.native_ship.position.y, "reentry lift is explicit presentation stress overlay")
		else:
			check(state.diagnostic_overlay_m == 0.0 and state.ship.position.y == state.native_ship.position.y, scenario + " uses native hull vertical pose")
	demo.dispose()
	demo.dispose()
	var disposed: Dictionary = demo.inspection_snapshot()
	check(disposed.disposed and not disposed.ready and disposed.resources.runtime == 0 and disposed.resources.world == 0 and demo.get_child_count() == 0, "idempotent disposal releases every local owner")
	demo.advance(1.0)
	check(demo.inspection_snapshot().tick == disposed.tick, "disposed experiment cannot advance")
	check(demo.configure({"kind": "patrol"}).ok and demo.inspection_snapshot().ready, "disposed node can be explicitly configured again")
	release(pair)
	finish()

func finish() -> void:
	print("LABORATORY_DEMO_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
