extends Node3D
## Visual-only native articulated adapter. Definitions contain detached world poses.

signal visual_event(event: Dictionary)

const BoneBody = preload("res://modules/physics_engine/impacts/impact_bone.gd")
const CAP := 12
static var _live_count := 0
var _bodies: Dictionary = {}
var _decks: Dictionary = {}
var _next_id := 0
var _water := Callable()
var _deck := Callable()
var _disposed := false
var _phase := 0.0
var _seen: Dictionary = {}

func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY

func set_environment(water: Callable, deck: Callable = Callable()) -> void:
	_water = water
	_deck = deck
	for entry: Dictionary in _bodies.values():
		for bone in entry.bones:
			bone.water_sampler = water
			bone.deck_sampler = deck

func register_deck(target_id: String, faces: PackedVector3Array, frame: Transform3D) -> void:
	if _disposed:
		return
	if not _decks.has(target_id):
		var body := StaticBody3D.new()
		body.name = "deck_collision_" + target_id
		body.collision_layer = 4
		body.collision_mask = 2
		var collision := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		shape.backface_collision = true
		collision.shape = shape
		body.add_child(collision)
		add_child(body)
		_decks[target_id] = body
	_decks[target_id].global_transform = frame

func update_deck(target_id: String, frame: Transform3D) -> void:
	if _decks.has(target_id):
		_decks[target_id].global_transform = frame

func spawn(definition: Dictionary, source: Dictionary, reduced_motion := false) -> String:
	if _disposed or _live_count >= CAP:
		return ""
	var event_key := "%s:%s:%s" % [source.get("target_id", ""), source.get("event_id", ""), source.get("slot", -1)]
	if _seen.has(event_key):
		return ""
	var transforms: Array = definition.get("transforms", [])
	var parents: Array = definition.get("parents", [])
	var names: Array = definition.get("names", [])
	if transforms.size() != 18 or parents.size() != 18 or names.size() != 18:
		return ""
	var velocity: Vector3 = source.get("velocity", Vector3.ZERO)
	var direction := Vector3(velocity.x, 0, velocity.z)
	if not direction.is_finite() or direction.length_squared() < 1.0e-8:
		return ""
	direction = direction.normalized()
	var casualty: bool = source.get("casualty", true)
	var speed := velocity.length() if casualty else 0.4
	var impulse := direction * speed * (0.65 if reduced_motion else 1.0)
	impulse.y = (6.0 if speed > 8.0 else 5.5) if casualty else 0.7
	impulse.y *= 0.7 if reduced_motion else 1.0
	var spin := Vector3.UP.cross(direction) * (0.7 if reduced_motion else 2.3) * (1.0 if casualty else 0.15)
	_next_id += 1
	var id := "impact_%d_%d" % [get_instance_id(), _next_id]
	var group := Node3D.new()
	group.name = id
	add_child(group)
	var bones: Array = []
	var centre: Vector3 = transforms[1].origin
	for index in 18:
		var bone = BoneBody.new()
		bone.name = names[index]
		bone.custom_integrator = true
		bone.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		bone.freeze = true
		bone.can_sleep = false
		bone.continuous_cd = true
		bone.mass = 4.0 if index < 6 else 2.5
		bone.collision_layer = 2
		bone.collision_mask = 5
		bone.radius = 0.005 if index == 0 else (0.16 if String(names[index]).contains("head") else (0.17 if String(names[index]).contains("chest") else 0.075))
		var shape := SphereShape3D.new()
		shape.radius = bone.radius
		var collision := CollisionShape3D.new()
		collision.shape = shape
		bone.add_child(collision)
		group.add_child(bone)
		bone.global_transform = transforms[index]
		PhysicsServer3D.body_set_state(bone.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, transforms[index])
		bone.simulation_velocity = impulse + spin.cross(transforms[index].origin - centre)
		bone.simulation_spin = spin
		bone.water_sampler = _water
		bone.deck_sampler = _deck
		bone.target_id = source.get("target_id", "")
		bone.phase = _phase
		bone.previous_phase = _phase
		bones.append(bone)
	var joints: Array[PinJoint3D] = []
	for index in range(1, 18):
		var parent_index: int = parents[index]
		if parent_index < 0 or parent_index >= index:
			group.free()
			return ""
		var joint := PinJoint3D.new()
		group.add_child(joint)
		joint.global_position = transforms[index].origin
		joint.node_a = joint.get_path_to(bones[parent_index])
		joint.node_b = joint.get_path_to(bones[index])
		joint.exclude_nodes_from_collision = true
		joints.append(joint)
	_bodies[id] = {"group": group, "bones": bones, "joints": joints, "source": source.duplicate(), "casualty": casualty, "age": 0.0, "wet": 0.0, "water_entered": false, "state": "airborne", "lifetime": 7.0 if casualty else 1.25}
	_seen[event_key] = true
	while _seen.size() > 256:
		_seen.erase(_seen.keys()[0])
	_live_count += 1
	visual_event.emit({"type": "crew-impact", "body_id": id, "target_id": source.get("target_id", ""), "event_id": source.get("event_id", "")})
	return id

