extends Node3D
## Trusted owner supplies dev/qa startup flags; no imported career state accepted.
signal main_menu_requested
const Runtime=preload("res://game/runtime/visual_qa_runtime.gd")
const DevelopmentAccess=preload("res://game/runtime/development_access.gd")
const Height=preload("res://modules/scene_engine/terrain/height_field.gd")
const Catalog=preload("res://game/domain/legacy/catalog.gd")
const Sea=preload("res://game/presentation/world/naval_world_view.gd")
const Services=preload("res://game/scenes/common/sea_services.gd")
const Inspector=preload("res://game/scenes/visual_qa/visual_qa_inspector.gd")
const KEYS:={KEY_W:"KeyW",KEY_S:"KeyS",KEY_A:"KeyA",KEY_D:"KeyD",KEY_UP:"ArrowUp",KEY_DOWN:"ArrowDown",KEY_LEFT:"ArrowLeft",KEY_RIGHT:"ArrowRight",KEY_BRACKETLEFT:"BracketLeft",KEY_BRACKETRIGHT:"BracketRight"}
var startup_options: Dictionary={}
var startup_receipt: Dictionary={}
var settings_storage: RefCounted
var runtime:=Runtime.new()
var heights:=Height.new()
var sea: Node3D
var interface: CanvasLayer
var services: Node
var _disposed:=false
var _active:=false
var _last_frame_ms:=-1.0
var _last_hud_ms:=-1.0
var _export_notice:=""
class SettingsRuntime extends RefCounted:
	var owner: RefCounted
	var pause_transition: Callable
	func _init(runtime_owner: RefCounted,on_pause_transition: Callable) -> void:
		owner=runtime_owner; pause_transition=on_pause_transition
	func set_handling_mode(_mode: String) -> void: pass # Source QA ignores persisted product handling.
	func snapshot() -> Dictionary: return owner.snapshot()
	func set_pause(reason: String,value: bool) -> Dictionary:
		var before: bool=owner.is_paused()
		var receipt: Dictionary=owner.set_pause(reason,value)
		if receipt.ok and before!=owner.is_paused(): pause_transition.call()
		return receipt
func _ready() -> void:
	set_physics_process(false) # RAF equivalent: idle wall intervals feed real fixed ticks.
	if not (DevelopmentAccess.host_allows() and (OS.has_feature("editor") or bool(startup_options.get("dev",false)) or bool(startup_options.get("qa",false)))):
		startup_receipt={"ok":false,"reason":"visual-qa-development-only"}; return
	if not heights.configure_ports(Catalog.DATA.PORTS,false,preload("res://game/scenes/common/reference_geography.gd").options()): startup_receipt={"ok":false,"reason":"visual-qa-geography-failed"}; return
	startup_receipt=runtime.configure(heights.sample_height,startup_options)
	if not startup_receipt.ok: return
	runtime.set_pause("loading",true)
	sea=Sea.new(); add_child(sea)
	if not sea.configure(heights.sample_height,Catalog.DATA.PORTS,runtime.sample_water_height,runtime.snapshot().naval): startup_receipt={"ok":false,"reason":"visual-qa-world-failed"}; return
	services=Services.new(); add_child(services); services.configure(SettingsRuntime.new(runtime,_reset_frame_clock),sea,settings_storage)
	interface=Inspector.new(); add_child(interface); interface.command_requested.connect(_command); interface.view_requested.connect(func(value): sea.tactical=value; _present(0,true))
	_present(0,true)
	if get_window().has_signal("visibility_changed"): get_window().connect("visibility_changed",_sync_visibility)
	if not startup_options.get("staged",false): activate_entry()
func activate_entry() -> void:
	if not startup_receipt.get("ok",false) or not sea: return
	Engine.physics_ticks_per_second=60; get_viewport().msaa_3d=Viewport.MSAA_4X
	get_window().title="海上明旗 · QA 画面验收"
	_active=true; runtime.set_pause("loading",false); _last_frame_ms=Time.get_ticks_usec()/1000.0; _present(0,true)
func _reset_frame_clock() -> void: _last_frame_ms=Time.get_ticks_usec()/1000.0
func _command(intent: Dictionary) -> void:
	var was_paused:=runtime.is_paused()
	match intent.get("type",""):
		"main-menu": main_menu_requested.emit(); return
		"open-settings": services.open_settings()
		"export":
			var receipt:=export_diagnostics()
			_export_notice="已导出 "+receipt.path if receipt.ok else "导出失败 "+receipt.reason
		_:
			var generation: int=runtime.snapshot().runtime.generation
			var receipt: Dictionary=runtime.command(intent)
			if not receipt.ok: runtime._notice=receipt.get("reason","command-rejected")
			if runtime.snapshot().runtime.generation!=generation:
				# Source battle IDs are stable across restart. Explicit reset releases old Jolt bodies.
				sea.configure(heights.sample_height,Catalog.DATA.PORTS,runtime.sample_water_height,runtime.snapshot().naval)
				sea.apply_settings(services.settings_storage.snapshot()); _last_frame_ms=Time.get_ticks_usec()/1000.0
	# Ordinary controls/export keep the previous idle timestamp, including their
	# CPU duration. Only lifecycle commands exclude an inactive wall period.
	if was_paused!=runtime.is_paused() or intent.get("type") in ["pause","resume","menu","restart","scenario","open-settings"]:
		_last_frame_ms=Time.get_ticks_usec()/1000.0
	_present(0,true)
