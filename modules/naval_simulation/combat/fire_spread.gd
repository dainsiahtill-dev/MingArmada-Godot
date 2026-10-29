extends RefCounted
## H5 coarse spatial wrapper. FireControl owns all heat integration and costs.
## One accepted step calls the r1 step exactly once; presentation owns no rules.
const Fire = preload("res://modules/naval_simulation/combat/fire_control.gd")
const VERSION := "ship-fire-r2-zones"
const ZONES := ["bow", "mid", "stern"]
const FIELDS := ["version", "heatByZone", "exposureTicks", "fuelSeconds", "wetness", "crewDamageCarry", "assignedFirefighters", "pendingFirefighters", "transferTicks", "supplies", "workCarry"]
const SPREAD_THRESHOLD := 24.0
const SPREAD_TICKS := 360
const SPREAD_HEAT := 12.0

static func initial(supplies: int = 0) -> Dictionary:
	return _from_legacy(Fire.initial(supplies), [0.0, 0.0, 0.0], [0, 0, 0])

static func valid(state: Variant) -> bool:
	if typeof(state) != TYPE_DICTIONARY or state.size() != FIELDS.size(): return false
	for field: String in FIELDS:
		if not state.has(field): return false
	if typeof(state.version) != TYPE_STRING or state.version != VERSION: return false
	if typeof(state.heatByZone) != TYPE_ARRAY or state.heatByZone.size() != 3: return false
	if typeof(state.exposureTicks) != TYPE_ARRAY or state.exposureTicks.size() != 3: return false
	for index: int in range(3):
		if not _number_in(state.heatByZone[index], 0.0, 100.0): return false
		if not _integer_in(state.exposureTicks[index], 0, SPREAD_TICKS): return false
	if _total(state.heatByZone) > 100.0: return false
	return Fire.valid(_summary_unchecked(state))

static func summary(state: Variant) -> Dictionary:
	return _summary_unchecked(state) if valid(state) else {}

static func ignite(state: Variant, payload: Variant, wetness: Variant, zone: Variant) -> Dictionary:
	if not valid(state): return _command_result(false, state, "invalid-state")
	var index: int = _zone_index(zone)
	if index < 0: return _command_result(false, state, "invalid-zone")
	var base: Dictionary = Fire.ignite(_summary_unchecked(state), payload, wetness)
	if not base.ok: return _command_result(false, state, str(base.reason))
	var heats: Array = _heat_copy(state.heatByZone)
	var exposure: Array = _tick_copy(state.exposureTicks)
	var accepted_heat: float = float(base.state.heat) - _total(heats)
	heats[index] = float(heats[index]) + accepted_heat
	_fit_total(heats, float(base.state.heat))
	exposure[index] = 0
	return _command_result(true, _from_legacy(base.state, heats, exposure), "")

static func assign(state: Variant, crew: Variant, able: Variant) -> Dictionary:
	if not valid(state): return _command_result(false, state, "invalid-state")
	var base: Dictionary = Fire.assign(_summary_unchecked(state), crew, able)
	if not base.ok: return _command_result(false, state, str(base.reason))
	return _command_result(true, _from_legacy(base.state, state.heatByZone, state.exposureTicks), "")

static func reserved_crew(state: Variant, able: Variant) -> int:
	return Fire.reserved_crew(_summary_unchecked(state), able) if valid(state) else 0

static func step(state: Variant, context: Variant) -> Dictionary:
	if not valid(state): return _rejected_step(state)
	var before: Array = _heat_copy(state.heatByZone)
	# The sole r1 integration call. Damage, fuel, work and team movement are returned intact.
	var result: Dictionary = Fire.step(_summary_unchecked(state), context)
	result.spreadEvents = []
	if not result.ok:
		result.state = state.duplicate(true)
		return result
	var heats: Array = _allocate_heat(before, float(result.state.heat))
	var exposure: Array = _tick_copy(state.exposureTicks)
	if float(result.state.heat) <= 0.0 or float(result.state.fuelSeconds) <= 0.0:
		heats = [0.0, 0.0, 0.0]
		exposure = [0, 0, 0]
	else:
		result.spreadEvents = _spread(before, heats, exposure)
		_fit_total(heats, float(result.state.heat))
	result.state = _from_legacy(result.state, heats, exposure)
	return result

