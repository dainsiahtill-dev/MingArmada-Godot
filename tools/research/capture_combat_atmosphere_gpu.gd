extends SceneTree
## Real menu/laboratory, scripted 60 Hz steps, GPU image every four accepted ticks.
## Fifteen samples per accepted second; rendering/export wall time is not game FPS.
const Main = preload("res://game/scenes/main/main_scene.tscn")
const STEP := 1.0 / 60.0
const TICKS_PER_FRAME := 4
const MAX_FRAMES := 600
const SEED := 1661
const CASES := [
	{"id": "calm-baseline", "enabled": false, "wind": "calm", "camera_mode": "battle"},
	{"id": "calm-candidate", "enabled": true, "wind": "calm", "camera_mode": "battle"},
	{"id": "crosswind-candidate", "enabled": true, "wind": "crosswind", "camera_mode": "battle"},
	{"id": "near-candidate", "enabled": true, "wind": "calm", "camera_mode": "near"}
]
var failures: Array = []
var captures: Array = []
var sequences: Array = []
var checks: Array = []
var cases: Array = []
var output := ""
var own_output := false
var main: Node
var lab: Control
var baseline: Dictionary = {}
var accepted_steps := 0

func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> bool:
	if not value:
		failures.append(message)
		printerr("FAIL COMBAT ATMOSPHERE GPU: ", message)
	return value
func frames(count: int) -> void:
	for _index in count: await process_frame
