extends SceneTree
## Isolated real Encounter, production sea, and official terminal presentation tail.
const DEMO_PATH := "res://game/research/demos/naval_combat_atmosphere_experiment.gd"
const STEP := 1.0 / 60.0
var assertions := 0
var failures := 0

func check(ok: bool, reason: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		printerr("FAIL LAB COMBAT ATMOSPHERE: ", reason)

func _initialize() -> void: run.call_deferred()

func run() -> void:
	check(FileAccess.file_exists(DEMO_PATH), "isolated naval combat atmosphere demo exists")
	if not FileAccess.file_exists(DEMO_PATH): finish(); return
	var script: Script = load(DEMO_PATH)
	if script == null: check(false, "demo loads"); finish(); return
	var demo: Node3D = script.new()
	var configured: Dictionary = demo.configure({"paused": true})
	check(configured.get("ok", false) and demo.get_child_count() == 0, "pre-tree configure owns no render nodes")
	var viewport:=SubViewport.new();viewport.size=Vector2i(1,1);root.add_child(viewport)
	viewport.add_child(demo)
	viewport.size=Vector2i(1100,720)
	for _i in 2: await process_frame
	check(demo.get("_strip").size.y<=90.0,"tiny initial viewport cannot expand HUD over the battle")
	var initial: Dictionary = demo.inspection_snapshot()
	check(initial.ready and initial.fixed_step == STEP and initial.tick == 0, "real sea is ready at zero accepted native steps")
	check(initial.native.ships.size() == 2 and initial.native.ships[0].hull == 42.0 and initial.native.ships[1].hull == 100.0, "fixture uses requested asymmetric real hull authority")
	check(initial.native.ships[0].visual.position.z == 0.0 and initial.native.ships[1].visual.position.z == 55.0, "two real ships begin fifty-five metres apart")
	demo.advance(0.25)
	demo.set_camera_mode("near")
	check(demo.inspection_snapshot().native == initial.native and demo.inspection_snapshot().tick == 0, "paused camera changes cannot advance native encounter")
	demo.set_camera_mode("battle")
	demo.set_paused(false)
	demo.advance(STEP * 0.5)
	check(demo.inspection_snapshot().tick == 0, "half fixed step only accumulates")
	demo.advance(STEP * 0.5)
	check(demo.inspection_snapshot().tick == 1, "two halves advance exactly one accepted native tick")
	for _i in 14: demo.advance(STEP)
	var candidate_native: Dictionary = demo.inspection_snapshot().native
	check(demo.inspection_snapshot().event_counts.fire > 0, "automatic cannon command produces actual native fire")
	check(demo.set_parameter("enabled", false).get("reset_required", false), "baseline factor requests a clean identical-authority reset")
	check(demo.reset_experiment({"enabled": false, "paused": false}).get("ok", false), "disabled baseline resets through normal lifecycle")
	for _i in 15: demo.advance(STEP)
	var baseline: Dictionary = demo.inspection_snapshot()
	check(baseline.native == candidate_native, "enabling atmosphere does not change native ships projectiles wind or clock")
	check(baseline.atmosphere.particles.is_empty() and baseline.atmosphere.draw_calls == 0, "baseline has no candidate particles or draws")
	check(demo.reset_experiment({"enabled": true, "paused": false}).get("ok", false), "candidate replay rebuilds a clean native battle")
	for _i in 2: await process_frame
	check(demo.get("_strip").size.y<=90.0,"candidate reset keeps bounded visible telemetry")
	for _i in 15: demo.advance(STEP)
	check(demo.inspection_snapshot().native == candidate_native, "same seed reset reproduces exact native state")
	var terminal: Dictionary = {}
	var saw_wreck_flame := false
	for _i in 240:
		demo.advance(0.25)
		var state: Dictionary = demo.inspection_snapshot()
		if state.event_counts.get("destruction-explosion", 0) > 0 and state.atmosphere.active_flames > 0: saw_wreck_flame = true
		if state.native.status in ["victory", "defeat"]:
			if terminal.is_empty(): terminal = state.native.duplicate(true)
			check(state.native == terminal, "terminal presentation tail never changes frozen native authority")
			if float(state.tail.elapsed) >= 9.5: break
	var ended: Dictionary = demo.inspection_snapshot()
	check(not terminal.is_empty(), "real encounter reaches an actual terminal result within the fixture budget")
	check(ended.event_counts.hit > 0 and ended.event_counts.sink > 0, "real ballistics produce hit and sink before wreck presentation")
	check(ended.event_counts.get("destruction-explosion", 0) > 0 and saw_wreck_flame, "actual ShipDamage destruction event drives visible wreck flame during official tail")
	check(float(ended.visual_time) > float(ended.native.time) and float(ended.tail.elapsed) >= 9.5, "visual time explicitly advances beyond frozen native time")
	check(ended.atmosphere.particles.is_empty(), "finite atmosphere ends within ten-second official tail")
	demo.set_paused(true)
	var stopped: Dictionary = demo.inspection_snapshot()
	demo.advance(0.25)
	check(demo.inspection_snapshot() == stopped, "pause freezes tail and candidate state exactly")
	var native_before: Dictionary = stopped.native.duplicate(true)
	check(not demo.configure({"wind": "invalid"}).get("ok", false) and demo.inspection_snapshot().native == native_before, "invalid parameter cannot destroy a valid running experiment")
	demo.dispose()
	check(demo.get_child_count() == 0 and demo.inspection_snapshot().disposed, "dispose frees actual sea and candidate render resources")
	demo.free()
	viewport.free()
	await process_frame
	finish()

func finish() -> void:
	print("LABORATORY_COMBAT_ATMOSPHERE_TESTS assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures else 0)
