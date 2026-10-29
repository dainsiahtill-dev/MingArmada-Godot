extends SceneTree

const RULES_PATH := "res://modules/naval_simulation/combat/fire_control.gd"
const PROFILE_PATH := "res://modules/naval_simulation/combat/fire_profile.gd"
var checks := 0
var failures := 0
var rules: Script

func _init() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		print("FAIL ship fire: ", label)
	return value

func near(actual: float, wanted: float, label: String, tolerance: float = 0.00000001) -> void:
	check(absf(actual - wanted) <= tolerance, label + " actual=" + str(actual) + " wanted=" + str(wanted))

func context() -> Dictionary:
	return {"able":20,"maxHull":1000.0,"maxSail":200.0,"maxCrew":1000,"rain01":0.0,"flammableLoad":0.0}

func burning(supplies: int = 0) -> Dictionary:
	var state: Dictionary = rules.initial(supplies)
	state.heat = 28.0
	state.fuelSeconds = 18.0
	return state

func rejected_step(state: Dictionary, input: Dictionary, label: String) -> void:
	var before := state.duplicate(true)
	var input_before := input.duplicate(true)
	var result: Dictionary = rules.step(state, input)
	check(not result.get("ok", true), label)
	check(_same_data(result.get("state", {}), before) and _same_data(state, before) and _same_data(input, input_before), label + " is atomic")
	check(result.get("damage", {}) == {"hull":0.0,"sail":0.0,"crew":0} and result.get("workSeconds", -1) == 0.0 and result.get("suppliesSpent", -1) == 0, label + " has no side effects")

func _same_data(left: Variant, right: Variant) -> bool:
	# Invalid-number fixtures still need an immutability check: NaN is not equal to itself.
	if typeof(left) != typeof(right):
		return false
	if typeof(left) == TYPE_FLOAT and is_nan(left):
		return is_nan(right)
	if typeof(left) == TYPE_DICTIONARY:
		if left.size() != right.size():
			return false
		for key: Variant in left:
			if not right.has(key) or not _same_data(left[key], right[key]):
				return false
		return true
	if typeof(left) == TYPE_ARRAY:
		if left.size() != right.size():
			return false
		for index in range(left.size()):
			if not _same_data(left[index], right[index]):
				return false
		return true
	return left == right

func _run() -> void:
	if not check(ResourceLoader.exists(RULES_PATH), "pure fire control module exists"):
		_finish()
		return
	if not check(ResourceLoader.exists(PROFILE_PATH), "versioned fire parameter profile exists"):
		_finish()
		return
	rules = load(RULES_PATH)
	for method: String in ["initial", "valid", "ignite", "assign", "reserved_crew", "step"]:
		if not check(rules != null and rules.has_method(method), "public pure method exists: " + method):
			_finish()
			return
	_initial_and_validation()
	_ignition_and_detachment()
	_transfer_and_population()
	_heat_integral_and_casualties()
	_supply_and_early_extinction()
	_invalid_commands()
	_finish()

