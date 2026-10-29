extends SceneTree
## Pure accepted-interval accounting. Native/Campaign handoff is a separate gate.
const RULES_PATH := "res://modules/naval_simulation/combat/crew_work.gd"
const FireControl = preload("res://modules/naval_simulation/combat/fire_control.gd")
const Launcher = preload("res://modules/naval_simulation/combat/fire_launcher.gd")
const STEP := 1.0 / 60.0
var rules: Script
var assertions := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> bool:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL CREW WORK: ", label)
	return value

func near(actual: float, expected: float, label: String) -> void:
	check(absf(actual - expected) <= 0.00000001, label + " actual=" + str(actual))

func finish() -> void:
	print("CREW_WORK_ACCOUNTING_TESTS assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures else 0)

func input(able: Variant = 100, launcher: Variant = 0, fire: Variant = 0, operational: Variant = true) -> Dictionary:
	return {"shipId":"p", "able":able, "launcherCrew":launcher, "fireDutyCrew":fire, "operational":operational, "position":{"x":2.0,"z":-3.0}, "velocity":{"x":4.0,"z":-5.0}, "hull":100.0}

func context(able: int) -> Dictionary:
	return {"able":able,"maxHull":100.0,"maxSail":100.0,"maxCrew":100,"rain01":0.0,"flammableLoad":0.0}

func row(able: int = 100, launcher: int = 0, fire: int = 0) -> Dictionary:
	return rules.sample(input(able, launcher, fire)).row

func rejected_sample(value: Dictionary, label: String) -> void:
	var before := var_to_bytes(value)
	var result: Dictionary = rules.sample(value)
	check(not result.get("ok", true) and not str(result.get("reason", "")).is_empty(), "reject sample: " + label)
	check(var_to_bytes(value) == before, "sample rejection preserves input: " + label)

func rejected_accumulate(carry: Dictionary, attackers: Dictionary, defenders: Variant, label: String) -> void:
	var before := var_to_bytes(carry)
	var attackers_before := var_to_bytes(attackers)
	var result: Dictionary = rules.accumulate(carry, attackers, defenders)
	check(not result.get("ok", true) and result.get("pulse", {}) == {} and not str(result.get("reason", "")).is_empty(), "reject accumulation: " + label)
	check(var_to_bytes(carry) == before and var_to_bytes(attackers) == attackers_before, "accumulation rejection is atomic: " + label)

func run() -> void:
	# A valid RED reports the missing feature, rather than a preload/parser error.
	if not check(ResourceLoader.exists(RULES_PATH), "CREW_WORK_MODULE_MISSING: pure accepted-tick labour accounting exists"):
		finish(); return
	rules = load(RULES_PATH)
	if not check(rules != null, "pure crew-work module loads"):
		finish(); return
	_test_samples()
	_test_rows_and_batches()
	_test_carry()
	_test_launcher_boundary()
	_test_transfer_boundary()
	_test_quench_return_boundary()
	_test_casualty_boundary()
	finish()

func _test_samples() -> void:
	var value := input(100, 4, 8)
	var before := value.duplicate(true)
	var sampled: Dictionary = rules.sample(value)
	if not check(sampled.get("ok", false), "real sample accepts disjoint launcher/fire/available crew"):
		return
	var wanted := {"shipId":"p","totalAbleAtStart":100,"totalAbleAtEnd":100,"launcherCrew":4,"fireDutyCrew":8,"availableCrew":88,"unavailableCrew":0,"position":{"x":2.0,"z":-3.0},"velocity":{"x":4.0,"z":-5.0},"hullAtStart":100.0}
	check(sampled.keys().size() == 3 and sampled.has_all(["ok","row","reason"]) and sampled.row == wanted, "sample exposes exact start-of-interval account with 88 free people")
	check(value == before and rules.valid_row(sampled.row), "successful sample preserves input and validates")
	sampled.row.position.x = 999.0
	check(value.position.x == 2.0, "sample deeply separates mutable position")
	var stopped: Dictionary = rules.sample(input(100, 4, 8, false))
	check(stopped.ok and stopped.row.availableCrew == 0 and stopped.row.unavailableCrew == 88 and stopped.row.launcherCrew == 4 and stopped.row.fireDutyCrew == 8, "non-operational ship retains duty reservations while 88 remaining crew cannot board")
	check(rules.sample(input(0)).row.availableCrew == 0, "zero population yields zero labour")
	check(rules.sample(input(6, 4, 2)).row.availableCrew == 0, "launcher-first six-person budget cannot double-book residual fire crew")
	var restored: Dictionary = rules.sample(input(100.0, 4.0, 8.0))
	check(restored.ok and restored.row.totalAbleAtStart is int and restored.row.launcherCrew is int and restored.row.fireDutyCrew is int, "integral JSON numbers normalize into integer crew accounts")
	var unicode := input(); unicode.shipId = "福船-甲"
	check(rules.sample(unicode).ok, "stable Unicode ship IDs are legal")
	for fixture: Dictionary in [{"able":true},{"able":-1},{"able":1.5},{"able":1001},{"able":NAN},{"able":INF},{"launcherCrew":5},{"launcherCrew":true},{"fireDutyCrew":129},{"fireDutyCrew":0.5},{"operational":1},{"hull":-0.01},{"hull":NAN},{"hull":INF},{"shipId":""},{"shipId":"x".repeat(257)},{"position":{"x":1.0,"z":0.0,"y":0.0}},{"position":{"x":NAN,"z":0.0}},{"velocity":{"x":0.0}},{"velocity":{"x":0.0,"z":true}}]:
		var invalid := input(); invalid.merge(fixture, true)
		rejected_sample(invalid, str(fixture.keys()[0]))
	rejected_sample(input(5, 4, 2), "total duty exceeds actual living crew")
	var unknown := input(); unknown.extra = 1
	rejected_sample(unknown, "unknown input field")
	var missing := input(); missing.erase("able")
	rejected_sample(missing, "missing input field")

func _test_rows_and_batches() -> void:
	var sampled := row(100, 4, 8)
	var before := sampled.duplicate(true)
	var ended: Dictionary = rules.finish_row(sampled, 97)
	check(ended.ok and ended.row.totalAbleAtStart == 100 and ended.row.totalAbleAtEnd == 97 and ended.row.availableCrew == 88, "right-boundary casualties do not rewrite already accepted labour")
	check(sampled == before and rules.valid_row(ended.row), "finishing preserves original row and budget conservation")
	ended.row.velocity.z = 99.0
	check(sampled.velocity.z == -5.0, "finish_row deeply separates geometry")
	for invalid_end: Variant in [-1, 101, true, 0.5, NAN, INF]:
		var result: Dictionary = rules.finish_row(sampled, invalid_end)
		check(not result.get("ok", true) and sampled == before, "finish_row rejects invalid/reviving population atomically")
	for patch: Dictionary in [{"totalAbleAtEnd":101},{"availableCrew":89},{"unavailableCrew":1},{"launcherCrew":5},{"fireDutyCrew":129},{"position":{"x":2.0,"z":-3.0,"y":0.0}},{"hullAtStart":-1.0},{"shipId":""}]:
		var malformed := sampled.duplicate(true); malformed.merge(patch, true)
		check(not rules.valid_row(malformed), "row rejects malformed conservation/domain: " + str(patch.keys()[0]))
	var extra := sampled.duplicate(true); extra.extra = true
	check(not rules.valid_row(extra), "row rejects unknown keys")
	var mixed := sampled.duplicate(true); mixed.availableCrew = 44; mixed.unavailableCrew = 44
	check(not rules.valid_row(mixed), "row rejects mixed availability that neither operational state can produce")
	var missing := sampled.duplicate(true); missing.erase("availableCrew")
	check(not rules.valid_row(missing) and not rules.valid_row(null), "row rejects missing keys and non-dictionaries")
	var rows := [sampled]
	var batch: Dictionary = rules.batch("海战-epoch", 120, rows)
	if not check(batch.get("ok", false), "batch binds accepted rows to battle and tick"):
		return
	check(batch.receipt.keys().size() == 5 and batch.receipt.has_all(["version","battleId","tick","stepSeconds","ships"]), "receipt exposes exact five-field transient contract")
	check(batch.receipt.version == "crew-work-r1" and batch.receipt.battleId == "海战-epoch" and batch.receipt.tick == 120 and batch.receipt.stepSeconds == STEP and rules.valid(batch.receipt), "receipt retains actual epoch, tick and fixed interval")
	var restored_batch: Dictionary = rules.batch("b", 120.0, rows)
	check(restored_batch.ok and restored_batch.receipt.tick is int and restored_batch.receipt.tick == 120, "batch normalizes integral JSON tick values")
	batch.receipt.ships[0].position.x = 999.0
	check(rows[0].position.x == 2.0, "batch deeply separates every row")
	var receipt: Dictionary = rules.batch("b", 1, rows).receipt
	var restored_receipt := receipt.duplicate(true); restored_receipt.tick = 1.0
	check(rules.valid(restored_receipt), "receipt validator accepts integral JSON tick values")
	for patch: Dictionary in [{"version":"other"},{"battleId":""},{"battleId":"b".repeat(4097)},{"tick":0},{"tick":true},{"tick":1.5},{"stepSeconds":STEP + 0.000001},{"ships":[sampled,sampled]}]:
		var invalid := receipt.duplicate(true); invalid.merge(patch, true)
		check(not rules.valid(invalid), "receipt rejects invalid identity/time/rows: " + str(patch.keys()[0]))
	var extra_receipt := receipt.duplicate(true); extra_receipt.extra = 0
	check(not rules.valid(extra_receipt) and not rules.valid(null), "receipt rejects unknown keys and non-dictionaries")
	for args: Array in [["",1,rows],["b",0,rows],["b",1,[sampled,sampled]]]:
		var source_before := var_to_bytes(args)
		check(not rules.batch(args[0], args[1], args[2]).get("ok", true) and var_to_bytes(args) == source_before, "invalid batch rejects atomically")
	var crowded: Array = []
	for i in 129:
		var item := sampled.duplicate(true); item.shipId = "ship-" + str(i); crowded.append(item)
	check(not rules.batch("b", 1, crowded).get("ok", true), "receipt rejects more than 128 unique ships")
	crowded.resize(128)
	check(rules.batch("b", 1, crowded).ok, "receipt accepts declared 128-ship capacity")

func _test_carry() -> void:
	var carry: Dictionary = rules.initial_carry()
	check(carry == {"version":"crew-work-r1","ticks":0,"attackerPersonTicksByShip":{},"defenderPersonTicks":0} and rules.valid_carry(carry), "fresh carry starts no invented historical work")
	var initial := carry.duplicate(true)
	var first: Dictionary = rules.accumulate(carry, {"甲":96,"乙":4}, 80)
	check(first.ok and first.pulse == {} and first.carry.ticks == 1 and first.carry.attackerPersonTicksByShip == {"甲":96,"乙":4} and first.carry.defenderPersonTicks == 80, "one accepted tick records ship-bound person-ticks without an early pulse")
	check(carry == initial, "successful accumulation does not mutate earlier carry")
	carry = first.carry
	for _i in 58: carry = rules.accumulate(carry, {"甲":96,"乙":4}, 80).carry
	check(carry.ticks == 59 and carry.attackerPersonTicksByShip == {"甲":5664,"乙":236} and carry.defenderPersonTicks == 4720, "59 accepted ticks remain unconsumed with exact integer totals")
	var last: Dictionary = rules.accumulate(carry, {"甲":96,"乙":4}, 80)
	check(last.ok and last.pulse.ticks == 60 and last.pulse.attackerPersonTicksByShip == {"甲":5760,"乙":240} and last.pulse.defenderPersonTicks == 4800, "tick60 emits exact ship-bound integer window")
	near(float(last.pulse.attackers), 100.0, "pulse converts complete attacker person-ticks to person-seconds")
	near(float(last.pulse.defenders), 80.0, "pulse converts complete defender person-ticks to person-seconds")
	check(last.carry == initial and carry.ticks == 59, "complete window resets returned carry without erasing caller history")
	last.pulse.attackerPersonTicksByShip["甲"] = 0
	check(carry.attackerPersonTicksByShip["甲"] == 5664, "pulse and prior carry own different mutable maps")
	var high: Dictionary = rules.initial_carry()
	var high_result: Dictionary = rules.accumulate(high, {"甲":1000,"乙":1000}, 1000)
	check(high_result.ok and high_result.carry.attackerPersonTicksByShip == {"甲":1000,"乙":1000}, "per-ship population limit does not cap a two-ship fleet at 1000")
	var restored := {"version":"crew-work-r1","ticks":1.0,"attackerPersonTicksByShip":{"p":96.0},"defenderPersonTicks":80.0}
	var normalized: Dictionary = rules.accumulate(restored, {"p":4.0}, 0.0)
	check(normalized.ok and normalized.carry.ticks is int and normalized.carry.attackerPersonTicksByShip.p is int and normalized.carry.attackerPersonTicksByShip.p == 100, "carry accepts and normalizes integral JSON numbers")
	for patch: Dictionary in [{"version":"other"},{"ticks":60},{"ticks":-1},{"ticks":true},{"attackerPersonTicksByShip":{"p":1}},{"attackerPersonTicksByShip":{"":0}},{"defenderPersonTicks":1}]:
		var invalid: Dictionary = rules.initial_carry(); invalid.merge(patch, true)
		check(not rules.valid_carry(invalid), "carry rejects impossible partial history: " + str(patch.keys()[0]))
	var extra: Dictionary = rules.initial_carry(); extra.extra = true
	check(not rules.valid_carry(extra) and not rules.valid_carry(null), "carry rejects unknown fields and non-dictionaries")
	for attackers: Dictionary in [{"p":true},{"p":0.5},{"p":-1},{"p":1001},{"p":NAN},{"":1},{"x".repeat(257):1}]:
		rejected_accumulate(rules.initial_carry(), attackers, 0, "invalid attacker population/id")
	for defenders: Variant in [-1, true, 0.5, 1001, NAN, INF]:
		rejected_accumulate(rules.initial_carry(), {}, defenders, "invalid defender population")
	var bad_carry: Dictionary = rules.initial_carry(); bad_carry.ticks = 60
	rejected_accumulate(bad_carry, {}, 0, "invalid incoming carry")
	var many := {}
	for i in 129: many["s-" + str(i)] = 1
	rejected_accumulate(rules.initial_carry(), many, 0, "too many attacker IDs")
	var union_carry: Dictionary = rules.initial_carry(); union_carry.ticks = 1
	for i in 128: union_carry.attackerPersonTicksByShip["s-" + str(i)] = 1
	rejected_accumulate(union_carry, {"new-ship":1}, 0, "union of carry and new ships exceeds capacity")

func _test_launcher_boundary() -> void:
	# Break caught: computing the interval from the launcher endpoint frees four
	# people on tick120, or assigns the endpoint to the entire second.
	var launcher: Dictionary = Launcher.initial()
	launcher.operationSeconds = 2.0
	var carry: Dictionary = rules.initial_carry()
	var pulse := {}
	for tick in range(1, 121):
		launcher.operationSeconds = float(121 - tick) / 60.0
		var sampled: Dictionary = rules.sample(input(100, Launcher.operators(launcher, 100)))
		var accepted: Dictionary = rules.finish_row(sampled.row, 100)
		check(accepted.ok and accepted.row.launcherCrew == 4 and accepted.row.availableCrew == 96, "launcher occupies complete interval " + str(tick))
		if tick >= 61:
			var result: Dictionary = rules.accumulate(carry, {"p":accepted.row.availableCrew}, 0)
			carry = result.carry; pulse = result.pulse
	launcher.operationSeconds = 0.0
	near(float(pulse.attackers), 96.0, "launcher window61..120 integral is 96 person-seconds")
	near(float(100 - Launcher.operators(launcher, 100)), 100.0, "launcher right endpoint is 100 available crew")
	near(100.0 - float(pulse.attackers), 4.0, "old whole-second endpoint overstates launcher labour by four person-seconds")
	check(rules.sample(input(100, Launcher.operators(launcher, 100))).row.availableCrew == 100, "released launcher labour starts in interval121")

func _test_transfer_boundary() -> void:
	# Break caught: confusing zero suppression work with zero reserved duty.
	var ignited: Dictionary = FireControl.ignite(FireControl.initial(24), "thorn-ball", 0.0)
	var assigned: Dictionary = FireControl.assign(ignited.state, 4, 100)
	var state: Dictionary = assigned.state
	var carry: Dictionary = rules.initial_carry()
	var work := 0.0
	for tick in range(1, 122):
		var sampled: Dictionary = rules.sample(input(100, 0, FireControl.reserved_crew(state, 100)))
		var advanced: Dictionary = FireControl.step(state, context(100)); state = advanced.state
		var accepted: Dictionary = rules.finish_row(sampled.row, 100 - int(advanced.damage.crew))
		work += float(advanced.workSeconds)
		check(accepted.ok and accepted.row.fireDutyCrew == 4 and accepted.row.availableCrew == 96, "transfer/working personnel remain exclusively reserved " + str(tick))
		if tick <= 120:
			var result: Dictionary = rules.accumulate(carry, {"p":accepted.row.availableCrew}, 0); carry = result.carry
			if tick in [60, 120]: near(float(result.pulse.attackers), 96.0, "transfer second remains 96 available person-seconds")
		if tick == 120:
			check(state.transferTicks == 0 and work == 0.0, "all120 transfer intervals finish without suppression work")
	near(work, 4.0 / 60.0, "first effective suppression occurs in interval121")

func _test_quench_return_boundary() -> void:
	# Break caught: releasing a team at quench or before120 full return intervals.
	var state: Dictionary = FireControl.initial(24)
	state.heat = 0.01; state.fuelSeconds = 10.0
	state.assignedFirefighters = 4; state.pendingFirefighters = 4
	var carry: Dictionary = rules.initial_carry()
	var pulse := {}
	for tick in range(1, 122):
		var sampled: Dictionary = rules.sample(input(100, 0, FireControl.reserved_crew(state, 100)))
		var advanced: Dictionary = FireControl.step(state, context(100)); state = advanced.state
		var accepted: Dictionary = rules.finish_row(sampled.row, 100 - int(advanced.damage.crew))
		check(accepted.ok and accepted.row.fireDutyCrew == 4 and accepted.row.availableCrew == 96, "quench/return retains interval-start duty " + str(tick))
		if tick == 1:
			check(advanced.extinguished and state.transferTicks == 120, "quench starts a fresh120-interval return")
			near(float(advanced.workSeconds), 0.01, "quench may use fractional suppression work without freeing duty")
		if tick == 120: check(state.transferTicks == 1, "119 full return intervals leave one interval")
		if tick >= 62:
			var result: Dictionary = rules.accumulate(carry, {"p":accepted.row.availableCrew}, 0)
			carry = result.carry; pulse = result.pulse
	check(state.transferTicks == 0 and FireControl.reserved_crew(state, 100) == 0, "quench plus120 full return intervals finally releases crew")
	near(float(pulse.attackers), 96.0, "return window62..121 retains 96 available person-seconds")
	near(100.0 - float(pulse.attackers), 4.0, "old return endpoint overstates the completed second by four person-seconds")
	check(rules.sample(input(100, 0, FireControl.reserved_crew(state, 100))).row.availableCrew == 100, "released return team becomes available next interval")

func _test_casualty_boundary() -> void:
	# Break caught: replacing accepted start population with end casualties.
	var carry: Dictionary = rules.initial_carry()
	var pulse := {}
	var ended := {}
	for tick in range(1, 61):
		ended = rules.finish_row(row(), 97 if tick == 60 else 100)
		var result: Dictionary = rules.accumulate(carry, {"p":ended.row.availableCrew}, 0)
		carry = result.carry; pulse = result.pulse
	check(ended.row.totalAbleAtStart == 100 and ended.row.totalAbleAtEnd == 97 and ended.row.availableCrew == 100, "right-boundary casualty row preserves full preceding labour")
	near(float(pulse.attackers), 100.0, "casualty window1..60 contains100 available person-seconds")
	near(97.0 - float(pulse.attackers), -3.0, "old casualty endpoint loses three already completed person-seconds")
	for _i in 60:
		var result: Dictionary = rules.accumulate(carry, {"p":row(97).availableCrew}, 0)
		carry = result.carry; pulse = result.pulse
	near(float(pulse.attackers), 97.0, "the next complete second uses the surviving97 crew")
