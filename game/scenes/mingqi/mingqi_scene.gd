extends Node3D
## Native opening composition; all game authority remains in MingqiRuntime.
signal main_menu_requested
const Runtime = preload("res://game/runtime/mingqi_runtime.gd")
const Storage = preload("res://game/persistence/save_coordinator.gd")
const HeightField = preload("res://modules/scene_engine/terrain/height_field.gd")
const WorldView = preload("res://modules/scene_engine/world/world_view.gd")
const Library = preload("res://modules/scene_engine/assets/asset_library.gd")
const WaveDescriptor = preload("res://modules/contracts/wave_descriptor.gd")
const ShipView = preload("res://game/presentation/ships/ship_view.gd")
const CrewView = preload("res://game/presentation/crew/crew_view.gd")
const Effects = preload("res://game/presentation/combat/combat_effects.gd")
const Interface = preload("res://game/ui/mingqi/mingqi_interface.gd")
var runtime := Runtime.new()
var storage := Storage.new()
var heights := HeightField.new()
var library := Library.new()
var world: Node3D
var camera: Camera3D
var interface: CanvasLayer
var effects: Node3D
var ships: Dictionary = {}
var sailors: Dictionary = {}
var tactical := false
var _capture_mode := false
var _disposed := false
var _zoom := 1.0
var _camera_follow := Vector3.ZERO
var _camera_ready := false
const KEYS := {KEY_W:"KeyW",KEY_S:"KeyS",KEY_A:"KeyA",KEY_D:"KeyD",KEY_UP:"ArrowUp",KEY_DOWN:"ArrowDown",KEY_LEFT:"ArrowLeft",KEY_RIGHT:"ArrowRight",KEY_BRACKETLEFT:"BracketLeft",KEY_BRACKETRIGHT:"BracketRight"}
func _ready() -> void:
	DisplayServer.window_set_title("海上明旗 · 1650 厦金护粮")
	Engine.physics_ticks_per_second = 60; get_viewport().msaa_3d = Viewport.MSAA_4X
	_capture_mode = "--capture-mingqi" in OS.get_cmdline_user_args()
	var geography: Array = JSON.parse_string(FileAccess.get_file_as_string("res://game/data/mingqi_geography.json"))
	if not heights.configure_ports(geography) or not runtime.configure(heights.sample_height).ok: push_error("Mingqi native startup failed"); get_tree().quit(1); return
	var env := WorldEnvironment.new(); var lighting := Environment.new()
	lighting.background_mode = Environment.BG_COLOR; lighting.background_color = Color("87ceeb")
	lighting.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; lighting.ambient_light_color = Color("a0c8ff"); lighting.ambient_light_energy = 0.45; lighting.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = lighting; add_child(env)
	var sun := DirectionalLight3D.new(); add_child(sun); sun.position = Vector3(300,150,100); sun.look_at(Vector3.ZERO); sun.light_energy = 1.2; sun.shadow_enabled = true
	camera = Camera3D.new(); add_child(camera); camera.current = true; camera.fov = 55; camera.near = 0.5; camera.far = 4000
	_update_camera(runtime.snapshot().naval,0)
	world = WorldView.new(); add_child(world)
	if not world.configure(heights.sample_height,WaveDescriptor.original_descriptors(),{"camera":camera,"ports":geography,"resolution":64,"chunk_radius":2,"collision":false,"visual_style":1}): push_error("Mingqi world failed"); get_tree().quit(1); return
	effects = Effects.new(); add_child(effects)
	interface = Interface.new(); add_child(interface); interface.command_requested.connect(_command); interface.view_requested.connect(func(value: bool): tactical = value)
	_present(0)
	if _capture_mode: _capture_run.call_deferred()
func _utc() -> String: return Time.get_datetime_string_from_system(true)+".000Z"
func _command(intent: Dictionary) -> void:
	var result: Dictionary
	match intent.get("type"):
		"save","save-and-menu":
			result = runtime.save_checkpoint(storage,_utc())
			if result.ok and intent.type == "save-and-menu": main_menu_requested.emit()
		"export-save":
			result = storage.read_backup() if intent.get("kind") == "backup" else runtime.export_save(_utc())
			if result.ok: DisplayServer.clipboard_set(result.json)
		"import-save":
			result = runtime.adopt_save(intent.get("json",""),storage,_utc())
			if result.ok: runtime.set_pause("loading",false); runtime.set_pause("menu",true)
		_: result = runtime.command(intent)
	if not result.ok: runtime._notify(result.get("reason","command-rejected"))
	_present(0)