func _initial_and_validation() -> void:
	var empty: Dictionary = rules.initial()
	check(empty == {"version":"ship-fire-r1","heat":0.0,"fuelSeconds":0.0,"wetness":0.0,"crewDamageCarry":0.0,"assignedFirefighters":0,"pendingFirefighters":0,"transferTicks":0,"supplies":0,"workCarry":0.0}, "initial contains the complete cold, empty state")
	check(rules.valid(empty) and rules.valid(rules.initial(600)), "both inventory boundaries are valid")
	check(rules.initial(-1).supplies == 0 and rules.initial(601).supplies == 600, "initial inventory cannot escape bounds")
	for value in [null, [], 1, true, "state"]:
		check(not rules.valid(value), "non-dictionary state rejected")
	for field: String in empty:
		var missing := empty.duplicate(true)
		missing.erase(field)
		check(not rules.valid(missing), "missing field rejected: " + field)
	var extra := empty.duplicate(true)
	extra.unownedState = 1
	check(not rules.valid(extra), "unknown state field rejected")
	for field: String in ["heat", "fuelSeconds", "wetness", "crewDamageCarry", "workCarry"]:
		for value in [true, false, null, "0", NAN, INF, -INF, -0.000001]:
			var malformed: Dictionary = rules.initial(1)
			malformed[field] = value
			check(not rules.valid(malformed), "invalid finite scalar rejected: " + field + "=" + str(value))
	for pair: Array in [["heat",100.000001],["fuelSeconds",72.000001],["wetness",1.000001],["crewDamageCarry",1.0],["workCarry",2.0]]:
		var malformed: Dictionary = rules.initial(1)
		malformed[pair[0]] = pair[1]
		check(not rules.valid(malformed), "upper scalar boundary rejected: " + pair[0])
	for field: String in ["assignedFirefighters", "pendingFirefighters", "transferTicks", "supplies"]:
		for value in [true, false, null, "0", 0.5, NAN, INF, -1]:
			var malformed: Dictionary = rules.initial()
			malformed[field] = value
			check(not rules.valid(malformed), "invalid discrete scalar rejected: " + field)
	for pair: Array in [["assignedFirefighters",129],["pendingFirefighters",129],["transferTicks",121],["supplies",601],["version","ship-fire-r2"]]:
		var malformed := empty.duplicate(true)
		malformed[pair[0]] = pair[1]
		check(not rules.valid(malformed), "state version or discrete bound rejected: " + pair[0])
	var impossible := empty.duplicate(true)
	impossible.workCarry = 0.1
	check(not rules.valid(impossible), "no fractional supply credit survives zero stock")
	var restored := empty.duplicate(true)
	for field: String in ["assignedFirefighters", "pendingFirefighters", "transferTicks", "supplies"]: restored[field] = 0.0
	check(rules.valid(restored), "JSON integer-valued numbers retain their discrete meaning")
	var result: Dictionary = rules.step(empty, context())
	check(result.ok and result.damage == {"hull":0.0,"sail":0.0,"crew":0} and result.workSeconds == 0.0 and not result.extinguished, "cold state neither ignites nor spends work")
	var residual := empty.duplicate(true)
	residual.fuelSeconds = 10.0
	check(rules.step(residual, context()).state == residual, "unburnt fuel cannot spontaneously ignite or consume fuel on a cold ship")

func _ignition_and_detachment() -> void:
	var initial: Dictionary = rules.initial(7)
	var before := initial.duplicate(true)
	var ordinary: Dictionary = rules.ignite(initial, "fire-ball", 0.0)
	var thorn: Dictionary = rules.ignite(initial, "thorn-ball", 0.0)
	check(ordinary.ok and ordinary.state.heat == 28.0 and ordinary.state.fuelSeconds == 18.0, "ordinary ignition starts finite candidate fire")
	check(thorn.ok and thorn.state.heat == 28.0 and thorn.state.fuelSeconds == 36.0, "thorn payload changes burn budget without inventing more initial heat")
	var wet: Dictionary = rules.ignite(initial, "fire-ball", 1.0)
	near(wet.state.heat, 11.2, "wet ignition reduces initial heat")
	near(wet.state.fuelSeconds, 10.8, "wet ignition reduces fuel")
	check(wet.state.wetness == 1.0, "ignition records declared vessel wetness")
	var still_wet: Dictionary = rules.ignite(wet.state, "fire-ball", 0.0)
	near(still_wet.state.heat, 22.4, "another impact cannot instantly dry an already wet deck")
	check(still_wet.state.wetness == 1.0, "only accepted simulation steps dry retained wetness")
	var repeated: Dictionary = rules.ignite(thorn.state, "thorn-ball", 0.0)
	check(repeated.state.heat == 56.0 and repeated.state.fuelSeconds == 72.0, "each real ignition adds finite heat and fuel")
	for i in range(5): repeated = rules.ignite(repeated.state, "thorn-ball", 0.0)
	check(repeated.state.heat == 100.0 and repeated.state.fuelSeconds == 72.0, "repeated impacts respect both caps")
	check(initial == before and ordinary == rules.ignite(initial, "fire-ball", 0.0), "ignition is immutable and replay deterministic")
	ordinary.state.supplies = 0
	ordinary.state.heat = 99.0
	check(initial == before and rules.ignite(initial, "fire-ball", 0.0).state.heat == 28.0, "returned ignition state is detached")
	var input := context()
	var state := burning(7)
	var state_before := state.duplicate(true)
	var input_before := input.duplicate(true)
	var stepped: Dictionary = rules.step(state, input)
	check(stepped == rules.step(state, input) and state == state_before and input == input_before, "step neither mutates inputs nor keeps hidden replay state")
	stepped.state.heat = 0.0
	stepped.damage.hull = 999.0
	check(state == state_before and rules.step(state, input).damage.hull < 1.0, "result damage and state cannot poison subsequent calls")

