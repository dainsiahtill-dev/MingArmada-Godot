extends SceneTree
## Isolated CPU comparison. Never interprets these timings as game frame times.
const Body = preload("res://modules/physics_engine/ships/ship_dynamics.gd")
const Ocean = preload("res://modules/physics_engine/ocean/ocean_adapter.gd")
const Coastal = preload("res://modules/physics_engine/ocean/coastal_wave_field.gd")
const Types = preload("res://modules/contracts/physics_types.gd")
const Manual = preload("res://modules/physics_engine/ships/manual_handling.gd")
const BASE := "res://docs/research/evidence/architecture-convergence-2026-10-21/baseline/source/"
const OLD_BODY := BASE + "modules/physics_engine/ships/ship_dynamics.gd.txt"
const OLD_OCEAN := BASE + "modules/naval_simulation/ocean_adapter.gd.txt"
const DEFAULT_OUTPUT := "res://docs/research/evidence/architecture-convergence-2026-10-21/physics/cpu-pairs-01.json"
const STEP := 1.0 / 60.0
const TICKS := 600
const WARMUP_PAIRS := 2
const SAMPLE_PAIRS := 12
var assertions := 0
var failures := 0
var _old_body: GDScript
var _old_ocean: GDScript
var _controls: Array = []
var _output := DEFAULT_OUTPUT

class TerrainCounter:
	extends RefCounted
	var depth := 4.0
	var calls := 0
	func sample_height(_x: float, _z: float) -> float:
		calls += 1
		return -depth

func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void: _run.call_deferred()

func _frozen_script(path: String) -> GDScript:
	var script := GDScript.new()
	script.source_code = FileAccess.get_file_as_string(path)
	check(not script.source_code.is_empty(), "frozen source available " + path)
	check(script.reload() == OK, "frozen source compiles unchanged " + path)
	return script

func _fleet(legacy: bool, depth: float) -> Dictionary:
	var terrain := TerrainCounter.new(); terrain.depth = depth
	var waves := Coastal.new()
	check(waves.configure(terrain.sample_height), "coastal fixture configured")
	var ocean: RefCounted = _old_ocean.new() if legacy else Ocean.new()
	ocean.sampler = waves; ocean.sea_level = 1.25
	var bodies: Array = []
	for kind: String in Types.SHIP_SPECS:
		var body: RefCounted = _old_body.new() if legacy else Body.new()
		var spec := {"kind":kind,"position":{"x":-160.0,"z":-60.0},"heading":0.45,"speed":2.0,"sailDeployment":0.85,"wind":{"direction":{"x":-0.8,"z":-0.6},"speed":14.0},"config":{"waterRelativeBuoyancy":true}}
		check(body.configure(spec, terrain.sample_height, ocean), "paired body configured " + kind)
		bodies.append(body)
	terrain.calls = 0
	return {"bodies":bodies,"ocean":ocean,"terrain":terrain}

func _build_controls() -> void:
	for tick in TICKS:
		var row: Array = []
		for kind: String in Types.SHIP_SPECS:
			var turn := 0.35 if tick < 360 else -0.2
			row.append({"time":(tick + 1) * STEP,"rudderAngleDeg":turn * 30.0,"crewSteeringForce":10000.0,"sailDeployment":0.85,"manualAssist":Manual.build(kind, turn, 2.0, 1.0, 1.0, 1.0, false, 0.85, true)})
		_controls.append(row)

func _advance(fleet: Dictionary, tick: int, legacy: bool) -> void:
	fleet.ocean.accepted_time = (tick + 1) * STEP
	for index in fleet.bodies.size():
		if legacy: fleet.bodies[index].step(STEP, _controls[tick][index])
		else: fleet.bodies[index].step_in_place(STEP, _controls[tick][index])

func _equivalence() -> Array:
	var rows: Array = []
	for depth: float in [4.0, 24.0]:
		var baseline := _fleet(true, depth); var candidate := _fleet(false, depth)
		var exact := 0
		for tick in TICKS:
			if tick == 180:
				for index in baseline.bodies.size():
					check(baseline.bodies[index].set_cargo_mass(200.0) and candidate.bodies[index].set_cargo_mass(200.0), "paired live cargo accepted")
			if tick == 300:
				for index in baseline.bodies.size():
					var draft: float = Types.ship_spec(baseline.bodies[index].get_snapshot().kind).draft * 0.9
					check(baseline.bodies[index].set_draft_meters(draft) and candidate.bodies[index].set_draft_meters(draft), "paired live draft accepted")
			_advance(baseline, tick, true); _advance(candidate, tick, false)
			for index in baseline.bodies.size():
				var same: bool = baseline.bodies[index].get_snapshot() == candidate.bodies[index].get_snapshot() and baseline.bodies[index].get_buoyancy_debug() == candidate.bodies[index].get_buoyancy_debug()
				check(same, "frozen baseline equality depth=" + str(depth) + " ship=" + str(index) + " tick=" + str(tick))
				if same: exact += 1
		rows.append({"depth_m":depth,"ships":6,"ticks_per_ship":TICKS,"exact_state_and_buoyancy_pairs":exact,"total_pairs":TICKS * 6,"sea_level_m":1.25,"cargo_change_tick":180,"draft_change_tick":300})
	return rows