static func _spread(before: Array, heats: Array, exposure: Array) -> Array:
	# Freeze post-r1 eligibility before any transfer: no same-tick relay.
	var frozen: Array = heats.duplicate()
	var candidates: Array = []
	var events: Array = []
	for target: int in range(3):
		if float(before[target]) > 0.0 or float(frozen[target]) > 0.0:
			exposure[target] = 0
			continue
		var source: int = _source_for(target, before, frozen)
		if source < 0:
			exposure[target] = 0
			continue
		exposure[target] = int(exposure[target]) + 1
		if int(exposure[target]) >= SPREAD_TICKS:
			candidates.append({"source":source, "target":target})
			exposure[target] = 0
	for candidate: Dictionary in candidates:
		var source: int = int(candidate.source)
		var target: int = int(candidate.target)
		# One donor may owe both ends; each successful transfer must leave 12 heat.
		if float(heats[source]) < SPREAD_HEAT * 2.0: continue
		heats[source] = float(heats[source]) - SPREAD_HEAT
		heats[target] = SPREAD_HEAT
		events.append({"fromZone":ZONES[source], "toZone":ZONES[target], "heat":SPREAD_HEAT})
	for index: int in range(3):
		if float(heats[index]) > 0.0: exposure[index] = 0
	return events

static func _source_for(target: int, before: Array, after: Array) -> int:
	var chosen: int = -1
	var hottest: float = -1.0
	for source: int in range(3):
		if absi(source - target) != 1: continue
		if float(before[source]) < SPREAD_THRESHOLD or float(after[source]) < SPREAD_THRESHOLD: continue
		if float(after[source]) > hottest:
			chosen = source
			hottest = float(after[source])
	return chosen

static func _allocate_heat(before: Array, wanted: float) -> Array:
	var heats: Array = before.duplicate()
	var delta: float = wanted - _total(before)
	if delta > 0.0:
		var active: int = 0
		for value: float in before:
			if value > 0.0: active += 1
		if active > 0:
			var share: float = delta / float(active)
			for index: int in range(3):
				if float(before[index]) > 0.0: heats[index] = float(heats[index]) + share
	elif delta < 0.0:
		var remaining: float = -delta
		for _index: int in range(3):
			var source: int = _hottest(heats)
			if source < 0 or remaining <= 0.0: break
			var removed: float = minf(remaining, float(heats[source]))
			heats[source] = maxf(0.0, float(heats[source]) - removed)
			remaining = maxf(0.0, remaining - removed)
	_fit_total(heats, wanted)
	return heats

static func _fit_total(heats: Array, wanted: float) -> void:
	# The final positive component absorbs only floating-point summation residue.
	# Earlier cold components stay zero; no extra r1 step or heat source is added.
	if _total(heats) == wanted: return
	var last: int = -1
	for index: int in range(3):
		if float(heats[index]) > 0.0: last = index
	if last < 0: return
	var prefix: float = 0.0
	for index: int in range(last): prefix += float(heats[index])
	heats[last] = maxf(0.0, wanted - prefix)

static func _hottest(heats: Array) -> int:
	var chosen: int = -1
	var hottest: float = 0.0
	for index: int in range(3):
		if float(heats[index]) > hottest:
			chosen = index
			hottest = float(heats[index])
	return chosen

static func _summary_unchecked(state: Dictionary) -> Dictionary:
	return {"version":"ship-fire-r1", "heat":_total(state.heatByZone),
		"fuelSeconds":state.fuelSeconds, "wetness":state.wetness, "crewDamageCarry":state.crewDamageCarry,
		"assignedFirefighters":state.assignedFirefighters, "pendingFirefighters":state.pendingFirefighters,
		"transferTicks":state.transferTicks, "supplies":state.supplies, "workCarry":state.workCarry}

static func _from_legacy(base: Dictionary, heats: Array, exposure: Array) -> Dictionary:
	var state: Dictionary = base.duplicate(true)
	state.version = VERSION
	state.erase("heat")
	state.heatByZone = _heat_copy(heats)
	state.exposureTicks = _tick_copy(exposure)
	return state

static func _heat_copy(values: Array) -> Array:
	return [float(values[0]), float(values[1]), float(values[2])]

static func _tick_copy(values: Array) -> Array:
	return [int(values[0]), int(values[1]), int(values[2])]

static func _total(heats: Array) -> float:
	return float(heats[0]) + float(heats[1]) + float(heats[2])

static func _zone_index(zone: Variant) -> int:
	if typeof(zone) != TYPE_STRING: return -1
	return ZONES.find(zone)

static func _number_in(value: Variant, minimum: float, maximum: float) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

static func _integer_in(value: Variant, minimum: int, maximum: int) -> bool:
	return _number_in(value, float(minimum), float(maximum)) and floor(float(value)) == float(value)

static func _command_result(ok: bool, state: Variant, reason: String) -> Dictionary:
	return {"ok":ok, "state":state.duplicate(true) if typeof(state) == TYPE_DICTIONARY else {}, "reason":reason}

static func _rejected_step(state: Variant) -> Dictionary:
	return {"ok":false, "state":state.duplicate(true) if typeof(state) == TYPE_DICTIONARY else {},
		"damage":{"hull":0.0,"sail":0.0,"crew":0}, "reservedCrew":0, "extinguished":false,
		"workSeconds":0.0, "suppliesSpent":0, "spreadEvents":[]}
