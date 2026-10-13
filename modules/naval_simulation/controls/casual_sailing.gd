extends RefCounted
## Player handling policy; the physics solver still owns every fixed-dt impulse.
## Wind changes cruise efficiency rather than removing the ability to sail.
const CRUISE := {"fisherman":4.5,"patrol":5.5,"fuchuan":5.0,"merchant":4.5,"voc":4.5,"heavy":3.5}
const RESPONSE := 1.6
const MAX_ACCELERATION := 0.9
const MAX_DECELERATION := 0.65

static func throttle(ship: Dictionary, visual: Dictionary, wind: Dictionary, request: Dictionary, power: float, drive_acceleration: float = 2.0) -> float:
	if not request.get("casual", false) or not CRUISE.has(ship.kind) or power <= 0.0 or drive_acceleration <= 0.0: return 0.0
	var forward := Vector2(cos(visual.heading), sin(visual.heading))
	var velocity := Vector2(visual.velocity.x, visual.velocity.z)
	var wind_direction := Vector2(wind.direction.x, wind.direction.y)
	var incidence := forward.dot(wind_direction.normalized()) if wind_direction.length_squared() > 0.0 else 0.0
	var efficiency := lerpf(0.8, 0.81 - 0.19 * clampf(incidence, -1.0, 1.0), clampf(float(wind.speed) / 12.0, 0.0, 1.0))
	var target: float = CRUISE[ship.kind] * request.sailIntent * efficiency * power * ship.stats.speedMultiplier
	if request.braking: target = 0.0
	var acceleration := clampf((target - velocity.dot(forward)) * RESPONSE, -MAX_DECELERATION, MAX_ACCELERATION) * power
	# The existing core applies half its drive budget for negative throttle.
	var budget := drive_acceleration * (0.5 if acceleration < 0.0 else 1.0)
	return clampf(acceleration / budget, -1.0, 1.0)
