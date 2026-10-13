extends "res://tools/capture-fidelity-island.gd"
## Private CPU isolation: first presentation at real newly accepted native time.
## Same-time reentry is reported separately; neither series is an FPS/GPU test.
const STEP := 1.0 / 60.0
const WATCHDOG_SECONDS := 90.0
var _sample_count := 8
var _finished := false
var _career_slot: RefCounted
var _legacy_slot: RefCounted
var _report: Dictionary = {
	"scope": "Actual main-menu Mingqi scene; isolated first calls at fresh accepted native time with the actual camera fixed to the preceding normal presentation. This is not a complete normal frame. Same-time cache reentry is separate. No FPS, GPU timing, total-frame sum or long-duration acceptance claim.",
	"samples": [],
}

func _run() -> void:
	output = "res://Temp/world-fresh-time-v1.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		if arg.begins_with("--samples="): _sample_count = arg.trim_prefix("--samples=").to_int()
	if not check(_sample_count >= 6 and _sample_count <= 12, "fresh-time sample count is between six and twelve"):
		quit(1)
		return
	if not check(not FileAccess.file_exists(output), "fresh diagnostic output required; prior evidence is never overwritten"):
		quit(1)
		return
	if not check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir())) == OK, "fresh diagnostic parent directory is available"):
		quit(1)
		return
	output_owned = true
	create_timer(WATCHDOG_SECONDS).timeout.connect(func():
		if not _finished:
			check(false, "fresh-time diagnostic watchdog expired")
			_finish())
	root.size = Vector2i(1600, 900)
	_career_slot = MemorySlot.new()
	_legacy_slot = MemorySlot.new()
	settings = Settings.new("user://verification/world-fresh-time-no-write-%d.json" % OS.get_process_id())
	main = Main.new()
	main.router = Router.new({"mingqi_storage": _career_slot, "legacy_storage": _legacy_slot, "settings_storage": settings})
	root.add_child(main)
	for unused in 5: await process_frame
	var button: Button = main.menu.find_child("mingqi", true, false)
	if not check(button != null and not button.disabled, "ordinary public new-career menu entry is available"):
		_finish()
		return
	var entry_start := Time.get_ticks_usec()
	button.pressed.emit()
	if not await _await_scene("mingqi"):
		_finish()
		return
	_report.entryWallMs = _elapsed_ms(entry_start)
	var game: Node = main.current_scene
	# Disable every automatic callback, including children with ALWAYS mode.
	# Direct production calls below still execute normally; no effect is removed.
	_freeze_callbacks(main)
	game.runtime.set_pause("blur", false)
	game.interface.close_panel()
	game.interface.close_menu()
	if not check(not game.runtime.is_paused(), "actual new career is active before controlled native advancement"):
		_finish()
		return
	game._present(0.0)
	var world: Node3D = game.sea.world
	var ocean: Node3D = world.get_ocean()
	var natural: Node3D = world.get("_natural_world")
	var atmosphere: RefCounted = world.get("atmosphere")
	var camera: Camera3D = game.sea.camera
	if not check(is_instance_valid(natural) and atmosphere != null, "formal career retains its natural shore/forest world and atmosphere"):
		_finish()
		return
	var initial: Dictionary = game.runtime.simulation.snapshot()
	_report.initialNativeTime = initial.time
	_report.initialWorldTime = world.get("_simulation_time")
	_report.shipCount = initial.ships.size()
	_report.settings = settings.snapshot()
	_report.counts = _counts(game, natural, atmosphere)
	_report.initialCamera = _camera_state(camera)
	_report.productionHashes = {}
	for path: String in ["res://game/scenes/mingqi/mingqi_scene.gd", "res://modules/scene_engine/world/world_view.gd", "res://modules/scene_engine/ocean/projected_ocean.gd", "res://modules/scene_engine/terrain/natural_world.gd", "res://modules/scene_engine/terrain/natural_shore_surf.gd", "res://modules/scene_engine/fidelity_fx/atmosphere.gd"]:
		_report.productionHashes[path] = FileAccess.get_sha256(path)
	var previous_time: float = initial.time
	for index in _sample_count:
		var before: Dictionary = game.runtime.simulation.snapshot()
		var world_before: float = world.get("_simulation_time")
		if not check(float(before.time) == previous_time and world_before == previous_time, "sample starts at matching previous native and presented world time"):
			break
		game.sea.observe_projectiles(before)
		var advance_start := Time.get_ticks_usec()
		var accepted: float = game.runtime.advance(STEP)
		var advance_ms := _elapsed_ms(advance_start)
		var native: Dictionary = game.runtime.simulation.snapshot()
		var target_time: float = native.time
		if not check(accepted > 0.0 and target_time > previous_time and absf(target_time - previous_time - accepted) < 1.0e-8, "sample uses a strict new time from the real accepted native interval"):
			break
		if not check(native.ships.size() == int(_report.shipCount), "controlled samples retain the actual formal fleet"):
			break
		game.sea.remember_authoritative_poses(native, accepted)
		var focus := _flagship_focus(native)
		var camera_before := _camera_state(camera)
		var fresh: Dictionary = _measure(world, ocean, natural, atmosphere, camera, target_time, focus, accepted)
		var fresh_state := _component_times(world, ocean, natural, atmosphere, target_time, "fresh")
		var same_time: Dictionary = _measure(world, ocean, natural, atmosphere, camera, target_time, focus, 0.0)
		var same_state := _component_times(world, ocean, natural, atmosphere, target_time, "same-time")
		check(camera_before == _camera_state(camera), "isolated fresh and cache calls preserve the actual camera condition")
		check(_times_match(fresh_state, target_time) and _times_match(same_state, target_time), "direct component presentation follows the latest accepted native time")
		# Complete the normal actor/UI/camera presentation only after isolated costs.
		# This is a completion call, and is never labelled as an untouched full frame.
		var completion_start := Time.get_ticks_usec()
		game._present(accepted)
		var completion_ms := _elapsed_ms(completion_start)
		var after: Dictionary = game.runtime.simulation.snapshot()
		var world_after: float = world.get("_simulation_time")
		check(float(after.time) == target_time and world_after == target_time, "normal completion leaves matching world and authoritative native time")
		_report.samples.append({"index": index, "acceptedSeconds": accepted, "nativeTimeBefore": before.time, "worldTimeBefore": world_before, "nativeTime": target_time, "nativeTick": native.tick, "freshMs": fresh, "sameTimeReentryMs": same_time, "freshComponentTimes": fresh_state, "sameTimeComponentTimes": same_state, "nativeAdvanceMs": advance_ms, "completionPresentMs": completion_ms, "worldTimeAfter": world_after, "nativeTimeAfter": after.time, "focus": [focus.x, focus.z], "cameraDuringIsolation": camera_before, "cameraAfterNormalPresent": _camera_state(camera), "atmosphere": _short_atmosphere(atmosphere)})
		print("WORLD_FRESH_TIME sample=", index, " native=", target_time, " freshMs=", fresh, " sameTimeMs=", same_time)
		previous_time = target_time
		await process_frame
		if _finished: return
	check(_report.samples.size() == _sample_count, "requested accepted-time samples completed")
	check(_report.counts == _counts(game, natural, atmosphere), "diagnostic preserves existing ships, terrain, shores, trees, clouds and fog")
	_finish()

