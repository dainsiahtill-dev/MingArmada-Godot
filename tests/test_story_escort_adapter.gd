extends SceneTree
## Escort category: real convoy arrival through native auto-navigation with the
## client kept alive, plus an honest failure when settled before arrival.

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
	var runtime: RefCounted = Support.setup("story-escort")
	check(Support.advance_to(runtime, 3), "playthrough reaches CH-04 with real settlements")
	check(runtime.call("command", {"type": "begin-stage"}).get("ok", false), "CH-04 begins")
	check(runtime.call("command", {"type": "transition"}).get("ok", false), "CH-04 transitions to Xiamen")
	var early: Dictionary = runtime.call("command", {"type": "settle-stage"})
	check(early.get("ok", false) and str(early.get("outcome", "")) == "failure", "settling before arrival is an honest failure")
	check(runtime.call("command", {"type": "retry-stage"}).get("ok", false), "retry keeps the convoy world")
	check(runtime.call("command", {"type": "begin-stage"}).get("ok", false), "second attempt begins")
	check(Support.play_actions(runtime, "CH-04-S1").get("ok", false), "escort plays with real arrival motion")
	var receipts: Array = runtime.call("snapshot").progress.receipts
	check(receipts.back().outcome == "success" and receipts.back().stageId == "CH-04-S1", "CH-04 settles only after the client really arrives")
	_finish()

func _finish() -> void:
	print("STORY_ESCORT_ADAPTER assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures > 0 else 0)
