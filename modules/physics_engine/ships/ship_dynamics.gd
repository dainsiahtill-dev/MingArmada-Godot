extends RefCounted

# Exact scalar marine integration order from frozen NormPhysicsEngine.
# All spatial state remains 64-bit scalar float; conversion to Vector3 belongs
# at presentation/contact adapters. No scene, naval, domain or UI dependencies.
const Types = preload("res://modules/contracts/physics_types.gd")
const ClockContract = preload("res://modules/contracts/simulation_contract.gd")
const WaveDescriptor = preload("res://modules/contracts/wave_descriptor.gd")
const ManualHandling = preload("res://modules/physics_engine/ships/manual_handling.gd")

var _configured := false
var _kind := ""
var _params: Dictionary = {}
var _config: Dictionary = Types.default_config()
var _terrain: Callable
var _waves: RefCounted
var _length := 30.0
var _beam := 6.0
var _height := 4.5
var _dry_mass := 120000.0
var _cargo_mass := 0.0
var _draft := 2.0
var _air_density := 1.225
var _water_density := 1025.0
var _frontal_area := 16.2
var _sail_area := 0.0
var _sail_run_cd := 1.4
var _sail_lift_slope := 4.2
var _sail_stall_rad := 28.0 * PI / 180.0
var _sail_cd0 := 0.08
var _sail_induced_drag := 0.6
var _sail_ce_height := 8.0
var _roll_gm := 1.5
var _roll_radius := 2.1
var _turn_roll_height := 1.575
var drive_max_accel := 2.0
var drive_reverse_factor := 0.5
var _x := 0.0
var _z := 0.0
var _heading := 0.0
var _vx := 0.0
var _vz := 0.0
var _yaw_rate := 0.0
var _base_y := 0.0
var _heave := 0.0
var _heave_rate := 0.0
var _pitch := 0.0
var _pitch_rate := 0.0
var _heel := 0.0
var _heel_rate := 0.0
var _buoyancy_offset: Variant = null
var _time := 0.0
var _wind_x := 1.0
var _wind_z := 0.0
var _wind_speed := 0.0
var _sail_angle := 0.0
var _sail_deployment := 1.0
var _sail_condition := 1.0
var _sail_power_scale := 1.0
var _controls := {"throttle": 0.0, "rudderAngleDeg": 0.0, "crewSteeringForce": 0.0, "manualAssist": {}}
var _wave_points: Array = []
var _wave_average := 0.0
var _sample_forward := 0.0
var _sample_side := 0.0
var _wave_pitch := 0.0
var _wave_heel := 0.0
var _sail_debug := {"valid": false, "apparentWindSpeed": 0.0, "trueWindSpeed": 0.0, "relativeWindDirDotForward": 0.0, "sailAngleRad": 0.0, "aoaRad": 0.0, "runBlend": 0.0, "cl": 0.0, "cd": 0.0, "forwardForce": 0.0}

