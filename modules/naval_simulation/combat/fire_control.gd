extends RefCounted
## Deterministic, one-tick fire rules. The caller owns accepted time and applies damage.

const Profile = preload("res://modules/naval_simulation/combat/fire_profile.gd")
const STATE_FIELDS := ["version", "heat", "fuelSeconds", "wetness", "crewDamageCarry", "assignedFirefighters", "pendingFirefighters", "transferTicks", "supplies", "workCarry"]
const ACCOUNTING_EPSILON := 0.000000000001
const INT64_EXCLUSIVE_FLOAT_BOUND := 9223372036854775808.0

static func initial(supplies: int = 0) -> Dictionary:
	return {
		"version":Profile.VERSION, "heat":0.0, "fuelSeconds":0.0, "wetness":0.0,
		"crewDamageCarry":0.0, "assignedFirefighters":0, "pendingFirefighters":0,
		"transferTicks":0, "supplies":clampi(supplies, 0, Profile.MAX_SUPPLIES), "workCarry":0.0,
	}

static func valid(state: Variant) -> bool:
	if typeof(state) != TYPE_DICTIONARY or state.size() != STATE_FIELDS.size():
		return false
	for field: String in STATE_FIELDS:
		if not state.has(field):
			return false
	if typeof(state.version) != TYPE_STRING or state.version != Profile.VERSION:
		return false
	if not _number_in(state.heat, 0.0, Profile.MAX_HEAT) or not _number_in(state.fuelSeconds, 0.0, Profile.MAX_FUEL_SECONDS):
		return false
	if not _number_in(state.wetness, 0.0, 1.0) or not _number_in(state.crewDamageCarry, 0.0, 1.0, false):
		return false
	if not _number_in(state.workCarry, 0.0, Profile.WORK_SECONDS_PER_SUPPLY, false):
		return false
	if not _integer_in(state.assignedFirefighters, 0, Profile.MAX_FIREFIGHTERS) or not _integer_in(state.pendingFirefighters, 0, Profile.MAX_FIREFIGHTERS):
		return false
	if not _integer_in(state.transferTicks, 0, Profile.TRANSFER_TICKS) or not _integer_in(state.supplies, 0, Profile.MAX_SUPPLIES):
		return false
	return state.supplies != 0 or state.workCarry == 0.0

static func ignite(state: Variant, payload: Variant, wetness: Variant) -> Dictionary:
	if not valid(state):
		return _command_result(false, state, "invalid-state")
	if typeof(payload) != TYPE_STRING or payload not in ["fire-ball", "thorn-ball"]:
		return _command_result(false, state, "invalid-payload")
	if not _number_in(wetness, 0.0, 1.0):
		return _command_result(false, state, "invalid-wetness")
	var next := _normalized_copy(state)
	var actual_wetness := maxf(float(next.wetness), float(wetness))
	var fuel: float = Profile.FIRE_BALL_FUEL_SECONDS if payload == "fire-ball" else Profile.THORN_BALL_FUEL_SECONDS
	next.wetness = actual_wetness
	next.heat = minf(Profile.MAX_HEAT, float(next.heat) + Profile.IGNITION_HEAT * (1.0 - Profile.WET_IGNITION_HEAT_REDUCTION * actual_wetness))
	next.fuelSeconds = minf(Profile.MAX_FUEL_SECONDS, float(next.fuelSeconds) + fuel * (1.0 - Profile.WET_IGNITION_FUEL_REDUCTION * actual_wetness))
	return _command_result(true, next, "")

static func assign(state: Variant, crew: Variant, able: Variant) -> Dictionary:
	if not valid(state):
		return _command_result(false, state, "invalid-state")
	if not _nonnegative_integer(able) or not _integer_in(crew, 0, Profile.MAX_FIREFIGHTERS):
		return _command_result(false, state, "invalid-crew")
	if crew > able:
		return _command_result(false, state, "insufficient-crew")
	var next := _normalized_copy(state)
	_clip_team(next, int(able))
	var target := int(crew)
	if target == next.pendingFirefighters and (next.transferTicks > 0 or target == next.assignedFirefighters):
		return _command_result(true, next, "")
	# An outbound team remains real occupied people when redirected or canceled.
	if next.transferTicks > 0:
		next.assignedFirefighters = maxi(next.assignedFirefighters, next.pendingFirefighters)
	next.pendingFirefighters = target
	next.transferTicks = Profile.TRANSFER_TICKS
	return _command_result(true, next, "")

