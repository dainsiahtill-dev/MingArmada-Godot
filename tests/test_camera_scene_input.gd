extends SceneTree
## Actual Scene callback routing and native authority contracts. This is CPU
## input evidence; GUI consumption and viewport pixels are verified separately.
const Settings = preload("res://game/persistence/user_settings.gd")
const AudioCleanup = preload("res://tests/fixtures/audio_cleanup.gd")

class TracedMingqi:
	extends "res://game/scenes/mingqi/mingqi_scene.gd"
	var command_calls := 0
	func _command(intent: Dictionary) -> void:
		command_calls += 1
		super._command(intent)

class TracedPractice:
	extends "res://game/scenes/naval_practice/naval_practice.gd"
	var command_calls := 0
	func _command(intent: Dictionary) -> void:
		command_calls += 1
		super._command(intent)

var assertions := 0
var failures := 0

func check(value: bool, detail: String) -> bool:
	assertions += 1
	if not value: failures += 1; printerr("FAIL camera scene: ", detail)
	return value

func _initialize() -> void:
	_run.call_deferred()

func _release(scene: Node) -> void:
	var playbacks: Array[WeakRef] = AudioCleanup.stop_players(scene)
	scene.free()
	check(await AudioCleanup.wait_for_release(self, playbacks), "actual camera scene releases audio playback")

func _button(index: MouseButton, pressed: bool, position: Vector2 = Vector2(700, 350)) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = index; event.pressed = pressed; event.position = position
	return event

func _pointer(scene: Node, event: InputEvent) -> void:
	scene.call("_input", event)
	scene.call("_unhandled_input", event)

func _drag(scene: Node) -> void:
	_pointer(scene, _button(MOUSE_BUTTON_RIGHT, true))
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(780, 310); motion.relative = Vector2(80, -40)
	motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	scene.call("_unhandled_input", motion)

func _key_f(scene: Node) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_F; event.physical_keycode = KEY_F; event.pressed = true
	scene.call("_input", event)
	scene.call("_unhandled_input", event)

func _targets(scene: Node) -> Dictionary:
	var status: Dictionary = scene.get("sea").call("camera_status")
	var result: Dictionary = {}
	for key: String in ["manual", "mode", "targetYaw", "targetPitch", "targetRadius", "zoom"]:
		result[key] = status.get(key)
	return result

func _blocked(scene: Node, label: String) -> void:
	var before: Dictionary = _targets(scene)
	var commands: int = scene.get("command_calls")
	_drag(scene)
	_pointer(scene, _button(MOUSE_BUTTON_WHEEL_UP, true))
	_key_f(scene)
	check(not scene.get("sea").call("camera_status").get("dragging", true) and _targets(scene) == before, label + " blocks orbit, wheel and recenter without changing camera targets")
	check(scene.get("command_calls") == commands, label + " blocked camera input issues no domain command")

func _actual_water_screen(scene: Node) -> Vector2:
	# Use the actual current camera and injected terrain, never a manufactured
	# projection result. The point must qualify before testing input ownership.
	for y: float in [400.0, 520.0, 650.0, 780.0]:
		for x: float in [550.0, 700.0, 850.0, 1000.0, 1150.0]:
			var screen: Vector2 = Vector2(x, y)
			var projected: Dictionary = scene.get("_mouse_course").project(scene.get("sea").get("camera"), screen, scene.get("heights").sample_height)
			if projected.get("ok", false): return screen
	return Vector2(INF, INF)

func _running_orbit_blocks_course(scene: Node) -> void:
	var runtime: RefCounted = scene.get("runtime")
	var sea: Node3D = scene.get("sea")
	check(runtime.set_pause("player", false).get("ok", false) and runtime.set_pause("blur", false).get("ok", false), "real free-sail Runtime resumes before testing RMB/LMB ownership")
	scene.call("_present", 0.0)
	check(not runtime.is_paused(), "RMB/LMB regression uses actual operational unpaused free sailing")
	for release_right_first: bool in [false, true]:
		# A failing RED may have created a course. Reset it through the public
		# domain API before the second case; do not overwrite private goal state.
		if runtime.simulation.handling_status().has("targetHeading"):
			check(runtime.command({"type":"stop-sailing"}).get("ok", false), "public stop cancels a preceding leaked course before the next gesture case")
		_key_f(scene)
		scene.call("_present", 0.0)
		var screen: Vector2 = _actual_water_screen(scene)
		if not check(screen.is_finite(), "real current free-sail camera resolves an eligible sea click for the chord fixture"): return
		var before: Dictionary = runtime.snapshot().naval
		var commands: int = scene.get("command_calls")
		_drag(scene)
		check(sea.call("camera_status").get("dragging", false), "RMB is actually active before the left-button chord")
		_pointer(scene, _button(MOUSE_BUTTON_LEFT, true, screen))
		if release_right_first:
			# Model a GUI-consumed right release: only raw input sees it. A left
			# press during orbit must never survive to become a later sea course.
			scene.call("_input", _button(MOUSE_BUTTON_RIGHT, false))
		_pointer(scene, _button(MOUSE_BUTTON_LEFT, false, screen))
		check(scene.get("command_calls") == commands and not runtime.simulation.handling_status().has("targetHeading"), "RMB/LMB chord emits no course or domain command; right released first=" + str(release_right_first))
		check(runtime.snapshot().naval == before, "RMB/LMB chord leaves every native sailing/pose field unchanged; right released first=" + str(release_right_first))
		scene.call("_input", _button(MOUSE_BUTTON_RIGHT, false))
	if runtime.simulation.handling_status().has("targetHeading"):
		check(runtime.command({"type":"stop-sailing"}).get("ok", false), "public stop clears any RED leaked course before the normal-click witness")
	_key_f(scene); scene.call("_present", 0.0)
	var normal: Vector2 = _actual_water_screen(scene)
	if not check(normal.is_finite(), "normal click witness also resolves actual eligible sea water"): return
	var commands: int = scene.get("command_calls")
	_pointer(scene, _button(MOUSE_BUTTON_LEFT, true, normal))
	_pointer(scene, _button(MOUSE_BUTTON_LEFT, false, normal))
	check(scene.get("command_calls") == commands + 1 and runtime.simulation.handling_status().has("targetHeading"), "ordinary left sea click still reaches actual mouse sailing after the camera gesture ends")

