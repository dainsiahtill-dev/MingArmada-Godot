extends SceneTree
## Real GPU, ordinary menu route, isolated registered production-component demos.
const Main = preload("res://game/scenes/main/main_scene.tscn")
var output := "res://docs/research/evidence/laboratory-environment-2026-10-14"
var failures: Array = []
var captures: Array = []
var sequences: Array = []
var main: Node
var lab: Control
var before: Dictionary = {}
func _initialize() -> void: run.call_deferred()
func check(ok: bool, reason: String) -> void:
	if not ok: failures.append(reason); printerr("FAIL: ",reason)
func frames(count: int) -> void:
	for _i in count: await process_frame
func capture(label: String) -> void:
	await frames(3)
	var receipt: Dictionary = await lab.save_experiment_frame(output+"/"+label+".png")
	check(receipt.ok,"native image and state export "+label)
	var ui := root.get_texture().get_image()
	check(ui.save_png(output+"/"+label+"-ui.png") == OK,"UI capture "+label)
	captures.append({"name":label,"image":label+".png","state":label+".png.json","ui":label+"-ui.png","sha256":FileAccess.get_sha256(output+"/"+label+".png")})
	print("ENVIRONMENT_CAPTURE ",label)
func launch(topic: String, options: Dictionary = {}) -> bool:
	check(lab.select_topic(topic),"select "+topic)
	options["paused"] = true
	var receipt: Dictionary = lab.start_demo(options)
	check(receipt.ok,"launch "+topic)
	return receipt.ok
func advance_to(seconds: float) -> void:
	lab._demo.set_paused(false)
	var target := int(round(seconds*32.0))
	while lab._demo.inspection_snapshot().tick < target:
		lab._demo.advance(1.0/32.0)
		if int(lab._demo.inspection_snapshot().tick)%32 == 0: await process_frame
	lab._demo.set_paused(true); lab._update_telemetry()
	sequences.append(lab.inspection_snapshot())