func advance(accepted_seconds: float, phase: float) -> void:
	if _disposed or not is_finite(accepted_seconds) or not is_finite(phase) or accepted_seconds < 0.0:
		return
	if phase < _phase - 1.0e-8:
		for id: String in _bodies.keys():
			_release(id, false)
		_seen.clear()
		_phase = phase
		return
	if phase <= _phase + 1.0e-8:
		accepted_seconds = 0.0
	_phase = phase
	for id: String in _bodies.keys():
		var entry: Dictionary = _bodies[id]
		entry.age += accepted_seconds
		var wet := false
		var water_bone = null
		var deck_contact := false
		for bone in entry.bones:
			wet = wet or bone.contact == "water"
			if bone.contact == "water":
				water_bone = bone
			deck_contact = deck_contact or bone.contact == "deck"
			bone.wet_age = entry.wet
			bone.request_step(accepted_seconds, phase)
		if wet:
			entry.wet += accepted_seconds
			entry.state = "water-contact"
			if not entry.water_entered and accepted_seconds > 0.0:
				entry.water_entered = true
				var point: Vector3 = PhysicsServer3D.body_get_state(water_bone.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM).origin
				if _water.is_valid():
					var surface: float = _water.call(point.x, point.z, water_bone.previous_phase)
					if is_finite(surface):
						point.y = surface
				visual_event.emit({"type": "crew-water-entry", "body_id": id, "target_id": entry.source.get("target_id", ""), "event_id": entry.source.get("event_id", ""), "position": point, "time": water_bone.previous_phase})
		elif deck_contact:
			entry.state = "deck-contact"
		if entry.age >= entry.lifetime - 1.0e-8 or entry.wet >= 1.2:
			_release(id, not entry.casualty)

func _release(id: String, recover: bool) -> void:
	var entry: Dictionary = _bodies[id]
	_bodies.erase(id)
	_live_count -= 1
	entry.group.free()
	var callback: Callable = entry.source.get("release", Callable())
	if callback.is_valid():
		callback.call(recover)
	visual_event.emit({"type": "crew-impact-finished", "body_id": id, "recover": recover})

func get_body_count() -> int:
	return _bodies.size()

func get_transforms(id: String) -> Array:
	var transforms: Array = []
	if _bodies.has(id):
		for bone in _bodies[id].bones:
			# Node transform synchronization lags the completed physics step. Sample
			# authoritative Jolt state so pause/pose handoff cannot add a late frame.
			transforms.append(PhysicsServer3D.body_get_state(bone.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM))
	return transforms

func occupied(target_id: String) -> Array[int]:
	var slots: Array[int] = []
	for entry: Dictionary in _bodies.values():
		if entry.source.get("target_id") == target_id:
			slots.append(entry.source.slot)
	return slots

func recovering(target_id: String) -> int:
	var count := 0
	for entry: Dictionary in _bodies.values():
		if entry.source.get("target_id") == target_id and not entry.casualty:
			count += 1
	return count

func remove_ship(target_id: String) -> void:
	for id: String in _bodies.keys():
		if _bodies[id].source.get("target_id") == target_id:
			_release(id, false)
	remove_deck(target_id)

func remove_deck(target_id: String) -> void:
	if _decks.has(target_id):
		_decks[target_id].free()
		_decks.erase(target_id)

func diagnostics() -> Dictionary:
	var bodies: Array[Dictionary] = []
	for id: String in _bodies:
		var entry: Dictionary = _bodies[id]
		bodies.append({"id": id, "bone_count": entry.bones.size(), "joint_count": entry.joints.size(), "age": entry.age, "wet": entry.wet, "state": entry.state, "water_entered": entry.water_entered, "casualty": entry.casualty, "transforms": get_transforms(id), "source": entry.source})
	return {"bodies": bodies, "count": _bodies.size(), "global_count": _live_count, "cap": CAP}

func dispose() -> void:
	if _disposed:
		return
	_disposed = true
	for id: String in _bodies.keys():
		_release(id, false)
	for deck in _decks.values():
		deck.free()
	_decks.clear()
	_seen.clear()

func _exit_tree() -> void:
	dispose()
