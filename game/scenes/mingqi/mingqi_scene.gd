extends Node3D
## Native opening composition; all game authority remains in MingqiRuntime.
signal main_menu_requested
const Runtime = preload("res://game/runtime/mingqi_runtime.gd")
const Campaign = preload("res://game/domain/mingqi/campaign.gd")
const Storage = preload("res://game/persistence/save_coordinator.gd")
const HeightField = preload("res://modules/scene_engine/terrain/height_field.gd")
const ReferenceGeography = preload("res://game/scenes/common/reference_geography.gd")
const NavalWorldView = preload("res://game/presentation/world/naval_world_view.gd")
const Interface = preload("res://game/ui/mingqi/mingqi_interface.gd")
const Services = preload("res://game/scenes/common/sea_services.gd")
const SeaChart = preload("res://game/scenes/common/sea_chart_overlay.gd")
var runtime := Runtime.new()
var storage := Storage.new()
var heights := HeightField.new()
var sea: Node3D
var services: Node
var minimap: CanvasLayer
var settings_storage: RefCounted
var startup_options: Dictionary = {}
var initial_save: String = ""
var startup_receipt: Dictionary = {}
var library: RefCounted
var world: Node3D
var camera: Camera3D
var interface: CanvasLayer
var effects: Node3D
var ships: Dictionary = {}
var sailors: Dictionary = {}
var tactical := false
var _capture_mode := false
var _disposed := false
var _activated := false
var _zoom := 1.0
var _verified_checkpoint := ""
var _save_status := ""
const KEYS := {KEY_W:"KeyW",KEY_S:"KeyS",KEY_A:"KeyA",KEY_D:"KeyD",KEY_UP:"ArrowUp",KEY_DOWN:"ArrowDown",KEY_LEFT:"ArrowLeft",KEY_RIGHT:"ArrowRight",KEY_BRACKETLEFT:"BracketLeft",KEY_BRACKETRIGHT:"BracketRight"}
func _ready() -> void:
	_capture_mode = "--capture-mingqi" in OS.get_cmdline_user_args()
	var options := _validate_startup_options()
	if not options.ok: startup_receipt = options; return
	var geography: Array = JSON.parse_string(FileAccess.get_file_as_string("res://game/data/mingqi_geography.json"))
	if not heights.configure_ports(geography,true,ReferenceGeography.options()): startup_receipt = {"ok":false,"reason":"geography-invalid"}; return
	runtime.enable_reference_enhancements()
	startup_receipt = runtime.configure(heights.sample_height,Campaign.new(options.seed,options.captainName,options.campaignId))
	if not startup_receipt.ok: return
	if not initial_save.is_empty():
		# Continue reads a confirmed slot. Only explicit import/save may rotate disk.
		startup_receipt = runtime.adopt_save(initial_save,null,_utc())
		if not startup_receipt.ok: return
		_confirm_checkpoint(initial_save)
	if startup_options.get("staged",false): runtime.set_pause("loading",true)
	sea = NavalWorldView.new(); add_child(sea)
	if not sea.configure(heights.sample_height,geography,runtime.sample_water_height,runtime.snapshot().naval): _reject_startup("world-startup-failed"); return
	_sync_view_handles()
	services = Services.new(); add_child(services); services.configure(runtime,sea,settings_storage)
	interface = Interface.new(); add_child(interface); interface.command_requested.connect(_command); interface.view_requested.connect(func(value: bool): tactical = value)
	if not interface.configure_chart(heights.sample_height): _reject_startup("fleet-chart-startup-failed"); return
	minimap = SeaChart.new(); add_child(minimap)
	if not minimap.configure(geography,heights.sample_height,{"bounds":Rect2(-850,-350,1550,1000)}): _reject_startup("minimap-startup-failed"); return
	minimap.chart_requested.connect(func(): interface.open_panel("convoy"); _present(0.0))
	_present(0)
	if not initial_save.is_empty(): interface.open_menu()
	startup_receipt = {"ok":true}
	if not startup_options.get("staged",false): activate_entry()
	if _capture_mode: _capture_run.call_deferred()
func activate_entry() -> Dictionary:
	if _disposed or not startup_receipt.get("ok",false): return {"ok":false,"reason":"entry-startup-unconfirmed"}
	if _activated: return {"ok":true}
	_activated = true
	get_window().title = "海上明旗 · 1650 厦金护粮"
	Engine.physics_ticks_per_second = 60; get_viewport().msaa_3d = Viewport.MSAA_4X
	if initial_save.is_empty(): runtime.set_pause("loading",false)
	_present(0.0)
	return {"ok":true}
func _validate_startup_options() -> Dictionary:
	var seed: Variant = startup_options.get("seed",1650)
	var captain: Variant = startup_options.get("captainName","林船长")
	var id: Variant = startup_options.get("campaignId","mingqi-1650")
	if not startup_options.get("staged",false) is bool: return {"ok":false,"reason":"invalid-options"}
	if not seed is int or seed < 0 or seed > 4294967295: return {"ok":false,"reason":"invalid-options"}
	if not captain is String or Campaign._has_controls(captain): return {"ok":false,"reason":"invalid-options"}
	captain = captain.strip_edges()
	if captain.is_empty() or captain.length() > 24 or not Campaign._valid_id(id): return {"ok":false,"reason":"invalid-options"}
	return {"ok":true,"seed":seed,"captainName":captain,"campaignId":id}
