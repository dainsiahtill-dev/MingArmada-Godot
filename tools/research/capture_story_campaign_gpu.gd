extends "res://tools/research/capture_ship_fire_gpu.gd"
## Real laboratory UI; every task fact below is explicitly synthetic.
const STORY_SCOPE := "synthetic-progress-fixture; no real gameplay completion"
const STORY_ROOT := "res://docs/research/evidence/story-campaign-flow/"

func check(value: bool, message: String) -> bool:
	if not value: failures.append(message); printerr("FAIL STORY CAMPAIGN GPU: ", message)
	return value

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output=") and output.is_empty(): output = arg.trim_prefix("--output=")
		else: check(false, "unknown or duplicate argument")
	var expected: String = OS.get_environment("SHIP_FIRE_CAPTURE_OUTPUT")
	var profile: String = OS.get_environment("SHIP_FIRE_PROFILE_ROOT")
	var original: String = OS.get_environment("SHIP_FIRE_ORIGINAL_APPDATA")
	var app: String = OS.get_environment("APPDATA")
	var local: String = OS.get_environment("LOCALAPPDATA")
	check(not expected.is_empty() and output.begins_with(STORY_ROOT) and output.ends_with("/frames") and not output.contains("..") and not output.contains("\\") and normal(ProjectSettings.globalize_path(output)) == normal(expected) and not DirAccess.dir_exists_absolute(expected) and not FileAccess.file_exists(expected), "fresh confined output")
	check(not original.is_empty() and inside(app, profile) and inside(local, profile) and normal(app) != normal(local) and inside(ProjectSettings.globalize_path("user://"), app) and not inside(profile, original) and not inside(original, profile), "isolated userdata")
	check(DisplayServer.get_name() != "headless", "non-headless graphics required")
	if DisplayServer.get_name() != "headless":
		var gpu: String = RenderingServer.get_video_adapter_name().to_lower()
		check(not gpu.is_empty() and not "llvmpipe" in gpu and not "swiftshader" in gpu and not "software" in gpu, "hardware graphics required")
	if not failures.is_empty(): print("STORY_CAMPAIGN_GPU_GUARD_REJECTED failures=", failures.size()); quit(2); return
	if not check(DirAccess.make_dir_recursive_absolute(expected) == OK, "create output"): quit(2); return
	own_output = true; AudioServer.set_bus_mute(0, true); seed(SEED)
	DisplayServer.window_set_size(Vector2i(1600,900)); root.content_scale_size = Vector2i(1600,900); root.size = Vector2i(1600,900)
	await frames(4)
	main = Main.instantiate(); root.add_child(main)
	await frames(4); await RenderingServer.frame_post_draw
	save_image(root.get_texture().get_image(), "menu-before.png", "menu", "", -1, 0, {})
	var button: Button = main.menu.find_child("laboratory", true, false)
	if not check(is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled, "actual laboratory menu entry"): await finish(); return
	button.pressed.emit()
	for _i in 120:
		await process_frame
		if is_instance_valid(main.current_scene): break
	lab = main.current_scene
	if not check(is_instance_valid(lab) and lab.startup_receipt.get("ok", false), "real laboratory ready"): await finish(); return
	lab.set_process(false)
	if not check(lab.select_topic("story-campaign-flow"), "registered mainline topic"): await finish(); return
	checks.append({"name":"real_entry","ok":true,"scope":STORY_SCOPE})
	for spec: Dictionary in [{"id":"complete","actions":120}, {"id":"recover","actions":123}, {"id":"missing-handover","actions":120}]:
		if not await run_story_case(spec): await finish(); return
	var before: Dictionary = lab._demo.inspection_snapshot()
	lab._reset_demo({"fixture":"complete","paused":true,"camera_mode":"overview"})
	await frames(2); await RenderingServer.frame_post_draw
	var reset: Dictionary = lab._demo.inspection_snapshot()
	check(reset.tick == 0 and reset.progress.stageIndex == 0 and reset.progress.receipts.is_empty() and reset.progress.failureArchive.is_empty(), "reset clears only synthetic progress")
	checks.append({"name":"reset","before":compact(before),"after":compact(reset),"ok":failures.is_empty()})
	save_image(lab._viewport.get_texture().get_image(), "reset.png", "reset", "", 0, 0, reset)
	var demo_ref: WeakRef = weakref(lab._demo)
	var panel_ref: WeakRef = weakref(lab._demo.get("_panel"))
	main._return_from_scene(lab); lab = null
	await frames(4); await RenderingServer.frame_post_draw
	var released: bool = demo_ref.get_ref() == null and panel_ref.get_ref() == null
	check(released, "leave releases all owned fixture controls")
	checks.append({"name":"dispose","released":released})
	save_image(root.get_texture().get_image(), "menu-returned.png", "menu", "", -1, 0, {})
	await finish()

