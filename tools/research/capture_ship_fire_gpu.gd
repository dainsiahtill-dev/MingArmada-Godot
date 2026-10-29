extends SceneTree
## Actual Main -> Laboratory -> registered controlled ignition. Host steps only.
## Twelve accepted 60 Hz steps per GPU sample; export wall time is not game FPS.
const Main = preload("res://game/scenes/main/main_scene.tscn")
const STEP := 1.0 / 60.0
const TICKS_PER_SAMPLE := 12
const MAX_SAMPLES := 240
const SEED := 1661
const SCOPE := "controlled ignition candidate; no live ballistic/campaign/production claim"
var failures: Array = []
var captures: Array = []
var sequences: Array = []
var checks: Array = []
var cases: Array = []
var output := ""
var own_output := false
var main: Node
var lab: Control
var accepted_steps := 0

func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> bool:
	if not value:
		failures.append(message)
		printerr("FAIL SHIP FIRE GPU: ", message)
	return value
func frames(count: int) -> void:
	for _i in count: await process_frame
func normal(path: String) -> String: return path.replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
func inside(path: String, parent: String) -> bool: return not parent.is_empty() and normal(path).begins_with(normal(parent) + "/")
func near(a: float, b: float) -> bool: return absf(a - b) <= 0.000001
func digest(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256); context.update(bytes)
	return context.finish().hex_encode()
func state_digest(value: Dictionary) -> String: return digest(JSON.stringify(value, "", false, true).to_utf8_buffer())
func authority_digest(state: Dictionary) -> String:
	return state_digest({"tick":state.tick,"time":state.time,"lanes":state.lanes,"context":state.context,"template":state.template,"visual":state.visual})

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output=") and output.is_empty(): output = arg.trim_prefix("--output=")
		else: check(false, "unknown or duplicate argument")
	var expected := OS.get_environment("SHIP_FIRE_CAPTURE_OUTPUT")
	var profile := OS.get_environment("SHIP_FIRE_PROFILE_ROOT")
	var original := OS.get_environment("SHIP_FIRE_ORIGINAL_APPDATA")
	var app := OS.get_environment("APPDATA")
	var local := OS.get_environment("LOCALAPPDATA")
	check(not expected.is_empty() and output.begins_with("res://docs/research/evidence/ship-fire-control/") and output.ends_with("/frames") and not output.contains("..") and not output.contains("\\") and normal(ProjectSettings.globalize_path(output)) == normal(expected) and not DirAccess.dir_exists_absolute(expected) and not FileAccess.file_exists(expected), "fresh confined output")
	check(not original.is_empty() and inside(app, profile) and inside(local, profile) and normal(app) != normal(local) and inside(ProjectSettings.globalize_path("user://"), app) and not inside(profile, original) and not inside(original, profile) and normal(profile) != normal(original), "isolated actual userdata")
	check(DisplayServer.get_name() != "headless", "non-headless graphics required")
	if DisplayServer.get_name() != "headless":
		var gpu := RenderingServer.get_video_adapter_name().to_lower()
		check(not gpu.is_empty() and not "llvmpipe" in gpu and not "swiftshader" in gpu and not "software" in gpu, "hardware graphics required")
	if not failures.is_empty():
		print("SHIP_FIRE_GPU_GUARD_REJECTED failures=", failures.size())
		quit(2); return
	if not check(DirAccess.make_dir_recursive_absolute(expected) == OK, "create fresh output"): quit(2); return
	own_output = true
	seed(SEED); AudioServer.set_bus_mute(0, true)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	root.content_scale_size = Vector2i(1600, 900); root.size = Vector2i(1600, 900)
	await frames(4)
	main = Main.instantiate(); root.add_child(main)
	await frames(4); await RenderingServer.frame_post_draw
	if not save_image(root.get_texture().get_image(), "menu-before.png", "menu", "", -1, 0, {}): await finish(); return
	var button: Button = main.menu.find_child("laboratory", true, false)
	if not check(is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled, "actual main menu laboratory button"): await finish(); return
	button.pressed.emit()
	for _i in 120:
		await process_frame
		if is_instance_valid(main.current_scene): break
	lab = main.current_scene
	if not check(is_instance_valid(lab) and lab.startup_receipt.get("ok", false), "laboratory opened from actual menu"): await finish(); return
	lab.set_process(false)
	if not check(lab.select_topic("ship-fire-control"), "registered ship-fire-control selectable"): await finish(); return
	checks.append({"name":"real_entry","ok":true,"input":"actual menu button signal and registered topic selection"})
	if not await run_case("default", 24, MAX_SAMPLES, true): await finish(); return
	if not await run_case("low-supplies", 4, 40, false): await finish(); return
	var exhausted: Dictionary = lab._demo.inspection_snapshot()
	check(exhausted.lanes.candidate.fireControl.supplies == 0 and exhausted.lanes.candidate.fireControl.heat > 0.0 and exhausted.lanes.candidate.workSeconds > 0.0, "four preparation shares exhaust while controlled fire remains active at eight seconds")
	# Exercise the actual host reset path, with explicit restoration of the
	# declared normal inventory; no stock appears merely because time passed.
	lab._reset_demo({"supplies":24, "paused":true, "camera_mode":"overview"})
	await frames(3); await RenderingServer.frame_post_draw
	var reset: Dictionary = lab._demo.inspection_snapshot()
	check(reset.tick == 0 and reset.lanes.candidate.fireControl.supplies == 24 and reset.lanes.candidate.suppliesSpent == 0 and reset.lanes.candidate.hull == 100.0 and reset.lanes.candidate.workSeconds == 0.0, "explicit host reset restores fresh twenty-four-share experiment")
	checks.append({"name":"reset_inventory","before":compact(exhausted),"after":compact(reset),"ok":failures.is_empty()})
	save_image(lab._viewport.get_texture().get_image(), "reset-restored.png", "reset", "reset", 0, 0, reset)
	var demo_ref: WeakRef = weakref(lab._demo)
	var sea_ref: WeakRef = weakref(lab._demo.get("_sea"))
	var fire_ref: WeakRef = weakref(lab._demo.get("_fire_view"))
	main._return_from_scene(lab); lab = null
	await frames(4)
	var released: bool = demo_ref.get_ref() == null and sea_ref.get_ref() == null and fire_ref.get_ref() == null
	check(released, "leaving actual laboratory releases demo sea and fire view")
	checks.append({"name":"dispose","released":released})
	await RenderingServer.frame_post_draw
	save_image(root.get_texture().get_image(), "menu-returned.png", "menu", "", -1, 0, {})
	await finish()

