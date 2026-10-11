extends RefCounted
## Immutable local triangles derived from authored hull/deck; physics receives copies.

var faces := PackedVector3Array()
var stations: Array[Dictionary] = []
var bounds := AABB()
var _deck_y := 0.0
var _ceiling := 0.0
var _obstacles: Array[AABB] = []

func configure(kind: String, model: Node3D) -> bool:
	faces.clear()
	stations.clear()
	_obstacles.clear()
	var deck := model.find_child("deck", true, false) as MeshInstance3D
	if not deck or not deck.mesh:
		return false
	bounds = _bounds(deck, model)
	_deck_y = bounds.position.y + 0.026
	_ceiling = bounds.end.y + 2.0
	for name in ["hull", "deck"]:
		var surface := model.find_child(name, true, false) as MeshInstance3D
		if surface and surface.mesh:
			var frame := _local_frame(surface, model)
			for vertex in surface.mesh.get_faces():
				faces.append(frame * vertex)
	var masts: Array[Node3D] = []
	var guns: Array[Node3D] = []
	for node in model.find_children("*", "Node3D", true, false):
		var name := String(node.name)
		if name in ["sterncastle", "stern_gallery", "admiral_stern_gallery", "patrol_stern_house", "cargo_hold", "fishing_canopy", "bow_firing_platform", "shield_rack"]:
			_obstacles.append(_bounds(node, model))
		if name.begins_with("mast_timber_"):
			_obstacles.append(_bounds(node, model).grow(0.22))
		if name.begins_with("mast_") and name.trim_prefix("mast_").is_valid_int():
			masts.append(node)
		if name.begins_with("cannon_port_") or name.begins_with("cannon_starboard_"):
			guns.append(node)
	var length := bounds.size.z
	var width := bounds.size.x / 0.92
	if kind == "merchant":
		_extra(0.0, -length * 0.36, width * 0.61, 4.2)
		for x in [-2.6, 2.6]:
			_extra(x, 4.875, 1.65, 5.3)
	if kind == "fisherman":
		for x in [-0.85, 0.85]:
			_extra(x, 3.1, 1.1, 1.1)
	var exclusions := {"fuchuan": [-8.4, 2.4, 2.4], "patrol": [-5.4, 1.4, 1.6], "heavy": [-13.9, 3.0, 3.2]}
	if exclusions.has(kind):
		var exclusion: Array = exclusions[kind]
		_extra(0.0, exclusion[0], exclusion[1], exclusion[2])
	var gun_inset := width * 0.03
	for gun in guns:
		var p := _local_frame(gun, model).origin
		_extra(p.x - signf(p.x) * gun_inset, p.z, 0.95, 1.2)
	var helms := {"fuchuan": -0.20, "fisherman": -0.38, "merchant": -0.26, "voc": -0.23, "patrol": -0.125, "heavy": -0.183}
	_add("helm", 0.0, length * float(helms.get(kind, -0.2)), 0.0, "", length, width)
	for mast in masts:
		var p := _local_frame(mast, model).origin
		for direction in [-1.0, 1.0]:
			_add("haul", direction * width * 0.27, p.z - 0.85, -direction * PI / 2.0, "", length, width)
	var worker_inset := maxf(1.1, gun_inset + 0.475 + 0.34 + 0.01)
	for gun in guns:
		var side := "port" if String(gun.name).contains("_port_") else "starboard"
		var direction := 1.0 if side == "port" else -1.0
		var p := _local_frame(gun, model).origin
		_add("cannon", p.x - direction * worker_inset, p.z, direction * PI / 2.0, side, length, width)
	_add("lookout", 0.0, length * 0.34, 0.0, "", length, width)
	var z := -length * 0.25
	while z <= length * 0.36:
		for x in [width * 0.27, -width * 0.27, 0.0, width * 0.14, -width * 0.14]:
			_add("idle", x, z, 0.0, "", length, width)
		z += 1.25
	for station in stations:
		if station.role == "idle":
			var end: Vector3 = station.position + Vector3(0, 0, 0.3)
			if _clear(end.x, end.z, length, width) and not sample(end.x, end.z).is_empty():
				station.role = "walk"
				station.patrol = end
				break
	var preferred: Array[Dictionary] = []
	for role in ["helm", "haul", "port", "starboard", "lookout"]:
		for station in stations:
			if station.role == role or (station.role == "cannon" and station.side == role):
				preferred.append(station)
				break
	for station in stations:
		if not preferred.has(station):
			preferred.append(station)
	stations = preferred
	return not stations.is_empty()

func _extra(x: float, z: float, width: float, depth: float) -> void:
	_obstacles.append(AABB(Vector3(x - width / 2, _deck_y - 0.2, z - depth / 2), Vector3(width, 2.2, depth)))

func _clear(x: float, z: float, length: float, width: float) -> bool:
	var t := 2.0 * z / length
	var half := width * 0.46 * pow(maxf(0.0, 1.0 - t * t), 0.64)
	if absf(x) + 0.35 >= half or absf(t) > 0.88:
		return false
	var actor := AABB(Vector3(x - 0.34, _deck_y + 0.02, z - 0.32), Vector3(0.68, 1.69, 0.64))
	for obstacle in _obstacles:
		if actor.intersects(obstacle):
			return false
	return true

func _add(role: String, x: float, z: float, heading: float, side: String, length: float, width: float) -> void:
	if stations.size() >= 24 or not _clear(x, z, length, width):
		return
	var support := sample(x, z)
	if support.is_empty():
		return
	for station in stations:
		if Vector2(station.position.x - x, station.position.z - z).length() < 0.95:
			return
	stations.append({"role": role, "position": support.point + Vector3.UP * 0.005, "normal": support.normal, "heading": heading, "side": side})

func sample(x: float, z: float) -> Dictionary:
	var highest := -INF
	var normal := Vector3.UP
	for index in range(0, faces.size(), 3):
		var a := faces[index]
		var b := faces[index + 1]
		var c := faces[index + 2]
		var n := (b - a).cross(c - a).normalized()
		if absf(n.y) < 0.5:
			continue
		var hit = Geometry3D.ray_intersects_triangle(Vector3(x, _ceiling, z), Vector3.DOWN, a, b, c)
		if hit != null and hit.y > highest:
			highest = hit.y
			normal = n if n.y >= 0.0 else -n
	if highest == -INF:
		return {}
	# Authored near/middle plank caulking is decoration above structural triangles.
	if highest < _deck_y:
		highest = _deck_y
		normal = Vector3.UP
	return {"point": Vector3(x, highest, z), "normal": normal}

func _local_frame(node: Node3D, model: Node3D) -> Transform3D:
	var frame := Transform3D.IDENTITY
	var current := node
	while current != model and current != null:
		frame = current.transform * frame
		current = current.get_parent() as Node3D
	return frame

func _bounds(node: Node3D, model: Node3D) -> AABB:
	var meshes: Array[Node] = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		meshes.push_front(node)
	var result := AABB()
	var first := true
	for mesh_node: MeshInstance3D in meshes:
		if not mesh_node.mesh:
			continue
		var transformed := _local_frame(mesh_node, model) * mesh_node.mesh.get_aabb()
		result = transformed if first else result.merge(transformed)
		first = false
	return result
