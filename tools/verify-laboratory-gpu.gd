extends SceneTree
## Actual menu -> Laboratory -> independent experiment; no external browser/server.
const Main = preload("res://game/scenes/main/main_scene.tscn")
var failures: Array = []
var captures: Array = []
var sequences: Array = []
var carrier_pairs: Array = []
var output := "res://docs/research/evidence/laboratory-2026-10-14"
var main: Node
var laboratory: Control
var papers_only := false
func _initialize() -> void: run.call_deferred()
func check(ok: bool, reason: String) -> void:
	if not ok: failures.append(reason); printerr("FAIL: ",reason)
func frames(count: int) -> void:
	for _i in count: await process_frame
func capture(name: String) -> void:
	await frames(2); await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image != null and not image.is_empty(),"GPU frame available: "+name)
	if image == null or image.is_empty(): return
	if papers_only: name = "final-"+name
	var path := output+"/"+name+".png"
	check(image.save_png(path) == OK,"GPU frame written: "+name)
	captures.append({"name":name,"image":name+".png","sha256":FileAccess.get_sha256(path),"size":[image.get_width(),image.get_height()],"laboratory":laboratory.inspection_snapshot() if is_instance_valid(laboratory) else {}})
func run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		elif argument == "--papers-only": papers_only = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(1600,1000); root.content_scale_size = root.size
	var persisted: Array = ["user://saves/mingqi-v2.json","user://saves/legacy-v1.json","user://settings.json"]
	var before: Dictionary = {}
	for path: String in persisted: before[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
	main = Main.instantiate(); root.add_child(main); await frames(4)
	var button: Button = main.menu.find_child("laboratory",true,false)
	check(button != null and button.is_visible_in_tree() and not button.disabled,"ordinary homepage laboratory button enabled")
	await capture("01-home")
	if button == null: finish(before,persisted); return
	button.pressed.emit()
	for _i in 80:
		await process_frame
		if is_instance_valid(main.current_scene): break
	laboratory = main.current_scene
	check(is_instance_valid(laboratory) and laboratory.startup_receipt.ok,"actual entry activates laboratory")
	if not is_instance_valid(laboratory): finish(before,persisted); return
	laboratory.set_process(false)
	await capture("02-paper-hull")
	for id: String in ["ocean-surface","shore-surf","weather-shadow","shadow-edges"]:
		check(laboratory.select_topic(id),"paper selectable: "+id)
		await capture("paper-"+id)
	laboratory.select_topic("hull-contact")
	if papers_only:
		laboratory.main_menu_requested.emit(); await frames(4)
		check(main.current_scene == null and main.menu.is_visible_in_tree(),"final paper UI returns to homepage")
		laboratory = null; await capture("returned-home"); finish(before,persisted); return
	check(laboratory.start_demo({"paused":false}).ok,"actual independent demo starts")
	if not is_instance_valid(laboratory._demo): finish(before,persisted); return
	for scenario: String in ["cruise","slow","turn","stop","reentry"]:
		laboratory._demo_options.scenario = scenario; laboratory._demo_options.paused = false
		laboratory._reset_demo()
		laboratory.find_child("ExperimentCase",true,false).select(laboratory.CASES.find(scenario))
		var timeline: Array = []
		for tick in 161:
			if tick: laboratory._demo.advance(1.0/32.0)
			var snapshot: Dictionary = laboratory._demo.inspection_snapshot()
			timeline.append({"tick":snapshot.tick,"time":snapshot.time,"ship":snapshot.ship,"impact":snapshot.contact.get("impact_strength",0),"overlay_m":snapshot.diagnostic_overlay_m,"tail":snapshot.tail})
			if tick in [96,128,136,144,160]:
				laboratory._update_telemetry(); await capture("demo-%s-t%03d" % [scenario,tick])
			elif tick%16 == 0: await process_frame
		check(timeline[-1].time > timeline[0].time,"accepted native time advances: "+scenario)
		sequences.append({"scenario":scenario,"timeline":timeline})
	laboratory._demo.set_paused(true); laboratory._demo_options.paused = true; laboratory._pause_button.text = "继续"
	var paused: Dictionary = laboratory._demo.inspection_snapshot()
	laboratory._demo.advance(0.25)
	check(laboratory._demo.inspection_snapshot().tick == paused.tick,"paused GPU experiment retains accepted tick")
	laboratory._contact.set_pressed(false); await capture("comparison-contact-off")
	var off: Dictionary = laboratory._demo.inspection_snapshot()
	check(off.tail == paused.tail and off.ship == paused.ship and off.time == paused.time,"A/B switch preserves identical tail pose and time")
	laboratory._contact.set_pressed(true); await capture("comparison-contact-on")
	var on: Dictionary = laboratory._demo.inspection_snapshot()
	check(on.tail == off.tail and on.ship == off.ship and on.time == off.time,"A/B enabled restores only contact visibility")
	var frame: Dictionary = await laboratory.save_experiment_frame(output+"/native-demo-export.png")
	check(frame.ok,"in-game screenshot and parameter export succeeds")
	for camera_mode: String in ["front","high"]:
		laboratory._change_camera(laboratory.CAMERAS.find(camera_mode))
		laboratory.find_child("ExperimentCamera",true,false).select(laboratory.CAMERAS.find(camera_mode))
		await capture("paused-camera-"+camera_mode)
	laboratory._change_camera(0); laboratory.find_child("ExperimentCamera",true,false).select(0)
	for kind: String in ["fisherman","merchant","voc","patrol","heavy"]:
		laboratory._demo_options.kind = kind; laboratory._demo_options.scenario = "cruise"; laboratory._demo_options.paused = false
		laboratory._reset_demo()
		laboratory.find_child("ExperimentShip",true,false).select(laboratory.KINDS.find(kind)); laboratory.find_child("ExperimentCase",true,false).select(0)
		for _tick in 96: laboratory._demo.advance(1.0/32.0)
		laboratory._update_telemetry(); await capture("ship-"+kind)
	for extent: float in [1200.0,384.0]:
		laboratory._demo_options.merge({"kind":"fuchuan","scenario":"cruise","paused":false,"camera_mode":"high","carrier_extent":extent},true)
		laboratory._reset_demo()
		for _tick in 128: laboratory._demo.advance(1.0/32.0)
		laboratory._pause_demo()
		var state: Dictionary = laboratory._demo.inspection_snapshot()
		carrier_pairs.append({"extent":extent,"state":state})
		await capture("carrier-%d-high" % int(extent))
	check(carrier_pairs[0].state.native_ship == carrier_pairs[1].state.native_ship and carrier_pairs[0].state.time == carrier_pairs[1].state.time and carrier_pairs[0].state.tail == carrier_pairs[1].state.tail,"carrier comparison retains identical native pose time and tail")
	laboratory._show_paper(); check(laboratory.inspection_snapshot().demo.is_empty(),"closing experiment releases world")
	laboratory.find_child("ReturnToMenu",true,false).pressed.emit(); await frames(4)
	check(main.current_scene == null and main.menu.is_visible_in_tree(),"actual owner returns to homepage")
	laboratory = null; await capture("03-returned-home")
	finish(before,persisted)
func finish(before: Dictionary,persisted: Array) -> void:
	var after: Dictionary = {}
	for path: String in persisted: after[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
	check(before == after,"normal laboratory entry and experiments do not mutate user saves/settings")
	var proof := {"valid":failures.is_empty(),"failures":failures,"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"displayServer":DisplayServer.get_name(),"captures":captures,"sequences":sequences,"carrierPairs":carrier_pairs,"persistedBefore":before,"persistedAfter":after,"scope":"Actual main-scene ordinary menu button, Laboratory papers and isolated registered hull experiment in real GPU SubViewport. Five controlled 32Hz timelines, six ship kinds, paused same-state contact A/B, controlled carrier comparison and native PNG+parameters export. Valid marks capture/state contracts, not a blanket artistic-effect acceptance. Not full-game FPS, original-game pixel parity or new independent validation of the four paper-only subjects."}
	proof.sourceHashes = {}
	for source: String in ["res://game/research/laboratory.gd","res://game/research/catalog.gd","res://game/research/paper_reader.gd","res://game/research/demos/hull_contact_experiment.gd","res://assets/research/catalog.json"]: proof.sourceHashes[source] = FileAccess.get_sha256(source)
	if papers_only: proof.scope = "Final bundled-paper text and caption UI observed from actual ordinary main-menu route, disposal and persisted-byte checks. Captures only; does not rerun the independent experiment or claim its artistic acceptance."
	var file := FileAccess.open(output+("/UI_VERIFY.json" if papers_only else "/GPU_VERIFY.json"),FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(proof,"\t")); file.close()
	else: failures.append("GPU report cannot be written")
	if is_instance_valid(main): main.free()
	await frames(2)
	print("LABORATORY_GPU captures=",captures.size()," sequences=",sequences.size()," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
