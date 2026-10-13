extends Node3D
## Original GLB presentation. Simulation remains the only pose/damage authority.

const AssetLibrary = preload("res://modules/scene_engine/assets/asset_library.gd")
const ModelProvider = preload("res://modules/scene_engine/assets/ship_model_provider.gd")
const ShipDamage = preload("res://game/presentation/ships/ship_damage.gd")
const DeckSupport = preload("res://game/presentation/crew/deck_stations.gd")
const DESTRUCTION_ANCHOR_LIFT := 0.35
signal presentation_event(event: Dictionary)
var _damage = ShipDamage.new()
const KINDS := ["fuchuan", "fisherman", "merchant", "voc", "patrol", "heavy"]
var _models: Array[Node3D] = []
var _library: RefCounted
var _provider: RefCounted
var _kind := ""
var _owns_library := false
var _lod := 0
var _time := 0.0
var _snapshot: Dictionary = {}
var _wind: Dictionary = {}
var _mast_yaw: Dictionary = {}
var _mast_basis: Dictionary = {}
var _rudder_rest: Dictionary = {}
var _barrel_rest: Dictionary = {}
var _recoil: Dictionary = {}
var _next_gun := {"port": 0, "starboard": 0}
var _seen_events: Dictionary = {}
const SOURCE_POSE_SECONDS := 4.0
const SOURCE_POSE_LIMIT := 256
var _source_poses: Array[Dictionary] = []
var _destruction_support: Variant = null
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
	_provider = ModelProvider.for_library(_library)
	_kind = kind
	_disposed = false
	_lod = 0
	rotation_order = EulerOrder.EULER_ORDER_YXZ
	for lod in 3:
		var model: Node3D = _provider.instantiate_ship(kind,lod,_library)
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
				_mast_basis[node.get_instance_id()] = node.basis
			if String(node.name) == "rudder_pivot": _rudder_rest[node.get_instance_id()] = node.rotation.y
			if String(node.name).begins_with("barrel_"):
				_barrel_rest[node.get_instance_id()] = node.position.z
	_damage.configure(_models)
	var deck := DeckSupport.new()
	if deck.configure(kind, _models[0]):
		var support: Dictionary = deck.sample(0.0, 0.0)
		if not support.is_empty(): _destruction_support = support.point + Vector3.UP * DESTRUCTION_ANCHOR_LIFT
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
		# Physics may already have recorded the new rewind timeline while the
		# drawn snapshot still belongs to the future. Keep that accepted history.
		if not _source_poses.is_empty() and float(_source_poses[-1].time)>supplied+1.0e-8:_source_poses.clear()
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
				node.basis = Basis(Vector3.UP,float(node.get_meta("sail_trim_origin",PI/2.0)) - sail_angle) * _mast_basis[id]
			if String(node.name) == "rudder_pivot":
				node.rotation.y = float(_rudder_rest.get(id,0.0)) + clampf(float(ship.get("rudder", 0.0)), -1.0, 1.0) * 0.42
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
	var damage_events: Array = _damage.apply_snapshot(ship, _time, _reduced_motion)
	# The current body/model frame must be available before same-time keys emit.
	_record_source_pose()
	for event: Dictionary in damage_events:
		event.position = {"x": global_position.x, "y": global_position.y, "z": global_position.z}
		if event.type == "destruction-explosion" and _destruction_support is Vector3:
			var born_ship: Variant = _source_pose_at(float(event.time), "ship_transform")
			if born_ship is Transform3D:
				var anchor: Vector3 = born_ship * _damage.model_transform_at(_models[0], float(event.time)) * _destruction_support
				if anchor.is_finite(): event.source_effect_position = {"x": anchor.x, "y": anchor.y, "z": anchor.z}
		presentation_event.emit(event)
	set_lod_distance([0.0, 220.0, 650.0][_lod])

func remember_authoritative_pose(ship:Dictionary,accepted_time:float)->Variant:
	# A physics observation records the exact transform that Node3D's normal
	# position/rotation setters would draw. It never changes the drawn node,
	# snapshot, animation/damage/recoil clock or authored model-root transform.
	if _disposed or not is_inside_tree() or _models.is_empty() or not is_finite(accepted_time):return null
	if String(ship.get("id",""))!=String(_snapshot.get("id","")):return null
	var visual:Dictionary=ship.get("visual",ship)
	var next_position:=_vector(visual.get("position",{}))
	var heading:=float(visual.get("heading",0.0));var pitch:=float(visual.get("pitch",0.0));var heel:=float(visual.get("heel",0.0))
	if not next_position.is_finite() or not is_finite(heading) or not is_finite(pitch) or not is_finite(heel):return null
	var local:=Transform3D(Basis.from_euler(Vector3(-pitch,PI/2.0-heading,heel),rotation_order).scaled_local(scale),next_position)
	var parent:=get_parent_node_3d()
	var global_pose:Transform3D=local if is_set_as_top_level() or parent==null else parent.global_transform*local
	var model_pose:Transform3D=global_pose*_models[0].transform
	if not model_pose.is_finite():return null
	_record_source_pose(accepted_time,model_pose,global_pose)
	return model_pose

