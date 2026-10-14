extends SceneTree
var assertions := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL voyage flow lab: ", message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var path := "res://game/research/demos/voyage_flow_experiment.gd"
	check(ResourceLoader.exists(path), "independent voyage flow demo exists")
	if failures: finish(); return
	var script = load(path)
	var demo = script.new()
	check(not demo.configure({"preset": "invented"}).ok, "unknown fixture refused")
	check(demo.configure({}).ok, "pre-tree configuration accepted")
	check(demo.get_child_count() == 0, "pre-tree has no owners")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 640)
	viewport.own_world_3d = true
	root.add_child(viewport)
	viewport.add_child(demo)
	var initial: Dictionary = demo.inspection_snapshot()
	check(initial.ready and initial.time == 0 and initial.tick == 0, "fresh isolated projection ready")
	check(not demo.is_processing() and not demo.is_physics_processing(), "host alone advances")
	demo.advance(1.0 / 64.0)
	check(demo.inspection_snapshot().tick == 0, "substep waits")
	demo.advance(1.0 / 64.0)
	check(demo.inspection_snapshot().tick == 1, "one accepted fixed step")
	demo.set_paused(true)
	var paused: Dictionary = demo.inspection_snapshot()
	demo.advance(5)
	check(demo.inspection_snapshot().state == paused.state, "paused state fixed")
	check(demo.set_parameter("candidate_enabled", false).ok, "baseline switch")
	check(demo.inspection_snapshot().state == paused.state and demo.inspection_snapshot().text != paused.text, "baseline changes presentation only")
	check(demo.set_parameter("preset", "partial").reset_required, "fixture change asks host for reset")
	check(demo.reset_experiment({"preset": "partial", "candidate_enabled": true}).ok, "partial-loss fixture resets")
	var partial: Dictionary = demo.inspection_snapshot()
	check(partial.flow.settlements[0].delivered == 20 and partial.flow.settlements[0].lost == 20, "partial fixture demonstrates preserved loss")
	demo.reset_experiment()
	check(demo.inspection_snapshot().state == partial.state and demo.inspection_snapshot().flow == partial.flow, "identical reset deterministic")
	demo.dispose()
	check(not demo.inspection_snapshot().ready and demo.get_child_count() == 0, "dispose frees all local presentation owners")
	viewport.free()
	finish()
func finish() -> void:
	print("LABORATORY_VOYAGE_FLOW_PASS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
