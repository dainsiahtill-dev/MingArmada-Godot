extends SceneTree
## Isolated auxiliary launch geometry and canonical-state contract.
const Cannon = preload("res://modules/naval_simulation/combat/cannon_system.gd")
var failures: Array[String] = []
var assertions: int = 0

func _initialize() -> void:
	var path: String = "res://modules/naval_simulation/combat/fire_launcher.gd"
	check(ResourceLoader.exists(path), "FIRE_LAUNCHER_MISSING: independent pure launcher module")
	if not ResourceLoader.exists(path):
		_finish()
		return
	var launcher: Script = load(path)
	for method: String in ["initial", "valid", "launch_solution", "operators"]:
		check(launcher.has_method(method), "pure launcher API " + method)
	if not failures.is_empty():
		_finish()
		return
	var state: Dictionary = launcher.initial(12, 8)
	check(launcher.valid(state), "initial canonical launcher state")
	check(state == {"ammo":{"fire-ball":12, "thorn-ball":8}, "cooldownSeconds":0.0, "operationSeconds":0.0}, "canonical state has exact declared fields")
	var mutations: Array = [
		["cooldownSeconds", -1], ["cooldownSeconds", 120.01], ["cooldownSeconds", NAN],
		["operationSeconds", -1], ["operationSeconds", 2.01], ["operationSeconds", INF],
	]
	for mutation: Array in mutations:
		var invalid: Dictionary = state.duplicate(true)
		invalid[mutation[0]] = mutation[1]
		check(not launcher.valid(invalid), "invalid canonical duration " + str(mutation))
	for quantity: Variant in [-1, 0.5, 61, NAN, true]:
		var invalid: Dictionary = state.duplicate(true)
		invalid.ammo["fire-ball"] = quantity
		check(not launcher.valid(invalid), "invalid payload inventory " + str(quantity))
	var extra: Dictionary = state.duplicate(true)
	extra.ammo.solid = 10
	check(not launcher.valid(extra), "ordinary ammunition cannot enter auxiliary inventory")
	extra = state.duplicate(true)
	extra.unexpected = 1
	check(not launcher.valid(extra), "canonical launcher rejects unknown state fields")
	check(launcher.operators(state, 100) == 0, "idle launcher reserves no crew")
	state.operationSeconds = 2.0
	check(launcher.operators(state, 100) == 4 and launcher.operators(state, 3) == 3 and launcher.operators(state, 0) == 0, "active operator reserve is four bounded by living population")
	var source: Dictionary = _ship("p", "fuchuan", {"x":0.0, "y":0.0, "z":0.0})
	var target: Dictionary = _ship("e", "fuchuan", {"x":0.0, "y":0.0, "z":50.0})
	var before: Array = [source.duplicate(true), target.duplicate(true)]
	var solution: Dictionary = launcher.launch_solution(source, target)
	check(solution.ok and solution.velocities.size() == 1 and solution.ttl == 4.0, "one independent payload with declared TTL")
	check(source == before[0] and target == before[1], "ballistic proposal never mutates source or target")
	if solution.ok:
		var velocity: Dictionary = solution.velocities[0]
		check(is_equal_approx(Vector3(velocity.x, velocity.y, velocity.z).length(), 28.0), "declared launch speed in metres per second")
		var dx: float = target.visual.position.x-solution.position.x
		var dz: float = target.visual.position.z-solution.position.z
		var flight: float = Vector2(dx, dz).length()/Vector2(velocity.x, velocity.z).length()
		var impact_y: float = solution.position.y+velocity.y*flight-0.5*9.81*flight*flight
		check(absf(impact_y-2.4) < 0.000001, "low ballistic arc reaches target freeboard datum under existing gravity")
		check(Cannon.corridor_clear(solution, []), "shared cannon corridor accepts independent ballistic shape")
		var friend: Dictionary = _ship("friend", "merchant", {"x":0.0, "y":0.0, "z":25.0})
		check(not Cannon.corridor_clear(solution, [friend]), "shared moving hull corridor blocks protected ship")
	var beyond: Dictionary = target.duplicate(true)
	beyond.visual.position.z = 70.01
	check(not launcher.launch_solution(source, beyond).ok, "declared 70 metre maximum uses ship centres")
	beyond.visual.position.z = 70.0
	check(launcher.launch_solution(source, beyond).ok, "exact range boundary remains reachable")
	var invalid_geometry: Dictionary = target.duplicate(true)
	invalid_geometry.visual.velocity.x = NAN
	check(not launcher.launch_solution(source, invalid_geometry).ok, "nonfinite target motion rejects a launch proposal")
	invalid_geometry = source.duplicate(true)
	invalid_geometry.kind = "unknown"
	check(not launcher.launch_solution(invalid_geometry, target).ok, "unknown hull cannot supply a fictional launch anchor")
	check(launcher.launch_solution(source, target) == solution, "repeated immutable input gives exact deterministic trajectory")
	_finish()

func _ship(id: String, kind: String, position: Dictionary) -> Dictionary:
	return {"id":id, "kind":kind, "hull":100.0, "visual":{"position":position, "heading":0.0,
		"velocity":{"x":0.0, "y":0.0, "z":0.0}, "heel":0.0, "pitch":0.0}}

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)

func _finish() -> void:
	for failure: String in failures: print("FIRE_LAUNCHER_FAIL ", failure)
	print("FIRE_LAUNCHER assertions=", assertions, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
