extends RefCounted

const Types = preload("res://modules/contracts/physics_types.gd")
const LIMITS := {
	"fisherman": [12.0, 6.0, 16.0], "patrol": [10.0, 5.5, 14.0], "fuchuan": [8.0, 5.0, 11.0],
	"merchant": [6.0, 4.0, 8.0], "voc": [6.0, 4.0, 8.0], "heavy": [4.5, 3.0, 6.0],
}

# Numeric hull-dependent torque budget. Permission/recovery/navigation are
# caller policy; the solver never knows a player, battle, campaign or UI.
static func build(kind: String, turn_intent: float, speed: float, crew_fraction: float = 1.0, hull_fraction: float = 1.0, sail_fraction: float = 1.0, braking: bool = false, sail_deployment: float = 1.0) -> Dictionary:
	if not LIMITS.has(kind) or not [turn_intent, speed, crew_fraction, hull_fraction, sail_fraction, sail_deployment].all(func(value: float) -> bool: return is_finite(value)):
		return {}
	var limits: Array = LIMITS[kind]
	var blend := clampf((speed - 0.3) / 1.2, 0.0, 1.0)
	return {"targetYawRateRad": clampf(turn_intent, -1.0, 1.0) * (limits[1] + (limits[0] - limits[1]) * blend) * PI / 180.0,
		"maxYawAccelerationRad": limits[2] * PI / 180.0,
		"powerFraction": clampf(crew_fraction, 0.0, 1.0) * sqrt(clampf(hull_fraction, 0.0, 1.0) * clampf(sail_fraction, 0.0, 1.0)),
		"neutralYawDamping": 2.5 if absf(turn_intent) < 0.001 else 0.0,
		"brakeDeceleration": 0.2 if braking and sail_deployment <= 0.05 else 0.0, "coastInNoGo": true}

static func sanitize(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var bounds := {"targetYawRateRad": [-12.0 * PI / 180.0, 12.0 * PI / 180.0], "maxYawAccelerationRad": [0.0, 16.0 * PI / 180.0], "powerFraction": [0.0, 1.0], "neutralYawDamping": [0.0, 3.0], "brakeDeceleration": [0.0, 0.2]}
	for key: String in bounds:
		if not Types.finite_number(value.get(key)) or value[key] < bounds[key][0] or value[key] > bounds[key][1]:
			return {}
	if not value.get("coastInNoGo") is bool:
		return {}
	var result := {}
	for key: String in bounds:
		result[key] = float(value[key])
	result.coastInNoGo = value.coastInNoGo
	return result

static func torque(request: Dictionary, yaw_rate: float, dry_yaw_inertia: float) -> float:
	if request.is_empty() or request.powerFraction == 0.0 or not is_finite(yaw_rate) or not is_finite(dry_yaw_inertia) or dry_yaw_inertia <= 0.0:
		return 0.0
	var desired: float = (request.targetYawRateRad - yaw_rate) * 4.0 - request.neutralYawDamping * yaw_rate
	return dry_yaw_inertia * clampf(desired, -request.maxYawAccelerationRad, request.maxYawAccelerationRad) * request.powerFraction
