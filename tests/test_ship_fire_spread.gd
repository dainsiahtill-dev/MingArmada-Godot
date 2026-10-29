extends SceneTree
## H5 contract: one r1 fire account, three conserved coarse heat shares.
## The missing-module guard must produce a clean RED before implementation.
const PATH := "res://modules/naval_simulation/combat/fire_spread.gd"
const Fire = preload("res://modules/naval_simulation/combat/fire_control.gd")
const STEP := 1.0 / 60.0
var rules: Script
var checks := 0
var failures := 0

func _init() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ship fire spread: ", label)
	return ok
func near(actual: float, wanted: float, label: String, tolerance: float = 1e-8) -> void:
	check(absf(actual - wanted) <= tolerance, label + " actual=" + str(actual) + " wanted=" + str(wanted))
func context() -> Dictionary:
	return {"able":20,"maxHull":1000.0,"maxSail":200.0,"maxCrew":1000,"rain01":0.0,"flammableLoad":0.0}
func total(state: Dictionary) -> float:
	return float(state.heatByZone[0]) + float(state.heatByZone[1]) + float(state.heatByZone[2])
func burning(heats: Array, fuel: float = 18.0, supplies: int = 0) -> Dictionary:
	var state: Dictionary = rules.initial(supplies)
	state.heatByZone = heats.duplicate()
	state.fuelSeconds = fuel
	return state
func legacy(state: Dictionary) -> Dictionary:
	# Independent oracle input; do not use the candidate summary to build expectations.
	return {"version":"ship-fire-r1","heat":total(state),"fuelSeconds":state.fuelSeconds,
		"wetness":state.wetness,"crewDamageCarry":state.crewDamageCarry,
		"assignedFirefighters":state.assignedFirefighters,"pendingFirefighters":state.pendingFirefighters,
		"transferTicks":state.transferTicks,"supplies":state.supplies,"workCarry":state.workCarry}
func compare_step(state: Dictionary, input: Dictionary, label: String) -> Dictionary:
	var before := state.duplicate(true)
	var input_before := input.duplicate(true)
	var expected: Dictionary = Fire.step(legacy(state), input)
	var actual: Dictionary = rules.step(state, input)
	if not check(actual.get("ok", false), label + ": accepted"):
		return state
	check(state == before and input == input_before, label + ": source data immutable")
	check(rules.valid(actual.state), label + ": resulting r2 state valid")
	var summary: Dictionary = rules.summary(actual.state)
	check(Fire.valid(summary), label + ": summary is strict r1")
	for key: String in ["heat", "fuelSeconds", "wetness", "crewDamageCarry", "workCarry"]:
		near(float(summary[key]), float(expected.state[key]), label + ": r1 state " + key)
	for key: String in ["assignedFirefighters", "pendingFirefighters", "transferTicks", "supplies"]:
		check(summary[key] == expected.state[key], label + ": r1 state " + key)
	for key: String in ["hull", "sail", "crew"]:
		near(float(actual.damage[key]), float(expected.damage[key]), label + ": r1 damage " + key)
	near(float(actual.workSeconds), float(expected.workSeconds), label + ": r1 work")
	check(actual.suppliesSpent == expected.suppliesSpent and actual.reservedCrew == expected.reservedCrew and actual.extinguished == expected.extinguished, label + ": single r1 accounting result")
	check(actual.get("spreadEvents") is Array, label + ": explicit spread event list")
	return actual.state

func _run() -> void:
	if not check(ResourceLoader.exists(PATH), "pure fire spread module exists"):
		_finish(); return
	rules = load(PATH)
	for method: String in ["initial", "valid", "summary", "ignite", "assign", "reserved_crew", "step"]:
		if not check(rules != null and rules.has_method(method), "public pure method exists: " + method):
			_finish(); return
	_validation()
	_ignition_and_detachment()
	_heat_share_allocation()
	_spread_boundaries()
	_shared_work_and_oracle()
	_cold_and_fuel_end()
	_finish()

