extends SceneTree
## Prepares an endgame checkpoint through the real settlement layer: plays the
## voyage to the T10 boundary (headless), then writes the checkpoint where the
## GPU endgame capture can restore it. No save slot of the user is touched —
## the output lands in user://saves/story-endgame-prep.json.

const Support = preload("res://tests/story_walkthrough_support.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var runtime: RefCounted = Support.setup("story-endgame-prep")
	if not Support.advance_to(runtime, 29):
		print("ENDGAME_PREP_READY=false reason=advance-failed")
		quit(1)
		return
	if not runtime.call("command", {"type": "begin-stage"}).get("ok", false):
		print("ENDGAME_PREP_READY=false reason=begin-failed")
		quit(1)
		return
	if not runtime.call("command", {"type": "transition"}).get("ok", false):
		print("ENDGAME_PREP_READY=false reason=transition-failed")
		quit(1)
		return
	var saved: Dictionary = runtime.call("save_checkpoint")
	if not saved.get("ok", false):
		print("ENDGAME_PREP_READY=false reason=save-failed")
		quit(1)
		return
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.make_dir_recursive("saves")
	var file := FileAccess.open("user://saves/story-endgame-prep.json", FileAccess.WRITE)
	if file == null:
		print("ENDGAME_PREP_READY=false reason=write-failed")
		quit(1)
		return
	file.store_string(str(saved.json))
	file.close()
	print("ENDGAME_PREP_READY=true bytes=", str(saved.json).length())
	quit(0)
