extends RefCounted
# Frozen source descriptors; optional trusted sampler has the same accepted clock.
var waves: Array = []
var heave_excursion = 0.0
var sea_level = 0.0
var accepted_time = 0.0
var sampler: RefCounted = null
func sample(x: float, z: float, _time: float) -> Dictionary:
	if sampler != null:
		var result: Dictionary = sampler.sample(x, z, accepted_time)
		result.height += sea_level
		return result
	var height = sea_level
	for wave: Dictionary in waves:
		var k = 2.0 * PI / wave.wavelength
		var phase = k * (wave.direction.x * x + wave.direction.y * z) + wave.speed * accepted_time
		height += wave.amplitude * sin(phase)
	return {"height": height}
func set_heading(direction: Dictionary) -> void:
	var heading = atan2(direction.y, direction.x) if direction.x * direction.x + direction.y * direction.y > 1e-12 else 0.0
	waves = []
	for base in [[0.0, 1.1, 28.0, 5.0], [PI * 0.28, 0.55, 14.0, 9.0], [-PI * 0.22, 0.35, 9.0, 12.0], [PI * 0.5, 0.25, 20.0, 7.0], [-PI * 0.35, 0.15, 35.0, 4.0]]:
		waves.append({"direction": {"x": cos(heading + base[0]), "y": sin(heading + base[0])}, "amplitude": base[1], "wavelength": base[2], "speed": base[3]})