func _freeze_callbacks(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child: Node in node.get_children(): _freeze_callbacks(child)

func _elapsed_ms(start: int) -> float:
	return float(Time.get_ticks_usec() - start) / 1000.0

func _flagship_focus(native: Dictionary) -> Vector3:
	for ship: Dictionary in native.ships:
		if ship.id == native.playerId:
			var point: Dictionary = ship.visual.position
			return Vector3(float(point.x), 0.0, float(point.z))
	check(false, "accepted native snapshot retains its flagship focus")
	return Vector3.ZERO

func _measure(world: Node3D, ocean: Node3D, natural: Node3D, atmosphere: RefCounted, camera: Camera3D, seconds: float, focus: Vector3, accepted: float) -> Dictionary:
	var costs: Dictionary = {}
	if not check(is_finite(seconds) and seconds >= 0.0, "isolated world presentation accepts a finite native time"):
		return costs
	# World.apply_snapshot performs this assignment before ocean/terrain sync.
	# Replay it outside the measured methods so surface shaders share the phase.
	world.set("_simulation_time", seconds)
	var start := Time.get_ticks_usec()
	ocean.set_simulation_time(seconds)
	costs.oceanTime = _elapsed_ms(start)
	start = Time.get_ticks_usec()
	world._sync_terrain_surface()
	costs.terrainSurfaceSync = _elapsed_ms(start)
	start = Time.get_ticks_usec()
	ocean.update_projection()
	costs.oceanProjection = _elapsed_ms(start)
	start = Time.get_ticks_usec()
	natural.apply_snapshot({"time": seconds, "focus": Vector2(focus.x, focus.z)}, accepted)
	costs.naturalShoreAndForest = _elapsed_ms(start)
	start = Time.get_ticks_usec()
	atmosphere.apply_snapshot({"time": seconds}, camera, focus)
	costs.atmosphere = _elapsed_ms(start)
	return costs

func _camera_state(camera: Camera3D) -> Dictionary:
	return {"position": [camera.global_position.x, camera.global_position.y, camera.global_position.z], "basis": [camera.global_basis.x, camera.global_basis.y, camera.global_basis.z], "fov": camera.fov}

func _short_atmosphere(atmosphere: RefCounted) -> Dictionary:
	var state: Dictionary = atmosphere.diagnostics()
	var result: Dictionary = {}
	for key: String in ["time", "animationTime", "cloudClones", "cloudMeshes", "fogInstances", "fogMeshes", "cloudUpdates", "historySteps"]: result[key] = state.get(key)
	return result

func _component_times(world: Node3D, ocean: Node3D, natural: Node3D, atmosphere: RefCounted, target: float, phase: String) -> Dictionary:
	var shores: Array = []
	for shore: Node3D in natural.get("_dynamic_shore"): shores.append(shore.get("_time"))
	var terrain_times: Array = []
	var terrains: Array = natural.get("_terrain")
	for index in terrains.size():
		var terrain: Node3D = terrains[index]
		var mesh: MeshInstance3D = terrain.get_mesh()
		var material: ShaderMaterial = mesh.material_override as ShaderMaterial if is_instance_valid(mesh) else null
		var shader_time: Variant = material.get_shader_parameter("simulation_time") if material != null else null
		var matches: bool = _shader_time_matches(shader_time, target)
		check(matches, phase + " terrain mesh " + str(index) + " shader simulation_time matches accepted native time")
		terrain_times.append({"index": index, "simulationTime": shader_time, "matchesNativeTime": matches})
	return {"world": world.get("_simulation_time"), "ocean": ocean.get("_simulation_time"), "atmosphere": atmosphere.get("_time"), "shore": shores, "terrainShaders": terrain_times}

func _shader_time_matches(value: Variant, target: float) -> bool:
	# Shader uniforms may use binary32 storage; retain the actual readback value.
	return (value is float or value is int) and is_finite(float(value)) and absf(float(value) - target) <= 1.0e-7 * maxf(1.0, absf(target))

func _times_match(state: Dictionary, target: float) -> bool:
	if float(state.world) != target or float(state.ocean) != target or float(state.atmosphere) != target: return false
	for value: Variant in state.shore:
		if not (value is float or value is int) or float(value) != target: return false
	for terrain: Dictionary in state.terrainShaders:
		if not bool(terrain.matchesNativeTime): return false
	return true

func _counts(game: Node, natural: Node3D, atmosphere: RefCounted) -> Dictionary:
	var state: Dictionary = _short_atmosphere(atmosphere)
	return {"ships": game.sea.ships.size(), "sailorOwners": game.sea.sailors.size(), "terrainMeshes": (natural.get("_terrain") as Array).size(), "forests": (natural.get("_trees") as Array).size(), "shores": (natural.get("_dynamic_shore") as Array).size(), "cloudClones": state.cloudClones, "cloudMeshes": state.cloudMeshes, "fogInstances": state.fogInstances, "fogMeshes": state.fogMeshes}

func _finish() -> void:
	if _finished: return
	_finished = true
	if _career_slot != null and _legacy_slot != null:
		check(_career_slot.writes == 0 and _legacy_slot.writes == 0, "private CPU diagnostic never writes career or legacy saves")
	_report.failures = failures
	_report.headless = DisplayServer.get_name() == "headless"
	_report.godot = Engine.get_version_info().string
	_report.gpu = RenderingServer.get_video_adapter_name()
	_report.watchdogSeconds = WATCHDOG_SECONDS
	if output_owned:
		if check(not FileAccess.file_exists(output), "diagnostic destination is still fresh at write time"):
			var file := FileAccess.open(output, FileAccess.WRITE)
			if check(file != null, "fresh-time diagnostic receipt opens"):
				file.store_string(JSON.stringify(_report, "\t"))
				file.close()
	if is_instance_valid(main): main.free()
	print("WORLD_FRESH_TIME_COMPLETE samples=", _report.samples.size(), " failures=", failures)
	quit(1 if failures else 0)