func run_case(id: String, supplies: int, limit: int, require_completion: bool) -> bool:
	var options := {"payload":"thorn-ball","firefighters":4,"supplies":supplies,"moisture":"dry","load":"clear","paused":true,"camera_mode":"overview","seed":SEED}
	if not check(lab.start_demo(options).get("ok", false), id + " starts registered controlled experiment"): return false
	await frames(3)
	if not await sample_frame(id, 0, 0): return false
	var state: Dictionary = lab._demo.inspection_snapshot()
	if not save_image(root.get_texture().get_image(), id + "-page.png", "page", id, 0, 0, state): return false
	var active_pause := false
	var extinguished_pause := false
	var completed := false
	var count := 0
	for index in range(1, limit + 1):
		for _i in TICKS_PER_SAMPLE:
			if not check(lab.step_demo().get("ok", false), id + " actual sixty-hertz host step"): return false
			accepted_steps += 1
		if not await sample_frame(id, index, TICKS_PER_SAMPLE): return false
		count = index
		state = lab._demo.inspection_snapshot()
		if id == "default" and index == 5:
			if not check(state.fire_view.living_fires == 2 and state.fire_view.active_flames > 0, "active controlled heat has live flame GPU observation"): return false
			if not await pause_probe(id, "active", index): return false
			active_pause = true
			if not await camera_pair(id, "active", index): return false
		if id == "default" and not extinguished_pause and both_cold(state):
			if not await pause_probe(id, "extinguished", index): return false
			extinguished_pause = true
			if not await camera_pair(id, "extinguished", index): return false
		if require_completion and fully_finished(state): completed = true; break
		if index % 25 == 0: print("SHIP_FIRE_GPU_PROGRESS case=", id, " sample=", index, " time=", state.time)
	if require_completion:
		check(completed and active_pause and extinguished_pause, id + " reaches cold fire returned crew and fully expired VFX within forty-eight seconds")
		check(state.lanes.candidate.hull > state.lanes.baseline.hull and state.lanes.candidate.hull < 100.0, "prepared suppression limits controlled hull loss without healing")
	else: check(state.tick == 480 and near(state.time, 8.0), "low-supply observation covers the first eight accepted seconds")
	cases.append({"id":id,"options":options,"samples":count + 1,"last_tick":state.tick,"last_time":state.time,"completed":completed,"active_pause":active_pause,"extinguished_pause":extinguished_pause,"final":compact(state)})
	return failures.is_empty()

