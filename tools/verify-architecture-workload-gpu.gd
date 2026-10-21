extends SceneTree
## Public Main -> sail, ordinary automatic physics/process, real Forward+ draws.
## Visibility isolation only: this is a workload census, never an FPS benchmark.
## API: https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-viewport-get-render-info
const Main = preload("res://game/scenes/main/main_scene.gd")
const Router = preload("res://game/runtime/game_router.gd")
const Settings = preload("res://game/persistence/user_settings.gd")
const Menu = preload("res://game/ui/menu/main_menu.gd")
const AudioCleanup = preload("res://tests/fixtures/audio_cleanup.gd")
const SOURCES := ["tools/verify-architecture-workload-gpu.gd", "tests/fixtures/audio_cleanup.gd", "game/scenes/main/main_scene.gd", "game/runtime/game_router.gd", "game/scenes/naval_practice/naval_practice.gd", "game/runtime/naval_practice_runtime.gd", "game/runtime/sailing_simulation.gd", "game/presentation/world/naval_world_view.gd", "game/presentation/ships/ship_view.gd", "game/presentation/crew/crew_view.gd", "modules/scene_engine/world/world_view.gd", "modules/scene_engine/terrain/natural_world.gd", "modules/scene_engine/terrain/natural_shore_surf.gd", "modules/scene_engine/fidelity_island/compiled_shore_sampler.gd", "modules/scene_engine/fidelity_fx/atmosphere.gd", "modules/scene_engine/fidelity_fx/cloud_native.gd", "modules/scene_engine/fidelity_fx/cloud_render_compiler.gd", "modules/scene_engine/fidelity_fx/cloud_curve_sampler.gd", "modules/scene_engine/fidelity_fx/world_cloud_lifecycle.gd", "modules/scene_engine/ocean/projected_ocean.gd", "modules/scene_engine/reference_island_water/ocean_renderer.gd"]
const PASSES := {"visible": RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, "shadow": RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, "canvas": RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS}
const METRICS := {"objects": RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME, "primitives": RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME, "draw_calls": RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME}
const ENTRY_SOURCES := ["game/ui/menu/main_menu.gd", "game/persistence/user_settings.gd"]
var output := ""
var sample_count := 16
var warmup_frames := 12
var include_ocean := true
var include_atmosphere := true
var assertions := 0
var failures: Array[String] = []
var epochs: Array = []
var captures: Array = []
var _main: Node
var _game: Node3D
var _world: Node3D
var _ocean: MeshInstance3D
var _reflection: SubViewport
var _atmosphere: RefCounted
var _targets: Array[Dictionary] = []
var _slots: Array[RefCounted] = []
var _settings: RefCounted
var _initial_flags: Dictionary = {}
var _initial_actors: Dictionary = {}
var _source_hashes: Dictionary = {}
var _persisted_before: Dictionary = {}
var _window_flags: Dictionary = {}
var _created_output := false
var _finished := false
var _started_utc := ""
var _entry_states: Array[Dictionary] = []
var _entry_state_key := ""
var _window_events: Array[Dictionary] = []
var _initial_authority: Dictionary = {}
var _interruption: Dictionary = {}

class MemorySlot extends RefCounted:
	var writes := 0
	func read_checkpoint() -> Dictionary: return {"ok": false, "reason": "save-not-found"}
	func write_checkpoint(_raw: String) -> Dictionary:
		writes += 1
		return {"ok": false, "reason": "census-write-forbidden"}

