extends RefCounted
const BALLISTICS = {
	"solid": {"speed": 65.0, "range": 250.0, "angle": 0.25, "ttl": 8.0, "damage": {"hull": 8.0, "sail": 1.0, "crew": 1.0}},
	"chain": {"speed": 55.0, "range": 190.0, "angle": 0.23, "ttl": 7.0, "damage": {"hull": 1.5, "sail": 12.0, "crew": 1.0}},
	"grape": {"speed": 42.0, "range": 80.0, "angle": 0.1, "ttl": 4.0, "damage": {"hull": 1.0, "sail": 1.0, "crew": 12.0}},
}
const ARC = 25.0 * PI / 180.0
static func muzzle(visual: Dictionary, spec: Dictionary, side: String, cannon: int) -> Dictionary:
	var longitudinal = spec.length * (-0.138 + cannon * 0.092 if spec.guns == 4 else -0.23 + cannon * 0.46 / maxf(1, spec.guns - 1))
	var curve = pow(1.0 - pow(longitudinal / (spec.length / 2.0), 2.0), 0.64)
	var out = spec.width * 0.435 * curve + 0.87
	var sign_side = 1 if side == "starboard" else -1
	return {"x": visual.position.x + cos(visual.heading) * longitudinal - sin(visual.heading) * sign_side * out,
		"y": visual.position.y + spec.freeboard + 0.3, "z": visual.position.z + sin(visual.heading) * longitudinal + cos(visual.heading) * sign_side * out}
