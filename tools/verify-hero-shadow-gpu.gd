extends SceneTree
## Frozen rig/camera comparison of exact production stencil seam in the lab.
const Experiment=preload("res://game/research/demos/hero_fuchuan_experiment.gd")
var output:=""
var failures:=0
var frames:Array=[]
var daylight:="studio"
var model:="art"
func check(ok:bool,message:String)->void:
	if not ok:failures+=1;printerr("FAIL hero shadow GPU: ",message)
func _initialize()->void:run.call_deferred()
func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg.begins_with("--daylight="):daylight=arg.trim_prefix("--daylight=")
		if arg.begins_with("--model="):model=arg.trim_prefix("--model=")
	if output.is_empty() or DirAccess.dir_exists_absolute(output) or DisplayServer.get_name()=="headless":
		printerr("fresh output and real GPU required");quit(1);return
	DirAccess.make_dir_recursive_absolute(output);root.size=Vector2i(1280,900)
	for mode:String in ["visible","authored"]:
		var demo:=Experiment.new();root.add_child(demo);demo.configure({"model":model,"animated":false,"paused":true,"shadows":mode,"daylight":daylight})
		for frame in 3:await process_frame;await RenderingServer.frame_post_draw
		check(demo.inspection_snapshot().time==0,"initially paused render readiness does not advance time: "+mode)
		for node:Node in demo._ship.get_model().find_children("*","MeshInstance3D",true,false):
			if node.get_meta("target_rigid_shadow_caster",false):check(node.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"paused handoff disables duplicate native rigid shadow: "+str(node.name))
		demo.set_paused(false)
		for tick in 65:
			if tick>0:demo.advance(1.0/32.0)
			demo._ship.rotation.y=float(tick)*.005
			demo.refresh_shadow_projection()
			await process_frame;await RenderingServer.frame_post_draw
			if tick in [0,32,64]:
				var path:=output.path_join("%s-%03d.png"%[mode,tick]);root.get_texture().get_image().save_png(path)
				frames.append({"mode":mode,"tick":tick,"image":path,"sha256":FileAccess.get_sha256(path),"state":demo.inspection_snapshot(),"shadow":demo.shadow_diagnostics()})
		var diagnostics:Dictionary=demo.shadow_diagnostics()
		check(diagnostics.renderer.gpu.initialized and diagnostics.renderer.gpu.error=="","real compositor initialized: "+mode)
		check(diagnostics.renderer.volumeCount==5 and diagnostics.renderer.errors.is_empty() and diagnostics.adapter.errors.is_empty(),"five valid shadow volumes: "+mode)
		demo.orbit_camera(PI,0)
		for frame in 3:demo.refresh_shadow_projection();await process_frame;await RenderingServer.frame_post_draw
		var reverse:=output.path_join(mode+"-reverse.png");root.get_texture().get_image().save_png(reverse)
		frames.append({"mode":mode,"tick":64,"image":reverse,"sha256":FileAccess.get_sha256(reverse),"state":demo.inspection_snapshot(),"shadow":demo.shadow_diagnostics()})
		var before:Dictionary=demo.inspection_snapshot();demo.set_paused(true);demo.advance(1)
		check(demo.inspection_snapshot().time==before.time,"pause preserves authority time: "+mode)
		demo.dispose();demo.free();await process_frame
	var file:=FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"scope":"Independent GPU hero-fuchuan; exact production stencil seam; 65 consecutive frames per factor plus reverse view, selected unedited captures. Not whole-game FPS.","model":model,"daylight":daylight,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":[1280,900],"fixedStep":1.0/32.0,"frames":frames,"failures":failures},"\t"));file.close()
	print("HERO_SHADOW_GPU_TESTS frames=130 failures=",failures);quit(1 if failures else 0)