func both_cold(state: Dictionary) -> bool:
	return state.lanes.baseline.fireControl.heat == 0.0 and state.lanes.candidate.fireControl.heat == 0.0
func fully_finished(state: Dictionary) -> bool:
	if not both_cold(state): return false
	for id: String in ["baseline", "candidate"]:
		if state.lanes[id].fireControl.transferTicks != 0 or state.lanes[id].reservedCrew != 0: return false
	var view: Dictionary = state.fire_view
	return view.living_fires == 0 and view.reserved_particles == 0 and view.active_smoke == 0 and view.active_flames == 0 and view.active_embers == 0

func valid_state(state: Dictionary) -> bool:
	if not state.get("ready", false) or not state.get("paused", false) or state.get("scope") != SCOPE or not state.get("error", "").is_empty(): return false
	if state.parameters.seed != SEED or state.parameters.payload != "thorn-ball" or state.parameters.firefighters != 4 or state.parameters.moisture != "dry" or state.parameters.load != "clear": return false
	if not near(state.fixed_step, STEP) or not near(state.time, int(state.tick) * STEP) or state.template.tick != 0 or state.template.time != 0.0 or not state.events.is_empty() or state.resources.storage != 0: return false
	if state.visual.tick != state.tick or not near(state.visual.time, state.time) or state.visual.ships.size() != 2: return false
	for ship: Dictionary in state.visual.ships:
		var lane: Dictionary = state.lanes[ship.id]
		if ship.hull != lane.hull or ship.sail != lane.sail or ship.crew != lane.crew or ship.fireControl != lane.fireControl: return false
		if not lane.crew is int or not lane.fireControl.supplies is int or lane.crew + lane.damage.crew != lane.maxCrew or lane.fireControl.supplies + lane.suppliesSpent != state.parameters.supplies: return false
		if not near(lane.hull + lane.damage.hull, 100.0) or not near(lane.sail + lane.damage.sail, 100.0): return false
	var fire: Dictionary = state.fire_view
	return fire.ready and fire.enabled and near(fire.time, state.time) and fire.draw_calls <= 3 and fire.particles.size() <= fire.capacity

func sample_frame(id: String, index: int, steps: int) -> bool:
	await process_frame; await RenderingServer.frame_post_draw
	var state: Dictionary = lab._demo.inspection_snapshot()
	if not check(valid_state(state), id + " same-frame controlled state matches real viewport"): return false
	var strip: Control = lab._demo.get("_strip")
	if not check(strip.size.y <= 160.0 and strip.size.y < lab._viewport.size.y * .35, "bounded fire telemetry leaves ship world visible"): return false
	var file := "%s-%03d.png" % [id, index]
	sequences.append({"case":id,"sample":index,"file":file,"steps":steps,"tick":state.tick,"time":state.time,"camera_mode":state.camera_mode,"state_sha256":state_digest(state),"lanes":state.lanes.duplicate(true),"fire_view":fire_counts(state.fire_view)})
	return save_image(lab._viewport.get_texture().get_image(), file, "experiment", id, index, steps, state)

func pause_probe(id: String, phase: String, index: int) -> bool:
	var before: Dictionary = lab._demo.inspection_snapshot()
	if not save_image(lab._viewport.get_texture().get_image(), id + "-" + phase + "-pause-before.png", "pause", id, index, 0, before): return false
	await frames(8); await RenderingServer.frame_post_draw
	var after: Dictionary = lab._demo.inspection_snapshot()
	var unchanged := before == after
	checks.append({"name":"pause","phase":phase,"case":id,"sample":index,"tick":before.tick,"time":before.time,"frames":8,"unchanged":unchanged,"before_sha256":state_digest(before),"after_sha256":state_digest(after)})
	if not check(unchanged, phase + " fire pause freezes all accepted state through eight rendered frames"): return false
	return save_image(lab._viewport.get_texture().get_image(), id + "-" + phase + "-pause-after.png", "pause", id, index, 0, after)

