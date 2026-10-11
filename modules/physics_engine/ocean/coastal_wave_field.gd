extends RefCounted
## Depth-limited native ocean profile. The original offshore wave field is intact.
## Eight metres is shared with coastal_wave_functions.gdshaderinc.

const Original = preload("res://modules/physics_engine/ocean/wave_field.gd")
const BREAKING_DEPTH := 8.0
var _original := Original.new()
var _height_sampler: Callable

func configure(height_sampler: Callable) -> bool:
	if not height_sampler.is_valid(): return false
	_height_sampler = height_sampler
	return true

func sample(x: float, z: float, time: float) -> Dictionary:
	var raw: Dictionary = _original.sample(x, z, time)
	if not _height_sampler.is_valid(): return raw
	var height := float(_height_sampler.call(x, z))
	if not is_finite(height): return raw
	var depth := -height
	if depth >= BREAKING_DEPTH: return raw
	if depth <= 0.0: return {"height": 0.0, "gradient": Vector2.ZERO, "normal": Vector3.UP}
	var t := depth / BREAKING_DEPTH
	var scale := t * t * (3.0 - 2.0 * t)
	var derivative := 6.0 * t * (1.0 - t) / BREAKING_DEPTH
	var ground_dx := float(_height_sampler.call(x + 0.5, z)) - float(_height_sampler.call(x - 0.5, z))
	var ground_dz := float(_height_sampler.call(x, z + 0.5)) - float(_height_sampler.call(x, z - 0.5))
	var gx := float(raw.gradient.x) * scale - float(raw.height) * derivative * ground_dx
	var gz := float(raw.gradient.y) * scale - float(raw.height) * derivative * ground_dz
	return {"height": float(raw.height) * scale, "gradient": Vector2(gx, gz), "normal": Vector3(-gx, 1.0, -gz).normalized()}
