extends Node
## Shared scene-owned settings and audio wiring, with verified persistent patches.
const UserSettings = preload("res://game/persistence/user_settings.gd")
const GameAudio = preload("res://game/presentation/audio/game_audio.gd")
const SettingsPanel = preload("res://game/ui/settings/settings_panel.gd")
signal settings_changed(settings: Dictionary)
var settings_storage: RefCounted
var audio: Node
var settings_panel: Control
var _runtime: RefCounted
var _sea: Node3D
var _layer: CanvasLayer
var _menu_was_paused := false
var _disposed := false

static func resolve_settings(storage: RefCounted = null) -> RefCounted:
	# The app loads its store before injection. Standalone scene owners resolve
	# their own store before building the first world at the confirmed quality.
	if storage != null: return storage
	var owned := UserSettings.new()
	owned.load_settings()
	return owned

func configure(runtime: RefCounted, sea: Node3D, storage: RefCounted = null) -> void:
	_disconnect_presentation_failure()
	_runtime = runtime; _sea = sea
	if _sea.has_signal("presentation_failed"):
		_sea.connect("presentation_failed",_on_presentation_failed)
	settings_storage = resolve_settings(storage)
	audio = GameAudio.new(); add_child(audio)
	_layer = CanvasLayer.new(); _layer.layer = 50; add_child(_layer)
	settings_panel = SettingsPanel.new(); _layer.add_child(settings_panel)
	settings_panel.settings_requested.connect(change_settings)
	settings_panel.close_requested.connect(close_settings)
	_apply(settings_storage.snapshot())

func _on_presentation_failed(receipt: Dictionary) -> void:
	if _disposed or _runtime==null: return
	_runtime.set_pause("error",true)
	if is_instance_valid(audio): audio.set_paused(true)
	var message := "画面资源未能载入，航行已暂停。请返回首页重试。（"+str(receipt.get("reason","presentation-unavailable"))+"）"
	if _runtime.has_method("_notify"):
		_runtime.call("_notify",message)
	else:
		# Practice/legacy expose the existing notice field without a notifier.
		for property: Dictionary in _runtime.get_property_list():
			if property.name=="_notice" and _runtime.get("_notice") is String:
				_runtime.set("_notice",message)
				break

func _disconnect_presentation_failure() -> void:
	if is_instance_valid(_sea) and _sea.has_signal("presentation_failed") and _sea.is_connected("presentation_failed",_on_presentation_failed):
		_sea.disconnect("presentation_failed",_on_presentation_failed)

func _apply(settings: Dictionary) -> void:
	_runtime.set_handling_mode(settings.handling)
	_sea.apply_settings(settings); audio.apply_settings(settings)
	settings_panel.apply_settings(settings)
	settings_changed.emit(settings.duplicate(true))

func change_settings(patch: Dictionary) -> Dictionary:
	if _disposed: return {"ok":false,"reason":"scene-disposed"}
	var receipt: Dictionary = settings_storage.update_settings(patch)
	if receipt.ok: _apply(receipt.settings)
	settings_panel.apply_settings(settings_storage.snapshot(),receipt.get("reason",""))
	return receipt

func present(native: Dictionary, events: Array, consumed: float, paused: bool) -> void:
	if _disposed: return
	audio.set_listener(_sea.camera.global_position)
	var failed: bool=_sea.has_method("presentation_status") and _sea.presentation_status().get("failed",false)
	audio.set_paused(paused or failed)
	audio.apply_snapshot(native,consumed); audio.apply_events(events)

func captures_keyboard() -> bool:
	return settings_panel != null and settings_panel.visible

func open_settings() -> void:
	if _disposed or settings_panel.visible: return
	_menu_was_paused = "menu" in _runtime.snapshot().runtime.pauseReasons
	_runtime.set_pause("menu",true)
	settings_panel.open(settings_storage.snapshot())

func close_settings() -> void:
	if _disposed: return
	settings_panel.close(); _runtime.set_pause("menu",_menu_was_paused)

func dispose() -> void:
	if _disposed: return
	_disposed = true
	_disconnect_presentation_failure()
	if audio: audio.dispose()
	_runtime = null; _sea = null

func _exit_tree() -> void: dispose()
