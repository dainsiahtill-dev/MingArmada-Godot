extends Node3D
signal main_menu_requested
const Runtime=preload("res://game/runtime/naval_practice_runtime.gd")
const Height=preload("res://modules/scene_engine/terrain/height_field.gd")
const Catalog=preload("res://game/domain/legacy/catalog.gd")
const Sea=preload("res://game/presentation/world/naval_world_view.gd")
const Services=preload("res://game/scenes/common/sea_services.gd")
const Interface=preload("res://game/ui/naval_practice.gd")
const Chart=preload("res://game/scenes/common/sea_chart_overlay.gd")
const TerminalPresentation=preload("res://game/scenes/common/terminal_presentation_clock.gd")
const MouseCourse=preload("res://game/scenes/common/mouse_course_projection.gd")
const KEYS:={KEY_W:"KeyW",KEY_S:"KeyS",KEY_A:"KeyA",KEY_D:"KeyD",KEY_UP:"ArrowUp",KEY_DOWN:"ArrowDown",KEY_LEFT:"ArrowLeft",KEY_RIGHT:"ArrowRight",KEY_BRACKETLEFT:"BracketLeft",KEY_BRACKETRIGHT:"BracketRight"}
var startup_options: Dictionary={"mode":"duel"}
var startup_receipt: Dictionary={}
var settings_storage: RefCounted
var runtime:=Runtime.new()
var heights:=Height.new()
var sea: Node3D
var interface: CanvasLayer
var services: Node
var minimap: CanvasLayer
var _disposed:=false
var _terminal_presentation:=TerminalPresentation.new()
var _mouse_course:=MouseCourse.new()
var _pending_presentation_seconds := 0.0
var _presentation_epoch := ""
func _ready() -> void:
	if not heights.configure_ports(Catalog.DATA.PORTS,false,preload("res://game/scenes/common/reference_geography.gd").options()): startup_receipt={"ok":false,"reason":"practice-geography-failed"}; return
	startup_receipt=runtime.configure(heights.sample_height,startup_options)
	if not startup_receipt.ok: return
	if startup_options.get("staged",false): runtime.set_pause("loading",true)
	settings_storage = Services.resolve_settings(settings_storage)
	sea=Sea.new(); add_child(sea)
	sea.apply_settings(settings_storage.snapshot())
	if not sea.configure(heights.sample_height,Catalog.DATA.PORTS,runtime.sample_water_height,runtime.snapshot().naval): startup_receipt={"ok":false,"reason":"practice-world-failed"}; return
	services=Services.new(); add_child(services); services.configure(runtime,sea,settings_storage)
	interface=Interface.new(); add_child(interface); interface.command_requested.connect(_command); interface.view_requested.connect(func(value): sea.tactical=value)
	if not interface.configure_chart(Catalog.DATA.PORTS,heights.sample_height): startup_receipt={"ok":false,"reason":"practice-chart-failed"}; return
	minimap=Chart.new(); add_child(minimap); minimap.configure(Catalog.DATA.PORTS,heights.sample_height)
	minimap.chart_requested.connect(func(): _command({"type":"chart","value":true}))
	_present(0)
	if not startup_options.get("staged",false): activate_entry()
func activate_entry() -> void:
	if not startup_receipt.get("ok",false) or not sea: return
	Engine.physics_ticks_per_second=60; get_viewport().msaa_3d=Viewport.MSAA_4X
	get_window().title="海上明旗 · "+{"duel":"单舰炮战","fleet":"舰队遭遇","sail":"自由试航"}[runtime.snapshot().runtime.mode]
	runtime.set_pause("loading",false); _present(0)
func _command(intent: Dictionary) -> void:
	if sea and intent.get("type") in ["menu", "open-settings", "chart", "main-menu", "begin-surrender", "restart"]: sea.cancel_camera_drag()
	match intent.get("type",""):
		"main-menu": main_menu_requested.emit(); return
		"open-settings": services.open_settings()
		"chart": runtime.set_pause("chart",bool(intent.get("value",false)))
		_:
			var receipt: Dictionary=runtime.command(intent)
			if not receipt.ok: runtime._notice=receipt.get("reason","command-rejected")
			elif intent.get("type") == "fire": return
	_present(0)
