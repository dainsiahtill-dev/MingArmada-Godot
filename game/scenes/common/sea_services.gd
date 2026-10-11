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

func configure(runtime: RefCounted, sea: Node3D, storage: RefCounted = null) -> void:
	_runtime = runtime; _sea = sea
	settings_storage = storage if storage else UserSettings.new()
	settings_storage.load_settings()
	audio = GameAudio.new(); add_child(audio)
	_layer = CanvasLayer.new(); _layer.layer = 50; add_child(_layer)
	settings_panel = SettingsPanel.new(); _layer.add_child(settings_panel)
	settings_panel.settings_requested.connect(change_settings)
	settings_panel.close_requested.connect(close_settings)
	_apply(settings_storage.snapshot())

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
	audio.set_paused(paused)
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
	if audio: audio.dispose()
	_runtime = null; _sea = null

func _exit_tree() -> void: dispose()
