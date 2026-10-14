extends SceneTree
const DEMO_PATH := "res://game/research/demos/ocean_surface_experiment.gd"
const Waves = preload("res://modules/physics_engine/ocean/wave_field.gd")
var assertions := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL laboratory ocean: ", message)

func stable_state(demo: Node3D) -> PackedByteArray:
	var state: Dictionary = demo.inspection_snapshot()
	return var_to_bytes([state.tick, state.time, state.parameters, state.camera_transform, state.camera_projection, state.telemetry.wave_samples, state.telemetry.uniforms])

func run() -> void:
	check(FileAccess.file_exists(DEMO_PATH), "independent production-ocean experiment exists")
	if failures:
		finish()
		return
	var script: GDScript = load(DEMO_PATH)
	var demo: Node3D = script.new()
	var defaults: Dictionary = demo.get_default_options()
	check(defaults.paused == false and defaults.camera_mode == "camera_near", "explicit defaults start unpaused at fixed near camera")
	var receipt: Dictionary = demo.configure({"paused": true})
	check(receipt.ok and receipt.pending and not receipt.ready, "configure before attachment validates without claiming resources")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800, 450)
	viewport.own_world_3d = true
	root.add_child(viewport)
	viewport.add_child(demo)
	var initial: Dictionary = demo.inspection_snapshot()
	check(initial.ready and not initial.disposed and initial.topic == "ocean-surface", "ready synchronously builds isolated ocean")
	check(not demo.is_processing() and not demo.is_physics_processing(), "host is sole advance owner")
	check(initial.tick == 0 and initial.time == 0.0 and initial.fixed_step == 0.03125, "accepted clock starts at exact 32Hz origin")
	check(initial.seed == "not_applicable" and initial.rng_state == "not_applicable", "ocean does not invent RNG state")
	check(initial.camera_transform.size() == 16 and initial.camera_projection.size() == 16, "actual camera matrices are numeric 16-value arrays")
	check(initial.viewport_size == [800, 450], "snapshot records actual viewport dimensions")
	check(initial.resources.ocean == 1 and initial.resources.mirror == 1 and initial.resources.ship == 0, "local resources include production mirror without campaign ship")
	check(initial.telemetry.shader == "res://modules/scene_engine/ocean/reference_game_water.gdshader", "actual production five-wave shader retained")
	check(initial.telemetry.normal_texture == "res://assets/textures/waternormals.jpg", "production normal texture actually bound")
	check(initial.telemetry.wave_count == 5 and initial.telemetry.carrier == "production-projected-ArrayMesh", "production projected mesh and five waves retained")
	check(initial.telemetry.optics.shared_world and initial.telemetry.optics.water_layer_excluded, "mirror shares isolated World3D and excludes water")
	var specifications: Array = demo.control_spec()
	var names: Array = []
	for entry: Dictionary in specifications:
		names.append(entry.id)
		check(entry.has("label") and entry.has("value") and entry.type in ["choice", "toggle", "range"], "control uses generic schema: " + entry.id)
		if entry.type == "choice":
			check(entry.choices[0].has("value") and entry.choices[0].has("label"), "choice values have display labels")
		elif entry.type == "range":
			check(entry.min == 0.0 and entry.max == (2.0 if entry.id=="detail_strength" else 1.0) and entry.step > 0.0, "optical control has bounded numeric range: "+entry.id)
	for key: String in defaults:
		check(key == "paused" or key in names, "experiment factor has descriptor; pause belongs to host: " + key)
	var frozen := stable_state(demo)
	demo.advance(1.0)
	check(stable_state(demo) == frozen, "pause ignores host advances")
	var ocean: MeshInstance3D = demo.get("_ocean")
	var material: ShaderMaterial = ocean.material_override
	var waves: Variant = material.get_shader_parameter("wave_components")
	var geometry := ocean.mesh
	var mirror: SubViewport = ocean.get_reflection_viewport()
	check(demo.set_parameter("optics_mode", "legacy").ok and material.get_shader_parameter("water_legacy_optics") == true, "same-time legacy comparison reaches actual material")
	check(demo.set_parameter("reflection_enabled", false).ok and material.get_shader_parameter("u_use_reflection") == false, "reflection control disables actual reflection sampling")
	check(mirror.render_target_update_mode == SubViewport.UPDATE_DISABLED, "reflection control suspends actual mirror render target")
	check(demo.set_parameter("refraction_enabled", false).ok and material.get_shader_parameter("u_refraction_enabled") == false, "refraction control reaches production depth branch")
	check(demo.set_parameter("detail_strength", 0.0).ok and material.get_shader_parameter("u_strength") == 0.0, "zero detail suppresses production normal slopes")
	check(demo.set_parameter("detail_strength", 2.0).ok and material.get_shader_parameter("u_strength") == 2.0, "detail upper bound consumes actual source strength")
	check(material.get_shader_parameter("wave_components") == waves and ocean.mesh == geometry and ocean.get_reflection_viewport() == mirror, "optical controls preserve five-wave descriptor, grid and mirror owner")
	check(demo.inspection_snapshot().tick == 0 and material.get_shader_parameter("simulation_time") == 0.0 and material.get_shader_parameter("u_time") == 0.0, "paused optical changes retain accepted time in both shader clocks")
	for bad: Array in [["detail_strength", -0.1], ["detail_strength", NAN], ["detail_strength", "high"], ["reflection_enabled", 1], ["optics_mode", "unknown"], ["camera_mode", "unknown"], ["unknown", true]]:
		var before := stable_state(demo)
		var rejected: Dictionary = demo.set_parameter(bad[0], bad[1])
		check(not rejected.ok and stable_state(demo) == before, "invalid update atomic: " + str(bad))
	check(not demo.configure({"detail_strength": INF}).ok and demo.inspection_snapshot().ready, "invalid live configuration keeps previous ready resources")
	for mode: String in ["camera_near", "camera_mid", "camera_horizon"]:
		demo.set_camera_mode(mode)
		var camera_state: Dictionary = demo.inspection_snapshot()
		check(camera_state.parameters.camera_mode == mode and camera_state.camera_transform.size() == 16 and camera_state.time == 0.0, "fixed camera changes observer only: " + mode)
	var camera_before: Array = demo.inspection_snapshot().camera_transform
	demo.orbit_camera(0.2, 0.1)
	demo.zoom_camera(0.25)
	check(demo.inspection_snapshot().camera_transform != camera_before and demo.inspection_snapshot().time == 0.0, "orbit and zoom change actual camera while paused")
	check(demo.inspection_snapshot().telemetry.optics.accepted_time == 0.0, "camera-only refresh synchronizes production mirror at same time")
	check(demo.reset_experiment(defaults).ok, "reset reconstructs full initial state")
	var reset_initial := stable_state(demo)
	for index in 16:
		demo.advance(0.03125)
	var advanced: Dictionary = demo.inspection_snapshot()
	check(advanced.tick == 16 and advanced.time == 0.5, "fixed-step accepts exact requested ticks")
	var model := Waves.new()
	check(absf(advanced.telemetry.wave_samples[1] - model.sample_height(25.0, -12.0, 0.5)) < 0.000002, "inspection samples real production wave field at accepted time")
	check(advanced.telemetry.uniforms.simulation_time == 0.5 and advanced.telemetry.uniforms.u_time == 0.5, "GPU material clocks agree with accepted clock")
	var replay := stable_state(demo)
	demo.reset_experiment(defaults)
	check(stable_state(demo) == reset_initial, "reset reproduces complete initial observer and uniforms")
	for index in 16:
		demo.advance(0.03125)
	check(stable_state(demo) == replay, "fixed command replay deterministic")
	demo.set_paused(true)
	var paused_tick: int = demo.inspection_snapshot().tick
	demo.set_parameter("optics_mode", "legacy")
	demo.orbit_camera(-0.1, 0.0)
	demo.advance(0.25)
	check(demo.inspection_snapshot().tick == paused_tick and demo.inspection_snapshot().time == 0.5, "late paused comparison preserves accepted history")
	demo.reset_experiment(defaults)
	demo.advance(1000.0)
	check(demo.inspection_snapshot().tick == 8, "foreground stalls cap catch-up at eight ticks")
	demo.advance(NAN)
	demo.advance(-1.0)
	check(demo.inspection_snapshot().tick == 8, "invalid host deltas never advance")
	var active_mirror: SubViewport = demo.get("_ocean").get_reflection_viewport()
	var mirror_id := active_mirror.get_instance_id()
	demo.dispose()
	demo.dispose()
	var disposed: Dictionary = demo.inspection_snapshot()
	check(disposed.disposed and not disposed.ready and disposed.resources.world == 0 and disposed.resources.mirror == 0 and demo.get_child_count() == 0, "idempotent dispose releases experiment resources")
	check(not is_instance_id_valid(mirror_id), "production mirror target actually freed")
	demo.advance(1.0)
	check(demo.inspection_snapshot().tick == disposed.tick, "disposed experiment ignores advances")
	check(demo.configure(defaults).ok and demo.inspection_snapshot().ready, "explicit configuration revives disposed experiment")
	viewport.free()
	finish()

func finish() -> void:
	print("LABORATORY_OCEAN_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
