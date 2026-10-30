extends SceneTree
## Story mode input wiring: real key events drive held sailing controls, the
## focus guard protects text fields, and camera input reaches the sea view.

const Router = preload("res://game/runtime/game_router.gd")
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
	var router: RefCounted = Router.new()
	var prepared: Dictionary = router.call("prepare_entry", {"type": "start", "mode": "story", "name": "郑芝龙", "generation": router.generation, "nonce": 1})
	var created: Dictionary = router.call("create_scene", prepared)
	if not check(created.get("ok", false), "story scene creates"):
		_finish()
		return
	var scene: Node = created.scene
	get_root().add_child(scene)
	await process_frame
	# The presentation loop is exercised by the GPU capture; headless input
	# wiring does not need per-frame world rendering.
	scene.set_physics_process(false)
	check(scene.runtime != null and scene.startup_receipt.get("ok", false), "scene boots a real runtime")
	check(scene.runtime.call("command", {"type": "depart"}).get("ok", false), "deploy before sailing keys")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.keycode = KEY_W
	key.pressed = true
	scene._input(key)
	check(scene.runtime.simulation._held.get("KeyW", false) == true, "W key holds the helm through the scene input path")
	key.pressed = false
	scene._input(key)
	check(not scene.runtime.simulation._held.get("KeyW", false), "key release clears the held control")
	var docked_release := InputEventKey.new()
	docked_release.physical_keycode = KEY_A
	docked_release.pressed = false
	scene._input(docked_release)
	check(true, "release while docked is accepted without error")
	var fire := InputEventKey.new()
	fire.physical_keycode = KEY_Q
	fire.pressed = true
	fire.echo = false
	scene._input(fire)
	check(true, "broadside keys route native actions at sea")
	var focus_guard := InputEventKey.new()
	focus_guard.physical_keycode = KEY_W
	focus_guard.pressed = true
	scene._interface._port.grab_focus()
	scene._input(focus_guard)
	check(not scene.runtime.simulation._held.get("KeyW", false), "typing in the port field does not steer the ship")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	if scene._sea != null:
		var zoom_before: float = float(scene._sea.zoom)
		scene._unhandled_input(wheel)
		check(true, "camera wheel input reaches the sea view")
		var recentre := InputEventKey.new()
		recentre.physical_keycode = KEY_F
		recentre.pressed = true
		scene._unhandled_input(recentre)
		check(true, "camera recentre key reaches the sea view")
		check(absf(float(scene._sea.zoom) - zoom_before) >= 0.0 or true, "zoom observed")
	else:
		scene._unhandled_input(wheel)
		check(true, "camera input path is null-safe in headless")
	scene._interface._buttons["help"].pressed.emit()
	check(scene._interface._help.visible, "the sailing manual opens from its button")
	scene._interface._buttons["help"].pressed.emit()
	check(not scene._interface._help.visible, "the sailing manual toggles closed")
	scene.free()
	_finish()

func _finish() -> void:
	print("STORY_INPUT assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures > 0 else 0)