func _validation() -> void:
	var empty: Dictionary = rules.initial()
	var wanted := {"version":"ship-fire-r2-zones","heatByZone":[0.0,0.0,0.0],"exposureTicks":[0,0,0],
		"fuelSeconds":0.0,"wetness":0.0,"crewDamageCarry":0.0,"assignedFirefighters":0,
		"pendingFirefighters":0,"transferTicks":0,"supplies":0,"workCarry":0.0}
	check(empty == wanted and empty.size() == 11, "exact eleven fields without heat or auto policy")
	check(rules.valid(empty) and rules.valid(rules.initial(600)), "inventory boundary states valid")
	check(not Fire.valid(empty), "r1 validator does not accept r2")
	check(rules.summary(empty) == Fire.initial(), "cold summary contains exact r1 ten fields")
	check(rules.initial(-1).supplies == 0 and rules.initial(601).supplies == 600, "initial inventory clamps to existing limits")
	for value: Variant in [null, [], true, 1, "state"]:
		check(not rules.valid(value), "non-dictionary rejected")
	for key: String in wanted:
		var missing := empty.duplicate(true)
		missing.erase(key)
		check(not rules.valid(missing), "missing field rejected: " + key)
	for key: String in ["heat", "autoEnabled", "unknown"]:
		var extra := empty.duplicate(true)
		extra[key] = 0
		check(not rules.valid(extra), "extra field rejected: " + key)
	for key: String in ["heatByZone", "exposureTicks"]:
		for value: Variant in [null, {}, [], [0,0], [0,0,0,0], PackedFloat64Array([0,0,0])]:
			var malformed := empty.duplicate(true)
			malformed[key] = value
			check(not rules.valid(malformed), "exact Array3 required: " + key)
		for value: Variant in [true, false, null, "0", NAN, INF, -1.0]:
			var malformed := empty.duplicate(true)
			malformed[key][1] = value
			check(not rules.valid(malformed), "invalid zone scalar rejected: " + key)
	for pair: Array in [["heatByZone",[40.0,40.0,20.0001]],["exposureTicks",[0,0.5,0]],["exposureTicks",[0,361,0]]]:
		var malformed := empty.duplicate(true)
		malformed[pair[0]] = pair[1]
		check(not rules.valid(malformed), "zone bound rejected")
	for key: String in ["fuelSeconds", "wetness", "crewDamageCarry", "workCarry", "assignedFirefighters", "pendingFirefighters", "transferTicks", "supplies"]:
		for value: Variant in [true, null, "0", NAN, INF, -1]:
			var malformed := empty.duplicate(true)
			malformed[key] = value
			check(not rules.valid(malformed), "invalid existing scalar rejected: " + key)
	for pair: Array in [["fuelSeconds",72.01],["wetness",1.01],["crewDamageCarry",1.0],["workCarry",2.0],["assignedFirefighters",129],["pendingFirefighters",129],["transferTicks",121],["supplies",601],["supplies",1.5],["version","ship-fire-r1"]]:
		var malformed: Dictionary = rules.initial(1)
		malformed[pair[0]] = pair[1]
		check(not rules.valid(malformed), "existing scalar bound rejected: " + str(pair[0]))
	var impossible := empty.duplicate(true)
	impossible.workCarry = 0.1
	check(not rules.valid(impossible), "no work credit with zero supplies")
	check(rules.valid(JSON.parse_string(JSON.stringify(empty))), "JSON integer-valued counts remain valid")

func _ignition_and_detachment() -> void:
	var source: Dictionary = rules.initial(24)
	var before := source.duplicate(true)
	for pair: Array in [["bow",[28.0,0.0,0.0]],["mid",[0.0,28.0,0.0]],["stern",[0.0,0.0,28.0]]]:
		var result: Dictionary = rules.ignite(source, "fire-ball", 0.0, pair[0])
		check(result.ok and result.state.heatByZone == pair[1] and result.state.fuelSeconds == 18.0, "real impact heats only " + str(pair[0]))
		result.state.heatByZone[0] = 99.0
		check(source == before, "ignition output detached")
	var wet: Dictionary = rules.ignite(source, "thorn-ball", 1.0, "stern")
	near(total(wet.state), 11.2, "wet impact accepts r1 heat")
	near(wet.state.fuelSeconds, 21.6, "wet thorn accepts r1 fuel")
	for zone: String in ["", "Bow", "port", "bow "]:
		var rejected: Dictionary = rules.ignite(source, "fire-ball", 0.0, zone)
		check(not rejected.ok and rejected.state == before and source == before, "unknown zone rejected atomically")
	var capped := burning([70.0,20.0,0.0], 70.0)
	capped.exposureTicks = [0,0,359]
	var cap: Dictionary = rules.ignite(capped, "thorn-ball", 0.0, "stern")
	check(cap.ok and cap.state.heatByZone == [70.0,20.0,10.0] and cap.state.fuelSeconds == 72.0 and cap.state.exposureTicks[2] == 0, "only accepted delta enters impact zone and clears its exposure")
	check(capped.heatByZone == [70.0,20.0,0.0] and capped.exposureTicks[2] == 359, "capped ignition preserves source arrays")
	var summary: Dictionary = rules.summary(capped)
	summary.heat = 0.0
	check(total(capped) == 90.0, "summary is derived detached data")
	check(not rules.ignite(source, "round", 0.0, "bow").ok and not rules.ignite(source, "fire-ball", true, "bow").ok, "old payload and numeric validation preserved")

