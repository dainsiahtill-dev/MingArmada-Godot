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
	check(initial.telemetry.source_seed_decimal is String and not initial.telemetry.source_seed_decimal.is_empty() and initial.telemetry.rng_state_retained == false, "configure-only source seed reported losslessly without invented retained state")
	check(not demo.is_processing() and not demo.is_physics_processing(), "host alone advances accepted clock")
	check(initial.camera_transform.size() == 16 and initial.camera_projection.size() == 16 and initial.viewport_size == [960,640], "actual camera matrices and viewport exported")
	var ids: Array = []
	for item: Dictionary in demo.control_spec():
		ids.append(item.id)
		check(item.has("label") and item.has("type") and item.has("value"), "host descriptor contains label, type and current value")
	check(ids.has("camera_mode") and ids.has("analytic_enabled") and ids.has("source_enabled") and ids.has("residue_enabled") and ids.has("source_opacity"), "host receives independent coast factors")
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