class MemorySettings extends RefCounted:
	var load_reason := "census-memory-defaults"
	var _settings: Dictionary = Settings.defaults()
	var _updates: Array[Dictionary] = []
	var memory_commits := 0
	var rejected_updates := 0
	var disk_write_attempts := 0
	func _init() -> void:
		_settings.captainName = Menu.normalized_name(_settings.captainName)
	func load_settings() -> Dictionary: return {"ok": true, "reason": load_reason, "settings": snapshot()}
	func snapshot() -> Dictionary: return _settings.duplicate(true)
	func update_settings(patch: Dictionary) -> Dictionary:
		# Main confirms this name before committing every ordinary start route.
		# Adopt that legitimate confirmation in memory; no FileAccess/Storage path.
		var accepted: bool = patch.size() == 1 and patch.get("captainName") is String and patch.captainName == _settings.captainName
		_updates.append({"patch": patch.duplicate(true), "accepted": accepted, "storage": "memory-only", "settingsBefore": snapshot()})
		if not accepted:
			rejected_updates += 1
			return {"ok": false, "reason": "census-unexpected-settings-patch", "settings": snapshot()}
		var candidate := snapshot(); candidate.merge(patch, true)
		_settings = Settings.normalise_settings(candidate); memory_commits += 1
		return {"ok": true, "reason": "census-name-confirmed-in-memory", "settings": snapshot()}
	func audit() -> Dictionary:
		return {"memoryCommits": memory_commits, "rejectedUpdates": rejected_updates, "diskWriteAttempts": disk_write_attempts, "updates": _updates.duplicate(true), "confirmed": snapshot()}

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> bool:
	assertions += 1
	if not ok: failures.append(message); printerr("FAIL workload census: ", message)
	return ok

func _frames(count: int) -> void:
	for _frame in count: await process_frame

func _hashes() -> Dictionary:
	var result: Dictionary = {}
	for path: String in SOURCES + ENTRY_SOURCES: result[path] = FileAccess.get_sha256("res://" + path)
	return result

func _saved_tree(path: String, result: Dictionary) -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)): return
	for file: String in DirAccess.get_files_at(path): result[path.path_join(file)] = FileAccess.get_sha256(path.path_join(file))
	for directory: String in DirAccess.get_directories_at(path): _saved_tree(path.path_join(directory), result)

func _persisted() -> Dictionary:
	var result: Dictionary = {}
	_saved_tree("user://saves", result)
	for file: String in DirAccess.get_files_at("user://"):
		if file.begins_with("settings.json"): result["user://" + file] = FileAccess.get_sha256("user://" + file)
	return result

func _id(node: Object) -> int: return node.get_instance_id() if is_instance_valid(node) else 0

func _entry_receipt() -> Dictionary:
	var receipt := {"requestedMode": "sail", "phase": "not-created"}
	if not is_instance_valid(_main): return receipt
	var menu: Control = _main.menu
	receipt.phase = menu.get("_phase") if is_instance_valid(menu) else "menu-unavailable"
	receipt.menuStatus = menu.get("_status").text if is_instance_valid(menu) else ""
	receipt.menuIntent = menu.get("_last_intent").duplicate(true) if is_instance_valid(menu) else {}
	receipt.menuDraftName = menu.draft_name() if is_instance_valid(menu) else ""
	receipt.routerActive = _main.router.get("_active").duplicate(true)
	receipt.routerGeneration = _main.router.generation
	receipt.activeSceneRequest = _main.get("_active_scene_request").duplicate(true)
	receipt.currentScene = {"present": false}
	receipt.candidateScene = {"present": false}
	for entry: Dictionary in [{"key": "currentScene", "node": _main.current_scene}, {"key": "candidateScene", "node": _main.get("_candidate")}]:
		if is_instance_valid(entry.node):
			receipt[entry.key] = {"present": true, "id": _id(entry.node), "script": entry.node.get_script().resource_path, "startup": _main._startup_receipt(entry.node)}
	receipt.failedMode = receipt.routerActive.get("mode", "sail") if receipt.phase == "error" else ""
	if _settings: receipt.settings = _settings.audit()
	return receipt

func _record_entry() -> Dictionary:
	var receipt := _entry_receipt()
	var key := JSON.stringify(receipt)
	if key != _entry_state_key:
		_entry_states.append({"processFrame": Engine.get_process_frames(), "receipt": receipt})
		_entry_state_key = key
	return receipt

