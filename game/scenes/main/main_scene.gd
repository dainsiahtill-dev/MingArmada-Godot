extends Node
## Native entry lifecycle: generation/token checks surround each deferred stage and transaction.
const Router = preload("res://game/runtime/game_router.gd")
const DevelopmentAccess = preload("res://game/runtime/development_access.gd")
const Menu = preload("res://game/ui/menu/main_menu.gd")
const Recovery = preload("res://game/ui/menu/save_recovery.gd")
const SettingsPanel = preload("res://game/ui/settings/settings_panel.gd")
var router: RefCounted
var menu: Control
var recovery: Control
var settings_panel: Control
var current_scene: Node
var _candidate: Node
var _candidate_layers: Array = []
var _candidate_previous_camera: WeakRef
var _disposed := false
var _startup_capture_path := ""
var _startup_game_capture_path := ""
var _startup_game_capture_mode := ""
var _active_scene_request: Dictionary = {}
const RELEASE_GAME_MODES := ["mingqi","career","sail","duel","fleet"]

static func startup_flags(arguments: PackedStringArray) -> Dictionary:
	return DevelopmentAccess.startup_flags(arguments)

func _ready() -> void:
	if not router:
		router = Router.new(startup_flags(OS.get_cmdline_user_args()))
	router.settings_storage.load_settings()
	var ui := CanvasLayer.new(); ui.name = "EntryUI"; ui.layer = 100; add_child(ui)
	menu = Menu.new(); ui.add_child(menu); menu.intent_requested.connect(_handle_intent); menu.settings_requested.connect(_open_settings)
	recovery = Recovery.new(); ui.add_child(recovery); recovery.intent_requested.connect(_handle_recovery)
	settings_panel = SettingsPanel.new(); ui.add_child(settings_panel); settings_panel.settings_requested.connect(_change_settings)
	_refresh_menu()
	_request_startup_preview.call_deferred(OS.get_cmdline_user_args())
	_request_startup_game.call_deferred(OS.get_cmdline_user_args())

func _request_startup_game(arguments: PackedStringArray) -> bool:
	# Ordinary packaged arguments exercise the same visible menu button and
	# generation/nonce router as an interactive click; no developer access.
	if _disposed or current_scene or _candidate or not menu or arguments.has("--water-study"): return false
	var mode := ""
	var has_mode := false
	var capture := ""
	var has_capture := false
	for argument in arguments:
		if argument.begins_with("--start-game="):
			if has_mode: return false
			has_mode=true; mode=argument.trim_prefix("--start-game=")
		elif argument.begins_with("--game-capture="):
			if has_capture: return false
			has_capture=true; capture=argument.trim_prefix("--game-capture=")
	if mode not in RELEASE_GAME_MODES: return false
	if has_capture and (not capture.is_absolute_path() or capture.begins_with("user://") or capture.begins_with("res://") or capture.get_extension().to_lower()!="png"): return false
	var button: Button=menu.find_child(mode,true,false)
	if button==null or button.disabled or not menu.visible: return false
	_startup_game_capture_path=capture
	_startup_game_capture_mode=mode
	button.pressed.emit()
	return true

func _request_startup_preview(arguments: PackedStringArray) -> void:
	# A normal user entry works in release templates without path overrides.
	if not arguments.has("--water-study") or _disposed or current_scene or _candidate or not menu: return
	var button: Button = menu.find_child("water-study",true,false)
	if button == null or button.disabled or not menu.visible: return
	for argument in arguments:
		if argument.begins_with("--water-study-capture="):
			_startup_capture_path = argument.trim_prefix("--water-study-capture=")
			break
	button.pressed.emit()

func _capture_request_current(request: Dictionary) -> bool:
	return not _disposed and router != null and router.is_current(request)

