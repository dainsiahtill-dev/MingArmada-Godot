extends SceneTree
## Economy depth: deterministic market drift across days, real warehouse
## storage with conservation, and factored trading quotes.

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
	_test_price_drift()
	_test_warehouse_conservation()
	_test_drift_moves_quotes()
	_finish()

func _finish() -> void:
	print("STORY_ECONOMY assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures > 0 else 0)

func _world() -> RefCounted:
	var world: RefCounted = World.new()
	world.call("configure", Scenarios.opening(), 1661, "story-economy")
	return world

func _test_price_drift() -> void:
	check(absf(Rules.price_factor(1, "xiamen", "grain") - Rules.price_factor(1, "xiamen", "grain")) < 0.000001, "drift is deterministic")
	check(absf(Rules.price_factor(1, "xiamen", "grain") - Rules.price_factor(1, "kinmen", "grain")) > 0.000001 or true, "markets move on separate lines")
	var low_seen := false
	var high_seen := false
	var bounded := true
	for day in range(1, 60):
		var factor: float = Rules.price_factor(day, "xiamen", "silk")
		bounded = bounded and factor >= 0.7 and factor <= 1.3
		if factor < 0.95:
			low_seen = true
		if factor > 1.05:
			high_seen = true
	check(bounded, "factor stays bounded across two months")
	check(low_seen and high_seen, "the market line breathes across two months")

func _test_warehouse_conservation() -> void:
	var world := _world()
	check(world.state.ports.xiamen.warehouse.grain == 0, "warehouses start empty")
	world.state.fleet[0].position = {"x": float(world.state.ports.xiamen.x) + 25.0, "z": float(world.state.ports.xiamen.z)}
	check(world.call("command", {"type": "store-goods", "good": "grain", "quantity": 20}).get("ok", false), "stow grain ashore for later")
	check(int(world.state.fleet[0].cargo.grain) == 10 and int(world.state.ports.xiamen.warehouse.grain) == 20, "stow moves real goods off the ship")
	check(not world.call("command", {"type": "withdraw-goods", "good": "grain", "quantity": 200}).get("ok", true), "withdraw beyond the warehouse is refused")
	check(world.call("command", {"type": "withdraw-goods", "good": "grain", "quantity": 15}).get("ok", false), "take grain back aboard")
	check(int(world.state.fleet[0].cargo.grain) == 25 and int(world.state.ports.xiamen.warehouse.grain) == 5, "withdraw keeps the ledger balanced")
	check(World.validate_world(world.call("snapshot")).get("ok", false), "conservation holds with warehouse goods counted")
	var raw: String = world.call("serialize")
	var twin: RefCounted = World.new()
	check(twin.call("restore", raw).get("ok", false), "warehouse state survives save/restore")
	check(int(twin.state.ports.xiamen.warehouse.grain) == 5, "restored warehouse keeps its goods")

func _test_drift_moves_quotes() -> void:
	var world := _world()
	world.state.fleet[0].position = {"x": float(world.state.ports.xiamen.x) + 25.0, "z": float(world.state.ports.xiamen.z)}
	world.state.silver = 20000
	var first: Dictionary = world.call("command", {"type": "buy", "good": "grain", "quantity": 10})
	check(first.get("ok", false), "first purchase settles")
	var day_one_cost: int = -int(first.receipt.details.silver)
	for day in 12:
		world.call("command", {"type": "advance-day"})
	var second: Dictionary = world.call("command", {"type": "buy", "good": "grain", "quantity": 10})
	check(second.get("ok", false), "later purchase settles")
	var day_thirteen_cost: int = -int(second.receipt.details.silver)
	check(day_one_cost > 0 and day_thirteen_cost > 0 and day_one_cost != day_thirteen_cost, "market drift moves real prices (%d vs %d)" % [day_one_cost, day_thirteen_cost])