func _authority_state() -> Dictionary:
	var state := {"rootHasFocus": root.has_focus(), "rootVisible": root.visible, "rootUnfocusable": root.unfocusable, "treePaused": paused, "runtimeReady": false}
	if is_instance_valid(_game) and _game.runtime.simulation:
		state.runtimeReady = true
		state.runtimePaused = _game.runtime.is_paused()
		state.pauseReasons = _game.runtime.presentation_pause_reasons().duplicate()
		state.nativeTick = _game.runtime.simulation.current_tick()
		state.nativeTime = _game.runtime.simulation.current_time()
		state.nativeStatus = _game.runtime.simulation.current_status()
		state.sceneVisible = _game.visible; state.sceneVisibleInTree = _game.is_visible_in_tree()
		state.sceneProcess = _game.is_processing(); state.scenePhysicsProcess = _game.is_physics_processing()
	return state

func _record_window_event(event: String) -> void:
	_window_events.append({"event": event, "processFrame": Engine.get_process_frames(), "drawnFrame": Engine.get_frames_drawn(), "authority": _authority_state()})

func _authority_guard(context: String, supplied: Dictionary = {}) -> bool:
	var state: Dictionary = _authority_state() if supplied.is_empty() else supplied
	var running: bool = state.runtimeReady and not state.runtimePaused and not state.treePaused and state.rootHasFocus
	if not running and _interruption.is_empty():
		_interruption = {"context": context, "processFrame": Engine.get_process_frames(), "drawnFrame": Engine.get_frames_drawn(), "authority": state.duplicate(true)}
		if is_instance_valid(_world) and is_instance_valid(_reflection): _interruption.flags = _flags()
		if is_instance_valid(_game) and is_instance_valid(_game.sea):
			var camera: Camera3D = _game.sea.camera
			_interruption.camera = {"position": camera.global_position, "basis": camera.global_basis, "fov": camera.fov}
		check(false, "automatic authority/focus interrupted: " + JSON.stringify(_interruption))
	return running

func _live_frames(count: int, context: String) -> bool:
	for frame: int in count:
		await process_frame
		if not _authority_guard(context + "/frame-" + str(frame)): return false
	return true

func _node_receipt(node: Node3D) -> Dictionary:
	return {"id": _id(node), "path": str(node.get_path()), "parent": _id(node.get_parent()), "owner": _id(node.owner), "visible": node.visible, "processMode": node.process_mode, "process": node.is_processing(), "physicsProcess": node.is_physics_processing()}

func _add_target(node: Node3D, category: String) -> void:
	if not check(is_instance_valid(node), "valid visibility owner: " + category): return
	_targets.append({"node": node, "category": category, "original": _node_receipt(node)})

func _visibility() -> Array:
	var result: Array = []
	for entry: Dictionary in _targets:
		if is_instance_valid(entry.node):
			var current: Dictionary = _node_receipt(entry.node)
			current.category = entry.category
			current.visibleInTree = entry.node.is_visible_in_tree()
			result.append(current)
	return result

func _restore_visibility() -> void:
	for entry: Dictionary in _targets:
		if is_instance_valid(entry.node): entry.node.visible = entry.original.visible

func _verify_visibility(hidden: String) -> void:
	for entry: Dictionary in _targets:
		if not check(is_instance_valid(entry.node), "visibility owner still alive: " + entry.category): continue
		var expected: Dictionary = entry.original.duplicate(true)
		if entry.category == hidden: expected.visible = false
		check(_node_receipt(entry.node) == expected, "exact visibility/process/parent/owner flags: " + entry.category + "/" + hidden)

func _mesh_count(node: Node) -> int:
	var count := 1 if node is MeshInstance3D else 0
	for child: Node in node.get_children(): count += _mesh_count(child)
	return count

func _actors() -> Dictionary:
	var ships: Dictionary = {}; var crew: Dictionary = {}
	for key: String in _game.sea.ships: ships[key] = _id(_game.sea.ships[key])
	for key: String in _game.sea.sailors: crew[key] = _id(_game.sea.sailors[key])
	var shore_meshes := 0; var shore_owners := 0
	for entry: Dictionary in _targets:
		if entry.category == "shore": shore_owners += 1; shore_meshes += _mesh_count(entry.node)
	return {"ships": ships, "crewOwners": crew, "shipActors": ships.size(), "crewActors": crew.size(), "shoreOwners": shore_owners, "shoreMeshInstanceNodes": shore_meshes, "shoreCountMeaning": "MeshInstance3D node inventory, NOT submitted objects, primitives or draw calls"}

