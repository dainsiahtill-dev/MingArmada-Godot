extends SceneTree
const Settings = preload("res://game/persistence/user_settings.gd")
const Storage = preload("res://game/persistence/save_coordinator.gd")
const Runtime = preload("res://game/runtime/legacy_runtime.gd")
var failures := 0
var assertions := 0
var exits := 0
func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ",detail)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var path := "res://game/scenes/legacy/legacy_scene.gd"
	var script = load(path) if ResourceLoader.exists(path) else null
	check(script != null,"native Legacy scene must connect career, UI, sea and saves")
	if script:
		root.size = Vector2i(1600,900)
		var scene = script.new()
		scene.storage = Storage.new("user://tests/legacy-scene-%s.json" % OS.get_process_id(),Runtime.validate_save)
		scene.settings_storage = Settings.new("user://tests/legacy-scene-settings-%s.json" % OS.get_process_id())
		root.add_child(scene); await process_frame
		scene.set_physics_process(false)
		check(scene.runtime.snapshot().adventure.currentPortId == "xiamen","actual new1661 docks at source home port")
		check(scene.sea.ships.has("player") and scene.sea.sailors.has("player"),"native career renders original flagship and sailors")
		var before: Dictionary = scene.runtime.snapshot().adventure
		var buy: Button = scene.interface.find_child("buy_grain",true,false)
		check(buy != null and not buy.disabled,"real market button uses runtime transaction preview")
		if buy: buy.pressed.emit()
		var after: Dictionary = scene.runtime.snapshot().adventure
		check(after.player.silver < before.player.silver and after.cargo.grain > before.cargo.grain,"UI buy reaches actual career money, inventory and quote authority")
		scene.interface.open_panel("chart")
		check("panel" in scene.runtime.snapshot().runtime.pauseReasons,"opening a named page string pauses the real career")
		scene.interface.close_panel()
		check(not ("panel" in scene.runtime.snapshot().runtime.pauseReasons),"closing a page boolean releases only the panel pause")
		scene.interface.open_panel("people")
		var banquet: Button = scene.interface.find_child("banquet",true,false)
		check(banquet != null and not banquet.disabled,"docked career has a ready actual banquet launch control")
		if banquet: banquet.pressed.emit()
		var encounter: Dictionary = scene.runtime.snapshot().runtime.encounter
		check(not encounter.is_empty() and scene.encounter_interface.visible,"actual People button mounts the career encounter interface")
		var sea_before: Dictionary = scene.runtime.native_snapshot()
		scene._physics_process(0.1)
		check(scene.runtime.snapshot().runtime.encounter.state.elapsed > encounter.state.elapsed and scene.runtime.native_snapshot() == sea_before,"originating panel freezes sea while actual banquet clock progresses")
		var gesture: Button = scene.encounter_interface.find_child("gesture_up",true,false)
		var mistakes: int = scene.runtime.snapshot().runtime.encounter.state.mistakes
		if gesture: gesture.pressed.emit()
		check(gesture != null and scene.runtime.snapshot().runtime.encounter.state.mistakes == mistakes+1,"actual encounter control reaches the authoritative off-beat action while panel remains open")
		check(scene._command({"type":"encounter-close","id":encounter.id}).ok,"career encounter returns through the same scene routing")
		scene.interface.close_panel()
		var depart: Button = scene.interface.find_child("depart",true,false)
		if depart: depart.pressed.emit()
		check(scene.runtime.snapshot().adventure.currentPortId == null,"actual departure button releases career anchorage")
		scene.interface.open_panel("chart")
		var waypoint: Button = scene.interface.find_child("waypoint_kinmen",true,false)
		check(waypoint != null,"chart exposes the source kinmen port waypoint")
		if waypoint: waypoint.pressed.emit()
		var routed: Dictionary = scene.runtime.native_snapshot()
		check(Runtime._ship(routed,routed.playerId).has("navigation"),"actual chart waypoint installs a native route under panel suspension: "+scene.runtime.snapshot().runtime.notice)
		check(not scene.interface.is_panel_open() and not ("panel" in scene.runtime.snapshot().runtime.pauseReasons),"successful chart navigation returns to sea and releases only originating panel pause")
		scene.interface.open_menu()
		var paused: Dictionary = scene.runtime.snapshot()
		scene._physics_process(10)
		check(scene.runtime.snapshot().naval == paused.naval and scene.runtime.snapshot().adventure == paused.adventure,"native menu freezes both sea and business clocks")
		scene.interface.close_menu()
		scene.runtime.set_pause("player",true)
		scene.services.open_settings()
		var row: Control = scene.services.settings_panel.find_child("quality",true,false)
		var choice: OptionButton = row.get_node("Value") if row else null
		check(choice != null,"real Legacy settings modal contains a focusable quality selector")
		if choice: choice.grab_focus()
		var escape := InputEventKey.new(); escape.physical_keycode = KEY_ESCAPE; escape.pressed = true
		Input.parse_input_event(escape); await process_frame
		check(not scene.services.captures_keyboard(),"physical-only Escape closes Legacy settings before GUI selector consumes it")
		check("player" in scene.runtime.snapshot().runtime.pauseReasons and not ("menu" in scene.runtime.snapshot().runtime.pauseReasons),"closing Legacy settings retains independent player pause")
		scene.runtime.set_pause("player",false)
		check(scene._command({"type":"settings","value":{"handling":"realistic","quality":"low","sound":false,"reducedMotion":true,"musicVolume":0.23}}).ok,"scene settings command verifies disk before applying")
		check(scene.runtime.snapshot().runtime.handlingMode == "realistic" and not scene.services.settings_storage.snapshot().sound,"same verified setting reaches runtime and audio owner")
		scene.interface.open_panel("settings")
		var quality: OptionButton = scene.interface.find_child("quality",true,false)
		check(quality.get_item_metadata(quality.selected) == "low" and not scene.interface.find_child("setting_sound",true,false).button_pressed and scene.interface.find_child("setting_reducedMotion",true,false).button_pressed and scene.interface.find_child("musicVolume",true,false).value == 23,"actual career settings display confirmed preferences")
		var apply_settings: Button = scene.interface.find_child("apply_settings",true,false)
		if apply_settings: apply_settings.pressed.emit()
		check(scene.services.settings_storage.snapshot().musicVolume == 0.23 and not scene.services.settings_storage.snapshot().sound,"Apply without edits preserves verified preferences")
		scene.interface.close_panel()
		scene.main_menu_requested.connect(func(): exits += 1)
		var recovered_storage = scene.storage
		scene.storage = Storage.new("res://project.godot/scene-save.json",Runtime.validate_save)
		check(not scene._command({"type":"save-and-menu"}).ok and exits == 0,"failed verified save never exits the native career")
		scene.interface.open_menu()
		var saves: Array = []
		scene.interface.command_requested.connect(func(intent):
			if intent.type == "save": saves.append(intent))
		var save_button: Button = scene.interface.find_child("menu_save",true,false)
		var revision: int = scene.runtime.snapshot().runtime.revision
		if save_button: save_button.pressed.emit()
		check(saves.size() == 1 and not scene.runtime.snapshot().runtime.lastSaveReceipt.ok and scene.runtime.snapshot().runtime.revision == revision,"real save failure does not invent business revision: "+JSON.stringify({"calls":saves.size(),"receipt":scene.runtime.snapshot().runtime.lastSaveReceipt,"before":revision,"after":scene.runtime.snapshot().runtime.revision}))
		check(scene.interface._pending.is_empty(),"scene acknowledges completed failed UI requests without waiting for business revision")
		scene.storage = recovered_storage
		# UI debounce consumes actual wall time, independent of simulated delta.
		var retry_at := Time.get_ticks_msec()+300
		while Time.get_ticks_msec()<retry_at: await process_frame
		if save_button: save_button.pressed.emit()
		check(saves.size() == 2 and scene.runtime.snapshot().runtime.lastSaveReceipt.ok and scene.storage.read_checkpoint().ok,"same actual Save button retries after storage recovery and verifies disk: "+JSON.stringify({"calls":saves.size(),"receipt":scene.runtime.snapshot().runtime.lastSaveReceipt,"disk":scene.storage.read_checkpoint().ok}))
		check(scene._command({"type":"save-and-menu"}).ok and exits == 1,"save-and-menu routes only after a real verified checkpoint")
		check(scene.storage.read_checkpoint().ok,"saved checkpoint is actual valid v1 disk JSON")
		scene.interface.close_menu()
		var fixtures = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/legacy-runtime-reference.json"))
		check(scene.runtime.adopt_save(fixtures.careerCheckpoints["14"]).ok,"real source v1 hostile checkpoint adopts into native scene")
		scene._present(0)
		scene.interface.open_panel("settings")
		var surrender: Button = scene.interface.find_child("begin_surrender",true,false)
		check(surrender != null and not surrender.disabled,"actual career surrender control remains reachable with a valid hostile")
		if surrender: surrender.pressed.emit()
		var quote = scene.runtime.snapshot().runtime.surrenderQuote
		check(quote is Dictionary and scene.interface.find_child("surrender_cancel",true,false).visible,"actual surrender button produces token-fenced native quote and dialog")
		if quote is Dictionary: scene.interface.find_child("surrender_cancel",true,false).pressed.emit()
		check(scene.runtime.snapshot().runtime.surrenderQuote == null,"actual cancel control resolves quote without changing hostile settlement")
		scene.interface.close_panel()
		scene.queue_free(); await process_frame; await process_frame
		# The native mixing worker releases stopped WAV voices asynchronously.
		# This waits for that real worker; no game or accepted time advances.
		await create_timer(0.08).timeout
	print("LEGACY_SCENE_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
