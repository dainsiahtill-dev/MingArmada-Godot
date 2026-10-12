extends SceneTree
const Ocean=preload("res://modules/scene_engine/ocean/projected_ocean.gd")
var assertions:=0
var failures:=0
func _initialize()->void:_run.call_deferred()
func check(value:bool,reason:String)->void:
	assertions+=1
	if not value:failures+=1;printerr("FAIL water environment: ",reason)
func _run()->void:
	var viewport:=SubViewport.new();viewport.size=Vector2i(800,600);root.add_child(viewport)
	var camera:=Camera3D.new();viewport.add_child(camera);camera.position=Vector3(28,23,45);camera.look_at(Vector3(0,6,3))
	var ocean:=Ocean.new();viewport.add_child(ocean)
	ocean.configure(camera,load("res://assets/textures/waternormals.jpg"),16)
	ocean.configure_reflection(camera);ocean.enable_surface_optics(true)
	var material:ShaderMaterial=ocean.material_override
	var names:Array[String]=[]
	for entry:Dictionary in material.shader.get_shader_uniform_list():names.append(str(entry.name))
	var present:=true
	for name:String in ["water_legacy_optics","water_environment_ripple_gain","water_environment_horizon_weight"]:
		var found:=name in names;check(found,"actual formal material consumes "+name);present=present and found
	if present:
		check(material.get_shader_parameter("water_legacy_optics")==false,"ordinary ocean defaults to blue rough environment optics")
		var gain:Variant=material.get_shader_parameter("water_environment_ripple_gain")
		var peak:Variant=material.get_shader_parameter("water_environment_horizon_weight")
		check((gain is float or gain is int) and float(gain)>0.0 and float(gain)<=.25,"environment retains a restrained moving ripple")
		check((peak is float or peak is int) and float(peak)>=.35 and float(peak)<=.6,"reflection remains visible without complete sky replacement")
		var geometry:=ocean.mesh
		var waves:Variant=material.get_shader_parameter("wave_components")
		var mirror:=ocean.get_reflection_viewport()
		var normals:Variant=material.get_shader_parameter("normal_texture")
		ocean.set_simulation_time(12.25)
		material.set_shader_parameter("water_legacy_optics",true)
		ocean.set_surface_quality("high");ocean.update_projection();ocean.set_simulation_time(12.25)
		check(material.get_shader_parameter("water_legacy_optics")==true,"legacy A/B flag survives final owner updates")
		check(material.get_shader_parameter("wave_components")==waves and material.get_shader_parameter("wave_count")==5,"optical tuning preserves all five authoritative waves")
		check(material.get_shader_parameter("normal_texture")==normals,"full body/detail normal texture is retained")
		check(ocean.mesh==geometry and ocean.get_reflection_viewport()==mirror,"optical mode reuses original geometry and actual reflection owner")
		check(mirror.render_target_update_mode==SubViewport.UPDATE_ALWAYS,"rough sea keeps real planar reflection active")
		check(material.get_shader_parameter("simulation_time")==12.25 and material.get_shader_parameter("u_time")==12.25,"legacy comparison uses exact accepted time")
		material.set_shader_parameter("water_legacy_optics",false);ocean.update_projection()
		check(material.get_shader_parameter("water_legacy_optics")==false,"new optics restore without rebuilding world")
	ocean.free();viewport.free()
	print("WATER_ENVIRONMENT_OPTICS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
