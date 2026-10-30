extends SceneTree
## Port category: real recruit and conditional charter transactions with costs
## and conditions; settling before signing earns nothing.

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
	var runtime: RefCounted = Support.setup("story-port")
	check(Support.advance_to(runtime, 4), "playthrough reaches CH-05 with real settlements")
	check(runtime.call("command", {"type": "begin-stage"}).get("ok", false), "CH-05 begins")
	check(runtime.call("command", {"type": "transition"}).get("ok", false), "CH-05 transitions to Xiamen")
	var early: Dictionary = runtime.call("command", {"type": "settle-stage"})
	check(early.get("ok", false) and str(early.get("outcome", "")) == "failure", "settling before the recruit is an honest failure")
	check(runtime.call("command", {"type": "retry-stage"}).get("ok", false), "retry keeps the port world")
	check(runtime.call("command", {"type": "begin-stage"}).get("ok", false), "second attempt begins")
	check(Support.play_actions(runtime, "CH-05-S1").get("ok", false), "recruit signs on for real cost")
	var receipts: Array = runtime.call("snapshot").progress.receipts
	check(receipts.back().outcome == "success" and receipts.back().stageId == "CH-05-S1", "CH-05 settles from the signed contract")
	var second: RefCounted = Support.setup("story-port-10")
	check(Support.advance_to(second, 9), "playthrough reaches CH-10")
	check(second.call("command", {"type": "begin-stage"}).get("ok", false), "CH-10 begins")
	check(second.call("command", {"type": "transition"}).get("ok", false), "CH-10 transitions to Malacca")
	check(Support.play_actions(second, "CH-10-S1").get("ok", false), "both port charters settle with real costs")
	var receipts10: Array = second.call("snapshot").progress.receipts
	check(receipts10.back().outcome == "success" and receipts10.back().stageId == "CH-10-S1", "CH-10 settles both permissions separately")
	_finish()

func _finish() -> void:
	print("STORY_PORT_ADAPTER assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures > 0 else 0)
