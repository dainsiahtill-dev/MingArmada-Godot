extends SceneTree
var assertions := 0
var failures := 0
func check(ok: bool, reason: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ",reason)
func _initialize() -> void: _run.call_deferred()
func settle() -> void:
	for _frame in range(5): await process_frame
func _run() -> void:
	var host := SubViewport.new(); host.size = Vector2i(1280,720); root.add_child(host)
	var lab: Control = load("res://game/research/laboratory.gd").new(); host.add_child(lab)
	await settle()
	check(lab.select_topic("architecture-convergence-2026-10-21"),"architecture topic loads")
	check(lab.start_demo({"paused":true}).ok,"real architecture experiment starts paused")
	await settle()
	var view: SubViewportContainer = lab.find_child("ExperimentView",true,false)
	var viewport: SubViewport = lab.find_child("ExperimentViewport",true,false)
	check(view.size.y>=200,"720px window reserves a readable experiment viewport")
	for label: Node in viewport.find_children("*","Label",true,false):
		check(label.get_global_rect().end.y<=viewport.size.y,"experiment diagnostic text stays inside its own viewport")
	var scroll := lab.find_child("ExperimentScroll",true,false) as ScrollContainer
	check(scroll!=null,"small windows retain access to all experiment controls via scrolling")
	if scroll!=null:
		scroll.scroll_vertical=10000; await settle()
		var stats: Label = lab.find_child("ExperimentTelemetry",true,false)
		check(scroll.get_global_rect().encloses(stats.get_global_rect()),"telemetry remains fully reachable at the bottom")
		scroll.scroll_vertical=0; await settle()
		var previous_zoom: float = lab.inspection_snapshot().demo.camera_controls.zoom
		var wheel := InputEventMouseButton.new(); wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN; wheel.pressed=true; wheel.position=view.get_global_rect().get_center()
		host.push_input(wheel); await settle()
		check(lab.inspection_snapshot().demo.camera_controls.zoom>previous_zoom,"wheel input still reaches the experiment camera")
		check(scroll.scroll_vertical==0,"wheel over the experiment does not also scroll its controls")
	host.size=Vector2i(1600,900); await settle()
	check(view.size.y>=300,"large window expands the world viewport")
	check(lab.inspection_snapshot().demo.get("tick",-1)==0,"layout changes do not advance the paused experiment")
	lab.dispose(); host.free(); await process_frame
	print("LABORATORY_VIEWPORT_LAYOUT_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
