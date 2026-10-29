extends SceneTree
## Real Controls keep the sea open and every command reachable in a small window.
var assertions := 0
var failures := 0
var commands: Array = []

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	_run.call_deferred()

func _settle() -> void:
	for frame in 10: await process_frame

func _inside(control: Control, bounds: Rect2) -> bool:
	var rect := control.get_global_rect()
	return rect.position.x >= bounds.position.x - 1 and rect.end.x <= bounds.end.x + 1 and rect.position.y >= bounds.position.y - 1 and rect.end.y <= bounds.end.y + 1

func _run() -> void:
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1600, 900)
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/mingqi-reference.json"))
	var packet := {"campaign": reference.initial, "naval": {"ships": []}, "runtime": {"generation": 70, "status": "ready", "paused": false}}
	var ui = load("res://game/ui/mingqi/mingqi_interface.gd").new()
	root.add_child(ui)
	ui.command_requested.connect(func(intent): commands.append(intent))
	ui.apply_snapshot(packet)
	await _settle()
	var dock = ui.find_child("command_dock", true, false)
	var command_scroll = ui.find_child("command_scroll", true, false)
	check(dock is PanelContainer and command_scroll is ScrollContainer, "commands have a separate painted dock with native scrolling")
	if not dock is PanelContainer or not command_scroll is ScrollContainer:
		ui.free()
		print("MINGQI_PAINTED_LAYOUT_TESTS assertions=", assertions, " failures=", failures)
		quit(1)
		return
	for viewport in [Vector2i(1600, 900), Vector2i(1280, 720)]:
		root.size = viewport
		await _settle()
		var hud: Control = ui.find_child("hud", true, false)
		var operation: Control = ui.find_child("operation", true, false)
		print("PAINTED_LAYOUT viewport=", viewport, " hud=", hud.get_rect(), " operation=", operation.get_rect(), " commands=", dock.get_rect())
		check(hud.size.x <= 380 and hud.size.y <= 270, "summary stays compact at " + str(viewport))
		check(dock.position.y >= viewport.y - 145 and dock.get_rect().end.y <= viewport.y - 10, "commands sit along the lower edge at " + str(viewport))
		check(operation.get_rect().end.y <= dock.position.y - 10, "reading panel clears command dock at " + str(viewport))
		check(operation.position.x - hud.get_rect().end.x >= viewport.x * 0.23, "central sea corridor remains open at " + str(viewport))
		for id in ["pause", "speed_0_25", "speed_1_0", "speed_8_0", "menu_open", "camera_captain", "camera_tactical", "stop_sailing", "sailing_manual"]:
			var control = ui.find_child(id, true, false)
			check(control is Button and dock.is_ancestor_of(control), "live command belongs to lower dock: " + id)
		for id in ["ship", "convoy", "port", "boarding", "tactics", "story"]:
			var tab: Button = ui.find_child("nav_" + id, true, false)
			tab.pressed.emit()
			await _settle()
			check(ui.find_child("panel_" + id, true, false).is_visible_in_tree(), "painted tab opens native page: " + id)
			check(tab.button_pressed, "selected tab has a persistent live state: " + id)
	check(commands.is_empty(), "page navigation remains local")
	var decoration = ui.find_child("header_cartouche", true, false)
	if decoration: check(decoration.mouse_filter == Control.MOUSE_FILTER_IGNORE, "header art passes pointer through")
	check(ui.get("_screen").mouse_filter == Control.MOUSE_FILTER_IGNORE, "clear sea keeps world input ownership")
	root.size = Vector2i(320, 480)
	await _settle()
	var bounds := Rect2(Vector2.ZERO, Vector2(320, 480))
	for id in ["hud", "operation", "command_dock"]:
		check(_inside(ui.find_child(id, true, false), bounds), "small window keeps panel inside viewport: " + id)
		var style: StyleBox=ui.find_child(id,true,false).get_theme_stylebox("panel")
		check(style.has_method("get_edge_style") and style.call("get_edge_style").texture!=null,"small independent window retains generated external frame and shadow: "+id)
	check(ui.find_child("operation", true, false).size.y >= 100, "small window preserves a scrollable reading area")
	for id in ["nav_ship", "nav_convoy", "nav_port", "nav_boarding", "nav_tactics", "nav_story", "pause", "speed_0_25", "speed_1_0", "speed_8_0", "menu_open", "camera_captain", "camera_tactical", "stop_sailing", "sailing_manual"]:
		var control: Control = ui.find_child(id, true, false)
		if control == null:
			check(false, "small window command exists: " + id)
			continue
		command_scroll.ensure_control_visible(control)
		await _settle()
		check(_inside(control, command_scroll.get_global_rect()), "small window can scroll to complete command: " + id)
	for page in ["ship", "convoy", "port", "boarding", "tactics", "story"]:
		ui.open_panel(page)
		await _settle()
		var page_control: Control = ui.find_child("panel_" + page, true, false)
		var operation_scroll: ScrollContainer = ui.find_child("operation_scroll", true, false)
		check(page_control.get_global_rect().end.x <= operation_scroll.get_global_rect().end.x + 1, "small reading page has no clipped horizontal controls: " + page)
	var manual: Button = ui.find_child("sailing_manual", true, false)
	manual.pressed.emit()
	await _settle()
	check(ui.find_child("keys", true, false).is_visible_in_tree(), "lower manual control opens full existing instructions")
	packet.runtime.generation = 71
	ui.apply_snapshot(packet)
	await _settle()
	check(ui.find_child("keys", true, false).is_visible_in_tree(), "painted reconstruction keeps manual state")
	check(commands.is_empty(), "layout and manual never emit simulation commands")
	ui.free()
	await process_frame
	print("MINGQI_PAINTED_LAYOUT_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
