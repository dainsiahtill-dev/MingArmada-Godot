extends SceneTree

const WaveField = preload("res://modules/physics_engine/ocean/wave_field.gd")
const ManualHandling = preload("res://modules/physics_engine/ships/manual_handling.gd")
const ABS_EPSILON := 1.0e-7
const REL_EPSILON := 1.0e-8
var _failures: Array[String] = []
var _assertions := 0
var _maximum_error := 0.0
var _solver_script: Script

class FlatWaves:
	extends RefCounted
	var level := 0.0
	func sample(_x: float, _z: float, _time: float) -> Dictionary:
		return {"height": level}

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, explanation: String) -> void:
	_assertions += 1
	if not value:
		_failures.append(explanation)

func _run() -> void:
	# Missing solver is an explicit feature failure, rather than a preload error.
	if ResourceLoader.exists("res://modules/physics_engine/ships/ship_dynamics.gd"):
		_solver_script = load("res://modules/physics_engine/ships/ship_dynamics.gd")
	_check(_solver_script != null and _solver_script.can_instantiate(), "native marine solver must exist and instantiate")
	if _solver_script != null and _solver_script.can_instantiate():
		_test_original_runtime_tracks()
		_test_invalid_ticks_and_detached_state()
		_test_atomic_live_updates()
		_test_auxiliary_steering_and_mass()
		_test_forward_brake_and_no_go()
		_test_four_support_buoyancy_and_anchor()
		_test_manual_budget_and_assist_boundaries()
	for failure in _failures.slice(0, 50):
		printerr("FAIL: ", failure)
	print("SHIP_PHYSICS_TESTS assertions=", _assertions, " failures=", _failures.size(), " max_oracle_error=", _maximum_error)
	quit(0 if _failures.is_empty() else 1)

func _compare_numeric(actual: Variant, expected: Variant, label: String) -> void:
	if expected is Dictionary:
		_check(actual is Dictionary, label + " must be a scalar dictionary")
		if not actual is Dictionary:
			return
		for key: String in expected:
			_check(actual.has(key), label + "." + key + " missing")
			if actual.has(key):
				_compare_numeric(actual[key], expected[key], label + "." + key)
	elif expected == null or expected is bool:
		_check(actual == expected, label + " differs")
	elif expected is float or expected is int:
		var error: float = absf(float(actual) - float(expected))
		_maximum_error = maxf(_maximum_error, error)
		_check(is_finite(float(actual)) and error <= ABS_EPSILON + REL_EPSILON * absf(float(expected)), "%s error %.12f expected %.12f actual %.12f" % [label, error, expected, actual])

func _test_original_runtime_tracks() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ship-reference.json"))
	_check(fixture.sourceHead == "9ad6a44daecd4ec36a8172d83ff27493feffe5dd", "golden data must identify the frozen original runtime")
	_check(fixture.tracks.size() == 24, "all 24 independent source cases must replay")
	for track: Dictionary in fixture.tracks:
		var spec: Dictionary = track.initial.duplicate(true)
		spec.kind = track.kind
		var waves: RefCounted = FlatWaves.new() if spec.get("sampler") == "flat" else WaveField.new()
		var engine = _solver_script.new()
		_check(engine.configure(spec, Callable(), waves), track.name + " configure")
		var frame_index := 0
		for tick in range(int(track.ticks) + 1):
			if tick > 0:
				for change: Dictionary in track.commands:
					if int(change.tick) != tick:
						continue
					if change.has("cargoMass"):
						_check(engine.set_cargo_mass(change.cargoMass), track.name + " cargo update")
					if change.has("draft"):
						_check(engine.set_draft_meters(change.draft), track.name + " draft update")
					if change.has("sailPowerScale"):
						engine.set_sail_power_scale(change.sailPowerScale)
					if change.has("controls"):
						track.controls = change.controls
					if change.has("stop"):
						engine.stop_horizontal_motion()
					if change.has("contact"):
						engine.resolve_horizontal_contact(change.contact.normal, change.contact.offset)
				var controls: Dictionary = track.controls.duplicate(true)
				controls.time = float(track.initial.get("time", 0.0)) + float(tick) / float(track.hz)
				engine.step(1.0 / float(track.hz), controls)
			if frame_index < track.frames.size() and int(track.frames[frame_index].tick) == tick:
				_compare_numeric(engine.get_snapshot(), track.frames[frame_index].state, "%s tick %d" % [track.name, tick])
				frame_index += 1
		_check(frame_index == track.frames.size(), track.name + " all oracle frames reached")
	print("ORIGINAL_SHIP_RUNTIME tracks=", fixture.tracks.size(), " frames=215 max_error=", _maximum_error)

func _body(extra: Dictionary = {}) -> RefCounted:
	var spec := {"kind": "fuchuan", "sailDeployment": 0.0, "wind": {"direction": {"x": 1.0, "z": 0.0}, "speed": 0.0}}
	spec.merge(extra, true)
	var engine: RefCounted = _solver_script.new()
	_check(engine.configure(spec, Callable(), FlatWaves.new()), "test body configures")
	return engine