func camera_pair(id: String, phase: String, index: int) -> bool:
	var before: Dictionary = lab._demo.inspection_snapshot()
	var hash_before := authority_digest(before)
	lab._demo.set_camera_mode("near")
	await frames(2); await RenderingServer.frame_post_draw
	var after: Dictionary = lab._demo.inspection_snapshot()
	var unchanged := hash_before == authority_digest(after)
	checks.append({"name":"camera_pair","phase":phase,"case":id,"sample":index,"tick":before.tick,"time":before.time,"unchanged":unchanged,"overview_file":"%s-%03d.png" % [id,index],"near_file":id + "-" + phase + "-near.png","before_authority_sha256":hash_before,"after_authority_sha256":authority_digest(after)})
	if not check(unchanged, "same-tick near camera preserves controlled accounts"): return false
	if not save_image(lab._viewport.get_texture().get_image(), id + "-" + phase + "-near.png", "detail", id, index, 0, after): return false
	lab._demo.set_camera_mode("overview")
	await frames(2)
	return check(hash_before == authority_digest(lab._demo.inspection_snapshot()), "restoring overview does not advance controlled fire")

func fire_counts(view: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: String in ["ready","enabled","time","living_fires","active_smoke","active_flames","active_embers","reserved_particles","capacity","draw_calls","dropped","underwater_stopped","live_emission_policy"]: result[key] = view.get(key)
	return result
func compact(state: Dictionary) -> Dictionary:
	if state.is_empty(): return {}
	var visual := {"tick":state.visual.tick,"time":state.visual.time,"battleId":state.visual.battleId,"ships":[]}
	for ship: Dictionary in state.visual.ships:
		visual.ships.append({"id":ship.id,"hull":ship.hull,"sail":ship.sail,"crew":ship.crew,"fireControl":ship.fireControl.duplicate(true),"visual":ship.visual.duplicate(true)})
	return {"scope":state.scope,"topic":state.topic,"ready":state.ready,"paused":state.paused,"tick":state.tick,"time":state.time,"fixed_step":state.fixed_step,"parameters":state.parameters.duplicate(true),"camera_mode":state.camera_mode,"camera":state.camera.duplicate(true),"lanes":state.lanes.duplicate(true),"context":state.context.duplicate(true),"template":{"tick":state.template.tick,"time":state.template.time,"sha256":state_digest(state.template)},"visual":visual,"events":state.events.duplicate(true),"resources":state.resources.duplicate(true),"fire_view":fire_counts(state.fire_view),"error":state.error}

func save_image(image: Image, file: String, kind: String, case_id: String, index: int, steps: int, state: Dictionary) -> bool:
	if not check(image != null and not image.is_empty(), "hardware framebuffer exists: " + file): return false
	image.convert(Image.FORMAT_RGBA8)
	var path := output + "/" + file
	if not check(not FileAccess.file_exists(path) and image.save_png(path) == OK, "fresh PNG write: " + file): return false
	captures.append({"file":file,"kind":kind,"case":case_id,"sample":index,"steps":steps,"tick":state.get("tick",0),"time":state.get("time",0.0),"viewport":[image.get_width(),image.get_height()],"sha256":FileAccess.get_sha256(path),"framebuffer_sha256":digest(image.get_data()),"framebuffer_format":"RGBA8","full_state_sha256":state_digest(state),"snapshot":compact(state)})
	return true

func finish() -> void:
	var report := {"valid":failures.is_empty(),"failures":failures,"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"displayServer":DisplayServer.get_name(),"fixedStep":STEP,"ticksPerSample":TICKS_PER_SAMPLE,"nominalSamplesPerAcceptedSecond":5,"maximumSamplesPerCase":MAX_SAMPLES + 1,"maximumDefaultAcceptedSeconds":48,"seed":SEED,"audioMuted":AudioServer.is_bus_mute(0),"acceptedSteps":accepted_steps,"cases":cases,"sequences":sequences,"captures":captures,"checks":checks,"scope":SCOPE,"evidence_scope":"Scripted actual Main/Laboratory entry. Controlled ignition and experiment accounts only; five GPU samples per accepted second. Full-precision JSON and per-image PNG/RGBA hashes. No manual play, real-time game FPS, per-tick image, live ballistic, campaign or production claim."}
	if own_output:
		var path := output + "/capture-result.json"
		if check(not FileAccess.file_exists(path), "fresh capture report"):
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file: file.store_string(JSON.stringify(report, "", false, true)); file.close()
			else: check(false, "capture report write")
	if is_instance_valid(main): main.free()
	await frames(2)
	print("SHIP_FIRE_GPU captures=", captures.size(), " samples=", sequences.size(), " accepted_steps=", accepted_steps, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
