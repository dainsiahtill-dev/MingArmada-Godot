extends SceneTree
## Missing clock gates, shared actor visibility, partial validation and leaked
## atmosphere owners must break these real-component contract tests.
var assertions := 0
var failures := 0
var _script: Script

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		printerr("FAIL weather laboratory: ", message)

func fixture(options: Dictionary = {}) -> Array:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 640)
	viewport.own_world_3d = true
	root.add_child(viewport)
	var demo: Node3D = _script.new()
	var receipt: Dictionary = demo.configure(options)
	check(receipt.get("ok", false) and receipt.get("pending", false), "configure before tree validates without allocating owners")
	check(demo.get_child_count() == 0, "pre-tree configuration has no scene resources")
	viewport.add_child(demo)
	check(demo.inspection_snapshot().ready, "ready synchronously builds isolated production atmosphere")
	return [demo, viewport]

func authority(demo: Node3D) -> PackedByteArray:
	var state: Dictionary = demo.inspection_snapshot()
	return var_to_bytes({"time": state.time, "tick": state.tick, "environment": state.environment})

func release(pair: Array) -> void:
	pair[0].dispose()
	pair[1].free()

func run() -> void:
	var path := "res://game/research/demos/weather_shadow_experiment.gd"
	check(FileAccess.file_exists(path), "isolated weather experiment exists")
	if not FileAccess.file_exists(path):
		finish()
		return
	_script = load(path)
	if _script == null:
		check(false, "experiment loads")
		finish()
		return
	var pair := fixture()
	var demo: Node3D = pair[0]
	var origin := authority(demo)
	var initial: Dictionary = demo.inspection_snapshot()
	check(initial.topic == "weather-shadow" and initial.tick == 0 and initial.time == 0.0, "fresh clock starts at exact accepted zero")
	check(initial.resources.weather == 1 and initial.resources.atmosphere == 1 and initial.resources.world == 1, "weather authority and render owner stay distinct")
	check(initial.telemetry.world_weather_instances == 3 and initial.telemetry.sky_clones > 20 and initial.telemetry.shadow_meshes == 5, "production ring and storm plus two cloud00 resources are present")
	check(initial.rng.weather.state_decimal == "1" and initial.rng.weather.seed_decimal == "1" and initial.rng.sky.seed_decimal == "1", "actual uint32 seeds and weather state export without loss")
	check(initial.camera.transform.size() == 16 and initial.camera.projection.size() == 16 and initial.viewport == [960, 640], "capture records actual camera matrices and viewport")
	check(not demo.is_processing() and not demo.is_physics_processing(), "host is sole accepted-clock owner")
	demo.advance(1.0 / 64.0)
	check(demo.inspection_snapshot().tick == 0, "fractional step cannot consume a native call")
	demo.advance(1.0 / 64.0)
	var first: Dictionary = demo.inspection_snapshot()
	check(first.tick == 1 and first.time == 0.03125 and first.environment.sourceCallIndex == 1, "two fractional steps admit exactly one source call")
	check(first.environment.source.rngState == 2745024 and first.environment.source.rngDraws == 1, "first source CRT draw has hand checked state and count")
	check(first.environment.source.weather.windVelocity == 3 and first.environment.source.weather.centers[0].x == 7970, "first weather call keeps original integer wind and center rules")
	check(first.environment.sky.ring.updates == 0, "first 32Hz step remains below strict cloud threshold")
	demo.advance(0.03125)
	var second: Dictionary = demo.inspection_snapshot()
	check(second.environment.sky.ring.updates == 1 and second.environment.sky.ring.nodes[0].rotation != initial.environment.sky.ring.nodes[0].rotation, "second source delta rotates sky ring independently")
	check(second.environment.worldClouds[0].worldPosition != initial.environment.worldClouds[0].worldPosition and second.environment.worldClouds[1].worldPosition != initial.environment.worldClouds[1].worldPosition, "multiple world weather centers move independently of sky ring")
	var before_pause := authority(demo)
	demo.set_paused(true)
	demo.advance(20.0)
	check(authority(demo) == before_pause, "pause preserves accepted calls RNG and controller history")
	var old_camera: Array = demo.inspection_snapshot().camera.transform
	demo.set_camera_mode("ground")
	demo.orbit_camera(0.12, 0.08)
	demo.zoom_camera(-0.2)
	check(demo.inspection_snapshot().camera.transform != old_camera and authority(demo) == before_pause, "paused camera changes refresh presentation without simulation")
	check(demo.set_parameter("shadows_enabled", false).ok, "shadow factor changes at accepted time")
	var without_shadow: Dictionary = demo.inspection_snapshot()
	check(without_shadow.telemetry.visible_shadow_meshes == 0 and without_shadow.telemetry.visible_world_cloud_meshes > 0 and without_shadow.telemetry.visible_sky_meshes > 0, "shadow gate affects only baked shadow records")
	check(authority(demo) == before_pause, "shadow comparison leaves weather RNG and sky authority identical")
	check(demo.set_parameter("shadows_enabled", true).ok, "shadow gate restores")
	check(demo.set_parameter("clouds_enabled", false).ok, "world cloud factor changes")
	var without_cloud: Dictionary = demo.inspection_snapshot()
	check(without_cloud.telemetry.visible_world_cloud_meshes == 0 and without_cloud.telemetry.visible_shadow_meshes > 0 and without_cloud.telemetry.visible_sky_meshes > 0, "world cloud gate preserves sky and baked shadows")
	check(demo.set_parameter("sky_enabled", false).ok, "sky ring factor changes")
	check(demo.inspection_snapshot().telemetry.visible_sky_meshes == 0 and authority(demo) == before_pause, "sky gate never consumes cloud or weather updates")
	check(demo.set_parameter("clouds_enabled", true).ok and demo.set_parameter("sky_enabled", true).ok, "independent factors restore at same accepted state")
	var stable: Dictionary = demo.inspection_snapshot()
	for input: Array in [["shadows_enabled", 1], ["sky_enabled", "false"], ["clouds_enabled", null], ["camera_mode", "unknown"], ["preset", "rain"], ["unknown", true]]:
		check(not demo.set_parameter(input[0], input[1]).ok and demo.inspection_snapshot() == stable, "invalid factor is rejected atomically: " + input[0])
	var requested: Dictionary = demo.set_parameter("preset", "storm")
	check(requested.ok and requested.reset_required and demo.inspection_snapshot() == stable, "changing initial-state preset explicitly requires reset")
	for invalid: Dictionary in [{"crt_seed": -1}, {"sky_crt_seed": 4294967296}, {"paused": 1}, {"zoom": NAN}, {"preset": 4}, {"unrecognized": true}]:
		check(not demo.configure(invalid).ok and demo.inspection_snapshot() == stable, "invalid configure does not release or partially mutate existing owners")
	check(demo.reset_experiment(demo.get_default_options()).ok and authority(demo) == origin, "reset restores exact initial packet and RNG")
	for _index in 64:
		demo.advance(0.03125)
	var forward := authority(demo)
	check(demo.inspection_snapshot().environment.sourceCallIndex == 64 and demo.inspection_snapshot().time == 2.0, "fixed 64 calls record two accepted seconds")
	check(demo.reset_experiment().ok, "same options reset accepted experiment")
	for _index in 64:
		demo.advance(0.03125)
	check(authority(demo) == forward, "replaying reset fixed sequence matches weather ring and controller state")
	check(demo.reset_experiment().ok, "bound fixture resets")
	demo.advance(10.0)
	check(demo.inspection_snapshot().tick == 8 and demo.inspection_snapshot().time == 0.25, "foreground stall catchup has eight-call upper bound")
	demo.advance(0.03125)
	check(demo.inspection_snapshot().tick == 9, "dropped wall time never becomes future backlog")
	var before_invalid := authority(demo)
	for delta: float in [0.0, -0.1, NAN, INF]:
		demo.advance(delta)
	check(authority(demo) == before_invalid, "invalid advance cannot consume state")
	for preset: String in ["clear", "storm", "sunset"]:
		check(demo.reset_experiment({"preset": preset}).ok, "declared initial-state preset builds: " + preset)
		var state: Dictionary = demo.inspection_snapshot()
		check(state.tick == 0 and state.parameters.preset == preset and state.telemetry.world_weather_instances == 3, "preset preserves native three-actor ownership: " + preset)
		if preset == "sunset":
			check(state.environment.source.weather.lightTime == 1930, "sunset uses authored late-day light-time scope")
		elif preset == "storm":
			check(state.environment.source.weather.centers[0].x == 2000 and state.environment.source.weather.lightTime == 1200, "storm is explicit near-center placement not invented day-mode enum")
	var specifications: Array = demo.control_spec()
	check(specifications.size() == 5, "host receives five independent weather controls")
	for specification: Dictionary in specifications:
		check(specification.has_all(["id", "label", "type", "value"]), "control schema is complete: " + specification.id)
	var held_weather: RefCounted = demo.get("_weather")
	var held_atmosphere: RefCounted = demo.get("_atmosphere")
	var weak_weather: WeakRef = weakref(held_weather)
	held_weather = null
	demo.dispose()
	demo.dispose()
	var disposed: Dictionary = demo.inspection_snapshot()
	check(disposed.disposed and not disposed.ready and demo.get_child_count() == 0, "disposal is idempotent and frees arena scene")
	check(disposed.resources.weather == 0 and disposed.resources.atmosphere == 0 and disposed.resources.meshes == 0 and disposed.resources.textures == 0, "all tracked owners and textures release")
	check(weak_weather.get_ref() == null and held_atmosphere.get("_textures").is_empty() and held_atmosphere.get("_weather").is_empty(), "native history reference and renderer cache resources release")
	held_atmosphere = null
	demo.advance(1.0)
	check(demo.inspection_snapshot().tick == disposed.tick, "disposed experiment cannot advance")
	check(demo.configure({"preset": "clear"}).ok and demo.inspection_snapshot().ready, "explicit configure can reuse disposed node")
	release(pair)
	finish()

func finish() -> void:
	print("LABORATORY_WEATHER_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
