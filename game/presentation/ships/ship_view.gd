extends Node3D
## Original GLB presentation. Simulation remains the only pose/damage authority.

const AssetLibrary = preload("res://modules/scene_engine/assets/asset_library.gd")
const ShipDamage = preload("res://game/presentation/ships/ship_damage.gd")
signal presentation_event(event: Dictionary)
var _damage = ShipDamage.new()
const KINDS := ["fuchuan", "fisherman", "merchant", "voc", "patrol", "heavy"]
var _models: Array[Node3D] = []
var _library: RefCounted
var _owns_library := false
var _lod := 0
var _time := 0.0
var _snapshot: Dictionary = {}
var _wind: Dictionary = {}
var _mast_yaw: Dictionary = {}
var _barrel_rest: Dictionary = {}
var _recoil: Dictionary = {}
var _next_gun := {"port": 0, "starboard": 0}
var _seen_events: Dictionary = {}
var _disposed := true
var _reduced_motion := false

func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled

func configure(kind: String, asset_library: RefCounted = null) -> bool:
	dispose()
	if not kind in KINDS:
		return false
	_owns_library = asset_library == null
	_library = AssetLibrary.new() if _owns_library else asset_library
	_disposed = false
	_lod = 0
	rotation_order = EulerOrder.EULER_ORDER_YXZ
	for lod in 3:
		var model: Node3D = _library.instantiate_model("res://assets/models/ships/%s-lod%d.glb" % [kind, lod])
		if model == null:
			dispose()
			return false
		model.name = "LOD%d" % lod
		add_child(model)
		model.visible = lod == _lod
		_models.append(model)
		for node in model.find_children("*", "Node3D", true, false):
			if String(node.name).begins_with("mast_") and String(node.name).trim_prefix("mast_").is_valid_int():
				_mast_yaw[node.get_instance_id()] = node.rotation.y
			if String(node.name).begins_with("barrel_"):
				_barrel_rest[node.get_instance_id()] = node.position.z
	_damage.configure(_models)
	return true

func apply_snapshot(ship: Dictionary, wind: Dictionary = {}, consumed: float = 0.0) -> void:
	if _disposed:
		return
	var supplied := float(ship.get("time", _time + maxf(0.0, consumed)))
	if not is_finite(supplied):
		return
	var rewind := supplied < _time - 1.0e-8
	if rewind:
		_recoil.clear()
		_seen_events.clear()
	_snapshot = ship.duplicate(true)
	_wind = wind.duplicate(true)
	if is_finite(consumed) and consumed > 0.0:
		for gun: String in _recoil:
			var offset := float(_recoil[gun]) * exp(-consumed * 9.0)
			_recoil[gun] = 0.0 if absf(offset) < 0.001 else offset
	_time = supplied
	var visual: Dictionary = ship.get("visual", ship)
	var point = visual.get("position", {})
	var next_position := _vector(point)
	var heading := float(visual.get("heading", 0.0))
	var pitch := float(visual.get("pitch", 0.0))
	var heel := float(visual.get("heel", 0.0))
	if not next_position.is_finite() or not is_finite(heading) or not is_finite(pitch) or not is_finite(heel):
		return
	position = next_position
	rotation = Vector3(-pitch, PI / 2.0 - heading, heel)
	var sail_angle := clampf(float(ship.get("sailAngle", 0.0)), -PI / 2.0, PI / 2.0)
	var deployment := clampf(float(ship.get("sailDeployment", 1.0)), 0.0, 1.0)
	var sail_health := clampf(float(ship.get("sail", 100.0)) / maxf(1.0, float(ship.get("maxSail", 100.0))), 0.0, 1.0)
	var speed := maxf(0.0, float(wind.get("speed", 0.0)))
	var inflation := _inflation_sign(visual, sail_angle, wind) * minf(1.0, speed / 18.0) * sail_health * deployment
	for model in _models:
		for node in model.find_children("*", "Node3D", true, false):
			var id: int = node.get_instance_id()
			if _mast_yaw.has(id):
				node.rotation.y = float(_mast_yaw[id]) + PI / 2.0 - sail_angle
			if String(node.name) == "rudder_pivot":
				node.rotation.y = clampf(float(ship.get("rudder", 0.0)), -1.0, 1.0) * 0.42
			if String(node.name).begins_with("flag_"):
				node.rotation.z = 0.0 if _reduced_motion else sin(_time * 4.0) * 0.025
			if node is MeshInstance3D and node.mesh and String(node.name).begins_with("sail_"):
				for index in node.mesh.get_blend_shape_count():
					var morph: StringName = node.mesh.get_blend_shape_name(index)
					if morph == &"furl":
						node.set_blend_shape_value(index, 1.0 - deployment)
					elif morph == &"inflate":
						node.set_blend_shape_value(index, inflation)
			if _barrel_rest.has(id):
				node.position.z = float(_barrel_rest[id]) + float(_recoil.get(String(node.name), 0.0))
	for event: Dictionary in _damage.apply_snapshot(ship, _time, _reduced_motion):
		event.position = {"x": global_position.x, "y": global_position.y, "z": global_position.z}
		presentation_event.emit(event)
	set_lod_distance([0.0, 220.0, 650.0][_lod])

