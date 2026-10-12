extends Node3D
## Original colored sailor GLBs, accepted-clock animation, visual-only hit response.

const AssetLibrary = preload("res://modules/scene_engine/assets/asset_library.gd")
const DeckStations = preload("res://game/presentation/crew/deck_stations.gd")
const ImpactPool = preload("res://modules/physics_engine/impacts/impact_pool.gd")
var _library
var _own_library := false
var _deck
var _model: Node3D
var _kind := ""
var _instances: Dictionary = {}
var _retired: Dictionary = {}
var _retire_for_hit := false
var _impacts: Dictionary = {}
var _pool
var _own_pool := true
var _disposed := false
var _lod := 0
var _distance := 0.0
var _time := 0.0
var _ship: Dictionary = {}
var _ship_id := ""
var _reduced := false
var _allocation := 24
var _sheet_until := 0.0
var _fire_until := {"port": 0.0, "starboard": 0.0}
var _seen: Dictionary = {}
var _fire_velocities: Dictionary = {}
var _loss_budget := 0
var _water := Callable()
var _deck_frame := Transform3D.IDENTITY
var _previous_deck_frame := Transform3D.IDENTITY
var _impact_managed := false
var _has_impact_phase := false
var _impact_phase := 0.0

func configure(ship_kind: String, ship_model: Node3D, asset_library = null) -> bool:
	if _library != null:
		dispose()
	_disposed = false
	_impact_managed = false
	_has_impact_phase = false
	_impact_phase = 0.0
	_kind = ship_kind
	_model = ship_model
	_deck_frame = ship_model.global_transform if is_instance_valid(ship_model) else global_transform
	_previous_deck_frame = _deck_frame
	_own_library = asset_library == null
	_library = AssetLibrary.new() if _own_library else asset_library
	_deck = DeckStations.new()
	if not is_instance_valid(ship_model) or not _deck.configure(ship_kind, ship_model):
		dispose()
		return false
	_pool = ImpactPool.new()
	add_child(_pool)
	_own_pool = true
	_pool.set_environment(_water, _sample_impact_deck)
	return true

func set_environment(water: Callable) -> void:
	_water = water
	if _pool != null:
		_pool.set_environment(water, _sample_impact_deck)

func set_impact_pool(pool) -> void:
	if _pool != null and _own_pool:
		_pool.dispose()
		_pool.free()
	_pool = pool
	_own_pool = false
	_impact_managed = false
	_has_impact_phase = false

func set_ship_model(model: Node3D) -> bool:
	if _disposed or model == _model:
		return not _disposed
	var next = DeckStations.new()
	if not next.configure(_kind, model):
		return false
	_model = model
	_deck = next
	if _pool != null:
		_pool.remove_deck(_ship_id)
		if _impact_managed and _has_impact_phase:
			# A LOD deck replacement keeps the physics-owned frame and pending
			# bone request; it must not advance the pool merely to register faces.
			_pool.register_deck(_ship_id, _deck.faces, _deck_frame)
	_reconcile()
	return true

func set_reduced_motion(enabled: bool) -> void:
	_reduced = enabled
	_reconcile()

func set_allocation(count: int) -> void:
	_allocation = clampi(count, 0, 24)
	_reconcile()

static func allocate_sailors(requests: Array) -> Dictionary:
	var sorted := requests.duplicate(true)
	sorted.sort_custom(func(a, b): return a.distance < b.distance if a.distance != b.distance else String(a.id) < String(b.id))
	var result: Dictionary = {}
	var remaining := 120
	for request: Dictionary in sorted:
		var count := clampi(int(floor(float(request.get("requested", 0)))), 0, 24)
		result[request.id] = 1 if count > 0 and remaining > 0 else 0
		remaining -= result[request.id]
	for request: Dictionary in sorted:
		if result[request.id] > 0:
			var extra := mini(remaining, maxi(0, mini(24, int(floor(float(request.requested)))) - 1))
			result[request.id] += extra
			remaining -= extra
	return result

func set_lod_distance(distance: float) -> void:
	if not is_finite(distance):
		return
	_distance = maxf(0.0, distance)
	if _lod == 0 and distance > 110.0:
		_lod = 1
	if _lod == 1 and distance < 90.0:
		_lod = 0
	if _lod == 1 and distance >= 330.0:
		_lod = 2
	if _lod == 2 and distance < 270.0:
		_lod = 0 if distance < 90.0 else 1
	_reconcile()