func _flags() -> Dictionary:
	var camera: Camera3D = _game.sea.camera
	var mirror: Camera3D = _ocean.get_reflection_camera()
	var optics: RefCounted = _ocean.get("_surface_optics")
	var reference: Dictionary = _ocean.get("_reference_state")
	return {"quality": _game.sea.get("_settings").quality, "settings": _game.sea.get("_settings").duplicate(true), "renderer": RenderingServer.get_current_rendering_method(), "sceneProcess": _game.is_processing(), "scenePhysicsProcess": _game.is_physics_processing(), "sceneProcessMode": _game.process_mode, "worldOwner": _id(_world), "oceanOwner": _id(_ocean), "atmosphereOwner": _id(_atmosphere), "simulationOwner": _id(_game.runtime.simulation), "encounterOwner": _id(_game.runtime.simulation.encounter), "effectsOwner": _id(_game.sea.effects), "wakesOwner": _id(_game.sea.wakes), "rootSize": [root.size.x, root.size.y], "contentSize": [root.content_scale_size.x, root.content_scale_size.y], "rootMsaa": root.msaa_3d, "physicsTicksPerSecond": Engine.physics_ticks_per_second, "cameraId": _id(camera), "cameraCullMask": camera.cull_mask, "mirrorCameraId": _id(mirror), "mirrorCullMask": mirror.cull_mask, "reflectionId": _id(_reflection), "reflectionSize": [_reflection.size.x, _reflection.size.y], "reflectionUpdateMode": _reflection.render_target_update_mode, "reflectionOwnWorld": _reflection.own_world_3d, "sunShadows": _game.sea.get("_sun").shadow_enabled, "glow": _game.sea.get("_environment").glow_enabled, "oceanFeatures": {"optics": optics.enabled, "reflection": optics.reflection_enabled, "refraction": optics.refraction_enabled, "waves": reference.waves, "foam": reference.foam, "caustics": reference.caustics, "projectionGuard": _ocean.get("_projection_guard_enabled"), "waveCount": _ocean.get("_descriptors").size()}, "atmosphereFeatures": {"reducedMotion": _atmosphere.get("_reduced_motion"), "cloudLifecycle": _atmosphere.get("_cloud_lifecycle_enabled")}}

func _actor_counts() -> Dictionary:
	var visible_crew := 0; var per_ship: Dictionary = {}
	for key: String in _game.sea.sailors:
		var count: int = _game.sea.sailors[key].get_visible_count()
		visible_crew += count; per_ship[key] = count
	return {"shipActors": _game.sea.ships.size(), "crewActors": _game.sea.sailors.size(), "live3DCrewModels": visible_crew, "live3DCrewModelsPerShip": per_ship, "shoreMeshInstanceNodes": _initial_actors.shoreMeshInstanceNodes}

func _source_clocks() -> Dictionary:
	var shore: Array = []
	for entry: Dictionary in _targets:
		if entry.category == "shore": shore.append({"id": _id(entry.node), "time": entry.node.get("_time"), "states": entry.node.get("_states").size(), "geometryBuilds": entry.node.get("_geometry_builds")})
	var presented: Dictionary = _game.sea.get("_snapshot")
	var environment: Dictionary = presented.get("environment", {})
	return {"worldTime": _world.get("_simulation_time"), "oceanTime": _ocean.get("_simulation_time"), "shore": shore, "atmosphereTime": _atmosphere.get("_time"), "cloudAnimationTime": _atmosphere.get("_cloud_time"), "cloudUpdates": _atmosphere.get("_ring").get("updates", 0), "presentedTick": presented.get("tick", -1), "presentedTime": presented.get("time", -1), "environmentAcceptedTime": environment.get("acceptedTime", -1), "environmentSourceCallIndex": environment.get("sourceCallIndex", -1)}

