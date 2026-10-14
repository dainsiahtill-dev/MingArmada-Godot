extends SceneTree
var assertions := 0
var failures := 0
func check(ok: bool, reason: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ",reason)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	check(ResourceLoader.exists("res://game/research/parameter_panel.gd"),"topic-specific parameter panel available")
	if failures: finish(); return
	var panel: Control = load("res://game/research/parameter_panel.gd").new()
	root.add_child(panel)
	var specs: Array = [
		{"id":"camera_mode","label":"视角","type":"choice","value":"near","choices":[{"value":"near","label":"近处"},{"value":"far","label":"远处"}]},
		{"id":"reflection","label":"反射","type":"toggle","value":true},
		{"id":"detail","label":"细节","type":"range","value":0.1,"min":0.0,"max":0.3,"step":0.01}]
	check(panel.bind_specs(specs).ok,"choice toggle numeric controls bind")
	var events: Array = []
	panel.parameter_changed.connect(func(id: String,value: Variant): events.append([id,value]))
	var camera: OptionButton = panel.find_child("Param_camera_mode",true,false)
	var reflection: CheckBox = panel.find_child("Param_reflection",true,false)
	var detail: SpinBox = panel.find_child("Param_detail",true,false)
	check(camera.selected == 0 and reflection.button_pressed and is_equal_approx(detail.value,0.1),"defaults reflected in actual controls")
	panel.sync_values({"camera_mode":"far","reflection":false,"detail":0.2})
	check(camera.selected == 1 and not reflection.button_pressed and is_equal_approx(detail.value,0.2),"restored inputs shown correctly")
	check(events.is_empty(),"snapshot sync cannot advance experiment via callback")
	camera.item_selected.emit(0); reflection.set_pressed(true); detail.value = 0.25
	check(events.size() == 3 and events[0] == ["camera_mode","near"] and events[1] == ["reflection",true] and events[2] == ["detail",0.25],"actual controls emit declared typed values")
	var count: int = panel.get_child_count()
	check(not panel.bind_specs([specs[0],specs[0]]).ok,"duplicate parameter IDs rejected")
	check(panel.get_child_count() == count,"invalid binding does not destroy existing controls")
	check(not panel.bind_specs([{"id":"x","label":"x","type":"range","value":1.0,"min":2.0,"max":1.0,"step":0.1}]).ok,"inverted ranges rejected")
	check(not panel.bind_specs([{"id":"x","label":"x","type":"choice","value":"bad","choices":[{"value":"ok","label":"ok"}]}]).ok,"unknown default choices rejected")
	check(panel.bind_specs([]).ok and panel.get_child_count() == 0,"switching to no controls frees all widgets")
	panel.free(); await process_frame; finish()
func finish() -> void:
	print("LABORATORY_PARAMETERS_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
