extends SceneTree
## Actual Mingqi scene lifecycle regression. Public departure and native course;
## no replaced snapshot/pose, ray fixture or claimed viewport pixel acceptance.
const MingqiScene = preload("res://game/scenes/mingqi/mingqi_scene.gd")
const Settings = preload("res://game/persistence/user_settings.gd")
const AudioCleanup = preload("res://tests/fixtures/audio_cleanup.gd")
var assertions := 0
var failures := 0
func check(value: bool, detail: String) -> bool:
	assertions += 1
	if not value: failures += 1; printerr("FAIL mouse scene: ", detail)
	return value
func _initialize() -> void:
	_run.call_deferred()
func _finish() -> void:
	print("MOUSE_COURSE_SCENE_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
func _release(scene: Node) -> void:
	var playbacks: Array[WeakRef] = AudioCleanup.stop_players(scene)
	scene.free()
	check(await AudioCleanup.wait_for_release(self, playbacks), "actual scene releases its audio playback")
func _tick(scene: Node, seconds: float) -> void:
	scene.call("_physics_process", seconds)
	scene.call("_process", 0.0)
func _player(native: Dictionary) -> Dictionary:
	for ship: Dictionary in native.ships:
		if ship.id == native.playerId: return ship
	return {}
func _run() -> void:
	var scene: Node3D = MingqiScene.new()
	scene.set("settings_storage", Settings.new("user://verification/mouse-course-scene-no-write-%d.json" % OS.get_process_id()))
	root.add_child(scene)
	scene.set_physics_process(false)
	scene.set_process(false)
	if not check(scene.get("startup_receipt").get("ok", false), "actual Mingqi scene completes ordinary native startup"):
		await _release(scene); _finish(); return
	var runtime: RefCounted = scene.get("runtime")
	var ui: CanvasLayer = scene.get("interface")
	ui.close_panel()
	ui.close_menu()
	var accepted: Dictionary = runtime.command({"type": "accept-convoy", "commandId": "mouse-scene-accept", "expectedRevision": runtime.snapshot().campaign.revision})
	check(accepted.get("ok", false), "actual career accepts its convoy through public domain command")
	var departed: Dictionary = runtime.command({"type": "depart", "commandId": "mouse-scene-depart", "expectedRevision": runtime.snapshot().campaign.revision})
	if not check(departed.get("ok", false) and runtime.snapshot().campaign.currentPortId == null, "public departure opens real career sailing"):
		await _release(scene); _finish(); return
	var player: Dictionary = _player(runtime.snapshot().naval)
	var point: Dictionary = {"x": float(player.visual.position.x) + 1000.0, "z": float(player.visual.position.z)}
	var course: Dictionary = runtime.command({"type": "mouse-course", "point": point})
	if not check(course.get("ok", false), "actual departed runtime accepts mouse sailing from authoritative player position"):
		await _release(scene); _finish(); return
	for tick in 20: _tick(scene, 0.05)
	var target: Variant = runtime.simulation.handling_status().get("targetHeading")
	if not check(typeof(target) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(target)), "accepted course remains owned after actual scene callbacks"):
		await _release(scene); _finish(); return
	var before: Dictionary = runtime.snapshot()
	scene.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	var paused: Dictionary = runtime.snapshot()
	check(runtime.is_paused() and paused.runtime.pauseReasons.has("blur"), "real focus-out notification owns runtime blur pause")
	check(paused.naval == before.naval and paused.campaign == before.campaign, "focus-out itself changes no native or campaign authority")
	for tick in 20: _tick(scene, 0.05)
	var frozen: Dictionary = runtime.snapshot()
	check(frozen.naval == before.naval and frozen.campaign == before.campaign, "accepted mouse course freezes full native/campaign state while unfocused")
	check(runtime.simulation.handling_status().get("targetHeading") == target, "blur retains legal course without advancing it")
	runtime.set_held("KeyA", true)
	var resume: Button = ui.find_child("pause", true, false) as Button
	if check(resume != null and resume.is_visible_in_tree() and not resume.disabled and resume.text == "继续", "actual HUD displays an enabled continue action after focus-out"):
		resume.pressed.emit()
	check(not runtime.is_paused() and not runtime.snapshot().runtime.pauseReasons.has("blur"), "actual continue action resumes player/blur pause")
	check(runtime.simulation.handling_status().get("targetHeading") == target, "explicit continue retains the legal mouse course")
	check(runtime.simulation.handling_status().get("targetHeading") == target, "keypress received while blurred cannot replace retained mouse intent")
	for tick in 20: _tick(scene, 0.05)
	var resumed: Dictionary = runtime.snapshot()
	check(resumed.naval.time > frozen.naval.time and resumed.campaign.simulationSeconds > frozen.campaign.simulationSeconds, "resumed actual callbacks advance native and career time")
	check(_player(resumed.naval).visual.position != _player(frozen.naval).visual.position, "resumed course produces real ship motion without replacing its pose")
	await _release(scene)
	_finish()
