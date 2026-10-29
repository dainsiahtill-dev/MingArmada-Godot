extends SceneTree
var assertions := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL broadside lab: ",message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var path := "res://game/research/demos/broadside_receipt_experiment.gd"
	check(ResourceLoader.exists(path),"independent experiment exists")
	if failures: finish(); return
	var script = load(path)
	check(script != null and script.can_instantiate(),"experiment script parses")
	if failures: finish(); return
	var demo = script.new()
	check(not demo.configure({"candidate_enabled":"yes"}).ok,"invalid switch rejected")
	check(demo.configure({}).ok,"detached configuration accepted")
	check(demo.get_child_count() == 0,"detached experiment owns no nodes")
	var viewport := SubViewport.new(); viewport.size = Vector2i(960,640); viewport.own_world_3d = true
	root.add_child(viewport); viewport.add_child(demo)
	check(demo.inspection_snapshot().ready,"host-created demo ready")
	check(not demo.is_processing() and not demo.is_physics_processing(),"host alone advances clock")
	for i in 20: demo.advance(1.0/32.0)
	var mixed: Dictionary = demo.inspection_snapshot()
	check(mixed.tick == 20 and mixed.fixture_events == 6,"four-fire fixture reaches the mixed hit/splash event")
	check(mixed.receipt.text == "右舷命中 · 敌船倭船","candidate retains confirmed hit")
	check(mixed.naive_text == "右舷炮弹未命中","naive overwrite failure fixture preserved")
	check(demo.set_parameter("candidate_enabled",false).ok,"baseline switch accepted")
	var baseline: Dictionary = demo.inspection_snapshot()
	check(baseline.visible_receipt == "" and baseline.receipt == mixed.receipt and baseline.tick == mixed.tick,"baseline changes only visibility")
	demo.set_paused(true); demo.advance(4.0)
	check(demo.inspection_snapshot().tick == mixed.tick,"pause holds clock and events")
	check(demo.reset_experiment({"candidate_enabled":true,"paused":false}).ok,"fixture reset accepted")
	for i in 20: demo.advance(1.0/32.0)
	var replay: Dictionary = demo.inspection_snapshot()
	check(replay.receipt == mixed.receipt and replay.naive_text == mixed.naive_text,"replay deterministic")
	demo.dispose()
	check(not demo.inspection_snapshot().ready and demo.get_child_count() == 0,"dispose releases local UI")
	viewport.free(); finish()
func finish() -> void:
	print("LABORATORY_BROADSIDE_RECEIPT assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