func _rapid_successive_clicks(scene: Node) -> void:
	var runtime: RefCounted = scene.get("runtime")
	var screen: Vector2 = _actual_water_screen(scene)
	if not check(screen.is_finite(), "rapid-click fixture uses the actual water projection"): return
	var commands: int = scene.get("command_calls")
	_pointer(scene, _button(MOUSE_BUTTON_LEFT, true, screen))
	# Only raw input sees a GUI-consumed release. A second sea press can occur
	# before the event-loop flush; the old deferred cancel must not clear it.
	scene.call("_input", _button(MOUSE_BUTTON_LEFT, false, screen))
	_pointer(scene, _button(MOUSE_BUTTON_LEFT, true, screen))
	await process_frame
	_pointer(scene, _button(MOUSE_BUTTON_LEFT, false, screen))
	check(scene.get("command_calls") == commands + 1 and runtime.simulation.handling_status().has("targetHeading"),
		"old GUI release cleanup cannot swallow a newer sea gesture in the same frame")
	await process_frame
	commands = scene.get("command_calls")
	_pointer(scene, _button(MOUSE_BUTTON_LEFT, true, screen))
	scene.call("_input", _button(MOUSE_BUTTON_LEFT, false, screen))
	await process_frame
	_pointer(scene, _button(MOUSE_BUTTON_LEFT, false, screen))
	check(scene.get("command_calls") == commands, "GUI release still clears its own unfinished gesture")

