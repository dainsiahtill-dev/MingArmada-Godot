extends SceneTree
const Demo=preload("res://game/research/demos/hull_contact_experiment.gd")
const Types=preload("res://modules/contracts/physics_types.gd")
var output:=""
var failures:Array=[]
var captures:Array=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message);printerr("FAIL: ",message)
func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	check(DisplayServer.get_name()!="headless","actual GPU")
	check(not output.is_empty() and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output)),"fresh output")
	if not failures.is_empty():finish();return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size=Vector2i(1280,720);root.content_scale_size=root.size;root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	root.unresizable=true;root.unfocusable=true;root.gui_disable_input=true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for kind:String in Types.SHIP_SPECS:
		var demo:=Demo.new();demo.configure({"kind":kind,"scenario":"cruise","contact_enabled":true});root.add_child(demo)
		await process_frame
		for phase in 4:
			for tick in 96:demo.advance(1.0/32.0)
			var s:Dictionary=demo.inspection_snapshot()
			var model:Node3D=demo._ship.get_model()
			var focus:Vector3=model.global_position+Vector3.UP
			var length:float=Types.ship_spec(kind).length
			var right:Vector3=model.global_basis.x.normalized();right.y=0
			var forward:Vector3=model.global_basis.z.normalized();forward.y=0
			demo._camera.global_position=focus+right*length*.95+forward*length*.12+Vector3.UP*length*.28
			demo._camera.look_at(focus)
			demo._ocean.set_simulation_time(s.time)
			for frame in 3:await process_frame
			await RenderingServer.frame_post_draw
			var min_clearance:=INF
			for node:Node in model.find_children("*","MeshInstance3D",true,false):
				if str(node.get_meta("damage_surface",""))!="hull":continue
				for surface in node.mesh.get_surface_count():
					for local:Vector3 in node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
						var world:Vector3=node.global_transform*local
						min_clearance=minf(min_clearance,world.y-demo._water(world.x,world.z,s.time))
			check(min_clearance<-.25,"actual hull remains immersed "+kind+" "+str(s.time))
			var label:="%s-%02d"%[kind,phase]
			var path:=output+"/"+label+".png"
			var img:Image=root.get_texture().get_image();check(img.save_png(path)==OK,"capture "+label)
			captures.append({"image":label+".png","sha256":FileAccess.get_sha256(path),"kind":kind,"time":s.time,"ship":s.native_ship,"buoyancy":s.buoyancy,"minimum_hull_clearance_m":min_clearance,"camera":str(demo._camera.global_transform),"viewport":str(img.get_size())})
		demo.dispose();demo.free();await process_frame
	finish()
func finish()->void:
	if not output.is_empty():
		var file:=FileAccess.open(output+"/GPU_VERIFY.json",FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify({"valid":failures.is_empty() and captures.size()==24,"failures":failures,"captures":captures,"gpu":RenderingServer.get_video_adapter_name(),"scope":"Existing isolated hull-contact lab; unchanged ocean shader, actual ship/crew, accepted 120Hz runtime. Camera widened only for whole-hull inspection. Not full-game FPS.","sources":{"physics":FileAccess.get_sha256("res://modules/physics_engine/ships/ship_dynamics.gd"),"driver":FileAccess.get_sha256("res://tools/verify-buoyancy-lab-gpu.gd")}},"\t"));file.close()
	print("BUOYANCY_LAB_GPU captures=",captures.size()," failures=",failures.size());quit(1 if not failures.is_empty() else 0)
