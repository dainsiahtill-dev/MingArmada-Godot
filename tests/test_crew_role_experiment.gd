extends SceneTree
var assertions := 0
var failures := 0
func check(value: bool, reason: String) -> void:
	assertions += 1
	if not value: failures += 1; printerr("FAIL crew experiment: ",reason)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(1280,720)
	var path := "res://game/research/demos/crew_role_experiment.gd"
	check(ResourceLoader.exists(path),"independent crew experiment exists")
	if failures: finish(); return
	var demo = load(path).new()
	check(demo.configure({"paused":false}).ok and demo.get_child_count() == 0,"configuration before tree creates no nodes")
	root.add_child(demo)
	check(demo.inspection_snapshot().ready,"ready on entering tree")
	var panel: PanelContainer = demo.find_child("CrewRolePanel",true,false)
	var style: StyleBox = panel.get_theme_stylebox("panel")
	if style.has_method("_get_draw_rect"):
		var painted: Rect2 = style.call("_get_draw_rect",Rect2(Vector2.ZERO,panel.size))
		painted.position += panel.position
		check(root.get_visible_rect().encloses(painted),"generated frame and shadow fit viewport")
	var initial: Dictionary = demo.inspection_snapshot()
	check(initial.fixed_step == 1.0/32.0,"host sees true fixed step")
	check(not demo.is_processing() and not demo.is_physics_processing(),"no second clock")
	await process_frame
	check(demo.inspection_snapshot().tick == 0,"render frames cannot advance work")
	demo.advance(1.0/64.0)
	check(demo.inspection_snapshot().tick == 0,"half step accumulates")
	demo.advance(1.0/64.0)
	check(demo.inspection_snapshot().tick == 1,"two half steps advance once")
	demo.set_paused(true)
	var paused: Dictionary = demo.inspection_snapshot()
	demo.advance(10.0)
	check(demo.inspection_snapshot() == paused,"pause cannot spend resources or accrue catchup")
	check(not demo.set_parameter("unknown",1).ok and demo.inspection_snapshot() == paused,"invalid parameter atomic")
	check(not demo.configure({"specialists":1}).ok and demo.inspection_snapshot() == paused,"invalid reconfigure preserves live experiment")
	check(demo.set_parameter("repair_detachment",true).ok,"live detachment")
	check(demo.inspection_snapshot().state.gun_efficiency == 0.75,"visible guns reflect moved people")
	check(demo.reset_experiment({"preset":"balanced","paused":false}).ok,"reset accepted")
	check(demo.inspection_snapshot().state == initial.state,"full reset matches initial rules")
	demo.advance(NAN); demo.advance(-1.0); demo.advance(INF)
	check(demo.inspection_snapshot().tick == 0,"invalid deltas do not advance")
	demo.advance(2.0)
	check(demo.inspection_snapshot().tick == 8 and is_equal_approx(demo.inspection_snapshot().dropped_seconds,1.75),"catchup bounded and dropped time visible")
	demo.dispose()
	check(demo.get_child_count() == 0 and demo.inspection_snapshot().disposed,"dispose releases experiment nodes")
	demo.free()
	var lab = load("res://game/research/laboratory.gd").new()
	root.add_child(lab); await process_frame
	check(lab.select_topic("crew-role-effects"),"actual laboratory topic selectable")
	check(lab.start_demo({"paused":true,"preset":"emergency"}).ok,"host starts emergency fixture")
	for i in range(4): await process_frame
	var host: Dictionary = lab.inspection_snapshot()
	check(host.presentation == "dashboard" and not lab.find_child("TopicAbstract",true,false).visible,"dashboard removes duplicate paper summary")
	check(lab.find_child("DashboardClock",true,false).is_visible_in_tree(),"compact clock remains visible")
	check(lab.find_child("ExperimentViewport",true,false).transparent_bg,"painted frame floats without gray viewport rectangle")
	var scroll: ScrollContainer = lab._demo.find_child("CrewRoleScroll",true,false)
	for id: String in ["CrewHull","CrewGuns","CrewFood","CrewMorale"]:
		var metric: Label = lab._demo.find_child(id,true,false)
		check(scroll.get_global_rect().encloses(metric.get_global_rect()),"wide dashboard displays metric: "+id)
	check(host.demo.state.counts.gunner == 2 and host.parameters.repair_detachment,"host reads normalized emergency parameters")
	var toggle: CheckBox = lab.find_child("Param_repair_detachment",true,false)
	check(toggle != null and toggle.button_pressed,"actual UI matches normalized assignment")
	check(lab.step_demo().ok and lab.inspection_snapshot().demo.tick == 1,"host single step advances once")
	check(lab.inspection_snapshot().demo.paused,"single step retains paused mode")
	lab._change_parameter("repair_detachment",false)
	check(lab.inspection_snapshot().demo.state.counts.gunner == 4,"can return gunners in emergency fixture")
	lab.select_topic("hull-contact")
	lab.select_topic("crew-role-effects")
	check(lab.start_demo({"paused":true}).ok,"reopen cached emergency fixture")
	check(not lab.inspection_snapshot().parameters.repair_detachment and lab.inspection_snapshot().demo.state.counts.gunner == 4,"reopen preserves explicit return-to-guns choice")
	check(lab.select_topic("hull-contact") and lab.inspection_snapshot().demo.is_empty(),"topic switch releases crew experiment")
	check(lab.inspection_snapshot().presentation == "scene" and lab.find_child("TopicAbstract",true,false).visible and lab.find_child("ResearchPrinciple",true,false).visible,"paper layout restored on leaving dashboard")
	check(not lab.find_child("ExperimentViewport",true,false).transparent_bg and not lab.find_child("DashboardClock",true,false).visible,"normal 3D presentation restored")
	lab.free(); await process_frame
	finish()
func finish() -> void:
	print("CREW_ROLE_EXPERIMENT_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