func _transfer_and_population() -> void:
	var state := burning(10)
	var assigned: Dictionary = rules.assign(state, 4, 20)
	check(assigned.ok and assigned.state.assignedFirefighters == 0 and assigned.state.pendingFirefighters == 4 and assigned.state.transferTicks == 120, "assignment schedules finite transfer")
	check(rules.reserved_crew(assigned.state, 20) == 4 and state.assignedFirefighters == 0, "travel reserves real people without mutating source")
	check(rules.assign(assigned.state, 4, 20).state == assigned.state, "repeated traveling assignment cannot restart its clock")
	var canceled: Dictionary = rules.assign(assigned.state, 0, 20)
	check(canceled.ok and canceled.state.assignedFirefighters == 4 and canceled.state.pendingFirefighters == 0 and canceled.state.transferTicks == 120 and rules.reserved_crew(canceled.state, 20) == 4, "canceling an outbound team still requires its people to return")
	state = assigned.state
	for i in range(120):
		var result: Dictionary = rules.step(state, context())
		check(result.ok and result.workSeconds == 0.0 and result.suppliesSpent == 0 and result.reservedCrew == 4, "entire transfer tick has zero firefighting: " + str(i + 1))
		state = result.state
	check(state.transferTicks == 0 and state.assignedFirefighters == 4 and state.pendingFirefighters == 4, "120 complete travel ticks arrive without early work")
	var working: Dictionary = rules.step(state, context())
	near(working.workSeconds, 1.0 / 15.0, "first working tick contains four sixtieths person-seconds")
	var repeat: Dictionary = rules.assign(state, 4, 20)
	check(repeat.ok and repeat.state == state, "same settled assignment does not send workers traveling again")
	var reducing: Dictionary = rules.assign(state, 2, 20)
	check(reducing.ok and reducing.state.transferTicks == 120 and rules.reserved_crew(reducing.state, 20) == 4, "reduction keeps old team reserved through return")
	var casualties := context()
	casualties.able = 1
	var clipped: Dictionary = rules.step(reducing.state, casualties)
	check(clipped.ok and clipped.reservedCrew == 1 and clipped.state.assignedFirefighters == 1 and clipped.state.pendingFirefighters == 1, "population loss clips both team endpoints rather than creating crew")
	check(rules.reserved_crew(reducing.state, 0) == 0, "no able population means no reservation")
	var waiting: Dictionary = rules.assign(rules.initial(10), 4, 20)
	state = waiting.state
	for i in range(121): state = rules.step(state, context()).state
	check(state.assignedFirefighters == 4 and state.transferTicks == 0 and state.supplies == 10 and state.workCarry == 0.0, "explicit cold standby occupies crew and spends no supplies")

