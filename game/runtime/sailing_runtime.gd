extends RefCounted
## Owns accepted simulation time and input intent. Physics and renderer stay apart.

const Dynamics = preload("res://modules/physics_engine/ships/ship_dynamics.gd")
const ManualHandling = preload("res://modules/physics_engine/ships/manual_handling.gd")
const Waves = preload("res://modules/physics_engine/ocean/wave_field.gd")
const CoastalWaves = preload("res://modules/physics_engine/ocean/coastal_wave_field.gd")
const STEP := 1.0 / 120.0

var _ship := Dynamics.new()
var _time := 0.0
var _accumulator := 0.0
var _paused := false
var _assisted := true
var _configured := false
var _turn := 0.0
var _deployment := 0.75
var _trim := 0.8
var _wind := {"direction": {"x": -1.0, "z": 0.3}, "speed": 12.0}
var _waves: RefCounted

func configure(height_sampler: Callable, spec: Dictionary = {}) -> bool:
	var initial := {"kind": "fuchuan", "position": {"x": -220.0, "z": -80.0}, "heading": 0.4, "time": 0.0, "speed": 0.0, "wind": _wind.duplicate(true), "sailAngle": _trim, "sailDeployment": _deployment}
	initial.merge(spec.duplicate(true), true)
	_waves = CoastalWaves.new()
	_waves.configure(height_sampler)
	_configured = _ship.configure(initial, height_sampler, _waves)
	if _configured:
		_time = float(initial.time)
		_deployment = float(initial.sailDeployment)
		_trim = float(initial.sailAngle)
		_wind = initial.wind.duplicate(true)
		_accumulator = 0.0
	return _configured

func sample_water_height(x: float, z: float, seconds: float) -> float:
	return _waves.sample(x, z, seconds).height if _waves else NAN

func command(intent: Dictionary) -> Dictionary:
	match intent.get("type", ""):
		"pause":
			_paused = bool(intent.get("value", not _paused))
			_turn = 0.0
		"assist": _assisted = bool(intent.get("value", not _assisted))
		"turn":
			var value: Variant = intent.get("value")
			if not (value is float or value is int) or not is_finite(value): return {"ok": false, "reason": "invalid-turn"}
			_turn = clampf(value, -1.0, 1.0)
		"sail":
			var value: Variant = intent.get("value")
			if not (value is float or value is int) or not is_finite(value): return {"ok": false, "reason": "invalid-sail"}
			_deployment = clampf(value, 0.0, 1.0)
		"trim":
			var value: Variant = intent.get("value")
			if not (value is float or value is int) or not is_finite(value): return {"ok": false, "reason": "invalid-trim"}
			_trim = clampf(value, -PI / 2.0, PI / 2.0)
		_: return {"ok": false, "reason": "unknown-command"}
	return {"ok": true}

func advance(seconds: float) -> float:
	if not _configured or _paused or not is_finite(seconds) or seconds <= 0:
		return 0.0
	_accumulator += minf(seconds, 0.25)
	var consumed := 0.0
	while _accumulator + 1.0e-12 >= STEP:
		var current: Dictionary = _ship.get_snapshot()
		var speed := sqrt(float(current.velocity.x) ** 2 + float(current.velocity.z) ** 2)
		var controls := {"time": _time + STEP, "rudderAngleDeg": _turn * 30.0, "crewSteeringForce": 20000.0, "sailAngle": _trim, "sailDeployment": _deployment, "wind": _wind.duplicate(true), "throttle": 0.0}
		if _assisted:
			controls.manualAssist = ManualHandling.build(current.kind, _turn, speed, 1.0, 1.0, 1.0, _deployment <= 0.05, _deployment)
		_ship.step(STEP, controls)
		_time += STEP
		consumed += STEP
		_accumulator -= STEP
	return consumed

func snapshot() -> Dictionary:
	var ship: Dictionary = _ship.get_snapshot()
	if ship.is_empty(): return {}
	ship["id"] = "flagship"
	ship["sailAngle"] = _trim
	ship["sailDeployment"] = _deployment
	ship["rudder"] = _turn
	ship["hull"] = 100.0
	ship["maxHull"] = 100.0
	ship["sail"] = 100.0
	ship["maxSail"] = 100.0
	ship["crew"] = 100
	ship["maxCrew"] = 100
	return {"time": _time, "ship": ship, "focus": {"x": ship.position.x, "z": ship.position.z}, "wind": _wind.duplicate(true), "paused": _paused, "assisted": _assisted}