func configure(spec: Dictionary, terrain: Callable = Callable(), waves: RefCounted = null) -> bool:
	var kind: String = spec.get("kind", "fuchuan")
	var params := Types.ship_spec(kind)
	if params.is_empty() or (spec.has("params") and not spec.params is Dictionary):
		return false
	params.beam = params.width
	params.height = params.freeboard + 2.0
	params.massOverride = params.mass
	params.sailInducedDragFactor = 0.08
	params.merge(spec.get("params", {}), true)
	var length: float = Types.finite_or(params.get("length"), NAN)
	var beam: float = Types.finite_or(params.get("width", params.get("beam")), NAN)
	var height: float = Types.finite_or(params.get("height"), NAN)
	var dry_mass: float = Types.finite_or(params.get("massOverride", params.get("mass", params.get("massKg"))), NAN)
	var cargo: float = Types.finite_or(spec.get("cargoMass", 0.0), NAN)
	var draft: float = Types.finite_or(spec.get("draft", params.draft), NAN)
	var position: Variant = spec.get("position", {"x": 0.0, "z": 0.0})
	if not position is Dictionary or not Types.finite_number(position.get("x")) or not Types.finite_number(position.get("z")):
		return false
	for field: String in ["heading", "speed", "time", "baseY", "sailAngle", "sailDeployment", "sailCondition", "sailPowerScale"]:
		if spec.has(field) and not Types.finite_number(spec[field]):
			return false
	if not is_finite(length) or length <= 0.0 or not is_finite(height) or height <= 0.0 or not is_finite(dry_mass) or dry_mass <= 0.0 or not is_finite(cargo) or cargo < 0.0 or cargo > dry_mass:
		return false
	var config := Types.default_config()
	config.merge({"keelAreaFactor": length / beam / 0.8, "keelLiftSlope": 6.0, "keelInducedDragFactor": 0.08, "sailPressureScale": 1.0}, true)
	if waves != null:
		config.heaveTravelLimit = WaveDescriptor.ORIGINAL_HEAVE_EXCURSION_METERS + draft * 2.0
	if not spec.get("config", {}) is Dictionary:
		return false
	config.merge(spec.get("config", {}), true)
	if not _valid_config(config) or not Types.valid_draft(draft, beam, dry_mass + cargo, config.heaveDamp, config.waterAreaFactor):
		return false
	for value: Variant in params.values():
		if (value is float or value is int) and not Types.finite_number(value):
			return false
	if not is_finite((dry_mass + cargo) * (length * length + beam * beam) / 12.0):
		return false
	_kind = kind
	_params = params.duplicate(true)
	_config = config.duplicate(true)
	_terrain = terrain
	_waves = waves
	_length = length
	_beam = beam
	_height = height
	_dry_mass = dry_mass
	_cargo_mass = cargo
	_draft = draft
	_air_density = Types.finite_or(params.get("rhoAir"), 1.225)
	_water_density = Types.finite_or(params.get("rhoWater"), 1025.0)
	_frontal_area = beam * height * 0.6
	var summed_sail: float = params.get("mainSailArea", 0.0) + params.get("foreSailArea", 0.0) + params.get("aftSailArea", 0.0)
	_sail_area = summed_sail if summed_sail > 0.0 else float(params.get("sailArea", 0.0))
	_sail_run_cd = params.get("sailRunCd", 1.4)
	_sail_lift_slope = params.get("sailLiftSlope", 4.2)
	_sail_stall_rad = params.get("sailStallAngle", 28.0) * PI / 180.0
	_sail_cd0 = params.get("sailCd0", 0.08)
	_sail_induced_drag = params.get("sailInducedDragFactor", 0.6)
	_sail_ce_height = _positive_or(params.get("sailCEHeight"), height * 0.6)
	_roll_gm = _positive_or(params.get("GMt"), beam * 0.25)
	_roll_radius = 0.35 * float(params.get("beam", beam))
	_turn_roll_height = height * 0.35
	_x = position.x
	_z = position.z
	_heading = spec.get("heading", 0.0)
	_vx = cos(_heading) * float(spec.get("speed", 0.0))
	_vz = sin(_heading) * float(spec.get("speed", 0.0))
	_yaw_rate = 0.0
	_heave = 0.0
	_heave_rate = 0.0
	_pitch = 0.0
	_pitch_rate = 0.0
	_heel = 0.0
	_heel_rate = 0.0
	_time = spec.get("time", 0.0)
	_buoyancy_offset = null
	_wave_points = [{"x": 0.0, "y": 0.0, "z": 0.0}, {"x": 0.0, "y": 0.0, "z": 0.0}, {"x": 0.0, "y": 0.0, "z": 0.0}, {"x": 0.0, "y": 0.0, "z": 0.0}]
	_wave_average = 0.0
	_sample_forward = 0.0
	_sample_side = 0.0
	_wave_pitch = 0.0
	_wave_heel = 0.0
	_base_y = spec.get("baseY", 0.0)
	if not spec.has("baseY") and waves != null:
		var c := cos(_heading)
		var s := sin(_heading)
		# Preserve original spawn arithmetic/order: -forward then +forward,
		# -side then +side; sum each divided sample, rather than sum / four.
		for f: float in [-1.0, 1.0]:
			for r: float in [-1.0, 1.0]:
				var forward := maxf(0.5, _length * 0.35)
				var side := maxf(0.25, _beam * 0.45)
				var sampled := _water_height(_x + c * forward * f - s * side * r, _z + s * forward * f + c * side * r)
				if is_finite(sampled):
					_base_y += sampled / 4.0
	set_wind(spec.get("wind", {"direction": {"x": 1.0, "z": 0.0}, "speed": 0.0}))
	set_sail_angle(spec.get("sailAngle", 0.8))
	set_sail_deployment(spec.get("sailDeployment", 0.8))
	set_sail_condition(spec.get("sailCondition", 1.0))
	set_sail_power_scale(spec.get("sailPowerScale", 1.0))
	_controls = {"throttle": 0.0, "rudderAngleDeg": 0.0, "crewSteeringForce": 0.0, "manualAssist": {}}
	_sail_debug = {"valid": false, "apparentWindSpeed": 0.0, "trueWindSpeed": 0.0, "relativeWindDirDotForward": 0.0, "sailAngleRad": 0.0, "aoaRad": 0.0, "runBlend": 0.0, "cl": 0.0, "cd": 0.0, "forwardForce": 0.0}
	_configured = true
	return true

