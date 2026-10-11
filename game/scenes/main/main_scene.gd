extends Node
## Native entry lifecycle: generation/token checks surround each deferred stage and transaction.
const Router = preload("res://game/runtime/game_router.gd")
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

func _ready() -> void:
	if not router:
		router = Router.new({"dev":"--dev" in OS.get_cmdline_user_args(),"qa":"--qa" in OS.get_cmdline_user_args()})
	router.settings_storage.load_settings()
	var ui := CanvasLayer.new(); ui.name = "EntryUI"; ui.layer = 100; add_child(ui)
	menu = Menu.new(); ui.add_child(menu); menu.intent_requested.connect(_handle_intent); menu.settings_requested.connect(_open_settings)
	recovery = Recovery.new(); ui.add_child(recovery); recovery.intent_requested.connect(_handle_recovery)
	settings_panel = SettingsPanel.new(); ui.add_child(settings_panel); settings_panel.settings_requested.connect(_change_settings)
	_refresh_menu()

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
	current_scene = null; router.cancel(); source.process_mode = Node.PROCESS_MODE_DISABLED
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
