extends RefCounted

# (amplitude, x wave number, z wave number, radians per simulation second).
# Scalar Variant floats retain double precision until the public Vector outputs.
# These are the exact sin(a)cos(b) expansion of ProjectedWaterShader, with world
# Y up and the original horizontal Vec2.y mapped to world Z.
const Descriptor = preload("res://modules/contracts/wave_descriptor.gd")
const COMPONENTS := Descriptor.ORIGINAL_COMPONENTS

func sample(x: float, z: float, time: float) -> Dictionary:
	var height := 0.0
	var gradient_x := 0.0
	var gradient_z := 0.0
	for component: Array in COMPONENTS:
		var amplitude: float = component[0]
		var wave_x: float = component[1]
		var wave_z: float = component[2]
		var phase: float = wave_x * x + wave_z * z + component[3] * time
		height += amplitude * sin(phase)
		var slope := amplitude * cos(phase)
		gradient_x += wave_x * slope
		gradient_z += wave_z * slope
	return {
		"height": height,
		"gradient": Vector2(gradient_x, gradient_z),
		"normal": Vector3(-gradient_x, 1.0, -gradient_z).normalized(),
	}