func _record_source_pose(accepted_time:float=NAN,model_pose:Variant=null,ship_pose:Variant=null) -> void:
	if _models.is_empty(): return
	var time:=_time if is_nan(accepted_time) else accepted_time
	if not is_finite(time):return
	if not _source_poses.is_empty() and time<float(_source_poses[-1].time)-1.0e-8:_source_poses.clear()
	var record := {"time":time,"transform":model_pose if model_pose is Transform3D else _models[0].global_transform,"ship_transform":ship_pose if ship_pose is Transform3D else global_transform}
	if not _source_poses.is_empty() and absf(float(_source_poses[-1].time)-time) <= 1.0e-8:
		_source_poses[-1] = record
	else:
		_source_poses.append(record)
	while _source_poses.size() > 1 and (_source_poses.size() > SOURCE_POSE_LIMIT or float(_source_poses[0].time) < time-SOURCE_POSE_SECONDS):
		_source_poses.pop_front()

func _source_pose_at(time: float, field: String = "transform") -> Variant:
	# Outside the bounded accepted history, callers use the native event mouth.
	# A latest ship transform must never relocate a delayed shot to the new ship.
	if not is_finite(time) or _source_poses.is_empty(): return null
	if time < float(_source_poses[0].time)-1.0e-8 or time > float(_source_poses[-1].time)+1.0e-8: return null
	for i in _source_poses.size():
		var before: Dictionary = _source_poses[i]
		if absf(time-float(before.time)) <= 1.0e-8: return before.get(field)
		if i+1 < _source_poses.size():
			var after: Dictionary = _source_poses[i+1]
			if time > float(before.time) and time < float(after.time):
				var from_pose: Variant = before.get(field)
				var to_pose: Variant = after.get(field)
				if not from_pose is Transform3D or not to_pose is Transform3D: return null
				var weight := (time-float(before.time))/(float(after.time)-float(before.time))
				# Retain constant affine shear while interpolating translation.
				if field == "ship_transform" and from_pose.basis.is_equal_approx(to_pose.basis):
					return Transform3D(from_pose.basis, from_pose.origin.lerp(to_pose.origin, weight))
				return (from_pose as Transform3D).interpolate_with(to_pose, weight)
	return null

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

func source_fire_position(event: Dictionary) -> Variant:
	if _disposed or event.get("type") != "fire" or String(event.get("shipId","")) != String(_snapshot.get("id","")): return null
	if event.has("source_muzzle_position"):
		var captured := _vector(event.source_muzzle_position)
		return captured if captured.is_finite() else null
	if _models.is_empty(): return null
	var born_pose: Variant = _source_pose_at(float(event.get("time",_time)))
	if not born_pose is Transform3D: return null
	var model := _models[0]
	var local_from_world := model.global_transform.affine_inverse()
	var side := str(event.get("side","port"))
	var nearest: Node3D = null
	var distance := INF
	var point := _vector(event.get("position",{}))
	for socket: Node3D in model.find_children("socket_smoke_"+side+"_*","Node3D",true,false):
		if not socket.has_meta("source_muzzle_position"): continue
		var logical_local := local_from_world * socket.global_position
		var candidate: float = (born_pose * logical_local).distance_squared_to(point)
		if candidate < distance: nearest=socket; distance=candidate
	return born_pose * nearest.get_meta("source_muzzle_position") if nearest else null

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

func source_kind() -> String:
	return _provider.source_kind(_kind) if _provider and not _disposed else ""

func dispose() -> void:
	_disposed = true
	_damage.dispose()
	for model in _models:
		if is_instance_valid(model):
			model.free()
	_models.clear()
	_mast_yaw.clear()
	_mast_basis.clear()
	_rudder_rest.clear()
	_barrel_rest.clear()
	_recoil.clear()
	_next_gun = {"port": 0, "starboard": 0}
	_seen_events.clear()
	_source_poses.clear()
	_destruction_support = null
	_snapshot.clear()
	_wind.clear()
	_time = 0.0
	if _owns_library and _library:
		_library.dispose()
	_library = null
	_provider = null
	_kind = ""
