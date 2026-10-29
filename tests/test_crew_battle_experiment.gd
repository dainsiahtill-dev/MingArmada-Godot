extends SceneTree
var assertions := 0
var failures := 0
func check(value: bool, reason: String) -> void:
	assertions += 1
	if not value: failures += 1; printerr("FAIL crew battle experiment: ",reason)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var demo = load("res://game/research/demos/crew_role_experiment.gd").new()
	check(demo.configure({"mode":"battle","paused":true,"pressure":"calm"}).ok,"same topic selects real battle mode")
	if failures: demo.free(); finish(); return
	check(demo.get_child_count() == 0,"battle pre-tree configure stays isolated")
	root.add_child(demo)
	for i in range(3): await process_frame
	var state: Dictionary = demo.inspection_snapshot()
	check(state.ready and state.fixed_step == 1.0/60.0,"battle view ready with correct native clock")
	check(state.parameters.mode == "battle" and state.native.ships.size() == 2,"registered topic exposes actual battle")
	demo.advance(1.0)
	check(demo.inspection_snapshot().tick == 0,"paused view cannot advance battle")
	demo.set_paused(false); demo.advance(1.0/120.0)
	check(demo.inspection_snapshot().tick == 0,"half fixed step accumulates")
	demo.advance(1.0/120.0)
	check(demo.inspection_snapshot().tick == 1,"two halves advance exactly one native step")
	demo.set_paused(true)
	var before: Dictionary = demo.inspection_snapshot()
	check(not demo.configure({"mode":"missing"}).ok and demo.inspection_snapshot() == before,"bad mode keeps running view")
	check(demo.reset_experiment({"mode":"workshop"}).ok,"can return to workshop")
	check(demo.inspection_snapshot().fixed_step == 1.0/32.0 and demo.inspection_snapshot().state.workers.size() == 12,"workshop retains previous cohort and clock")
	check(demo.reset_experiment({"mode":"battle","roster":"elite","pressure":"calm"}).ok,"can reopen with paid elite roster")
	check(demo.inspection_snapshot().crew.workers.size() == 6 and demo.inspection_snapshot().contract.total_committed == 144,"no free specialists through mode switching")
	demo.dispose()
	check(demo.get_child_count() == 0 and demo.inspection_snapshot().disposed,"both world and overlay released")
	demo.free(); await process_frame
	var lab = load("res://game/research/laboratory.gd").new()
	root.add_child(lab); await process_frame
	check(lab.select_topic("crew-role-effects") and lab.start_demo({"paused":true}).ok,"laboratory starts existing workshop")
	var direct: Dictionary = lab.start_demo({"mode":"battle","paused":true,"pressure":"calm"})
	check(direct.ok,"start mode override replaces incompatible cached workshop options")
	if not direct.ok: lab.free(); finish(); return
	lab._change_parameter("mode","workshop")
	lab._change_parameter("mode","battle")
	for i in range(3): await process_frame
	check(lab.inspection_snapshot().demo.fixed_step == 1.0/60.0,"host switched native clock")
	check(lab.find_child("Param_roster",true,false) != null and lab.find_child("Param_preset",true,false) == null,"mode switch rebinds actual parameter controls")
	var sea: Node3D = lab._demo.find_child("CrewBattleProductionSea",true,false)
	var ocean: MeshInstance3D = sea.world.get_ocean()
	check(ocean._last_camera_transform == sea.camera.global_transform and ocean._last_viewport_size == sea.get_viewport().get_visible_rect().size,"paused initial sea projection matches final host camera and viewport")
	var authoritative: Dictionary = lab.inspection_snapshot().demo.state
	root.size = Vector2i(960,640)
	root.content_scale_size = Vector2i(960,640)
	for i in range(4): await process_frame
	check(ocean._last_camera_transform == sea.camera.global_transform and ocean._last_viewport_size == sea.get_viewport().get_visible_rect().size,"paused resize refreshes sea projection")
	check(lab.inspection_snapshot().demo.state == authoritative,"projection resize never advances battle or contract")
	check(lab.step_demo().ok and lab.inspection_snapshot().demo.tick == 1,"host advances battle one native step")
	lab._change_parameter("mode","workshop")
	check(lab.find_child("Param_preset",true,false) != null and lab.find_child("Param_roster",true,false) == null,"return restores workshop controls")
	lab.free(); await process_frame
	finish()
func finish() -> void:
	print("CREW_BATTLE_EXPERIMENT_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
