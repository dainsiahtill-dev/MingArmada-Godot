extends SceneTree

const Ocean = preload("res://modules/scene_engine/ocean/projected_ocean.gd")
const World = preload("res://modules/scene_engine/world/world_view.gd")
var assertions := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func check(value: bool, reason: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL: ", reason)

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800,600)
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0,25,20)
	camera.look_at(Vector3.ZERO)
	var ocean := Ocean.new()
	viewport.add_child(ocean)
	ocean.configure(camera,load("res://assets/textures/waternormals.jpg"),16)
	check(ocean.has_method("set_surface_wind"),"ocean accepts authoritative wind for separate surface layers")
	check(ocean.has_method("set_surface_quality"),"surface detail has an explicit bounded quality budget")
	if ocean.has_method("set_surface_wind") and ocean.has_method("set_surface_quality"):
		var material: ShaderMaterial = ocean.material_override
		var waves: Variant = material.get_shader_parameter("wave_components")
		ocean.set_surface_wind(Vector2(3,4),18.0)
		check(material.get_shader_parameter("surface_wind_direction").distance_to(Vector2(.6,.8)) < .00001,"wind heading normalized in XZ")
		check(material.get_shader_parameter("surface_wind_speed") == 18.0,"wind speed reaches surface only")
		ocean.set_simulation_time(8.0)
		ocean.set_simulation_time(8.0)
		check(material.get_shader_parameter("simulation_time") == 8.0,"paused surface uses accepted time")
		ocean.set_surface_wind(Vector2(NAN,0),10.0)
		check(material.get_shader_parameter("surface_wind_speed") == 18.0,"invalid wind cannot poison accepted surface uniforms")
		ocean.set_surface_wind(Vector2.ZERO,0.0)
		check(material.get_shader_parameter("surface_wind_direction").is_finite(),"calm wind has a finite deterministic heading")
		check(material.get_shader_parameter("surface_wind_speed") == 0.0,"calm removes wind-driven glints")
		ocean.set_surface_wind(Vector2(1,0),1.0e100)
		check(material.get_shader_parameter("surface_wind_speed") <= 60.0,"extreme finite wind is bounded for fragment detail")
		ocean.set_surface_quality("low")
		var low := float(material.get_shader_parameter("surface_detail_strength"))
		ocean.set_surface_quality("high")
		var high := float(material.get_shader_parameter("surface_detail_strength"))
		check(low > 0.0 and high > low and high <= .16,"quality scales a bounded surface detail budget")
		check(material.get_shader_parameter("reference_whitecaps_texture") is Texture2D,"whitecaps read an actual alpha texture")
		check(material.get_shader_parameter("wave_components") == waves,"wind and detail quality never change buoyancy wave descriptors")
		ocean.set_visual_style(0)
		check(material.get_shader_parameter("visual_style") == 0,"original water profile still selectable")
	ocean.free()
	var world := World.new()
	viewport.add_child(world)
	check(world.configure(func(_x: float,_z: float): return -30.0,[],{"camera":camera,"resolution":4,"chunk_radius":0,"vegetation":false,"collision":false,"quality":"low"}),"generic world accepts surface quality")
	world.apply_snapshot({"time":3.0,"wind":{"direction":{"x":0.0,"y":1.0},"speed":12.0}})
	check(world.get_ocean().material_override.get_shader_parameter("surface_wind_speed") == 12.0,"world forwards wind without advancing a private clock")
	world.dispose()
	viewport.queue_free()
	await process_frame
	print("REFERENCE_OCEAN_LAYER_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
