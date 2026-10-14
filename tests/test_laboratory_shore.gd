extends SceneTree
## Real coast fixture: clock, source samples, independent factors and lifetime.
var assertions := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		printerr("FAIL laboratory shore: ", message)

func native_state(demo: Node3D) -> PackedByteArray:
	var state: Dictionary = demo.inspection_snapshot()
	return var_to_bytes({"tick":state.tick,"time":state.time,"source":state.telemetry.source,"terrain":state.telemetry.terrain_fingerprint,"seed":state.telemetry.source_seed_decimal})

func run() -> void:
	var path := "res://game/research/demos/shore_surf_experiment.gd"
	check(ResourceLoader.exists(path), "independent real-coast experiment exists")
	if failures:
		finish()
		return
	var script: Script = load(path)
	var demo: Node3D = script.new()
	var defaults: Dictionary = demo.get_default_options()
	check(defaults.paused == false and defaults.camera_mode == "close", "unpaused close-view default is explicit")
	check(defaults.get("shore_edge_feather_m",-1.0) == 0.6, "wider feather defaults to0.6vertical meters")
	check(defaults.get("shore_edge_water_weight",-1.0) == 0.55, "nearshore water coverage defaults to0.55candidate")
	check(not demo.configure({"shore_edge_water_weight":NAN}).ok and not demo.configure({"shore_edge_water_weight":1.01}).ok and not demo.configure({"shore_edge_water_weight":false}).ok, "water coverage invalid values reject before allocation")
	check(not demo.configure({"shore_edge_feather_m":NAN}).ok and not demo.configure({"shore_edge_feather_m":0.61}).ok, "nonfinite/out-of-domain feather rejects before allocation")
	check(not demo.configure({"source_opacity":NAN}).ok, "nonfinite opacity rejects before resource allocation")
	check(not demo.configure({"analytic_opacity":-0.1}).ok, "out-of-domain opacity rejects")
	check(not demo.configure({"source_enabled":1}).ok, "factor toggle requires bool")
	check(not demo.configure({"camera_mode":"bad"}).ok, "unknown camera rejects")
	check(not demo.configure({"quality":"bad"}).ok, "unknown production quality rejects")
	check(not demo.configure({"zoom":0.0}).ok, "zero replay zoom rejects")
	check(demo.get_child_count() == 0, "invalid configuration allocates no scene")
	var receipt: Dictionary = demo.configure({})
	check(receipt.ok and receipt.pending and not receipt.ready, "configure before attachment is validated pending")
	check(demo.get_child_count() == 0, "pending configuration has no scene owners")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960,640)
	viewport.own_world_3d = true
	root.add_child(viewport)
	viewport.add_child(demo)
	var initial: Dictionary = demo.inspection_snapshot()
	check(initial.ready and initial.topic == "shore-surf", "ready synchronously builds production seam")
	check(initial.tick == 0 and initial.time == 0.0, "initial authority is zero accepted seconds")
	check(initial.resources.terrain == 1 and initial.resources.source_surf == 1 and initial.resources.ocean == 1 and initial.resources.ships == 0, "scope owns one actual island and no fleet")
	check(initial.resources.get("offscreen_targets",0) == 1 and initial.resources.get("source_patches",0) > 8, "actual reflection and source-patch resource population recorded")
	check(initial.telemetry.terrain_resolution == 257 and initial.telemetry.terrain_seed == 1661 and initial.telemetry.shore_field_resolution == 512, "actual source terrain and coast field inputs recorded")
	check(initial.telemetry.source.contourCount > 0 and initial.telemetry.source.patchCount > 8 and initial.telemetry.source.maxCoastHeightError < 0.0002, "source patches follow rendered triangle shore within declared error")
	check(initial.telemetry.source.originalTexture == "surf_bart3.dds" and initial.telemetry.source.surfaceWaveCount == 5, "real original texture and five-wave binding retained")
	var uniform_exists := false
	var water_weight_uniform_exists := false
	for uniform: Dictionary in demo.get("_ocean").material_override.shader.get_shader_uniform_list():
		uniform_exists = uniform_exists or uniform.name == "shore_edge_feather_m"
		water_weight_uniform_exists = water_weight_uniform_exists or uniform.name == "shore_edge_water_weight"
	check(uniform_exists, "feather candidate binds a declared shader seam rather than an unused materialproperty")
	check(water_weight_uniform_exists, "water coverage binds declared shared shader seam")
	check(initial.telemetry.source_seed_decimal is String and not initial.telemetry.source_seed_decimal.is_empty() and initial.telemetry.rng_state_retained == false, "configure-only source seed reported losslessly without invented retained state")
	check(not demo.is_processing() and not demo.is_physics_processing(), "host alone advances accepted clock")
	check(initial.camera_transform.size() == 16 and initial.camera_projection.size() == 16 and initial.viewport_size == [960,640], "actual camera matrices and viewport exported")
	var shore_focus: Vector3 = demo.get("_focus")
	check(initial.camera_position.distance_to(shore_focus)<60.0, "close preset observes local surf instead of framing the entire island")
	# Regression from real UI GPU frame: build aspect differs after controls lay
	# out. Fixed ticks must not leave the projected carrier at the old aspect.
	demo.set_paused(true)
	var resize_frozen := native_state(demo)
	var calls_before_resize: int = initial.telemetry.source_updates
	viewport.size = Vector2i(1260,449)
	demo.advance(0.03125)
	var submitted: Array = demo.get("_ocean").mesh.surface_get_arrays(0)
	var camera: Camera3D = demo.get("_camera")
	var minimum := Vector2(INF,INF)
	var maximum := Vector2(-INF,-INF)
	for vertex: Vector3 in submitted[Mesh.ARRAY_VERTEX]:
		var pixel := camera.unproject_position(vertex)
		minimum = minimum.min(pixel)
		maximum = maximum.max(pixel)
	check(minimum.x<=0.0 and maximum.x>=1260.0 and minimum.y<=0.0 and maximum.y>=449.0, "paused viewport resize refreshes actual projected carrier across all screen edges")
	var coast: Vector3 = shore_focus-demo.get("_outward")*6.0
	var offshore: Vector3 = coast+demo.get("_outward")*24.0
	var coast_pixel := camera.unproject_position(coast)
	var offshore_pixel := camera.unproject_position(offshore)
	check(coast_pixel.y>0.0 and coast_pixel.y<449.0 and offshore_pixel.y>0.0 and offshore_pixel.y<449.0, "close preset frames true coast through the24m advancing wash zone")
	check(native_state(demo) == resize_frozen and demo.inspection_snapshot().telemetry.source_updates == calls_before_resize, "resize refresh cannot advance clock or source controller")
	viewport.size = Vector2i(960,640)
	demo.advance(0.03125)
	demo.set_paused(false)
	var ids: Array = []
	for item: Dictionary in demo.control_spec():
		ids.append(item.id)
		check(item.has("label") and item.has("type") and item.has("value"), "host descriptor contains label, type and current value")
	check(ids.has("camera_mode") and ids.has("analytic_enabled") and ids.has("source_enabled") and ids.has("residue_enabled") and ids.has("source_opacity"), "host receives independent coast factors")
	check(ids.has("shore_edge_feather_m"), "host exposes verticalmeter shoreline feather candidate")
	check(ids.has("shore_edge_water_weight"), "host exposes nearshore water coverage factor")
	demo.advance(1.0/64.0)
	check(demo.inspection_snapshot().tick == 0, "half step cannot invoke source time")
	demo.advance(1.0/64.0)
	check(demo.inspection_snapshot().tick == 1 and demo.inspection_snapshot().time == 0.03125, "two halves accept one exact source step")
	check(demo.reset_experiment().ok, "same input resets")
	for _step in 192:
		demo.advance(0.03125)
	var replay := native_state(demo)
	var before: Dictionary = demo.inspection_snapshot()
	check(before.tick == 192 and before.time == 6.0, "192 fixed steps accept six seconds")
	check(before.telemetry.source.states != initial.telemetry.source.states, "accepted time changes real source controller outputs")
	demo.set_paused(true)
	demo.advance(0.25)
	await process_frame
	check(native_state(demo) == replay, "pause and host frame preserve real source history")
	for factor: String in ["analytic", "source", "residue"]:
		check(demo.set_parameter(factor + "_enabled",false).ok, "factor independently disables: " + factor)
		check(native_state(demo) == replay, "same-time disable preserves source samples: " + factor)
		var hidden: Dictionary = demo.inspection_snapshot()
		check(hidden.telemetry.source_updates == before.telemetry.source_updates, "same-time switch performs no source update: " + factor)
		check(hidden.telemetry.layers[factor].effective_opacity == 0.0, "disabled shader or carrier has zero effective opacity: " + factor)
		check(demo.set_parameter(factor + "_enabled",true).ok and demo.set_parameter(factor + "_opacity",0.5).ok, "factor restores and scales current layer: " + factor)
		check(native_state(demo) == replay, "opacity preserves source state: " + factor)
		check(demo.inspection_snapshot().telemetry.layers[factor].effective_opacity == 0.5, "half opacity binds to own layer: " + factor)
	var layers: Dictionary = demo.inspection_snapshot().telemetry.layers
	check(absf(layers.analytic.bound_strength - 0.18) < 0.000001 and absf(layers.residue.bound_strength - 0.19) < 0.000001, "independent analytic/residue strengths bind production scalar seams")
	check(layers.source.bound_alpha_error < 0.000001, "source alpha scales actual material and leaves recovered samples untouched")
	var edge_source_calls: int = demo.inspection_snapshot().telemetry.source_updates
	check(demo.set_parameter("shore_edge_feather_m",0.0).ok, "same-time shore feather baseline selects hard edge")
	check(demo.get("_ocean").material_override.get_shader_parameter("shore_edge_feather_m") == 0.0 and native_state(demo) == replay, "hard-edge baseline changes actual uniform without native updates")
	check(demo.set_parameter("shore_edge_feather_m",0.6).ok, "feather upper boundary accepted")
	var feathered: Dictionary = demo.inspection_snapshot()
	check(feathered.parameters.get("shore_edge_feather_m",-1.0) == 0.6 and demo.get("_ocean").material_override.get_shader_parameter("shore_edge_feather_m") == 0.6, "candidate receipt matches realmaterial binding")
	check(native_state(demo) == replay and feathered.telemetry.source_updates == edge_source_calls, "feather candidate does not change terrain/source/RNG/time")
	check(not demo.set_parameter("shore_edge_feather_m",-0.01).ok and not demo.set_parameter("shore_edge_feather_m",INF).ok and not demo.set_parameter("shore_edge_feather_m",true).ok and demo.inspection_snapshot().parameters.get("shore_edge_feather_m",-1.0) == 0.6, "bad feather live values atomically preserve candidate")
	check(demo.set_parameter("shore_edge_feather_m",0.6).ok, "restore declared feather candidate")
	var before_water_weight: Dictionary = demo.inspection_snapshot()
	check(demo.set_parameter("shore_edge_water_weight",1.0).ok, "same-width old coverage is selected with weight1")
	check(demo.get("_ocean").material_override.get_shader_parameter("shore_edge_water_weight") == 1.0 and demo.inspection_snapshot().parameters.shore_edge_feather_m == 0.6, "old coverage changes realuniform without changing width")
	check(demo.set_parameter("shore_edge_water_weight",0.0).ok, "transparent coverage boundary accepted")
	check(demo.get("_ocean").material_override.get_shader_parameter("shore_edge_water_weight") == 0.0 and native_state(demo) == replay and demo.inspection_snapshot().telemetry.source_updates == before_water_weight.telemetry.source_updates, "coverage boundary preserves native source/time/terrain/calls")
	check(demo.set_parameter("shore_edge_water_weight",0.55).ok, "restore declared0.55water coverage candidate")
	check(demo.inspection_snapshot().telemetry.get("shore_edge_water_weight",-1.0) == 0.55 and demo.inspection_snapshot().parameters.get("shore_edge_water_weight",-1.0) == 0.55, "water coverage exported as actual bound input")
	check(not demo.set_parameter("shore_edge_water_weight",-0.01).ok and not demo.set_parameter("shore_edge_water_weight",1.01).ok and not demo.set_parameter("shore_edge_water_weight",INF).ok and not demo.set_parameter("shore_edge_water_weight",true).ok, "water coverage invalid live values atomically reject")
	check(native_state(demo) == replay and demo.inspection_snapshot().parameters.get("shore_edge_water_weight",-1.0) == 0.55 and demo.inspection_snapshot().telemetry.source_updates == before_water_weight.telemetry.source_updates, "bad coverage input preserves candidate and native timeline")
	var parameter_state: Dictionary = demo.inspection_snapshot().parameters
	check(not demo.set_parameter("source_opacity",2.0).ok and not demo.set_parameter("source_enabled","false").ok and not demo.set_parameter("missing",true).ok, "invalid live controls atomically reject")
	check(demo.inspection_snapshot().parameters == parameter_state and native_state(demo) == replay, "rejection preserves all options and native outputs")
	var reconfigure: Dictionary = demo.set_parameter("quality","high")
	check(not reconfigure.ok and reconfigure.get("reset_required",false), "resource rebuild factor requests explicit reset")
	demo.set_camera_mode("wide")
	demo.orbit_camera(0.15,0.1)
	demo.zoom_camera(-0.2)
	var changed: Dictionary = demo.inspection_snapshot()
	check(changed.camera_transform != before.camera_transform and changed.camera_mode == "wide" and native_state(demo) == replay, "paused camera changes actual view without source calls")
	check(changed.telemetry.source_updates == before.telemetry.source_updates, "camera redraw performs no source update")
	check(changed.telemetry.geometry_builds == before.telemetry.geometry_builds and changed.resources == before.resources, "camera never rebuilds coast or resources")
	var saved: Dictionary = changed.parameters.duplicate(true)
	saved.paused = false
	check(demo.reset_experiment(saved).ok, "replay reset accepts actual parameter receipt")
	for _step in 192:
		demo.advance(0.03125)
	check(native_state(demo) == replay, "reset reproduces exact source packets, states and terrain")
	var restored: Dictionary = demo.inspection_snapshot()
	check(restored.camera_transform == changed.camera_transform and restored.camera_projection == changed.camera_projection, "reset reproduces saved concrete orbit camera")
	var before_edge := native_state(demo)
	demo.set_camera_mode("edge")
	var edge_view: Dictionary = demo.inspection_snapshot()
	check(edge_view.camera_mode == "edge" and edge_view.camera_position.distance_to(shore_focus)<40.0 and edge_view.camera_position.y>20.0, "edge preset is fixed close overhead view of actual shore")
	check(native_state(demo) == before_edge, "edge camera comparison preserves exact accepted source timeline")
	demo.advance(99.0)
	check(demo.inspection_snapshot().tick == 200, "catch-up accepts at most eight source steps")
	var bounded := native_state(demo)
	demo.advance(-1.0)
	demo.advance(NAN)
	check(native_state(demo) == bounded, "invalid delta cannot poison authority")
	check(not demo.configure({"residue_opacity":-0.1}).ok and native_state(demo) == bounded and demo.inspection_snapshot().ready, "bad live configuration preserves existing experiment")
	check(demo.configure({"camera_mode":"close"}).ok and demo.get_child_count() == 1 and demo.inspection_snapshot().tick == 0, "live configure replaces owners exactly once")
	var old_mirror: Camera3D = demo.get("_ocean").get_reflection_camera()
	var old_surf: Node3D = demo.get("_surf")
	demo.dispose()
	demo.dispose()
	var disposed: Dictionary = demo.inspection_snapshot()
	check(disposed.disposed and not disposed.ready and disposed.resources.ocean == 0 and disposed.resources.source_surf == 0 and demo.get_child_count() == 0, "idempotent dispose releases scene and optical owners")
	check(not is_instance_valid(old_mirror) and not is_instance_valid(old_surf), "dispose releases actual retained mirror and source nodes")
	demo.advance(1.0)
	check(demo.inspection_snapshot().tick == disposed.tick, "disposed authority cannot advance")
	check(demo.configure({"paused":true}).ok and demo.inspection_snapshot().ready, "explicit configure can reuse disposed owner")
	demo.dispose()
	viewport.free()
	finish()

func finish() -> void:
	print("LABORATORY_SHORE_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
