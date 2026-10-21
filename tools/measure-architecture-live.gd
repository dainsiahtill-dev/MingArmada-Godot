extends "res://tools/capture-fidelity-island.gd"
## Private comparison observer. Each process enters one actual public menu mode;
## the product alone advances physics/process and chooses camera/quality/actors.
const AudioCleanup = preload("res://tests/fixtures/audio_cleanup.gd")
const WARMUP_SECONDS := 10.0
const SAMPLE_SECONDS := 30.0
const CODE_ROOTS := ["res://game", "res://modules"]
var mode := "mingqi"
var _game: Node
var _measured: Array[Dictionary] = []
var _report: Dictionary = {}
var _stopping := false
var _invalid: Array[String] = []

func _run() -> void:
	output = ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--mode="): mode = argument.trim_prefix("--mode=")
		elif argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	if output.is_empty(): output = "res://Temp/entry-live-%s-v1" % mode
	if not check(mode in ["mingqi", "sail", "duel", "fidelity-island"], "mode must be mingqi|sail|duel|fidelity-island"):
		await _finish(); return
	if not check(DisplayServer.get_name() != "headless", "entry observation requires actual native GPU rendering"):
		await _finish(); return
	if not check(not output.is_empty() and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output)) and not FileAccess.file_exists(output), "fresh output directory required"):
		await _finish(); return
	if not check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output)) == OK, "fresh output directory opens"):
		await _finish(); return
	output_owned = true
	_report = {"schema":"ming-armada-architecture-live-v1", "createdAtUtc":Time.get_datetime_string_from_system(true) + "Z", "mode":mode, "menuRngSeed":1661, "scope":"Actual public menu/router; automatic production physics/process; ten seconds warmup then thirty seconds observed engine intervals. Default camera, settings and actors retained. No manual producer calls, FPS cap or GPU readback during observation; fixed-seed controlled comparison, not hardware-independent or long-duration acceptance.", "rows":[]}
	create_timer(120.0).timeout.connect(func():
		if not _stopping:
			_invalidate("watchdog-expired")
			check(false, "entry live diagnostic watchdog expired")
			_finish()
	)
	root.unresizable = true
	root.size = Vector2i(1600, 900)
	root.content_scale_size = Vector2i(1600, 900)
	var slot := MemorySlot.new()
	var legacy := MemorySlot.new()
	settings = Settings.new("user://verification/entry-live-no-write-%d.json" % OS.get_process_id())
	main = Main.new()
	main.router = Router.new({"mingqi_storage":slot, "legacy_storage":legacy, "settings_storage":settings})
	root.add_child(main)
	for frame in 5:
		await process_frame
		if _stopping: return
	var button: Button = main.menu.find_child(mode, true, false)
	if not check(button != null and not button.disabled and button.is_visible_in_tree(), "actual public menu button is available: " + mode):
		await _finish(); return
	var entry_started := Time.get_ticks_usec()
	seed(1661) # Same explicit menu RNG seed in both frozen projects.
	button.pressed.emit()
	if not await _await_entry():
		if not _stopping: await _finish()
		return
	_report.entryWallMs = float(Time.get_ticks_usec() - entry_started) / 1000.0
	_game = main.current_scene
	root.grab_focus()
	# Close only the actual initial UI blockers. Product defaults, camera and
	# actor counts remain untouched; focus loss still requires explicit resume.
	if mode == "mingqi":
		_game.get("interface").close_panel()
		_game.get("interface").close_menu()
	if mode != "fidelity-island":
		var runtime: RefCounted = _game.get("runtime")
		runtime.set_pause("menu", false)
		runtime.set_pause("player", false)
		runtime.set_pause("blur", false)
	for frame in 3:
		await process_frame
		if _stopping: return
	# Reapply requested client dimensions after the native window style settles.
	root.size = Vector2i(1600, 900)
	for frame in 3:
		await RenderingServer.frame_post_draw
		if _stopping: return
	_register_viewports()
	var expected := _fixed_load()
	if expected.window != [1600, 900] or expected.viewport != [1600.0, 900.0] or expected.renderTexture != [1600.0, 900.0]:
		_invalidate("actual-window-dimensions-not-1600x900")
	_report.expectedFixedLoad = expected
	_report.initialActors = _actors()
	_report.initialCamera = _camera()
	_report.codeHashes = _code_hashes()
	_report.engine = Engine.get_version_info()
	_report.gpu = RenderingServer.get_video_adapter_name()
	_report.renderingMethod = RenderingServer.get_current_rendering_method()
	_report.clockOwner = "scene.seconds (automatic preview process)" if mode == "fidelity-island" else "native encounter.tick / 60"
	_report.viewports = _viewport_metadata()
	_report.nativeStart = _native_time()
	var start := Time.get_ticks_usec()
	var previous := start
	var prior_physics := Engine.get_physics_frames()
	var sample_started := -1
	var sample_end := -1
	while not _stopping:
		await process_frame
		if _stopping: return
		var now := Time.get_ticks_usec()
		var physics := Engine.get_physics_frames()
		var wall := float(now - start) / 1000000.0
		var included := sample_started >= 0
		var load_state := _fixed_load()
		var changes := _load_changes(expected, load_state)
		for key: String in changes: _invalidate("fixed-load-changed-" + key)
		var paused := _paused()
		var focused := root.has_focus()
		var visible := root.visible
		if paused: _invalidate("external-pause")
		if not focused: _invalidate("window-unfocused")
		if not visible: _invalidate("window-hidden")
		var row := {"wallSeconds":wall, "intervalMs":float(now - previous) / 1000.0, "physicsSteps":physics - prior_physics, "nativeTime":_native_time(), "focused":focused, "visible":visible, "paused":paused, "pauseReasons":_pause_reasons(), "includedInMetrics":included, "valid":changes.is_empty() and not paused and focused and visible, "fixedLoad":load_state, "fixedLoadChanges":changes, "resources":_resources(), "actors":_actors(), "renderTimes":_render_times(), "renderSetupCpuMs":RenderingServer.get_frame_setup_time_cpu(), "engineProcessMonitorMs":Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, "enginePhysicsMonitorMs":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0}
		_report.rows.append(row)
		previous = now
		prior_physics = physics
		if sample_started < 0 and wall >= WARMUP_SECONDS:
			# The boundary interval remains a warmup row. Every later completed
			# interval, including the final slow interval, is retained untrimmed.
			sample_started = now
			_report.sampleNativeStart = _native_time()
		elif sample_started >= 0 and float(now - sample_started) / 1000000.0 >= SAMPLE_SECONDS:
			sample_end = now
			break
	_report.warmupWallSeconds = float(sample_started - start) / 1000000.0
	_report.sampleWallSeconds = float(sample_end - sample_started) / 1000000.0
	_report.observedWallSeconds = float(sample_end - start) / 1000000.0
	_report.measurementStoppedAtUsec = sample_end
	_report.nativeEnd = _native_time()
	_report.finalActors = _actors()
	_report.finalCamera = _camera()
	_report.metrics = _metrics(_report.rows.filter(func(row: Dictionary): return row.includedInMetrics))
	_report.finalCodeHashes = _code_hashes()
	if _report.finalCodeHashes != _report.codeHashes: _invalidate("source-code-changed-during-run")
	# All timing rows are complete before pausing or reading actual GPU pixels.
	if mode == "fidelity-island": _game.set("paused", true)
	else: _game.get("runtime").set_pause("player", true)
	for frame in 3:
		await process_frame
		if _stopping: return
	await RenderingServer.frame_post_draw
	if _stopping: return
	var image := root.get_texture().get_image()
	var png := output + "/" + mode + "-after-observation.png"
	var saved := image != null and not image.is_empty() and image.save_png(png) == OK
	check(saved, "actual viewport PNG is saved after observation")
	_report.viewportCapture = {"path":ProjectSettings.globalize_path(png), "saved":saved, "capturedAfterMeasurement":true, "completedAtUsec":Time.get_ticks_usec(), "sha256":FileAccess.get_sha256(png) if saved else "", "width":image.get_width() if saved else 0, "height":image.get_height() if saved else 0}
	check(slot.writes == 0 and legacy.writes == 0, "observation preserves actual user save slots")
	_report.saveWrites = {"mingqi":slot.writes, "legacy":legacy.writes}
	await _finish()

