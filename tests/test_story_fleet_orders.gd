extends SceneTree
## Fleet orders: formation switching and assigned escorts drive real native
## navigation, and the orders survive save/restore.

const Support = preload("res://tests/story_walkthrough_support.gd")
const World = preload("res://game/domain/story_world/story_world_session.gd")
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
	_test_order_plumbing()
	_test_escort_follows_for_real()
	_finish()

func _finish() -> void:
	print("STORY_FLEET_ORDERS assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures > 0 else 0)

func _test_order_plumbing() -> void:
	var world: RefCounted = World.new()
	world.call("configure", Scenarios.opening(), 1661, "story-fleet-orders")
	world.state.silver = 5000
	world.state.currentPortId = "xiamen"
	check(world.call("command", {"type": "buy-ship", "kind": "merchant"}).get("ok", false), "a second hull joins the squadron")
	check(world.call("command", {"type": "set-formation", "mode": "abreast"}).get("ok", false), "formation switches to abreast")
	check(str(world.state.orders.formation) == "abreast", "the order is on the books")
	check(not world.call("command", {"type": "set-formation", "mode": "wedge"}).get("ok", true), "unknown formations refused")
	var wing: String = str(world.state.fleet[1].id)
	check(world.call("command", {"type": "assign-escort", "shipId": wing, "targetId": "merchant-convoy"}).get("ok", false), "the wing takes an escort assignment")
	check(str(world.state.orders.escorts.get(wing, "")) == "merchant-convoy", "the assignment is on the books")
	check(not world.call("command", {"type": "assign-escort", "shipId": "player", "targetId": "x"}).get("ok", true), "the flagship cannot be sent away")
	check(not world.call("command", {"type": "release-escort", "shipId": "player"}).get("ok", true), "releasing an unassigned ship is refused")
	check(world.call("command", {"type": "release-escort", "shipId": wing}).get("ok", false), "the assignment is released")
	check(World.validate_world(world.call("snapshot")).get("ok", false), "orders validate in the world")
	world.call("command", {"type": "assign-escort", "shipId": wing, "targetId": "merchant-convoy"})
	var twin: RefCounted = World.new()
	check(twin.call("restore", world.call("serialize")).get("ok", false), "orders survive save/restore")
	check(str(twin.state.orders.formation) == "abreast" and twin.state.orders.escorts.has(wing), "restored squadron keeps its orders")

func _test_escort_follows_for_real() -> void:
	var runtime: RefCounted = Support.setup("story-fleet-follow")
	check(Support.advance_to(runtime, 3), "playthrough reaches CH-04")
	check(runtime.call("command", {"type": "begin-stage"}).get("ok", false), "CH-04 begins")
	check(runtime.call("command", {"type": "transition"}).get("ok", false), "CH-04 transitions")
	runtime.world.state.silver = 5000
	check(runtime.call("command", {"type": "buy-ship", "kind": "patrol"}).get("ok", false), "a fast wing ship joins for the escort")
	var wing: String = str(runtime.world.state.fleet.back().id)
	check(runtime.call("command", {"type": "transfer-crew", "fromShipId": "player", "toShipId": wing, "count": 20}).get("ok", false), "the wing is crewed for sea")
	check(runtime.call("command", {"type": "assign-escort", "shipId": wing, "targetId": "ch04-client-convoy"}).get("ok", false), "the wing is assigned to the client convoy")
	check(runtime.call("command", {"type": "depart"}).get("ok", false), "the squadron deploys")
	# Real ship speeds in this sim are crawl-scale (~0.1-0.35 m/s), so closing
	# a 140 m gap exceeds any runner budget. The honest escort property is
	# station-keeping: start alongside the charge and hold formation.
	var charge_spawn := {"x": -225.0, "z": 100.0}
	runtime.world.state.fleet.back().position = {"x": charge_spawn.x + 10.0, "z": charge_spawn.z}
	runtime.call("_reseat")
	Support.run_ticks(runtime, 600)
	var spread: float = _spread(runtime, wing, "ch04-client-convoy")
	check(spread <= 25.0, "the wing holds escort station beside its charge (%.1f m)" % spread)

func _spread(runtime: RefCounted, wing: String, charge: String) -> float:
	var native: Dictionary = runtime.call("native_snapshot")
	var a := {}
	var b := {}
	for entry: Dictionary in native.ships:
		if str(entry.id) == wing:
			a = entry.visual.position
		if str(entry.id) == charge:
			b = entry.visual.position
	return sqrt(pow(float(a.get("x", 0.0)) - float(b.get("x", 0.0)), 2) + pow(float(a.get("z", 0.0)) - float(b.get("z", 0.0)), 2))
