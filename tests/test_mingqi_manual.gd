extends SceneTree
## HUD manual remains local and survives real snapshot reconstruction.
var failures := 0
var commands: Array = []

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _settle() -> void:
	for frame in 8: await process_frame

func _run() -> void:
	root.size = Vector2i(1600, 900)
	root.content_scale_size = Vector2i.ZERO
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/mingqi-reference.json"))
	var ui = load("res://game/ui/mingqi/mingqi_interface.gd").new()
	root.add_child(ui)
	ui.command_requested.connect(func(intent): commands.append(intent))
	var packet := {"campaign": reference.initial, "naval": {"ships": []}, "runtime": {"generation": 40, "status": "ready", "paused": false}}
	ui.apply_snapshot(packet)
	await _settle()
	var hud = ui.find_child("hud", true, false)
	var keys = ui.find_child("keys", true, false)
	var toggle = ui.find_child("sailing_manual", true, false)
	var collapsed_height: float = hud.size.y
	print("MANUAL_INITIAL size=", hud.size, " min=", hud.get_combined_minimum_size())
	check(toggle is Button, "manual must have a discoverable toggle")
	check(keys is Label and not keys.is_visible_in_tree(), "four-line manual is hidden initially")
	if not toggle is Button or not keys is Label:
		ui.free()
		quit(1)
		return
	check(toggle.text == "操船手册", "collapsed toggle identifies manual")
	toggle.pressed.emit()
	await _settle()
	check(keys.is_visible_in_tree() and toggle.text == "收起手册", "toggle opens manual and offers close")
	check(keys.text.contains("左键") and keys.text.contains("右键") and keys.text.contains("W/S") and keys.text.contains("Esc"), "all original four instruction lines remain available")
	var expanded_height: float = hud.size.y
	print("MANUAL_EXPANDED size=", hud.size, " min=", hud.get_combined_minimum_size())
	check(expanded_height > collapsed_height + 30.0, "collapsed HUD recovers manual space")
	ui.open_panel("port")
	packet.campaign = reference.steps[-1].state
	ui.apply_snapshot(packet)
	await _settle()
	var rebuilt = ui.find_child("sailing_manual", true, false)
	keys = ui.find_child("keys", true, false)
	check(rebuilt != toggle, "recorded structural snapshot rebuilds HUD")
	check(rebuilt is Button and keys.is_visible_in_tree() and rebuilt.text == "收起手册", "open manual survives panel change and snapshot rebuild")
	if rebuilt is Button: rebuilt.pressed.emit()
	await _settle()
	check(not keys.is_visible_in_tree() and rebuilt.text == "操船手册", "manual closes again")
	check(ui.find_child("hud", true, false).size.y < expanded_height - 30.0, "closing the manual releases its HUD space")
	packet.runtime.generation = 41
	ui.apply_snapshot(packet)
	await _settle()
	check(not ui.find_child("keys", true, false).is_visible_in_tree(), "closed manual survives generation rebuild")
	check(commands.is_empty(), "manual actions do not emit business or runtime commands")
	ui.free()
	await process_frame
	print("MINGQI_MANUAL failures=", failures)
	quit(1 if failures else 0)