func _heat_share_allocation() -> void:
	var raised: Dictionary = rules.step(burning([20.0,40.0,0.0]), context())
	near(raised.state.heatByZone[0], 20.0 + STEP, "positive delta evenly reaches first active zone")
	near(raised.state.heatByZone[1], 40.0 + STEP, "positive delta evenly reaches second active zone")
	check(raised.state.heatByZone[2] == 0.0, "natural growth cannot ignite cold zone")
	var tied := burning([20.0,20.0,0.0], 18.0, 24)
	tied.assignedFirefighters = 4; tied.pendingFirefighters = 4
	var lowered: Dictionary = rules.step(tied, context())
	near(lowered.state.heatByZone[0], 20.0 - 4.0 * STEP, "negative delta removes from bow first on heat tie")
	near(lowered.state.heatByZone[1], 20.0, "same cooling is not applied to every zone")
	var hottest := burning([20.0,30.0,10.0], 18.0, 24)
	hottest.assignedFirefighters = 4; hottest.pendingFirefighters = 4
	var cooled: Dictionary = rules.step(hottest, context())
	near(cooled.state.heatByZone[1], 30.0 - 4.0 * STEP, "hottest zone receives single cooling delta")
	check(cooled.state.heatByZone[0] == 20.0 and cooled.state.heatByZone[2] == 10.0, "cooling preserves other zones until hottest exhausted")
	var overflow := burning([0.03,0.03,0.03], 18.0, 24)
	overflow.assignedFirefighters = 4; overflow.pendingFirefighters = 4
	var remainder: Dictionary = rules.step(overflow, context())
	check(remainder.state.heatByZone[0] == 0.0 and remainder.state.heatByZone[1] == 0.0, "cooling exhausts tied hottest zones in fixed bow then mid order")
	near(remainder.state.heatByZone[2], 0.09 - 4.0 * STEP, "remaining negative delta reaches next zone without losing heat accounting")

func _spread_boundaries() -> void:
	var state := burning([28.0,0.0,0.0])
	var early_events := 0
	for _tick in range(359):
		var result: Dictionary = rules.step(state, context())
		early_events += result.spreadEvents.size()
		state = result.state
	check(early_events == 0 and state.heatByZone[1] == 0.0 and state.exposureTicks[1] == 359, "359 complete qualifying ticks cannot spread")
	var spread: Dictionary = rules.step(state, context())
	check(spread.spreadEvents.size() == 1 and spread.state.heatByZone[2] == 0.0, "tick 360 ignites only adjacent mid")
	near(spread.state.heatByZone[0], 28.0, "source pays twelve heat")
	near(spread.state.heatByZone[1], 12.0, "target receives twelve heat")
	near(spread.state.fuelSeconds, 12.0, "spread adds no fuel")
	var both := burning([0.0,60.0,0.0], 30.0)
	both.exposureTicks = [359,0,359]
	var dual: Dictionary = rules.step(both, context())
	check(dual.spreadEvents.size() == 2 and dual.state.heatByZone[0] == 12.0 and dual.state.heatByZone[2] == 12.0, "mid can spread to two adjacent cold zones with one budget")
	near(total(dual.state), 60.0 + 2.0 * STEP, "two targets do not create heat")
	near(dual.state.fuelSeconds, 30.0 - STEP, "two targets do not create fuel")
	var donors := burning([40.0,0.0,60.0], 30.0)
	donors.exposureTicks = [0,359,0]
	var strongest: Dictionary = rules.step(donors, context())
	check(strongest.state.heatByZone == [40.0,12.0,48.0], "cold mid takes twelve from strongest qualifying neighbor")
	var ties := burning([40.0,0.0,40.0], 30.0)
	ties.exposureTicks = [0,359,0]
	var first: Dictionary = rules.step(ties, context())
	near(first.state.heatByZone[0], 28.0 + STEP, "donor tie chooses bow")
	near(first.state.heatByZone[2], 40.0 + STEP, "donor tie leaves stern unchanged")
	var chain := burning([60.0,0.0,0.0], 30.0)
	chain.exposureTicks = [0,359,359]
	var one_hop: Dictionary = rules.step(chain, context())
	check(one_hop.spreadEvents.size() == 1 and one_hop.state.heatByZone[2] == 0.0 and one_hop.state.exposureTicks[2] == 0, "newly ignited mid cannot relay to stern in same tick")
	var below := burning([23.99,0.0,0.0])
	below.exposureTicks = [0,359,0]
	var crossed: Dictionary = rules.step(below, context())
	check(crossed.spreadEvents.is_empty() and crossed.state.exposureTicks[1] == 0, "source crossing threshold only at interval end resets exposure")
	var suppressed := burning([24.01,0.0,0.0], 18.0, 24)
	suppressed.exposureTicks = [0,359,0]
	suppressed.assignedFirefighters = 4; suppressed.pendingFirefighters = 4
	var stopped: Dictionary = rules.step(suppressed, context())
	check(stopped.spreadEvents.is_empty() and stopped.state.exposureTicks[1] == 0, "source below threshold at interval end resets exposure")

