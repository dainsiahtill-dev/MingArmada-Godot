extends SceneTree
## Land category: real land-control settlement plus shore load/deliver/withdraw
## with an honest failure before the landing.

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
	var runtime: RefCounted = Support.setup("story-land")
	check(Support.advance_to(runtime, 13), "playthrough reaches CH-14 with real settlements")
	check(runtime.call("command", {"type": "begin-stage"}).get("ok", false), "CH-14 begins")
	check(runtime.call("command", {"type": "transition"}).get("ok", false), "CH-14 transitions to Penghu")
	var early: Dictionary = runtime.call("command", {"type": "settle-stage"})
	check(early.get("ok", false) and str(early.get("outcome", "")) == "failure", "settling before the landing is an honest failure")
	check(runtime.call("command", {"type": "retry-stage"}).get("ok", false), "retry keeps the shore world")
	check(runtime.call("command", {"type": "begin-stage"}).get("ok", false), "second attempt begins")
	check(Support.play_actions(runtime, "CH-14-S1").get("ok", false), "land, load, deliver and withdraw play for real")
	var receipts: Array = runtime.call("snapshot").progress.receipts
	check(receipts.back().outcome == "success" and receipts.back().stageId == "CH-14-S1", "CH-14 settles from real shore settlements")
	check(receipts.back().objectiveProgress["ch14-land"] == 1, "land-control witness holds at settle time")
	_finish()

func _finish() -> void:
	print("STORY_LAND_ADAPTER assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures > 0 else 0)
