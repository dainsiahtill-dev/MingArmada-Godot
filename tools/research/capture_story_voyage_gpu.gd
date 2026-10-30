extends "res://tools/research/capture_ship_fire_gpu.gd"
## Step-4 GPU/input acceptance slice for the story mode: real 棣栭〉鈫掍富绾胯埅绋?## entry, real UI intents through the operations panel buttons, an honest
## failure settlement, a real story save, and menu return with disposal.
const StoryRuntime = preload("res://game/runtime/story_runtime.gd")
const STORY_ROOT := "res://docs/research/evidence/story-campaign-flow/"
const VOYAGE_SCOPE := "story-voyage-gpu-slice; real entry, real UI intents, real save"

var scene: Node = null

func check(value: bool, message: String) -> bool:
	if not value: failures.append(message); printerr("FAIL STORY VOYAGE GPU: ", message)
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
	if not failures.is_empty(): print("STORY_VOYAGE_GPU_GUARD_REJECTED failures=", failures.size()); quit(2); return
	if not check(DirAccess.make_dir_recursive_absolute(expected) == OK, "create output"): quit(2); return
	own_output = true; AudioServer.set_bus_mute(0, true); seed(SEED)
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.content_scale_size = Vector2i(1600, 900); root.size = Vector2i(1600, 900)
	await frames(4)
	main = Main.instantiate(); root.add_child(main)
	await frames(4); await RenderingServer.frame_post_draw
	save_image(root.get_texture().get_image(), "menu-before.png", "menu", "", -1, 0, story_state())
	var button: Button = main.menu.find_child("story", true, false)
	if not check(is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled, "actual story menu entry"): await finish(); return
	button.pressed.emit()
	for _i in 120:
		await process_frame
		if is_instance_valid(main.current_scene): break
	scene = main.current_scene
	if not check(is_instance_valid(scene) and scene.startup_receipt.get("ok", false), "real story scene ready"): await finish(); return
	checks.append({"name": "real_entry", "ok": true, "scope": VOYAGE_SCOPE})
	await frames(4); await RenderingServer.frame_post_draw
	save_image(root.get_texture().get_image(), "story-initial.png", "story", "ch01", 0, 0, story_state())
	var panel = scene._interface
	if not check(panel != null and panel._buttons.has("begin-stage"), "operations panel present"): await finish(); return
	panel._buttons["begin-stage"].pressed.emit()
	await frames(2); await RenderingServer.frame_post_draw
	save_image(root.get_texture().get_image(), "ch01-briefing.png", "story", "ch01", 1, 0, story_state())
	panel._buttons["transition"].pressed.emit()
	panel._buttons["depart"].pressed.emit()
	for sample in 6:
		for _i in 30:
			await process_frame
		await RenderingServer.frame_post_draw
		save_image(root.get_texture().get_image(), "voyage-%02d.png" % sample, "voyage", "ch01", sample + 2, 30, story_state())
	panel._buttons["settle-stage"].pressed.emit()
	await frames(2); await RenderingServer.frame_post_draw
	save_image(root.get_texture().get_image(), "ch01-failure.png", "story", "ch01", 9, 0, story_state())
	var failed_state := story_state()
	if check(failed_state.receipts >= 1 and str(failed_state.lastOutcome) == "failure", "honest failure receipt recorded before arrival"):
		checks.append({"name": "honest_failure", "ok": true, "receipts": failed_state.receipts})
	panel._buttons["retry-stage"].pressed.emit()
	panel._buttons["begin-stage"].pressed.emit()
	panel._buttons["save"].pressed.emit()
	await frames(2); await RenderingServer.frame_post_draw
	var saved: String = read_user_save()
	if check(not saved.is_empty() and StoryRuntime.validate_save(saved).get("ok", false), "real story save written and validates"):
		checks.append({"name": "save", "ok": true, "bytes": saved.length()})
	save_image(root.get_texture().get_image(), "ch01-save.png", "story", "ch01", 10, 0, story_state())
	var scene_ref: WeakRef = weakref(scene)
	var runtime_ref: WeakRef = weakref(scene.runtime)
	main._return_from_scene(scene)
	scene = null
	await frames(4); await RenderingServer.frame_post_draw
	save_image(root.get_texture().get_image(), "menu-returned.png", "menu", "", -1, 0, story_state())
	var released: bool = scene_ref.get_ref() == null and runtime_ref.get_ref() == null
	check(released, "leave releases the story runtime")
	checks.append({"name": "dispose", "released": released})
	# Real restore acceptance: the menu's continue entry rebuilds the voyage
	# from the very save just written, and the story resumes where it stood.
	var continue_button: Button = main.menu.find_child("story-continue", true, false)
	if not check(is_instance_valid(continue_button) and continue_button.is_visible_in_tree() and not continue_button.disabled, "actual story-continue menu entry"): await finish(); return
	continue_button.pressed.emit()
	for _i in 120:
		await process_frame
		if is_instance_valid(main.current_scene): break
	scene = main.current_scene
	if not check(is_instance_valid(scene) and scene.startup_receipt.get("ok", false), "restored story scene ready"): await finish(); return
	var restored: Dictionary = story_state()
	if check(restored.attempt == 2 and restored.receipts == 1 and restored.phase == "active", "the save resumes at the exact attempt and receipts"):
		checks.append({"name": "restore", "ok": true, "attempt": restored.attempt, "receipts": restored.receipts})
	save_image(root.get_texture().get_image(), "ch01-restored.png", "story", "ch01", 11, 0, restored)
	scene_ref = weakref(scene)
	runtime_ref = weakref(scene.runtime)
	main._return_from_scene(scene)
	scene = null
	await frames(4); await RenderingServer.frame_post_draw
	save_image(root.get_texture().get_image(), "menu-final.png", "menu", "", -1, 0, story_state())
	check(scene_ref.get_ref() == null and runtime_ref.get_ref() == null, "restored scene also disposes")
	await finish()