func normal(path: String) -> String: return path.replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
func inside(path: String, parent: String) -> bool: return not parent.is_empty() and normal(path).begins_with(normal(parent) + "/")
func near(a: float, b: float) -> bool: return absf(a - b) <= 0.000001
func digest(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
func state_digest(value: Dictionary) -> String: return digest(JSON.stringify(value,"",false,true).to_utf8_buffer())

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output=") and output.is_empty(): output = arg.trim_prefix("--output=")
		else: check(false, "unknown or duplicate argument")
	var expected := OS.get_environment("COMBAT_ATMOSPHERE_CAPTURE_OUTPUT")
	var profile := OS.get_environment("COMBAT_ATMOSPHERE_PROFILE_ROOT")
	var original := OS.get_environment("COMBAT_ATMOSPHERE_ORIGINAL_APPDATA")
	var app := OS.get_environment("APPDATA")
	var local := OS.get_environment("LOCALAPPDATA")
	check(not expected.is_empty() and output.begins_with("res://docs/research/evidence/naval-combat-atmosphere/") and output.ends_with("/frames") and not output.contains("..") and not output.contains("\\") and normal(ProjectSettings.globalize_path(output)) == normal(expected) and not DirAccess.dir_exists_absolute(expected) and not FileAccess.file_exists(expected), "fresh confined output")
	check(not original.is_empty() and inside(app, profile) and inside(local, profile) and normal(app) != normal(local) and inside(ProjectSettings.globalize_path("user://"), app) and not inside(profile, original) and not inside(original, profile) and normal(profile) != normal(original), "isolated actual userdata")
	check(DisplayServer.get_name() != "headless", "non-headless graphics required")
	if DisplayServer.get_name() != "headless":
		var gpu := RenderingServer.get_video_adapter_name().to_lower()
		check(not gpu.is_empty() and not "llvmpipe" in gpu and not "swiftshader" in gpu and not "software" in gpu, "hardware graphics required")
	if not failures.is_empty():
		print("COMBAT_ATMOSPHERE_GPU_GUARD_REJECTED failures=", failures.size())
		quit(2)
		return
	if not check(DirAccess.make_dir_recursive_absolute(expected) == OK, "create fresh output"): quit(2); return
	own_output = true
	seed(SEED)
	AudioServer.set_bus_mute(0, true)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	root.content_scale_size = Vector2i(1600, 900)
	root.size = Vector2i(1600, 900)
	await frames(4)
	main = Main.instantiate()
	root.add_child(main)
	await frames(4)
	await RenderingServer.frame_post_draw
	if not save_image(root.get_texture().get_image(), "menu-before.png", "menu", "", {}): await finish(); return
	var button: Button = main.menu.find_child("laboratory", true, false)
	if not check(is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled, "actual main menu laboratory button"): await finish(); return
	button.pressed.emit()
	for _index in 120:
		await process_frame
		if is_instance_valid(main.current_scene): break
	lab = main.current_scene
	if not check(is_instance_valid(lab) and lab.startup_receipt.get("ok", false), "laboratory opened from actual menu"): await finish(); return
	lab.set_process(false)
	if not check(lab.select_topic("naval-combat-atmosphere"), "registered atmosphere topic selectable"): await finish(); return
	checks.append({"name": "real_entry", "input": "ordinary menu button signal followed by registered topic selection", "ok": true})
	for fixture: Dictionary in CASES:
		if not await run_case(fixture): await finish(); return
	var owned_demo: WeakRef = weakref(lab._demo)
	main._return_from_scene(lab)
	lab = null
	await frames(4)
	check(owned_demo.get_ref() == null, "leaving actual laboratory releases the demo and owned world")
	checks.append({"name": "dispose", "released": owned_demo.get_ref() == null})
	await RenderingServer.frame_post_draw
	save_image(root.get_texture().get_image(), "menu-returned.png", "menu", "", {})
	await finish()

func run_case(fixture: Dictionary) -> bool:
	var id: String = fixture.id
	var options: Dictionary = fixture.duplicate(true)
	options.erase("id")
	options.paused = true
	options.seed = SEED
	var started: Dictionary = lab.start_demo(options)
	checks.append({"name": "case_entry", "case": id, "receipt": started.duplicate(true)})
	if not check(started.get("ok", false), id + " starts through actual laboratory lifecycle"): return false
	await frames(5)
	var state: Dictionary = lab._demo.inspection_snapshot()
	var strip: Control = lab._demo.get("_strip")
	if not check(is_instance_valid(strip) and strip.size.y<=90.0,"HUD leaves the actual battle visible"): return false
	if not check(valid_state(state, fixture), id + " initial fixture"): return false
	if not await sample_frame(fixture, 0, 0): return false
	if not save_image(root.get_texture().get_image(), id + "-page-start.png", "page", id, state): return false
	var terminal_native := ""
	var paused_wreck := false
	var largest_smoke := 0
	var largest_flame := 0
	var frame_count := 0
	var first_terminal_tick := -1
	for frame in range(1, MAX_FRAMES + 1):
		var advanced := 0
		for _index in TICKS_PER_FRAME:
			var before: Dictionary = lab._demo.inspection_snapshot()
			if before.get("finished", false): break
			var receipt: Dictionary = lab.step_demo()
			if not check(receipt.get("ok", false), id + " host single-step accepted"): return false
			var after: Dictionary = lab._demo.inspection_snapshot()
			if not check(int(after.tick) == int(before.tick) + 1 and valid_state(after, fixture), id + " accepted native/tail step has valid state"): return false
			accepted_steps += 1
			advanced += 1
			if after.native.status in ["victory", "defeat"]:
				var current := state_digest(after.native)
				if terminal_native.is_empty(): terminal_native = current; first_terminal_tick = int(after.tick)
				if not check(current == terminal_native, id + " terminal visual tail freezes entire native authority"): return false
			if after.get("finished", false): break
		if advanced == 0: break
		if not await sample_frame(fixture, frame, advanced): return false
		frame_count = frame
		state = lab._demo.inspection_snapshot()
		largest_smoke = maxi(largest_smoke, int(state.atmosphere.active_smoke))
		largest_flame = maxi(largest_flame, int(state.atmosphere.active_flames))
		if fixture.enabled and not paused_wreck and state.event_counts.get("destruction-explosion", 0) > 0 and state.atmosphere.active_flames > 0:
			if not await pause_probe(id): return false
			paused_wreck = true
		if frame % 60 == 0: print("COMBAT_ATMOSPHERE_GPU_PROGRESS case=", id, " sample=", frame, " tick=", state.tick, " native=", state.native.time, " visual=", state.visual_time)
		if state.get("finished", false): break
	var native: Dictionary = state.native
	check(native.status in ["victory", "defeat"] and state.finished and near(float(state.tail.elapsed), 10.0), id + " completes real terminal result and official ten-second tail")
	check(int(state.event_counts.fire) > 0 and int(state.event_counts.hit) > 0 and int(state.event_counts.sink) > 0 and int(state.event_counts.get("destruction-explosion", 0)) > 0, id + " real fire hit sink and ShipDamage destruction observed")
	check(state.atmosphere.particles.is_empty(), id + " finite particles expire before tail stops")
	check(not fixture.enabled or paused_wreck, id + " active wreck flame has a paused GPU probe")
	check(not fixture.enabled or largest_smoke > 0 and largest_flame > 0, id + " candidate actually emits smoke and fire")
	if not save_image(root.get_texture().get_image(), id + "-page-end.png", "page", id, state): return false
	cases.append({"id": id, "options": options, "sampled_frames": frame_count + 1, "accepted_tick": state.tick, "first_terminal_tick": first_terminal_tick, "native_time": native.time, "visual_time": state.visual_time, "tail_elapsed": state.tail.elapsed, "terminal_native_sha256": terminal_native, "event_counts": state.event_counts.duplicate(true), "largest_smoke": largest_smoke, "largest_flame": largest_flame, "paused_wreck": paused_wreck, "finished": state.finished})
	return failures.is_empty()

func valid_state(state: Dictionary, fixture: Dictionary) -> bool:
	if not state.get("ready", false) or not state.get("paused", false) or not near(float(state.get("fixed_step", 0.0)), STEP): return false
	if state.parameters.seed != SEED or state.parameters.enabled != fixture.enabled or state.parameters.wind != fixture.wind or state.camera_mode != fixture.camera_mode: return false
	var native: Dictionary = state.native
	var tail: Dictionary = state.tail
	if not near(float(state.visual_time), float(native.time) + float(tail.elapsed)) or int(native.tick) > int(state.tick): return false
	if native.ships.size() != 2 or not near(float(native.wind.speed), 0.0 if fixture.wind == "calm" else 12.0): return false
	var atmosphere: Dictionary = state.atmosphere
	if not atmosphere.ready or atmosphere.enabled != fixture.enabled or int(atmosphere.draw_calls) > 3 or atmosphere.particles.size() > int(atmosphere.capacity): return false
	if not fixture.enabled and (not atmosphere.particles.is_empty() or atmosphere.draw_calls != 0): return false
	for particle: Dictionary in atmosphere.particles:
		if particle.position.size() != 3 or not particle.position.all(func(v: Variant) -> bool: return (v is int or v is float) and is_finite(float(v))): return false
		if not is_finite(float(particle.alpha)) or not is_finite(float(particle.size)) or float(particle.born) > float(state.visual_time) or float(particle.expires) <= float(state.visual_time) or float(particle.expires) > float(particle.born) + 9.000001: return false
	return true

func sample_frame(fixture: Dictionary, index: int, advanced: int) -> bool:
	await process_frame
	await RenderingServer.frame_post_draw
	var state: Dictionary = lab._demo.inspection_snapshot()
	var viewport: SubViewport = lab.find_child("ExperimentViewport", true, false)
	if not check(is_instance_valid(viewport) and valid_state(state, fixture), String(fixture.id) + " same-frame state matches rendered viewport"): return false
	var native_hash := state_digest(state.native)
	var same_native := true
	if fixture.id == "calm-baseline": baseline[int(state.tick)] = native_hash
	elif fixture.wind == "calm":
		same_native = baseline.get(int(state.tick), "") == native_hash
		if not check(same_native, String(fixture.id) + " matches baseline full native state at accepted tick " + str(state.tick)): return false
	var file := "%s-%03d.png" % [fixture.id, index]
	sequences.append({"case": fixture.id, "sample": index, "file": file, "tick": state.tick, "native_tick": state.native.tick, "native_time": state.native.time, "visual_time": state.visual_time, "tail_elapsed": state.tail.elapsed, "ticks_advanced": advanced, "native_sha256": native_hash, "same_calm_authority": same_native, "active_smoke": state.atmosphere.active_smoke, "active_flames": state.atmosphere.active_flames, "active_embers": state.atmosphere.active_embers, "event_counts": state.event_counts.duplicate(true), "projected_flames": projected_flames(state, viewport)})
	return save_image(viewport.get_texture().get_image(), file, "experiment", String(fixture.id), state)

func projected_flames(state: Dictionary, viewport: SubViewport) -> Array:
	var result: Array = []
	var camera: Camera3D = lab._demo.get("_sea").camera
	var rect := Rect2(Vector2.ZERO, Vector2(viewport.size))
	for particle: Dictionary in state.atmosphere.particles:
		if particle.kind != "flame": continue
		var point := Vector3(float(particle.position[0]), float(particle.position[1]), float(particle.position[2]))
		if camera.is_position_behind(point): continue
		var screen := camera.unproject_position(point)
		if rect.has_point(screen): result.append({"id": particle.id, "pixel": [screen.x, screen.y], "scope": "centre projects inside viewport; opaque occlusion still requires image review"})
	return result

func pause_probe(id: String) -> bool:
	var before: Dictionary = lab._demo.inspection_snapshot()
	var viewport: SubViewport = lab.find_child("ExperimentViewport", true, false)
	if not save_image(viewport.get_texture().get_image(), id + "-pause-before.png", "pause", id, before): return false
	await frames(8)
	await RenderingServer.frame_post_draw
	var after: Dictionary = lab._demo.inspection_snapshot()
	var unchanged: bool = before == after
	checks.append({"name": "wreck_pause", "case": id, "frames": 8, "tick": before.tick, "unchanged": unchanged, "native_sha256": state_digest(after.native), "particles_sha256": digest(JSON.stringify(after.atmosphere.particles).to_utf8_buffer())})
	if not check(unchanged, id + " paused rendered frames freeze authority tail and particles"): return false
	return save_image(viewport.get_texture().get_image(), id + "-pause-after.png", "pause", id, after)

func save_image(image: Image, file: String, kind: String, case_id: String, state: Dictionary) -> bool:
	if not check(image != null and not image.is_empty(), "hardware framebuffer exists: " + file): return false
	image.convert(Image.FORMAT_RGBA8)
	var path := output + "/" + file
	if not check(not FileAccess.file_exists(path) and image.save_png(path) == OK, "fresh PNG write: " + file): return false
	captures.append({"file": file, "kind": kind, "case": case_id, "viewport": [image.get_width(), image.get_height()], "sha256": FileAccess.get_sha256(path), "framebuffer_sha256": digest(image.get_data()), "framebuffer_format": "RGBA8", "snapshot": state.duplicate(true)})
	return true

func finish() -> void:
	var report := {"valid": failures.is_empty(), "failures": failures, "engine": Engine.get_version_info(), "gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "displayServer": DisplayServer.get_name(), "fixedStep": STEP, "ticksPerFrame": TICKS_PER_FRAME, "nominalSamplesPerAcceptedSecond": 15, "maximumSamplesPerCase": MAX_FRAMES + 1, "seed": SEED, "audioMuted": AudioServer.is_bus_mute(0), "acceptedSteps": accepted_steps, "cases": cases, "sequences": sequences, "captures": captures, "checks": checks, "scope": "Scripted ordinary menu to registered isolated laboratory. Four accepted 60 Hz steps per GPU sample (15 samples per accepted second), including an official terminal visual tail that freezes native authority. PNG and state proof require art review. No manual play, real-time FPS, per-physics-step imagery, volumetric renderer or production integration claim."}
	if own_output:
		var path := output + "/capture-result.json"
		if check(not FileAccess.file_exists(path), "fresh report"):
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file: file.store_string(JSON.stringify(report,"",false,true)); file.close()
			else: check(false, "report write")
	if is_instance_valid(main): main.free()
	await frames(2)
	print("COMBAT_ATMOSPHERE_GPU captures=", captures.size(), " samples=", sequences.size(), " accepted_steps=", accepted_steps, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
