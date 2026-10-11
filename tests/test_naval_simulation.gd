extends SceneTree
const Encounter = preload("res://modules/naval_simulation/encounter.gd")
const Planner = preload("res://modules/naval_simulation/navigation/wet_route_planner.gd")
const Collator = preload("res://modules/naval_simulation/id_collator.gd")
var failures: Array[String] = []
var assertions := 0
func _initialize() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/naval-reference.json"))
	var collator = Collator.new()
	for pair: Dictionary in fixture.localePairs: compare(collator.compare(pair.a, pair.b), pair.expected, "collation/" + pair.a + "/" + pair.b)
	for case: Dictionary in fixture.cases:
		var configuration = case.config.duplicate(true)
		if configuration.has("_terrain"): configuration.sampleTerrainHeight = terrain.bind(configuration._terrain)
		var game = Encounter.new(configuration)
		if not game.last_error.is_empty(): failures.append(case.name + "/constructor " + game.last_error); continue
		for record: Dictionary in case.records:
			var action: Dictionary = record.action
			var result: Variant = null
			if action.method == "step":
				for i in int(action.get("count", 1)):
					game.step(action.get("seconds", 1.0 / 60.0))
			else:
				result = game.callv(action.method, action.args)
			compare(result, record.result, case.name + "/" + action.method + "/result")
			compare(game.snapshot(), record.snapshot, case.name + "/" + action.method + "/snapshot")
			compare(game.drain_events(), record.events, case.name + "/events")
			compare(game.order_status(), record.orders, case.name + "/orders")
			for id in record.navigation: compare(game.navigation_status(id), record.navigation[id], case.name + "/navigation/" + id)
	for sweep: Dictionary in fixture.sweeps:
		compare(Encounter.Sweep.sweep_moving_box(sweep.from, sweep.to, sweep.previous, sweep.current, sweep.box), sweep.expected, "sweep/" + sweep.name)
	for route: Dictionary in fixture.routes:
		var sampler: Callable = terrain.bind(route.terrain)
		compare(Planner.new().plan(route.start, route.target, route.hull, sampler), route.expected, "route/" + route.terrain)
	if failures.is_empty():
		print("NAVAL_SIMULATION_PASS assertions=", assertions, " cases=", fixture.cases.size())
		quit(0)
	else:
		for failure in failures.slice(0, 30): print("NAVAL_FAIL ", failure)
		print("NAVAL_SIMULATION_FAIL count=", failures.size())
		quit(1)
func terrain(x: float, z: float, kind: String) -> float:
	match kind:
		"wall": return 10.0 if absf(x - 100.0) < 20.0 else -100.0
		"island": return 10.0 if sqrt(pow(x - 100.0, 2) + z * z) < 45.0 else -100.0
		"dry": return 10.0
		"nan": return NAN
	return -100.0
func compare(actual: Variant, expected: Variant, path: String) -> void:
	assertions += 1
	if expected is Dictionary:
		if not actual is Dictionary: failures.append(path + " expected dictionary"); return
		if actual.size() != expected.size(): failures.append(path + " dictionary keys got " + str(actual.keys()) + " expected " + str(expected.keys()))
		for key in expected:
			if not actual.has(key): failures.append(path + " missing " + key)
			else: compare(actual[key], expected[key], path + "/" + key)
	elif expected is Array:
		if not actual is Array or actual.size() != expected.size(): failures.append(path + " array size " + str(actual) + " expected " + str(expected.size())); return
		for i in expected.size(): compare(actual[i], expected[i], path + "/" + str(i))
	elif expected is int or expected is float:
		if not numeric_equal(actual, expected):
			failures.append(path + " got " + str(actual) + " expected " + str(expected))
	elif actual != expected: failures.append(path + " got " + str(actual) + " expected " + str(expected))
static func numeric_equal(actual: Variant, expected: Variant) -> bool:
	return (actual is int or actual is float) and (expected is int or expected is float) and is_finite(float(actual)) and is_finite(float(expected)) and absf(float(actual) - float(expected)) <= 1e-7 * maxf(1.0, absf(float(expected)))