func story_state() -> Dictionary:
	var state := {"ready": is_instance_valid(scene), "scope": VOYAGE_SCOPE, "actualGameplayComplete": false}
	if not is_instance_valid(scene):
		return state
	var packet: Dictionary = scene.runtime.call("snapshot")
	var progress: Dictionary = packet.get("progress", {})
	var receipts: Array = progress.get("receipts", [])
	state.stageIndex = int(progress.get("stageIndex", 0))
	state.phase = str(progress.get("phase", ""))
	state.attempt = int(progress.get("attempt", 1))
	state.receipts = receipts.size()
	state.lastOutcome = str(receipts.back().outcome) if not receipts.is_empty() else ""
	state.portId = str(packet.get("world", {}).get("currentPortId", ""))
	state.silver = int(packet.get("world", {}).get("silver", 0))
	return state

func compact(state: Dictionary) -> Dictionary:
	# Voyage states are plain dictionaries; the base compaction expects the
	# fire-experiment view payload and would read absent fields.
	return state.duplicate(true)

func read_user_save() -> String:
	var file := FileAccess.open("user://saves/story-v1.json", FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text

func finish() -> void:
	var report: Dictionary = {"valid": failures.is_empty(), "failures": failures, "scope": VOYAGE_SCOPE, "actualGameplayComplete": false, "step": "doc38-step4-slice", "gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "displayServer": DisplayServer.get_name(), "audioMuted": AudioServer.is_bus_mute(0), "seed": SEED, "fixedStep": STEP, "checks": checks, "captures": captures, "evidence_scope": "Actual Main/story entry with real UI intents and a real save; voyage slice only (not the full 30-stage playthrough), no manual keyboard play."}
	if own_output:
		var file := FileAccess.open(output + "/capture-result.json", FileAccess.WRITE)
		if file: file.store_string(JSON.stringify(report, "", false, true)); file.close()
		else: check(false, "write report")
	if is_instance_valid(main): main.free()
	await frames(2)
	print("STORY_VOYAGE_GPU captures=", captures.size(), " samples=", 6, " accepted_steps=", 180, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
