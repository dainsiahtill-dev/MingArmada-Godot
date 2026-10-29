extends SceneTree
## Real MainScene -> Laboratory -> registered demo. Capture-only, not gameplay.
const Main = preload("res://game/scenes/main/main_scene.tscn")
const Contract = preload("res://tools/research/broadside_capture_contract.gd")
const TOPIC := "broadside-receipt-readability"
var failures: Array = []
var captures: Array = []
var output := ""
var own_output := false
var main: Node
var lab: Control
var comparisons := 0

func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> bool:
	if not value: failures.append(message); printerr("FAIL BROADSIDE GPU: ",message)
	return value
func frames(count: int) -> void:
	for index in count: await process_frame
func digest_json(value: Variant) -> String:
	var ctx := HashingContext.new(); ctx.start(HashingContext.HASH_SHA256); ctx.update(JSON.stringify(value).to_utf8_buffer())
	return ctx.finish().hex_encode()
func rect_values(rect: Rect2) -> Array: return [rect.position.x,rect.position.y,rect.size.x,rect.size.y]

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output=") and output.is_empty(): output = arg.trim_prefix("--output=")
		else: check(false,"unknown or duplicate argument")
	var expected := OS.get_environment("BROADSIDE_CAPTURE_OUTPUT")
	check(Contract.output_ok(output,expected),"fresh confined capture output")
	check(Contract.profile_ok(OS.get_environment("APPDATA"),OS.get_environment("LOCALAPPDATA"),OS.get_environment("BROADSIDE_PROFILE_ROOT"),OS.get_environment("BROADSIDE_ORIGINAL_APPDATA"),ProjectSettings.globalize_path("user://")),"isolated appdata/localappdata and actual userdata")
	check(DisplayServer.get_name() != "headless","non-headless graphics required")
	if DisplayServer.get_name() != "headless":
		var adapter := RenderingServer.get_video_adapter_name().to_lower()
		check(not adapter.is_empty() and not "llvmpipe" in adapter and not "swiftshader" in adapter,"non-software graphics adapter required")
	if not failures.is_empty():
		print("BROADSIDE_LAB_GPU_GUARD_REJECTED failures=",failures.size()); quit(2); return
	if not check(DirAccess.make_dir_recursive_absolute(expected) == OK,"capture directory creation"): quit(2); return
	own_output = true
	main = Main.instantiate(); root.add_child(main); await frames(4)
	var button: Button = main.menu.find_child("laboratory",true,false)
	if not check(is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled,"actual main-menu laboratory button"): await finish(); return
	button.pressed.emit()
	for _i in 80:
		await process_frame
		if is_instance_valid(main.current_scene): break
	lab = main.current_scene
	if not check(is_instance_valid(lab) and lab.startup_receipt.get("ok",false),"laboratory opens through MainScene"): await finish(); return
	lab.set_process(false)
	if not check(lab.select_topic(TOPIC),"registered research topic selected"): await finish(); return
	for size: Vector2i in [Vector2i(1600,900),Vector2i(1280,720)]:
		DisplayServer.window_set_size(size); root.content_scale_size = size; root.size = size
		await frames(5); await RenderingServer.frame_post_draw
		var baseline: Array = []
		for enabled: bool in [false,true]:
			if not check(lab.start_demo({"paused":true,"candidate_enabled":enabled}).get("ok",false),"registered demo starts"): await finish(); return
			for tick in Contract.LAST_TICK+1:
				if tick > 0 and not check(lab.step_demo().get("ok",false),"host single step"): await finish(); return
				var snap: Dictionary = lab._demo.inspection_snapshot()
				if not check(int(snap.tick) == tick and absf(float(snap.time)-tick*Contract.STEP)<1.0e-12,"fixed frame clock"): await finish(); return
				if enabled:
					comparisons += 1
					if not check(Contract.pair_ok(baseline[tick],snap),"paired baseline/candidate state"): await finish(); return
				else: baseline.append(snap.duplicate(true))
				if not await capture(size,enabled,tick,snap): await finish(); return
	check(captures.size() == 4*(Contract.LAST_TICK+1),"all frames captured")
	check(comparisons == 2*(Contract.LAST_TICK+1),"all paired states compared")
	await finish()

func capture(size: Vector2i, enabled: bool, tick: int, snap: Dictionary) -> bool:
	await process_frame; await RenderingServer.frame_post_draw
	var observed: Dictionary = lab._demo.inspection_snapshot()
	if not check(observed == snap,"state remains fixed through frame_post_draw"): return false
	var experiment: SubViewport = lab.find_child("ExperimentViewport",true,false)
	var panel: PanelContainer = lab._demo.find_child("BroadsideReceiptPaper",true,false)
	if not check(is_instance_valid(experiment) and is_instance_valid(panel),"experiment viewport and frame exist"): return false
	var style: StyleBox = panel.get_theme_stylebox("panel")
	if not check(style.has_method("_get_draw_rect"),"painted frame draw bounds available"): return false
	var draw: Rect2 = style.call("_get_draw_rect",Rect2(Vector2.ZERO,panel.size)); draw.position += panel.position
	var viewport_bounds := Rect2(Vector2.ZERO,Vector2(experiment.size))
	if not check(viewport_bounds.encloses(draw),"complete painted frame and shadow fit experiment viewport"): return false
	var label_rects: Array = []
	for label: Label in panel.find_children("*","Label",true,false):
		var rect := label.get_global_rect()
		if not check(viewport_bounds.encloses(rect) and label.size.x+0.1 >= label.get_combined_minimum_size().x and label.size.y+0.1 >= label.get_combined_minimum_size().y,"each label fits viewport and control"): return false
		label_rects.append(rect_values(rect))
	var im := root.get_texture().get_image()
	if not check(im != null and not im.is_empty() and im.get_size() == size,"actual captured viewport dimensions"): return false
	var name := "%dx%d-%s-%03d.png" % [size.x,size.y,"candidate" if enabled else "baseline",tick]
	var path := output+"/"+name
	if not check(not FileAccess.file_exists(path),"capture cannot overwrite existing image"): return false
	if not check(im.save_png(path) == OK,"capture PNG written"): return false
	var digest := FileAccess.get_sha256(path)
	if not check(not digest.is_empty(),"capture image hash"): return false
	captures.append({"file":name,"sha256":digest,"viewport":[size.x,size.y],"variant":"candidate" if enabled else "baseline","tick":tick,"time":snap.time,"events":Contract.fixture_events(tick),"snapshot":snap,"layout":{"viewport":[experiment.size.x,experiment.size.y],"panel":rect_values(panel.get_rect()),"paintedBounds":rect_values(draw),"labels":label_rects}})
	return true

func finish() -> void:
	var report := {"valid":failures.is_empty(),"failures":failures,"scope":"registered laboratory synthetic event fixture, real GPU continuous capture; not formal gameplay, manual input, player experience or FPS","engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"displayServer":DisplayServer.get_name(),"fixedStep":Contract.STEP,"lastTick":Contract.LAST_TICK,"fixture":Contract.input_fixture(),"fixtureSha256":digest_json(Contract.input_fixture()),"comparisons":comparisons,"captures":captures}
	if own_output:
		var path := output+"/capture-result.json"
		if not FileAccess.file_exists(path):
			var file := FileAccess.open(path,FileAccess.WRITE)
			if file: file.store_string(JSON.stringify(report,"\t")); file.close()
			else: failures.append("capture result write failed")
		else: failures.append("capture result already exists")
	if is_instance_valid(main): main.free()
	await frames(2)
	print("BROADSIDE_LAB_GPU captures=",captures.size()," comparisons=",comparisons," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
