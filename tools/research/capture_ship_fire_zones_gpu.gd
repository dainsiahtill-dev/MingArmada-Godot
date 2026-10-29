extends "res://tools/research/capture_ship_fire_gpu.gd"
## Same registered topic, fixed host cadence and original capture guards.
## This only observes controlled ignition; no production/campaign acceptance.
const Spread = preload("res://modules/naval_simulation/combat/fire_spread.gd")

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output=") and output.is_empty(): output = arg.trim_prefix("--output=")
		else: check(false, "unknown or duplicate argument")
	var expected: String = OS.get_environment("SHIP_FIRE_CAPTURE_OUTPUT")
	var profile: String = OS.get_environment("SHIP_FIRE_PROFILE_ROOT")
	var original: String = OS.get_environment("SHIP_FIRE_ORIGINAL_APPDATA")
	var app: String = OS.get_environment("APPDATA")
	var local: String = OS.get_environment("LOCALAPPDATA")
	check(not expected.is_empty() and output.begins_with("res://docs/research/evidence/ship-fire-control/") and output.ends_with("/frames") and not output.contains("..") and not output.contains("\\") and normal(ProjectSettings.globalize_path(output)) == normal(expected) and not DirAccess.dir_exists_absolute(expected) and not FileAccess.file_exists(expected), "fresh confined output")
	check(not original.is_empty() and inside(app, profile) and inside(local, profile) and normal(app) != normal(local) and inside(ProjectSettings.globalize_path("user://"), app) and not inside(profile, original) and not inside(original, profile) and normal(profile) != normal(original), "isolated actual userdata")
	check(DisplayServer.get_name() != "headless", "non-headless graphics required")
	if DisplayServer.get_name() != "headless":
		var gpu: String = RenderingServer.get_video_adapter_name().to_lower()
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
	if not check(lab.select_topic("ship-fire-control"), "original registered topic selectable"): await finish(); return
	checks.append({"name":"real_entry", "ok":true, "input":"actual menu button signal and original registered topic selection"})
	for spec: Dictionary in [{"id":"stern","supplies":24,"zone":"stern","limit":240,"complete":true}, {"id":"bow","supplies":24,"zone":"bow","limit":40,"complete":false}, {"id":"mid","supplies":24,"zone":"mid","limit":40,"complete":false}, {"id":"low-supplies","supplies":4,"zone":"stern","limit":40,"complete":false}]:
		if not await run_zone_case(spec): await finish(); return
	var exhausted: Dictionary = lab._demo.inspection_snapshot()
	check(exhausted.lanes.candidate.fireControl.supplies == 0 and total(exhausted.lanes.candidate) > 0.0 and exhausted.lanes.candidate.workSeconds > 0.0, "exhaustion stops effective work while fire remains")
	lab._reset_demo({"supplies":24, "paused":true, "camera_mode":"overview"})
	await frames(3); await RenderingServer.frame_post_draw
	var reset: Dictionary = lab._demo.inspection_snapshot()
	check(reset.tick == 0 and reset.lanes.candidate.fireControl.supplies == 24 and reset.lanes.candidate.spreadCount == 0 and reset.lanes.candidate.spreadEvents.is_empty() and reset.lanes.candidate.workSeconds == 0.0 and reset.lanes.candidate.hull == 100.0, "explicit reset restores resources and clears spatial ledger")
	checks.append({"name":"reset_inventory", "before":compact(exhausted), "after":compact(reset), "ok":failures.is_empty()})
	save_image(lab._viewport.get_texture().get_image(), "reset-restored.png", "reset", "reset", 0, 0, reset)
	var demo_ref: WeakRef = weakref(lab._demo)
	var sea_ref: WeakRef = weakref(lab._demo.get("_sea"))
	var fire_ref: WeakRef = weakref(lab._demo.get("_fire_view"))
	main._return_from_scene(lab); lab = null
	await frames(4)
	var released: bool = demo_ref.get_ref() == null and sea_ref.get_ref() == null and fire_ref.get_ref() == null
	check(released, "actual laboratory exit releases owned world")
	checks.append({"name":"dispose", "released":released})
	await RenderingServer.frame_post_draw
	save_image(root.get_texture().get_image(), "menu-returned.png", "menu", "", -1, 0, {})
	await finish()

