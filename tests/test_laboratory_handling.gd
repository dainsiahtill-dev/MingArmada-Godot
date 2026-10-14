extends SceneTree
var assertions := 0
var failures := 0
func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL handling demo: ",detail)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var path := "res://game/research/demos/sailing_handling_experiment.gd"
	if not ResourceLoader.exists(path):
		check(false,"isolated production handling experiment exists")
		finish(); return
	var demo: Node3D = load(path).new()
	check(demo.configure({"scenario":"pause-resume"}).ok,"configure before tree attachment")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960,640); viewport.own_world_3d = true
	root.add_child(viewport); viewport.add_child(demo)
	check(demo.inspection_snapshot().ready,"configured experiment owns real runtime and ship")
	for tick in 420: demo.advance(1.0/60.0)
	var replay: Dictionary = demo.inspection_snapshot()
	check(replay.tick == 420 and absf(replay.time-6.0) < 1e-8,"scheduled pause freezes one second of native time")
	check(replay.telemetry.speed_mps >= 1.5,"production assisted propulsion survives scheduled pause and resume")
	demo.set_paused(true)
	var frozen: Dictionary = demo.inspection_snapshot()
	demo.advance(1.0)
	demo.orbit_camera(0.2,0.1); demo.zoom_camera(-0.12)
	var inspected: Dictionary = demo.inspection_snapshot()
	check(inspected.native == frozen.native and inspected.tick == frozen.tick,"paused camera never advances motion or timeline")
	check(inspected.camera != frozen.camera,"paused orbit and wheel alter the actual production camera")
	check(not demo.configure({"kind":"invalid"}).ok and demo.inspection_snapshot().native == frozen.native,"invalid config preserves the running owner")
	var camera_targets: Dictionary = demo.get("_camera_rig").status()
	check(demo.reset_experiment({"paused":false}).ok,"same-input reset succeeds")
	var reset_targets: Dictionary = demo.get("_camera_rig").status()
	check(absf(reset_targets.targetYaw-camera_targets.targetYaw) < 1e-8 and absf(reset_targets.targetPitch-camera_targets.targetPitch) < 1e-8 and absf(reset_targets.targetRadius-camera_targets.targetRadius) < 1e-8,"same-condition reset retains the selected camera view")
	for tick in 420: demo.advance(1.0/60.0)
	check(demo.inspection_snapshot().native == replay.native,"reset deterministically reproduces accepted motion")
	var before: Dictionary = demo.inspection_snapshot()
	demo.advance(NAN); demo.advance(-1.0)
	check(demo.inspection_snapshot().native == before.native,"invalid clock cannot mutate native state")
	for scenario: String in ["headwind","turn","reverse","stop"]:
		check(demo.reset_experiment({"scenario":scenario,"paused":false}).ok,"scenario resets: "+scenario)
		for tick in 300: demo.advance(1.0/60.0)
		var state: Dictionary = demo.inspection_snapshot()
		check(state.time > 4.99 and state.native.ships[0].visual.position.x is float,"scenario consumes real native steps: "+scenario)
		if scenario == "stop": check(state.native.ships[0].sailDeployment == 0.0,"stop issues the public furl intent")
	check(demo.set_parameter("kind","heavy").get("reset_required",false),"ship change requires host-owned reset")
	demo.dispose(); demo.dispose()
	check(demo.inspection_snapshot().disposed and demo.get_child_count() == 0 and demo.inspection_snapshot().resources.runtime == 0,"idempotent disposal removes local world and authority")
	demo.free(); viewport.free()
	finish()
func finish() -> void:
	print("LABORATORY_HANDLING_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