func _viewport_counters(viewport: Viewport) -> Dictionary:
	var result: Dictionary = {}
	for pass_name: String in PASSES:
		var values: Dictionary = {}
		for metric_name: String in METRICS:
			# Native call order is (viewport RID, render pass TYPE, INFO metric).
			values[metric_name] = RenderingServer.viewport_get_render_info(viewport.get_viewport_rid(), PASSES[pass_name], METRICS[metric_name])
		result[pass_name] = values
	return result

func _sample(index: int, hidden: String) -> Dictionary:
	var native: RefCounted = _game.runtime.simulation
	var main_counters := _viewport_counters(root)
	var reflection_counters := _viewport_counters(_reflection)
	check(main_counters.visible.objects > 0 and main_counters.visible.draw_calls > 0, "main native visible counters available, sample " + str(index))
	check(reflection_counters.visible.objects > 0 and reflection_counters.visible.draw_calls > 0, "reflection native visible counters available, sample " + str(index))
	check(_flags() == _initial_flags, "nonvisibility rendering/process/owner flags unchanged, sample " + str(index))
	_verify_visibility(hidden)
	var camera: Camera3D = _game.sea.camera
	return {"sample": index, "drawnFrame": Engine.get_frames_drawn(), "processFrame": Engine.get_process_frames(), "physicsFrame": Engine.get_physics_frames(), "nativeTick": native.current_tick(), "nativeTime": native.current_time(), "nativeStatus": native.current_status(), "authority": _authority_state(), "main": main_counters, "reflection": reflection_counters, "sourceClocks": _source_clocks(), "actorCounts": _actor_counts(), "camera": {"position": camera.global_position, "basis": camera.global_basis, "fov": camera.fov}, "visibility": _visibility()}

func _capture(label: String) -> void:
	await process_frame; await RenderingServer.frame_post_draw
	for entry: Dictionary in [{"viewport": root, "suffix": "main"}, {"viewport": _reflection, "suffix": "reflection"}]:
		var pixels: Image = entry.viewport.get_texture().get_image()
		if not check(pixels != null and not pixels.is_empty(), "real framebuffer " + label + "/" + entry.suffix): continue
		var name: String = label + "-" + entry.suffix + ".png"
		check(pixels.save_png(output.path_join(name)) == OK, "capture saved " + name)
		captures.append({"image": name, "sha256": FileAccess.get_sha256(output.path_join(name)), "size": [pixels.get_width(), pixels.get_height()], "nativeTick": _game.runtime.simulation.current_tick(), "authority": _authority_state(), "visibility": _visibility()})

func _epoch(label: String, hidden: String) -> bool:
	_restore_visibility(); _verify_visibility("")
	if not _authority_guard(label + "/before-visibility"): return false
	for entry: Dictionary in _targets:
		if entry.category == hidden: entry.node.visible = false
	if not await _live_frames(warmup_frames, label + "/warmup"):
		_restore_visibility(); _verify_visibility(""); return false
	var start_tick: int = _game.runtime.simulation.current_tick()
	var clocks_before := _source_clocks()
	var samples: Array = []
	for index: int in sample_count:
		await process_frame; await RenderingServer.frame_post_draw
		var sample: Dictionary = _sample(index, hidden)
		samples.append(sample)
		if not _authority_guard(label + "/sample-" + str(index), sample.authority): break
	var end_tick: int = _game.runtime.simulation.current_tick()
	if not _interruption.is_empty():
		epochs.append({"label": label, "hiddenCategory": hidden, "aborted": true, "startNativeTick": start_tick, "endNativeTick": end_tick, "sourceClocksBefore": clocks_before, "sourceClocksAfter": _source_clocks(), "samples": samples, "authority": _authority_state(), "flags": _flags(), "actors": _actors(), "visibility": _visibility()})
		_restore_visibility(); _verify_visibility(""); return false
	check(end_tick > start_tick, "native ticks advance during " + label)
	check(_source_clocks().worldTime > clocks_before.worldTime, "production world algorithm continues during " + label)
	check(_source_clocks().atmosphereTime > clocks_before.atmosphereTime, "production atmosphere algorithm continues during " + label)
	for index in clocks_before.shore.size(): check(_source_clocks().shore[index].time > clocks_before.shore[index].time, "production shore algorithm continues during " + label + "/" + str(index))
	check(_actors() == _initial_actors, "actor/shore topology unchanged during " + label)
	_verify_visibility(hidden)
	await _capture(label)
	var capture_running := _authority_guard(label + "/after-capture")
	epochs.append({"label": label, "hiddenCategory": hidden, "aborted": not capture_running, "startNativeTick": start_tick, "endNativeTick": end_tick, "sourceClocksBefore": clocks_before, "sourceClocksAfter": _source_clocks(), "samples": samples, "authority": _authority_state(), "flags": _flags(), "actors": _actors(), "visibility": _visibility()})
	_restore_visibility(); _verify_visibility("")
	print("WORKLOAD_EPOCH label=", label, " samples=", samples.size(), " nativeTicks=", start_tick, "..", end_tick)
	return capture_running