func apply_snapshot(ship: Dictionary, _wind: Dictionary = {}, consumed: float = 0.0) -> void:
	if _disposed or _deck == null:
		return
	var delta := maxf(0.0, consumed) if is_finite(consumed) else 0.0
	var supplied: float = ship.get("time", _time + delta)
	if not is_finite(supplied):
		return
	var impacts_current := _impact_managed and _has_impact_phase and supplied == _impact_phase
	if supplied < _time - 1.0e-8 and not impacts_current:
		_reset_impact_timeline()
	# Terminal snapshots remove standing coverage immediately, but their drawn
	# skins survive until this accepted tick's authoritative hit events transfer them.
	for instance: Dictionary in _retired.values():
		_release_instance(instance)
	_retired.clear()
	var lost := 0
	if not _ship.is_empty():
		lost = maxi(0, _actual_count(_ship) - _actual_count(ship))
		if absf(float(ship.get("sailDeployment", 1.0)) - float(_ship.get("sailDeployment", 1.0))) > 0.001 or absf(float(ship.get("sailAngle", 0.0)) - float(_ship.get("sailAngle", 0.0))) > 0.005:
			_sheet_until = float(ship.get("time", _time + delta)) + 2.4
	_loss_budget = lost
	if is_finite(supplied):
		_time = supplied
	_ship = ship.duplicate(true)
	_ship_id = ship.get("id", "")
	if _pool != null:
		if not impacts_current:
			# Standalone callers retain their original stepping. Once managed,
			# a manual capture at a new phase is the fallback physics owner.
			_advance_impact_frame(delta, _time, _model.global_transform, false)
		_pose_impacts()
	_retire_for_hit = lost > 0
	_reconcile()
	_retire_for_hit = false

func advance_impacts(phase: float, consumed: float, authoritative_model_transform: Transform3D) -> void:
	# Scene physics calls this even with an empty pool. Standing skin animation,
	# authoritative crew-loss bookkeeping and event transfer remain in render.
	if _disposed or _deck == null or _pool == null or not is_finite(phase) or not is_finite(consumed) or consumed < 0.0 or not authoritative_model_transform.is_finite():
		return
	var rewound := _has_impact_phase and phase < _impact_phase - 1.0e-8
	if not _has_impact_phase:
		rewound = phase < _time - 1.0e-8
	if rewound:
		_reset_impact_timeline()
	_impact_managed = true
	_advance_impact_frame(consumed, phase, authoritative_model_transform, rewound)

func _advance_impact_frame(consumed: float, phase: float, frame: Transform3D, rewound: bool) -> void:
	_previous_deck_frame = frame if rewound else _deck_frame
	_deck_frame = frame
	_pool.register_deck(_ship_id, _deck.faces, _deck_frame)
	if _own_pool:
		_pool.advance(consumed, phase)
	if _impact_managed:
		_impact_phase = phase
		_has_impact_phase = true

func _reset_impact_timeline() -> void:
	if _pool != null:
		_pool.remove_ship(_ship_id)
	_seen.clear()
	_fire_velocities.clear()
	_fire_until = {"port": 0.0, "starboard": 0.0}
	_sheet_until = 0.0
	_loss_budget = 0
	_ship.clear()

func _actual_count(ship: Dictionary) -> int:
	var count: float = ship.get("crew", 0.0)
	return maxi(0, int(floor(count))) if float(ship.get("hull", 0.0)) > 0.0 and is_finite(count) else 0

func _reconcile() -> void:
	if _disposed or _deck == null or _ship.is_empty():
		return
	var desired := mini(_actual_count(_ship), mini(_allocation, mini(_deck.stations.size(), [24, 8, 2][_lod])))
	if _distance > 1800.0:
		desired = 0
	if _pool != null:
		desired = maxi(0, desired - _pool.recovering(_ship_id))
	var occupied: Array = _pool.occupied(_ship_id) if _pool != null else []
	var indices: Array[int] = []
	for index in _deck.stations.size():
		if not occupied.has(index) and indices.size() < desired:
			indices.append(index)
	for index: int in _instances.keys():
		if not indices.has(index) or _instances[index].lod != _lod:
			if _retire_for_hit and not indices.has(index):
				_retired[index] = _instances[index]
				_retired[index].root.visible = false
			else:
				_release_instance(_instances[index])
			_instances.erase(index)
	for index in indices:
		if not _instances.has(index):
			var model: Node3D = _library.instantiate_model("res://assets/models/sailors/sailor-lod%d.glb" % _lod)
			if model == null:
				continue
			model.name = "crew_%02d" % index
			add_child(model)
			var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
			var player: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
			player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			_instances[index] = {"root": model, "skeleton": skeleton, "player": player, "lod": _lod, "clip": "", "slot": index}
		_sample_instance(_instances[index], _deck.stations[index])

