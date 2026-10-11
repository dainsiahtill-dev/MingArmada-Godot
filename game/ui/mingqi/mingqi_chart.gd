extends Control
## Read-only chart, drawing actual world coordinates and catalog routes.
signal point_requested(point: Dictionary)
var vessels: Dictionary = {}
var ports: Dictionary = {}
var routes: Dictionary = {}
var selected_id := ""
var _bounds := Rect2(-430, -390, 900, 830)

func _ready() -> void:
	custom_minimum_size = Vector2(360, 240)
	mouse_filter = Control.MOUSE_FILTER_STOP

func apply_data(current: Dictionary, harbors: Dictionary, lanes: Dictionary, selected: String) -> void:
	vessels = current.duplicate(true)
	ports = harbors.duplicate(true)
	routes = lanes.duplicate(true)
	selected_id = selected
	var minimum := Vector2(-430, -390)
	var maximum := Vector2(470, 440)
	for ship in vessels.values():
		var position: Dictionary = ship.get("pose", {}).get("position", {})
		var point := Vector2(float(position.get("x", 0)), float(position.get("z", 0)))
		minimum = minimum.min(point - Vector2(80, 80))
		maximum = maximum.max(point + Vector2(80, 80))
	_bounds = Rect2(minimum, maximum - minimum)
	queue_redraw()

func _map(point: Dictionary) -> Vector2:
	return Vector2((float(point.get("x", 0)) - _bounds.position.x) / _bounds.size.x, (float(point.get("z", 0)) - _bounds.position.y) / _bounds.size.y) * size

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("0b282e"))
	for x in range(1, 6): draw_line(Vector2(size.x * x / 6.0, 0), Vector2(size.x * x / 6.0, size.y), Color("25474b"))
	for z in range(1, 5): draw_line(Vector2(0, size.y * z / 5.0), Vector2(size.x, size.y * z / 5.0), Color("25474b"))
	for route in routes.values():
		var line := PackedVector2Array()
		for point in route.get("points", []): line.append(_map(point))
		if line.size() > 1: draw_polyline(line, Color("bc9b62") if route.get("minimumDepth", 8) < 3 else Color("599591"), 2.0, true)
	var font := ThemeDB.fallback_font
	for port in ports.values():
		var position := _map(port.get("position", {}))
		draw_rect(Rect2(position - Vector2(4, 4), Vector2(8, 8)), Color("e0c68e"))
		draw_string(font, position + Vector2(8, -7), str(port.get("name", "港口")), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("e9d9b8"))
	for ship in vessels.values():
		var position := _map(ship.get("pose", {}).get("position", {}))
		var color := Color("e19886") if ship.get("ownerId") == "enemy" else Color("e7dabb") if ship.get("representation") == "near" else Color("bf9d61")
		draw_circle(position, 5, color)
		if ship.get("id") == selected_id: draw_arc(position, 9, 0, TAU, 24, Color("ffde94"), 2)
		draw_line(position, position + Vector2(cos(float(ship.get("pose", {}).get("heading", 0))), sin(float(ship.get("pose", {}).get("heading", 0)))) * 12, color, 1.5)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var relative: Vector2 = event.position / size
		point_requested.emit({"x": _bounds.position.x + relative.x * _bounds.size.x, "z": _bounds.position.y + relative.y * _bounds.size.y})
		accept_event()
