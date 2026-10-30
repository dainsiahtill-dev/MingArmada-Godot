extends SceneTree
## Real land-battle minigame: the land stage settles through a model-authoritative
## tactical grid battle driven to victory, then the shore settlements.

const Support = preload("res://tests/story_walkthrough_support.gd")
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
	var runtime: RefCounted = Support.setup("story-land-game")
	check(Support.advance_to(runtime, 13), "playthrough reaches CH-14")
	check(runtime.call("command", {"type": "begin-stage"}).get("ok", false), "CH-14 begins")
	check(runtime.call("command", {"type": "transition"}).get("ok", false), "CH-14 transitions to Penghu")
	var battle: Dictionary = Support.land_battle_until_win(runtime, "ch14-transshipment-quay")
	check(battle.get("ok", false), "real land battle reaches a victory: %s" % str(battle.get("attempt", battle.get("reason", "?"))))
	check(runtime.world.state.landPositions.has("ch14-transshipment-quay"), "land-control recorded from the real battle")
	var loaded: Dictionary = runtime.call("command", {"type": "load-manifest", "manifestId": "ch14-shore-load", "fromId": "ch14-transshipment-quay", "people": 0, "cargo": {"grain": 40}, "ontoShipIds": ["player"]})
	check(loaded.get("ok", false), "shore load after the landing")
	check(runtime.call("command", {"type": "deliver", "good": "grain", "quantity": 40}).get("ok", false), "shore delivery settles")
	check(runtime.call("command", {"type": "withdraw", "groupId": "ch14-shore-party", "rendezvousPortId": "penghu", "people": 12}).get("ok", false), "shore party withdraws")
	var settled: Dictionary = runtime.call("command", {"type": "settle-stage"})
	check(settled.get("ok", false) and str(settled.get("outcome", "")) == "success", "CH-14 settles from the real battle: %s" % str(settled.get("outcome", "")))
	_finish()

func _finish() -> void:
	print("STORY_LAND_MINIGAME assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures > 0 else 0)
