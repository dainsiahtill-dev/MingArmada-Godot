extends SceneTree

const Spray = preload("res://modules/scene_engine/ocean/shore_spray.gd")
const ShoreField = preload("res://modules/scene_engine/ocean/shore_field.gd")
var assertions := 0
var failures := 0

func check(condition: bool, detail: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", detail)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var sampler := func(x: float, _z: float) -> float: return x * 0.1
	var bounds := Rect2(-20, -20, 40, 40)
	var field := ShoreField.new()
	check(field.configure(sampler, bounds, 32), "injected field contains genuine dry/wet crossing")
	var spray := Spray.new()
	root.add_child(spray)
	check(spray.configure(sampler, bounds, 160), "configure shallow-water spray from actual ground")
	check(spray.multimesh.instance_count <= 160, "texture detail retains existing spray count budget")
	check(spray.multimesh.mesh.size == Vector2(0.7, 0.7), "texture detail retains existing quad dimensions")
	spray.set_shore_field(field.get_texture(), field.get_bounds(), field.get_coast_texture())
	var material: ShaderMaterial = spray.material_override
	check(material.get_shader_parameter("has_coast_distance_field") == true, "spray receives true coast distance instead of outlining every shallow bank")
	check(material.get_shader_parameter("coast_distance_texture") == field.get_coast_texture(), "coast texture is the injected field")
	var mask: Texture2D = material.get_shader_parameter("spray_mask_texture")
	check(mask != null and mask.resource_path.ends_with("water spash.tga.png"), "spray binds sparse alpha droplets from original reference")
	spray.set_simulation_time(17.25)
	check(material.get_shader_parameter("simulation_time") == 17.25, "native caller time reaches spray")
	spray.set_simulation_time(NAN)
	check(material.get_shader_parameter("simulation_time") == 17.25, "invalid time retains accepted phase")
	await process_frame
	await process_frame
	check(material.get_shader_parameter("simulation_time") == 17.25, "engine frames do not advance paused spray")
	check(spray.configure(sampler, bounds, 160), "reconfigure same shallow samples")
	material = spray.material_override
	check(material.get_shader_parameter("simulation_time") == 17.25, "rebuild preserves caller's accepted simulation phase")
	spray.set_shore_field(field.get_texture(), field.get_bounds())
	check(material.get_shader_parameter("has_coast_distance_field") == false, "missing coast distances suppress ungrounded breaking spray")
	spray.queue_free()
	await process_frame
	print("SHORE_SPRAY_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
