extends "res://tools/verify-interactive-wake-production-gpu.gd"
var evidence:Array=[]
var pixel_metrics:Array=[]
func hashes()->Dictionary:
	var result:=super.hashes()
	for f:String in ["modules/scene_engine/fidelity_fx/atmosphere.gd","modules/scene_engine/fidelity_fx/atmosphere.gdshader","modules/environment_engine/weather_state.gd","tools/verify-cloud-ocean-composition.gd"]:
		result[f]=FileAccess.get_sha256("res://"+f)
	return result
func save_frame(label:String)->Image:
	for i in 3:await process_frame
	await RenderingServer.frame_post_draw
	var img:Image=root.get_texture().get_image()
	check(img.save_png(output+"/"+label+".png")==OK,"save "+label)
	evidence.append({"image":label+".png","sha256":FileAccess.get_sha256(output+"/"+label+".png"),"time":scene.runtime.snapshot().naval.time,"camera":str(scene.sea.camera.global_transform),"clouds":scene.runtime.snapshot().naval.environment.worldClouds})
	return img
func changed_pixels(a:Image,b:Image,region:Rect2i)->int:
	var count:=0
	for y in range(region.position.y,region.end.y):
		for x in range(region.position.x,region.end.x):
			var ca:=a.get_pixel(x,y);var cb:=b.get_pixel(x,y)
			if absf(ca.r-cb.r)+absf(ca.g-cb.g)+absf(ca.b-cb.b)>.07:count+=1
	return count
func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	check(not output.is_empty() and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output)),"fresh output")
	check(DisplayServer.get_name()!="headless","actual GPU")
	if not failures.is_empty():finish();return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output));output_owned=true;frozen=hashes()
	root.size=Vector2i(1280,800);root.content_scale_size=root.size;root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	root.unresizable=true;root.unfocusable=true;root.gui_disable_input=true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	scene=Practice.new();scene.startup_options={"mode":"sail","staged":true}
	scene.settings_storage=Settings.new("user://tests/cloud-composition-%d.json"%OS.get_process_id())
	root.add_child(scene);await process_frame;await process_frame
	scene.set_process(false);scene.set_physics_process(false);isolate_input(scene)
	check(scene.startup_receipt.get("ok",false),"normal free-sail scene")
	if not failures.is_empty():finish();return
	scene.activate_entry();scene.interface.visible=false;scene.minimap.visible=false
	await ticks(60)
	var packet:Dictionary=scene.runtime.snapshot().naval.environment
	var cp:Array=packet.worldClouds[0].worldPosition
	var center:=Vector3(cp[0],cp[1],cp[2])
	var opaque:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(140,180,100);opaque.mesh=box
	var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_color=Color(.8,.06,.5);opaque.material_override=material
	scene.add_child(opaque);opaque.visible=false
	var retained:=var_to_bytes(scene.runtime.snapshot())
	for angle:String in ["low","horizon","overview"]:
		var focus:=Vector3(center.x,20.0,center.z)
		var height:float={"low":45.0,"horizon":110.0,"overview":200.0}[angle]
		var eye:=focus+Vector3(-500,height,700)
		scene.sea.set_camera_controller(func():scene.sea.camera.global_position=eye;scene.sea.camera.look_at(focus))
		await settle()
		var atmosphere:RefCounted=scene.sea.world.atmosphere
		var storm:Array=atmosphere._weather[0].meshes
		for r:Dictionary in storm:
			if not r.bakedShadow:check(r.material.render_priority>scene.sea.world.get_ocean().material_override.render_priority,"actual cloud draws after actual sea")
		opaque.global_position=eye.lerp(center+Vector3.UP*50,.5)
		var images:Dictionary={}
		var mirrors:Dictionary={}
		for variant:String in ["baseline","production","no-storm","occluded","occluded-no-storm"]:
			opaque.visible=variant.begins_with("occluded")
			for r:Dictionary in storm:
				if r.bakedShadow:continue
				r.material.render_priority=0 if variant=="baseline" else 2
				r.node.visible=not variant.ends_with("no-storm")
			images[variant]=await save_frame(angle+"-"+variant)
			if angle=="low" and variant in ["production","no-storm"]:
				var reflection:SubViewport=scene.sea.world.get_ocean()._reference_renderer._reflection
				var mirror:Image=reflection.get_texture().get_image()
				mirrors[variant]=mirror
				check(mirror.save_png(output+"/mirror-"+variant+".png")==OK,"mirror image")
		var roi:=Rect2i(490,200,320,230)
		var selected:=changed_pixels(images.production,images["no-storm"],roi)
		var old:=changed_pixels(images.baseline,images["no-storm"],roi)
		var blocked:=changed_pixels(images.occluded,images["occluded-no-storm"],Rect2i(540,240,200,150))
		check(selected>800,"whole cloud visible against sky/sea "+angle)
		if angle=="overview":check(old<selected*.1,"baseline reproduces ocean covering world cloud")
		if angle=="horizon":check(old<selected*.95,"baseline reproduces partial horizon cut")
		if angle=="low":check(abs(old-selected)<selected*.1,"low sky view preserved")
		check(blocked==0,"opaque foreground still occludes cloud "+angle)
		pixel_metrics.append({"angle":angle,"baseline_cloud_pixels":old,"production_cloud_pixels":selected,"occluded_difference_pixels":blocked})
		if angle=="low":
			var n:=changed_pixels(mirrors.production,mirrors["no-storm"],Rect2i(Vector2i.ZERO,mirrors.production.get_size()))
			check(n>100,"actual reflection contains world cloud")
			pixel_metrics[-1].mirror_cloud_pixels=n
		check(var_to_bytes(scene.runtime.snapshot())==retained,"camera/material comparisons never advance weather")
		for r:Dictionary in storm:
			if not r.bakedShadow:r.node.visible=true;r.material.render_priority=2
		opaque.visible=false
	opaque.free()
	await ticks(120)
	var moved:Dictionary=scene.runtime.snapshot().naval.environment
	check(moved.worldClouds[0].worldPosition!=packet.worldClouds[0].worldPosition,"cloud moves in world while camera stays fixed")
	await save_frame("moving-3s")
	var before:=var_to_bytes(scene.runtime.snapshot())
	scene.sea.apply_settings({"quality":"high"})
	await settle();await save_frame("quality-high-paused")
	check(var_to_bytes(scene.runtime.snapshot())==before,"rebuild does not advance weather")
	for group:Array in scene.sea.world.atmosphere._clouds:
		for r:Dictionary in group:check(r.material.render_priority==2,"sky rebuilt with cloud priority")
	for instance:Dictionary in scene.sea.world.atmosphere._weather:
		for r:Dictionary in instance.meshes:check(r.material.render_priority==(0 if r.bakedShadow else 2),"world cloud/shadow separation survives rebuild")
	check(hashes()==frozen,"source frozen")
	var file:=FileAccess.open(output+"/COMPOSITION_VERIFY.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"valid":failures.is_empty(),"failures":failures,"captures":evidence,"metrics":pixel_metrics,"sources":frozen,"scope":"Actual normal scene; fixed t=1s camera and material counterfactuals. Magenta box is an explicitly synthetic opaque occlusion fixture. Two extra accepted frames cover movement and quality rebuild."},"\t"));file.close()
	finish()