func get_snapshot() -> Dictionary:
	return {"kind": _kind, "time": _time, "position": {"x": _x, "y": _base_y + _heave, "z": _z}, "heading": _heading,
		"velocity": {"x": _vx, "y": 0.0, "z": _vz}, "yawRate": _yaw_rate,
		"heave": _heave, "heaveRate": _heave_rate, "pitch": _pitch, "pitchRate": _pitch_rate, "heel": _heel, "heelRate": _heel_rate,
		"baseY": _base_y, "buoyancyOffsetY": _buoyancy_offset, "mass": _mass(),
		"dimensions": {"length": _length, "width": _beam, "draft": _draft},
		"rig": {"sailAngle": _sail_angle, "sailDeployment": _sail_deployment, "sailCondition": _sail_condition, "sailPowerScale": _sail_power_scale},
		"sailDebug": _sail_debug.duplicate(true)}

func get_config() -> Dictionary:
	return _config.duplicate(true)

func get_wave_debug() -> Dictionary:
	if not _update_wave_sample(cos(_heading), sin(_heading)):
		return {}
	return {"points": _wave_points.duplicate(true), "averageHeight": _wave_average, "sampleForward": _sample_forward, "sampleSide": _sample_side, "pitchRad": _wave_pitch, "heelRad": _wave_heel}

func set_config(partial: Dictionary) -> bool:
	var candidate := _config.duplicate(true)
	candidate.merge(partial, true)
	if not _valid_config(candidate) or not Types.valid_draft(_draft, _beam, _mass(), candidate.heaveDamp, candidate.waterAreaFactor):
		return false
	_config = candidate
	return true

func set_cargo_mass(cargo_kg: float) -> bool:
	if not is_finite(cargo_kg) or cargo_kg < 0.0 or cargo_kg > _dry_mass or not Types.valid_draft(_draft, _beam, _dry_mass + cargo_kg, _config.heaveDamp, _config.waterAreaFactor):
		return false
	_cargo_mass = cargo_kg
	return true

func set_draft_meters(draft_meters: float) -> bool:
	if not Types.valid_draft(draft_meters, _beam, _mass(), _config.heaveDamp, _config.waterAreaFactor):
		return false
	_draft = draft_meters
	return true

func set_sail_angle(angle: float) -> void:
	_sail_angle = Types.normalized_angle(angle)

func set_sail_deployment(value: float) -> void:
	_sail_deployment = clampf(value, 0.0, 1.0) if is_finite(value) else 0.0

func set_sail_condition(value: float) -> void:
	_sail_condition = clampf(value, 0.0, 1.0) if is_finite(value) else 0.0

func set_sail_power_scale(value: float) -> void:
	_sail_power_scale = clampf(value, 0.0, 4.0) if is_finite(value) else 0.0

func set_wind(wind: Dictionary) -> void:
	var direction: Variant = wind.get("direction")
	_wind_x = 1.0
	_wind_z = 0.0
	if direction is Dictionary:
		var x: float = Types.finite_or(direction.get("x"), NAN)
		var z: float = Types.finite_or(direction.get("z", direction.get("y")), NAN)
		if is_finite(x) and is_finite(z) and x * x + z * z > 1.0e-12:
			_wind_x = x
			_wind_z = z
	_wind_speed = maxf(0.0, Types.finite_or(wind.get("speed"), 0.0))

func set_base_y(y: float) -> bool:
	if not is_finite(y):
		return false
	_base_y = y
	_buoyancy_offset = null
	return true

func set_state(position: Dictionary, heading: float) -> bool:
	if not Types.finite_number(position.get("x")) or not Types.finite_number(position.get("z")) or not is_finite(heading):
		return false
	_x = position.x
	_z = position.z
	_heading = heading
	_buoyancy_offset = null
	return true

func set_speed(speed: float) -> bool:
	if not is_finite(speed):
		return false
	_vx = cos(_heading) * speed
	_vz = sin(_heading) * speed
	return true

