extends "res://tools/verify-interactive-wake-production-gpu.gd"
var observations:Array=[]
func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	check(not output.is_empty() and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output)),"fresh output")
	check(DisplayServer.get_name()!="headless","actual GPU")
	if not failures.is_empty():finish();return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output));output_owned=true;frozen=hashes()
	root.size=Vector2i(1280,800);root.content_scale_size=root.size;root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT;root.unresizable=true;root.unfocusable=true;root.gui_disable_input=true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	scene=Practice.new();scene.startup_options={"mode":"sail","staged":true};scene.settings_storage=Settings.new("user://tests/cloud-order-%d.json"%OS.get_process_id())
	root.add_child(scene);await process_frame;await process_frame
	scene.set_process(false);scene.set_physics_process(false);isolate_input(scene)
	check(scene.startup_receipt.get("ok",false),"actual practice")
	if not failures.is_empty():finish();return
	scene.activate_entry();scene.interface.visible=false;scene.minimap.visible=false
	await ticks(60)
	var atmosphere:RefCounted=scene.sea.world.atmosphere
	var packet:Dictionary=scene.runtime.snapshot().naval.environment
	var cp:Array=packet.worldClouds[0].worldPosition
	var center:=Vector3(cp[0],cp[1],cp[2])
	for angle:String in ["low","overview"]:
		var focus:=Vector3(center.x,20.0,center.z)
		var eye:=focus+Vector3(-500,45 if angle=="low" else 200,700)
		scene.sea.set_camera_controller(func():scene.sea.camera.global_position=eye;scene.sea.camera.look_at(focus))
		await settle()
		var meshes:Array=atmosphere._weather[0].meshes
		var geometry:Array=[]
		for r:Dictionary in meshes:
			var aabb:AABB=r.node.global_transform*r.node.mesh.get_aabb()
			geometry.append({"block":r.block,"shadow":r.bakedShadow,"position":str(r.node.global_position),"boundsMinY":aabb.position.y,"boundsMaxY":aabb.end.y,"depth":r.sourceDepthFlags,"alphaFlags":r.sourceAlphaFlags,"billboard":r.material.get_shader_parameter("source_billboard_enabled"),"shader":r.material.shader.code})
		for variant:String in ["baseline","sea-hidden","priority","raised"]:
			var ocean:MeshInstance3D=scene.sea.world.get_ocean()
			ocean.visible=variant!="sea-hidden"
			for r:Dictionary in meshes:
				if not r.bakedShadow:
					r.material.render_priority=1 if variant=="priority" else 0
					if variant=="raised":r.node.position.y+=80.0
			for frame in 3:await process_frame
			await RenderingServer.frame_post_draw
			var label:=angle+"-"+variant
			var img:Image=root.get_texture().get_image()
			check(img.save_png(output+"/"+label+".png")==OK,"save "+label)
			observations.append({"label":label,"image":label+".png","sha256":FileAccess.get_sha256(output+"/"+label+".png"),"time":packet.acceptedTime,"cloud":packet.worldClouds[0],"geometry":geometry,"camera":str(scene.sea.camera.global_transform)})
			if variant=="raised":
				for r:Dictionary in meshes:
					if not r.bakedShadow:r.node.position.y-=80.0
		scene.sea.world.get_ocean().visible=true
		for r:Dictionary in meshes:r.material.render_priority=0
	var file:=FileAccess.open(output+"/DIAGNOSIS.json",FileAccess.WRITE);file.store_string(JSON.stringify({"records":observations,"scope":"Same native scene, camera, time and world cloud. Single factor variants: hide ocean, priority after transparent ocean, raise cloud node (non-billboard geometry only).","failures":failures},"\t"));file.close()
	finish()