func _sync_visibility() -> void: set_visibility_paused(not get_window().visible)
func set_visibility_paused(hidden: bool) -> void:
	if _disposed or runtime._disposed: return
	runtime.note_event("visibility-hidden" if hidden else "visibility-visible")
	if hidden: runtime.set_pause("blur",true)
	runtime.set_pause("hidden",hidden); _last_frame_ms=Time.get_ticks_usec()/1000.0
	if interface: _present(0,true)
func _process(_delta: float) -> void:
	if not _active or _disposed: return
	var now:=Time.get_ticks_usec()/1000.0
	var seconds:=maxf(0,(now-_last_frame_ms)/1000.0) if _last_frame_ms>=0 else 0.0
	_last_frame_ms=now; _physics_process(seconds)
func _physics_process(delta: float) -> void:
	if not _active or not interface or _disposed: return
	var callback:=Time.get_ticks_usec()/1000.0; var before:=_chunks()
	sea.observe_projectiles(runtime.snapshot().naval)
	var start:=Time.get_ticks_usec()/1000.0
	var consumed: float=runtime.advance(delta,callback)
	var simulation_end:=Time.get_ticks_usec()/1000.0
	_present(consumed)
	var completed:=Time.get_ticks_usec()/1000.0
	runtime.diagnostics.complete_frame({"callbackTimestampMs":callback,"cpuStartedAtMs":start,"cpuCompletedAtMs":completed,"completedAtMs":completed,"benchmarkSeconds":runtime.snapshot().runtime.benchmarkSeconds,"simulationSeconds":runtime.snapshot().naval.time,"phase":runtime.phase(),"cpu":{"simulationMs":simulation_end-start,"viewWorldMs":completed-simulation_end,"viewMs":null,"worldUpdateMs":null,"renderSubmitMs":null,"gpuCompletionMs":null},"world":{"before":before,"after":_chunks()}})
func _present(consumed: float,force: bool=false) -> void:
	var packet: Dictionary=runtime.snapshot()
	if not interface or packet.is_empty(): return
	var events: Array=sea.apply_snapshot(packet.naval,runtime.drain_events(),consumed)
	services.present(packet.naval,events,consumed,packet.runtime.paused)
	var now:=Time.get_ticks_usec()/1000.0
	if force or now-_last_hud_ms>150:
		interface.apply_snapshot(packet,inspection_snapshot()); _last_hud_ms=now
func _chunks() -> Dictionary:
	if not sea or not sea.world: return {}
	var player: Dictionary=Sea.find_ship(runtime.snapshot().naval,"player"); var p: Dictionary=player.visual.position
	var scale: float=sea.world._chunk_size
	return {"center":{"x":floori(p.x/scale),"z":floori(p.z/scale)},"chunks":sea.world.get_chunk_count(),"builds":sea.world.get_chunk_build_count(),"pendingCreates":0,"pendingDisposes":0,"scheduling":"synchronous native world"}
func inspection_snapshot() -> Dictionary:
	var native: Dictionary=runtime.snapshot().get("naval",{})
	var ships: Array=[]; var bodies: Array=[]; var visible:=0
	if sea:
		for id: String in sea.sailors:
			var crew=sea.sailors[id]; var detail: Dictionary=crew.diagnostics(); var ship:=Sea.find_ship(native,id)
			visible+=int(detail.visible)
			ships.append({"id":id,"kind":ship.get("kind"),"crew":ship.get("crew"),"visible":detail.visible,"lod":detail.lod,"acceptedTime":detail.accepted_time,"roles":detail.roles.duplicate(true)})
			for entry: Dictionary in crew.get_impact_pool().diagnostics().bodies:
				var positions: Array=[]
				for frame: Transform3D in entry.transforms: positions.append({"x":frame.origin.x,"y":frame.origin.y,"z":frame.origin.z})
				bodies.append({"id":entry.id,"targetId":id,"eventId":entry.source.event_id,"slot":entry.source.slot,"casualty":entry.casualty,"age":entry.age,"wet":entry.wet,"boneCount":entry.bone_count,"jointCount":entry.joint_count,"bonePositions":positions})
	return {"sailors":{"battleId":native.get("battleId"),"tick":native.get("tick"),"simulationTime":native.get("time"),"visible":visible,"budget":120,"impacts":{"active":bodies.size(),"cap":12,"bodies":bodies},"ships":ships},"originalMetrics":runtime.original_metrics(),"summary":runtime.diagnostics.summary(),"chunks":_chunks(),"export":_export_notice}
