extends SceneTree
## Native pointer regression for manual actions and the compact chart's canvas.
var assertions := 0
var failures := 0
var scene: Node

func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",detail)

func _initialize() -> void: _run.call_deferred()

func _frames() -> void:
	for frame in 4: await process_frame

func _click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new(); motion.position=point; motion.global_position=point; root.push_input(motion,true)
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT; event.position=point; event.global_position=point; event.pressed=pressed
		root.push_input(event,true); await process_frame
	scene._present(0.0); await _frames()

func _key(code: Key) -> void:
	for pressed: bool in [true,false]:
		var event := InputEventKey.new(); event.keycode=code; event.physical_keycode=code; event.pressed=pressed
		root.push_input(event,true); await process_frame
	scene._present(0.0); await _frames()

func _scroll_to(control: Control) -> void:
	var parent := control.get_parent()
	while parent:
		if parent is ScrollContainer: parent.ensure_control_visible(control)
		parent=parent.get_parent()
	await _frames()

func _manual_heading(hud: CanvasLayer) -> Label:
	var manual: Control=hud.find_child("SailingManual",true,false)
	for label: Node in manual.find_children("*","Label",true,false):
		if label.text=="操船手册": return label as Label
	return null

func _fully_visible(control: Control, owner: Control) -> bool:
	if control==null or not control.is_visible_in_tree(): return false
	var bounds:=control.get_global_rect()
	if not owner.get_global_rect().encloses(bounds): return false
	var parent:=control.get_parent()
	while parent and parent!=owner:
		if parent is ScrollContainer and not parent.get_global_rect().encloses(bounds): return false
		parent=parent.get_parent()
	return true

func _run() -> void:
	root.size=Vector2i(1280,720); root.content_scale_size=Vector2i(1280,720)
	scene=load("res://game/scenes/naval_practice/naval_practice.gd").new(); scene.startup_options={"mode":"duel"}; root.add_child(scene)
	await _frames(); scene.set_process(false); scene.set_physics_process(false)
	check(scene.startup_receipt.ok,"real duel scene starts")
	var hud: CanvasLayer=scene.interface
	await _key(KEY_M)
	check(hud.chart.visible,"physical M opens real chart before secondary controls")
	await _click(hud.find_child("close_chart",true,false))
	check(not hud.chart.visible and not scene.runtime.is_paused(),"native chart close releases chart pause")
	await _click(hud.find_child("help",true,false))
	check(hud.find_child("SailingManual",true,false).visible,"native help click opens manual")
	await _scroll_to(hud.find_child("settings",true,false))
	await _click(hud.find_child("settings",true,false))
	check(scene.services.settings_panel.visible,"native manual settings action opens settings")
	await _click(scene.services.settings_panel.find_child("Close",true,false))
	check(not scene.services.settings_panel.visible and not scene.runtime.is_paused(),"native settings close restores prior running state")
	var heading:=_manual_heading(hud)
	check(_fully_visible(heading,hud.find_child("SailingManual",true,false)),"manual title remains completely visible after scrolling to settings and returning")
	check(heading!=null and heading.name=="SailingManualHeading","manual keeps a stable named heading for visual inspection")
	await _key(KEY_ESCAPE)
	check(hud.is_menu_open(),"physical Escape opens menu after settings close")
	await _click(hud.find_child("resume",true,false))
	check(not scene.runtime.is_paused(),"native resume releases menu pause")
	await _scroll_to(hud.find_child("surrender",true,false))
	await _click(hud.find_child("surrender",true,false))
	var state: Dictionary=scene.runtime.snapshot().runtime
	check(not state.surrenderQuote.is_empty() and hud.find_child("confirm_surrender",true,false).is_visible_in_tree(),"visible manual surrender click reaches authority confirmation instead of the compact chart; reasons="+str(state.pauseReasons))
	check(not hud.chart.visible and not "chart" in state.pauseReasons,"manual click cannot accidentally open compact chart behind it")
	check(_fully_visible(heading,hud.find_child("SailingManual",true,false)),"surrender confirmation does not clip the visible manual title")
	if not state.surrenderQuote.is_empty():
		await _click(hud.find_child("cancel_surrender",true,false))
		check(not scene.runtime.is_paused(),"native cancel resumes the ongoing encounter")
	scene.queue_free(); await _frames()
	print("MARITIME_MANUAL_INPUT_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
