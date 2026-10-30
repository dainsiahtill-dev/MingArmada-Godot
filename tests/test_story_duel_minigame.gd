extends SceneTree
## Real duel minigame: the boarding stage settles through model-authoritative
## duel victories driven via encounter-action loops (fresh seed per try).

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
	var runtime: RefCounted = Support.setup("story-live-duel")
	check(Support.advance_to(runtime, 1), "playthrough reaches CH-02")
	check(runtime.call("command", {"type": "begin-stage"}).get("ok", false), "CH-02 begins")
	check(runtime.call("command", {"type": "transition"}).get("ok", false), "CH-02 transitions to Kinmen")
	Support.pose_at(runtime, -175.0, 335.0)
	check(runtime.call("command", {"type": "identify-target", "shipId": "ch02-confirmed-prize"}).get("ok", false), "identify before boarding")
	var duel: Dictionary = Support.duel_until_win(runtime, "ch02-confirmed-prize")
	check(duel.get("ok", false), "real duel reaches a captured victory: %s" % str(duel.get("attempt", duel.get("reason", "?"))))
	var settled: Dictionary = runtime.call("command", {"type": "settle-stage"})
	check(settled.get("ok", false) and str(settled.get("outcome", "")) == "success", "CH-02 settles from the real duel capture: " + str(settled.get("outcome", "")))
	_finish()

func _finish() -> void:
	print("STORY_DUEL_MINIGAME assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures > 0 else 0)