func _assist(power: float = 1.0) -> Dictionary:
	return {"targetYawRateRad": deg_to_rad(8.0), "maxYawAccelerationRad": deg_to_rad(11.0), "powerFraction": power,
		"neutralYawDamping": 0.0, "brakeDeceleration": 0.0, "coastInNoGo": true}

func _test_invalid_ticks_and_detached_state() -> void:
	var engine = _body({"speed": 2.0})
	var before: Dictionary = engine.get_snapshot()
	for dt: float in [0.0, -1.0, INF, -INF, NAN]:
		engine.step(dt, {"throttle": 1.0})
	_check(engine.get_snapshot() == before, "invalid deltas must not mutate controls, clock or body")
	var detached: Dictionary = engine.get_snapshot()
	detached.position.x = 999.0
	detached.rig.sailDeployment = 1.0
	_check(engine.get_snapshot() == before, "snapshot nested dictionaries must be detached")
	var capped = _body({"speed": 2.0})
	engine.step(20.0, {"throttle": 1.0})
	capped.step(0.05, {"throttle": 1.0})
	_check(engine.get_snapshot() == capped.get_snapshot(), "large delta consumes original 50ms cap once")
	var reference = _body()
	var bad = _body()
	bad.step(1.0 / 120.0, {"throttle": NAN, "rudderAngleDeg": INF, "crewSteeringForce": INF, "manualAssist": {"targetYawRateRad": INF}})
	reference.step(1.0 / 120.0, {})
	_check(bad.get_snapshot() == reference.get_snapshot(), "invalid controls clear all propulsion and assist")

func _test_atomic_live_updates() -> void:
	var engine = _body()
	engine.step(1.0 / 120.0, {"manualAssist": _assist()})
	var before: Dictionary = engine.get_snapshot()
	for draft: float in [0.0, -1.0, 0.049, INF, NAN]:
		_check(not engine.set_draft_meters(draft), "invalid draft rejected")
	for cargo: float in [-1.0, 95001.0, INF, NAN]:
		_check(not engine.set_cargo_mass(cargo), "invalid cargo rejected")
	_check(not engine.set_config({"waterCd": 0.99, "heaveTravelLimit": 0.0}), "invalid config rejected atomically")
	_check(not engine.set_config({"waterCd": 0.99, "heaveTravelLimit": null}), "null heave bound rejects whole live config")
	_check(not engine.set_config({"waterCd": 0.99, "heaveTravelLimit": "9"}), "string heave bound rejects whole live config")
	_check(engine.get_snapshot() == before, "invalid updates retain all dynamics and wave offset")
	_check(engine.set_cargo_mass(47500.0) and engine.set_draft_meters(2.7), "valid load and draft accepted")
	var after: Dictionary = engine.get_snapshot()
	_check(after.position == before.position and after.yawRate == before.yawRate and after.buoyancyOffsetY == before.buoyancyOffsetY, "equipment changes retain current body and wave reference")
	_check(after.mass == 142500.0 and after.dimensions.draft == 2.7, "load and draft use kg and m")
	var invalid = _solver_script.new()
	_check(not invalid.configure({"kind": "missing"}, Callable(), FlatWaves.new()), "unknown hull kind rejected")

func _test_auxiliary_steering_and_mass() -> void:
	var light = _body()
	var loaded = _body({"cargoMass": 95000.0})
	var weak = _body()
	var zero = _body()
	for engine in [light, loaded]:
		engine.step(1.0 / 120.0, {"manualAssist": _assist()})
	weak.step(1.0 / 120.0, {"manualAssist": _assist(0.25)})
	zero.step(1.0 / 120.0, {"manualAssist": _assist(0.0)})
	var yaw: float = light.get_snapshot().yawRate
	_check(yaw > 0.0 and yaw <= deg_to_rad(11.0) / 120.0, "manual turn obeys dry hull acceleration budget")
	_check(absf(loaded.get_snapshot().yawRate - yaw * 0.5) < 1.0e-12, "loaded inertia halves dry torque response")
	_check(absf(weak.get_snapshot().yawRate - yaw * 0.25) < 1.0e-12, "crew power scales torque")
	_check(zero.get_snapshot().heading == 0.0 and light.get_snapshot().position.x == 0.0, "manual torque cannot add direct translation")
	var crew = _body()
	crew.step(1.0 / 120.0, {"rudderAngleDeg": 30.0, "crewSteeringForce": 7400.0})
	_check(crew.get_snapshot().heading > 0.0 and crew.get_snapshot().velocity.z < 0.0, "crew stern force rotates and translates through forces")
	var fast = _body({"speed": 3.0})
	var hydraulic = _body({"speed": 3.0})
	fast.step(1.0 / 120.0, {"rudderAngleDeg": 30.0, "crewSteeringForce": 7400.0})
	hydraulic.step(1.0 / 120.0, {"rudderAngleDeg": 30.0})
	_check(fast.get_snapshot() == hydraulic.get_snapshot(), "normal water speed disables auxiliary stern force")