func _reject_startup(reason: String) -> void:
	startup_receipt = {"ok":false,"reason":reason}
	if services: services.dispose(); services.free(); services = null
	if minimap: minimap.dispose(); minimap.free(); minimap = null
	if interface: interface.free(); interface = null
	if sea: sea.dispose(); sea.free(); sea = null
	world = null; camera = null; effects = null; ships.clear(); sailors.clear()

func _utc() -> String: return Time.get_datetime_string_from_system(true)+".000Z"
func _confirm_checkpoint(expected: String = "") -> void:
	# Recovery exports the last confirmed checkpoint, not arbitrary backup files.
	# Continue verifies the exact original bytes without writing or rotating disk.
	var read: Dictionary = storage.read_checkpoint()
	if read.get("ok",false) and (expected.is_empty() or read.json == expected): _verified_checkpoint = read.json
func _checkpoint_export() -> Dictionary:
	return {"ok":true,"json":_verified_checkpoint} if not _verified_checkpoint.is_empty() else {"ok":false,"reason":"save-not-found"}
func _save_failure(reason: String) -> String:
	return {"save-directory-failed":"无法创建存档目录。", "save-write-failed":"存档写入失败。", "save-readback-failed":"存档读回不一致，未确认保存。", "save-read-failed":"存档读取失败。", "save-invalid":"存档无效或版本不受支持。", "save-not-found":"没有上次已验证的安全存档。", "save-replace-failed":"存档替换失败，保留上次安全存档。", "save-backup-failed":"存档备份失败。", "save-recovery-failed":"存档恢复失败。"}.get(reason,interface._reason(reason))
func _command(intent: Dictionary) -> void:
	var result: Dictionary
	match intent.get("type"):
		"menu":
			result = runtime.command(intent)
			if result.ok and intent.get("value") == false: runtime.set_pause("loading",false)
		"open-settings": services.open_settings(); result = {"ok":true}
		"settings": result = services.change_settings(intent.get("value",{}))
		"save","save-and-menu":
			result = runtime.save_checkpoint(storage,_utc())
			if result.ok: _confirm_checkpoint()
			_save_status = "航程已验证并保存。" if result.ok else "未能保存："+_save_failure(result.get("reason","save-write-failed"))
			if result.ok and intent.type == "save-and-menu": main_menu_requested.emit()
		"export-save":
			result = _checkpoint_export() if intent.get("kind") == "backup" else runtime.export_save(_utc())
			if result.ok: DisplayServer.clipboard_set(result.json)
			_save_status = "存档已导出。" if result.ok else "未能导出："+_save_failure(result.get("reason","save-not-found"))
			if result.ok: runtime._notify(_save_status)
		"import-save":
			result = runtime.adopt_save(intent.get("json",""),storage,_utc())
			if result.ok:
				_confirm_checkpoint(); interface.open_menu()
			_save_status = "存档已验证、保存并载入。准备好后继续航行。" if result.ok else "导入未成功："+_save_failure(result.get("reason","save-invalid"))
		_: result = runtime.command(intent)
	if not result.ok: runtime._notify(result.get("reason","command-rejected"))
	_present(0)
func _physics_process(delta: float) -> void:
	if not world or _capture_mode: return
	if interface.captures_keyboard() or services.captures_keyboard():
		for code in KEYS.values(): runtime.set_held(code,false)
	sea.observe_projectiles(runtime.simulation.snapshot())
	var consumed: float = runtime.advance(delta)
	_present(consumed)
func _update_camera(native: Dictionary,delta: float) -> void:
	sea.tactical = tactical; sea.zoom = _zoom; sea._update_camera(native,delta)
func _sync_view_handles() -> void:
	world = sea.world; camera = sea.camera; effects = sea.effects
	library = sea.library; ships = sea.ships; sailors = sea.sailors
func _present(consumed: float) -> void:
	if not world: return
	var packet: Dictionary = runtime.snapshot(); var native: Dictionary = packet.naval
	packet.runtime.hasCheckpoint = not _verified_checkpoint.is_empty()
	packet.runtime.saveStatus = _save_status
	sea.tactical = tactical; sea.zoom = _zoom
	var events: Array = sea.apply_snapshot(native,runtime.drain_events(),consumed)
	_sync_view_handles()
	services.present(native,events,consumed,bool(packet.runtime.paused))
	interface.apply_snapshot(packet)
	if minimap: minimap.present(native,{},not interface.visible or interface.is_panel_open() or interface.is_menu_open() or services.captures_keyboard())
func _input(event: InputEvent) -> void:
	if not interface or not event is InputEventKey or not event.pressed or event.echo: return
	var code: int = event.physical_keycode if event.physical_keycode else event.keycode
	if services.captures_keyboard():
		if code == KEY_ESCAPE: services.close_settings(); _present(0.0)
		get_viewport().set_input_as_handled(); return
	if code == KEY_ESCAPE:
		if runtime.snapshot().runtime.pauseReasons.has("menu"): interface.close_menu()
		else: interface.open_menu()
		get_viewport().set_input_as_handled(); return
	if code == KEY_SPACE and not interface.captures_keyboard():
		runtime.command({"type":"pause"}); get_viewport().set_input_as_handled()
func _unhandled_key_input(event: InputEvent) -> void:
	if not interface or not event is InputEventKey or event.echo: return
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
	if services: services.dispose()
	if minimap: minimap.dispose()
	if sea: sea.dispose()
	runtime.dispose()
