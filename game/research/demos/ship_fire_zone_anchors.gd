extends RefCounted
## Independent research helper. Stores only copied model-local values; the
## caller owns all world transforms and the source model's lifetime.
const DeckSupport = preload("res://game/presentation/crew/deck_stations.gd")
const KINDS: Array[String] = ["fuchuan", "fisherman", "merchant", "voc", "patrol", "heavy"]
const ZONES: Array[String] = ["bow", "mid", "stern"]
const EDGE_EPSILON: float = 0.00001
var _ready: bool = false
var _anchors: Dictionary = {}
var _bounds: AABB = AABB()
var _triangle_count: int = 0

func configure(kind: String, model: Node3D) -> Dictionary:
	clear()
	if kind not in KINDS:
		return {"ok": false, "reason": "unsupported_ship_kind"}
	if not is_instance_valid(model):
		return {"ok": false, "reason": "source_model_unavailable"}
	# DeckSupport already resolves nested mesh transforms into the model frame,
	# including tagged raised quarterdecks and its native waterline contract.
	var deck: Variant = DeckSupport.new()
	# Its boolean reports crew station availability, not geometry availability.
	# A fire point may fit a narrow or offset deck with no valid crew footprint.
	deck.configure(kind, model)
	if deck.faces.is_empty():
		return {"ok": false, "reason": "actual_deck_support_unavailable"}
	var bounds: AABB = deck.bounds
	if not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size.x <= EDGE_EPSILON * 2.0 or bounds.size.z <= EDGE_EPSILON * 6.0:
		return {"ok": false, "reason": "invalid_deck_bounds"}
	var staged: Dictionary = {}
	var length: float = bounds.size.z
	var center: Vector3 = bounds.get_center()
	var partition: float = length / 3.0
	for index: int in ZONES.size():
		var zone: String = ZONES[index]
		# Canonical authored ship frame: +Z bow, -Z stern. Partition the
		# actual support bounds, rather than assuming the model is centered.
		var target_z: float = center.z + partition * float(1 - index)
		var lower_z: float = target_z - partition * 0.5 + EDGE_EPSILON
		var upper_z: float = target_z + partition * 0.5 - EDGE_EPSILON
		var anchor: Dictionary = _resolve_zone(deck, center.x, target_z, lower_z, upper_z)
		if anchor.is_empty():
			return {"ok": false, "reason": "unsupported_fire_zone:" + zone}
		anchor.zone = zone
		staged[zone] = anchor
	_anchors = staged
	_bounds = bounds
	_triangle_count = int(deck.faces.size() / 3)
	_ready = true
	return {"ok": true, "reason": ""}

func sample(zone: String) -> Dictionary:
	if not _ready or not _anchors.has(zone):
		return {}
	return _anchors[zone].duplicate(true)

func diagnostics() -> Dictionary:
	var anchors: Dictionary = {}
	for zone: String in ZONES:
		if not _anchors.has(zone):
			continue
		var anchor: Dictionary = _anchors[zone]
		anchors[zone] = {"zone": zone, "point": _vector(anchor.point), "normal": _vector(anchor.normal)}
	return {"ready": _ready, "anchors": anchors, "bounds": {"position": _vector(_bounds.position), "size": _vector(_bounds.size)}, "triangle_count": _triangle_count}

func clear() -> void:
	_ready = false
	_anchors.clear()
	_bounds = AABB()
	_triangle_count = 0

func _resolve_zone(deck: Variant, x: float, z: float, lower_z: float, upper_z: float) -> Dictionary:
	var center_hit: Dictionary = _sample(deck, x, z)
	if not center_hit.is_empty():
		return center_hit
	# A center hole is not a flat platform. Clip real triangles to the strict
	# partition interior, then test their interior centroids. Ranking by XZ
	# distance and preserving face order on ties makes recovery deterministic.
	# Clipping also finds narrow support whose original centroid is outside
	# this region; no fixed search grid can guarantee that coverage.
	var faces: PackedVector3Array = deck.faces
	var nearest: Dictionary = {}
	var nearest_distance: float = INF
	for index: int in range(0, faces.size(), 3):
		var a: Vector3 = faces[index]
		var b: Vector3 = faces[index + 1]
		var c: Vector3 = faces[index + 2]
		var normal: Vector3 = (b - a).cross(c - a).normalized()
		if not normal.is_finite() or absf(normal.y) < 0.5:
			continue
		var polygon: PackedVector3Array = _clip_z(PackedVector3Array([a, b, c]), lower_z, true)
		polygon = _clip_z(polygon, upper_z, false)
		if polygon.size() < 3:
			continue
		var centroid: Vector3 = Vector3.ZERO
		for vertex: Vector3 in polygon:
			centroid += vertex
		centroid /= float(polygon.size())
		if centroid.z < lower_z or centroid.z > upper_z:
			continue
		var candidate: Dictionary = _sample(deck, centroid.x, centroid.z)
		if candidate.is_empty():
			continue
		var distance: float = Vector2(centroid.x - x, centroid.z - z).length_squared()
		if distance < nearest_distance:
			nearest = candidate
			nearest_distance = distance
	return nearest

func _sample(deck: Variant, x: float, z: float) -> Dictionary:
	var support: Dictionary = deck.sample(x, z)
	if support.is_empty():
		return {}
	var point: Variant = support.get("point")
	var normal: Variant = support.get("normal")
	if not point is Vector3 or not normal is Vector3 or not point.is_finite() or not normal.is_finite() or normal.y <= 0.0:
		return {}
	return {"point": point, "normal": normal}

func _clip_z(polygon: PackedVector3Array, plane_z: float, keep_above: bool) -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	if polygon.is_empty():
		return result
	var previous: Vector3 = polygon[polygon.size() - 1]
	var previous_inside: bool = previous.z >= plane_z if keep_above else previous.z <= plane_z
	for current: Vector3 in polygon:
		var current_inside: bool = current.z >= plane_z if keep_above else current.z <= plane_z
		if current_inside != previous_inside:
			var ratio: float = (plane_z - previous.z) / (current.z - previous.z)
			result.append(previous.lerp(current, ratio))
		if current_inside:
			result.append(current)
		previous = current
		previous_inside = current_inside
	return result

func _vector(value: Vector3) -> Dictionary:
	return {"x": value.x, "y": value.y, "z": value.z}
