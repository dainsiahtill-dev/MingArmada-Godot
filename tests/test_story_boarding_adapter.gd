extends SceneTree
## Boarding category: real identify + boarding gates on live native positions,
## decoy misstep earns no credit and costs standing, forged settle rejected.

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
	var runtime: RefCounted = Support.setup("story-boarding")
	check(Support.advance_to(runtime, 1), "playthrough reaches CH-02 with real settlements")
	check(runtime.call("command", {"type": "begin-stage"}).get("ok", false), "CH-02 begins")
	check(runtime.call("command", {"type": "transition"}).get("ok", false), "CH-02 transitions to Kinmen")
	check(not runtime.call("command", {"type": "settle-stage", "success": true}).get("ok", true), "forged settle outcome rejected")
	Support.pose_at(runtime, -155.0, 335.0)
	var identified: Dictionary = runtime.call("command", {"type": "identify-target", "shipId": "ch02-confirmed-prize"})
	check(identified.get("ok", false) and identified.identity.flag == "lead-seal-blue", "identify reads real world identity fields")
	Support.pose_at(runtime, -65.0, 322.0)
	check(runtime.call("command", {"type": "resolve-boarding", "targetId": "ch02-decoy-merchant", "captured": true, "disposition": "capture", "battleId": "b-decoy"}).get("ok", false), "boarding the decoy settles for real")
	var wrong: Dictionary = runtime.call("command", {"type": "settle-stage"})
	check(wrong.get("ok", false) and str(wrong.get("outcome", "")) == "failure", "wrong target earns no objective credit")
	check(int(runtime.world.state.relations.voc) < 0, "misstep costs standing")
	check(runtime.call("command", {"type": "retry-stage"}).get("ok", false), "retry keeps the world")
	check(runtime.call("command", {"type": "begin-stage"}).get("ok", false), "second attempt begins")
	check(Support.play_actions(runtime, "CH-02-S1").get("ok", false), "second attempt boards the confirmed prize")
	var receipts: Array = runtime.call("snapshot").progress.receipts
	check(receipts.back().outcome == "success" and receipts.back().stageId == "CH-02-S1", "capture of the confirmed prize settles")
	_finish()

func _finish() -> void:
	print("STORY_BOARDING_ADAPTER assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures > 0 else 0)