func _measure(legacy: bool) -> Dictionary:
	var fleet := _fleet(legacy, 4.0)
	var start := Time.get_ticks_usec()
	for tick in TICKS: _advance(fleet, tick, legacy)
	var elapsed := Time.get_ticks_usec() - start
	return {"duration_usec":elapsed,"terrain_calls":fleet.terrain.calls,"solver_steps":TICKS * fleet.bodies.size(),"accepted_seconds_per_ship":TICKS * STEP}

func _stats(samples: Array, field: String) -> Dictionary:
	var values: Array = samples.map(func(sample: Dictionary): return sample[field])
	values.sort()
	var total := 0.0
	for value in values: total += float(value)
	return {"n":values.size(),"mean":total / values.size(),"min":values[0],"max":values[-1],"p50":values[int(ceil(0.5 * values.size())) - 1],"p95":values[int(ceil(0.95 * values.size())) - 1],"quantile":"nearest-rank ceil(q*n)-1"}

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): _output = argument.trim_prefix("--output=")
	if FileAccess.file_exists(_output):
		check(false, "evidence already exists; choose a new --output=res:// path")
		print("PHYSICS_CONVERGENCE_MEASURE assertions=", assertions, " failures=", failures)
		quit(1)
		return
	_old_body = _frozen_script(OLD_BODY); _old_ocean = _frozen_script(OLD_OCEAN)
	_build_controls()
	var equality := _equivalence()
	for _warmup in WARMUP_PAIRS: _measure(true); _measure(false)
	var baseline: Array = []; var candidate: Array = []; var order: Array = []
	for pair in SAMPLE_PAIRS:
		if pair % 2 == 0:
			baseline.append(_measure(true)); candidate.append(_measure(false)); order.append("baseline,candidate")
		else:
			candidate.append(_measure(false)); baseline.append(_measure(true)); order.append("candidate,baseline")
		check(baseline[-1].terrain_calls == TICKS * 6 * 25 and candidate[-1].terrain_calls == TICKS * 6 * 5, "every measured batch retains all five accepted water samples per ship tick")
	var hashes: Dictionary = {}
	for path: String in [OLD_BODY,OLD_OCEAN,"res://modules/physics_engine/ships/ship_dynamics.gd","res://modules/physics_engine/ships/manual_handling.gd","res://modules/physics_engine/ocean/ocean_adapter.gd","res://modules/physics_engine/ocean/coastal_wave_field.gd","res://modules/physics_engine/ocean/wave_field.gd","res://modules/contracts/physics_types.gd","res://modules/contracts/simulation_contract.gd","res://modules/contracts/wave_descriptor.gd","res://tools/measure-physics-convergence.gd"]: hashes[path] = FileAccess.get_sha256(path)
	var evidence := {"schemaVersion":1,"recordType":"performance","scope":"isolated-headless-numeric-CPU","engine":Engine.get_version_info(),"environment":{"os":OS.get_name(),"cpu":OS.get_processor_name(),"logical_processors":OS.get_processor_count(),"gpu":"not-used headless","power_policy":"unknown"},"sources":hashes,"controls":{"step_seconds":STEP,"ticks_per_ship":TICKS,"ship_kinds":Types.SHIP_SPECS.keys(),"depth_m":4.0,"seed":"not-applicable deterministic analytic waves","initial_position":{"x":-160.0,"z":-60.0},"initial_heading_rad":0.45,"initial_speed_mps":2.0,"sea_level_m":1.25,"viewport":"none headless","warmup_pairs":WARMUP_PAIRS,"sample_pairs":SAMPLE_PAIRS,"pair_order":order},"equivalence":equality,"baseline":{"description":"frozen pre-change solver and full-only ocean adapter; returned snapshots discarded as at former encounter call site","samples":baseline,"duration_usec":_stats(baseline,"duration_usec")},"candidate":{"description":"current solver step_in_place plus scalar accepted-time ocean adapter","samples":candidate,"duration_usec":_stats(candidate,"duration_usec")},"assertions":assertions,"failures":failures,"limitations":["CPU microbenchmark only; no render/GPU or complete game frame measurement","AI, coast collision, combat, campaign and Jolt crew are outside timing scope","12-pair p95 describes these samples only; no sustained thermal or deployment claim","Power policy and background load are not controlled by this script"]}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output.get_base_dir()))
	var file := FileAccess.open(_output, FileAccess.WRITE)
	if file == null: check(false, "evidence output writable")
	else: file.store_string(JSON.stringify(evidence, "\t") + "\n"); file.close()
	print("PHYSICS_CONVERGENCE_EVIDENCE ", _output)
	print("PHYSICS_CONVERGENCE_MEASURE assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
