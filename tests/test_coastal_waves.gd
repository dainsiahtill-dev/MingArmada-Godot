extends SceneTree

const Coastal = preload("res://modules/physics_engine/ocean/coastal_wave_field.gd")
const Original = preload("res://modules/physics_engine/ocean/wave_field.gd")
var checks := 0
var failures := 0

func check(ok: bool) -> void:
	checks += 1
	if not ok: failures += 1

func _initialize() -> void:
	var original := Original.new()
	var coastal := Coastal.new()
	for depth: float in [0, 0.2, 1, 2.4, 4, 8, 24]:
		check(coastal.configure(func(_x: float, _z: float) -> float: return -depth))
		for index in 120:
			var actual: Dictionary = coastal.sample(-171.4158, -32.72906, index * 0.25)
			check(actual.height >= -depth and actual.height <= depth)
			if depth >= 8: check(absf(actual.height - original.sample(-171.4158, -32.72906, index * 0.25).height) < 1.0e-12)
	check(coastal.configure(func(x: float, z: float) -> float: return -4.0 + x * 0.1 + z * 0.05))
	var point := Vector2(0.5, 0.2)
	var state: Dictionary = coastal.sample(point.x, point.y, 10.0)
	var epsilon := 0.01
	var dx: float = (coastal.sample(point.x + epsilon, point.y, 10.0).height - coastal.sample(point.x - epsilon, point.y, 10.0).height) / (2.0 * epsilon)
	var dz: float = (coastal.sample(point.x, point.y + epsilon, 10.0).height - coastal.sample(point.x, point.y - epsilon, 10.0).height) / (2.0 * epsilon)
	check(absf(state.gradient.x - dx) < 1.0e-6 and absf(state.gradient.y - dz) < 1.0e-6)
	check(state.normal.is_equal_approx(Vector3(-dx, 1.0, -dz).normalized()))
	print("COASTAL_WAVE_TESTS assertions=", checks, " failures=", failures)
	quit(1 if failures else 0)
