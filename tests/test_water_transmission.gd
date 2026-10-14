extends SceneTree
const Demo=preload("res://game/research/demos/ocean_surface_experiment.gd")
var assertions:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL WATER TRANSMISSION ",label)
func run()->void:
	var viewport:=SubViewport.new();viewport.size=Vector2i(800,450);viewport.own_world_3d=true;root.add_child(viewport)
	var camera:=Camera3D.new();viewport.add_child(camera);camera.position=Vector3(0,10,20);camera.look_at(Vector3.ZERO)
	var ocean:=preload("res://modules/scene_engine/ocean/projected_ocean.gd").new();viewport.add_child(ocean)
	ocean.configure(camera,load("res://assets/textures/waternormals.jpg"),16);ocean.configure_reflection(camera);ocean.enable_surface_optics(true)
	check(ocean.material_override.get_shader_parameter("water_scattering")==.35 and ocean.material_override.get_shader_parameter("water_linear_transmission")==true,"formal owner explicitly configures selected defaults")
	var declared:Array=[]
	for u:Dictionary in ocean.material_override.shader.get_shader_uniform_list():declared.append(u.name)
	check("water_scattering" in declared and "water_linear_transmission" in declared,"optical inputs are shader declarations")
	check("preserve_shallow_transmission" in declared,"coastal preservation is a real shader input")
	check(ocean.material_override.get_shader_parameter("preserve_shallow_transmission")==true,"formal owner preserves existing shallows")
	ocean.free();camera.free()
	var demo:=Demo.new();viewport.add_child(demo)
	check(demo.configure({"paused":true}).ok,"existing lab builds")
	var before:Dictionary=demo.inspection_snapshot()
	var material:ShaderMaterial=demo._ocean.material_override
	var controls:Array=[]
	for c:Dictionary in demo.control_spec():controls.append(c.id)
	check("water_scattering" in controls,"lab exposes calibrated extinction")
	check("water_linear_transmission" in controls,"lab exposes transmission domain")
	var amount:Variant=material.get_shader_parameter("water_scattering")
	check((amount is float or amount is int) and is_equal_approx(float(amount),.35),"default is selected transparent candidate")
	check(material.get_shader_parameter("water_linear_transmission")==true,"default linear transmission")
	check(demo.set_parameter("water_scattering",.65).get("ok",false),"comparison candidate can be selected")
	check(material.get_shader_parameter("water_scattering")==.65,"control reaches real shared water")
	for bad:Variant in [-.1,1.1,NAN,INF,"clear",true]:
		check(not demo.set_parameter("water_scattering",bad).get("ok",false),"invalid extinction rejected "+str(bad))
	check(material.get_shader_parameter("water_scattering")==.65,"invalid requests atomic")
	check(not demo.set_parameter("water_linear_transmission",1).get("ok",false),"linear mode requires boolean")
	check(demo.set_parameter("water_scattering",0.0).get("ok",false),"legacy scatter response available")
	check(demo.set_parameter("water_linear_transmission",false).get("ok",false),"legacy display mixing available")
	demo._ocean.set_surface_quality("high");demo.refresh_viewport()
	check(material.get_shader_parameter("water_scattering")==0.0 and material.get_shader_parameter("water_linear_transmission")==false,"same owner quality preserves comparison")
	check(demo.reset_experiment({"water_scattering":.35,"water_linear_transmission":true}).ok,"reset restores accepted values")
	var after:Dictionary=demo.inspection_snapshot()
	check(before.time==after.time and before.telemetry.wave_samples==after.telemetry.wave_samples,"water physics and accepted clock unchanged")
	check(after.telemetry.wave_count==5,"five waves retained")
	check(after.telemetry.uniforms.get("water_scattering")==.35 and after.telemetry.uniforms.get("water_linear_transmission")==true,"inspection receipt records optical factors")
	check(demo.set_parameter("preserve_shallow_transmission",false).get("ok",false),"lab can isolate coastal preservation")
	check(demo._ocean.material_override.get_shader_parameter("preserve_shallow_transmission")==false,"coast factor reaches formal material")
	var text:=FileAccess.get_file_as_string("res://modules/scene_engine/ocean/reference_shore_foam.gdshaderinc")
	var regex:=RegEx.new();regex.compile("(?s)float reference_shallow_transmission_preservation\\(float depth, float coast\\)\\s*\\{([^}]+)\\}")
	var found:=regex.search(text)
	check(found!=null,"actual coastal transmission weighting exists")
	if found:
		var script:=GDScript.new();script.source_code="extends RefCounted\nfunc sample(depth:float,coast:float)->float:\n\t"+found.get_string(1).strip_edges().replace(";","")+"\n"
		check(script.reload()==OK,"actual weight compiles for numeric check")
		if script.can_instantiate():
			var model:RefCounted=script.new()
			for row:Array in [[0.,0.,1.],[1.5,12.,1.],[3.75,12.,.5],[6.,12.,0.],[1.,80.,0.],[1.,1000.,0.],[20.,0.,0.]]:
				check(absf(model.sample(row[0],row[1])-row[2])<.00001,"real shore vs offshore weight "+str(row))
	demo.dispose();viewport.free()
	print("WATER_TRANSMISSION_TESTS assertions=",assertions," failures=",failures)
	quit(0 if failures==0 else 1)