func stop_horizontal_motion() -> void:
	_vx = 0.0
	_vz = 0.0
	_yaw_rate = 0.0

func correct_horizontal_motion(position: Dictionary, velocity: Dictionary, heading: Variant = null) -> bool:
	if not Types.finite_number(position.get("x")) or not Types.finite_number(position.get("z")) or not Types.finite_number(velocity.get("x")) or not Types.finite_number(velocity.get("z")) or (heading != null and not Types.finite_number(heading)):
		return false
	_x = position.x
	_z = position.z
	_vx = velocity.x
	_vz = velocity.z
	if heading != null:
		_heading = heading
	return true

func resolve_horizontal_contact(normal: Dictionary, offset: Dictionary) -> float:
	if not [normal.get("x"), normal.get("z"), offset.get("x"), offset.get("z")].all(Types.finite_number):
		return _yaw_rate
	var inertia := _mass() * (_length * _length + _beam * _beam) / 12.0
	var lever: float = offset.x * normal.z - offset.z * normal.x
	var inward: float = _vx * normal.x + _vz * normal.z + _yaw_rate * lever
	if inward > 0.0 and _mass() > 0.0 and inertia > 0.0:
		var impulse := inward / (1.0 / _mass() + lever * lever / inertia)
		_vx += normal.x * (-impulse / _mass())
		_vz += normal.z * (-impulse / _mass())
		_yaw_rate -= impulse * lever / inertia
	return _yaw_rate

