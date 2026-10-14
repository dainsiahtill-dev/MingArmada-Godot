extends RefCounted
## Converts an unconsumed world click to a sea-plane intent. It owns no ship,
## camera movement, navigation or authority; the runtime validates the command.
const CLICK_SLOP := 8.0
var _pressed := false
var _press_position := Vector2.ZERO
var _dragged := false
var _gesture_id := 0
func cancel_gesture() -> void:
	_gesture_id += 1
	_pressed = false
	_dragged = false
func cancel_gesture_after_dispatch() -> void:
	# GUI consumption is known only after raw input. Cancel that gesture after
	# dispatch, without letting its cleanup erase a newer press in the same frame.
	_cancel_if_current.call_deferred(_gesture_id)
func _cancel_if_current(gesture_id: int) -> void:
	if gesture_id == _gesture_id: cancel_gesture()
func consume(event: InputEvent) -> Dictionary:
	if event is InputEventMouseMotion:
		if _pressed:
			if not event.position.is_finite(): cancel_gesture()
			elif event.position.distance_to(_press_position) > CLICK_SLOP: _dragged = true
		return {}
	if not event is InputEventMouseButton or not event.position.is_finite(): return {}
	if event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed:
			cancel_gesture()
			return {"type": "stop-sailing"}
		return {}
	if event.button_index != MOUSE_BUTTON_LEFT: return {}
	if event.pressed:
		_gesture_id += 1
		_pressed = true
		_press_position = event.position
		_dragged = false
		return {}
	var clicked: bool = _pressed and not _dragged and event.position.distance_to(_press_position) <= CLICK_SLOP
	cancel_gesture()
	return {"type": "mouse-course", "screen": event.position} if clicked else {}
func ray_to_point(origin: Vector3, direction: Vector3, terrain: Callable, sea_level: float = 0.0, max_distance: float = 4000.0) -> Dictionary:
	if not origin.is_finite() or not direction.is_finite() or not is_finite(sea_level) or not is_finite(max_distance) or max_distance <= 0.0:
		return {"ok": false, "reason": "invalid-ray"}
	if not terrain.is_valid(): return {"ok": false, "reason": "terrain-unavailable"}
	# An upward/parallel ray is sky, even when the camera is below the plane.
	if direction.y >= -0.000001: return {"ok": false, "reason": "above-horizon"}
	var distance_parameter: float = (sea_level - origin.y) / direction.y
	if not is_finite(distance_parameter) or distance_parameter <= 0.0:
		return {"ok": false, "reason": "behind-camera"}
	var point: Vector3 = origin + direction * distance_parameter
	if not point.is_finite() or origin.distance_to(point) > max_distance:
		return {"ok": false, "reason": "outside-view-range"}
	var height: Variant = terrain.call(point.x, point.z)
	if typeof(height) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(height)):
		return {"ok": false, "reason": "invalid-terrain"}
	if float(height) >= sea_level: return {"ok": false, "reason": "land-point"}
	return {"ok": true, "point": {"x": point.x, "z": point.z}}
func project(camera: Camera3D, screen: Vector2, terrain: Callable) -> Dictionary:
	if not is_instance_valid(camera) or not camera.is_inside_tree():
		return {"ok": false, "reason": "camera-unavailable"}
	if not screen.is_finite() or not camera.get_viewport().get_visible_rect().has_point(screen):
		return {"ok": false, "reason": "outside-viewport"}
	return ray_to_point(camera.project_ray_origin(screen), camera.project_ray_normal(screen), terrain, 0.0, camera.far)