func _test_forward_brake_and_no_go() -> void:
	var forward = _body()
	forward.step(1.0 / 120.0, {"throttle": 1.0})
	_check(forward.get_snapshot().velocity.x > 0.0 and forward.get_snapshot().velocity.z == 0.0, "heading zero forward drive uses +X")
	var brakes = _body({"speed": 0.03})
	var assist := _assist()
	assist.targetYawRateRad = 0.0
	assist.brakeDeceleration = 0.2
	for i in range(120):
		brakes.step(1.0 / 120.0, {"manualAssist": assist})
	_check(brakes.get_snapshot().velocity.x == 0.0, "braking stops without reversal")
	var upwind := {"speed": 5.0, "sailDeployment": 1.0, "wind": {"direction": {"x": 1.0, "z": 0.0}, "speed": 9.0}}
	var realistic = _body(upwind)
	var assisted = _body(upwind)
	assist.brakeDeceleration = 0.0
	realistic.step(1.0 / 120.0, {})
	assisted.step(1.0 / 120.0, {"manualAssist": assist})
	_check(realistic.get_snapshot().velocity.x == 0.0 and assisted.get_snapshot().velocity.x > 0.0, "realistic hard no-go and opt-in manual coasting both preserved")
	_check(assisted.get_snapshot().sailDebug.forwardForce == 0.0, "coasting provides no false headwind thrust")

func _test_four_support_buoyancy_and_anchor() -> void:
	var waves := FlatWaves.new()
	var engine = _solver_script.new()
	engine.configure({"kind": "fisherman", "baseY": -1.0, "sailDeployment": 0.0, "config": {"heaveTravelLimit": 9.0}}, Callable(), waves)
	engine.step_buoyancy(1.0 / 120.0)
	waves.level = 4.0
	for i in range(1200):
		engine.step_buoyancy(1.0 / 120.0)
	_check(absf(engine.get_snapshot().position.y - 3.0) < 0.2, "four buoyancy supports follow moved water rather than hard root anchoring")
	var moving = _body({"speed": 3.0})
	moving.step(1.0 / 120.0, {"manualAssist": _assist()})
	var before: Dictionary = moving.get_snapshot()
	moving.stop_horizontal_motion()
	var after: Dictionary = moving.get_snapshot()
	_check(after.velocity == {"x": 0.0, "y": 0.0, "z": 0.0} and after.yawRate == 0.0, "anchor removes horizontal momentum")
	_check(after.position == before.position and after.heaveRate == before.heaveRate and after.pitchRate == before.pitchRate and after.buoyancyOffsetY == before.buoyancyOffsetY, "anchor preserves water pose, rates and reference")

func _test_manual_budget_and_assist_boundaries() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ship-reference.json"))
	_check(fixture.manualBudgets.size() == 54, "all original manual hull/speed/intent budgets exported")
	for budget: Dictionary in fixture.manualBudgets:
		var actual: Dictionary = ManualHandling.build(budget.kind, budget.turnIntent, budget.speed, budget.crewFraction, budget.hullFraction, budget.sailFraction, budget.braking, budget.sailDeployment)
		_compare_numeric(actual, budget.expected, "manual budget %s %.1f %.1f" % [budget.kind, budget.speed, budget.turnIntent])
	var invalid := [
		{"targetYawRateRad": NAN}, {"targetYawRateRad": INF}, {"targetYawRateRad": deg_to_rad(12.0) + 0.001},
		{"targetYawRateRad": -deg_to_rad(12.0) - 0.001}, {"maxYawAccelerationRad": -1.0},
		{"maxYawAccelerationRad": deg_to_rad(16.0) + 0.001}, {"maxYawAccelerationRad": INF},
		{"powerFraction": -0.01}, {"powerFraction": 1.01}, {"powerFraction": NAN},
		{"neutralYawDamping": -1.0}, {"neutralYawDamping": 3.01}, {"neutralYawDamping": INF},
		{"brakeDeceleration": -0.01}, {"brakeDeceleration": 0.201}, {"brakeDeceleration": NAN}, {"coastInNoGo": 1},
	]
	for malformed: Dictionary in invalid:
		var engine = _body()
		var reference = _body()
		for i in range(120):
			engine.step(1.0 / 120.0, {"manualAssist": _assist()})
			reference.step(1.0 / 120.0, {"manualAssist": _assist()})
		var request := _assist()
		request.merge(malformed, true)
		engine.step(1.0 / 120.0, {"manualAssist": request})
		reference.step(1.0 / 120.0, {})
		_check(engine.get_snapshot() == reference.get_snapshot(), "malformed assist clears whole previous request: " + str(malformed))
	_check(ManualHandling.build("missing", 1.0, 0.0).is_empty(), "unknown manual hull rejects budget")
	_check(ManualHandling.build("fuchuan", NAN, 0.0).is_empty(), "nonfinite manual input rejects budget")