func _heat_integral_and_casualties() -> void:
	var state := burning()
	var result: Dictionary = rules.step(state, context())
	near(result.state.heat, 28.03333333333333, "fixed 60 Hz integrates dry heat growth")
	near(result.state.fuelSeconds, 17.98333333333333, "one accepted step consumes one sixtieth fuel second")
	near(result.damage.hull, 0.03735555555555556, "hull damage uses heat integral rather than endpoint")
	near(result.damage.sail, 0.02054555555555556, "sail damage has separate declared coefficient")
	check(result.damage.crew == 0 and typeof(result.damage.crew) == TYPE_INT, "sub-person fire damage never kills a whole crew member")
	near(result.state.crewDamageCarry, 0.03735555555555556, "fractional crew damage remains in state")
	var flammable := context()
	flammable.flammableLoad = 1.0
	var loaded: Dictionary = rules.step(state, flammable)
	near(loaded.state.heat, 28.05833333333333, "flammable load raises only the declared heat growth rate")
	near(loaded.damage.hull, 0.03737222222222222, "flammable cargo influences the same heat integral")
	state.heat = 100.0
	var capped: Dictionary = rules.step(state, context())
	check(capped.state.heat == 100.0, "heat cap survives positive growth")
	near(capped.damage.hull, 0.13333333333333333, "heat above cap never contributes invisible damage")
	state = burning()
	state.heat = 60.0
	var total_crew := 0
	var total_hull := 0.0
	for i in range(30):
		result = rules.step(state, context())
		check(typeof(result.damage.crew) == TYPE_INT and result.damage.crew >= 0, "each crew debit remains a nonnegative integer")
		total_crew += result.damage.crew
		total_hull += result.damage.hull
		state = result.state
	check(total_crew == 2, "thirty small ticks kill only two accumulated people")
	near(state.crewDamageCarry, 0.42, "fractional casualty remainder persists across all ticks")
	near(total_hull, 2.42, "fixed-step damage equals independent half-second integral")
	near(float(total_crew) + state.crewDamageCarry, total_hull, "integer casualties plus carry conserve expected damage")
	var dying := burning()
	dying.heat = 100.0
	dying.crewDamageCarry = 0.99
	dying.assignedFirefighters = 4
	dying.pendingFirefighters = 4
	var last_crew := context()
	last_crew.able = 4
	var casualty: Dictionary = rules.step(dying, last_crew)
	check(casualty.damage.crew == 1 and casualty.state.assignedFirefighters == 3 and casualty.state.pendingFirefighters == 3 and casualty.reservedCrew == 3, "this tick's casualty clips its own returned reservation")
	last_crew.able = 0
	var empty_ship: Dictionary = rules.step(dying, last_crew)
	check(empty_ship.damage.crew == 0 and empty_ship.reservedCrew == 0 and empty_ship.state.assignedFirefighters == 0, "a dead crew cannot be killed or reserved twice")
	var rain := context()
	rain.rain01 = 1.0
	state = burning()
	var rained: Dictionary = rules.step(state, rain)
	near(rained.state.wetness, 1.0 / 600.0, "rain advances wetness before fire integration")
	near(rained.state.heat, 28.03316666666667, "rain enters fire once through updated wetness")
	var fuel_end := burning()
	fuel_end.fuelSeconds = 0.001
	var exhausted: Dictionary = rules.step(fuel_end, context())
	check(exhausted.extinguished and exhausted.state.heat == 0.0 and exhausted.state.fuelSeconds == 0.0, "fuel exhaustion extinguishes inside a tick")
	near(exhausted.damage.hull, 0.00224008, "fuel end charges only the burning millisecond")