func run_story_case(spec: Dictionary) -> bool:
	var id: String = spec.id
	if not check(lab.start_demo({"fixture":id,"paused":true,"camera_mode":"overview","seed":SEED}).get("ok", false), "start synthetic " + id): return false
	await frames(2)
	if not await story_sample(id, 0): return false
	for action: int in range(1, int(spec.actions) + 1):
		for _i in 15:
			if not check(lab.step_demo().get("ok", false), "host accepted step"): return false
			accepted_steps += 1
		if not await story_sample(id, action): return false
		if id == "complete" and action in [34, 38, 46, 50, 82, 118]:
			if not await detail_probe(id, action): return false
		if action % 30 == 0: print("STORY_CAMPAIGN_GPU_PROGRESS case=", id, " action=", action)
	var state: Dictionary = lab._demo.inspection_snapshot()
	if id == "missing-handover":
		check(state.blocked and state.currentStage.id == "T10" and state.progress.phase == "active" and state.progress.receipts.size() == 29, "missing actual handover fact cannot finish even synthetic fixture")
		if not await pause_probe(id, "blocked", int(spec.actions)): return false
	else:
		check(state.progress.phase == "complete" and state.progress.stageIndex == 30 and state.progress.receipts.size() == (31 if id == "recover" else 30), "synthetic path completed expected records")
	cases.append({"id":id,"actions":int(spec.actions),"last_tick":state.tick,"last_time":state.time,"final":compact(state)})
	return failures.is_empty()

func story_sample(id: String, action: int) -> bool:
	await process_frame; await RenderingServer.frame_post_draw
	var state: Dictionary = lab._demo.inspection_snapshot()
	if not check(state.scope == STORY_SCOPE and state.ready and state.paused and state.error.is_empty() and state.resources.world == 0 and state.resources.runtime == 0 and state.resources.storage == 0 and state.tick == action * 15 and near(state.time, action * .25) and state.text.contains("非真实任务通关"), "fixture scope, clock and no world ownership"): return false
	var file: String = "%s-%03d.png" % [id, action]
	sequences.append({"case":id,"action":action,"file":file,"tick":state.tick,"time":state.time,"transitionCount":state.transitionCount,"stageIndex":state.progress.stageIndex,"phase":state.progress.phase,"revision":state.progress.revision})
	return save_image(lab._viewport.get_texture().get_image(), file, "fixture", id, action, 15 if action > 0 else 0, state)

func detail_probe(id: String, action: int) -> bool:
	var before: Dictionary = lab._demo.inspection_snapshot()
	lab._demo.set_camera_mode("current")
	await frames(2); await RenderingServer.frame_post_draw
	var after: Dictionary = lab._demo.inspection_snapshot()
	var unchanged: bool = before.progress == after.progress and before.tick == after.tick and before.transitionCount == after.transitionCount
	check(unchanged, "view change preserves synthetic facts and cursor")
	checks.append({"name":"detail","action":action,"unchanged":unchanged,"file":"detail-%03d.png" % action,"stageId":after.currentStage.get("id", "")})
	save_image(lab._viewport.get_texture().get_image(), "detail-%03d.png" % action, "detail", id, action, 0, after)
	if action == 46 and not await pause_probe(id, "father-review", action): return false
	lab._demo.set_camera_mode("overview"); await frames(2)
	return failures.is_empty()

func compact(state: Dictionary) -> Dictionary:
	var copy: Dictionary = state.duplicate(true)
	if copy.has("ui"):
		for key: String in copy.ui:
			if copy.ui[key] is Rect2:
				var rect: Rect2 = copy.ui[key]
				copy.ui[key] = [rect.position.x,rect.position.y,rect.size.x,rect.size.y]
	return copy

func finish() -> void:
	var report: Dictionary = {"valid":failures.is_empty(),"failures":failures,"scope":STORY_SCOPE,"actualGameplayComplete":false,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"displayServer":DisplayServer.get_name(),"audioMuted":AudioServer.is_bus_mute(0),"seed":SEED,"fixedStep":STEP,"ticksPerSample":15,"acceptedSteps":accepted_steps,"cases":cases,"sequences":sequences,"checks":checks,"captures":captures,"evidence_scope":"Actual Main/Laboratory and rendered synthetic progress only. No real tasks, world assets, manual play, campaign persistence or gameplay completion."}
	if own_output:
		var file := FileAccess.open(output + "/capture-result.json", FileAccess.WRITE)
		if file: file.store_string(JSON.stringify(report, "", false, true)); file.close()
		else: check(false, "write report")
	if is_instance_valid(main): main.free()
	await frames(2)
	print("STORY_CAMPAIGN_GPU captures=", captures.size(), " samples=", sequences.size(), " accepted_steps=", accepted_steps, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
