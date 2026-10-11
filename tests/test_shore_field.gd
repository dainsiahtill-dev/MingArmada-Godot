extends SceneTree

const ShoreField = preload("res://modules/scene_engine/ocean/shore_field.gd")
var failures := 0
var assertions := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, detail: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", detail)

func _run() -> void:
	var field := ShoreField.new()
	var sampler := func(x: float, z: float) -> float: return x + z * 0.5
	check(field.configure(sampler, Rect2(-20, -10, 40, 20), 32), "configure bounded injected coastline")
	check(field.get_bounds() == Vector4(-20, -10, 20, 10), "texture bounds retain world X/Z corners")
	var texture: Texture2D = field.get_texture()
	check(texture != null, "height texture exists")
	if texture:
		var height := texture.get_image()
		check(height.get_format() == Image.FORMAT_RF, "signed heights preserve shallow/deep/land, not clamped color")
		check(absf(height.get_pixel(0, 0).r + 25.0) < 1e-5, "west-south is underwater signed height")
		check(absf(height.get_pixel(31, 31).r - 25.0) < 1e-5, "east-north is dry land signed height")
	var before: Texture2D = field.get_texture()
	check(not field.configure(Callable(), Rect2(0, 0, 1, 1)), "invalid sampler rejected")
	check(field.get_texture() == before, "failed rebuild preserves accepted texture")
	var submerged := ShoreField.new()
	check(submerged.configure(func(_x: float, _z: float) -> float: return -2.4, Rect2(-20, -20, 40, 40), 32), "shallow underwater bank is accepted")
	check(submerged.get_coast_texture().get_image().get_pixel(16, 16).r > 10000, "underwater bank does not create fake shore surf")
	print("SHORE_FIELD_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
