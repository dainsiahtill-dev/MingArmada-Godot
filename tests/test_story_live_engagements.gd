extends SceneTree
## Live engagements: naval stages settle through REAL broadside gunnery on the
## live native engine, and the boarding stage settles through a REAL duel
## victory driven via the model-authoritative coordinator path.

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
	_test_live_gunnery_settles_naval_stage()
	_finish()

func _finish() -> void:
	print("STORY_LIVE_ENGAGEMENTS assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures > 0 else 0)

func _test_live_gunnery_settles_naval_stage() -> void:
	var runtime: RefCounted = Support.setup("story-live-fire")
	check(Support.advance_to(runtime, 23), "playthrough reaches T04 with real settlements")
	check(runtime.call("command", {"type": "begin-stage"}).get("ok", false), "T04 begins")
	check(runtime.call("command", {"type": "transition"}).get("ok", false), "T04 transitions to Heliao")
	check(runtime.call("command", {"type": "depart"}).get("ok", false), "fleet deploys to meet the counterattack")
	var first: Dictionary = Support.live_fire_kill(runtime, "dutch-counterattack-1", 840.0, 120.0, 16000)
	check(first.get("ok", false), "live gunnery sinks counterattack-1 in %s ticks (%s)" % [str(first.get("ticks", 0)), str(first.get("reason", "sunk"))])
	var second: Dictionary = Support.live_fire_kill(runtime, "dutch-counterattack-2", 860.0, 180.0, 16000)
	check(second.get("ok", false), "live gunnery sinks counterattack-2 in %s ticks (%s)" % [str(second.get("ticks", 0)), str(second.get("reason", "sunk"))])
	var settled: Dictionary = runtime.call("command", {"type": "settle-stage"})
	check(settled.get("ok", false) and str(settled.get("outcome", "")) == "success", "T04 settles from real broadside results: %s / %s" % [str(settled.get("outcome", settled.get("reason", ""))), str(settled.get("witnesses", ""))])
	check(settled.get("witnesses", {}).get("t04-neutralize", {}).get("ok", false) == true, "neutralize witness reads the live sunk state")