func _run() -> void:
	_started_utc = Time.get_datetime_string_from_system(true)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		elif argument.begins_with("--samples="): sample_count = int(argument.trim_prefix("--samples="))
		elif argument.begins_with("--warmup="): warmup_frames = int(argument.trim_prefix("--warmup="))
		elif argument == "--skip-ocean": include_ocean = false
		elif argument == "--skip-atmosphere": include_atmosphere = false
		else: check(false, "unknown census flag " + argument)
	check(DisplayServer.get_name() != "headless", "real graphics backend required; no fabricated headless counters")
	check(RenderingServer.get_current_rendering_method() == "forward_plus", "actual production Forward+ backend")
	check(ClassDB.class_has_method("RenderingServer", "viewport_get_render_info"), "native per-viewport counter API present")
	check(sample_count >= 12 and sample_count <= 32 and warmup_frames >= 3 and warmup_frames <= 60, "12..32 drawn samples and 3..60 settling frames")
	check(not output.is_empty() and output.begins_with("res://") and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output)), "fresh res:// evidence directory required")
	if not failures.is_empty(): await _finish(); return
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output)) == OK, "new evidence directory created")
	if not failures.is_empty(): await _finish(); return
	_created_output = true; _source_hashes = _hashes(); _persisted_before = _persisted()
	_window_flags = {"size": root.size, "contentSize": root.content_scale_size, "contentMode": root.content_scale_mode, "unresizable": root.unresizable, "unfocusable": root.unfocusable, "guiDisableInput": root.gui_disable_input}
	root.size = Vector2i(1600, 900); root.content_scale_size = root.size; root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.unresizable = true; root.unfocusable = false; root.gui_disable_input = true
	root.focus_entered.connect(_record_window_event.bind("focus_entered"))
	root.focus_exited.connect(_record_window_event.bind("focus_exited"))
	root.grab_focus(); _record_window_event("startup-grab-focus-once")
	var career := MemorySlot.new(); var legacy := MemorySlot.new()
	_slots = [career, legacy]; _settings = MemorySettings.new()
	_main = Main.new(); _main.router = Router.new({"mingqi_storage": career, "legacy_storage": legacy, "settings_storage": _settings})
	root.add_child(_main); await _frames(4)
	_record_entry()
	var button: Button = _main.menu.find_child("sail", true, false)
	if not check(button != null and button.is_visible_in_tree() and not button.disabled, "ordinary public sail button enabled"): await _finish(); return
	check(_main.menu.draft_name() == _settings.snapshot().captainName, "public menu and memory settings preconfirm the same normalized name")
	button.pressed.emit()
	_record_entry()
	for _frame in 400:
		await process_frame
		var entry: Dictionary = _record_entry()
		if is_instance_valid(_main.current_scene) and _main.current_scene.get("startup_receipt").get("ok", false): break
		if entry.phase == "error": break
	if not check(is_instance_valid(_main.current_scene), "public Router activated actual scene: " + JSON.stringify(_entry_receipt())): await _finish(); return
	_game = _main.current_scene
	check(_game.get_script().resource_path == "res://game/scenes/naval_practice/naval_practice.gd", "actual NavalPractice production source")
	check(_game.startup_receipt.get("ok", false) and _game.runtime.snapshot().runtime.mode == "sail", "normal sail route initialized")
	check(_game.runtime.simulation.encounter.config.get("seed") == 1661, "production fixed seed 1661")
	check(_settings.snapshot().quality == "balanced", "balanced injected before initial scene configuration")
	_world = _game.sea.world; _ocean = _world.get_ocean(); _reflection = _ocean.get_reflection_viewport(); _atmosphere = _world.atmosphere
	_record_window_event("startup-before-initial-blur-clear")
	if root.has_focus():
		_game.runtime.set_pause("blur", false)
		_record_window_event("startup-initial-blur-clear-once")
	_initial_authority = _authority_state()
	if not _authority_guard("public-entry-before-warmup"): await _finish(); return
	if not await _live_frames(warmup_frames, "public-entry-warmup"): await _finish(); return
	if not check(is_instance_valid(_reflection) and is_instance_valid(_atmosphere), "actual planar reflection and source atmosphere available"): await _finish(); return
	var natural: Node3D = _world.get("_natural_world")
	if not check(is_instance_valid(natural), "public sail real natural world available"): await _finish(); return
	for shore: Node3D in natural.get("_dynamic_shore"): _add_target(shore, "shore")
	_add_target(_ocean, "ocean"); _add_target(_atmosphere.get("_container"), "atmosphere")
	_initial_flags = _flags(); _initial_actors = _actors()
	check(_initial_actors.shipActors == 3 and _initial_actors.crewActors == 3, "all public sail ships and 3D crew owners present")
	check(_initial_actors.shoreOwners > 0 and _initial_actors.shoreMeshInstanceNodes == 1704, "expected 1704 shore MeshInstance nodes, explicitly not draw calls")
	check(_initial_flags.sceneProcess and _initial_flags.scenePhysicsProcess, "production automatic process/physics remain enabled")
	check(_initial_flags.reflectionUpdateMode == SubViewport.UPDATE_ALWAYS, "actual reflection continues every drawn frame")
	check(_initial_flags.quality == "balanced" and _initial_flags.physicsTicksPerSecond == 60, "balanced production world and native 60Hz authority")
	if not failures.is_empty(): await _finish(); return
	var plan: Array = [{"label": "00-normal", "hidden": ""}, {"label": "01-shore-hidden", "hidden": "shore"}]
	if include_ocean: plan.append({"label": "02-ocean-hidden", "hidden": "ocean"})
	if include_atmosphere: plan.append({"label": "03-atmosphere-cloud-fog-weather-hidden", "hidden": "atmosphere"})
	plan.append({"label": "04-restored-normal", "hidden": ""})
	for entry: Dictionary in plan:
		if not await _epoch(entry.label, entry.hidden): break
	await _finish()