func _physics_process(delta: float) -> void:
	if not interface or _disposed: return
	sea.observe_projectiles(runtime.snapshot().naval)
	var consumed:float=runtime.advance(delta)
	var native:Dictionary=runtime.simulation.snapshot()
	_sync_presentation_epoch(native)
	_pending_presentation_seconds += consumed
	var was_anchored: bool = _terminal_presentation.is_anchored()
	var tail:=_terminal_presentation.advance(native,runtime.presentation_pause_reasons(),delta,consumed)
	_pending_presentation_seconds += tail
	var visual: Dictionary = _terminal_presentation.snapshot(native) if _terminal_presentation.is_anchored() else native
	# Source birth history and Jolt remain on the accepted physics cadence.
	sea.remember_authoritative_poses(visual,consumed+tail)
	if not was_anchored and _terminal_presentation.is_anchored(): _present(0.0)
	elif runtime.requires_immediate_actor_presentation():
		# Crew losses require their original whole-fleet pose/skin transfer.
		# Fire keeps its accepted birth and native FX cadence without redrawing
		# camera, unrelated actors, water, world, HUD or chart on each gun.
		if Sea.requires_full_event_presentation(runtime.simulation._events): _present(0.0)
		else: _present_local_fire(0.0)
func _process(_delta: float) -> void:
	if interface and not _disposed: _present(0.0)
func _sync_presentation_epoch(native: Dictionary) -> void:
	var epoch: String = native.get("battleId","")
	if epoch == _presentation_epoch: return
	_presentation_epoch = epoch; _pending_presentation_seconds = 0.0
	_terminal_presentation.reset()
func _present_local_fire(consumed: float) -> void:
	if not interface or _disposed or not runtime.simulation: return
	var native: Dictionary=runtime.simulation.snapshot()
	_sync_presentation_epoch(native)
	consumed += _pending_presentation_seconds
	var visual:Dictionary=_terminal_presentation.snapshot(native)
	var events: Array=sea.apply_local_fire(visual,runtime.drain_events(),consumed)
	services.present(visual,events,consumed,runtime.is_paused())
func _present(consumed: float) -> void:
	var packet: Dictionary=runtime.snapshot()
	if not interface or packet.is_empty(): return
	_sync_presentation_epoch(packet.naval)
	consumed += _pending_presentation_seconds
	_pending_presentation_seconds = 0.0
	var visual:Dictionary=_terminal_presentation.snapshot(packet.naval)
	var events: Array=sea.apply_snapshot(visual,runtime.drain_events(),consumed)
	var reasons:Array=runtime.presentation_pause_reasons()
	var result_only:bool=reasons.size()==1 and reasons[0]=="result"
	var tail_audio:bool=result_only and _terminal_presentation.allows_playback() and (_terminal_presentation.is_playing() or consumed>0.0)
	services.present(visual,events,consumed,packet.runtime.paused and not tail_audio); interface.apply_snapshot(packet)
	if not _mouse_sailing_ready(): _mouse_course.cancel_gesture()
	if not _camera_input_ready(): sea.cancel_camera_drag()
	minimap.present(packet.naval,{},services.captures_keyboard() or interface.is_menu_open() or interface.chart.visible or not packet.runtime.surrenderQuote.is_empty() or packet.naval.status in ["victory","defeat","surrendered"])