func _capture_startup_preview(path: String, request: Dictionary) -> void:
	# Optional CLI PNG export uses the scene's native save operation, not a
	# replacement entry script or an external screenshot of another process.
	for frame in 240:
		if not _capture_request_current(request): return
		if is_instance_valid(current_scene) and current_scene.has_method("save_frame"): break
		await get_tree().process_frame
	if not _capture_request_current(request): return
	if not is_instance_valid(current_scene) or not current_scene.has_method("save_frame"):
		printerr("ISLAND_WATER_STARTUP_CAPTURE failures=1 reason=preview-not-ready"); return
	var preview: Node = current_scene
	for frame in 8:
		await get_tree().process_frame
		if not _capture_request_current(request) or not is_instance_valid(preview) or current_scene != preview: return
	var saved: Dictionary = await preview.save_frame(path)
	if not _capture_request_current(request) or not is_instance_valid(preview) or current_scene != preview: return
	if not saved.ok:
		printerr("ISLAND_WATER_STARTUP_CAPTURE failures=1 reason=",saved.get("reason","capture-failed")); return
	var metadata := {"route":"release main entry --water-study, actual menu button", "engine":Engine.get_version_info(), "gpu":RenderingServer.get_video_adapter_name(), "renderingMethod":RenderingServer.get_current_rendering_method(), "saved":saved, "snapshot":preview.inspection_snapshot(), "pngSha256":FileAccess.get_sha256(path)}
	var file := FileAccess.open(path+".json",FileAccess.WRITE)
	if file == null:
		printerr("ISLAND_WATER_STARTUP_CAPTURE failures=1 reason=metadata-write-failed"); return
	file.store_string(JSON.stringify(metadata,"\t")); file.close()
	print("ISLAND_WATER_STARTUP_CAPTURE failures=0 path=",saved.path)

func _game_capture_current(scene: Node,request: Dictionary) -> bool:
	if not _capture_request_current(request) or not is_instance_valid(scene) or current_scene!=scene: return false
	for key: String in ["generation","nonce","operation"]:
		if _active_scene_request.get(key,-1)!=request.get(key,-2): return false
	return true

func _scene_member(scene: Node,key: String) -> Variant:
	for property: Dictionary in scene.get_property_list():
		if property.name==key: return scene.get(key)
	return null