static func reserved_crew(state: Variant, able: Variant) -> int:
	if not valid(state) or not _nonnegative_integer(able):
		return 0
	return mini(int(able), maxi(int(state.assignedFirefighters), int(state.pendingFirefighters)))

static func step(state: Variant, context: Variant) -> Dictionary:
	if not valid(state):
		return _step_result(false, state)
	if not _valid_context(context):
		return _step_result(false, state)
	var next := _normalized_copy(state)
	var able := int(context.able)
	_clip_team(next, able)
	var traveling: bool = next.transferTicks > 0
	var workers: int = 0 if traveling else next.assignedFirefighters
	if traveling:
		next.transferTicks -= 1
		if next.transferTicks == 0:
			next.assignedFirefighters = next.pendingFirefighters
	next.wetness = clampf(float(next.wetness) + (float(context.rain01) * Profile.RAIN_WETNESS_PER_SECOND - (1.0 - float(context.rain01)) * Profile.DRYING_PER_SECOND) * Profile.STEP_SECONDS, 0.0, 1.0)
	var had_heat: bool = next.heat > 0.0
	var remaining: float = Profile.STEP_SECONDS
	var area := 0.0
	var work := 0.0
	var spent := 0
	var natural_rate: float = Profile.HEAT_GROWTH_PER_SECOND * (1.0 + Profile.FLAMMABLE_HEAT_GAIN * float(context.flammableLoad)) - Profile.WET_COOLING_PER_SECOND * float(next.wetness)
	# At most two work regimes: available preparation, then exhausted preparation.
	while remaining > 0.0 and next.heat > 0.0 and next.fuelSeconds > 0.0:
		var work_budget: float = Profile.WORK_SECONDS_PER_SUPPLY * next.supplies - float(next.workCarry)
		var effective_workers: int = workers if work_budget > 0.0 else 0
		var duration: float = minf(remaining, float(next.fuelSeconds))
		if effective_workers > 0:
			duration = minf(duration, work_budget / float(effective_workers))
		var rate: float = natural_rate - Profile.FIREFIGHTER_COOLING_PER_SECOND * effective_workers
		var segment := _integrate_heat(float(next.heat), rate, duration)
		var elapsed: float = segment.seconds
		area += float(segment.area)
		next.heat = segment.heat
		next.fuelSeconds = maxf(0.0, float(next.fuelSeconds) - elapsed)
		remaining = maxf(0.0, remaining - elapsed)
		if effective_workers > 0:
			var actual_work: float = minf(work_budget, float(effective_workers) * elapsed)
			work += actual_work
			spent += _spend_work(next, actual_work)
		if next.fuelSeconds == 0.0:
			next.heat = 0.0
		# A zero-length segment can arise only at an exhausted floating-point budget.
		if elapsed == 0.0:
			break
	if next.fuelSeconds == 0.0:
		next.heat = 0.0
	var expected_crew: float = float(next.crewDamageCarry) + area * Profile.CREW_DAMAGE_PER_HEAT_SECOND * float(context.maxCrew)
	var whole_crew := int(floor(expected_crew))
	var crew_loss := mini(able, whole_crew)
	next.crewDamageCarry = expected_crew - float(whole_crew)
	_clip_team(next, able - crew_loss)
	var extinguished: bool = had_heat and next.heat == 0.0
	if extinguished and maxi(next.assignedFirefighters, next.pendingFirefighters) > 0:
		next.assignedFirefighters = maxi(next.assignedFirefighters, next.pendingFirefighters)
		next.pendingFirefighters = 0
		next.transferTicks = Profile.TRANSFER_TICKS
	var result := _step_result(true, next)
	result.damage = {
		"hull":area * Profile.HULL_DAMAGE_PER_HEAT_SECOND * float(context.maxHull),
		"sail":area * Profile.SAIL_DAMAGE_PER_HEAT_SECOND * float(context.maxSail),
		"crew":crew_loss,
	}
	result.reservedCrew = reserved_crew(next, able - crew_loss)
	result.extinguished = extinguished
	result.workSeconds = work
	result.suppliesSpent = spent
	return result

