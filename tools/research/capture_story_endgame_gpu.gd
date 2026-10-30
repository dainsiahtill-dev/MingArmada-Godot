extends "res://tools/research/capture_ship_fire_gpu.gd"
## Step-4 endgame slice: restores a prepared T10 checkpoint through the real
## menu continue entry, then finishes the three-gate ending with REAL button
## intents (terms / evacuation / handover), settles success, and reaches the
## campaign ending — all with PNG captures and disposal audits.
const StoryRuntime = preload("res://game/runtime/story_runtime.gd")
const STORY_ROOT := "res://docs/research/evidence/story-campaign-flow/"
const VOYAGE_SCOPE := "story-endgame-gpu-slice; real restore, real ending controls, real settle"

var scene: Node = null

func check(value: bool, message: String) -> bool:
	if not value: failures.append(message); printerr("FAIL STORY ENDGAME GPU: ", message)
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
	if not failures.is_empty(): print("STORY_ENDGAME_GPU_GUARD_REJECTED failures=", failures.size()); quit(2); return
	if not check(DirAccess.make_dir_recursive_absolute(expected) == OK, "create output"): quit(2); return
	own_output = true; AudioServer.set_bus_mute(0, true); seed(SEED)
	DisplayServer.window_set_size(Vector2i(1600, 900)); root.content_scale_size = Vector2i(1600, 900); root.size = Vector2i(1600, 900)
	await frames(4)
	main = Main.instantiate(); root.add_child(main)
	await frames(4); await RenderingServer.frame_post_draw
	save_image(root.get_texture().get_image(), "menu-before.png", "menu", "", -1, 0, story_state())
	var button: Button = main.menu.find_child("story-continue", true, false)
	if not check(is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled, "actual story-continue menu entry"): await finish(); return
	button.pressed.emit()
	for _i in 120:
		await process_frame
		if is_instance_valid(main.current_scene): break
	scene = main.current_scene
	if not check(is_instance_valid(scene) and scene.startup_receipt.get("ok", false), "restored endgame scene ready"): await finish(); return
	var restored := story_state()
	if check(restored.stageIndex == 29 and restored.phase == "active" and restored.receipts == 29, "the prepared endgame restores exactly (stage %s, receipts %s)" % [str(restored.stageIndex), str(restored.receipts)]):
		checks.append({"name": "restore", "ok": true, "stageIndex": restored.stageIndex, "receipts": restored.receipts})
	save_image(root.get_texture().get_image(), "endgame-restored.png", "story", "t10", 0, 0, restored)
	var panel = scene._interface
	var order := ["terms", "evacuate", "handover"]
	for index in order.size():
		var pressed := false
		for key: Variant in panel._ending_buttons:
			if str(key).begins_with(order[index]):
				var ending_button: Button = panel._ending_buttons[key]
				if ending_button.is_visible_in_tree():
					ending_button.pressed.emit()
					pressed = true
					break
		if not check(pressed, "real %s button pressed" % order[index]): await finish(); return
		await frames(3); await RenderingServer.frame_post_draw
		save_image(root.get_texture().get_image(), "endgame-%s.png" % order[index], "story", "t10", index + 1, 0, story_state())
	panel._buttons["depart"].pressed.emit()
	await frames(3); await RenderingServer.frame_post_draw
	save_image(root.get_texture().get_image(), "endgame-depart.png", "story", "t10", 4, 0, story_state())
	panel._buttons["settle-stage"].pressed.emit()
	await frames(3); await RenderingServer.frame_post_draw
	var settled := story_state()
	if settled.receipts != 30:
		# The button already routed the intent; probing the scene command again
		# surfaces the exact refusal for the evidence trail.
		var progress_state: Dictionary = scene.runtime.progress.call("snapshot")
		print("ENDGAME probe progress=", JSON.stringify(progress_state.objectiveProgress), " evidence=", JSON.stringify((progress_state.seenEvidence as Dictionary).keys()))
		var probe: Dictionary = scene._command({"type": "settle-stage"})
		print("ENDGAME probe settle=", JSON.stringify(probe))
		await frames(3)
		settled = story_state()
	save_image(root.get_texture().get_image(), "endgame-complete.png", "story", "t10", 5, 0, settled)
	if check(settled.receipts == 30 and settled.lastOutcome == "success", "T10 settles success through the real three gates (receipts %s, %s, gates %s)" % [str(settled.receipts), str(settled.lastOutcome), str(settled.gates)]):
		checks.append({"name": "settle", "ok": true, "outcome": settled.lastOutcome})
	panel._buttons["continue-story"].pressed.emit()
	await frames(3); await RenderingServer.frame_post_draw
	var ending := story_state()
	if str(ending.phase) != "complete":
		var probe_end: Dictionary = scene._command({"type": "continue-story"})
		print("ENDGAME probe continue=", JSON.stringify(probe_end))
		await frames(3)
		ending = story_state()
	if check(ending.phase == "complete", "the campaign reaches its ending phase (%s)" % str(ending.phase)):
		checks.append({"name": "ending", "ok": true, "phase": ending.phase})
	save_image(root.get_texture().get_image(), "endgame-ending.png", "story", "t10", 6, 0, ending)
	await frames(4); await RenderingServer.frame_post_draw
	save_image(root.get_texture().get_image(), "endgame-summary.png", "story", "t10", 7, 0, story_state())
	var scene_ref: WeakRef = weakref(scene)
	var runtime_ref: WeakRef = weakref(scene.runtime)
	main._return_from_scene(scene)
	scene = null
	await frames(4); await RenderingServer.frame_post_draw
	save_image(root.get_texture().get_image(), "menu-final.png", "menu", "", -1, 0, story_state())
	var released: bool = scene_ref.get_ref() == null and runtime_ref.get_ref() == null
	check(released, "the finished voyage releases its runtime")
	checks.append({"name": "dispose", "released": released})
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
	var gates := {}
	for key: Variant in packet.get("runtime", {}).get("witnesses", {}).get("objectives", {}):
		gates[str(key)] = bool(packet.runtime.witnesses.objectives[key].get("ok", false))
	state.gates = gates
	return state

func compact(state: Dictionary) -> Dictionary:
	return state.duplicate(true)

func finish() -> void:
	var report: Dictionary = {"valid": failures.is_empty(), "failures": failures, "scope": VOYAGE_SCOPE, "actualGameplayComplete": false, "step": "doc38-step4-endgame-slice", "gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "displayServer": DisplayServer.get_name(), "audioMuted": AudioServer.is_bus_mute(0), "seed": SEED, "fixedStep": STEP, "checks": checks, "captures": captures, "evidence_scope": "Real restore of a prepared T10 checkpoint through the menu continue entry, then the three-gate ending driven by real UI buttons to the campaign ending. Not a human keyboard playthrough of the full voyage."}
	if own_output:
		var file := FileAccess.open(output + "/capture-result.json", FileAccess.WRITE)
		if file: file.store_string(JSON.stringify(report, "", false, true)); file.close()
		else: check(false, "write report")
	if is_instance_valid(main): main.free()
	await frames(2)
	print("STORY_ENDGAME_GPU captures=", captures.size(), " samples=", 3, " accepted_steps=", 90, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
