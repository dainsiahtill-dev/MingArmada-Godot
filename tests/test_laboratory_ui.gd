extends SceneTree
var assertions := 0
var failures := 0
func check(ok: bool, reason: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ",reason)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	check(FileAccess.file_exists("res://game/research/laboratory.gd"),"unified laboratory scene exists")
	if failures: _finish(); return
	var lab: Control = load("res://game/research/laboratory.gd").new()
	root.add_child(lab); await process_frame
	check(lab.startup_receipt.get("ok",false),"laboratory startup succeeds")
	check(lab.inspection_snapshot().topic_count == 5,"five papers in one entry")
	check(lab.select_topic("hull-contact"),"hull paper selectable")
	check(lab.find_child("ResearchPaper",true,false).get_parsed_text().contains("问题与假设"),"paper rendered inside game")
	check(not lab.select_topic("missing"),"missing selection leaves current subject intact")
	check(lab.inspection_snapshot().selected_topic == "hull-contact","selection retained after invalid subject")
	check(lab.select_topic("shadow-edges"),"shadow paper selectable")
	check(not lab.start_demo().ok,"unregistered demo cannot launch")
	check(lab.inspection_snapshot().demo.is_empty(),"paper-only topic allocates no experiment")
	lab.select_topic("hull-contact")
	var started: Dictionary = lab.start_demo({"paused":true,"camera_mode":"front","carrier_extent":384.0})
	check(started.ok,"independent experiment starts")
	if started.ok:
		var paused: Dictionary = lab.inspection_snapshot().demo
		check(lab.find_child("ExperimentCamera",true,false).selected == 1,"restored camera agrees with visible selector")
		check(lab.find_child("ExperimentCarrier",true,false).selected == 1,"restored carrier agrees with visible selector")
		lab._process(0.25)
		check(lab.inspection_snapshot().demo.tick == paused.tick,"paused experiment keeps time")
		check(lab.inspection_snapshot().demo.contact_enabled,"local contact comparison initially enabled")
		lab.find_child("ContactEnabled",true,false).set_pressed(false)
		check(not lab.inspection_snapshot().demo.contact_enabled,"comparison toggle controls demo only")
		lab.select_topic("ocean-surface")
		check(lab.inspection_snapshot().demo.is_empty(),"changing paper disposes experiment")
		await process_frame
		check(lab.find_child("ExperimentViewport",true,false).get_child_count() == 0,"no hidden experiment left running")
	var returns: Array = []
	lab.main_menu_requested.connect(func(): returns.append(true))
	lab.find_child("ReturnToMenu",true,false).pressed.emit()
	check(returns.size() == 1,"return emits existing owner lifecycle signal")
	lab.dispose(); lab.dispose()
	check(lab.inspection_snapshot().disposed,"idempotent disposal")
	check(not lab.start_demo().ok,"disposed laboratory cannot restart a world")
	lab.free(); await process_frame
	_finish()
func _finish() -> void:
	print("LABORATORY_UI_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
