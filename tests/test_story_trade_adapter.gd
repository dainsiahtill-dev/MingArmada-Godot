extends SceneTree
## Trade category: real buy/sell settlements against story markets, per-task
## ledger windows, real capacity management, real provisioning stockpile.

const Support = preload("res://tests/story_walkthrough_support.gd")
const RUNTIME_PATH := "res://game/runtime/story_runtime.gd"
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
	_test_task_ledger_profit()
	_test_stockpile_with_real_capacity()
	_finish()

func _finish() -> void:
	print("STORY_TRADE_ADAPTER assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures > 0 else 0)

func _test_task_ledger_profit() -> void:
	var runtime: RefCounted = Support.setup("story-trade")
	check(Support.advance_to(runtime, 2), "playthrough reaches CH-03 with real settlements")
	check(runtime.call("command", {"type": "begin-stage"}).get("ok", false), "CH-03 begins")
	check(runtime.call("command", {"type": "transition"}).get("ok", false), "CH-03 transitions to Kinmen")
	check(runtime.call("command", {"type": "mint-grant", "good": "grain", "quantity": 30}).get("ok", false), "trading cargo granted for the lesson")
	check(runtime.call("command", {"type": "sell", "good": "grain", "quantity": 30}).get("ok", false), "real sale against the Kinmen market")
	var settled: Dictionary = runtime.call("command", {"type": "settle-stage"})
	check(settled.get("ok", false) and str(settled.get("outcome", "")) == "success", "CH-03 settles from real per-task net")
	var ledger: Dictionary = runtime.world.call("voyage_ledger", "ch03-public-cargo")
	check(ledger.get("ok", false) and int(ledger.net) > 0, "task ledger holds this attempt's real net")
	runtime.call("command", {"type": "continue-story"})
	check(int(runtime.world.call("voyage_ledger", "ch03-public-cargo").net) > 0, "closed ledger window keeps its own net")

func _test_stockpile_with_real_capacity() -> void:
	var runtime: RefCounted = Support.setup("story-trade-capacity")
	check(Support.advance_to(runtime, 19), "playthrough reaches CH-20 with real settlements")
	check(runtime.call("command", {"type": "begin-stage"}).get("ok", false), "CH-20 begins")
	check(runtime.call("command", {"type": "transition"}).get("ok", false), "CH-20 transitions to Xiamen")
	Support.fund(runtime, 3000)
	check(runtime.call("command", {"type": "sign-charter", "permitId": "regional-supply-renewal", "scope": "expedition-supply", "issuer": "ming-coast", "cost": 120, "conditions": ["续订粮水与修材"]}).get("ok", false), "real charter settlement")
	check(runtime.call("command", {"type": "buy-ship", "kind": "merchant"}).get("ok", false), "real ship purchase for expedition capacity")
	var merchant: String = str(runtime.world.state.fleet.back().id)
	check(runtime.call("command", {"type": "transfer-crew", "fromShipId": "player", "toShipId": merchant, "count": 16}).get("ok", false), "real crew transfer to the transport")
	check(runtime.call("command", {"type": "buy", "good": "grain", "quantity": 90}).get("ok", false), "buy grain onto the flagship")
	var refused: Dictionary = runtime.world.call("command", {"type": "buy", "good": "grain", "quantity": 100000})
	check(not refused.get("ok", true), "capacity gate refuses overloading: " + str(refused.get("reason", "")))
	check(runtime.call("command", {"type": "transfer-cargo", "fromShipId": "player", "toShipId": merchant, "good": "grain", "quantity": 90}).get("ok", false), "real cargo transfer to the transport")
	check(runtime.call("command", {"type": "buy", "good": "grain", "quantity": 70}).get("ok", false), "buy the rest of the grain")
	check(runtime.call("command", {"type": "buy", "good": "wood", "quantity": 40}).get("ok", false), "buy repair materials")
	var settled: Dictionary = runtime.call("command", {"type": "settle-stage"})
	check(settled.get("ok", false) and str(settled.get("outcome", "")) == "success", "CH-20 stockpile settles from real purchases: " + str(settled.get("outcome", "")))
