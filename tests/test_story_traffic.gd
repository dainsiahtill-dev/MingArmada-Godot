extends SceneTree
## Living sea traffic: declared trade routes carry neutral traders that really
## sail toward their destination and turn around on arrival.

const Support = preload("res://tests/story_walkthrough_support.gd")
const Scenarios = preload("res://game/domain/story_campaign/scenarios.gd")
var assertions: int = 0
var failures: int = 0

func _init() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> bool:
	assertions += 1
	if not value:
		failures += 1
		print("FAIL: ", label)
	return value

func _run() -> void:
	_test_routes_validate()
	_test_traders_sail_and_turn()
	_finish()

func _finish() -> void:
	print("STORY_TRAFFIC assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures > 0 else 0)

func _test_routes_validate() -> void:
	var geo: Dictionary = Scenarios.geography()
	check(geo.get("ok", false), "geography with trade routes validates")
	check((geo.data.tradeRoutes as Array).size() == 4, "four trade routes declared")

func _test_traders_sail_and_turn() -> void:
	var runtime: RefCounted = Support.setup("story-traffic", 2.0, true)
	check(Support.advance_to(runtime, 0), "runtime reaches CH-01")
	check(runtime.call("command", {"type": "begin-stage"}).get("ok", false), "CH-01 begins")
	check(runtime.call("command", {"type": "transition"}).get("ok", false), "CH-01 transitions")
	check(runtime._traffic_setups.size() == 4, "four traders ply the sea")
	var native: Dictionary = runtime.call("native_snapshot")
	var seen := 0
	for entry: Dictionary in native.ships:
		if str(entry.id).begins_with("traffic-"):
			seen += 1
	check(seen == 4, "all traders are live in the native scene, got %d" % seen)
	check(runtime.call("command", {"type": "depart"}).get("ok", false), "the fleet deploys")
	var trader := "traffic-xiamen-kinmen"
	var before: float = _distance_to_goal(runtime, trader)
	Support.run_ticks(runtime, 600)
	var after: float = _distance_to_goal(runtime, trader)
	check(after < before, "the trader really sails toward its destination (%.1f -> %.1f m)" % [before, after])
	# Force an arrival: pose the trader beside its destination and watch the
	# waypoint flip to the far endpoint on the next navigation update.
	var route: Dictionary = runtime._traffic_routes[trader]
	runtime._traffic_setups[trader].position = {"x": float(route.b.x) + 10.0, "z": float(route.b.z)}
	runtime.call("_reseat")
	Support.run_ticks(runtime, 40)
	var goal: Dictionary = runtime._traffic_targets[trader]
	var flip_distance: float = sqrt(pow(float(goal.x) - float(route.a.x), 2) + pow(float(goal.z) - float(route.a.z), 2))
	check(flip_distance <= 1.0, "on arrival the trader turns for home")

func _distance_to_goal(runtime: RefCounted, trader: String) -> float:
	var goal: Dictionary = runtime._traffic_targets[trader]
	var native: Dictionary = runtime.call("native_snapshot")
	for entry: Dictionary in native.ships:
		if str(entry.id) == trader:
			var here: Dictionary = entry.visual.position
			return sqrt(pow(float(here.x) - float(goal.x), 2) + pow(float(here.z) - float(goal.z), 2))
	return INF
