extends SceneTree
## Whole-voyage walkthrough: 开局→CH01..CH20→CH12 real handoff→T01..T10→结局
## through real settlements (dock gates, deliveries, captures, charters,
## manifests, terms, handover), with a real failure+retry and mid-voyage
## save/restore. Fixture poses/funding/speed are documented in the support
## module; every objective is re-verified at settle time.

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
	_test_full_voyage_with_failure_and_retry()
	_finish()

func _finish() -> void:
	print("STORY_VOYAGE_WALKTHROUGH assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures > 0 else 0)

func _test_full_voyage_with_failure_and_retry() -> void:
	var runtime: RefCounted = Support.setup("story-walk")
	# Real failure first: settle CH-01 with nothing done, then retry keeps world.
	check(runtime.call("command", {"type": "begin-stage"}).get("ok", false), "voyage begins at CH-01")
	var failed: Dictionary = runtime.call("command", {"type": "settle-stage"})
	check(failed.get("ok", false) and str(failed.get("outcome", "")) == "failure", "unfinished CH-01 settles honest failure")
	check(runtime.call("command", {"type": "retry-stage"}).get("ok", false), "retry keeps the world (保损)")
	check(Support.play_from(runtime, 0), "full voyage plays CH-01..T10 to completion")
	var state: Dictionary = runtime.call("snapshot").progress
	check(str(state.phase) == "complete", "campaign reaches the ending phase")
	check(state.receipts.size() == 31, "thirty stage receipts plus the retained honest failure receipt, got %d" % state.receipts.size())
	check(bool(state.handoff.done) and str(state.handoff.to) == "zheng-chenggong", "CH-12 handoff marked after the real transfer")
	check(int(runtime.world.state.silver) >= 0, "world economy stays finite through the voyage")
	check(str(state.protagonistId) == "zheng-chenggong", "protagonist flips to the son after the handoff")
	var summary: Dictionary = runtime.call("voyage_summary")
	check(int(summary.get("stages", 0)) == 30 and int(summary.get("attempts", 0)) == 31, "the epilogue ledger counts all thirty stages plus the honest failure")
	check(bool(summary.get("handoff", false)) and str(summary.get("protagonist", "")) == "zheng-chenggong", "the epilogue records the handoff and the son's command")
	check(int(summary.get("days", 0)) >= 1 and int(summary.get("fleet", 0)) >= 2, "the epilogue carries real voyage facts")