func step(delta: float, controls: Dictionary = {}) -> Dictionary:
	var dt := ClockContract.accepted_delta(delta)
	if not _configured or dt == 0.0:
		return get_snapshot()
	_accept_controls(controls)
	_time = Types.finite_or(controls.get("time"), _time + dt)
	var fx := cos(_heading)
	var fz := sin(_heading)
	var sx := -fz
	var sz := fx
	var has_wave := _update_wave_sample(fx, fz)
	var throttle: float = _controls.throttle
	var assist: Dictionary = _controls.manualAssist
	var mass := _mass()
	# Drive precedes apparent wind so its velocity participates in sail forces.
	if throttle != 0.0 and mass > 0.0:
		var reverse_scale := drive_reverse_factor if throttle < 0.0 else 1.0
		var drive_accel := throttle * drive_max_accel * reverse_scale
		_vx += fx * (drive_accel * dt)
		_vz += fz * (drive_accel * dt)
	var sail_side_force := _step_sail(fx, fz, sx, sz, dt)
	var sail_factor := _sail_deployment * _sail_condition * _sail_power_scale
	# Quadratic air/water drag and dry hull braking budget cannot reverse velocity.
	var speed_abs := sqrt(_vx * _vx + _vz * _vz)
	if speed_abs > 1.0e-6 and mass > 0.0:
		var air_drag := 0.5 * _air_density * 0.2 * _frontal_area * speed_abs * speed_abs
		var water_drag: float = 0.5 * _water_density * _config.waterCd * _water_area() * speed_abs * speed_abs
		var brake_force: float = _dry_mass * assist.brakeDeceleration * assist.powerFraction if not assist.is_empty() else 0.0
		var total_accel := (air_drag + water_drag + brake_force) / mass
		var new_speed := speed_abs - total_accel * dt
		if new_speed <= 0.0:
			_vx = 0.0
			_vz = 0.0
			speed_abs = 0.0
		else:
			var scale := new_speed / speed_abs
			_vx *= scale
			_vz *= scale
			speed_abs = new_speed
	# Keel force and induced drag use the speed before the keel impulse.
	if speed_abs > 1.0e-6 and mass > 0.0 and _config.keelAreaFactor > 0.0 and _config.keelLiftSlope > 0.0:
		var v_forward := _vx * fx + _vz * fz
		var v_side := _vx * sx + _vz * sz
		var leeway := atan2(v_side, absf(v_forward) + 1.0e-3)
		var stall: float = _config.keelStallDeg * PI / 180.0
		var cl: float = _config.keelLiftSlope * clampf(leeway, -stall, stall)
		var q_water := 0.5 * _water_density * speed_abs * speed_abs
		var area: float = _water_area() * _config.keelAreaFactor
		var force_side := -cl * q_water * area
		_vx += sx * ((force_side * dt) / mass)
		_vz += sz * ((force_side * dt) / mass)
		var cd: float = _config.keelCd0 + _config.keelInducedDragFactor * (cl * cl)
		var force_drag := q_water * cd * area
		if force_drag > 0.0:
			var velocity_length := sqrt(_vx * _vx + _vz * _vz)
			if velocity_length > 1.0e-6:
				var next_speed := velocity_length - (force_drag / mass) * dt
				if next_speed <= 0.0:
					_vx = 0.0
					_vz = 0.0
				else:
					var scale := next_speed / velocity_length
					_vx *= scale
					_vz *= scale
		speed_abs = sqrt(_vx * _vx + _vz * _vz)
	if speed_abs > 1.0e-6 and _config.lateralDampCoeff > 0.0:
		var lateral_speed := _vx * sx + _vz * sz
		var lateral_damp: float = exp(-_config.lateralDampCoeff * speed_abs * dt)
		var change := lateral_speed * lateral_damp - lateral_speed
		_vx += sx * change
		_vz += sz * change
	# Original realistic hard no-go is an explicit legacy rule. Assistance can
	# opt into coasting; no-go still suppresses sail propulsion in either path.
	var no_go_zone: float = maxf(0.0, _config.noGoZoneDeg) * PI / 180.0
	if not assist.get("coastInNoGo", false) and _sail_area > 0.0 and sail_factor > 0.0 and no_go_zone > 0.0 and absf(throttle) < 1.0e-3 and _wind_speed > 0.0:
		var wind := _normalized_wind()
		var dot: float = wind.x * fx + wind.z * fz
		if dot > 0.0 and acos(minf(1.0, dot)) < no_go_zone:
			var v_forward := _vx * fx + _vz * fz
			if v_forward > 0.0:
				_vx += fx * -v_forward
				_vz += fz * -v_forward
	# Hydraulic rudder, low-speed stern force and optional bounded torque.
	var flow_forward := _vx * fx + _vz * fz
	var flow_speed := absf(flow_forward)
	var inertia := (1.0 / 12.0) * mass * (_length * _length + _beam * _beam)
	var stall: float = _config.rudderStallDeg * PI / 180.0
	var rudder_rad: float = clampf(_controls.rudderAngleDeg * PI / 180.0, -stall, stall)
	var hydraulic := flow_speed > 1.0e-3 and _water_area() > 0.0
	var moment := 0.0
	if hydraulic:
		var cl: float = _config.rudderLiftSlope * rudder_rad
		var q_water := 0.5 * _water_density * flow_speed * flow_speed
		var rudder_area: float = _water_area() * _config.rudderAreaFactor
		var flow_sign := signf(flow_forward) if flow_forward != 0.0 else 1.0
		var lift := -cl * q_water * rudder_area * flow_sign
		_vx += sx * ((lift * dt) / mass)
		_vz += sz * ((lift * dt) / mass)
		var arm: float = _length * _config.rudderArmFactor
		moment = lift * arm
	var water_speed := sqrt(_vx * _vx + _vz * _vz)
	var speed_ratio := minf(1.0, water_speed / 1.2)
	var yaw_ratio := clampf(signf(rudder_rad) * _yaw_rate / 0.035, 0.0, 1.0)
	var crew_arm := -_length / 2.0
	var crew_force: float = _controls.crewSteeringForce
	var crew_lift := -crew_force * (rudder_rad / (PI / 6.0)) * (1.0 - _smoothstep01(speed_ratio)) * (1.0 - _smoothstep01(yaw_ratio)) if crew_force > 0.0 else 0.0
	if inertia > 0.0 and crew_arm != 0.0:
		var force_limit := 0.012 * inertia / absf(crew_arm)
		crew_lift = clampf(crew_lift, -force_limit, force_limit)
	else:
		crew_lift = 0.0
	if crew_lift != 0.0:
		_vx += sx * ((crew_lift * dt) / mass)
		_vz += sz * ((crew_lift * dt) / mass)
		moment += crew_lift * crew_arm
	var dry_inertia := (1.0 / 12.0) * _dry_mass * (_length * _length + _beam * _beam)
	var assist_moment := ManualHandling.torque(assist, _yaw_rate, dry_inertia)
	moment += assist_moment
	if hydraulic or crew_lift != 0.0 or assist_moment != 0.0:
		if inertia > 0.0:
			var yaw_acc: float = moment / inertia - _config.yawDamp * _yaw_rate
			_yaw_rate += yaw_acc * dt
			_yaw_rate = clampf(_yaw_rate, -_config.maxYawRate, _config.maxYawRate)
			var yaw_damp: float = exp(-_config.lateralDampCoeff * flow_speed * dt)
			_yaw_rate *= yaw_damp
	var torque_heel := sail_side_force * _sail_ce_height
	var torque_turn := -mass * flow_speed * _yaw_rate * _turn_roll_height
	_step_buoyancy(dt, has_wave, torque_heel + torque_turn)
	_heading += _yaw_rate * dt
	_x += _vx * dt
	_z += _vz * dt
	return get_snapshot()

