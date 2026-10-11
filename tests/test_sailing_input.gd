extends SceneTree
## Native scene input path, using generated Godot events rather than direct commands.

var assertions := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://game/scenes/sailing_trial/sailing_trial.tscn").instantiate()
	root.add_child(scene)
	scene.set_physics_process(false)
	await process_frame
	var initial: Dictionary = scene.runtime.snapshot()
	await key(KEY_W, true)
	for tick in 120: scene._physics_process(1.0 / 120.0)
	await key(KEY_W, false)
	check(scene.runtime.snapshot().ship.sailDeployment > initial.ship.sailDeployment, "W raises real sail deployment")
	await key(KEY_D, true)
	for tick in 1200: scene._physics_process(1.0 / 120.0)
	await key(KEY_D, false)
	check(scene.runtime.snapshot().ship.heading > initial.ship.heading + 0.4, "D follows physical key polling into steering solver")
	await key(KEY_2, true)
	await key(KEY_2, false)
	check(scene.tactical, "2 selects native tactical camera")
	await key(KEY_SPACE, true)
	await key(KEY_SPACE, false)
	check(scene.runtime.snapshot().paused, "Space pauses through native unhandled input")
	var paused: Dictionary = scene.runtime.snapshot()
	for tick in 240: scene._physics_process(1.0 / 120.0)
	check(scene.runtime.snapshot() == paused, "paused input path cannot advance state")
	check(scene.world.get_ocean().material_override.get_shader_parameter("simulation_time") == paused.time, "water stays on paused physics time")
	await key(KEY_SPACE, true)
	await key(KEY_SPACE, false)
	check(not scene.runtime.snapshot().paused, "Space resumes native runtime")
	await key(KEY_1, true)
	await key(KEY_1, false)
	check(not scene.tactical, "1 selects native captain camera")
	scene.free()
	print("SAILING_INPUT_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
