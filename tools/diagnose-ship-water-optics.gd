extends "res://tools/verify-interactive-wake-production-gpu.gd"
## Research only: immutable production shader, isolated in-memory one-factor variants.
var optics_shader:Shader
var source_code:String
var samples:Array=[]
var refinement:=false
var tuning:=false
var production_check:=false
var target_size:=Vector2i(1600,900)
const HISTORICAL_SHADER="res://docs/research/evidence/ship-water-optics-2026-10-14/reference-pre-integration.gdshader.txt"
func hashes()->Dictionary:
	var result:=super.hashes()
	for path:String in ["tools/diagnose-ship-water-optics.gd","modules/scene_engine/ocean/shore_edge_coverage.gdshaderinc","modules/scene_engine/ocean/reference_shore_foam.gdshaderinc","modules/scene_engine/ocean/water_environment_optics.gdshaderinc","modules/scene_engine/reference_island_water/source_common.gdshaderinc"]:
		result[path]=FileAccess.get_sha256("res://"+path)
	result[HISTORICAL_SHADER.trim_prefix("res://")]=FileAccess.get_sha256(HISTORICAL_SHADER)
	return result
func geometry_receipt()->Dictionary:
	var native:Dictionary=scene.runtime.snapshot().naval
	var ship:Node3D=scene.sea.ships[native.playerId]
	var count:=0;var below:=0;var lo:=INF;var hi:=-INF
	for node:Node in ship.get_model().find_children("*","MeshInstance3D",true,false):
		if str(node.get_meta("damage_surface",""))!="hull":continue
		for surface:int in node.mesh.get_surface_count():
			var arrays:Array=node.mesh.surface_get_arrays(surface)
			for local:Vector3 in arrays[Mesh.ARRAY_VERTEX]:
				var point:Vector3=node.global_transform*local
				var level:float=scene.runtime.sample_water_height(point.x,point.z,float(native.time))
				var clearance:=point.y-level
				count+=1;below+=int(clearance<0);lo=minf(lo,clearance);hi=maxf(hi,clearance)
	return {"hull_vertices":count,"below_authoritative_five_wave_surface":below,"minimum_clearance_m":lo,"maximum_clearance_m":hi,"scope":"Actual rigid hull vertices and authoritative five-wave height. Local GPU wake displacement is separately bounded to 0.25m."}