static func _integrate_heat(heat: float, rate: float, duration: float) -> Dictionary:
	var elapsed := duration
	if rate < 0.0:
		var to_zero := heat / -rate
		if to_zero <= elapsed:
			return {"heat":0.0, "area":0.5 * heat * to_zero, "seconds":to_zero}
		var end := heat + rate * elapsed
		return {"heat":end, "area":0.5 * (heat + end) * elapsed, "seconds":elapsed}
	if rate > 0.0:
		var to_cap: float = (Profile.MAX_HEAT - heat) / rate
		if to_cap < elapsed:
			return {"heat":Profile.MAX_HEAT, "area":0.5 * (heat + Profile.MAX_HEAT) * to_cap + Profile.MAX_HEAT * (elapsed - to_cap), "seconds":elapsed}
	var end: float = minf(Profile.MAX_HEAT, heat + rate * elapsed)
	return {"heat":end, "area":0.5 * (heat + end) * elapsed, "seconds":elapsed}

static func _spend_work(state: Dictionary, work: float) -> int:
	var accumulated: float = float(state.workCarry) + work
	# Repeated rational 1/60-second work may round just below an exact full preparation.
	var spent := mini(int(state.supplies), int(floor((accumulated + ACCOUNTING_EPSILON) / Profile.WORK_SECONDS_PER_SUPPLY)))
	state.supplies -= spent
	state.workCarry = 0.0 if state.supplies == 0 else maxf(0.0, accumulated - spent * Profile.WORK_SECONDS_PER_SUPPLY)
	return spent

static func _clip_team(state: Dictionary, able: int) -> void:
	state.assignedFirefighters = mini(state.assignedFirefighters, able)
	state.pendingFirefighters = mini(state.pendingFirefighters, able)

static func _normalized_copy(state: Dictionary) -> Dictionary:
	var result := state.duplicate(true)
	for field: String in ["assignedFirefighters", "pendingFirefighters", "transferTicks", "supplies"]:
		result[field] = int(result[field])
	for field: String in ["heat", "fuelSeconds", "wetness", "crewDamageCarry", "workCarry"]:
		result[field] = float(result[field])
	return result

static func _valid_context(context: Variant) -> bool:
	if typeof(context) != TYPE_DICTIONARY:
		return false
	for field: String in ["able", "maxHull", "maxSail", "maxCrew", "rain01", "flammableLoad"]:
		if not context.has(field):
			return false
	return _nonnegative_integer(context.able) and _nonnegative_integer(context.maxCrew) and context.maxCrew > 0 and _positive_number(context.maxHull) and _positive_number(context.maxSail) and _number_in(context.rain01, 0.0, 1.0) and _number_in(context.flammableLoad, 0.0, 1.0)

static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))

static func _number_in(value: Variant, minimum: float, maximum: float, inclusive_maximum: bool = true) -> bool:
	return _number(value) and value >= minimum and (value <= maximum if inclusive_maximum else value < maximum)

static func _positive_number(value: Variant) -> bool:
	return _number(value) and value > 0.0

static func _nonnegative_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return value >= 0
	return typeof(value) == TYPE_FLOAT and is_finite(value) and value >= 0.0 and value < INT64_EXCLUSIVE_FLOAT_BOUND and floor(value) == value

static func _integer_in(value: Variant, minimum: int, maximum: int) -> bool:
	return _nonnegative_integer(value) and value >= minimum and value <= maximum

static func _command_result(ok: bool, state: Variant, reason: String) -> Dictionary:
	return {"ok":ok, "state":state.duplicate(true) if typeof(state) == TYPE_DICTIONARY else {}, "reason":reason}

static func _step_result(ok: bool, state: Variant) -> Dictionary:
	return {
		"ok":ok, "state":state.duplicate(true) if typeof(state) == TYPE_DICTIONARY else {},
		"damage":{"hull":0.0, "sail":0.0, "crew":0}, "reservedCrew":0,
		"extinguished":false, "workSeconds":0.0, "suppliesSpent":0,
	}