func _physics_process(delta: float) -> void:
	if not world or _capture_mode: return
	if interface.captures_keyboard():
		for code in KEYS.values(): runtime.set_held(code,false)
	effects.observe_projectiles(runtime.simulation.snapshot())
	var consumed: float = runtime.advance(delta)
	_present(consumed)
func _update_camera(native: Dictionary,delta: float) -> void:
	var active: Dictionary = Runtime._ship(native,native.playerId)
	if active.is_empty(): return
	var point: Dictionary = active.visual.position; var target := Vector3(point.x,point.y+3,point.z)
	# Smooth only target-follow; horizon/camera up remains stable during hull roll.
	if not _camera_ready or delta <= 0: _camera_follow = target; _camera_ready = true
	else: _camera_follow = _camera_follow.lerp(target,1-exp(-6*delta))
	camera.position = _camera_follow+(Vector3(80,115,-110) if tactical else Vector3(33,24,-39))*_zoom
	camera.look_at(_camera_follow)
func _present(consumed: float) -> void:
	if not world: return
	var packet: Dictionary = runtime.snapshot(); var native: Dictionary = packet.naval
	_update_camera(native,consumed)
	var requests: Array = []
	for ship: Dictionary in native.ships:
		var point: Dictionary = ship.visual.position; var distance := camera.position.distance_to(Vector3(point.x,point.y,point.z))
		requests.append({"id":ship.id,"distance":distance,"requested":mini(24,int(ship.crew)) if distance <= 220 else mini(8,int(ship.crew)) if distance <= 650 else mini(2,int(ship.crew)) if distance <= 1200 else 0})
	var allocation: Dictionary = CrewView.allocate_sailors(requests)
	var ids: Array = []
	for ship: Dictionary in native.ships:
		ids.append(ship.id)
		if not ships.has(ship.id):
			var view := ShipView.new(); add_child(view)
			if not view.configure(ship.kind,library): push_error("Ship import failed: "+ship.kind); view.queue_free(); continue
			var crew := CrewView.new(); view.add_child(crew)
			if not crew.configure(ship.kind,view.get_model(),library): push_error("Crew import failed: "+ship.kind)
			crew.set_environment(runtime.sample_water_height); ships[ship.id] = view; sailors[ship.id] = crew
		var view: Node3D = ships[ship.id]; var crew: Node3D = sailors[ship.id]
		view.apply_snapshot(ship,native.wind,consumed); var distance := camera.position.distance_to(view.position)
		view.set_lod_distance(distance); crew.set_ship_model(view.get_model()); crew.set_lod_distance(distance); crew.set_allocation(allocation.get(ship.id,0))
		var timed := ship.duplicate(true); timed.time = native.time; crew.apply_snapshot(timed,native.wind,consumed)
	for id in ships.keys():
		if not id in ids: sailors[id].dispose(); ships[id].dispose(); ships[id].queue_free(); ships.erase(id); sailors.erase(id)
	var events: Array = effects.presentation_events(runtime.drain_events())
	for id in ships: ships[id].apply_events(events); sailors[id].apply_events(events)
	effects.apply_snapshot(native,consumed); effects.apply_events(events)
	world.apply_snapshot({"time":native.time,"focus":Runtime._ship(native,native.playerId).visual.position},consumed)
	interface.apply_snapshot(packet)
func _input(event: InputEvent) -> void:
	if not interface or not event is InputEventKey or not event.pressed or event.echo: return
	if event.physical_keycode == KEY_ESCAPE:
		if runtime.snapshot().runtime.pauseReasons.has("menu"): interface.close_menu()
		else: interface.open_menu()
		get_viewport().set_input_as_handled(); return
	if event.physical_keycode == KEY_SPACE and not interface.captures_keyboard():
		runtime.command({"type":"pause"}); get_viewport().set_input_as_handled()
