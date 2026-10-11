extends RefCounted

# amplitude m, wave number X/Z rad/m, angular phase speed rad/s.
# Never expose the shared arrays to callers: CPU and GPU consume detached data.
const ORIGINAL_COMPONENTS := [
	[1.0, 0.02, 0.015, 0.9],
	[1.0, 0.02, -0.015, 0.1],
	[1.0, 0.05, 0.0, -0.6],
	[0.25, 0.1, 0.11, 2.05],
	[0.25, 0.1, -0.11, -0.05],
]
const MAX_WAVES := 8
const ORIGINAL_HEAVE_EXCURSION_METERS := 7.0

static func original_components() -> Array:
	return ORIGINAL_COMPONENTS.duplicate(true)

static func original_descriptors() -> Array:
	var result: Array = []
	for component: Array in ORIGINAL_COMPONENTS:
		var wave_number: float = sqrt(component[1] * component[1] + component[2] * component[2])
		result.append({"amplitude": component[0], "direction": {"x": component[1] / wave_number, "z": component[2] / wave_number}, "wavelength": TAU / wave_number, "speed": component[3]})
	return result

static func valid_descriptors(waves: Array) -> bool:
	if waves.size() > MAX_WAVES:
		return false
	var amplitude_sum := 0.0
	for value: Variant in waves:
		if not value is Dictionary or not value.get("direction") is Dictionary:
			return false
		for field: String in ["amplitude", "wavelength", "speed"]:
			if not _finite(value.get(field)):
				return false
		if not _finite(value.direction.get("x")) or not _finite(value.direction.get("z", value.direction.get("y"))):
			return false
		if value.wavelength <= 0.0 or not is_finite(TAU / value.wavelength):
			return false
		amplitude_sum += absf(value.amplitude)
	return is_finite(amplitude_sum * 2.0)

static func _finite(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
