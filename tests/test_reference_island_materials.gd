extends SceneTree

const Chunk = preload("res://modules/scene_engine/terrain/terrain_chunk.gd")
const Ocean = preload("res://modules/scene_engine/ocean/projected_ocean.gd")
var assertions := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func check(value: bool, reason: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL: ", reason)

func _run() -> void:
	var original := Chunk.new()
	root.add_child(original)
	check(original.configure(func(x: float,z: float): return 4.0 + x * .01 + z * .02,Vector2i.ZERO,40.0,8,true),"legacy geometry configuration remains supported")
	check(original.material_override is StandardMaterial3D,"default terrain retains the migration vertex-color material")
	check(original.has_method("sync_surface_state"),"detailed terrain accepts the shared water uniforms without a private clock")
	check(original.has_method("get_surface_weights"),"terrain mesh stores bounded height and slope material weights")
	if not original.has_method("sync_surface_state") or not original.has_method("get_surface_weights"):
		original.free()
		print("REFERENCE_ISLAND_MATERIAL_TESTS assertions=",assertions," failures=",failures)
		quit(1)
		return
	var detailed := Chunk.new()
	root.add_child(detailed)
	check(detailed.call("configure",func(x: float,z: float): return 4.0 + x * .01 + z * .02,Vector2i.ZERO,40.0,8,true,{"detailed":true}),"enhanced surface is an explicit configuration")
	var material: ShaderMaterial = detailed.material_override
	check(material != null,"detailed surface creates a shader material")
	var source: Array = original.mesh.surface_get_arrays(0)
	var target: Array = detailed.mesh.surface_get_arrays(0)
	check(source[Mesh.ARRAY_VERTEX] == target[Mesh.ARRAY_VERTEX],"surface detail never changes injected vertex heights")
	check(source[Mesh.ARRAY_NORMAL] == target[Mesh.ARRAY_NORMAL],"surface detail preserves geometric slope normals")
	check(source[Mesh.ARRAY_COLOR] == target[Mesh.ARRAY_COLOR],"authored height palette remains intact as vertex color")
	check(source[Mesh.ARRAY_INDEX] == target[Mesh.ARRAY_INDEX],"surface detail leaves terrain collision triangles unchanged")
	check(detailed.get_collision_body().get_child_count() == 1,"detail retains one owned collision shape")
	var weights = detailed.call("get_surface_weights",-4.0,Vector3.UP)
	check(weights.x > .99 and weights.y < .001 and weights.z < .001,"flat seabed uses sand rather than grass")
	weights = detailed.call("get_surface_weights",1.5,Vector3.UP)
	check(weights.x > .99,"low flat beach remains dry sand")
	weights = detailed.call("get_surface_weights",18.0,Vector3.UP)
	check(weights.y > .95,"flat island interior supports a grass layer")
	weights = detailed.call("get_surface_weights",18.0,Vector3(.95,.15,0).normalized())
	check(weights.z > .95 and weights.y < .01,"steep slopes expose rock and suppress grass")
	for h: float in [-30.0,-1.0,0.0,2.0,6.0,12.0,70.0,130.0]:
		for n: Vector3 in [Vector3.UP,Vector3(.7,.7,0).normalized(),Vector3(.99,.1,0).normalized()]:
			weights = detailed.call("get_surface_weights",h,n)
			check(weights.is_finite() and minf(weights.x,minf(weights.y,weights.z)) >= 0.0 and absf(weights.x+weights.y+weights.z-1.0)<.000001,"surface weights remain normalized at every tested height and slope")
	var uvs: PackedVector2Array = target[Mesh.ARRAY_TEX_UV]
	check(uvs.size() == target[Mesh.ARRAY_VERTEX].size(),"each rendered vertex carries its material weights")
	for i in uvs.size():
		var expected: Vector3 = detailed.call("get_surface_weights",target[Mesh.ARRAY_VERTEX][i].y,target[Mesh.ARRAY_NORMAL][i])
		check(uvs[i].distance_to(Vector2(expected.x,expected.y)) < .000001,"rendered material weights match actual altitude and slope")
	var other := Chunk.new()
	root.add_child(other)
	check(other.call("configure",func(_x:float,_z:float):return 18.0,Vector2i(1,0),40.0,8,false,{"detailed":true}),"neighbor chunk has an independent surface")
	check(other.material_override != material,"shader uniforms belong to each chunk rather than a shared mutable resource")
	var ocean := Ocean.new()
	root.add_child(ocean)
	ocean.configure(null,load("res://assets/textures/waternormals.jpg"),8)
	var ocean_material: ShaderMaterial = ocean.material_override
	check(detailed.call("sync_surface_state",ocean_material),"ocean without islands still supplies its accepted wave and time state")
	check(not bool(material.get_shader_parameter("has_shore_field")),"a missing shore field uses the explicit offshore fallback")
	var wave := [{"amplitude":.6,"direction":{"x":1.0,"z":0.0},"wavelength":12.0,"speed":.7}]
	check(ocean.set_wave_descriptors(wave),"fixture uses a real non-default ocean wave")
	ocean.set_simulation_time(12.5)
	var image := Image.create(2,2,false,Image.FORMAT_RF)
	image.fill(Color(-4,0,0))
	var height_texture := ImageTexture.create_from_image(image)
	ocean.set_shore_field(height_texture,Vector4(-20,-20,20,20))
	check(detailed.call("sync_surface_state",ocean_material),"terrain accepts an actual configured ocean state")
	check(material.get_shader_parameter("simulation_time") == 12.5,"caustics and wet sand use accepted water time")
	check(material.get_shader_parameter("wave_components") == ocean_material.get_shader_parameter("wave_components"),"terrain receives the same wave amplitudes and phases")
	check(material.get_shader_parameter("wave_count") == 1,"custom wave count is copied rather than assumed five")
	check(material.get_shader_parameter("shore_height_texture") == height_texture,"shore attenuation reads the same height field resource")
	check(material.get_shader_parameter("shore_bounds") == ocean_material.get_shader_parameter("shore_bounds"),"height-field coordinate bounds remain consistent")
	check(bool(material.get_shader_parameter("coastal_attenuation")) == bool(ocean_material.get_shader_parameter("coastal_attenuation")),"terrain follows the configured coastal attenuation policy")
	check(float(other.material_override.get_shader_parameter("simulation_time")) == 0.0,"updating one chunk cannot advance another chunk")
	check(detailed.call("sync_surface_state",ocean_material),"paused state can be reapplied")
	check(material.get_shader_parameter("simulation_time") == 12.5,"reapplying accepted time never ages wet sand or caustics")
	ocean.set_simulation_time(2.0)
	check(detailed.call("sync_surface_state",ocean_material),"surface supports runtime rewind")
	check(material.get_shader_parameter("simulation_time") == 2.0,"rewind seeks the same visual time")
	var changed_components: PackedVector4Array = ocean_material.get_shader_parameter("wave_components")
	changed_components[0] = Vector4(.4,.2,.1,.9)
	ocean_material.set_shader_parameter("wave_components",changed_components)
	check(detailed.call("sync_surface_state",ocean_material),"same accepted time still accepts changed static wave configuration")
	check(material.get_shader_parameter("wave_components") == changed_components,"a static-wave cache cannot keep the old wave after configuration changes")
	var revised_bounds := Vector4(-40,-30,50,60)
	ocean_material.set_shader_parameter("shore_bounds",revised_bounds)
	check(detailed.call("sync_surface_state",ocean_material),"same accepted time accepts a new shore-field coordinate contract")
	check(material.get_shader_parameter("shore_bounds") == revised_bounds,"new shore-field bounds propagate without advancing time")
	ocean_material.set_shader_parameter("simulation_time",NAN)
	check(not detailed.call("sync_surface_state",ocean_material),"invalid surface time is rejected")
	check(material.get_shader_parameter("simulation_time") == 2.0,"invalid time leaves last accepted state intact")
	check(not detailed.call("sync_surface_state",null),"missing ocean state is rejected")
	var shader: String = material.shader.code
	check(not shader.contains("TIME"),"terrain shader has no wall-clock animation path")
	check(not shader.contains("ALPHA ="),"terrain remains opaque and avoids transparent land sorting")
	var mesh_ref: WeakRef = weakref(detailed.mesh)
	var material_ref: WeakRef = weakref(material)
	material = null
	detailed.dispose()
	detailed.dispose()
	check(detailed.mesh == null and detailed.material_override == null and detailed.get_collision_body() == null,"dispose releases mesh, material and owned collision")
	check(mesh_ref.get_ref() == null and material_ref.get_ref() == null,"surface does not retain private mesh or material after disposal")
	check(detailed.configure(func(_x:float,_z:float):return 6.0,Vector2i.ZERO,40.0,8,false),"disposed chunk can return to original mode")
	check(detailed.material_override is StandardMaterial3D and detailed.get_collision_body() == null,"reconfigure restores default material without old collision")
	check(detailed.call("configure",func(_x:float,_z:float):return 6.0,Vector2i.ZERO,40.0,8,false,{"detailed":true,"caustics":false}),"reconfigure can create a new detailed material")
	check(not bool(detailed.material_override.get_shader_parameter("caustics_enabled")),"caustic detail has an explicit effect switch")
	ocean_material.set_shader_parameter("simulation_time",2.0)
	check(detailed.call("sync_surface_state",ocean_material),"surface state is copied into the new private material even when source state did not change")
	check(detailed.material_override.get_shader_parameter("shore_bounds") == revised_bounds and detailed.material_override.get_shader_parameter("wave_components") == changed_components,"reconfiguration cannot reuse stale state-cache ownership")
	original.free()
	detailed.free()
	other.free()
	ocean.free()
	await process_frame
	print("REFERENCE_ISLAND_MATERIAL_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
