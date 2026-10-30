extends SceneTree
## Fixture isolation: synthetic fixtures never write the formal save slot, the
## research demo keeps its synthetic-scope declarations, and a real story voyage
## writes nothing to user://saves unless a checkpoint is explicitly stored.

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
	var demo := FileAccess.open("res://game/research/demos/story_campaign_flow_experiment.gd", FileAccess.READ)
	check(demo != null, "synthetic demo source present")
	var text: String = demo.get_as_text() if demo != null else ""
	check(text.contains("synthetic-progress-fixture"), "demo keeps its synthetic scope declaration")
	check(text.contains("主线进度合成实验 · 非真实任务通关"), "demo keeps the non-real-completion heading")
	var before := _save_slots()
	var runtime: RefCounted = Support.setup("story-isolation")
	check(Support.advance_to(runtime, 3), "fixture voyage runs through real settlements")
	var after := _save_slots()
	check(before == after, "fixture voyages write no formal save slot")
	check(not after.has("story-v1.json"), "story save slot untouched by fixtures")
	_finish()

func _save_slots() -> Dictionary:
	var found := {}
	var dir := DirAccess.open("user://saves")
	if dir == null:
		return found
	for entry in dir.get_files():
		found[entry] = true
	return found

func _finish() -> void:
	print("STORY_FIXTURE_ISOLATION assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures > 0 else 0)
