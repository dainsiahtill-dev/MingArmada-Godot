extends SceneTree
const World = preload("res://modules/scene_engine/world/world_view.gd")
var assertions := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(value: bool, reason: String) -> void:
	assertions += 1
	if not value: failures += 1; printerr("FAIL: ",reason)
func _run() -> void:
	var camera := Camera3D.new(); root.add_child(camera)
	camera.position = Vector3(0,100,100)
	var ports := [{"id":"far","x":2050.0,"z":0.0,"islandX":2000.0,"islandZ":0.0,"radius":80.0}]
	var height := func(x: float,z: float): return 30.0 - Vector2(x-2000.0,z).length() * .5
	var world := World.new(); root.add_child(world)
	check(world.configure(height,[],{"camera":camera,"ports":ports,"vegetation":false,"island_details":false,"resolution":4,"chunk_radius":0,"collision":false}),"actual enhanced world configures")
	var ocean = world.get_ocean()
	check(ocean.get_surface_optics_diagnostics().enabled,"product world enables optics with its actual camera")
	check(not world.get_distant_chunks().is_empty(),"far island has supported terrain")
	for seconds: float in [12.5,12.5,2.0]:
		world.apply_snapshot({"time":seconds,"focus":Vector2.ZERO})
		for chunk in world.get_chunks() + world.get_distant_chunks():
			var material: ShaderMaterial = chunk.material_override
			check(material != null,"near and far terrain use private detail shaders")
			check(material.get_shader_parameter("simulation_time") == seconds,"wet sand and caustics share accepted time including pause and rewind")
			check(material.get_shader_parameter("wave_components") == ocean.material_override.get_shader_parameter("wave_components"),"terrain receives original ocean waves")
			check(material.get_shader_parameter("shore_height_texture") == ocean.material_override.get_shader_parameter("shore_height_texture"),"terrain shares read-only coast field")
	world.apply_snapshot({"time":8.0,"focus":Vector2(3000,0)})
	for chunk in world.get_chunks():
		check(chunk.material_override.get_shader_parameter("simulation_time") == 8.0,"streamed tiles are initialized at current accepted time")
	world.dispose(); world.free()
	var legacy := World.new(); root.add_child(legacy)
	check(legacy.configure(height,[],{"camera":camera,"visual_style":0,"ports":ports,"vegetation":false,"resolution":4,"chunk_radius":0,"collision":false}),"frozen legacy world configures")
	check(not legacy.get_ocean().get_surface_optics_diagnostics().enabled,"frozen legacy keeps original non-screen shader")
	for chunk in legacy.get_chunks() + legacy.get_distant_chunks(): check(chunk.material_override is StandardMaterial3D,"legacy terrain remains unchanged")
	legacy.dispose(); legacy.free(); camera.free()
	print("REFERENCE_SURFACE_INTEGRATION_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
