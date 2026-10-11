extends Node3D
## Native1661 composition. Business/combat/encounter authority stays in Runtime.
signal main_menu_requested
const Runtime = preload("res://game/runtime/legacy_runtime.gd")
const Catalog = preload("res://game/domain/legacy/catalog.gd")
const Storage = preload("res://game/persistence/save_coordinator.gd")
const Height = preload("res://modules/scene_engine/terrain/height_field.gd")
const Sea = preload("res://game/presentation/world/naval_world_view.gd")
const Interface = preload("res://game/ui/legacy/legacy_interface.gd")
const EncounterInterface = preload("res://game/ui/encounters/encounter_interface.gd")
const Services = preload("res://game/scenes/common/sea_services.gd")
const SeaChart = preload("res://game/scenes/common/sea_chart_overlay.gd")
const KEYS := {KEY_W:"KeyW",KEY_S:"KeyS",KEY_A:"KeyA",KEY_D:"KeyD",KEY_UP:"ArrowUp",KEY_DOWN:"ArrowDown",KEY_LEFT:"ArrowLeft",KEY_RIGHT:"ArrowRight",KEY_BRACKETLEFT:"BracketLeft",KEY_BRACKETRIGHT:"BracketRight"}
const SHORTCUTS := {KEY_I:"KeyI",KEY_M:"KeyM",KEY_F:"KeyF",KEY_B:"KeyB",KEY_ESCAPE:"Escape"}
const ENCOUNTER_KEYS := {KEY_J:"KeyJ",KEY_K:"KeyK",KEY_L:"KeyL",KEY_U:"KeyU",KEY_I:"KeyI",KEY_O:"KeyO",KEY_SPACE:"Space",KEY_UP:"ArrowUp",KEY_DOWN:"ArrowDown",KEY_LEFT:"ArrowLeft",KEY_RIGHT:"ArrowRight",KEY_W:"KeyW",KEY_A:"KeyA",KEY_S:"KeyS",KEY_D:"KeyD",KEY_ENTER:"Enter"}
var runtime := Runtime.new()
var storage := Storage.new("user://saves/legacy-v1.json",Runtime.validate_save)
var settings_storage: RefCounted
var startup_options: Dictionary = {}
var initial_save := ""
var startup_receipt: Dictionary = {}
var sea: Node3D
var interface: CanvasLayer
var encounter_interface: Control
var services: Node
var minimap: CanvasLayer
var heights := Height.new()
var _expanded_chart: Control
var tactical := false
var _zoom := 1.0
var _disposed := false
var _capture_mode := false

func _ready() -> void:
	DisplayServer.window_set_title("海上明旗 · 1661 航海生涯")
	Engine.physics_ticks_per_second = 60; get_viewport().msaa_3d = Viewport.MSAA_4X
	_capture_mode = "--capture-legacy" in OS.get_cmdline_user_args()
	if not heights.configure_ports(Catalog.DATA.PORTS): push_error("Legacy geography failed"); return
	var options := startup_options.duplicate(true); options.storage = storage
	startup_receipt = runtime.configure(heights.sample_height,options)
	if not startup_receipt.ok: push_error("Legacy runtime startup: "+startup_receipt.get("reason","")); return
	if not initial_save.is_empty():
		startup_receipt = runtime.adopt_save(initial_save,storage)
		if not startup_receipt.ok: return
	sea = Sea.new(); add_child(sea)
	if not sea.configure(heights.sample_height,Catalog.DATA.PORTS,runtime.sample_water_height,runtime.snapshot().naval): push_error("Legacy world startup failed"); return
	services = Services.new(); add_child(services); services.configure(runtime,sea,settings_storage)
	interface = Interface.new(); add_child(interface)
	interface.set_readiness_provider(runtime.preview_command)
	interface.command_requested.connect(_command)
	interface.view_requested.connect(func(value: bool): tactical = value)
	var layer := CanvasLayer.new(); layer.layer = 35; add_child(layer)
	encounter_interface = EncounterInterface.new(); layer.add_child(encounter_interface)
	encounter_interface.command_requested.connect(_command)
	minimap = SeaChart.new(); add_child(minimap)
	if not minimap.configure(Catalog.DATA.PORTS,heights.sample_height): push_error("Legacy minimap failed"); return
	minimap.chart_requested.connect(func(): interface.open_panel("chart"); _present(0.0))
	_present(0.0)
	if not initial_save.is_empty(): interface.open_menu()
	if _capture_mode: _capture_run.call_deferred()