func factor(id: String, value: Variant) -> void:
	var original: Dictionary = lab._demo.inspection_snapshot()
	lab._change_parameter(id,value)
	var current: Dictionary = lab._demo.inspection_snapshot()
	check(current.time == original.time and current.tick == original.tick,"factor keeps accepted clock "+id)
	if original.has("rng"): check(current.rng == original.rng,"factor keeps RNG "+id)
	if original.has("environment"): check(current.environment == original.environment,"factor keeps environment "+id)
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(1600,1000); root.content_scale_size = root.size
	for path: String in ["user://saves/mingqi-v2.json","user://saves/legacy-v1.json","user://settings.json"]:
		before[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
	main = Main.instantiate(); root.add_child(main); await frames(4)
	var button: Button = main.menu.find_child("laboratory",true,false)
	check(button != null and button.is_visible_in_tree(),"ordinary homepage laboratory entry")
	button.pressed.emit()
	for _i in 80:
		await process_frame
		if is_instance_valid(main.current_scene): break
	lab = main.current_scene
	check(is_instance_valid(lab) and lab.startup_receipt.ok,"real route activates laboratory")
	if not is_instance_valid(lab): finish(); return
	lab.set_process(false)
	if not launch("ocean-surface"): finish(); return
	for seconds: float in [0.0,0.5,1.0,2.0]:
		await advance_to(seconds); await capture("ocean-near-t%03d" % int(seconds*32))
	for mode: String in ["camera_mid","camera_horizon"]:
		factor("camera_mode",mode); await capture("ocean-"+mode)
	factor("optics_mode","legacy"); await capture("ocean-horizon-legacy")
	factor("optics_mode","soft"); factor("camera_mode","camera_near")
	factor("reflection_enabled",false); await capture("ocean-mirror-off")
	factor("reflection_enabled",true); factor("refraction_enabled",false); await capture("ocean-refraction-off")
	factor("refraction_enabled",true); factor("detail_strength",0.0); await capture("ocean-detail-zero")
	lab._change_parameter.call_deferred("detail_strength",0.75)
	var canceled: Dictionary = await lab.save_experiment_frame(output+"/stale-parameter-frame.png")
	check(not canceled.ok and not FileAccess.file_exists(output+"/stale-parameter-frame.png"),"parameter mutation cancels stale pending capture")
	if not launch("shore-surf"): finish(); return
	for seconds: float in [0.0,6.0,12.0,18.0,24.0]:
		await advance_to(seconds); await capture("shore-close-t%03d" % int(seconds))
	factor("camera_mode","wide"); await capture("shore-wide")
	factor("camera_mode","edge")
	for width: float in [0.0,0.1,0.35,0.6]:
		factor("shore_edge_feather_m",width); await capture("shore-edge-width-%02d" % int(width*100))
	factor("shore_edge_feather_m",0.6)
	factor("shore_edge_water_weight",1.0); await capture("shore-edge-water-weight-100")
	factor("shore_edge_water_weight",0.55); await capture("shore-edge-water-weight-55")
	factor("camera_mode","close")
	for selected: String in ["analytic","source","residue","off"]:
		for layer: String in ["analytic","source","residue"]: factor(layer+"_enabled",selected == layer)
		await capture("shore-"+selected+"-only")
	if not launch("weather-shadow"): finish(); return
	for seconds: float in [0.0,1.0,2.0]:
		await advance_to(seconds); await capture("weather-clear-t%03d" % int(seconds))
	for mode: String in ["sky","ground"]:
		factor("camera_mode",mode); await capture("weather-clear-"+mode)
	for preset: String in ["storm","sunset"]:
		lab._change_parameter("preset",preset)
		check(lab._demo.inspection_snapshot().tick == 0,"preset explicitly resets "+preset)
		for mode: String in ["overview","sky","ground"]:
			factor("camera_mode",mode); await capture("weather-"+preset+"-"+mode)
	lab._change_parameter("preset","storm"); factor("camera_mode","overview")
	await advance_to(2.0); await capture("weather-storm-on")
	for id: String in ["shadows_enabled","clouds_enabled","sky_enabled"]:
		factor("camera_mode","sky" if id == "sky_enabled" else "ground" if id == "shadows_enabled" else "overview")
		await capture("weather-"+id+"-on")
		factor(id,false); await capture("weather-"+id+"-off"); factor(id,true)
	lab._show_paper()
	check(lab._viewport.get_child_count() == 0,"exit disposes independent owners")
	lab.find_child("ReturnToMenu",true,false).pressed.emit(); await frames(4)
	check(main.current_scene == null and main.menu.is_visible_in_tree(),"real route returns homepage")
	finish()
func finish() -> void:
	var after: Dictionary = {}
	for path: String in before: after[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
	check(before == after,"laboratory preserves save and settings bytes")
	var source_hashes: Dictionary = {}
	for source: String in ["game/research/laboratory.gd","game/research/parameter_panel.gd","game/research/catalog.gd","assets/research/catalog.json","game/research/demos/ocean_surface_experiment.gd","game/research/demos/shore_surf_experiment.gd","game/research/demos/weather_shadow_experiment.gd","modules/scene_engine/ocean/reference_game_water.gdshader","modules/scene_engine/ocean/shore_edge_coverage.gdshaderinc"]:
		source_hashes[source] = FileAccess.get_sha256("res://"+source)
	var proof := {"valid":failures.is_empty(),"failures":failures,"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"displayServer":DisplayServer.get_name(),"captures":captures,"sequences":sequences,"sourceHashes":source_hashes,"persistedBefore":before,"persistedAfter":after,"scope":"Ordinary menu and real GPU isolated demos; time, factor, image/state, disposal and persisted-byte contracts. PNG artistic review is separate. Actual SubViewport dimensions are saved per frame; no production change, full-game performance or original-renderer parity claim."}
	var file := FileAccess.open(output+"/GPU_VERIFY.json",FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(proof,"\t")); file.close()
	else: failures.append("report write failed")
	if is_instance_valid(main): main.free()
	await frames(2)
	print("LABORATORY_ENVIRONMENT_GPU captures=",captures.size()," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