func step_buoyancy(delta: float, accepted_time: Variant = null) -> Dictionary:
	var dt := ClockContract.accepted_delta(delta)
	if not _configured or dt == 0.0:
		return get_snapshot()
	_time = Types.finite_or(accepted_time, _time + dt)
	var has_wave := _update_wave_sample(cos(_heading), sin(_heading))
	_step_buoyancy(dt, has_wave, 0.0)
	return get_snapshot()

func _step_sail(fx: float, fz: float, sx: float, sz: float, dt: float) -> float:
	_sail_debug.valid = false
	var side_force := 0.0
	var factor := _sail_deployment * _sail_condition * _sail_power_scale
	if _sail_area > 0.0 and factor > 0.0 and _wind_speed > 0.0 and _mass() > 0.0:
		var wind := _normalized_wind()
		var apparent_x: float = wind.x * -_wind_speed - _vx
		var apparent_z: float = wind.z * -_wind_speed - _vz
		var aw_speed := sqrt(apparent_x * apparent_x + apparent_z * apparent_z)
		if aw_speed > 0.01:
			var ax := apparent_x * (1.0 / aw_speed)
			var az := apparent_z * (1.0 / aw_speed)
			var efficiency := _no_go_efficiency(-ax * fx + -az * fz)
			var plane_x := cos(_heading + _sail_angle)
			var plane_z := sin(_heading + _sail_angle)
			var normal_x := -plane_z
			var normal_z := plane_x
			if normal_x * ax + normal_z * az < 0.0:
				normal_x = -normal_x
				normal_z = -normal_z
			var dot_plane := ax * plane_x + az * plane_z
			var cos_plane := absf(dot_plane)
			var incidence := clampf(1.0 - cos_plane * cos_plane, 0.1, 1.0)
			var q_air := 0.5 * _air_density * aw_speed * aw_speed
			var pressure_cd: float = _sail_run_cd * maxf(0.0, _config.sailPressureScale)
			var pressure_scale := q_air * pressure_cd * _sail_area * incidence
			var pressure_x := normal_x * pressure_scale
			var pressure_z := normal_z * pressure_scale
			var chord_x := plane_x if dot_plane >= 0.0 else -plane_x
			var chord_z := plane_z if dot_plane >= 0.0 else -plane_z
			var cross := ax * chord_z - az * chord_x
			var dot := ax * chord_x + az * chord_z
			var aoa := atan2(cross, dot)
			var abs_aoa := absf(aoa)
			var cl := 0.0
			if abs_aoa <= _sail_stall_rad:
				cl = _sail_lift_slope * aoa
			else:
				var denominator := maxf(1.0e-4, PI / 2.0 - _sail_stall_rad)
				var blend := clampf((abs_aoa - _sail_stall_rad) / denominator, 0.0, 1.0)
				var fade := (1.0 - blend) * (1.0 - blend)
				cl = _sail_lift_slope * _sail_stall_rad * signf(aoa) * fade
			var cd := _sail_cd0 + _sail_induced_drag * (cl * cl)
			var lift_scale := q_air * cl * _sail_area
			var drag_scale := q_air * cd * _sail_area
			var wing_x := (az * lift_scale + ax * drag_scale) * cos_plane
			var wing_z := (-ax * lift_scale + az * drag_scale) * cos_plane
			var parasitic_scale := q_air * 0.5 * _sail_area
			var total_x := ((pressure_x + wing_x) + ax * parasitic_scale) * (efficiency * factor)
			var total_z := ((pressure_z + wing_z) + az * parasitic_scale) * (efficiency * factor)
			var forward_force := total_x * fx + total_z * fz
			side_force = total_x * sx + total_z * sz
			_vx += total_x * (dt / _mass())
			_vz += total_z * (dt / _mass())
			_sail_debug = {"valid": true, "apparentWindSpeed": aw_speed, "trueWindSpeed": _wind_speed, "relativeWindDirDotForward": wind.x * fx + wind.z * fz, "sailAngleRad": _sail_angle, "aoaRad": aoa, "runBlend": incidence, "cl": cl, "cd": cd, "forwardForce": forward_force}
	if not _sail_debug.valid or _wind_speed <= 0.0 or _sail_area <= 0.0:
		_sail_debug.valid = false
		_sail_debug.apparentWindSpeed = 0.0
		_sail_debug.trueWindSpeed = _wind_speed
		_sail_debug.forwardForce = 0.0
	return side_force