func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or event.echo: return
	if KEYS.has(event.physical_keycode):
		if not event.pressed or not interface.captures_keyboard(): runtime.set_held(KEYS[event.physical_keycode],event.pressed)
		return
	if not event.pressed or interface.captures_keyboard(): return
	match event.physical_keycode:
		KEY_SPACE: runtime.command({"type":"pause"})
		KEY_1: tactical = false
		KEY_2: tactical = true
		KEY_R: runtime.simulation.toggle_trim()
		KEY_Q,KEY_Z: runtime.command({"type":"fire","side":"port"})
		KEY_E,KEY_X: runtime.command({"type":"fire","side":"starboard"})
		KEY_ESCAPE: interface.open_menu()
		KEY_F12: _capture("manual-%d"%Time.get_unix_time_from_system())
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: _zoom = clampf(_zoom*0.9,0.55,2)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: _zoom = clampf(_zoom*1.1,0.55,2)
func _capture_run() -> void:
	interface.open_panel("convoy")
	for i in 8: await get_tree().process_frame
	await _capture("opening")
	var packet: Dictionary = runtime.snapshot()
	var accepted: Dictionary = runtime.command({"type":"accept-convoy","commandId":"native-capture-accept","expectedRevision":packet.campaign.revision})
	if not accepted.ok: push_error("Capture failed to accept convoy"); get_tree().quit(1); return
	interface.open_panel("ship"); _present(0)
	for i in 8: await get_tree().process_frame
	await _capture("loaded-fleet")
	packet = runtime.snapshot()
	var departed: Dictionary = runtime.command({"type":"depart","commandId":"native-capture-depart","expectedRevision":packet.campaign.revision})
	if not departed.ok: push_error("Capture failed to depart"); get_tree().quit(1); return
	runtime.set_held("KeyW",true)
	for tick in 300: runtime.advance(1.0/60)
	runtime.set_held("KeyW",false); interface.close_panel(); _present(5)
	for i in 8: await get_tree().process_frame
	await _capture("sailing-water")
	tactical = true; interface.open_panel("convoy"); _present(0)
	for i in 8: await get_tree().process_frame
	await _capture("departed-tactical")
	interface.visible = false
	# Six accepted seconds cover a full coastal breaker cycle; disk capture time
	# is deliberately separate from simulation time and is not an FPS benchmark.
	for frame in 72:
		var consumed: float = runtime.advance(1.0/12)
		_present(consumed)
		camera.position = Vector3(-480,270,185); camera.look_at(Vector3(-480,0,-60))
		world.get_ocean().update_projection()
		for i in 2: await get_tree().process_frame
		await _capture("shore-wave-"+str(frame).pad_zeros(2))
	interface.visible = true
	print("NATIVE_MINGQI_CAPTURE_COMPLETE ships=",ships.size()," tick=",runtime.snapshot().naval.tick)
	get_tree().quit()
func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var directory := "res://docs/migration/evidence/mingqi"; DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var png: String = directory+"/"+label+".png"; var result := get_viewport().get_texture().get_image().save_png(png)
	var metadata := runtime.snapshot(); metadata.engine = Engine.get_version_info(); metadata.gpu = RenderingServer.get_video_adapter_name(); metadata.camera = {"position":[camera.position.x,camera.position.y,camera.position.z],"tactical":tactical}; metadata.uiVisible = interface.visible; metadata.viewport = [get_viewport().size.x,get_viewport().size.y]; metadata.frameTimeMs = Performance.get_monitor(Performance.TIME_PROCESS)*1000; metadata.effects = effects.diagnostics(); metadata.sailors = {}
	for id in sailors: metadata.sailors[id] = sailors[id].diagnostics()
	var file := FileAccess.open(directory+"/"+label+".json",FileAccess.WRITE); file.store_string(JSON.stringify(metadata,"  ")); file.close()
	if result != OK: push_error("Native PNG save failed")
func _exit_tree() -> void:
	if _disposed: return
	_disposed = true
	for id in sailors: sailors[id].dispose()
	for id in ships: ships[id].dispose()
	if world: world.dispose()
	library.dispose(); runtime.dispose()