func _await_entry() -> bool:
	while not _stopping:
		await process_frame
		if _stopping: return false
		if is_instance_valid(main.current_scene):
			return check(main.current_scene.get("startup_receipt").get("ok", false), "actual menu/router initializes " + mode)
	return false

func _invalidate(reason: String) -> void:
	if reason not in _invalid: _invalid.append(reason)

func _native_time() -> float:
	if mode == "fidelity-island": return float(_game.get("seconds"))
	var encounter: RefCounted = _game.get("runtime").get("simulation").get("encounter")
	return float(encounter.get("tick")) / 60.0

func _paused() -> bool:
	return bool(_game.get("paused")) if mode == "fidelity-island" else _game.get("runtime").is_paused()

func _pause_reasons() -> Array:
	if mode == "fidelity-island": return ["preview"] if _paused() else []
	return _game.get("runtime").get("_pauses").keys()

func _resources() -> Dictionary:
	return {"nodes":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), "objects":int(Performance.get_monitor(Performance.OBJECT_COUNT)), "resources":int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)), "orphanNodes":int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)), "staticMemoryBytes":int(Performance.get_monitor(Performance.MEMORY_STATIC)), "videoMemoryBytes":int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)), "physicsActiveObjects":int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))}

func _actors() -> Dictionary:
	var sea: Node3D = _game.get("sea")
	var visible_crew := 0
	var impacts := 0
	var ship_lods: Dictionary = {}
	var crew_lods: Dictionary = {}
	var ships: Dictionary = sea.get("ships")
	var sailors: Dictionary = sea.get("sailors")
	for view: Node3D in ships.values():
		var key := str(view.get_lod())
		ship_lods[key] = int(ship_lods.get(key, 0)) + 1
	for crew: Node3D in sailors.values():
		visible_crew += crew.get_visible_count()
		impacts += int(crew.get("_impacts").size())
		var key := str(crew.get("_lod"))
		crew_lods[key] = int(crew_lods.get(key, 0)) + 1
	return {"ships":ships.size(), "crewOwners":sailors.size(), "visibleCrew":visible_crew, "crewImpacts":impacts, "shipLODs":ship_lods, "crewLODs":crew_lods}

