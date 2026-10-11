extends RefCounted

# Runtime owns accepted simulation time. Numeric solvers have no Node callbacks.
const PHYSICS_HZ := 120
const PHYSICS_DELTA_SECONDS := 1.0 / PHYSICS_HZ
const NAVAL_HZ := 60
const MAX_MARINE_DELTA_SECONDS := 0.05
const GRAVITY_METERS_PER_SECOND_SQUARED := 9.81
const UNITS := {"position": "m", "velocity": "m/s", "mass": "kg", "angles": "rad", "time": "s", "force": "N", "torque": "N*m"}

static func accepted_delta(seconds: float) -> float:
	return minf(seconds, MAX_MARINE_DELTA_SECONDS) if is_finite(seconds) and seconds > 0.0 else 0.0