func _command(intent: Dictionary) -> Dictionary:
	var receipt: Dictionary
	var return_to_menu := false
	match intent.get("type",""):
		"panel":
			var value = intent.get("value",false)
			var opened: bool = not value.is_empty() if value is String else value if typeof(value) == TYPE_BOOL else false
			receipt = runtime.set_pause("panel",opened)
		"menu":
			receipt = runtime.set_pause("menu",bool(intent.get("value",false)))
			if receipt.ok and not intent.get("value",false): runtime.set_pause("loading",false)
		"settings": receipt = services.change_settings(intent.get("value",{}))
		"open-settings": services.open_settings(); receipt = {"ok":true}
		"main-menu": receipt = {"ok":true}; return_to_menu = true
		"save","save-and-menu":
			receipt = runtime.save_checkpoint(storage)
			return_to_menu = receipt.ok and intent.type == "save-and-menu"
		"export-save":
			receipt = storage.read_backup() if intent.get("kind") == "backup" else runtime.export_save()
			if receipt.ok: DisplayServer.clipboard_set(receipt.json)
		"import-save":
			var raw: String = intent.get("json","")
			if intent.has("path"):
				var file := FileAccess.open(intent.path,FileAccess.READ)
				if file == null: receipt = {"ok":false,"reason":"无法读取所选存档文件"}
				else: raw = file.get_as_text(); file.close()
			if receipt.is_empty(): receipt = runtime.adopt_save(raw,storage)
			if receipt.ok: interface.open_menu()
		_: receipt = runtime.command(intent)
	if not receipt.ok: runtime.notify(receipt.get("reason","command-rejected"))
	interface.acknowledge_command(intent,receipt)
	if receipt.ok and intent.get("type") == "navigate" and intent.get("point") != null:
		interface.close_panel()
	_present(0.0)
	if return_to_menu: main_menu_requested.emit()
	return receipt

func _present(consumed: float) -> void:
	if not sea: return
	var packet: Dictionary = runtime.snapshot()
	sea.tactical = tactical; sea.zoom = _zoom
	var events: Array = sea.apply_snapshot(packet.naval,runtime.drain_events(),consumed)
	services.present(packet.naval,events,consumed,bool(packet.runtime.paused))
	packet.settings = services.settings_storage.snapshot()
	interface.apply_snapshot(packet)
	var encounter = packet.runtime.get("encounter")
	encounter_interface.apply_snapshot(encounter if encounter is Dictionary else {},packet.runtime.revision)
	var chart: Control = interface.find_child("world_chart",true,false)
	if chart and chart != _expanded_chart:
		_expanded_chart = chart
		chart.configure(Catalog.DATA.PORTS,heights.sample_height)
	var overlays := SeaChart.navigation_overlays(packet.naval,{"activeObjectives":packet.adventure.get("activeObjectives",[]),"waypoint":packet.adventure.get("waypoint",{})})
	if chart: chart.apply_naval_snapshot(packet.naval,overlays)
	var result: Control = interface.find_child("result",true,false)
	if minimap: minimap.present(packet.naval,overlays,not interface.visible or interface.is_panel_open() or interface.is_menu_open() or encounter_interface.visible or services.captures_keyboard() or (result != null and result.visible))

func _physics_process(delta: float) -> void:
	if not sea or _capture_mode: return
	if interface.captures_keyboard() or services.captures_keyboard():
		for code in KEYS.values(): runtime.set_held(code,false)
	sea.observe_projectiles(runtime.native_snapshot())
	var consumed: float = runtime.advance(delta)
	_present(consumed)