func variant(mode:String)->String:
	if mode=="production":return optics_shader.code
	var code:=source_code
	if mode=="no-transmission":code=code.replace("if(!u_refraction_enabled)","if(true)")
	if mode=="no-object-reflection":code=code.replace("if(u_use_reflection&&","if(false&&")
	if mode=="no-shore-feather":code=code.replace("if(shore_edge_feather_m>0.0 &&","if(false &&")
	if mode=="stronger-absorption":code=code.replace("vec3(.19,.075,.035)*optical_depth","vec3(.80,.40,.22)*optical_depth")
	if mode=="ray-length":
		code=code.replace("vec3 transmit=exp","optical_depth/=max(-normalize((VIEW_MATRIX*vec4(v_world,1)).xyz).z,0.05);\n\tvec3 transmit=exp")
	if mode=="linear-absorption":
		code=code.replace("scene*transmit+water_color*(1.0-transmit)","reference_to_display(reference_to_linear(scene)*transmit+reference_to_linear(water_color)*(1.0-transmit))")
	if mode=="depth":code=code.replace("ALPHA=1.0;","ALPHA=1.0; ALBEDO=vec3(clamp(optical_depth/5.0,0.0,1.0));")
	if mode=="submerged":code=code.replace("ALPHA=1.0;","ALPHA=1.0; ALBEDO=vec3(clamp(below_surface/5.0,0.0,1.0));")
	# A declared artistic effective scattering term, not measured seawater data.
	if mode in ["extinction","extinction-linear"]:
		code=code.replace("vec3(.19,.075,.035)*optical_depth","(vec3(.19,.075,.035)+vec3(.65))*optical_depth")
	if mode=="extinction-linear":
		code=code.replace("scene*transmit+water_color*(1.0-transmit)","reference_to_display(reference_to_linear(scene)*transmit+reference_to_linear(water_color)*(1.0-transmit))")
	if mode in ["linear-045","linear-035"]:
		var scatter:=".45" if mode=="linear-045" else ".35"
		code=code.replace("vec3(.19,.075,.035)*optical_depth","(vec3(.19,.075,.035)+vec3("+scatter+"))*optical_depth")
		code=code.replace("scene*transmit+water_color*(1.0-transmit)","reference_to_display(reference_to_linear(scene)*transmit+reference_to_linear(water_color)*(1.0-transmit))")
	return code
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		elif arg=="--refine":refinement=true
		elif arg=="--tune":tuning=true
		elif arg=="--production-check":production_check=true
		else:check(false,"unknown argument "+arg)
	check(not output.is_empty() and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output)),"fresh output")
	check(DisplayServer.get_name()!="headless","actual GPU")
	if not failures.is_empty():finish();return
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))==OK,"directory")
	output_owned=true;frozen=hashes()
	if production_check:target_size=Vector2i(2157,900)
	root.mode=Window.MODE_WINDOWED;root.unresizable=true
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT;root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_KEEP
	root.size=target_size;root.content_scale_size=target_size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	scene=Practice.new();scene.startup_options={"mode":"sail","staged":true}
	scene.settings_storage=Settings.new("user://tests/ship-water-optics-%d.json"%OS.get_process_id())
	root.add_child(scene);await process_frame;await process_frame
	scene.set_process(false);scene.set_physics_process(false)
	check(scene.startup_receipt.get("ok",false),"actual free-sail startup")
	if not failures.is_empty():finish();return
	scene.activate_entry();scene.sea.apply_settings({"quality":"balanced"});scene.interface.visible=false
	scene.runtime.set_pause("blur",false);await ticks(480)
	var frozen_state:=var_to_bytes(scene.runtime.snapshot())
	var native:Dictionary=scene.runtime.snapshot().naval
	var ship:Node3D=scene.sea.ships[native.playerId]
	var model:Node3D=ship.get_model()
	var focus:Vector3=model.global_position+Vector3.UP*2.0
	var mat:ShaderMaterial=scene.sea.world.get_ocean().material_override
	optics_shader=mat.shader;source_code=optics_shader.code
	if production_check:
		source_code=FileAccess.get_file_as_string(HISTORICAL_SHADER)
		var scattering:Variant=mat.get_shader_parameter("water_scattering")
		print("OPTICS_ACTUAL path=",optics_shader.resource_path," scatter=",scattering," linear=",mat.get_shader_parameter("water_linear_transmission")," code=",optics_shader.code.sha256_text())
		check((scattering is float or scattering is int) and is_equal_approx(float(scattering),.35),"actual default uses selected 0.35")
		check(mat.get_shader_parameter("water_linear_transmission")==true,"actual default uses linear transmission")
		check(mat.get_shader_parameter("preserve_shallow_transmission")==true,"actual default preserves coastal response")
		if not failures.is_empty():finish();return
	var geometry:=geometry_receipt()
	for angle:String in ["low","high"]:
		var eye:Vector3=focus+model.global_basis.x.normalized()*25.0+model.global_basis.z.normalized()*12.0+Vector3.UP*(5.0 if angle=="low" else 19.0)
		scene.sea.set_camera_controller(func():scene.sea.camera.global_position=eye;scene.sea.camera.look_at(focus))
		await settle()
		var modes:Array=["baseline","no-transmission","no-object-reflection","no-shore-feather","stronger-absorption","ray-length","linear-absorption","depth","submerged"]
		if refinement:modes=["baseline","extinction","extinction-linear","no-transmission"]
		if tuning:modes=["baseline","extinction-linear","linear-045","linear-035","no-transmission"]
		if production_check:modes=["baseline","linear-035","production"]
		for mode:String in modes:
			var shader:=Shader.new();shader.code=variant(mode);mat.shader=shader
			if mode=="production" or (mode=="baseline" and not production_check):mat.shader=optics_shader
			for _frame in 4:await process_frame
			await RenderingServer.frame_post_draw
			var label:=angle+"-"+mode
			var image:Image=root.get_texture().get_image()
			check(image.get_size()==target_size,"fixed framebuffer dimensions")
			check(image.save_png(output+"/"+label+".png")==OK,"save "+label)
			check(var_to_bytes(scene.runtime.snapshot())==frozen_state,"same authoritative state")
			records.append({"label":label,"image":label+".png","image_sha256":FileAccess.get_sha256(output+"/"+label+".png"),"camera":str(scene.sea.camera.global_transform),"time":native.time,"mode":mode,"geometry":geometry,"optics":scene.sea.world.get_ocean().get_surface_optics_diagnostics(),"shader_sha256":variant(mode).sha256_text()})
			print("SHIP_WATER_OPTICS_CAPTURE ",label)
		mat.shader=optics_shader
	if production_check:
		for frame_index in 12:
			await ticks(15)
			await capture("motion-%02d"%frame_index)
	check(hashes()==frozen,"production sources unchanged")
	check(records.size()==(18 if production_check else 10 if tuning else 8 if refinement else 18),"complete controlled capture matrix")
	finish()
