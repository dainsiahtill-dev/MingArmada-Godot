extends SceneTree
## Ship system upgrades: real silver, shipyard gate, three-level bounds and
## live stat effects (legacy shipyard semantics in the mainline).

const Support = preload("res://tests/story_walkthrough_support.gd")
const Rules = preload("res://game/domain/story_world/story_rules.gd")
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
	_test_costs_and_bounds()
	_test_shipyard_gate()
	_test_live_upgrade_stats()
	_finish()

func _finish() -> void:
	print("STORY_UPGRADES assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures > 0 else 0)

func _world() -> RefCounted:
	var world: RefCounted = World.new()
	world.call("configure", Scenarios.opening(), 1661, "story-upgrades")
	world.state.silver = 5000
	return world

func _test_costs_and_bounds() -> void:
	check(Rules.upgrade_cost("hull", 0) == 180 and Rules.upgrade_cost("cannons", 0) == 250, "upgrade prices follow the shipyard schedule")
	check(Rules.upgraded_max_hull(1) == 120 and Rules.upgraded_max_hull(3) == 173, "hull caps grow by level")
	var world := _world()
	var silver_before: int = int(world.state.silver)
	check(world.call("command", {"type": "upgrade", "system": "hull"}).get("ok", false), "hull upgrade settles")
	check(silver_before - int(world.state.silver) == 180, "the shipyard takes real silver")
	var ship: Dictionary = world.state.fleet[0]
	check(int(ship.upgrades.hull) == 1 and int(ship.maxHull) == 120 and int(ship.hull) == 120, "hull upgrade raises the cap and the ship")
	world.call("command", {"type": "upgrade", "system": "hull"})
	world.call("command", {"type": "upgrade", "system": "hull"})
	check(int(world.state.fleet[0].upgrades.hull) == 3, "levels advance to three")
	check(not world.call("command", {"type": "upgrade", "system": "hull"}).get("ok", true), "the three-level cap refuses more")
	check(not world.call("command", {"type": "upgrade", "system": "engines"}).get("ok", true), "unknown systems refused")
	check(World.validate_world(world.call("snapshot")).get("ok", false), "upgraded hulls validate")
	var twin: RefCounted = World.new()
	check(twin.call("restore", world.call("serialize")).get("ok", false), "upgrades survive save/restore")
	check(int(twin.state.fleet[0].upgrades.hull) == 3, "restored ship keeps its levels")

func _test_shipyard_gate() -> void:
	var world := _world()
	world.state.currentPortId = "kinmen"
	check(not world.call("command", {"type": "upgrade", "system": "cannons"}).get("ok", true), "ports without a shipyard refuse upgrades")

func _test_live_upgrade_stats() -> void:
	var runtime: RefCounted = Support.setup("story-upgrades-stats")
	runtime.fixture_speed_multiplier = 1.0
	runtime.fixture_reload_multiplier = 1.0
	runtime.world.state.silver = 5000
	check(runtime.world.call("command", {"type": "upgrade", "system": "cannons"}).get("ok", false), "cannons upgrade settles at Xiamen")
	check(runtime.world.call("command", {"type": "upgrade", "system": "sails"}).get("ok", false), "sails upgrade settles")
	check(runtime.world.call("command", {"type": "upgrade", "system": "equipment"}).get("ok", false), "equipment upgrade settles")
	var setup: Dictionary = runtime._fleet_setup(runtime.world.state.fleet[0])
	check(absf(float(setup.stats.cannonMultiplier) - 1.15) < 0.000001, "gun batteries hit harder (%s)" % str(setup.stats.cannonMultiplier))
	check(absf(float(setup.stats.speedMultiplier) - 1.08) < 0.000001, "new sails push faster (%s)" % str(setup.stats.speedMultiplier))
	check(absf(float(setup.stats.steeringMultiplier) - 1.15) < 0.000001, "steering gear answers sooner (%s)" % str(setup.stats.steeringMultiplier))
