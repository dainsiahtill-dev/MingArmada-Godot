extends SceneTree

const Uniforms = preload("res://modules/scene_engine/ocean/wave_uniforms.gd")
const Descriptor = preload("res://modules/contracts/wave_descriptor.gd")
const Ocean = preload("res://modules/scene_engine/ocean/projected_ocean.gd")
const World = preload("res://modules/scene_engine/world/world_view.gd")
var failures := 0
var assertions := 0

func _initialize() -> void: _run.call_deferred()

func check(condition: bool, detail: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", detail)

func _run() -> void:
	var original := Uniforms.components(Descriptor.original_descriptors())
	check(original.size() == 8, "native GPU wave buffer covers all eight supported slots")
	check(original[0].distance_to(Vector4(1, .02, .015, .9)) < 1e-6, "original expansion reaches shader uniforms")
	var invalid := [{"amplitude": 1.0, "direction": {"x": 0.0, "z": 0.0}, "wavelength": 100.0, "speed": 1.0}]
	check(Uniforms.components(invalid).is_empty(), "zero heading rejects before shader NaN")
	var enormous := [{"amplitude": 1.0, "direction": {"x": 1.0e300, "z": 1.0e300}, "wavelength": 100.0, "speed": 1.0}]
	var large := Uniforms.components(enormous)
	check(not large.is_empty() and large[0].is_finite(), "finite huge heading normalizes without squared overflow")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800, 600)
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0, 20, 10)
	camera.look_at(Vector3.ZERO)
	var world := World.new()
	viewport.add_child(world)
	var sea := func(_x: float, _z: float) -> float: return -24.0
	check(world.configure(sea, [], {"camera": camera, "resolution": 4, "chunk_radius": 0, "collision": false, "vegetation": false}), "default world wave profile is accepted")
	var ocean := world.get_ocean()
	check(ocean.material_override.get_shader_parameter("wave_count") == 5, "empty world default preserves original moving sea")
	var before: Variant = ocean.material_override.get_shader_parameter("wave_components")
	check(not ocean.set_wave_descriptors(invalid), "invalid wave injection rejected")
	check(ocean.material_override.get_shader_parameter("wave_components") == before, "rejected wave injection leaves accepted GPU input intact")
	world.dispose()
	viewport.queue_free()
	await process_frame
	print("WAVE_UNIFORM_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
