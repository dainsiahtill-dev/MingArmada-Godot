extends "res://tools/verify-interactive-wake-production-gpu.gd"
const Lifecycle=preload("res://modules/scene_engine/fidelity_fx/world_cloud_lifecycle.gd")
var evidence:Array=[]
var trajectories:Dictionary={}
var metrics:Dictionary={}
func hashes()->Dictionary:
	var result:=super.hashes()
	for path:String in ["modules/environment_engine/weather_state.gd","modules/scene_engine/fidelity_fx/world_cloud_lifecycle.gd","modules/scene_engine/fidelity_fx/atmosphere.gd","modules/scene_engine/fidelity_fx/atmosphere.gdshader","tools/verify-cloud-lifecycle-production-gpu.gd"]:result[path]=FileAccess.get_sha256("res://"+path)
	return result
func position()->Vector3:
	var d:Dictionary=scene.sea.world.atmosphere.diagnostics().worldCloudLifecycle
	return d.states[0].position if d.enabled else Lifecycle.vector(scene.runtime.snapshot().naval.environment.worldClouds[0].worldPosition)
func save_frame(label:String)->void:
	if not await settle():return
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	check(not image.is_empty() and image.save_png(output+"/"+label+".png")==OK,"actual normal scene capture "+label)
	var ocean:MeshInstance3D=scene.sea.world.get_ocean()
	var mirror:Image=ocean.get_reflection_viewport().get_texture().get_image()
	check(mirror.save_png(output+"/"+label+"-mirror.png")==OK,"actual mirror capture")
	var native:Dictionary=scene.runtime.snapshot().naval
	var material:ShaderMaterial=ocean.material_override
	check(material.get_shader_parameter("water_scattering")==.35 and material.get_shader_parameter("water_linear_transmission")==true and material.get_shader_parameter("preserve_shallow_transmission")==true,"accepted optics preserved")
	check(scene.sea.sailors.size()>0,"3D crew retained")
	evidence.append({"image":label+".png","sha256":FileAccess.get_sha256(output+"/"+label+".png"),"mirror":label+"-mirror.png","mirror_sha256":FileAccess.get_sha256(output+"/"+label+"-mirror.png"),"accepted_time":native.environment.acceptedTime,"camera":str(scene.sea.camera.global_transform),"native_clouds":native.environment.worldClouds,"display":scene.sea.world.atmosphere.diagnostics().worldCloudLifecycle,"field":scene.sea.interactive_water_status()})
func frame_cloud():
	var eye:=Vector3(-1598,170,700);var focus:=Vector3(-1598,70,0)
	scene.sea.set_camera_controller(func():scene.sea.camera.global_position=eye;scene.sea.camera.look_at(focus))
func profile(atmosphere:RefCounted,native:Dictionary)->Dictionary:
	var result:Dictionary={}
	for policy:bool in [false,true]:
		atmosphere.set_cloud_lifecycle_enabled(policy)
		atmosphere.apply_snapshot(native,scene.sea.camera,Vector3.ZERO,scene.sea.world.get_ocean().get_reflection_camera())
		var samples:Array[int]=[]
		for i in 96:
			var start:=Time.get_ticks_usec()
			atmosphere.apply_snapshot(native,scene.sea.camera,Vector3.ZERO,scene.sea.world.get_ocean().get_reflection_camera())
			var elapsed:=Time.get_ticks_usec()-start
			if i>=16:samples.append(elapsed)
		samples.sort();result["candidate" if policy else "baseline"]={"median_us":samples[40],"p95_us":samples[76],"samples":80,"scope":"paused same-packet CPU presentation only; not whole-game FPS"}
	return result
