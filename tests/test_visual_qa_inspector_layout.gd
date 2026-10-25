extends SceneTree
var assertions := 0
var failures := 0
func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ", detail)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size = Vector2i(1600,900)
	var inspector = load("res://game/scenes/visual_qa/visual_qa_inspector.gd").new()
	root.add_child(inspector)
	inspector.find_child("scenario",true,false).select(4)
	await process_frame; await process_frame; await process_frame
	root.size = Vector2i(320,480)
	root.content_scale_size = Vector2i(320,480)
	await process_frame; await process_frame; await process_frame
	var panel: Control = inspector.get("_panel")
	print("QA_PANEL_RECT ",panel.get_rect()," minimum=",panel.get_combined_minimum_size())
	check(panel.get_rect().end.x <= 320 and panel.get_rect().end.y <= 480, "paper inspector fits 320 by 480 without obscuring exit")
	var scenario: OptionButton = inspector.find_child("scenario",true,false)
	check(scenario.get_item_text(4).contains("QA火力2%"), "narrow selection keeps the complete low-damage scenario description in its popup")
	var intents: Array = []
	inspector.command_requested.connect(func(intent): intents.append(intent))
	scenario.item_selected.emit(4)
	check(intents == [{"type":"scenario","value":"impact-weak"}], "clipped selection still emits the canonical scenario intent")
	check(inspector.get("_screen").mouse_filter == Control.MOUSE_FILTER_IGNORE, "inspector still leaves world input outside panel")
	check(inspector.find_child("diagnostics",true,false).get_theme_font_size("font_size") == 11, "dense diagnostic readout retains its explicit small font")
	inspector.free()
	await process_frame
	print("VISUAL_QA_INSPECTOR_LAYOUT_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
