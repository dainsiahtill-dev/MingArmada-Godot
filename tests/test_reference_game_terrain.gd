extends SceneTree

const Chunk = preload("res://modules/scene_engine/terrain/terrain_chunk.gd")
var assertions := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func check(value: bool, reason: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL: ",reason)

func finish() -> void:
	print("REFERENCE_GAME_TERRAIN_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)

func _run() -> void:
	var chunk: Variant = Chunk.new()
	root.add_child(chunk)
	check(is_nan(chunk.sample_mesh_height(0.0,0.0)),"unconfigured mesh has no invented height")
	var supports_state := false
	for method: Dictionary in chunk.get_method_list():
		if method.name == "sync_surface_state": supports_state=method.args.size() >= 2
	check(supports_state,"formal terrain accepts optional shared demo surface state while retaining legacy call")
	if not supports_state:
		chunk.free()
		finish()
		return
	var sample := func(x:float,z:float):return 3.0+x*.013+z*.021
	check(chunk.configure(sample,Vector2i(-1,2),40,8,true,{"detailed":true}),"formal detailed terrain configures without changing island geography")
	var original_vertices: PackedVector3Array=chunk.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var original_shape: Shape3D=chunk.get_collision_body().get_child(0).shape
	var material: ShaderMaterial=chunk.material_override
	var source := _source_material()
	source.set_shader_parameter("u_time",12.5)
	source.set_shader_parameter("u_tide",2.25)
	source.set_shader_parameter("u_sun",Vector3(-.8,.18,-.45).normalized())
	source.set_shader_parameter("u_sun_color",Vector3(1,.65,.35))
	check(chunk.sync_surface_state(source),"formal terrain consumes the actual demo-style material contract")
	check(material.get_shader_parameter("u_time") == 12.5 and material.get_shader_parameter("simulation_time") == 12.5,"new and legacy accepted-time views stay aligned")
	check(material.get_shader_parameter("u_tide") == 2.25,"wet sand and underwater caustics share ocean tide")
	check(material.get_shader_parameter("u_sun") == Vector3(-.8,.18,-.45).normalized(),"source sun direction is copied without an independent daylight clock")
	check(material.get_shader_parameter("u_sun_color") == Vector3(1,.65,.35),"source sunset color is retained")
	check(material.get_shader_parameter("u_caustics") == true,"default formal caustics remain enabled")
	var source_components: PackedVector4Array=material.get_shader_parameter("wave_components")
	check(material.get_shader_parameter("wave_count") == 4 and source_components.size() == 4,"source demo wave contract is translated without an assumed five-wave count")
	check(source_components[0].is_equal_approx(Vector4(.32,TAU/18.0,0,-1.4)),"source wave translation retains amplitude, direction and signed phase speed")
	check(chunk.sync_surface_state(source,{"time":20.0,"tide":-1.25,"preset":"clear","caustics":false}),"root can inject a validated shared presentation state")
	check(material.get_shader_parameter("u_time") == 20.0 and material.get_shader_parameter("u_tide") == -1.25,"shared override is authoritative for the accepted snapshot")
	check(material.get_shader_parameter("u_sun") == Vector3(-.5,.8,.3).normalized(),"clear preset uses the exact demo sun vector")
	check(material.get_shader_parameter("u_sun_color") == Vector3(1,.95,.82),"clear preset uses the exact demo sun color")
	check(material.get_shader_parameter("u_caustics") == false and material.get_shader_parameter("caustics_enabled") == false,"shared caustic switch cannot diverge across uniform contracts")
	var accepted: Dictionary = _surface_values(material)
	for invalid: Dictionary in [{"time":NAN},{"tide":INF},{"sun":Vector3(NAN,1,0)},{"sunColor":Vector3(1,INF,1)},{"preset":"invalid"},{"time":"invalid"},{"caustics":"invalid"}]:
		check(not chunk.sync_surface_state(source,invalid),"malformed shared state is rejected before any mutation")
		check(_surface_values(material) == accepted,"rejected state leaves every accepted surface input intact")
	check(chunk.sync_surface_state(source,{"time":20.0,"tide":-1.25,"preset":"clear","caustics":false}),"paused shared state can be reapplied")
	check(_surface_values(material) == accepted,"same accepted state never ages wet sand or caustics")
	check(chunk.sync_surface_state(source,{"time":2.0,"preset":"sunset","caustics":true}),"accepted rewind is supported")
	check(material.get_shader_parameter("u_time") == 2.0 and material.get_shader_parameter("u_sun_color") == Vector3(1,.65,.35),"rewind seeks source effects and requested lighting")
	check(chunk.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == original_vertices,"surface integration never changes terrain heights")
	check(chunk.get_collision_body().get_child(0).shape == original_shape,"surface integration keeps its original collision shape")
	check(chunk.has_method("sample_mesh_height"),"formal terrain provides actual rendered triangle height for precise local coast textures")
	if chunk.has_method("sample_mesh_height"):
		check(absf(chunk.sample_mesh_height(-43.125,83.75)-4.198125) < 2e-6,"world coordinate query follows translated chunk geography")
		for index: int in [0,1,8,9,40,80]:
			var vertex: Vector3=original_vertices[index]
			check(chunk.sample_mesh_height(vertex.x+chunk.position.x,vertex.z+chunk.position.z) == vertex.y,"query at a knot preserves actual Float32 vertex height")
		check(is_nan(chunk.sample_mesh_height(-60.01,80)) and is_nan(chunk.sample_mesh_height(-40,100.01)),"outside rendered chunk returns explicit missing height")
		check(is_nan(chunk.sample_mesh_height(NAN,80)),"nonfinite mesh queries cannot enter a texture")
		check(is_nan(chunk.sample_mesh_height(-40,INF)),"infinite mesh queries cannot enter a texture")
		for index: int in [0,8,72,80]:
			var vertex: Vector3=original_vertices[index]
			check(chunk.sample_mesh_height(vertex.x+chunk.position.x,vertex.z+chunk.position.z) == vertex.y,"closed outer border uses the exact drawn Float32 corner")
		var holder := Node3D.new()
		root.add_child(holder)
		holder.position=Vector3(500,3,-1000)
		chunk.reparent(holder,false)
		check(absf(chunk.sample_mesh_height(456.875,-916.25)-7.198125) < 2e-6,"mesh query includes actual parent translation and world height")
		holder.position+=Vector3(7,-4,13)
		check(absf(chunk.sample_mesh_height(463.875,-903.25)-3.198125) < 2e-6,"mesh query follows current parent translation instead of a cached world origin")
		chunk.reparent(root,false)
		holder.free()
		var saddle: Variant=Chunk.new()
		root.add_child(saddle)
		check(saddle.configure(func(x:float,z:float):return 10.0*(x+4.0)/2.0+20.0*(z+4.0)/2.0+10.0*(x+4.0)*(z+4.0)/4.0,Vector2i.ZERO,8,4,false),"nonplanar fixture uses the real formal terrain builder")
		check(saddle.sample_mesh_height(-3.5,-3.5) == 7.5,"lower actual triangle uses three corners instead of bilinear saddle height")
		check(saddle.sample_mesh_height(-2.5,-2.5) == 27.5,"upper actual triangle preserves the source diagonal")
		check(saddle.sample_mesh_height(-2,-2) == 40.0,"cell boundary uses the exact shared corner")
		var saddle_vertices: PackedVector3Array=saddle.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for row: int in 4:
			for column: int in 4:
				var a: int=row*5+column
				var c: int=a+5
				for fraction: Vector2 in [Vector2(.2,.3),Vector2(.5,.5),Vector2(.8,.7)]:
					var expected: float = saddle_vertices[a].y+(saddle_vertices[a+1].y-saddle_vertices[a].y)*fraction.x+(saddle_vertices[c].y-saddle_vertices[a].y)*fraction.y if fraction.x+fraction.y<=1 else saddle_vertices[c+1].y+(saddle_vertices[c].y-saddle_vertices[c+1].y)*(1-fraction.x)+(saddle_vertices[a+1].y-saddle_vertices[c+1].y)*(1-fraction.y)
					check(absf(saddle.sample_mesh_height(-4.0+(column+fraction.x)*2.0,-4.0+(row+fraction.y)*2.0)-expected)<.000001,"mesh query agrees with actual three-corner triangle in every saddle cell")
		check(saddle.configure(func(_x:float,_z:float):return -7.25,Vector2i(2,-3),16,8,false),"reconfigured mesh replaces the prior saddle geometry")
		check(saddle.sample_mesh_height(32.0,-48.0) == -7.25 and is_nan(saddle.sample_mesh_height(-3.5,-3.5)),"reconfiguration replaces height cache, resolution and translated footprint")
		saddle.dispose()
		check(is_nan(saddle.sample_mesh_height(-3.5,-3.5)),"disposed chunk releases its sampler height cache")
		saddle.free()
	var other: Variant = Chunk.new()
	root.add_child(other)
	check(other.configure(sample,Vector2i(0,2),40,8,false,{"detailed":true,"caustics":false}),"neighbor keeps an independent material and its configured local effect limit")
	check(other.sync_surface_state(source,{"caustics":true}),"local caustic limit can receive a global enabled state")
	check(other.material_override.get_shader_parameter("u_caustics") == false,"global state cannot override explicit per-chunk caustic disable")
	check(other.material_override != material,"formal tiles have no shared mutable clock resource")
	var source_ref: WeakRef = weakref(source)
	source = null
	check(source_ref.get_ref() == null,"tile state does not retain the ocean material")
	chunk.dispose(); other.dispose()
	check(chunk.mesh == null and chunk.material_override == null and chunk.get_collision_body() == null,"integration preserves terrain lifecycle")
	chunk.free(); other.free()
	finish()

func _source_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """shader_type spatial;
uniform float u_time=0.0;
uniform float u_tide=0.0;
uniform vec3 u_sun=vec3(-.505076,.808122,.303046);
uniform vec3 u_sun_color=vec3(1.0,.95,.82);
uniform bool u_caustics=true;
uniform vec4 u_waves[4];
uniform vec4 u_speeds=vec4(1.4,1.8,2.2,2.8);
uniform float u_strength=1.0;
void fragment(){ALBEDO=vec3(1.0);}
"""
	var result := ShaderMaterial.new()
	result.shader=shader
	result.set_shader_parameter("u_waves",PackedVector4Array([Vector4(1,0,.32,TAU/18),Vector4(0,1,.18,TAU/11),Vector4(.70710678,.70710678,.14,TAU/7),Vector4(-1,0,.09,TAU/4.2)]))
	return result

func _surface_values(material:ShaderMaterial) -> Dictionary:
	var result := {}
	for key: String in ["simulation_time","u_time","u_tide","u_sun","u_sun_color","u_caustics","caustics_enabled","wave_components","wave_count","shore_bounds","has_shore_field","shore_height_texture","coastal_attenuation"]:
		result[key]=material.get_shader_parameter(key)
	return result
