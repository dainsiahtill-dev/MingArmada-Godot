extends RefCounted

const Descriptor = preload("res://modules/contracts/wave_descriptor.gd")

static func components(descriptors: Array) -> PackedVector4Array:
	var result := PackedVector4Array()
	if not Descriptor.valid_descriptors(descriptors): return result
	for entry: Dictionary in descriptors:
		var direction: Dictionary = entry.direction
		var x := float(direction.x)
		var z := float(direction.get("z", direction.get("y", 0.0)))
		var scale := maxf(absf(x), absf(z))
		if not is_finite(scale) or scale <= 1.0e-12: return PackedVector4Array()
		var scaled_x := x / scale
		var scaled_z := z / scale
		var magnitude := sqrt(scaled_x * scaled_x + scaled_z * scaled_z)
		var k := TAU / float(entry.wavelength)
		var component := Vector4(entry.amplitude, scaled_x / magnitude * k, scaled_z / magnitude * k, entry.speed)
		if not component.is_finite(): return PackedVector4Array()
		result.append(component)
	while result.size() < 8: result.append(Vector4.ZERO)
	return result
