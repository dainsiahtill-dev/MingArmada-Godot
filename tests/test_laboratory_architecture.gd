extends SceneTree
const Catalog = preload("res://game/research/catalog.gd")
const DEMO_PATH := "res://game/research/demos/architecture_convergence_experiment.gd"
const TOPIC := "architecture-convergence-2026-10-21"
const STEP := 1.0 / 60.0
var assertions := 0
var failures := 0
var samples: Array = []

func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ", message)

func _initialize() -> void: _run.call_deferred()

func _physical(state: Dictionary) -> PackedByteArray:
	return var_to_bytes([state.tick,state.time,state.seed,state.baseline,state.candidate,state.counts])

func _run() -> void:
	var catalog := Catalog.new()
	check(catalog.load_catalog().ok, "bundled research catalog remains valid")
	var topic: Dictionary = catalog.topic(TOPIC)
	check(not topic.is_empty(), "architecture convergence is a registered independent research topic")
	check(catalog.demo_path(TOPIC) == DEMO_PATH and catalog.read_paper(TOPIC).get("ok",false), "home laboratory resolves bundled paper and explicit demo allowlist")
	check(FileAccess.file_exists(DEMO_PATH), "independent architecture demo exists")
	if not FileAccess.file_exists(DEMO_PATH): _finish(); return
	var demo: Node3D = load(DEMO_PATH).new()
	var configured: Dictionary = demo.configure({"paused":true})
	check(configured.ok and configured.pending and not configured.ready, "detached configure validates without constructing resources")
	var viewport := SubViewport.new(); viewport.own_world_3d = true; viewport.size = Vector2i(800,450); root.add_child(viewport); viewport.add_child(demo)
	var initial: Dictionary = demo.inspection_snapshot()
	check(initial.ready and initial.topic == TOPIC and initial.tick == 0 and initial.time == 0.0 and initial.seed == 1661, "isolated production experiment starts at declared deterministic origin")
	check(not demo.is_processing() and not demo.is_physics_processing(), "host alone supplies elapsed time")
	check(initial.resources.simulations == 2 and initial.resources.ship == 1 and initial.resources.ocean == 1, "paired authorities share one observed production ship and ocean")
	check(initial.surface.shader == "res://modules/scene_engine/ocean/reference_game_water.gdshader" and initial.surface.wave_count == 5 and initial.surface.shallow_field, "production shader and shallow-depth texture describe the same five-wave surface")
	var frozen := _physical(initial)
	demo.advance(1.0); demo.orbit_camera(0.2,0.05); demo.zoom_camera(-0.1)
	check(_physical(demo.inspection_snapshot()) == frozen, "paused camera work neither advances authority nor measurement counters")
	var observer: Dictionary = demo.inspection_snapshot().camera_controls
	check(demo.reset_experiment().ok and demo.inspection_snapshot().camera_controls == observer, "same-condition reset preserves observation camera")
	demo.set_paused(false); demo.advance(STEP * 1.5)
	var partial: Dictionary = demo.inspection_snapshot()
	samples.append({"case":"fractional-frame","tick":partial.tick,"accepted_time":partial.time,"render_time":partial.render_time,"counts":partial.counts,"baseline":partial.baseline,"candidate":partial.candidate,"surface":partial.surface,"camera_transform":partial.camera_transform})
	check(partial.tick == 1 and partial.baseline == partial.candidate and partial.telemetry.exact, "paired full/scalar production simulations accept the same fixed tick")
	check(partial.counts.full_terrain == 25 and partial.counts.scalar_terrain == 5 and partial.counts.full_samples == 5 and partial.counts.scalar_samples == 5, "live shallow-water measurement counts twenty-five versus five real terrain calls")
	check(partial.counts.candidate_full_samples == 0, "candidate actually consumes the production scalar ocean seam")
	check(absf(partial.render_time - STEP * 0.5) < 1.0e-12 and partial.time == STEP, "production interpolation consumes fractional frame remainder without advancing authority")
	var accepted := _physical(partial)
	check(demo.set_parameter("interpolation",false).ok and demo.inspection_snapshot().render_time == STEP, "same-time toggle selects fixed authoritative pose")
	check(demo.set_parameter("variant","full").ok and _physical(demo.inspection_snapshot()) == accepted, "baseline selection changes observation only")
	check(demo.set_parameter("interpolation",true).ok and _physical(demo.inspection_snapshot()) == accepted, "interpolation selection cannot spend accepted time or resample physics")
	demo.set_paused(true)
	accepted = _physical(demo.inspection_snapshot())
	for invalid: float in [-1.0,NAN,INF]: demo.advance(invalid)
	check(_physical(demo.inspection_snapshot()) == accepted, "invalid deltas remain atomic")
	check(not demo.configure({"kind":"unknown"}).ok and demo.inspection_snapshot().ready, "invalid configuration preserves the existing experiment")
	check(not demo.set_parameter("unknown",true).ok, "unregistered parameter rejected")
	check(demo.set_parameter("kind","heavy").reset_required and demo.inspection_snapshot().parameters.kind == "fuchuan", "ship factor requires host-owned explicit reset")
	var specifications: Array = demo.control_spec()
	var ship_choices := 0
	for specification: Dictionary in specifications:
		if specification.id == "kind": ship_choices = specification.choices.size()
	check(ship_choices == 6, "all six production hull types selectable")
	for kind: String in ["fuchuan","fisherman","patrol","merchant","voc","heavy"]:
		check(demo.reset_experiment({"kind":kind,"paused":false,"interpolation":true,"variant":"scalar"}).ok, "real model reset " + kind)
		for tick in 12: demo.advance(STEP)
		var state: Dictionary = demo.inspection_snapshot()
		samples.append({"case":"selectable-hull","kind":kind,"tick":state.tick,"time":state.time,"counts":state.counts,"exact":state.telemetry.exact,"resources":state.resources})
		check(state.tick == 12 and state.baseline == state.candidate and state.telemetry.exact, "full/scalar state exact for selectable hull " + kind)
		check(state.counts.full_terrain == 300 and state.counts.scalar_terrain == 60, "real production probe counts accumulate deterministically " + kind)
	var replay: Dictionary = demo.inspection_snapshot()
	check(demo.reset_experiment().ok, "reset starts a fresh measurement")
	for tick in 12: demo.advance(STEP)
	check(_physical(demo.inspection_snapshot()) == _physical(replay), "same seed/inputs reset replays complete paired state and counts")
	demo.dispose(); demo.dispose()
	var disposed: Dictionary = demo.inspection_snapshot()
	check(disposed.disposed and not disposed.ready and disposed.resources.world == 0 and disposed.resources.simulations == 0 and demo.get_child_count() == 0, "idempotent dispose releases model, ocean and paired authorities")
	viewport.free()
	var lab: Control = load("res://game/research/laboratory.gd").new(); root.add_child(lab); lab.set_process(false)
	check(lab.select_topic(TOPIC) and lab.start_demo({"paused":true}).ok, "existing homepage laboratory host starts registered architecture topic")
	check(lab.step_demo().ok and lab.inspection_snapshot().demo.tick == 1, "shared host single-step accepts one production sixty-Hz tick")
	lab.dispose(); lab.free()
	_finish()

func _finish() -> void:
	print("LABORATORY_ARCHITECTURE_SAMPLES ",JSON.stringify(samples))
	print("LABORATORY_ARCHITECTURE_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