func _supply_and_early_extinction() -> void:
	var input := context()
	input.rain01 = 1.0
	var state := burning(1)
	state.heat = 0.001
	state.wetness = 1.0
	state.assignedFirefighters = 4
	state.pendingFirefighters = 4
	var result: Dictionary = rules.step(state, input)
	check(result.ok and result.extinguished and result.state.heat == 0.0, "sufficient real work extinguishes inside a tick")
	near(result.state.fuelSeconds, 17.9999, "heat extinction retains its remaining unburnt fuel")
	near(result.workSeconds, 0.0004, "early extinction uses only 0.0001 seconds of four workers")
	near(result.damage.hull, 0.000000004, "early extinction integrates only its triangle of heat", 0.000000000001)
	check(result.suppliesSpent == 0 and result.state.supplies == 1, "partial preparation use does not round up to a full debit")
	near(result.state.workCarry, 0.0004, "partial preparation use is retained as spent person-seconds")
	check(result.state.pendingFirefighters == 0 and result.state.transferTicks == 120 and result.reservedCrew == 4, "extinguished team must return for 120 ticks")
	state = result.state
	var previous_supply: int = state.supplies
	for i in range(120):
		result = rules.step(state, input)
		check(result.workSeconds == 0.0 and result.suppliesSpent == 0, "return trip cannot bill firefighting")
		state = result.state
	check(state.assignedFirefighters == 0 and state.pendingFirefighters == 0 and state.transferTicks == 0 and state.supplies == previous_supply, "return completes without losing or duplicating people or stock")
	state = burning(1)
	state.heat = 1.0
	state.wetness = 1.0
	state.assignedFirefighters = 4
	state.pendingFirefighters = 4
	state.workCarry = 1.99
	result = rules.step(state, input)
	near(result.workSeconds, 0.01, "last partial preparation caps actual person-seconds")
	check(result.suppliesSpent == 1 and result.state.supplies == 0 and result.state.workCarry == 0.0, "last preparation is spent exactly once with no remaining free credit")
	near(result.state.heat, 0.9183333333333333, "fire continues naturally after within-tick supply exhaustion")
	near(result.damage.hull, 0.001270388888888889, "supply exhaustion splits suppression and unsuppressed integrals")
	var dry: Dictionary = rules.step(result.state, input)
	check(dry.workSeconds == 0.0 and dry.suppliesSpent == 0 and dry.state.supplies == 0, "empty inventory never produces free work")
	state = burning(2)
	state.assignedFirefighters = 4
	state.pendingFirefighters = 4
	var total_work := 0.0
	var total_spent := 0
	for i in range(120):
		result = rules.step(state, context())
		total_work += result.workSeconds
		total_spent += result.suppliesSpent
		check(rules.valid(result.state), "long resource exhaustion remains inside state domain")
		state = result.state
	near(total_work, 4.0, "two preparations support exactly four person-seconds")
	check(total_spent == 2 and state.supplies == 0 and state.workCarry == 0.0, "long resource ledger conserves both preparations")

func _invalid_commands() -> void:
	var state := burning(7)
	var before := state.duplicate(true)
	for payload in ["", "solid", "unknown", true, null, 7]:
		var result: Dictionary = rules.ignite(state, payload, 0.0)
		check(not result.get("ok", true) and result.state == before and state == before, "invalid payload rejected atomically")
	for wetness in [-0.01, 1.01, true, null, NAN, INF]:
		check(not rules.ignite(state, "fire-ball", wetness).get("ok", true), "invalid ignition wetness rejected")
	for crew in [-1, 129, 21, 1.5, true, null, NAN, INF]:
		var result: Dictionary = rules.assign(state, crew, 20)
		check(not result.get("ok", true) and result.state == before, "invalid or unavailable worker assignment rejected")
	for able in [-1, true, 1.5, null, NAN, INF]:
		check(not rules.assign(state, 1, able).get("ok", true) and rules.reserved_crew(state, able) == 0, "invalid able count neither assigns nor reserves people")
	for field: String in context():
		var missing := context()
		missing.erase(field)
		rejected_step(state, missing, "missing context field rejected: " + field)
	for field: String in ["maxHull", "maxSail", "rain01", "flammableLoad"]:
		for value in [true, null, NAN, INF, -0.01]:
			var malformed := context()
			malformed[field] = value
			rejected_step(state, malformed, "invalid context number rejected: " + field)
	for pair: Array in [["able",-1],["able",true],["able",1.5],["maxCrew",0],["maxCrew",true],["maxCrew",1.5],["maxHull",0.0],["maxSail",0.0],["rain01",1.01],["flammableLoad",1.01]]:
		var malformed := context()
		malformed[pair[0]] = pair[1]
		rejected_step(state, malformed, "context range or integer constraint rejected: " + pair[0])
	var malformed := before.duplicate(true)
	malformed.heat = -1.0
	check(not rules.ignite(malformed, "fire-ball", 0.0).get("ok", true) and not rules.assign(malformed, 1, 20).get("ok", true) and rules.reserved_crew(malformed, 20) == 0, "invalid state cannot enter other public operations")
	rejected_step(malformed, context(), "invalid state cannot advance")

func _finish() -> void:
	print("SHIP_FIRE_CONTROL_TEST_COMPLETE checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