func _finish() -> void:
	if _finished: return
	_finished = true
	var actual_samples := 0
	for epoch: Dictionary in epochs: actual_samples += epoch.samples.size()
	_restore_visibility()
	var restored: Dictionary = {}
	var entry_final := _record_entry()
	if is_instance_valid(_game) and not _initial_flags.is_empty():
		_verify_visibility(""); check(_flags() == _initial_flags, "all inspected original rendering/process/owner flags restored")
		check(_actors() == _initial_actors, "all original actor and shoreline owners retained")
		restored = {"flags": _flags(), "visibility": _visibility(), "actors": _actors()}
		await _capture("99-final-restored")
		_verify_visibility("")
	var playbacks: Array[WeakRef] = []
	if is_instance_valid(_main):
		playbacks = AudioCleanup.stop_players(_main)
		_main.free(); _main = null
	await _frames(3)
	check(await AudioCleanup.wait_for_release(self, playbacks), "actual audio playback owners released before exit")
	for slot: RefCounted in _slots: check(slot.writes == 0, "no checkpoint write attempted")
	if _settings:
		check(_settings.memory_commits == 1 and _settings.rejected_updates == 0, "exactly one expected public-entry name confirmation committed in memory")
		check(_settings.disk_write_attempts == 0, "no personal settings disk write attempted")
	if _created_output:
		check(_persisted() == _persisted_before, "real saves/settings tree byte hashes unchanged")
		check(_hashes() == _source_hashes, "watched production and tool source hashes unchanged")
		var report := {"schemaVersion": 1, "recordType": "native-render-workload-census", "valid": failures.is_empty(), "assertions": assertions, "failures": failures, "startedAtUtc": _started_utc, "finishedAtUtc": Time.get_datetime_string_from_system(true), "engine": Engine.get_version_info(), "gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "displayServer": DisplayServer.get_name(), "api": {"method": "RenderingServer.viewport_get_render_info(viewport RID, ViewportRenderInfoType, ViewportRenderInfo)", "documentation": "https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-viewport-get-render-info", "passes": PASSES, "metrics": METRICS, "shadowMeaning": "Native SHADOW render pass; zero is retained as zero. Custom source shadow geometry can contribute to VISIBLE instead. Objects can repeat across passes, lights and viewports; do not add them as unique scene objects."}, "controls": {"route": "ordinary Main public sail button -> Router -> NavalPractice", "seed": 1661, "quality": "balanced", "viewport": [1600, 900], "samplesPerEpoch": sample_count, "settlingFramesPerEpoch": warmup_frames, "oceanIsolation": include_ocean, "atmosphereIsolation": include_atmosphere, "automaticProductionCallbacks": true, "vsyncChanged": false, "actorRemoval": false, "algorithmReplacement": false}, "initialFlags": _initial_flags, "initialActors": _initial_actors, "epochs": epochs, "captures": captures, "restored": restored, "sourcesBefore": _source_hashes, "sourcesAfter": _hashes(), "persistedBefore": _persisted_before, "persistedAfter": _persisted(), "scope": "Actual Forward+ per-viewport native workload counters after frame_post_draw. Sequential live epochs retain normal simulation and source presentation; native ticks/cameras differ and are recorded. Only whole visibility owners are hidden temporarily, independently, with restoration between epochs. Atmosphere owner includes clouds, fog, weather and baked cloud shadow meshes. 1704 is a shore MeshInstance NODE inventory, never a draw-call estimate. Counters expose submitted workload, not GPU elapsed time, pixel overdraw, unique objects, performance improvement or full-game FPS. No manual scene stage replay, sampler substitution, save/settings write or reduced-feature optimization claim."}
		report.startup = {"states": _entry_states, "final": entry_final, "settingsAudit": _settings.audit() if _settings else {}}
		report.authority = {"initial": _initial_authority, "interruption": _interruption, "windowEvents": _window_events, "focusPolicy": "One startup grab_focus and one initial blur clear only while root already has focus, both before census epochs. Then fail immediately on focus loss or any runtime/SceneTree pause. No per-frame set_pause, resume or repeated focus grab."}
		report.actualSamples = actual_samples
		var file := FileAccess.open(output.path_join("WORKLOAD_CENSUS.json"), FileAccess.WRITE)
		if check(file != null, "census report output opens"):
			report.assertions = assertions; report.valid = failures.is_empty(); report.failures = failures.duplicate()
			file.store_string(JSON.stringify(report, "\t")); file.close()
	if not _window_flags.is_empty():
		root.size = _window_flags.size; root.content_scale_size = _window_flags.contentSize; root.content_scale_mode = _window_flags.contentMode
		root.unresizable = _window_flags.unresizable; root.unfocusable = _window_flags.unfocusable; root.gui_disable_input = _window_flags.guiDisableInput
	print("ARCHITECTURE_WORKLOAD_GPU assertions=", assertions, " epochs=", epochs.size(), " samples=", actual_samples, " captures=", captures.size(), " failures=", failures.size())
	quit(1 if not failures.is_empty() else 0)
