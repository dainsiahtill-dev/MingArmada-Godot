extends SceneTree
## The existing fire topic's controlled native-candidate labour comparison.
const TRIAL_PATH := "res://game/research/demos/ship_fire_work_trial.gd"
const DEMO_PATH := "res://game/research/demos/ship_fire_control_experiment.gd"
const CrewWork = preload("res://modules/naval_simulation/combat/crew_work.gd")
var assertions := 0
var failures := 0
var trial_script: Script

func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> bool:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL LAB CREW WORK: ", label)
	return value
func near(actual: float, expected: float, label: String) -> void:
	check(absf(actual - expected) <= 0.00000001, label + " actual=" + str(actual))
func finish() -> void:
	print("LABORATORY_CREW_WORK_TESTS assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures else 0)
func step(trial: RefCounted, count: int) -> void:
	for _i in count:
		if not check(trial.advance_fixed().get("ok", false), "candidate accepts exactly one fixed labour interval"):
			return
func worker_row(state: Dictionary) -> Dictionary:
	for item: Dictionary in state.get("receipt", {}).get("ships", []):
		if item.shipId == "candidate": return item
	return {}

func run() -> void:
	# Missing helper is an intentional, observable RED rather than a preload error.
	if not check(ResourceLoader.exists(TRIAL_PATH), "SHIP_FIRE_WORK_TRIAL_MISSING: existing topic has native labour comparison helper"):
		finish(); return
	trial_script = load(TRIAL_PATH)
	if not check(trial_script != null, "isolated native labour helper loads"):
		finish(); return
	_test_launcher()
	_test_transfer()
	_test_return()
	_test_casualty()
	await _test_existing_demo()
	finish()

func _test_launcher() -> void:
	var trial: RefCounted = trial_script.new()
	if not check(trial.configure("launcher").get("ok", false), "launcher case configures the real research native candidate"):
		return
	var initial: Dictionary = trial.snapshot()
	check(initial.case == "launcher" and initial.tick == 0 and initial.time == 0.0 and initial.receipt == {}, "configuration creates no invented past receipt")
	check(initial.worker.id == "candidate" and initial.worker.crew == 100 and initial.worker.maxCrew == 100 and initial.worker.availableCrew == 96, "same controlled worker starts its actual four-person launch operation")
	check(initial.native.ships.size() == 2 and initial.native.projectiles.size() > 0, "launcher uses actual target and committed native projectile")
	check(initial.events.any(func(event: Dictionary): return event.get("type") == "fire-payload-launched" and event.get("shipId") == "candidate"), "launch exposes the actual native event")
	step(trial, 120)
	var state: Dictionary = trial.snapshot()
	var accepted: Dictionary = worker_row(state)
	check(state.tick == 120 and state.native.tick == 120 and CrewWork.valid(state.receipt) and state.receipt.tick == 120, "inspection binds real candidate state and receipt to accepted tick120")
	check(accepted.launcherCrew == 4 and accepted.availableCrew == 96 and state.worker.availableCrew == 100, "tick120 receipt retains operators while native endpoint releases them")
	check(state.completed_windows.size() == 2 and state.window.ticks == 0, "two exact sixty-tick windows complete without carry drift")
	near(float(state.comparison.integratedPersonSeconds), 96.0, "same worker's second launcher second integrates96 person-seconds")
	near(float(state.comparison.endpointPersonSeconds), 100.0, "same worker's endpoint estimate is100 person-seconds")
	near(float(state.comparison.errorPersonSeconds), 4.0, "displayed launcher endpoint error is positive four person-seconds")
	var replay: Dictionary = state.duplicate(true)
	check(trial.reset().get("ok", false) and trial.snapshot().tick == 0, "reset returns same controlled case to tick zero")
	step(trial, 120)
	check(trial.snapshot() == replay, "same seed, native inputs and120 accepted steps reproduce complete helper state")
	step(trial, 1)
	check(worker_row(trial.snapshot()).launcherCrew == 0 and worker_row(trial.snapshot()).availableCrew == 100, "interval121 actually returns operators to available labour")
	var detached: Dictionary = trial.snapshot(); detached.worker.crew = 1
	check(trial.snapshot().worker.crew == 100, "inspection deep-copies native worker state")
	var before: Dictionary = trial.snapshot()
	check(not trial.configure("invented").get("ok", true) and trial.snapshot() == before, "unknown controlled case preserves current valid trial")

func _test_transfer() -> void:
	var trial: RefCounted = trial_script.new()
	if not check(trial.configure("transfer").get("ok", false), "hot transfer case configures"):
		return
	var initial: Dictionary = trial.snapshot()
	check(initial.worker.fireControl.heat == 28.0 and initial.worker.fireControl.supplies == 64 and initial.worker.fireControl.pendingFirefighters == 4 and initial.worker.fireControl.transferTicks == 120, "transfer begins with declared hot stock and actual time-zero assignment")
	step(trial, 120)
	var arrival: Dictionary = trial.snapshot()
	check(arrival.worker.fireControl.transferTicks == 0 and worker_row(arrival).fireDutyCrew == 4 and worker_row(arrival).availableCrew == 96, "arrival120 remains occupied in real receipt")
	check(arrival.worker.fireControl.supplies == 64 and arrival.worker.fireControl.workCarry == 0.0, "120 complete travel intervals perform no suppression work")
	near(float(arrival.comparison.integratedPersonSeconds), 96.0, "transfer second integrates96 available person-seconds")
	near(float(arrival.comparison.errorPersonSeconds), 0.0, "endpoint agrees only while reservations have not changed")
	step(trial, 1)
	near(float(trial.snapshot().worker.fireControl.workCarry), 4.0 / 60.0, "first native suppression work occurs on interval121")

func _test_return() -> void:
	var trial: RefCounted = trial_script.new()
	if not check(trial.configure("return").get("ok", false), "controlled active-team quench case configures"):
		return
	var initial: Dictionary = trial.snapshot()
	check(initial.tick == 0 and initial.worker.fireControl.assignedFirefighters == 4 and initial.worker.fireControl.heat == 0.01 and initial.worker.fireControl.fuelSeconds == 1.0, "return fixture declares initial active team without invented prior work")
	step(trial, 1)
	var quenched: Dictionary = trial.snapshot()
	check(quenched.worker.fireControl.heat == 0.0 and quenched.worker.fireControl.transferTicks == 120 and worker_row(quenched).fireDutyCrew == 4, "real first interval quenches and starts full120-interval return")
	step(trial, 119)
	check(trial.snapshot().worker.fireControl.transferTicks == 1 and worker_row(trial.snapshot()).fireDutyCrew == 4, "quench plus119 return intervals still occupies team")
	step(trial, 1)
	var released: Dictionary = trial.snapshot()
	check(released.tick == 121 and released.worker.fireControl.transferTicks == 0 and released.worker.availableCrew == 100 and worker_row(released).fireDutyCrew == 4, "last real return interval retains labour while its endpoint releases team")
	check(released.window.ticks == 1, "return boundary appears in the next partial fixed window")
	check(released.comparison.firstTick == 62 and released.comparison.lastTick == 121 and released.comparison.ticks == 60, "rolling read-only comparison is distinct from partial fixed carry")
	near(float(released.comparison.integratedPersonSeconds), 96.0, "rolling return window62..121 records sixty occupied intervals")
	near(float(released.comparison.endpointPersonSeconds), 100.0, "rolling endpoint uses the same accepted one-second window")
	near(float(released.comparison.errorPersonSeconds), 4.0, "return endpoint overstates completed labour by four person-seconds")
	step(trial, 1)
	check(worker_row(trial.snapshot()).fireDutyCrew == 0 and worker_row(trial.snapshot()).availableCrew == 100, "returned crew works only from the following interval")

func _test_casualty() -> void:
	var trial: RefCounted = trial_script.new()
	if not check(trial.configure("casualty").get("ok", false), "casualty case configures actual enemy grape fire"):
		return
	var hit := false
	for _i in 600:
		step(trial, 1)
		var state: Dictionary = trial.snapshot()
		var accepted: Dictionary = worker_row(state)
		if not accepted.is_empty() and accepted.totalAbleAtEnd < accepted.totalAbleAtStart:
			hit = true
			check(state.worker.crew == accepted.totalAbleAtEnd and accepted.availableCrew == accepted.totalAbleAtStart, "actual right-boundary casualties cannot debit preceding accepted labour")
			check(state.events.any(func(event: Dictionary): return event.get("type") == "hit" and event.get("targetId") == "candidate" and float(event.get("damage", {}).get("crew", 0.0)) > 0.0), "casualty is accompanied by real hostile projectile-hit event")
			break
	check(hit, "controlled grape trajectory produces an observed real casualty within600 accepted intervals")

func _test_existing_demo() -> void:
	var demo_script: Script = load(DEMO_PATH)
	var demo: Node3D = demo_script.new()
	check(demo.get_default_options().get("work_case") == "off", "original controlled fire comparison remains default")
	check(demo.configure({"work_case":"launcher","paused":false}).get("ok", false) and demo.get_child_count() == 0, "work case prepares without renderer before tree entry")
	var viewport := SubViewport.new(); viewport.size = Vector2i(1100,720); viewport.own_world_3d = true
	root.add_child(viewport); viewport.add_child(demo)
	for _i in 2: await process_frame
	if not check(demo.inspection_snapshot().get("ready", false), "existing registered fire Demo presents the controlled work case"):
		demo.dispose(); demo.free(); viewport.free(); return
	for _i in 120: demo.advance(1.0 / 60.0)
	var state: Dictionary = demo.inspection_snapshot()
	check(state.topic == "ship-fire-control" and state.parameters.work_case == "launcher" and state.has("work_trial"), "work trial stays inside the existing topic and inspection")
	check(state.visual.ships == state.work_trial.native.ships and state.work_trial.tick == state.tick, "drawn ships expose actual same-candidate native health, positions and population")
	near(float(state.work_trial.comparison.errorPersonSeconds), 4.0, "existing Demo exposes same-worker native launcher discrepancy")
	demo.set_paused(true)
	var paused: Dictionary = demo.inspection_snapshot()
	demo.advance(0.25)
	check(demo.inspection_snapshot() == paused, "pause admits no extra native receipts or person-ticks")
	demo.set_camera_mode("near")
	check(demo.inspection_snapshot().work_trial == paused.work_trial, "camera-only observation leaves labour authority unchanged")
	check(demo.reset_experiment({"paused":true}).get("ok", false) and demo.inspection_snapshot().work_trial.tick == 0, "existing host reset clears accepted labour carry")
	demo.dispose()
	check(demo.get_child_count() == 0 and demo.inspection_snapshot().disposed, "existing Demo disposal releases work-case presentation")
	demo.free(); viewport.free()
	await process_frame
