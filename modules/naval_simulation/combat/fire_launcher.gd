extends RefCounted
## Auxiliary game payload proposal. Encounter owns permission, stock and accepted time.
const Types = preload("res://modules/contracts/physics_types.gd")
const RANGE_METRES: float = 70.0
const SPEED_METRES_PER_SECOND: float = 28.0
const TTL_SECONDS: float = 4.0
const COOLDOWN_SECONDS: float = 12.0
const OPERATION_SECONDS: float = 2.0
const OPERATOR_COUNT: int = 4
const MAX_PAYLOADS: int = 60
const GRAVITY: float = 9.81
const PAYLOADS: Array[String] = ["fire-ball", "thorn-ball"]

static func initial(fire_balls: int = 0, thorn_balls: int = 0) -> Dictionary:
	return {"ammo":{"fire-ball":clampi(fire_balls, 0, MAX_PAYLOADS), "thorn-ball":clampi(thorn_balls, 0, MAX_PAYLOADS)},
		"cooldownSeconds":0.0, "operationSeconds":0.0}

static func valid(state: Variant) -> bool:
	if not state is Dictionary or state.size() != 3 or not state.has_all(["ammo", "cooldownSeconds", "operationSeconds"]): return false
	if not state.ammo is Dictionary or state.ammo.size() != 2 or not state.ammo.has_all(PAYLOADS): return false
	for payload: String in PAYLOADS:
		if not _count(state.ammo[payload]) or state.ammo[payload] > MAX_PAYLOADS: return false
	return _range(state.cooldownSeconds, 0.0, 120.0) and _range(state.operationSeconds, 0.0, OPERATION_SECONDS)

static func operators(state: Variant, able: Variant) -> int:
	if not valid(state) or not _count(able): return 0
	return mini(OPERATOR_COUNT, int(minf(float(able), OPERATOR_COUNT))) if float(state.operationSeconds) > 0.0 else 0

static func launch_solution(source: Variant, target: Variant) -> Dictionary:
	if not _geometry_known(source) or not _geometry_known(target): return _no("invalid-fire-launch-geometry")
	var sv: Dictionary = source.visual
	var tv: Dictionary = target.visual
	var centre_dx: float = float(tv.position.x)-float(sv.position.x)
	var centre_dz: float = float(tv.position.z)-float(sv.position.z)
	var centre_distance: float = sqrt(centre_dx*centre_dx+centre_dz*centre_dz)
	if not is_finite(centre_distance) or centre_distance > RANGE_METRES: return _no("fire-launch-out-of-range")
	var spec: Dictionary = Types.ship_spec(source.kind)
	# Target adapter anchor: a deck station one fifth of the hull length forward.
	# This is a declared game placement, not a reconstruction of a historical launcher.
	var forward: float = float(spec.length)*0.2
	var position: Dictionary = {"x":float(sv.position.x)+cos(float(sv.heading))*forward,
		"y":float(sv.position.y)+float(spec.freeboard)+1.0, "z":float(sv.position.z)+sin(float(sv.heading))*forward}
	var estimate: float = centre_distance/SPEED_METRES_PER_SECOND
	var dx: float = float(tv.position.x)+float(tv.velocity.x)*estimate-position.x
	var dz: float = float(tv.position.z)+float(tv.velocity.z)*estimate-position.z
	var distance: float = sqrt(dx*dx+dz*dz)
	if not is_finite(distance) or distance < 0.00000001: return _no("invalid-fire-launch-distance")
	var target_spec: Dictionary = Types.ship_spec(target.kind)
	var height: float = float(tv.position.y)+float(target_spec.freeboard)+0.5-position.y
	var speed2: float = SPEED_METRES_PER_SECOND*SPEED_METRES_PER_SECOND
	# Same low-arc solution and gravity as the existing cannon implementation.
	var discriminant: float = speed2*speed2-GRAVITY*(GRAVITY*distance*distance+2.0*height*speed2)
	if not is_finite(discriminant) or discriminant < 0.0: return _no("fire-launch-trajectory-unreachable")
	var elevation: float = atan((speed2-sqrt(discriminant))/(GRAVITY*distance))
	var bearing: float = atan2(dz, dx)
	var horizontal: float = SPEED_METRES_PER_SECOND*cos(elevation)
	var velocity: Dictionary = {"x":cos(bearing)*horizontal, "y":SPEED_METRES_PER_SECOND*sin(elevation), "z":sin(bearing)*horizontal}
	if not position.values().all(_finite) or not velocity.values().all(_finite): return _no("invalid-fire-launch-geometry")
	return {"ok":true, "reason":"", "position":position, "velocities":[velocity], "ttl":TTL_SECONDS}

static func _geometry_known(ship: Variant) -> bool:
	if not ship is Dictionary or not ship.get("kind") is String or Types.ship_spec(ship.kind).is_empty(): return false
	var visual: Variant = ship.get("visual")
	if not visual is Dictionary or not visual.get("position") is Dictionary or not visual.get("velocity") is Dictionary or not _finite(visual.get("heading")): return false
	for axis: String in ["x", "y", "z"]:
		if not _finite(visual.position.get(axis)) or not _finite(visual.velocity.get(axis)): return false
	return true

static func _finite(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))

static func _range(value: Variant, minimum: float, maximum: float) -> bool:
	return _finite(value) and value >= minimum and value <= maximum

static func _count(value: Variant) -> bool:
	return _finite(value) and value >= 0 and value <= 9007199254740991 and value == floor(float(value))

static func _no(reason: String) -> Dictionary:
	return {"ok":false, "reason":reason, "position":{}, "velocities":[], "ttl":TTL_SECONDS}
