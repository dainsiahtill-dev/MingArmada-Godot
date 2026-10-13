extends SceneTree
## Projection/gesture mathematics only; actual scene input and GPU belong to the
## root native verification. No synthetic snapshot or replacement camera world.
var assertions := 0
var failures := 0
func check(value: bool, detail: String) -> void:
	assertions += 1
	if not value: failures += 1; printerr("FAIL mouse projection: ", detail)
func _initialize() -> void:
	var path := "res://game/scenes/common/mouse_course_projection.gd"
	if not ResourceLoader.exists(path):
		check(false, "shared sea-plane course projection exists")
		_finish()
		return
	var script: Script = load(path)
	var helper: RefCounted = script.new()
	var deep: Callable = func(_x: float, _z: float) -> float: return -80.0
	var straight: Dictionary = helper.call("ray_to_point", Vector3(10, 20, 30), Vector3.DOWN, deep)
	check(straight.get("ok", false) and straight.get("point") == {"x": 10.0, "z": 30.0}, "downward ray returns its actual XZ sea-plane point")
	var diagonal: Dictionary = helper.call("ray_to_point", Vector3(0, 10, 0), Vector3(1, -2, 3), deep)
	check(diagonal.get("ok", false) and diagonal.get("point") == {"x": 5.0, "z": 15.0}, "ray intersection handles an unnormalized direction without altering world scale")
	var rejected: Array = [
		[Vector3(0, 10, 0), Vector3.RIGHT],
		[Vector3(0, 10, 0), Vector3.UP],
		[Vector3(0, -10, 0), Vector3.DOWN],
		[Vector3(INF, 10, 0), Vector3.DOWN],
		[Vector3(0, 10, 0), Vector3(0, NAN, 0)],
		[Vector3(0, 10, 0), Vector3.ZERO],
		[Vector3(0, 10, 0), Vector3(1, -0.00001, 0)],
	]
	for ray: Array in rejected:
		check(not helper.call("ray_to_point", ray[0], ray[1], deep).get("ok", true), "horizon, behind, nonfinite or distant intersection is rejected")
	for height: float in [0.0, 10.0, NAN]:
		var terrain: Callable = func(_x: float, _z: float) -> float: return height
		check(not helper.call("ray_to_point", Vector3(0, 10, 0), Vector3.DOWN, terrain).get("ok", true), "actual land or invalid terrain sample cannot become a mouse course")
	check(not helper.call("ray_to_point", Vector3(0, 10, 0), Vector3.DOWN, Callable()).get("ok", true), "missing terrain sampler is rejected")
	check(not helper.call("project", null, Vector2.ZERO, deep).get("ok", true), "missing actual camera is rejected before ray projection")
	check(helper.call("consume", _button(MOUSE_BUTTON_LEFT, true, Vector2(100, 100))).is_empty(), "left press records intent without issuing a command")
	var clicked: Dictionary = helper.call("consume", _button(MOUSE_BUTTON_LEFT, false, Vector2(103, 100)))
	check(clicked.get("type") == "mouse-course" and clicked.get("screen") == Vector2(103, 100), "small pointer jitter preserves a left click")
	helper.call("consume", _button(MOUSE_BUTTON_LEFT, true, Vector2(100, 100)))
	var dragged := InputEventMouseMotion.new(); dragged.position = Vector2(120, 100)
	helper.call("consume", dragged)
	check(helper.call("consume", _button(MOUSE_BUTTON_LEFT, false, Vector2(100, 100))).is_empty(), "dragging back to press origin cannot accidentally issue a course")
	helper.call("consume", _button(MOUSE_BUTTON_LEFT, true, Vector2(100, 100)))
	helper.call("cancel_gesture")
	check(helper.call("consume", _button(MOUSE_BUTTON_LEFT, false, Vector2(100, 100))).is_empty(), "UI or pause cancellation discards a pending world click")
	check(helper.call("consume", _button(MOUSE_BUTTON_MIDDLE, true, Vector2.ZERO)).get("type") == "stop-sailing", "middle press emits a stop intent")
	check(helper.call("consume", _button(MOUSE_BUTTON_MIDDLE, false, Vector2.ZERO)).is_empty(), "middle release does not repeat stop")
	check(helper.call("consume", _button(MOUSE_BUTTON_RIGHT, true, Vector2.ZERO)).is_empty(), "right mouse remains available to existing actions")
	_finish()
func _button(index: MouseButton, pressed: bool, position: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = index; event.pressed = pressed; event.position = position
	return event
func _finish() -> void:
	print("MOUSE_COURSE_PROJECTION_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