func _camera() -> Dictionary:
	var camera: Camera3D = _game.get("sea").get("camera")
	return {"position":[camera.global_position.x, camera.global_position.y, camera.global_position.z], "rotation":[camera.global_rotation.x, camera.global_rotation.y, camera.global_rotation.z], "fov":camera.fov, "near":camera.near, "far":camera.far}

func _register_viewports() -> void:
	_measured.append({"name":"main", "path":str(root.get_path()), "role":"main", "viewport":root, "rid":root.get_viewport_rid()})
	var camera: Camera3D = _game.get("sea").get("camera")
	for viewport: SubViewport in root.find_children("*", "SubViewport", true, false):
		var role := "reflection" if str(viewport.name).to_lower().contains("reflection") else "scene" if viewport == camera.get_viewport() else "subviewport"
		_measured.append({"name":str(viewport.name), "path":str(viewport.get_path()), "role":role, "viewport":viewport, "rid":viewport.get_viewport_rid()})
	for entry: Dictionary in _measured: RenderingServer.viewport_set_measure_render_time(entry.rid, true)

func _viewport_metadata() -> Array:
	var result: Array = []
	for entry: Dictionary in _measured:
		var viewport: Viewport = entry.viewport
		var texture_size := viewport.get_texture().get_size()
		result.append({"name":entry.name, "path":entry.path, "role":entry.role, "size":[texture_size.x, texture_size.y], "msaa3d":viewport.msaa_3d, "scaling3dScale":viewport.scaling_3d_scale, "scaling3dMode":viewport.scaling_3d_mode})
	return result

func _render_times() -> Array:
	var result: Array = []
	for entry: Dictionary in _measured:
		result.append({"name":entry.name, "path":entry.path, "role":entry.role, "cpuMs":RenderingServer.viewport_get_measured_render_time_cpu(entry.rid), "gpuMs":RenderingServer.viewport_get_measured_render_time_gpu(entry.rid)})
	return result

