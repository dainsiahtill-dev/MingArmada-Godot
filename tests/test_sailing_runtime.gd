extends SceneTree

const Runtime = preload("res://game/runtime/sailing_runtime.gd")
const Hud = preload("res://game/ui/sailing_hud.gd")
var failures := 0
var assertions := 0

func _initialize() -> void: _run.call_deferred()

func check(condition: bool, detail: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", detail)

func _run() -> void:
	var sea := func(_x: float, _z: float) -> float: return -24.0
	var runtime := Runtime.new()
	check(runtime.configure(sea), "native ship initializes on injected water terrain")
	var start: Dictionary = runtime.snapshot()
	for tick in 1200: runtime.advance(Runtime.STEP)
	var moving: Dictionary = runtime.snapshot()
	check(absf(moving.time - 10.0) < 1e-9, "120Hz runtime owns exact consumed simulation time")
	check(Vector2(moving.ship.position.x, moving.ship.position.z).distance_to(Vector2(start.ship.position.x, start.ship.position.z)) > 8.0, "sails produce real travel without engine throttle")
	runtime.command({"type": "turn", "value": 0.5})
	for tick in 1200: runtime.advance(Runtime.STEP)
	var turning: Dictionary = runtime.snapshot()
	check(turning.ship.heading > moving.ship.heading + 0.4, "bounded assisted steering produces a real course change")
	runtime.command({"type": "pause", "value": true})
	var paused: Dictionary = runtime.snapshot()
	check(runtime.advance(60.0) == 0.0 and runtime.snapshot() == paused, "pause accepts no elapsed time and changes no pose")
	check(not runtime.command({"type": "sail", "value": NAN}).ok and runtime.snapshot() == paused, "invalid input is rejected atomically")
	runtime.command({"type": "pause", "value": false})
	check(absf(runtime.advance(Runtime.STEP) - Runtime.STEP) < 1e-12, "resume advances only one fixed step")
	var partitioned := Runtime.new()
	partitioned.configure(sea)
	for tick in 600: partitioned.advance(1.0 / 60.0)
	check(partitioned.snapshot().ship == moving.ship, "60Hz accepted frames produce same 120Hz numerical ship")
	var hud := Hud.new()
	root.add_child(hud)
	await process_frame
	var buttons := hud.find_children("*", "Button", true, false)
	check(buttons.size() == 4, "all native HUD actions are present")
	for button: Button in buttons:
		check(button.focus_mode == Control.FOCUS_NONE, "mouse HUD button cannot consume Space pause hotkey")
	hud.queue_free()
	await process_frame
	print("SAILING_RUNTIME_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
