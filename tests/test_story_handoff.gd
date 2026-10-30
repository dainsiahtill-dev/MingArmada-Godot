extends SceneTree
## Handoff category: the single CH-12 world transfer with a real manifest,
## duplicate refusal, no heal/no money change, and the protagonist flip.

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
	var runtime: RefCounted = Support.setup("story-handoff")
	check(Support.advance_to(runtime, 11), "playthrough reaches CH-12 with real settlements")
	check(runtime.call("command", {"type": "begin-stage"}).get("ok", false), "CH-12 begins")
	check(runtime.call("command", {"type": "transition"}).get("ok", false), "CH-12 transitions to Xiamen")
	var silver_before: int = int(runtime.world.state.silver)
	var hull_before: int = int(runtime.world.state.fleet[0].hull)
	check(Support.play_actions(runtime, "CH-12-S1").get("ok", false), "handoff settles from the real transfer")
	check(not runtime.call("command", {"type": "transfer-manifest", "to": "zheng-chenggong", "manifest": {"ships": ["player"], "people": []}}).get("ok", true), "duplicate world transfer refused")
	check(int(runtime.world.state.silver) == silver_before and int(runtime.world.state.fleet[0].hull) == hull_before, "handoff heals nothing and moves no money")
	var state: Dictionary = runtime.call("snapshot").progress
	check(bool(state.handoff.done) and str(state.handoff.to) == "zheng-chenggong", "progress records the single handoff")
	check(str(state.protagonistId) == "zheng-chenggong", "protagonist flips to the son")
	check(runtime.world.state.transfers.size() == 1, "exactly one world transfer record")
	_finish()

func _finish() -> void:
	print("STORY_HANDOFF assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures > 0 else 0)