func _update_wave_sample(fx: float, fz: float) -> bool:
	if _waves == null:
		_wave_average = 0.0
		_sample_forward = 0.0
		_sample_side = 0.0
		_wave_pitch = 0.0
		_wave_heel = 0.0
		return false
	_sample_forward = maxf(0.5, _length * 0.35)
	_sample_side = maxf(0.25, _beam * 0.45)
	var forward_x := fx * _sample_forward
	var forward_z := fz * _sample_forward
	var side_x := -fz * _sample_side
	var side_z := fx * _sample_side
	var coordinates := [[_x + forward_x + side_x, _z + forward_z + side_z], [_x + forward_x - side_x, _z + forward_z - side_z], [_x - forward_x - side_x, _z - forward_z - side_z], [_x - forward_x + side_x, _z - forward_z + side_z]]
	var heights: Array[float] = []
	for point: Array in coordinates:
		heights.append(_water_height(point[0], point[1]))
	if not heights.all(func(value: float) -> bool: return is_finite(value)):
		_wave_average = 0.0
		_wave_pitch = 0.0
		_wave_heel = 0.0
		return false
	for i in range(4):
		_wave_points[i] = {"x": coordinates[i][0], "y": heights[i], "z": coordinates[i][1]}
	_wave_average = (heights[0] + heights[1] + heights[2] + heights[3]) * 0.25
	_wave_pitch = atan2((heights[0] + heights[1]) * 0.5 - (heights[2] + heights[3]) * 0.5, _sample_forward * 2.0)
	_wave_heel = atan2((heights[1] + heights[2]) * 0.5 - (heights[0] + heights[3]) * 0.5, _sample_side * 2.0)
	return true

func _step_buoyancy(dt: float, has_wave: bool, external_roll_torque: float) -> void:
	var mass := _mass()
	var roll_inertia := mass * _roll_radius * _roll_radius
	if not _config.buoyancyEnabled:
		_heave = 0.0
		_heave_rate = 0.0
		_pitch = 0.0
		_pitch_rate = 0.0
		_buoyancy_offset = null
		if roll_inertia > 0.0:
			var restoring := mass * 9.81 * _roll_gm * sin(_heel)
			var acceleration := (external_roll_torque - restoring) / roll_inertia - 0.6 * _heel_rate
			_heel_rate += acceleration * dt
			_heel += _heel_rate * dt
			_heel = clampf(_heel, -PI / 3.0 * 0.99, PI / 3.0 * 0.99)
		return
	if _waves == null:
		return
	var center_water := _water_height(_x, _z)
	var water_ref := _wave_average if has_wave else center_water
	if not is_finite(water_ref):
		return
	if _buoyancy_offset == null:
		_buoyancy_offset = _base_y + _heave - water_ref
	var water_offset: float = _buoyancy_offset
	var sample_forward := _sample_forward if _sample_forward > 0.0 else maxf(0.5, _length * 0.35)
	var sample_side := _sample_side if _sample_side > 0.0 else maxf(0.25, _beam * 0.45)
	var stiffness := (mass * 9.81) / _draft / 4.0
	var damping: float = (mass * _config.heaveDamp) / 4.0
	var boat_y := _base_y + _heave
	var sin_pitch := sin(_pitch)
	var sin_heel := sin(_heel)
	var x_offsets := [sample_forward, sample_forward, -sample_forward, -sample_forward]
	var z_offsets := [sample_side, -sample_side, -sample_side, sample_side]
	var force := 0.0
	var roll_torque := 0.0
	var pitch_torque := 0.0
	for i in range(4):
		var x: float = x_offsets[i]
		var z: float = z_offsets[i]
		var water_y: float = (float(_wave_points[i].y) if has_wave else center_water) + water_offset
		var hull_y := boat_y - _draft + x * sin_pitch - z * sin_heel
		var depth := water_y - hull_y
		if depth <= 0.0:
			continue
		var point_velocity := _heave_rate + x * _pitch_rate - z * _heel_rate
		var point_force := maxf(0.0, stiffness * depth - damping * point_velocity)
		force += point_force
		roll_torque += -z * point_force
		pitch_torque += x * point_force
	var heave_acc := (force - mass * 9.81) / mass
	_heave_rate += heave_acc * dt
	_heave += _heave_rate * dt
	var max_heave: float = _config.get("heaveTravelLimit", _draft * 2.0)
	_heave = clampf(_heave, -max_heave, max_heave)
	var pitch_inertia := (1.0 / 12.0) * mass * (_length * _length + _height * _height)
	if pitch_inertia > 0.0:
		var pitch_acc := pitch_torque / pitch_inertia - 0.6 * _pitch_rate
		_pitch_rate += pitch_acc * dt
		_pitch += _pitch_rate * dt
		_pitch = clampf(_pitch, -PI / 10.0, PI / 10.0)
	if roll_inertia > 0.0:
		var heel_acc := (roll_torque + external_roll_torque) / roll_inertia - 0.6 * _heel_rate
		_heel_rate += heel_acc * dt
		_heel += _heel_rate * dt
		_heel = clampf(_heel, -PI / 7.0 * 0.99, PI / 7.0 * 0.99)