func _exercise(mingqi: bool) -> void:
	var label: String = "Mingqi" if mingqi else "Practice"
	var scene: Node3D = TracedMingqi.new() if mingqi else TracedPractice.new()
	scene.set("startup_options", {"seed":1650, "campaignId":"camera-input-1650", "captainName":"镜头船长", "staged":true} if mingqi else {"mode":"sail", "staged":true})
	scene.set("settings_storage", Settings.new("user://verification/camera-scene-%s-no-write-%d.json" % [label, OS.get_process_id()]))
	root.add_child(scene)
	scene.set_process(false); scene.set_physics_process(false)
	if not check(scene.get("startup_receipt").get("ok", false), label + " starts actual native scene, source fleet and UI"):
		await _release(scene); return
	var sea: Node3D = scene.get("sea")
	# RED must fail safely when the new Sea API has not been implemented.
	if not check(sea.has_method("handle_camera_input"), label + " actual Sea exposes camera input routing"):
		await _release(scene); return
	if not check(sea.has_method("camera_status") and sea.has_method("cancel_camera_drag") and sea.has_method("recenter_camera"), label + " Sea exposes camera targets, release cancellation and explicit recenter"):
		await _release(scene); return
	var runtime: RefCounted = scene.get("runtime")
	var ui: CanvasLayer = scene.get("interface")
	scene.call("activate_entry")
	if mingqi: ui.close_panel(); ui.close_menu()
	else: scene.call("_command", {"type":"menu", "value":false})
	scene.call("_present", 0.0)
	check(not mingqi or runtime.snapshot().campaign.currentPortId == "xiamen", label + " camera fixture retains the real opening port")
	check(runtime.set_pause("player", true).get("ok", false), label + " public player pause is accepted")
	scene.call("_present", 0.0)
	var authority: Dictionary = runtime.snapshot()
	var defaults: Dictionary = _targets(scene)
	var commands: int = scene.get("command_calls")
	_drag(scene)
	var manual: Dictionary = _targets(scene)
	check(sea.call("camera_status").get("dragging", false) and manual.manual == true and manual != defaults, label + " paused world RMB drag creates actual manual orbit targets")
	# Only raw _input sees this release, as when the GUI consumes it. It must
	# cancel drag but retain the chosen view instead of silently recentering.
	scene.call("_input", _button(MOUSE_BUTTON_RIGHT, false))
	check(not sea.call("camera_status").get("dragging", true) and _targets(scene) == manual, label + " GUI-consumed RMB release cancels dragging and retains manual targets")
	var zoom_before: float = sea.get("zoom")
	_pointer(scene, _button(MOUSE_BUTTON_WHEEL_UP, true))
	check(float(sea.get("zoom")) < zoom_before, label + " paused unhandled wheel zooms in through actual Sea camera intent")
	scene.call("_present", 0.0)
	check(float(sea.get("zoom")) < zoom_before, label + " full scene presentation cannot overwrite wheel intent with a stale legacy zoom")
	var zoom_in: float = sea.get("zoom")
	_pointer(scene, _button(MOUSE_BUTTON_WHEEL_DOWN, true))
	check(float(sea.get("zoom")) > zoom_in, label + " unhandled wheel down reverses the zoom direction")
	_key_f(scene)
	check(_targets(scene) == defaults and not sea.call("camera_status").get("dragging", true), label + " F explicitly restores default following view and zoom")
	check(scene.get("command_calls") == commands, label + " camera drag, release, wheel and F issue no domain command")
	var after: Dictionary = runtime.snapshot()
	check(after.naval == authority.naval and after.get("campaign", {}) == authority.get("campaign", {}), label + " observing while paused changes no ship pose, sailing state or campaign authority")
	_drag(scene)
	ui.hide(); scene.call("_present", 0.0)
	check(not sea.call("camera_status").get("dragging", true), label + " hiding actual HUD cancels active camera drag")
	_blocked(scene, label + " hidden HUD")
	ui.show(); scene.call("_present", 0.0); _key_f(scene)

	_drag(scene)
	if mingqi: ui.open_menu()
	else: scene.call("_command", {"type":"menu", "value":true})
	scene.call("_present", 0.0)
	check(not sea.call("camera_status").get("dragging", true), label + " opening actual menu cancels a pending camera drag")
	_blocked(scene, label + " menu")
	if mingqi: ui.close_menu()
	else: scene.call("_command", {"type":"menu", "value":false})
	if mingqi: ui.open_panel("convoy")
	else: scene.call("_command", {"type":"chart", "value":true})
	scene.call("_present", 0.0)
	_blocked(scene, label + " actual chart/panel")
	if mingqi: ui.close_panel()
	else: scene.call("_command", {"type":"chart", "value":false})

	_drag(scene)
	scene.call("_command", {"type":"open-settings"})
	check(not sea.call("camera_status").get("dragging", true), label + " opening actual settings cancels a pending camera drag")
	_blocked(scene, label + " settings")
	scene.get("services").close_settings()
	scene.call("_present", 0.0)
	var editor := LineEdit.new()
	ui.get("_screen").add_child(editor); editor.grab_focus()
	check(scene.get_viewport().gui_get_focus_owner() == editor, label + " fixture owns an actual focused editable UI control")
	_blocked(scene, label + " editable focus")
	editor.release_focus(); editor.free()
	_drag(scene)
	scene.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	check(not sea.call("camera_status").get("dragging", true), label + " real window focus-out notification cancels camera drag")
	after = runtime.snapshot()
	check(after.naval == authority.naval and after.get("campaign", {}) == authority.get("campaign", {}), label + " all camera and modal callbacks preserve actual frozen native/campaign authority")
	if not mingqi:
		_running_orbit_blocks_course(scene)
		await _rapid_successive_clicks(scene)
	else:
		ui.close_panel(); ui.close_menu()
		# Earlier checks deliberately issue several modal callbacks inside one
		# frame. Reset each owner through the public runtime before departure.
		runtime.set_pause("menu",false); runtime.set_pause("player",false); runtime.set_pause("blur",false)
		var accepted: Dictionary = runtime.command({"type":"accept-convoy","commandId":"gesture-accept","expectedRevision":runtime.snapshot().campaign.revision})
		var departed: Dictionary = runtime.command({"type":"depart","commandId":"gesture-depart","expectedRevision":runtime.snapshot().campaign.revision}) if accepted.get("ok",false) else {}
		if check(accepted.get("ok",false) and departed.get("ok",false),"Mingqi rapid gesture test leaves port through actual contract and departure commands: " + JSON.stringify({"accepted":accepted,"departed":departed,"pauses":runtime.snapshot().runtime.pauseReasons})):
			ui.close_panel(); scene.call("_present",0.0)
			await _rapid_successive_clicks(scene)
	await _release(scene)

func _run() -> void:
	root.size = Vector2i(1600, 900)
	await _exercise(true)
	await _exercise(false)
	print("CAMERA_SCENE_INPUT_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