func _fixed_load() -> Dictionary:
	var visible_size := root.get_visible_rect().size
	var texture_size := root.get_texture().get_size()
	return {"window":[root.size.x, root.size.y], "viewport":[visible_size.x, visible_size.y], "renderTexture":[texture_size.x, texture_size.y], "contentScaleSize":[root.content_scale_size.x, root.content_scale_size.y], "contentScaleFactor":root.content_scale_factor, "settings":settings.snapshot(), "seaSettings":_game.get("sea").get("_settings").duplicate(true), "viewports":_viewport_metadata(), "physicsHz":Engine.physics_ticks_per_second, "maxPhysicsStepsPerFrame":Engine.max_physics_steps_per_frame, "maxFps":Engine.max_fps, "timeScale":Engine.time_scale, "vsyncMode":DisplayServer.window_get_vsync_mode()}

func _load_changes(expected: Dictionary, actual: Dictionary) -> Array[String]:
	var changed: Array[String] = []
	for key: String in expected:
		if not actual.has(key) or actual[key] != expected[key]: changed.append(key)
	return changed

func _collect_code(directory: String, paths: Array[String]) -> void:
	var listing := DirAccess.open(directory)
	if listing == null: return
	listing.list_dir_begin()
	var name := listing.get_next()
	while not name.is_empty():
		var path := directory.path_join(name)
		if listing.current_is_dir(): _collect_code(path, paths)
		elif name.get_extension() in ["gd", "gdshader", "gdshaderinc", "tscn"]: paths.append(path)
		name = listing.get_next()
	listing.list_dir_end()

func _code_hashes() -> Dictionary:
	var paths: Array[String] = ["res://project.godot", "res://tools/measure-architecture-live.gd", "res://tools/capture-fidelity-island.gd"]
	for directory: String in CODE_ROOTS: _collect_code(directory, paths)
	paths.sort()
	var hashes: Dictionary = {}
	for path: String in paths: hashes[path] = FileAccess.get_sha256(path)
	return hashes

func _stats(values: Array) -> Dictionary:
	if values.is_empty(): return {"count":0}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value: Variant in sorted: total += float(value)
	var middle := floori(float(sorted.size()) / 2.0)
	return {"count":sorted.size(), "mean":total / sorted.size(), "median":float(sorted[middle]) if sorted.size() % 2 else (float(sorted[middle - 1]) + float(sorted[middle])) * 0.5, "p95":sorted[ceili(sorted.size() * 0.95) - 1], "p99":sorted[ceili(sorted.size() * 0.99) - 1], "worst":sorted.back()}

func _metrics(rows: Array) -> Dictionary:
	var result: Dictionary = {}
	for key: String in ["intervalMs", "physicsSteps", "renderSetupCpuMs", "engineProcessMonitorMs", "enginePhysicsMonitorMs"]:
		result[key] = _stats(rows.map(func(row: Dictionary): return row[key]))
	var intervals: Dictionary = result.intervalMs
	result.observedFps = 1000.0 / float(intervals.mean) if intervals.get("count", 0) > 0 and intervals.mean > 0.0 else null
	result.renderTimes = []
	for entry: Dictionary in _measured:
		var cpu: Array = []
		var gpu: Array = []
		for row: Dictionary in rows:
			for timing: Dictionary in row.renderTimes:
				if timing.path == entry.path:
					cpu.append(timing.cpuMs); gpu.append(timing.gpuMs)
		result.renderTimes.append({"name":entry.name, "path":entry.path, "role":entry.role, "cpuMs":_stats(cpu), "gpuMs":_stats(gpu)})
	return result

func _finish() -> void:
	if _stopping: return
	_stopping = true
	var playbacks: Array[WeakRef] = []
	if is_instance_valid(main):
		playbacks = AudioCleanup.stop_players(main)
		main.free()
		main = null
	check(await AudioCleanup.wait_for_release(self, playbacks), "entry diagnostic releases actual audio playback")
	if output_owned:
		_report.failures = failures
		_report.invalidReasons = _invalid
		_report.valid = failures == 0 and _invalid.is_empty() and _report.has("measurementStoppedAtUsec")
		var file := FileAccess.open(output + "/live-observation.json", FileAccess.WRITE)
		if check(file != null, "entry observation receipt opens"):
			file.store_string(JSON.stringify(_report, "\t")); file.close()
	print("ENTRY_LIVE_OBSERVATION mode=", mode, " frames=", _report.get("rows", []).size(), " valid=", _report.get("valid", false), " failures=", failures, " output=", output)
	quit(1 if failures or not _invalid.is_empty() else 0)
