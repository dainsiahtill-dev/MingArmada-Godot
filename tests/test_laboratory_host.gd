extends SceneTree
var assertions := 0
var failures := 0
func check(ok: bool, reason: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ",reason)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	print("HOST_STAGE create ",Time.get_ticks_msec())
	var lab: Control = load("res://game/research/laboratory.gd").new()
	root.add_child(lab); await process_frame
	check(lab.has_method("step_demo"),"unified host provides a single accepted step")
	if not lab.has_method("step_demo"): lab.free(); finish(); return
	check(lab.start_demo({"paused":true}).ok,"hull experiment still starts through shared host")
	print("HOST_STAGE hull ready ",Time.get_ticks_msec())
	var before: Dictionary = lab.inspection_snapshot().demo
	check(lab.step_demo().ok,"paused experiment allows one step")
	var after: Dictionary = lab.inspection_snapshot().demo
	check(after.tick == before.tick+1 and after.time > before.time and after.paused,"single step advances exactly once and preserves pause")
	lab._pause_demo(); before = lab.inspection_snapshot().demo
	check(not lab.step_demo().ok and lab.inspection_snapshot().demo.tick == before.tick,"running experiment cannot receive extra hidden steps")
	for topic: String in ["ocean-surface","shore-surf","weather-shadow"]:
		print("HOST_STAGE start ",topic," ",Time.get_ticks_msec())
		check(lab.select_topic(topic),"environment research selectable: "+topic)
		check(lab.start_demo({"paused":true}).ok,"registered independent demo starts: "+topic)
		print("HOST_STAGE ready ",topic," ",Time.get_ticks_msec())
		var receipt: Dictionary = lab.inspection_snapshot()
		check(not receipt.demo.is_empty() and receipt.demo.ready,"independent scene ready: "+topic)
		if receipt.demo.is_empty(): continue
		check(not receipt.parameters.has("kind") and not receipt.parameters.has("contact_enabled"),"hull options do not leak into environment topic: "+topic)
		check(lab.find_child("TopicParameters",true,false).visible,"topic-specific controls visible: "+topic)
		before = lab.inspection_snapshot().demo
		check(lab.step_demo().ok and lab.inspection_snapshot().demo.tick == before.tick+1,"shared single-step works: "+topic)
		lab._demo.orbit_camera(0.18,0.08); lab._demo.zoom_camera(-0.12)
		var observer := camera_matrix(lab.inspection_snapshot().demo)
		lab._reset_demo()
		check(camera_matrix(lab.inspection_snapshot().demo) == observer and lab.inspection_snapshot().demo.tick == 0,"same-condition reset preserves observer: "+topic)
		var original_size: Vector2i = root.size
		root.size = original_size + Vector2i(130,70)
		for _frame in 3: await process_frame
		if topic != "weather-shadow":
			check(lab._demo._ocean._last_viewport_size == Vector2(lab._viewport.size),"paused resize refreshes projected surface immediately: "+topic)
		check(lab.inspection_snapshot().demo.tick == 0,"resize does not advance simulation: "+topic)
		root.size = original_size
		for _frame in 3: await process_frame
		if topic == "weather-shadow":
			var observer_options: Dictionary = lab.inspection_snapshot().demo.parameters
			lab._change_parameter("preset","storm")
			check(lab.inspection_snapshot().demo.parameters.preset == "storm" and lab.inspection_snapshot().demo.tick == 0,"reset-required preset applied by host")
			var preset_options: Dictionary = lab.inspection_snapshot().demo.parameters
			check(preset_options.orbit_yaw == observer_options.orbit_yaw and preset_options.orbit_pitch == observer_options.orbit_pitch and preset_options.zoom == observer_options.zoom,"preset reset preserves relative observer while framing the new weather center")
		lab._show_paper(); await process_frame
		check(lab.inspection_snapshot().demo.is_empty() and lab.find_child("ExperimentViewport",true,false).get_child_count() == 0,"topic switch releases isolated resources: "+topic)
	lab.select_topic("hull-contact"); lab.start_demo({"paused":true})
	check(lab.find_child("ExperimentShip",true,false).is_visible_in_tree(),"legacy hull controls restored after other subjects")
	lab.dispose(); lab.free(); await process_frame; finish()
func camera_matrix(snapshot: Dictionary) -> Array:
	return snapshot.camera.transform if snapshot.has("camera") else snapshot.camera_transform
func finish() -> void:
	print("LABORATORY_HOST_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
