extends SceneTree
## Mid-voyage save/restore: one save carries world + progress together, resumes
## at the handoff boundary, completes the same voyage, and rejects tampering.

const Support = preload("res://tests/story_walkthrough_support.gd")
const StorySave = preload("res://game/domain/story_world/story_save.gd")
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
	_test_mid_voyage_save_restore()
	_test_tampered_save_rejected()
	_finish()

func _finish() -> void:
	print("STORY_SAVE_RESTORE assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures > 0 else 0)

func _test_mid_voyage_save_restore() -> void:
	var first: RefCounted = Support.setup("story-restore")
	check(Support.advance_to(first, 12), "voyage reaches the handoff boundary")
	var saved: Dictionary = first.call("save_checkpoint")
	check(saved.get("ok", false), "mid-voyage checkpoint exports world and progress together")
	var second: RefCounted = Support.setup("story-restore-resumed")
	check(second.call("adopt_save", str(saved.json)).get("ok", false), "restored runtime adopts the checkpoint")
	var restored_state: Dictionary = second.call("snapshot").progress
	check(int(restored_state.stageIndex) == 12 and int(restored_state.attempt) == 1, "restored progress resumes at the handoff boundary")
	check(Support.play_from(second, 12), "restored runtime completes the same voyage")
	var second_state: Dictionary = second.call("snapshot").progress
	check(str(second_state.phase) == "complete", "restored run reaches the ending")
	check(bool(second_state.handoff.done), "restored run keeps the handoff marker")

func _test_tampered_save_rejected() -> void:
	var runtime: RefCounted = Support.setup("story-tamper")
	check(Support.advance_to(runtime, 3), "voyage produces a real checkpoint")
	var saved: Dictionary = runtime.call("save_checkpoint")
	check(saved.get("ok", false), "checkpoint available for tampering")
	var parser := JSON.new()
	parser.parse(str(saved.json))
	var tampered: Dictionary = (parser.data as Dictionary).duplicate(true)
	tampered.world.fleet[0].cargo.grain = 99999
	check(not StorySave.validate(JSON.stringify(tampered)).get("ok", true), "tampered world goods break conservation")
	check(not StorySave.validate(str(saved.json) + "x").get("ok", true), "corrupted bytes rejected")
	check(not StorySave.validate("{\"version\":1}").get("ok", true), "foreign save schema rejected")