func _sample_instance(instance: Dictionary, station: Dictionary) -> void:
	var velocity: Dictionary = _ship.get("visual", {}).get("velocity", {})
	var moving := Vector2(float(velocity.get("x", 0.0)), float(velocity.get("z", 0.0))).length() > 0.25
	var clip := "idle"
	if station.role == "helm" and moving and absf(float(_ship.get("rudder", 0.0))) > 0.03:
		clip = "helm"
	if station.role == "haul" and _sheet_until > _time:
		clip = "haul"
	if station.role == "cannon" and (float(_ship.get("cooldownSeconds", {}).get(station.side, 0.0)) > 0.0 or _fire_until.get(station.side, 0.0) > _time):
		clip = "load-cannon"
	if station.role == "lookout" and moving:
		clip = "lookout"
	if station.role == "walk" and moving and not _reduced:
		clip = "walk"
	var player: AnimationPlayer = instance.player
	if instance.clip != clip:
		player.play(clip)
		instance.clip = clip
	var duration := player.get_animation(clip).length
	var sample_time := duration * 0.25 if _reduced else fposmod(_time + instance.slot * 0.173, duration)
	player.seek(sample_time, true)
	var position: Vector3 = station.position
	if station.has("patrol") and clip == "walk":
		var phase := (1.0 - cos((_time + instance.slot * 0.173) * PI / 3.0)) * 0.5
		position = position.lerp(station.patrol, phase)
		var support: Dictionary = _deck.sample(position.x, position.z)
		if not support.is_empty():
			position.y = support.point.y + 0.005
	instance.root.position = position
	for mesh: MeshInstance3D in instance.root.find_children("*", "MeshInstance3D", true, false):
		mesh.transparency = 0.0
	var normal: Vector3 = station.normal
	instance.root.basis = Basis(Quaternion(Vector3.UP, normal)) * Basis(Vector3.UP, station.heading)
	if clip == "walk" and sin((_time + instance.slot * 0.173) * PI / 3.0) < 0.0:
		instance.root.rotate_y(PI)

func apply_events(events: Array) -> void:
	if _disposed:
		return
	for event: Dictionary in events:
		if event.get("type") == "fire" and event.has("projectileId") and event.has("velocity"):
			_fire_velocities[event.projectileId] = _vector(event.velocity)
		var event_id: String = event.get("id", "")
		if event_id.is_empty() or _seen.has(event_id):
			continue
		if event.get("type") == "fire" and event.get("shipId") == _ship_id:
			_seen[event_id] = true
			_fire_until[event.get("side", "port")] = _time + 3.2
		if event.get("type") == "hit" and event.get("targetId") == _ship_id and float(event.get("damage", {}).get("crew", 0.0)) > 0.0:
			_seen[event_id] = true
			var direction: Vector3 = _vector(event.velocity) if event.has("velocity") else _fire_velocities.get(event.get("projectileId", ""), Vector3.ZERO)
			if direction.length_squared() < 1.0e-8:
				continue
			direction.y = 0.0
			direction = direction.normalized() * (7.0 if event.get("ammo") == "grape" else 10.0)
			var casualties := mini(_loss_budget, int(ceil(float(event.damage.crew))))
			if casualties == 0:
				_start_impact(event_id, _vector(event.get("position", {})), direction, false)
			while casualties > 0 and _start_impact(event_id, _vector(event.get("position", {})), direction, true):
				casualties -= 1
				_loss_budget -= 1
	while _seen.size() > 256:
		_seen.erase(_seen.keys()[0])
	while _fire_velocities.size() > 256:
		_fire_velocities.erase(_fire_velocities.keys()[0])
	_reconcile()