func _accept_controls(input: Dictionary) -> void:
	_controls = {"throttle": clampf(Types.finite_or(input.get("throttle"), 0.0), -1.0, 1.0),
		"rudderAngleDeg": Types.finite_or(input.get("rudderAngleDeg"), 0.0),
		"crewSteeringForce": clampf(Types.finite_or(input.get("crewSteeringForce"), 0.0), 0.0, 40000.0),
		"manualAssist": ManualHandling.sanitize(input.get("manualAssist"))}
	if input.has("sailAngle"):
		set_sail_angle(Types.finite_or(input.sailAngle, NAN))
	if input.has("sailDeployment"):
		set_sail_deployment(Types.finite_or(input.sailDeployment, NAN))
	if input.has("sailCondition"):
		set_sail_condition(Types.finite_or(input.sailCondition, NAN))
	if input.has("sailPowerScale"):
		set_sail_power_scale(Types.finite_or(input.sailPowerScale, NAN))
	if input.get("wind") is Dictionary:
		set_wind(input.wind)

func _valid_config(config: Dictionary) -> bool:
	for key: String in config:
		if key == "buoyancyEnabled":
			if not config[key] is bool:
				return false
		elif not Types.finite_number(config[key]):
			return false
	if config.has("heaveTravelLimit") and config.heaveTravelLimit <= 0.0:
		return false
	return config.heaveDamp >= 0.0 and config.waterAreaFactor >= 0.0 and config.maxYawRate >= 0.0

func _water_height(x: float, z: float) -> float:
	if _waves == null or not _waves.has_method("sample"):
		return NAN
	var sampled: Variant = _waves.sample(x, z, _time)
	return Types.finite_or(sampled.get("height"), NAN) if sampled is Dictionary else NAN

func _normalized_wind() -> Dictionary:
	var squared := _wind_x * _wind_x + _wind_z * _wind_z
	if squared <= 1.0e-12:
		return {"x": 1.0, "z": 0.0}
	var inverse := 1.0 / sqrt(squared)
	return {"x": _wind_x * inverse, "z": _wind_z * inverse}

func _no_go_efficiency(dot: float) -> float:
	var zone: float = maxf(0.0, _config.noGoZoneDeg)
	if zone <= 0.0:
		return 1.0
	var fade: float = maxf(0.0, _config.noGoFadeDeg)
	var angle := acos(clampf(dot, -1.0, 1.0))
	var zone_rad := zone * PI / 180.0
	var fade_rad := fade * PI / 180.0
	if fade_rad <= 1.0e-4:
		return 1.0 if angle >= zone_rad else 0.0
	var blend := clampf((angle - zone_rad) / fade_rad, 0.0, 1.0)
	return blend * blend

func _water_area() -> float:
	return _beam * _draft * _config.waterAreaFactor

func _mass() -> float:
	return _dry_mass + _cargo_mass

static func _smoothstep01(value: float) -> float:
	return value * value * (3.0 - 2.0 * value)

static func _positive_or(value: Variant, fallback: float) -> float:
	return float(value) if Types.finite_number(value) and value > 0.0 else fallback