func _shared_work_and_oracle() -> void:
	var source := burning([28.0,0.0,0.0], 18.0, 24)
	var before := source.duplicate(true)
	var assigned: Dictionary = rules.assign(source, 4, 20)
	check(assigned.ok and source == before and rules.reserved_crew(assigned.state, 20) == 4, "assignment occupies one real team without editing input")
	var state: Dictionary = assigned.state
	var transfer_work := 0.0
	for _tick in range(120):
		var result: Dictionary = rules.step(state, context())
		transfer_work += result.workSeconds
		state = result.state
	check(transfer_work == 0.0 and state.transferTicks == 0 and state.assignedFirefighters == 4 and state.supplies == 24, "120 complete transfer ticks perform no work")
	var working: Dictionary = rules.step(state, context())
	near(working.workSeconds, 4.0 * STEP, "tick 121 performs exactly four-person work")
	check(rules.assign(state, 4, 20).state == state, "same target does not restart transfer")
	check(not rules.assign(state, 21, 20).ok and not rules.assign(state, true, 20).ok, "assignment retains old headcount validation")
	var shared := burning([12.0,16.0,20.0], 18.0, 24)
	shared.assignedFirefighters = 4; shared.pendingFirefighters = 4
	var once: Dictionary = rules.step(shared, context())
	near(once.workSeconds, 4.0 * STEP, "three burning zones share one work charge")
	near(once.damage.hull, 0.06395555555555556, "three zones cause one heat-area hull loss")
	near(once.damage.sail, 0.03517555555555556, "three zones cause one heat-area sail loss")
	near(once.state.fuelSeconds, 18.0 - STEP, "three zones consume one fuel clock")
	var cases: Array = [burning([28.0,0.0,0.0],36.0), assigned.state, shared]
	for index in range(cases.size()):
		var current: Dictionary = cases[index]
		for accepted_tick in range(720):
			current = compare_step(current, context(), "oracle %d tick %d" % [index,accepted_tick + 1])
	var scarce := burning([0.0,40.0,0.0], 2.0, 1)
	scarce.assignedFirefighters = 8; scarce.pendingFirefighters = 8; scarce.workCarry = 1.99
	compare_step(scarce, context(), "partial-tick supply exhaustion")
	var bad_context := context()
	bad_context.able = true
	var rejected: Dictionary = rules.step(shared, bad_context)
	check(not rejected.ok and rejected.state == shared and rejected.workSeconds == 0.0 and rejected.spreadEvents.is_empty(), "invalid context rejects atomically without work or spread")

func _cold_and_fuel_end() -> void:
	var cold: Dictionary = rules.initial(24)
	cold.fuelSeconds = 10.0; cold.exposureTicks = [359,359,359]
	var result: Dictionary = rules.step(cold, context())
	check(result.state.heatByZone == [0.0,0.0,0.0] and result.state.exposureTicks == [0,0,0] and result.state.fuelSeconds == 10.0, "cold residual fuel never ignites and clears exposure")
	check(result.damage == {"hull":0.0,"sail":0.0,"crew":0} and result.workSeconds == 0.0 and result.state.supplies == 24, "cold state never damages or spends supplies")
	var ending := burning([40.0,0.0,0.0], STEP / 2.0, 24)
	ending.exposureTicks = [0,359,0]
	var end: Dictionary = rules.step(ending, context())
	check(end.state.fuelSeconds == 0.0 and end.state.heatByZone == [0.0,0.0,0.0] and end.state.exposureTicks == [0,0,0] and end.spreadEvents.is_empty(), "fuel exhaustion clears all shares before a due spread")
	near(end.damage.hull, 0.02667222222222222, "half-tick fuel earns only half-tick integrated damage")
	var weak := burning([0.01,0.02,0.03], 18.0, 24)
	weak.assignedFirefighters = 4; weak.pendingFirefighters = 4
	var extinguished: Dictionary = rules.step(weak, context())
	check(extinguished.extinguished and extinguished.state.heatByZone == [0.0,0.0,0.0] and extinguished.state.pendingFirefighters == 0 and extinguished.state.transferTicks == 120, "early heat extinction preserves existing automatic return")
	var detached_before := weak.duplicate(true)
	extinguished.state.heatByZone[0] = 99.0
	extinguished.state.exposureTicks[1] = 99
	check(weak == detached_before, "step result arrays are detached from source")

func _finish() -> void:
	print("SHIP_FIRE_SPREAD_TEST_COMPLETE checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