func _start_impact(event_id: String, position: Vector3, velocity: Vector3, casualty: bool) -> bool:
	var candidates := _instances.duplicate()
	if casualty:
		candidates.merge(_retired)
	if _pool == null or candidates.is_empty():
		return false
	var indices := candidates.keys()
	indices.sort_custom(func(a, b): return candidates[a].root.global_position.distance_squared_to(position) < candidates[b].root.global_position.distance_squared_to(position))
	var slot: int = indices[0]
	var instance: Dictionary = candidates[slot]
	var skeleton: Skeleton3D = instance.skeleton
	var transforms: Array = []
	var parents: Array = []
	var names: Array = []
	for index in skeleton.get_bone_count():
		transforms.append(skeleton.global_transform * skeleton.get_bone_global_pose(index))
		parents.append(skeleton.get_bone_parent(index))
		names.append(skeleton.get_bone_name(index))
	var definition := {"transforms": transforms, "parents": parents, "names": names}
	var source := {"target_id": _ship_id, "event_id": event_id, "slot": slot, "velocity": velocity, "casualty": casualty, "release": func(recover): _finish_impact(slot, instance, recover)}
	var id: String = _pool.spawn(definition, source, _reduced)
	if id.is_empty():
		return false
	instance.player.pause()
	_instances.erase(slot)
	_retired.erase(slot)
	instance.root.visible = true
	instance.root.reparent(_pool, true)
	_impacts[id] = instance
	return true

func _pose_impacts() -> void:
	for id: String in _impacts.keys():
		var instance: Dictionary = _impacts[id]
		var skeleton: Skeleton3D = instance.skeleton
		var transforms: Array = _pool.get_transforms(id)
		for index in transforms.size():
			skeleton.set_bone_global_pose_override(index, skeleton.global_transform.affine_inverse() * transforms[index], 1.0, true)
		if transforms.size() > 0:
			var fade := 1.0
			for entry: Dictionary in _pool.diagnostics().bodies:
				if entry.id == id:
					fade = clampf(minf((7.0 - entry.age) / 0.7, 1.0 - entry.wet / 1.2), 0.0, 1.0)
			for mesh: MeshInstance3D in instance.root.find_children("*", "MeshInstance3D", true, false):
				mesh.transparency = 1.0 - fade

func _finish_impact(slot: int, instance: Dictionary, recover: bool) -> void:
	for id: String in _impacts.keys():
		if _impacts[id] == instance:
			_impacts.erase(id)
	if recover and not _disposed:
		instance.skeleton.clear_bones_global_pose_override()
		instance.root.reparent(self, false)
		_instances[slot] = instance
		_reconcile()
	else:
		_release_instance(instance)

func _sample_impact_deck(target_id: String, point: Vector3, previous: Vector3, _phase: float, _previous_phase: float) -> Dictionary:
	if target_id != _ship_id or _deck == null:
		return {}
	var frame := _deck_frame
	var local := frame.affine_inverse() * point
	var old := _previous_deck_frame.affine_inverse() * previous
	var support: Dictionary = _deck.sample(local.x, local.z)
	if support.is_empty() or old.y < support.point.y - 0.1:
		return {}
	return {"point": frame * support.point, "normal": (frame.basis * support.normal).normalized()}

func _vector(value) -> Vector3:
	if value is Vector3:
		return value
	return Vector3(value.get("x", 0.0), value.get("y", 0.0), value.get("z", 0.0)) if value is Dictionary else Vector3.ZERO

func get_visible_count() -> int:
	return _instances.size()

func get_instances() -> Array:
	return _instances.values()

func get_impact_pool():
	return _pool

func sample_deck(x: float, z: float) -> Dictionary:
	return _deck.sample(x, z) if _deck != null else {}

func diagnostics() -> Dictionary:
	var roles: Array[Dictionary] = []
	for instance: Dictionary in _instances.values():
		var station: Dictionary = _deck.stations[instance.slot]
		roles.append({"slot": instance.slot, "role": station.role, "side": station.side, "clip": instance.clip})
	return {"visible": _instances.size(), "lod": _lod, "accepted_time": _time, "roles": roles, "impact_count": _impacts.size()}

func _release_instance(instance: Dictionary) -> void:
	if is_instance_valid(instance.root):
		instance.root.free()

func dispose() -> void:
	if _disposed:
		return
	_disposed = true
	_impact_managed = false
	_has_impact_phase = false
	_impact_phase = 0.0
	if _pool != null:
		_pool.remove_ship(_ship_id)
		if _own_pool:
			_pool.dispose()
			_pool.free()
	_pool = null
	for instance: Dictionary in _instances.values():
		_release_instance(instance)
	_instances.clear()
	for instance: Dictionary in _retired.values():
		_release_instance(instance)
	_retired.clear()
	_impacts.clear()
	_seen.clear()
	_fire_velocities.clear()
	_ship.clear()
	_deck = null
	_model = null
	if _own_library and _library != null:
		_library.dispose()
	_library = null

func _exit_tree() -> void:
	dispose()