func _input(event: InputEvent) -> void:
	# This runs before GUI consumption; releasing over a widget still ends drag.
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT and not event.pressed:
		if sea: sea.cancel_camera_drag()
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed: _mouse_course.cancel_gesture()
		else: _mouse_course.cancel_gesture_after_dispatch()
	if event is InputEventKey and event.pressed: _mouse_course.cancel_gesture()
	if not interface or not event is InputEventKey or event.echo: return
	var key: int=event.physical_keycode if event.physical_keycode else event.keycode
	if key in [KEY_ESCAPE, KEY_M] and sea: sea.cancel_camera_drag()
	if services.captures_keyboard():
		if event.pressed and key==KEY_ESCAPE: services.close_settings(); _present(0)
		get_viewport().set_input_as_handled(); return
	# F belongs to unhandled camera input, including while sailing is paused.
	# Leave focused widgets their normal opportunity to consume it first.
	if key==KEY_F: return
	if not event.pressed:
		if KEYS.has(key): runtime.set_held(KEYS[key],false)
		return
	var focus:=get_viewport().gui_get_focus_owner()
	if key not in [KEY_ESCAPE,KEY_M] and (focus is Range or focus is LineEdit or focus is TextEdit or focus is OptionButton): return
	if key==KEY_ESCAPE:
		if interface.chart.visible: _command({"type":"chart","value":false})
		elif not runtime.snapshot().runtime.surrenderQuote.is_empty(): _command({"type":"cancel-surrender"})
		else: _command({"type":"menu","value":not interface.is_menu_open()})
	elif key==KEY_M: _command({"type":"chart","value":not interface.chart.visible})
	elif not runtime.is_paused():
		if KEYS.has(key): runtime.set_held(KEYS[key],true)
		elif key in [KEY_Q,KEY_E,KEY_SPACE]: _command({"type":"fire","side":"port" if key==KEY_Q else "starboard" if key==KEY_E else runtime.nearest_side()})
		elif key in [KEY_1,KEY_2,KEY_3]: _command({"type":"select-ammo","ammo":{KEY_1:"solid",KEY_2:"chain",KEY_3:"grape"}[key]})
		elif key==KEY_R: _command({"type":"trim"})
	get_viewport().set_input_as_handled()
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_mouse_course.cancel_gesture()
	if not _camera_input_ready():
		if sea: sea.cancel_camera_drag()
	elif event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode if event.physical_keycode else event.keycode)==KEY_F:
		_mouse_course.cancel_gesture(); sea.recenter_camera()
		get_viewport().set_input_as_handled(); return
	elif sea.handle_camera_input(event):
		_mouse_course.cancel_gesture()
		get_viewport().set_input_as_handled(); return
	if not _mouse_sailing_ready():
		_mouse_course.cancel_gesture()
		return
	var intent:Dictionary=_mouse_course.consume(event)
	if intent.is_empty(): return
	if intent.type=="mouse-course":
		var projected:Dictionary=_mouse_course.project(sea.camera,intent.screen,heights.sample_height)
		if not projected.get("ok",false): return
		intent={"type":"mouse-course","point":projected.point}
	_command(intent)
	get_viewport().set_input_as_handled()
func _mouse_sailing_ready() -> bool:
	return not _disposed and sea!=null and interface!=null and services!=null and interface.visible and not sea.camera_status().dragging and not runtime.is_paused() and not interface.is_menu_open() and not interface.chart.visible and not services.captures_keyboard()
func _camera_input_ready() -> bool:
	if _disposed or sea==null or interface==null or services==null or not interface.visible: return false
	if interface.is_menu_open() or interface.chart.visible or services.captures_keyboard(): return false
	var modal: Control=interface.get("_modal")
	if modal and modal.visible: return false
	var focus: Control=get_viewport().gui_get_focus_owner()
	if focus is Range or focus is OptionButton: return false
	if focus is LineEdit and focus.editable: return false
	if focus is TextEdit and focus.editable: return false
	return true
func _notification(what: int) -> void:
	if not runtime or runtime._disposed: return
	if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_mouse_course.cancel_gesture()
		if sea: sea.cancel_camera_drag()
		runtime.set_pause("blur",true)
		if interface: _present(0)
func _exit_tree() -> void:
	if _disposed: return
	_disposed=true
	_pending_presentation_seconds = 0.0; _presentation_epoch = ""
	_terminal_presentation.reset()
	if services: services.dispose()
	if minimap: minimap.dispose()
	if sea: sea.dispose()
	runtime.dispose()
