extends SceneTree
## Layout and native input checks; headless evidence does not prove rendered art.
var assertions := 0
var failures := 0

func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", detail)

func _initialize() -> void: _run.call_deferred()

func _settle() -> void:
	for frame in 4: await process_frame

func _key(code: Key) -> void:
	var event := InputEventKey.new(); event.keycode = code; event.physical_keycode = code; event.pressed = true
	Input.parse_input_event(event); await process_frame
	event = event.duplicate(); event.pressed = false; Input.parse_input_event(event); await process_frame

func _inside(control: Control, bounds: Rect2) -> bool:
	var rect := control.get_global_rect()
	return rect.position.x >= bounds.position.x and rect.end.x <= bounds.end.x + 1 and rect.position.y >= bounds.position.y and rect.end.y <= bounds.end.y + 1

func _run() -> void:
	root.size = Vector2i(1280,720); root.content_scale_size = Vector2i(1280,720)
	var runtime = load("res://game/runtime/naval_practice_runtime.gd").new()
	check(runtime.configure(func(_x,_z): return -50.0,{"mode":"duel"}).ok,"canonical duel fixture starts")
	var hud = load("res://game/ui/naval_practice.gd").new(); root.add_child(hud)
	var intents: Array = []; hud.command_requested.connect(func(intent): intents.append(intent))
	hud.apply_snapshot(runtime.snapshot()); await _settle()
	check(hud.get("_panel").size.y <= 150,"navigation summary leaves the horizon open instead of a tall scrolling board: "+str(hud.get("_panel").get_rect())+" status="+str(hud.get("_status").get_rect()))
	var help: Control = hud.find_child("MouseSailingHint",true,false)
	check(help != null and not help.is_visible_in_tree(),"low frequency sailing manual starts collapsed")
	var help_button: Button = hud.find_child("help",true,false)
	check(help_button != null,"manual has a discoverable control")
	if help_button:
		help_button.pressed.emit(); await _settle()
		check(help.is_visible_in_tree() and intents.is_empty(),"opening manual reveals existing controls without issuing simulation commands")
		help_button.pressed.emit(); await _settle()
		check(not help.is_visible_in_tree(),"manual can be closed again")
	hud.find_child("fire_starboard",true,false).pressed.emit()
	check(intents == [{"type":"fire","side":"starboard"}],"compact cannon control keeps canonical fire intent")
	intents.clear(); hud.apply_snapshot(runtime.snapshot())
	check(intents.is_empty(),"snapshot updates do not manufacture commands")
	check(hud.get("_screen").mouse_filter == Control.MOUSE_FILTER_IGNORE,"clear sea remains outside HUD input ownership")
	root.size = Vector2i(320,480); root.content_scale_size = Vector2i(320,480); await _settle()
	check(_inside(hud.get("_panel"),root.get_visible_rect()),"320 wide summary stays inside viewport")
	var commands: Control = hud.find_child("CommandPanel",true,false)
	check(commands != null,"high frequency controls have their own command rail")
	if commands: check(_inside(commands,root.get_visible_rect()),"320 wide command rail stays inside viewport")
	hud.free(); runtime.dispose()

	var previous := Button.new(); root.add_child(previous); previous.grab_focus()
	var panel = load("res://game/ui/settings/settings_panel.gd").new(); root.add_child(panel)
	var patches: Array = []; panel.settings_requested.connect(func(patch): patches.append(patch))
	var defaults: Dictionary = load("res://game/persistence/user_settings.gd").defaults()
	panel.open(defaults); await _settle()
	var paper: Control = panel.get_node("Center/Panel")
	check(_inside(paper,root.get_visible_rect()),"320 wide settings sheet fits viewport on both axes: "+str(paper.get_global_rect()))
	var fields: Node = panel.get_node("Center/Panel/Column/Scroll/Fields")
	for row in fields.get_children():
		if not row.has_node("Value"): continue
		var value: Control = row.get_node("Value")
		check(value.get_global_rect().end.x <= root.get_visible_rect().end.x,"setting control stays horizontally reachable: "+row.name)
	check(not fields.get_node("sound/Value").button_pressed and not fields.get_node("music/Value").button_pressed,"presentation keeps both audio defaults muted")
	check(fields.get_node("sound/Value").text == "已关闭" and fields.get_node("music/Value").text == "已关闭","confirmed muted defaults have explicit closed captions")
	var enabled_settings := defaults.duplicate(true); enabled_settings.sound=true; panel.apply_settings(enabled_settings)
	check(fields.get_node("sound/Value").text == "已开启" and fields.get_node("music/Value").text == "已关闭","confirmed boolean captions distinguish enabled sound and muted music")
	panel.apply_settings(defaults)
	var sound: CheckButton = fields.get_node("sound/Value"); sound.grab_focus(); await _key(KEY_SPACE)
	check(patches == [{"sound":true}],"focused native sound switch emits exactly the keyboard change")
	patches.clear(); panel.apply_settings(defaults); check(patches.is_empty(),"confirmed settings reapply silently")
	var slider: HSlider = fields.get_node("soundVolume/Value"); slider.grab_focus(); var before := slider.value; await _key(KEY_LEFT)
	check(slider.value < before and patches.size() == 1 and patches[0].has("soundVolume"),"native volume slider retains keyboard focus and patch semantics")
	patches.clear()
	var quality: OptionButton = fields.get_node("quality/Value"); quality.grab_focus(); await _key(KEY_SPACE); await _settle()
	check(quality.get_popup().visible,"native quality menu opens from narrow layout keyboard focus")
	await _key(KEY_DOWN); await _key(KEY_ENTER)
	check(patches == [{"quality":"high"}],"native quality menu commits the chosen canonical value exactly once")
	panel.apply_settings(defaults,"settings-write-failed"); await _settle()
	check(_inside(paper,root.get_visible_rect()),"narrow persistence error keeps Return and settings sheet inside viewport")
	panel.close(); check(root.gui_get_focus_owner() == previous,"closing settings restores previous focus")
	panel.free(); previous.free(); await process_frame
	print("MARITIME_HUD_LAYOUT_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