func export_diagnostics(path: String="") -> Dictionary:
	if _disposed or runtime.snapshot().is_empty(): return {"ok":false,"reason":"visual-qa-disposed"}
	runtime.note_event("export")
	if path.is_empty(): path="user://ming-armada-performance-%s.json" % Time.get_ticks_msec()
	var detail:=inspection_snapshot(); var packet: Dictionary=runtime.snapshot(); var data:=runtime.diagnostics.snapshot()
	data.merge({"schema":"ming-armada-native-frame-diagnostics-v1","exportedAt":Time.get_datetime_string_from_system(true),"association":"elapsedMs is the native idle wall interval; previousCompletedFrame attaches only for measured CPU overlap. viewWorldMs includes view, crew, effects, terrain and audio CPU. Render-submit and GPU completion are unavailable; correlation does not establish cause.","collection":"Active positive idle intervals since restart, including warmup and benchmark boundary intervals. includedInMetrics preserves 20s inclusive /80s exclusive source window; original intervals retain rolling limit 7200.","metadata":{"source":"Godot-native VisualScenarios from frozen 9ad6a44","mode":"qa","scenario":packet.runtime.scenario,"phase":packet.runtime.phase,"paused":packet.runtime.paused,"quality":services.settings_storage.snapshot().quality,"playback":packet.runtime.playback,"benchmarkSeconds":packet.runtime.benchmarkSeconds,"simulationSeconds":packet.naval.time,"viewport":{"width":get_viewport().size.x,"height":get_viewport().size.y},"engine":Engine.get_version_info().string,"renderingMethod":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name()},"native":packet.naval,"sailors":detail.sailors,"originalMetrics":detail.originalMetrics,"originalFrameIntervalsMs":runtime._frames.duplicate(),"summary":detail.summary},true)
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if not file: return {"ok":false,"reason":error_string(FileAccess.get_open_error())}
	file.store_string(JSON.stringify(data,"  ")); file.flush(); var error:=file.get_error(); file.close()
	if error!=OK: return {"ok":false,"reason":error_string(error)}
	if JSON.parse_string(FileAccess.get_file_as_string(path))==null: return {"ok":false,"reason":"diagnostic-readback-failed"}
	return {"ok":true,"path":ProjectSettings.globalize_path(path)}
func _nearest_side() -> String:
	var native: Dictionary=runtime.snapshot().naval; var player:=Sea.find_ship(native,native.playerId); var distance:=INF; var side:="starboard"
	for ship: Dictionary in native.ships:
		if ship.team!="hostile" or ship.hull<=0: continue
		var dx: float=ship.visual.position.x-player.visual.position.x; var dz: float=ship.visual.position.z-player.visual.position.z
		if dx*dx+dz*dz<distance: distance=dx*dx+dz*dz; side="starboard" if -sin(player.visual.heading)*dx+cos(player.visual.heading)*dz>=0 else "port"
	return side
func _input(event: InputEvent) -> void:
	if not interface or not _active or not event is InputEventKey or event.echo: return
	var key: int=event.physical_keycode if event.physical_keycode else event.keycode
	if not event.pressed:
		if KEYS.has(key): runtime.set_held(KEYS[key],false)
		return
	if services.captures_keyboard():
		if key==KEY_ESCAPE: services.close_settings(); _last_frame_ms=Time.get_ticks_usec()/1000.0; _present(0,true)
		get_viewport().set_input_as_handled(); return
	var focus:=get_viewport().gui_get_focus_owner()
	if key!=KEY_ESCAPE and (focus is Range or focus is LineEdit or focus is TextEdit or focus is OptionButton): return
	if key==KEY_ESCAPE: _command({"type":"resume"} if runtime.is_paused() else {"type":"pause"})
	elif not runtime.is_paused():
		if KEYS.has(key): runtime.set_held(KEYS[key],true)
		elif key in [KEY_Q,KEY_E,KEY_SPACE]: _command({"type":"fire","side":"port" if key==KEY_Q else "starboard" if key==KEY_E else _nearest_side()})
		elif key in [KEY_1,KEY_2,KEY_3]: _command({"type":"select-ammo","ammo":{KEY_1:"solid",KEY_2:"chain",KEY_3:"grape"}[key]})
		elif key==KEY_R: _command({"type":"trim"})
	get_viewport().set_input_as_handled()
func _notification(what: int) -> void:
	if not runtime or runtime._disposed: return
	if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		runtime.note_event("blur"); runtime.set_pause("blur",true); _last_frame_ms=Time.get_ticks_usec()/1000.0
		if interface: _present(0,true)
	elif what==NOTIFICATION_APPLICATION_PAUSED: set_visibility_paused(true)
	elif what==NOTIFICATION_APPLICATION_RESUMED: set_visibility_paused(false)
func _exit_tree() -> void:
	if _disposed: return
	_disposed=true; _active=false
	if services: services.dispose()
	if sea: sea.dispose()
	runtime.dispose()
