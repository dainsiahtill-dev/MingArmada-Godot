extends SceneTree
const Demo=preload("res://game/research/demos/weather_shadow_experiment.gd")
const Lifecycle=preload("res://modules/scene_engine/fidelity_fx/world_cloud_lifecycle.gd")
const SOURCES=["modules/environment_engine/weather_state.gd","modules/scene_engine/fidelity_fx/world_cloud_lifecycle.gd","modules/scene_engine/fidelity_fx/atmosphere.gd","modules/scene_engine/fidelity_fx/atmosphere.gdshader","game/research/demos/weather_shadow_experiment.gd","tools/verify-cloud-lifecycle-lab-gpu.gd"]
var output:=""
var failures:Array[String]=[]
var evidence:Array=[]
var trajectories:Dictionary={}
var sources:Dictionary={}
var demo:Node3D
func _initialize()->void:run.call_deferred()
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message);printerr("FAIL: ",message)
func hashes()->Dictionary:
	var result:Dictionary={}
	for path:String in SOURCES:result[path]=FileAccess.get_sha256("res://"+path)
	return result
func values(v:Vector3)->Array:return [v.x,v.y,v.z]
func capture(label:String,packet:Dictionary)->Image:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	check(not image.is_empty(),"real lab framebuffer")
	check(image.save_png(output+"/"+label+".png")==OK,"save "+label)
	evidence.append({"image":label+".png","sha256":FileAccess.get_sha256(output+"/"+label+".png"),"time":packet.acceptedTime})
	return image
func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	check(not output.is_empty() and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output)),"fresh lab output")
	check(DisplayServer.get_name()!="headless","actual GPU")
	if not failures.is_empty():quit(1);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output));sources=hashes()
	root.size=Vector2i(1280,800);root.content_scale_size=root.size;root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	root.gui_disable_input=true;root.unfocusable=true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var frames:Dictionary={};var authority:Dictionary={}
	for variant:String in ["baseline","candidate"]:
		demo=Demo.new();root.add_child(demo)
		check(demo.configure({"preset":"cloud_exit","cloud_lifecycle":variant=="candidate","sky_enabled":false}).ok,"lab preset configure")
		trajectories[variant]=[];frames[variant]=[];authority[variant]=[]
		var previous:Dictionary={}
		for tick in 129:
			if tick>0:demo.advance(1.0/32.0)
			var inspected:Dictionary=demo.inspection_snapshot()
			var packet:Dictionary=inspected.environment
			authority[variant].append(var_to_bytes(packet).hex_encode().sha256_text())
			var current:Dictionary=inspected.telemetry.renderer.worldCloudLifecycle.states.get(0,{})
			var position:Vector3=Lifecycle.vector(packet.worldClouds[0].worldPosition) if current.is_empty() else current.position
			trajectories[variant].append({"time":packet.acceptedTime,"position":values(position),"native":packet.worldClouds[0].worldPosition,"generation":packet.worldClouds[0].generation,"retiring":current.get("retiring",false),"recycles":current.get("recycles",0),"radius":demo._atmosphere._weather[0].get("lifecycleRadius",0.0)})
			if variant=="candidate" and tick==1:check(current.retiring and position.distance_to(previous.position)<4.0,"on-screen source reset retains moving whole actor")
			if variant=="candidate" and not previous.is_empty() and current.recycles>previous.recycles:
				var radius:float=demo._atmosphere._weather[0].lifecycleRadius+Lifecycle.VIEW_MARGIN_METRES
				check(not Lifecycle.sphere_in_views(previous.position+previous.velocity/32.0,radius,demo._camera.get_frustum()),"outgoing bound fully outside at recycle")
				check(not Lifecycle.sphere_in_views(position,radius,demo._camera.get_frustum()),"incoming bound starts offscreen")
			previous=current
			if (tick<=64 and tick%4==0) or tick in [80,96,112,113,114,115,116,128]:
				frames[variant].append(await capture("%s-%03d"%[variant,tick],packet))
			else:await process_frame
			check(inspected.telemetry.world_weather_instances==3,"bounded three actors")
		if variant=="candidate":check(int(previous.recycles)>0,"fixture observes an actual offscreen recycle")
		demo.dispose();demo.free();demo=null;await process_frame
	check(authority.baseline==authority.candidate,"A/B complete source packet hashes identical at all 129 times")
	var old_jump:=Lifecycle.vector(trajectories.baseline[1].position).distance_to(Lifecycle.vector(trajectories.baseline[0].position))
	var new_step:=Lifecycle.vector(trajectories.candidate[1].position).distance_to(Lifecycle.vector(trajectories.candidate[0].position))
	check(old_jump>1000.0 and new_step<4.0,"baseline kilometer pop replaced by continuous movement")
	var changed:=0
	for y in range(100,740,2):
		for x in range(100,1180,2):
			var a:Color=frames.baseline[1].get_pixel(x,y);var b:Color=frames.candidate[1].get_pixel(x,y)
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>.08:changed+=1
	check(changed>500,"candidate visible cloud survives reset in real pixels")
	check(hashes()==sources,"lab sources frozen")
	var file:=FileAccess.open(output+"/LAB_VERIFY.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"valid":failures.is_empty(),"failures":failures,"gpu":RenderingServer.get_video_adapter_name(),"sources":sources,"captures":evidence,"trajectories":trajectories,"metrics":{"baseline_first_jump_m":old_jump,"candidate_first_step_m":new_step,"changed_sampled_pixels":changed},"scope":"Existing weather-shadow Godot laboratory. Declared near-reset source fixture, fixed camera, seed1,129 accepted samples per arm at32Hz.25 framebuffer samples per arm:0..2s at8Hz plus exit/recycle surrounding frames through4s. Original modelScale1 on diagnostic grid, not full-game FPS or original pixel parity."},"\t"));file.close()
	print("CLOUD_LIFECYCLE_LAB_GPU captures=",evidence.size()," failures=",failures.size());quit(1 if failures.size() else 0)
