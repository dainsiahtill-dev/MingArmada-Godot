extends SceneTree
const Scene = preload("res://game/scenes/legacy/legacy_scene.gd")
const Runtime = preload("res://game/runtime/legacy_runtime.gd")
const Settings = preload("res://game/persistence/user_settings.gd")
class ReadOnlyStorage extends "res://game/persistence/save_coordinator.gd":
	var writes := 0
	func write_checkpoint(_raw: String) -> Dictionary:
		writes += 1
		return {"ok":false,"reason":"read-only-slot"}
var assertions := 0
var failures := 0
func check(value: bool, detail: String) -> void:
	assertions += 1
	if not value: failures += 1; printerr("FAIL: ",detail)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/legacy-runtime-reference.json"))
	var raw: String = fixtures.careerCheckpoints["14"]
	var old_title: String=root.title; var old_ticks: int=Engine.physics_ticks_per_second
	root.title="staging-sentinel"; Engine.physics_ticks_per_second=120
	var staged:=Scene.new(); staged.startup_options={"staged":true}
	staged.settings_storage=Settings.new("user://tests/legacy-staging-settings-%s.json" % OS.get_process_id())
	root.add_child(staged); await process_frame; staged.set_physics_process(false)
	check(root.title=="staging-sentinel" and Engine.physics_ticks_per_second==120,"staged career defers global title and physics rate")
	check(staged.runtime.is_paused(),"staged career starts audio and sea on loading pause")
	check(staged.has_method("activate_entry"),"ready career exposes commit activation")
	if staged.has_method("activate_entry"):
		staged.activate_entry()
		check(Engine.physics_ticks_per_second==60 and not staged.runtime.is_paused(),"activation applies native rate and releases new-career loading")
	staged.queue_free(); await process_frame; await process_frame
	root.title=old_title; Engine.physics_ticks_per_second=old_ticks
	var slot := ReadOnlyStorage.new()
	var scene := Scene.new()
	scene.initial_save = raw; scene.storage = slot
	scene.settings_storage = Settings.new("user://tests/legacy-startup-settings-%s.json" % OS.get_process_id())
	root.add_child(scene); await process_frame; scene.set_physics_process(false)
	check(scene.startup_receipt.get("ok",false),"ordinary continue succeeds with read-only checkpoint storage")
	check(slot.writes == 0,"ordinary continue does not write or rotate the user's checkpoint")
	check(scene.sea != null and scene.interface != null,"restored career builds real world and UI")
	if scene.interface:
		check(scene.interface.is_menu_open() and "loading" in scene.runtime.snapshot().runtime.pauseReasons,"restored career waits for explicit Continue before sailing")
		scene.interface.close_menu()
		check(not ("loading" in scene.runtime.snapshot().runtime.pauseReasons),"Continue releases loading pause through actual UI")
	scene.queue_free(); await process_frame; await process_frame
	var bad := Scene.new(); bad.initial_save = "{broken"; bad.storage = slot
	root.add_child(bad); await process_frame
	check(not bad.startup_receipt.get("ok",true) and bad.sea == null,"invalid saved career returns a nonfatal startup receipt without world")
	check(slot.writes == 0,"invalid continue retains checkpoint bytes")
	bad.queue_free(); await process_frame; await process_frame
	await create_timer(0.08).timeout
	print("LEGACY_STARTUP_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