func apply_events(events: Array) -> void:
	if _disposed:
		return
	for event: Dictionary in events:
		if event.get("type", "") != "fire":
			continue
		var id := String(event.get("id", "%s:%s:%s" % [event.get("shipId", ""), event.get("time", 0), event.get("side", "")]))
		if _seen_events.has(id):
			continue
		_seen_events[id] = true
		if String(event.get("shipId", "")) == String(_snapshot.get("id", "")):
			_fire(String(event.get("side", "port")), event.get("position"))
	# Bound event de-duplication memory for long-running presentation sessions.
	if _seen_events.size() > 256:
		var keys := _seen_events.keys()
		for index in keys.size() - 128:
			_seen_events.erase(keys[index])

func _fire(side: String, point) -> void:
	if not side in ["port", "starboard"] or _models.is_empty():
		return
	var guns: Array[Node3D] = []
	for node in _models[0].find_children("barrel_" + side + "_*", "Node3D", true, false):
		guns.append(node)
	if guns.is_empty():
		return
	guns.sort_custom(func(a: Node3D, b: Node3D): return String(a.name) < String(b.name))
	var selected: Node3D = guns[int(_next_gun[side]) % guns.size()]
	var nearest := INF
	if point != null:
		var world_point := _vector(point)
		for gun in guns:
			var socket_name := String(gun.name).replace("barrel_", "socket_smoke_")
			var socket := gun.get_parent().find_child(socket_name, true, false) as Node3D
			if socket:
				var distance := socket.global_position.distance_squared_to(world_point)
				if distance < nearest:
					nearest = distance
					selected = gun
	_next_gun[side] = (guns.find(selected) + 1) % guns.size()
	_recoil[String(selected.name)] = -0.6
	for model in _models:
		var barrel := model.find_child(String(selected.name), true, false) as Node3D
		if barrel:
			barrel.position.z = float(_barrel_rest[barrel.get_instance_id()]) - 0.6

func _inflation_sign(visual: Dictionary, sail_angle: float, wind: Dictionary) -> float:
	var direction = wind.get("direction", {"x": 1.0, "y": 0.0})
	var dx := float(direction.get("x", 1.0))
	var dz := float(direction.get("y", direction.get("z", 0.0)))
	var length_squared := dx * dx + dz * dz
	if length_squared < 1.0e-8:
		dx = 1.0
		dz = 0.0
	else:
		dx /= sqrt(length_squared)
		dz /= sqrt(length_squared)
	var velocity := _vector(visual.get("velocity", {}))
	var speed := float(wind.get("speed", 0.0))
	var angle := float(visual.get("heading", 0.0)) + sail_angle
	return -1.0 if (-dx * speed - velocity.x) * sin(angle) - (-dz * speed - velocity.z) * cos(angle) < 0.0 else 1.0

func _vector(value) -> Vector3:
	if value is Vector3:
		return value
	if value is Dictionary:
		return Vector3(float(value.get("x", 0.0)), float(value.get("y", 0.0)), float(value.get("z", 0.0)))
	return Vector3.ZERO

func set_lod_distance(distance: float) -> void:
	_lod = 2 if distance >= 650.0 else (1 if distance >= 220.0 else 0)
	for index in _models.size():
		_models[index].visible = index == _lod and not _damage.ended()

func damage_diagnostics() -> Dictionary:
	return _damage.diagnostics()

func get_lod() -> int:
	return _lod

func get_model() -> Node3D:
	return _models[_lod] if _models.size() > _lod else null

func dispose() -> void:
	_disposed = true
	_damage.dispose()
	for model in _models:
		if is_instance_valid(model):
			model.free()
	_models.clear()
	_mast_yaw.clear()
	_barrel_rest.clear()
	_recoil.clear()
	_next_gun = {"port": 0, "starboard": 0}
	_seen_events.clear()
	_snapshot.clear()
	_wind.clear()
	_time = 0.0
	if _owns_library and _library:
		_library.dispose()
	_library = null