func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	check(not output.is_empty() and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output)),"fresh output")
	check(DisplayServer.get_name()!="headless","real GPU")
	if not failures.is_empty():finish();return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output));output_owned=true;frozen=hashes()
	root.size=Vector2i(1280,800);root.content_scale_size=root.size;root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	root.gui_disable_input=true;root.unfocusable=true;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var authorities:Dictionary={}
	for variant:String in ["baseline","production"]:
		scene=Practice.new();scene.startup_options={"mode":"sail","staged":true}
		scene.settings_storage=Settings.new("user://tests/cloud-life-%s-%d.json"%[variant,OS.get_process_id()])
		root.add_child(scene);await process_frame;await process_frame
		scene.set_process(false);scene.set_physics_process(false);isolate_input(scene)
		check(scene.startup_receipt.get("ok",false),"real free-sail starts")
		if not failures.is_empty():finish();return
		scene.activate_entry();scene.interface.visible=false;scene.minimap.visible=false
		if variant=="production":await save_frame("normal-entry")
		var owner:RefCounted=scene.runtime.simulation.encounter._environment
		var epoch:int=owner.snapshot().epoch
		check(owner.configure({"epoch":epoch,"model_scale":10.0,"crt_seed":1,"initial_state":{"lightTime":1200,"windHeading":1073741760,"windDisplacement":0,"windVelocity":0,"centers":[{"x":-15980,"y":0},{"x":3000,"y":4000},{"x":6000,"y":-4000}]}}),"explicit near-reset fixture in real weather producer")
		# Install the changed initial environment through the simulation's normal
		# refresh contract; its cached t=0 packet otherwise predates this fixture.
		scene.runtime.simulation.refresh_snapshot()
		check(scene.runtime.snapshot().naval.environment.worldClouds[0].worldPosition[0]==-1598.0,"fixture reaches actual cached runtime snapshot")
		var atmosphere:RefCounted=scene.sea.world.atmosphere
		atmosphere.reset_timeline();atmosphere.set_cloud_lifecycle_enabled(variant=="production")
		frame_cloud();await settle()
		authorities[variant]=[];trajectories[variant]=[]
		for tick in 121:
			if tick>0:await ticks(1)
			await settle()
			var native:Dictionary=scene.runtime.snapshot().naval
			var packet:Dictionary=native.environment
			var d:Dictionary=atmosphere.diagnostics().worldCloudLifecycle
			var p:=position()
			authorities[variant].append(var_to_bytes(packet).hex_encode().sha256_text())
			trajectories[variant].append({"time":packet.acceptedTime,"position":[p.x,p.y,p.z],"generation":packet.worldClouds[0].generation,"retiring":d.states.get(0,{}).get("retiring",false),"recycles":d.states.get(0,{}).get("recycles",0)})
			check(atmosphere.diagnostics().worldWeatherInstances==3,"fixed three presentation actors")
			if tick in [0,2,8,15,30,60,90,120]:await save_frame("%s-%03d"%[variant,tick])
		if variant=="production":
			var retained:=var_to_bytes(scene.runtime.snapshot())
			var display:Dictionary=atmosphere.diagnostics().worldCloudLifecycle.states
			var cloud_owner:=atmosphere
			scene.sea.apply_settings({"quality":"high"});await settle();await save_frame("quality-high-paused")
			check(scene.sea.world.atmosphere==cloud_owner and atmosphere.diagnostics().worldCloudLifecycle.states==display,"quality reuses complete visible trajectory")
			var eye:=Vector3(-1598,80,700);var focus:=Vector3(-1598,100,0)
			scene.sea.set_camera_controller(func():scene.sea.camera.global_position=eye;scene.sea.camera.look_at(focus))
			await save_frame("low-angle-paused")
			check(atmosphere.diagnostics().worldCloudLifecycle.states==display,"paused camera orbit cannot recycle")
			check(var_to_bytes(scene.runtime.snapshot())==retained,"quality and camera do not advance source RNG/time")
			for instance:Dictionary in atmosphere._weather:
				for record:Dictionary in instance.meshes:check(record.material.render_priority==(0 if record.bakedShadow else 2),"cloud ocean pass and baked shadow retained")
			# Turn both main and mirrored views away; only a subsequent accepted
			# frame may retire the old actor, with replacement outside both views.
			eye=Vector3(-1598,170,700);focus=Vector3(-1598,170,1700)
			scene.sea.set_camera_controller(func():scene.sea.camera.global_position=eye;scene.sea.camera.look_at(focus))
			await settle();check(atmosphere.diagnostics().worldCloudLifecycle.states==display,"same-time look-away cannot force a recycle")
			await ticks(2);await save_frame("after-offscreen-recycle")
			var state:Dictionary=atmosphere.diagnostics().worldCloudLifecycle.states[0]
			check(state.recycles==1 and not state.retiring,"formal complete actor recycles only after leave")
			var radius:float=atmosphere._weather[0].lifecycleRadius+Lifecycle.VIEW_MARGIN_METRES
			check(not Lifecycle.sphere_in_views(state.position,radius,scene.sea.camera.get_frustum(),scene.sea.world.get_ocean().get_reflection_camera().get_frustum()),"formal new actor outside main and real reflected frusta")
			metrics.cpu=profile(atmosphere,scene.runtime.snapshot().naval)
		var playbacks:Array[WeakRef]=AudioCleanup.stop_players(scene)
		scene.free();scene=null;check(await AudioCleanup.wait_for_release(self,playbacks),"variant audio resources released")
	check(authorities.baseline==authorities.production,"all 121 normal runtime accepted packets identical between policies")
	metrics.baseline_first_jump_m=Lifecycle.vector(trajectories.baseline[2].position).distance_to(Lifecycle.vector(trajectories.baseline[1].position))
	metrics.production_first_step_m=Lifecycle.vector(trajectories.production[2].position).distance_to(Lifecycle.vector(trajectories.production[1].position))
	check(metrics.baseline_first_jump_m>1000 and metrics.production_first_step_m<2.0,"real runtime reset retains continuous cloud instead of km pop")
	check(hashes()==frozen,"production sources frozen")
	var file:=FileAccess.open(output+"/LIFECYCLE_VERIFY.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"valid":failures.is_empty(),"failures":failures,"sources":frozen,"captures":evidence,"trajectories":trajectories,"metrics":metrics,"scope":"Real free-sail entrance, production runtime/physics/ocean/crew/planar reflection. A declared near-reset Weather fixture at normal modelScale10 is the only altered initial state. Two121-sample60Hz runs; eight visible timeline captures plus mirror each. Quality/pause/camera/offscreen recycle checks. CPU timings are not whole-game FPS."},"\t"));file.close()
	print("CLOUD_LIFECYCLE_PRODUCTION_GPU captures=",evidence.size()," failures=",failures.size());finish()