func run_zone_case(spec: Dictionary) -> bool:
	var id: String = spec.id
	var options: Dictionary = {"fire_model":"zones", "ignition_zone":spec.zone, "payload":"thorn-ball", "firefighters":4, "supplies":spec.supplies, "moisture":"dry", "load":"clear", "paused":true, "camera_mode":"overview", "seed":SEED}
	if not check(lab.start_demo(options).get("ok", false), id + " starts registered spatial candidate"): return false
	await frames(3)
	if not await sample_frame(id, 0, 0): return false
	var state: Dictionary = lab._demo.inspection_snapshot()
	if not save_image(root.get_texture().get_image(), id + "-page.png", "page", id, 0, 0, state): return false
	var active_pause: bool = false
	var extinguished_pause: bool = false
	var spread_pause: bool = false
	var completed: bool = false
	var count: int = 0
	for index: int in range(1, int(spec.limit) + 1):
		for _i in TICKS_PER_SAMPLE:
			if not check(lab.step_demo().get("ok", false), id + " actual host step"): return false
			accepted_steps += 1
		if not await sample_frame(id, index, TICKS_PER_SAMPLE): return false
		count = index
		state = lab._demo.inspection_snapshot()
		if id == "stern" and index == 5:
			if not check(state.fire_view.living_fires == 2 and state.fire_view.active_flames > 0, "active zone fire observed by actual GPU"): return false
			if not await pause_probe(id, "active", index) or not await camera_pair(id, "active", index): return false
			active_pause = true
		if id == "stern" and index == 125:
			if not check(state.lanes.baseline.spreadCount == 2 and state.fire_view.burning_zones == 3, "unattended flame reaches all three real-deck regions"): return false
			if not await pause_probe(id, "spread", index) or not await baseline_detail(id, index): return false
			spread_pause = true
		if id == "stern" and not extinguished_pause and both_cold(state):
			if not await pause_probe(id, "extinguished", index) or not await camera_pair(id, "extinguished", index): return false
			extinguished_pause = true
		if spec.complete and fully_finished(state): completed = true; break
		if index % 25 == 0: print("SHIP_FIRE_GPU_PROGRESS case=", id, " sample=", index, " time=", state.time)
	if spec.complete:
		check(completed and active_pause and spread_pause and extinguished_pause, "spatial case reaches cold, returned staff and expired VFX within forty-eight seconds")
		check(state.lanes.candidate.spreadCount == 0 and state.lanes.candidate.hull > state.lanes.baseline.hull and state.lanes.candidate.hull < 100.0, "single team prevents propagation without healing")
	else:
		check(state.tick == 480 and near(state.time, 8.0), id + " covers eight accepted seconds")
		if id == "mid": check(state.lanes.baseline.spreadCount == 2, "mid ignition reaches both adjacent ends")
		elif id == "bow": check(state.lanes.baseline.spreadCount == 1 and state.lanes.baseline.fireControl.heatByZone[2] == 0.0, "bow ignition first reaches mid, never instant stern")
	cases.append({"id":id, "options":options, "samples":count + 1, "last_tick":state.tick, "last_time":state.time, "completed":completed, "active_pause":active_pause, "extinguished_pause":extinguished_pause, "spread_pause":spread_pause, "final":compact(state)})
	return failures.is_empty()

func baseline_detail(id: String, index: int) -> bool:
	var before: Dictionary = lab._demo.inspection_snapshot()
	var authority: String = authority_digest(before)
	lab._demo.set_camera_mode("baseline-near")
	await frames(2); await RenderingServer.frame_post_draw
	var after: Dictionary = lab._demo.inspection_snapshot()
	check(authority == authority_digest(after), "left ship close camera preserves accepted state")
	checks.append({"name":"baseline_detail", "tick":after.tick, "time":after.time, "unchanged":authority == authority_digest(after), "before_authority_sha256":authority, "after_authority_sha256":authority_digest(after), "overview_file":"%s-%03d.png" % [id,index], "near_file":id + "-spread-near.png"})
	if not save_image(lab._viewport.get_texture().get_image(), id + "-spread-near.png", "detail", id, index, 0, after): return false
	lab._demo.set_camera_mode("overview")
	await frames(2)
	return failures.is_empty() and check(authority == authority_digest(lab._demo.inspection_snapshot()), "restore overview without progression")

func total(lane: Dictionary) -> float: return float(Spread.summary(lane.fireControl).get("heat", -1.0))
func both_cold(state: Dictionary) -> bool: return total(state.lanes.baseline) == 0.0 and total(state.lanes.candidate) == 0.0

func valid_state(state: Dictionary) -> bool:
	if not state.get("ready", false) or not state.get("paused", false) or state.get("scope") != SCOPE or not state.get("error", "").is_empty(): return false
	if state.parameters.fire_model != "zones" or state.parameters.seed != SEED or state.parameters.payload != "thorn-ball" or state.parameters.firefighters != 4 or state.parameters.moisture != "dry" or state.parameters.load != "clear": return false
	if not near(state.fixed_step, STEP) or not near(state.time, int(state.tick) * STEP) or state.template.tick != 0 or state.template.time != 0.0 or not state.events.is_empty() or state.resources.storage != 0: return false
	if state.visual.tick != state.tick or not near(state.visual.time, state.time) or state.visual.ships.size() != 2: return false
	for ship: Dictionary in state.visual.ships:
		var lane: Dictionary = state.lanes[ship.id]
		if not Spread.valid(lane.fireControl) or ship.fireControl != Spread.summary(lane.fireControl) or ship.fireSpread != lane.fireControl: return false
		if ship.hull != lane.hull or ship.sail != lane.sail or ship.crew != lane.crew: return false
		if not lane.crew is int or not lane.fireControl.supplies is int or lane.crew + lane.damage.crew != lane.maxCrew or lane.fireControl.supplies + lane.suppliesSpent != state.parameters.supplies: return false
		if not near(lane.hull + lane.damage.hull, 100.0) or not near(lane.sail + lane.damage.sail, 100.0) or not near(lane.workSeconds, lane.suppliesSpent * 2.0 + lane.fireControl.workCarry): return false
	var fire: Dictionary = state.fire_view
	return fire.ready and fire.enabled and near(fire.time, state.time) and fire.draw_calls <= 3 and fire.reserved_particles <= fire.capacity and fire.living_fires <= 2 and fire.burning_zones <= 6

func fire_counts(view: Dictionary) -> Dictionary:
	var result: Dictionary = super.fire_counts(view)
	for key: String in ["burning_zones", "ships", "zone_anchors", "capacity_smoke_evictions"]: result[key] = view.get(key)
	result.particles = view.get("particles", []).duplicate(true)
	return result

func compact(state: Dictionary) -> Dictionary:
	var result: Dictionary = super.compact(state)
	if state.is_empty(): return result
	for ship: Dictionary in result.visual.ships:
		for source: Dictionary in state.visual.ships:
			if source.id == ship.id: ship.fireSpread = source.fireSpread.duplicate(true)
	return result