func _input(event: InputEvent) -> void:
	if not interface or not event is InputEventKey or not event.pressed or event.echo: return
	var code: int = event.physical_keycode if event.physical_keycode else event.keycode
	if services.captures_keyboard():
		if code == KEY_ESCAPE: services.close_settings(); _present(0.0)
		get_viewport().set_input_as_handled(); return
	if encounter_interface.visible and ENCOUNTER_KEYS.has(code):
		encounter_interface.request_key(ENCOUNTER_KEYS[code]); get_viewport().set_input_as_handled(); return
	if code == KEY_ESCAPE:
		interface.request_shortcut("Escape"); get_viewport().set_input_as_handled()
	elif code == KEY_SPACE and not interface.captures_keyboard():
		_command({"type":"pause","reason":"player","value":not ("player" in runtime.snapshot().runtime.pauseReasons)})
		get_viewport().set_input_as_handled()

func _unhandled_key_input(event: InputEvent) -> void:
	if not interface or not event is InputEventKey: return
	var code: int = event.physical_keycode if event.physical_keycode else event.keycode
	if KEYS.has(code):
		runtime.set_held(KEYS[code],event.pressed and not interface.captures_keyboard() and not services.captures_keyboard())
		get_viewport().set_input_as_handled(); return
	if not event.pressed or event.echo or interface.captures_keyboard(): return
	if SHORTCUTS.has(code): interface.request_shortcut(SHORTCUTS[code])
	elif code in [KEY_1,KEY_2]: tactical = code == KEY_2; _present(0.0)
	elif code == KEY_R: _command({"type":"trim"})
	elif code in [KEY_Q,KEY_Z,KEY_E,KEY_X]:
		_command({"type":"native-action","action":{"type":"fire","shipId":runtime.snapshot().naval.playerId,"side":"port" if code in [KEY_Q,KEY_Z] else "starboard"}})
	else: return
	get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not sea or not event is InputEventMouseButton or not event.pressed: return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		_zoom = clampf(_zoom*0.92 if event.button_index == MOUSE_BUTTON_WHEEL_UP else _zoom/0.92,0.55,2.0)
		_present(0.0); get_viewport().set_input_as_handled()

func _capture_run() -> void:
	interface.open_panel("market")
	for tick in 8: await get_tree().process_frame
	await _capture("opening-market")
	interface.open_panel("chart")
	for tick in 4: await get_tree().process_frame
	await _capture("six-port-chart")
	interface.close_panel(); _command({"type":"depart"}); runtime.set_held("KeyW",true)
	for tick in 180: _present(runtime.advance(1.0/60.0))
	runtime.set_held("KeyW",false)
	for tick in 4: await get_tree().process_frame
	await _capture("sailing")
	interface.visible = false
	sea.camera.position = Vector3(-480,270,185); sea.camera.look_at(Vector3(-480,0,-60))
	sea.world.get_ocean().update_projection()
	for tick in 6: await get_tree().process_frame
	await _capture("island-shore")
	sea.camera.position = Vector3(-280,80,70); sea.camera.look_at(Vector3(-320,0,-40))
	sea.world.get_ocean().update_projection()
	for tick in 6: await get_tree().process_frame
	await _capture("harbor-details")
	print("NATIVE_LEGACY_CAPTURE_COMPLETE ships=",sea.ships.size()," tick=",runtime.native_snapshot().tick)
	get_tree().quit()

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var directory := "res://docs/migration/evidence/legacy"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(directory+"/"+label+".png")
	if error != OK: push_error("Legacy capture failed: "+str(error))
	var file := FileAccess.open(directory+"/"+label+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"viewport":[image.get_width(),image.get_height()],"cameraPosition":[sea.camera.position.x,sea.camera.position.y,sea.camera.position.z],"uiVisible":interface.visible,"packet":runtime.snapshot(),"audio":services.audio.diagnostics()},"\t")); file.close()

func _exit_tree() -> void:
	if _disposed: return
	_disposed = true
	if services: services.dispose()
	if minimap: minimap.dispose()
	if sea: sea.dispose()
	runtime.dispose()
