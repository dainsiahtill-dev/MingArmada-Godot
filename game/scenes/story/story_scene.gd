extends Node3D
## Story campaign formal entry: composes the story runtime with the shared sea
## presentation and the thin operations panel. Mirrors the legacy scene's
## composition seam (runtime owns settlement; views only present).

signal main_menu_requested
const KEYS := {KEY_W: "KeyW", KEY_S: "KeyS", KEY_A: "KeyA", KEY_D: "KeyD", KEY_UP: "ArrowUp", KEY_DOWN: "ArrowDown", KEY_LEFT: "ArrowLeft", KEY_RIGHT: "ArrowRight", KEY_BRACKETLEFT: "BracketLeft", KEY_BRACKETRIGHT: "BracketRight"}
const Runtime = preload("res://game/runtime/story_runtime.gd")
const Storage = preload("res://game/persistence/save_coordinator.gd")
const Sea = preload("res://game/presentation/world/naval_world_view.gd")
const Interface = preload("res://game/ui/story/story_interface.gd")
const Services = preload("res://game/scenes/common/sea_services.gd")
const Height = preload("res://modules/scene_engine/terrain/height_field.gd")
const Scenarios = preload("res://game/domain/story_campaign/scenarios.gd")
const ReferenceGeography = preload("res://game/scenes/common/reference_geography.gd")
const SeaChart = preload("res://game/scenes/common/sea_chart_overlay.gd")
const EncounterInterface = preload("res://game/ui/encounters/encounter_interface.gd")

var startup_options: Dictionary = {}
var initial_save := ""
var storage: RefCounted = Storage.new("user://saves/story-v1.json", Runtime.validate_save)
var settings_storage: RefCounted
var runtime := Runtime.new()
var startup_receipt: Dictionary = {}
var _sea
var _interface: CanvasLayer
var _services
var _heights
var _minimap
var _encounter_interface
var _disposed := false

func _ready() -> void:
	_heights = Height.new()
	var geo: Dictionary = Scenarios.geography()
	_heights.configure_ports(geo.get("data", {}).get("ports", []), false, ReferenceGeography.source_options())
	var options := startup_options.duplicate(true)
	options.erase("staged")
	options.runId = str(options.get("runId", "story"))
	startup_receipt = runtime.call("configure", _heights.sample_height, options)
	if not startup_receipt.get("ok", false):
		push_error("story runtime configure failed: " + str(startup_receipt.get("reason", "")))
		return
	if not initial_save.is_empty():
		runtime.call("adopt_save", initial_save, null, false)
	if DisplayServer.get_name() != "headless":
		settings_storage = Services.resolve_settings(settings_storage)
		_sea = Sea.new()
		add_child(_sea)
		_sea.apply_settings(settings_storage.snapshot())
		_sea.configure(_heights.sample_height, geo.get("data", {}).get("ports", []), runtime.sample_water_height, runtime.native_snapshot())
		_services = Services.new()
		add_child(_services)
		_services.configure(runtime, _sea, settings_storage)
	_interface = Interface.new()
	add_child(_interface)
	_interface.command_requested.connect(_command)
	_encounter_interface = EncounterInterface.new()
	var layer := CanvasLayer.new()
	layer.layer = 35
	add_child(layer)
	layer.add_child(_encounter_interface)
	_encounter_interface.command_requested.connect(_command)
	_minimap = SeaChart.new()
	add_child(_minimap)
	_minimap.configure(geo.get("data", {}).get("ports", []), _heights.sample_height)
	_present(0.0)
	if not bool(startup_options.get("staged", false)):
		activate_entry()

func _runtime_settings() -> void:
	settings_storage = Services.resolve_settings(settings_storage)

func activate_entry() -> void:
	Engine.physics_ticks_per_second = 60
	get_viewport().msaa_3d = Viewport.MSAA_4X

func _physics_process(delta: float) -> void:
	if _disposed or runtime == null or _sea == null:
		return
	_sea.observe_projectiles(runtime.native_snapshot())
	var consumed: float = runtime.call("advance", delta)
	_present(consumed)

func _present(_consumed: float) -> void:
	var packet: Dictionary = runtime.call("snapshot")
	if _sea != null:
		_sea.apply_snapshot(packet.get("native", {}), [], _consumed)
	if _interface != null:
		_interface.apply_snapshot(packet)
	if _encounter_interface != null:
		var encounter: Variant = packet.get("runtime", {}).get("encounter")
		_encounter_interface.apply_snapshot(encounter if encounter is Dictionary else {}, int(packet.get("runtime", {}).get("revision", 0)))
	if _minimap != null:
		var overlays: Dictionary = SeaChart.navigation_overlays(packet.get("native", {}), {})
		_minimap.present(packet.get("native", {}), overlays, false)

func _command(intent: Dictionary) -> Dictionary:
	var type := str(intent.get("type", ""))
	if type == "main-menu":
		main_menu_requested.emit()
		return {"ok": true}
	if type == "save":
		var exported: Dictionary = runtime.call("save_checkpoint", storage)
		if exported.get("ok", false) and storage != null:
			return storage.write_checkpoint(str(exported.json))
		return exported
	if type == "save-and-menu":
		var saved := _command({"type": "save"})
		main_menu_requested.emit()
		return saved
	if type == "pause":
		return runtime.set_pause(str(intent.get("reason", "player")), bool(intent.get("value", true)))
	return runtime.call("command", intent)

func _input(event: InputEvent) -> void:
	if _disposed or runtime == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		if _sea != null:
			_sea.cancel_camera_drag()
	if not event is InputEventKey or event.echo:
		return
	var key: int = event.physical_keycode if event.physical_keycode else event.keycode
	if not event.pressed:
		if KEYS.has(key):
			runtime.set_held(KEYS[key], false)
		return
	var focus := get_viewport().gui_get_focus_owner()
	if key in [KEY_Q, KEY_E, KEY_R, KEY_1, KEY_2, KEY_3] or KEYS.has(key):
		if focus is LineEdit or focus is TextEdit or focus is SpinBox:
			return
	if KEYS.has(key):
		runtime.set_held(KEYS[key], true)
	elif key == KEY_Q:
		runtime.call("command", {"type": "native-action", "action": {"type": "fire", "shipId": str(runtime.world.state.flagshipId), "side": "port"}})
	elif key == KEY_E:
		runtime.call("command", {"type": "native-action", "action": {"type": "fire", "shipId": str(runtime.world.state.flagshipId), "side": "starboard"}})
	elif key in [KEY_1, KEY_2, KEY_3]:
		runtime.call("command", {"type": "native-action", "action": {"type": "select-ammo", "shipId": str(runtime.world.state.flagshipId), "ammo": {KEY_1: "solid", KEY_2: "chain", KEY_3: "grape"}[key]}})
	elif key == KEY_R:
		runtime.call("command", {"type": "trim"})
	get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if _disposed or _sea == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.physical_keycode if event.physical_keycode else event.keycode
		if key == KEY_F:
			_sea.recenter_camera()
			get_viewport().set_input_as_handled()
			return
	if _sea.handle_camera_input(event):
		get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	_disposed = true
	if _services != null and _services.has_method("dispose"):
		_services.dispose()
	if _sea != null and _sea.has_method("dispose"):
		_sea.dispose()
	runtime.dispose()
