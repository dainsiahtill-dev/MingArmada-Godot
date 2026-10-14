extends SceneTree
const Ocean = preload("res://modules/scene_engine/ocean/projected_ocean.gd")
var assertions := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures += 1; printerr("FAIL interactive wake ocean: ",message)
func run() -> void:
	var ocean := Ocean.new()
	check(ocean.has_method("bind_interactive_wake_field"),"ocean exposes optional field binding")
	check(ocean.has_method("set_interactive_wake_debug"),"ocean exposes diagnostic modes")
	if failures: ocean.free(); finish(); return
	var texture := ImageTexture.create_from_image(Image.create(4,4,false,Image.FORMAT_RGBAF))
	var bounds := Vector4(-48,-48,48,48)
	check(ocean.call("bind_interactive_wake_field",texture,bounds,true),"binding accepted before configure")
	var camera := Camera3D.new()
	ocean.configure(camera,texture,16,100.0)
	var material: ShaderMaterial = ocean.material_override
	check(material.get_shader_parameter("interactive_wake_enabled")==true,"configure publishes saved binding")
	check(material.get_shader_parameter("interactive_wake_bounds")==bounds,"world bounds reach material")
	check(material.get_shader_parameter("interactive_wake_surface")==texture,"surface channels reach actual sea material")
	var wave_components: Variant = material.get_shader_parameter("wave_components")
	var before := [material.get_shader_parameter("interactive_wake_surface"),material.get_shader_parameter("interactive_wake_bounds")]
	for bad: Vector4 in [Vector4.ZERO,Vector4(1,0,0,2),Vector4(NAN,0,1,2)]:
		check(not ocean.call("bind_interactive_wake_field",texture,bad,true),"malformed world window rejected")
		check([material.get_shader_parameter("interactive_wake_surface"),material.get_shader_parameter("interactive_wake_bounds")]==before,"invalid window cannot tear texture/bounds pair")
	check(not ocean.call("bind_interactive_wake_field",null,bounds,true),"missing texture cannot hide legacy wake")
	check(ocean.call("set_interactive_wake_debug","foam"),"foam diagnostic accepted")
	check(material.get_shader_parameter("interactive_wake_debug")==2,"foam mode reaches material")
	check(not ocean.call("set_interactive_wake_debug","invalid") and material.get_shader_parameter("interactive_wake_debug")==2,"bad mode atomic")
	ocean.set_surface_quality("low")
	ocean.configure(camera,texture,24,120.0)
	check(material.get_shader_parameter("interactive_wake_enabled")==true and material.get_shader_parameter("interactive_wake_bounds")==bounds,"quality/reconfigure retains live field")
	check(material.get_shader_parameter("wave_components")==wave_components,"binding never changes base five waves")
	check(ocean.call("bind_interactive_wake_field",null,Vector4.ZERO,false),"explicit disable clears field")
	check(material.get_shader_parameter("interactive_wake_enabled")==false and material.get_shader_parameter("interactive_wake_surface")==null,"disable releases texture reference before owner disposal")
	camera.free(); ocean.free(); finish()
func finish() -> void:
	print("INTERACTIVE_WAKE_OCEAN_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