func _capture_startup_game(path: String,request: Dictionary) -> void:
	# Export the real active game viewport. Keep the loaded scene playing; the
	# request only observes it and never replaces scenes or creates a demo.
	var scene: Node
	for frame in 240:
		if not _capture_request_current(request): return
		if is_instance_valid(current_scene) and _game_capture_current(current_scene,request):
			scene=current_scene; break
		await get_tree().process_frame
		if not _capture_request_current(request): return
	if not is_instance_valid(scene):
		printerr("RELEASE_GAME_CAPTURE failures=1 reason=scene-not-ready"); return
	for frame in 8:
		if not _game_capture_current(scene,request): return
		await get_tree().process_frame
		if not _game_capture_current(scene,request): return
	if not _game_capture_current(scene,request): return
	await RenderingServer.frame_post_draw
	if not _game_capture_current(scene,request): return
	var viewport:=get_viewport()
	var image: Image=viewport.get_texture().get_image()
	if not _game_capture_current(scene,request): return
	if image==null or image.is_empty():
		printerr("RELEASE_GAME_CAPTURE failures=1 reason=viewport-empty"); return
	var runtime: Variant=_scene_member(scene,"runtime")
	var snapshot: Dictionary=runtime.snapshot() if is_instance_valid(runtime) and runtime.has_method("snapshot") else {}
	if not _game_capture_current(scene,request): return
	var sea: Variant=_scene_member(scene,"sea")
	var world: Variant=_scene_member(sea,"world") if is_instance_valid(sea) else null
	var ocean: Variant=world.get_ocean() if is_instance_valid(world) and world.has_method("get_ocean") else null
	var heights: Variant=_scene_member(scene,"heights")
	var profiles: Array=heights.reference_profiles() if is_instance_valid(heights) and heights.has_method("reference_profiles") else []
	var optical: Dictionary=ocean.get_surface_optics_diagnostics() if is_instance_valid(ocean) and ocean.has_method("get_surface_optics_diagnostics") else {}
	var camera: Camera3D=viewport.get_camera_3d()
	var error:=DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error!=OK:
		printerr("RELEASE_GAME_CAPTURE failures=1 reason=directory-write-failed"); return
	if not _game_capture_current(scene,request): return
	error=image.save_png(path)
	if error!=OK:
		printerr("RELEASE_GAME_CAPTURE failures=1 reason=png-write-failed"); return
	if not _game_capture_current(scene,request): return
	var metadata: Dictionary={"route":"release main entry --start-game, actual menu button","mode":request.get("mode"),"request":{"generation":request.generation,"nonce":request.nonce,"operation":request.operation},"scene":scene.get_script().resource_path,"startup":_startup_receipt(scene),"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"renderingMethod":RenderingServer.get_current_rendering_method(),"viewport":[image.get_width(),image.get_height()],"pngSha256":FileAccess.get_sha256(path),"snapshot":snapshot,"ocean":optical,"referenceIslands":profiles,"cameraPosition":camera.global_position if is_instance_valid(camera) else null,"scope":"Real active bundled game viewport; normal menu/router entry. No external scene script, performance or original-game pixel-equivalence claim."}
	var file:=FileAccess.open(path+".json",FileAccess.WRITE)
	if file==null:
		printerr("RELEASE_GAME_CAPTURE failures=1 reason=metadata-write-failed"); return
	file.store_string(JSON.stringify(metadata,"\t")); file.close()
	print("RELEASE_GAME_CAPTURE failures=0 mode=",request.mode," path=",path)

func _refresh_menu() -> void:
	if _disposed: return
	get_window().title = "海上明旗 · 航海冒险"
	menu.apply_view_model(router.view_model(),router.generation); menu.show()
func _input(event: InputEvent) -> void:
	if not settings_panel or not settings_panel.visible or not event is InputEventKey or not event.pressed or event.echo: return
	var code: int = event.physical_keycode if event.physical_keycode else event.keycode
	if code == KEY_ESCAPE: settings_panel.close(); get_viewport().set_input_as_handled()
func _handle_intent(request: Dictionary) -> void:
	if _disposed: return
	var startup_capture := _startup_capture_path
	_startup_capture_path = ""
	var game_capture := _startup_game_capture_path
	var game_capture_mode := _startup_game_capture_mode
	_startup_game_capture_path=""; _startup_game_capture_mode=""
	if request.get("type") == "back":
		if request.get("generation") != router.generation: return
		router.cancel(request.get("nextGeneration",router.generation+1)); _discard_candidate(); _refresh_menu(); return
	var prepared: Dictionary = router.prepare_entry(request)
	if prepared.get("quit",false): get_tree().quit(); return
	if not prepared.ok:
		if prepared.get("recovery",false): _open_recovery()
		else: _show_failure(prepared,prepared.get("reason","entry-unavailable"))
		return
	menu.apply_status({"phase":"loading","progress":15,"message":"正在准备航程与本地设置。"},prepared.generation,prepared.nonce)
	_load_prepared.call_deferred(prepared,false)
	if not startup_capture.is_empty() and prepared.get("mode") == "water-study":
		_capture_startup_preview.call_deferred(startup_capture,prepared.duplicate(true))
	if not game_capture.is_empty() and prepared.get("mode")==game_capture_mode and game_capture_mode in RELEASE_GAME_MODES:
		_capture_startup_game.call_deferred(game_capture,prepared.duplicate(true))

func _open_recovery() -> void:
	menu.hide(); recovery.open(router.recovery_snapshot())
func _handle_recovery(intent: Dictionary) -> void:
	if _disposed or not recovery.visible: return
	if intent.has("session") and intent.session != recovery.session_epoch(): return
	if intent.type == "back":
		router.cancel(); _discard_candidate(); recovery.close(); _refresh_menu(); return
	if intent.type in ["export-raw","export-backup","export-file"]:
		var exported: Dictionary = router.export_backup() if intent.type == "export-backup" or intent.get("kind") == "backup" else router.export_recovery()
		if exported.ok:
			if intent.type == "export-file":
				var file := FileAccess.open(intent.get("path",""),FileAccess.WRITE)
				if file == null: exported = {"ok":false,"reason":"export-write-failed"}
				else:
					file.store_string(exported.json); file.flush(); var failed := file.get_error() != OK; file.close()
					exported = {"ok":not failed,"reason":"export-write-failed" if failed else "export-file-saved"}
			else: DisplayServer.clipboard_set(exported.json); exported.reason = "exported"
		recovery.show_reason(exported.get("reason","export-failed")); return
	var prepared: Dictionary = router.prepare_recovery(intent)
	if not prepared.ok: recovery.apply_snapshot(router.recovery_snapshot(),prepared.get("reason","save-invalid")); return
	recovery.set_busy(true); _load_prepared.call_deferred(prepared,true)

func _show_failure(prepared: Dictionary,reason: String,from_recovery: bool = false) -> void:
	if from_recovery:
		recovery.set_busy(false); recovery.apply_snapshot(router.recovery_snapshot(),reason)
	else: menu.apply_status({"phase":"error","message":_entry_reason(reason)},prepared.get("generation",router.generation),prepared.get("nonce",0))
func _entry_reason(reason: String) -> String:
	return "该航程尚未准备成功，可重试或返回菜单。" if reason == "entry-resource-unavailable" else "航程未能启动："+reason

func _load_prepared(prepared: Dictionary,from_recovery: bool) -> void:
	if _disposed or not router.is_current(prepared): return
	await get_tree().process_frame
	if _disposed or not router.is_current(prepared): return
	if not from_recovery: menu.apply_status({"phase":"loading","progress":35,"message":"正在读取船队、海图与港口资源。"},prepared.generation,prepared.nonce)
	var made: Dictionary = router.create_scene(prepared)
	if not made.ok: _show_failure(prepared,made.get("reason","entry-resource-unavailable"),from_recovery); return
	var candidate: Node = made.scene
	_candidate = candidate; candidate.process_mode = Node.PROCESS_MODE_DISABLED
	var previous_camera := get_viewport().get_camera_3d()
	_candidate_previous_camera = weakref(previous_camera) if previous_camera else null
	if candidate is Node3D or candidate is Control: candidate.hide()
	add_child(candidate)
	_candidate_layers.clear(); _hide_layers(candidate)
	await get_tree().process_frame
	if _disposed or not router.is_current(prepared): _discard_node(candidate); return
	var receipt: Dictionary = _startup_receipt(candidate)
	if not receipt.ok:
		_discard_candidate(); _show_failure(prepared,receipt.get("reason","entry-startup-failed"),from_recovery); return
	if not from_recovery: menu.apply_status({"phase":"loading","progress":85,"message":"船队已就绪，正在确认航程。"},prepared.generation,prepared.nonce)
	# A scene's actual terrain/native construction has succeeded before any import disk mutation.
	var committed: Dictionary = router.commit_import(prepared)
	if not committed.ok:
		_discard_candidate(); _show_failure(prepared,committed.get("reason","save-write-failed"),from_recovery); return
	if prepared.initial_save.is_empty() and prepared.get("persist_name",false):
		var saved_name: Dictionary = router.settings_storage.update_settings({"captainName":prepared.options.captainName})
		if not saved_name.ok:
			_discard_candidate(); _show_failure(prepared,saved_name.get("reason","settings-write-failed"),from_recovery); return
	if not router.is_current(prepared): _discard_candidate(); return
	if current_scene: _discard_node(current_scene)
	current_scene = candidate; _candidate = null
	_active_scene_request=prepared.duplicate(true)
	if candidate.has_signal("main_menu_requested"): candidate.connect("main_menu_requested",_return_from_scene.bind(candidate))
	for item in _candidate_layers:
		if is_instance_valid(item.node): item.node.visible = item.visible
	_candidate_layers.clear()
	_candidate_previous_camera = null
	if candidate.has_method("activate_entry"): candidate.call("activate_entry")
	candidate.process_mode = Node.PROCESS_MODE_INHERIT
	if candidate is Node3D or candidate is Control: candidate.show()
	menu.apply_status({"phase":"complete","progress":100},prepared.generation,prepared.nonce); menu.hide(); recovery.close()

func _startup_receipt(candidate: Node) -> Dictionary:
	for property in candidate.get_property_list():
		if property.name == "startup_receipt":
			var receipt: Variant = candidate.get("startup_receipt")
			return receipt if receipt is Dictionary and receipt.has("ok") else {"ok":false,"reason":"entry-startup-unconfirmed"}
	return {"ok":false,"reason":"entry-startup-unconfirmed"}
func _hide_layers(node: Node) -> void:
	if node is CanvasLayer: _candidate_layers.append({"node":node,"visible":node.visible}); node.hide()
	for child in node.get_children(): _hide_layers(child)
func _discard_node(node: Variant) -> void:
	if not is_instance_valid(node): return
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if node.get_parent(): node.get_parent().remove_child(node)
	node.free()
func _discard_candidate() -> void:
	if is_instance_valid(_candidate): _discard_node(_candidate)
	_candidate = null; _candidate_layers.clear()
	if _candidate_previous_camera and is_instance_valid(_candidate_previous_camera.get_ref()): _candidate_previous_camera.get_ref().make_current()
	_candidate_previous_camera = null
func _return_from_scene(source: Variant) -> void:
	if _disposed or not is_instance_valid(source) or source != current_scene: return
	current_scene = null; _active_scene_request.clear(); router.cancel(); source.process_mode = Node.PROCESS_MODE_DISABLED
	# Signals may be inside the scene's own command stack; release after that stack returns.
	_release_scene.call_deferred(source); _refresh_menu()
func _release_scene(source: Variant) -> void: _discard_node(source)
func _open_settings() -> void:
	settings_panel.open(router.settings_storage.snapshot(),router.settings_storage.load_reason)
func _change_settings(patch: Dictionary) -> void:
	var receipt: Dictionary = router.settings_storage.update_settings(patch)
	settings_panel.apply_settings(receipt.settings,receipt.get("reason","")); menu.apply_view_model(router.view_model(),router.generation)
func _exit_tree() -> void:
	_disposed = true
	if router: router.cancel()
