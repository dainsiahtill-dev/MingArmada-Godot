extends SceneTree
## Port services depth: banqueting buys real standing (relations improve the
## quote), intel buys real market knowledge (remote factors recorded and kept).

const World = preload("res://game/domain/story_world/story_world_session.gd")
const Rules = preload("res://game/domain/story_world/story_rules.gd")
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
	_test_banquet_buys_standing()
	_test_intel_buys_knowledge()
	_test_service_gates()
	_finish()

func _finish() -> void:
	print("STORY_PORT_SERVICES assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures > 0 else 0)

func _world() -> RefCounted:
	var world: RefCounted = World.new()
	world.call("configure", Scenarios.opening(), 1661, "story-services")
	world.state.silver = 5000
	return world

func _test_banquet_buys_standing() -> void:
	var world := _world()
	world.state.currentPortId = "xiamen"
	var relation_before: int = int(world.state.relations.zheng)
	var silver_before: int = int(world.state.silver)
	check(world.call("command", {"type": "attend-banquet"}).get("ok", false), "the banquet settles")
	check(int(world.state.relations.zheng) == relation_before + 3, "the host faction gains three points of standing")
	check(silver_before - int(world.state.silver) == 30, "the evening costs thirty taels")
	for repeat in 8:
		world.call("command", {"type": "attend-banquet"})
	check(int(world.state.relations.zheng) == 27, "nine banquets stack to twenty-seven points")
	world.state.relations.zheng = 98
	world.call("command", {"type": "attend-banquet"})
	check(int(world.state.relations.zheng) == 100, "standing clamps at a hundred")
	# Better standing really improves the ask: same goods, lower bill.
	for good: String in ["grain", "wood", "iron", "silk", "porcelain", "spices"]:
		world.state.ports.xiamen.priceFactor[good] = 1.0
	world.state.relations.zheng = -50
	var cold: int = int(world.call("command", {"type": "buy", "good": "grain", "quantity": 10}).receipt.details.silver) * -1
	world.state.ports.xiamen.stock.grain = 200
	world.state.relations.zheng = 100
	var warm: int = int(world.call("command", {"type": "buy", "good": "grain", "quantity": 10}).receipt.details.silver) * -1
	check(warm < cold, "relations really move the bill (%d vs %d)" % [warm, cold])

func _test_intel_buys_knowledge() -> void:
	var world := _world()
	world.state.currentPortId = "xiamen"
	check(not world.call("command", {"type": "gather-intel", "portId": "xiamen"}).get("ok", true), "peering at your own dock is refused")
	check(not world.call("command", {"type": "gather-intel", "portId": "atlantis"}).get("ok", true), "unknown ports are refused")
	var silver_before: int = int(world.state.silver)
	check(world.call("command", {"type": "gather-intel", "portId": "kinmen"}).get("ok", false), "the message house reports Kinmen's line")
	check(silver_before - int(world.state.silver) == 20, "the report costs twenty taels")
	check(world.state.intel.has("kinmen") and world.state.intel.kinmen.priceFactor.size() == 6, "remote factors are recorded")
	check(World.validate_world(world.call("snapshot")).get("ok", false), "intel validates in the world")
	var twin: RefCounted = World.new()
	check(twin.call("restore", world.call("serialize")).get("ok", false), "intel survives save/restore")
	check(twin.state.intel.has("kinmen"), "restored world keeps the report")

func _test_service_gates() -> void:
	var world := _world()
	world.state.currentPortId = "kinmen"
	check(not world.call("command", {"type": "attend-banquet"}).get("ok", true), "ports without a banquet refuse the feast")
	check(not world.call("command", {"type": "gather-intel", "portId": "xiamen"}).get("ok", true), "ports without a message house refuse reports")
