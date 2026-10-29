extends SceneTree
## Controlled ignition candidates only; this test does not assert live combat integration.
const DEMO_PATH := "res://game/research/demos/ship_fire_control_experiment.gd"
const STEP := 1.0 / 60.0
const SCOPE := "controlled ignition candidate; no live ballistic/campaign/production claim"
var assertions := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(value: bool, reason: String) -> bool:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL LAB SHIP FIRE: ", reason)
	return value

func near(actual: float, expected: float, reason: String, tolerance: float = 0.00000001) -> void:
	check(absf(actual - expected) <= tolerance, reason + " actual=" + str(actual))

func finish() -> void:
	print("LABORATORY_SHIP_FIRE assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures else 0)

func advance_ticks(demo: Node3D, ticks: int) -> void:
	for _i in ticks: demo.advance(STEP)

func run() -> void:
	# Removing the demo must report a missing feature, not a preload parser error.
	if not check(FileAccess.file_exists(DEMO_PATH), "independent controlled ship-fire experiment exists"):
		finish(); return
	var script: Script = load(DEMO_PATH)
	if not check(script != null, "controlled ship-fire experiment loads"):
		finish(); return
	var demo: Node3D = script.new()
	check(demo.configure({"paused":true}).get("ok", false) and demo.get_child_count() == 0, "pre-tree configuration creates no renderer or persistent session")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1, 1)
	viewport.own_world_3d = true
	root.add_child(viewport)
	viewport.add_child(demo)
	for _i in 2: await process_frame
	viewport.size = Vector2i(1100, 720)
	for _i in 2: await process_frame
	var initial: Dictionary = demo.inspection_snapshot()
	if not check(initial.get("ready", false), "real Sea, ShipView, Crew and heat-driven presentation are ready"):
		printerr(initial.get("error", "")); demo.dispose(); demo.free(); viewport.free(); finish(); return
	check(initial.scope == SCOPE and initial.topic == "ship-fire-control", "inspection identifies controlled ignition scope")
	check(initial.tick == 0 and initial.time == 0.0 and initial.fixed_step == STEP, "host starts at deterministic zero tick")
	check(initial.parameters.payload == "thorn-ball" and initial.parameters.firefighters == 4 and initial.parameters.supplies == 24 and initial.parameters.moisture == "dry" and initial.parameters.load == "clear", "initial candidate exposes its complete controlled inputs")
	check(initial.resources.storage == 0 and initial.events.is_empty(), "controlled ignition creates no campaign storage or fabricated combat events")
	check(initial.lanes.baseline.fireControl.heat == 28.0 and initial.lanes.candidate.fireControl.heat == 28.0, "both lanes receive identical controlled ignition heat")
	check(initial.lanes.baseline.fireControl.fuelSeconds == 36.0 and initial.lanes.candidate.fireControl.fuelSeconds == 36.0, "both lanes receive identical thorn payload fuel")
	check(initial.lanes.baseline.hull == initial.lanes.candidate.hull and initial.lanes.baseline.crew == initial.lanes.candidate.crew, "both lanes start from equal health and personnel")
	check(initial.lanes.baseline.fireControl.pendingFirefighters == 0 and initial.lanes.candidate.fireControl.pendingFirefighters == 4, "only declared candidate allocation differs")
	var sea: Node3D = demo.get("_sea")
	check(sea.ships.size() == 2 and sea.sailors.size() == 2, "both independent lanes own real production ship and crew actors")
	var left_on_screen: Vector2 = sea.camera.unproject_position(sea.ships.baseline.global_position)
	var right_on_screen: Vector2 = sea.camera.unproject_position(sea.ships.candidate.global_position)
	check(left_on_screen.x < right_on_screen.x, "overview matches declared left unattended and right staffed lanes")
	var strip: Control = demo.get("_strip")
	check(strip is Panel and strip.size.y <= 160.0 and strip.size.x <= 1090.0, "bounded telemetry recovers after one-pixel viewport without covering ships")
	demo.advance(.25)
	demo.set_camera_mode("near")
	var camera_only: Dictionary = demo.inspection_snapshot()
	check(camera_only.tick == 0 and camera_only.lanes == initial.lanes, "paused camera changes do not alter experiment authority")
	demo.set_camera_mode("overview")
	demo.set_paused(false)
	demo.advance(STEP * .5)
	check(demo.inspection_snapshot().tick == 0, "half step only accumulates")
	demo.advance(STEP * .5)
	advance_ticks(demo, 119)
	var transfer: Dictionary = demo.inspection_snapshot()
	check(transfer.tick == 120 and transfer.lanes.candidate.fireControl.transferTicks == 0, "one hundred twenty complete ticks finish transfer")
	check(transfer.lanes.candidate.workSeconds == 0.0 and transfer.lanes.candidate.fireControl.supplies == 24, "two-second transfer performs no suppression and spends no supplies")
	near(transfer.lanes.baseline.fireControl.heat, 32.0, "unattended dry heat follows controlled two-second integral")
	near(transfer.lanes.candidate.hull, 99.52, "experimental hull account applies the heat integral once")
	near(transfer.lanes.candidate.sail, 98.68, "experimental sail account applies its distinct damage rate")
	check(transfer.lanes.baseline.hull == transfer.lanes.candidate.hull, "traveling crew cannot suppress fire early")
	demo.advance(STEP)
	var working: Dictionary = demo.inspection_snapshot()
	near(working.lanes.candidate.workSeconds, 4.0 / 60.0, "first effective tick records four real person-seconds per second")
	check(working.lanes.candidate.fireControl.heat < working.lanes.baseline.fireControl.heat, "working team changes actual fire state")
	check(working.lanes.candidate.crew is int and working.lanes.candidate.fireControl.supplies is int, "experiment personnel and preparation inventory remain integer accounts")
	var replay: Dictionary = working.lanes.duplicate(true)
	check(demo.reset_experiment({"paused":false}).get("ok", false), "same inputs reset normally")
	advance_ticks(demo, 121)
	check(demo.inspection_snapshot().lanes == replay, "same accepted ticks reproduce both independent accounts")
	advance_ticks(demo, 600)
	var extinguished: Dictionary = demo.inspection_snapshot()
	check(extinguished.lanes.candidate.fireControl.heat == 0.0 and extinguished.lanes.baseline.fireControl.heat > 0.0, "prepared four-person team extinguishes this candidate before unattended fuel expires")
	check(extinguished.lanes.candidate.hull < 100.0 and extinguished.lanes.candidate.hull > extinguished.lanes.baseline.hull, "suppression limits experimental damage without healing it")
	check(extinguished.lanes.candidate.suppliesSpent > 0 and extinguished.lanes.candidate.fireControl.supplies + extinguished.lanes.candidate.suppliesSpent == 24, "effective work consumes actual finite preparation inventory")
	var hull_after: float = extinguished.lanes.candidate.hull
	advance_ticks(demo, 180)
	near(demo.inspection_snapshot().lanes.candidate.hull, hull_after, "extinguished fire stops hull damage and never repairs")
	check(demo.reset_experiment({"firefighters":8,"supplies":0,"paused":false}).get("ok", false), "zero-preparation case resets")
	advance_ticks(demo, 300)
	var empty: Dictionary = demo.inspection_snapshot()
	check(empty.lanes.candidate.workSeconds == 0.0 and empty.lanes.candidate.suppliesSpent == 0, "zero preparation cannot provide free suppression")
	check(empty.lanes.candidate.hull == empty.lanes.baseline.hull and empty.lanes.candidate.fireControl.heat == empty.lanes.baseline.fireControl.heat, "unfunded team has no hidden damage advantage")
	check(demo.reset_experiment({"moisture":"wet-deck","load":"powder","payload":"fire-ball","supplies":4,"firefighters":2,"paused":false}).get("ok", false), "wetness, payload, load and finite preparation inputs are accepted together")
	var wet: Dictionary = demo.inspection_snapshot()
	near(wet.lanes.candidate.fireControl.heat, 11.2, "wet-deck input lowers initial heat")
	near(wet.lanes.candidate.fireControl.fuelSeconds, 10.8, "wet-deck ordinary payload has finite reduced fuel")
	check(wet.context.rain01 == 0.0 and wet.context.flammableLoad == 1.0, "wet deck and flammable load are separate controlled inputs")
	check(demo.reset_experiment({"moisture":"rain","paused":false}).get("ok", false), "rain context resets")
	advance_ticks(demo, 60)
	near(demo.inspection_snapshot().lanes.candidate.fireControl.wetness, .1, "rain supplies only the declared experimental wetness context")
	demo.set_paused(true)
	var stopped: Dictionary = demo.inspection_snapshot()
	demo.advance(.25)
	check(demo.inspection_snapshot() == stopped, "pause freezes clock, fire, damage, crew and finite inventory")
	for invalid: Dictionary in [{"firefighters":3},{"supplies":5},{"moisture":"storm"},{"load":"explosive"},{"payload":"solid"},{"seed":true},{"paused":1},{"unknown":true}]:
		check(not demo.configure(invalid).get("ok", true) and demo.inspection_snapshot() == stopped, "invalid options preserve valid experiment: " + str(invalid))
	check(not demo.set_parameter("firefighters", 2).get("reset_required", true), "same work allocation does not request a needless reset")
	check(demo.set_parameter("firefighters", 4).get("reset_required", false), "different work allocation requests an explicit clean reset")
	check(demo.reset_experiment({"firefighters":0,"supplies":64,"moisture":"dry","load":"clear","payload":"thorn-ball","paused":false}).get("ok", false), "zero-person and ample-preparation control resets")
	demo.advance(.5)
	var capped: Dictionary = demo.inspection_snapshot()
	check(capped.tick == 15 and capped.dropped_seconds == .25, "host accepts at most quarter-second per advance")
	check(capped.lanes.baseline == capped.lanes.candidate, "zero-person candidate matches independently stepped unattended baseline")
	check(capped.template.tick == 0 and capped.template.time == 0.0 and capped.events.is_empty(), "template Encounter never advances or invents ballistic events")
	viewport.size = Vector2i(1, 1)
	for _i in 2: await process_frame
	viewport.size = Vector2i(1100, 720)
	for _i in 2: await process_frame
	strip = demo.get("_strip")
	check(strip.size.y <= 160.0, "reset and resize retain bounded HUD height")
	demo.dispose()
	check(demo.get_child_count() == 0 and demo.inspection_snapshot().disposed and demo.inspection_snapshot().resources.storage == 0, "dispose releases both real ship presentations and experimental state")
	demo.free()
	viewport.free()
	await process_frame
	finish()
