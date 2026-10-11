extends RefCounted
static func valid_id(value: Variant) -> bool:
	if not value is String or value.strip_edges().is_empty() or value.length() > 256 or value in ["__proto__", "prototype", "constructor"]: return false
	for i in value.length():
		if value.unicode_at(i) < 32 or value.unicode_at(i) == 127: return false
	return true
static func exact(value: Dictionary, keys: Array) -> bool:
	return value.size() == keys.size() and keys.all(func(k): return value.has(k))
static func finite(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))
static func valid_order(value: Variant) -> bool:
	if not value is Dictionary or not exact(value, ["id", "shipIds", "intent"]) or not valid_id(value.id) or not value.shipIds is Array or value.shipIds.size() < 1 or value.shipIds.size() > 64 or not value.shipIds.all(valid_id) or not value.intent is Dictionary: return false
	var seen = {}
	for ship_id in value.shipIds:
		if seen.has(ship_id): return false
		seen[ship_id] = true
	var intent = value.intent
	if intent.get("kind") == "rally": return exact(intent, ["kind", "point"]) and intent.point is Dictionary and exact(intent.point, ["x", "z"]) and finite(intent.point.x) and finite(intent.point.z)
	if intent.get("kind") == "keep-distance": return exact(intent, ["kind", "targetId", "range"]) and valid_id(intent.targetId) and finite(intent.range) and intent.range > 0 and intent.range <= 10000
	return intent.get("kind") in ["protect", "intercept", "focus", "prepare-boarding"] and exact(intent, ["kind", "targetId"]) and valid_id(intent.targetId)
static func decision(intent: Dictionary, ship: Dictionary, target: Dictionary = {}, threat: Dictionary = {}, index: int = 0) -> Dictionary:
	var p = ship.visual.position
	if intent.kind == "rally": return {"point": intent.point.duplicate(true), "fire": false, "completed": _distance(p, intent.point) < 25 and _speed(ship) < 1}
	var q = target.visual.position
	var dx = p.x - q.x
	var dz = p.z - q.z
	var distance = sqrt(dx * dx + dz * dz)
	var nx = dx / distance if distance > 1 else 1.0
	var nz = dz / distance if distance > 1 else 0.0
	if intent.kind == "protect":
		var bearing = atan2(threat.visual.position.z - q.z, threat.visual.position.x - q.x) if not threat.is_empty() else target.visual.heading + PI / 2.0
		var offset = 60 + index * 35
		var result = {"point": {"x": q.x + cos(bearing) * offset, "z": q.z + sin(bearing) * offset}, "fire": not threat.is_empty()}
		if not threat.is_empty(): result.preferredTargetId = threat.id
		return result
	if intent.kind == "intercept":
		var lead = minf(25, distance / maxf(3, _speed(ship) + 3))
		return {"point": {"x": q.x + target.visual.velocity.x * lead, "z": q.z + target.visual.velocity.z * lead}, "preferredTargetId": target.id, "fire": true}
	if intent.kind == "keep-distance":
		var wanted = intent.range
		if distance < wanted - 15 or distance > wanted + 45: return {"point": {"x": q.x + nx * (wanted + 25), "z": q.z + nz * (wanted + 25)}, "preferredTargetId": target.id, "fire": true}
		var bearing = atan2(q.z - p.z, q.x - p.x)
		var side = 1 if sin(bearing - ship.visual.heading) >= 0 else -1
		var tangent = bearing - side * PI / 2.0
		return {"point": {"x": p.x + cos(tangent) * 120 + nx * (wanted - distance) * 2, "z": p.z + sin(tangent) * 120 + nz * (wanted - distance) * 2}, "preferredTargetId": target.id, "fire": true}
	if intent.kind == "prepare-boarding": return {"point": {"x": q.x + nx * 35, "z": q.z + nz * 35}, "preferredTargetId": target.id, "fire": false, "maxDeployment": 0.4}
	var bearing = atan2(q.z - p.z, q.x - p.x)
	var side = 1 if sin(bearing - ship.visual.heading) >= 0 else -1
	return {"point": {"x": q.x + nx * 140, "z": q.z + nz * 140} if distance > 190 else {"x": p.x + cos(bearing - side * PI / 2.0) * 150, "z": p.z + sin(bearing - side * PI / 2.0) * 150}, "preferredTargetId": target.id, "fire": true}
static func _distance(a: Dictionary, b: Dictionary) -> float: return sqrt(pow(a.x - b.x, 2) + pow(a.z - b.z, 2))
static func _speed(ship: Dictionary) -> float: return sqrt(pow(ship.visual.velocity.x, 2) + pow(ship.visual.velocity.z, 2))
