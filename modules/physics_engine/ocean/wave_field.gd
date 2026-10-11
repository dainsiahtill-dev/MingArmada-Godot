extends RefCounted

# (amplitude, x wave number, z wave number, radians per simulation second).
# Scalar Variant floats retain double precision until the public Vector outputs.
# These are the exact sin(a)cos(b) expansion of ProjectedWaterShader, with world
# Y up and the original horizontal Vec2.y mapped to world Z.
const Descriptor = preload("res://modules/contracts/wave_descriptor.gd")
const COMPONENTS := Descriptor.ORIGINAL_COMPONENTS
var _components: Array = Descriptor.original_components()

func configure(descriptors: Array = Descriptor.original_descriptors()) -> bool:
	if not Descriptor.valid_descriptors(descriptors): return false
	# Preserve the source scalar expansion exactly for the default profile:
	# reconstructing k from wavelength would introduce a tiny rounding change.
	if descriptors == Descriptor.original_descriptors():
		_components = Descriptor.original_components()
		return true
	var next: Array = []
	for wave: Dictionary in descriptors:
		var x := float(wave.direction.x)
		var z := float(wave.direction.get("z", wave.direction.get("y", 0.0)))
		var scale := maxf(absf(x), absf(z))
		x /= scale; z /= scale
		var magnitude := sqrt(x*x+z*z)
		var k := TAU/float(wave.wavelength)
		next.append([float(wave.amplitude),x/magnitude*k,z/magnitude*k,float(wave.speed)])
	_components = next
	return true

func sample_height(x: float, z: float, time: float) -> float:
	# Same scalar phases and accumulation order as sample(), without discarded
	# cosine derivatives, Vector outputs or a result Dictionary.
	var height := 0.0
	for component: Array in _components:
		var amplitude: float = component[0]
		var wave_x: float = component[1]
		var wave_z: float = component[2]
		var phase: float = wave_x * x + wave_z * z + component[3] * time
		height += amplitude * sin(phase)
	return height

func sample(x: float, z: float, time: float) -> Dictionary:
	var height := 0.0
	var gradient_x := 0.0
	var gradient_z := 0.0
	for component: Array in _components:
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
