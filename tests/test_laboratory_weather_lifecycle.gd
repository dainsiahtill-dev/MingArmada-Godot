extends SceneTree
## Missing lifecycle control, source mutation, or direct visible reset must fail.
const Demo = preload("res://game/research/demos/weather_shadow_experiment.gd")
var assertions := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		printerr("FAIL weather lifecycle laboratory: ", message)

func authority(demo) -> PackedByteArray:
	var state: Dictionary = demo.inspection_snapshot()
	return var_to_bytes({"time": state.time, "tick": state.tick, "environment": state.environment})

func actor_positions(demo) -> Array:
	var result: Array = []
	var renderer = demo.get("_atmosphere")
	for record: Dictionary in renderer.get("_weather")[0].meshes:
		result.append(record.node.global_position)
	return result

func run() -> void:
	var demo := Demo.new()
	check(demo.configure({"cloud_lifecycle": true}).get("ok", false), "existing weather experiment accepts independent lifecycle factor")
	if failures:
		demo.free()
		finish()
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 640)
	viewport.own_world_3d = true
	root.add_child(viewport)
	viewport.add_child(demo)
	var initial: Dictionary = demo.inspection_snapshot()
	check(demo.get_default_options().cloud_lifecycle and initial.telemetry.renderer.worldCloudLifecycle.enabled, "default experiment explicitly enables production lifecycle")
	var unchanged := authority(demo)
	demo.set_paused(true)
	check(demo.set_parameter("cloud_lifecycle", false).ok, "paused baseline switch is accepted")
	check(not demo.inspection_snapshot().telemetry.renderer.worldCloudLifecycle.enabled and authority(demo) == unchanged, "baseline switch affects display strategy without consuming authority")
	check(demo.set_parameter("cloud_lifecycle", true).ok, "candidate switch restores without reset")
	var held: Dictionary = demo.inspection_snapshot()
	check(not demo.set_parameter("cloud_lifecycle", 1).ok and demo.inspection_snapshot() == held, "non-bool lifecycle factor rejects atomically")
	var lifecycle: Dictionary = held.telemetry.renderer.worldCloudLifecycle.duplicate(true)
	demo.orbit_camera(0.12, 0.08)
	demo.zoom_camera(-0.2)
	demo.advance(10.0)
	check(authority(demo) == unchanged and demo.inspection_snapshot().telemetry.renderer.worldCloudLifecycle == lifecycle, "paused camera refresh cannot move recycle or consume RNG")
	var specifications: Array = demo.control_spec()
	var lifecycle_controls: Array = specifications.filter(func(row: Dictionary): return row.id == "cloud_lifecycle")
	check(specifications.size() == 7 and lifecycle_controls.size() == 1 and lifecycle_controls[0].type == "toggle", "host exposes exactly one lifecycle bool as seventh weather control")
	check(demo.reset_experiment({"preset": "cloud_exit", "cloud_lifecycle": true, "paused": false, "camera_mode": "overview", "orbit_yaw": 0.0, "orbit_pitch": 0.0, "zoom": 1.0}).ok, "near-reset visible exit fixture builds")
	initial = demo.inspection_snapshot()
	var origin := actor_positions(demo)
	var fixed_camera: Array = initial.camera.transform
	check(initial.environment.source.weather.centers[0].x == -15980, "fixture starts twenty source units before west reset boundary")
	var camera: Camera3D = demo.get("_camera")
	for height: float in [36.0, 0.12]:
		var point := camera.unproject_position(Vector3(-1598.0, height, 0.0))
		check(point.x > 24.0 and point.x < 936.0 and point.y > 24.0 and point.y < 616.0, "fixed overview contains outgoing cloud and shadow before source reset")
	demo.advance(1.0 / 32.0)
	var candidate: Dictionary = demo.inspection_snapshot()
	var continuous := actor_positions(demo)
	check(candidate.environment.worldClouds[0].generation == 1 and candidate.environment.source.weather.centers[0].x > 0, "first accepted step actually resets authoritative source center")
	var display: Dictionary = candidate.telemetry.renderer.worldCloudLifecycle.states[0]
	check(display.retiring and display.generation == 1 and display.recycles == 0, "latest source reset is observed while original visible cloud waits for full cloud and shadow exit")
	var maximum_step := 0.0
	for index in origin.size():
		maximum_step = maxf(maximum_step, origin[index].distance_to(continuous[index]))
	check(maximum_step < 10.0 and continuous[0].x < origin[0].x, "every original cloud and shadow mesh continues west without kilometre teleport")
	check(candidate.camera.transform == fixed_camera and candidate.telemetry.world_weather_instances == 3, "observation camera and three-instance bound stay fixed")
	var candidate_authority := authority(demo)
	check(demo.reset_experiment({"cloud_lifecycle": false}).ok, "same declared fixture builds direct-reset baseline")
	demo.advance(1.0 / 32.0)
	var baseline: Dictionary = demo.inspection_snapshot()
	check(authority(demo) == candidate_authority, "A/B factor preserves complete source RNG weather sky and controllers")
	var baseline_gap: float = actor_positions(demo)[0].distance_to(continuous[0])
	check(baseline_gap > 1000.0, "baseline exposes original visible reset instead of hiding the failure fixture")
	check(baseline.resources == candidate.resources and baseline.camera == candidate.camera, "A/B uses identical resource counts fixed camera and accepted time")
	print("WEATHER_LIFECYCLE_LAB_METRICS max_mesh_step_m=", maximum_step, " baseline_gap_m=", baseline_gap)
	demo.dispose()
	viewport.free()
	finish()

func finish() -> void:
	print("LABORATORY_WEATHER_LIFECYCLE_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
