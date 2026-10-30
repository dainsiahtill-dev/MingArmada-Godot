extends SceneTree
## Partnership voyages: a semi-independent partner sails real capital to a
## foreign market; the yield follows the day's real price-factor spread and
## splits 60/40 with the partner.

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
	_test_spread_math()
	_test_partner_voyage()
	_finish()

func _finish() -> void:
	print("STORY_PARTNERSHIPS assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures > 0 else 0)

func _factors(value: float) -> Dictionary:
	var map := {}
	for good: String in ["grain", "wood", "iron", "silk", "porcelain", "spices"]:
		map[good] = value
	return map

func _test_spread_math() -> void:
	check(absf(Rules.partner_spread(_factors(1.0), _factors(1.2)) - 0.2) < 0.000001, "spread reads the market gap")
	check(absf(Rules.partner_spread(_factors(1.2), _factors(0.7)) + 0.3) < 0.000001, "losses floor at minus 0.3")
	check(absf(Rules.partner_spread(_factors(0.7), _factors(1.3)) - 0.6) < 0.000001, "gains ceiling at 0.6")
	check(Rules.partner_player_return(200, 0.2) == 144, "two hundred taels at +20% returns 144 to the player")

func _test_partner_voyage() -> void:
	var world: RefCounted = World.new()
	world.call("configure", Scenarios.opening(), 1661, "story-partners")
	world.state.silver = 1000
	check(not world.call("command", {"type": "dispatch-convoy", "dispatchId": "p1", "shipIds": ["player"], "partnerId": "ghost", "capital": 200, "destinationPortId": "kinmen"}).get("ok", true), "an unsigned partner cannot sail")
	check(not world.call("command", {"type": "dispatch-convoy", "dispatchId": "p1", "shipIds": ["player"], "partnerId": "keeper", "capital": 200, "destinationPortId": "atlantis"}).get("ok", true), "unknown destinations refused")
	world.call("command", {"type": "sign-on", "personId": "keeper", "name": "黎秋砚", "role": "diplomat", "cost": 0, "wage": 0})
	var silver_before: int = int(world.state.silver)
	check(world.call("command", {"type": "dispatch-convoy", "dispatchId": "p1", "shipIds": ["player"], "partnerId": "keeper", "capital": 200, "destinationPortId": "kinmen"}).get("ok", false), "the partner sails with real capital")
	check(silver_before - int(world.state.silver) == 200, "the capital leaves the ledger")
	check(not world.call("command", {"type": "dispatch-convoy", "dispatchId": "p1", "shipIds": ["player"], "partnerId": "keeper", "capital": 100, "destinationPortId": "kinmen"}).get("ok", true), "double dispatching refused")
	var home: Dictionary = world.state.ports.xiamen
	var away: Dictionary = world.state.ports.kinmen
	var spread: float = Rules.partner_spread(home.priceFactor, away.priceFactor)
	var expected: int = Rules.partner_player_return(200, spread)
	var before_return: int = int(world.state.silver)
	var returned: Dictionary = world.call("command", {"type": "return-dispatch", "dispatchId": "p1", "resultManifest": {"note": "合伙归建"}})
	check(returned.get("ok", false), "the partner returns and settles")
	check(int(world.state.silver) - before_return == expected, "the share follows the real spread (%d expected)" % expected)
	check(returned.receipt.details.settlement.spread == spread, "the settlement records the spread")
	check(not world.call("command", {"type": "return-dispatch", "dispatchId": "p1"}).get("ok", true), "settling twice refused")
	check(World.validate_world(world.call("snapshot")).get("ok", false), "partnership records validate")
	var twin: RefCounted = World.new()
	check(twin.call("restore", world.call("serialize")).get("ok", false), "partnership records survive save/restore")
