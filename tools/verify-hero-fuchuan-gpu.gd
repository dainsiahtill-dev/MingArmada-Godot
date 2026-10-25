extends SceneTree
const Experiment=preload("res://game/research/demos/hero_fuchuan_experiment.gd")
var output:="res://docs/production/hero-fuchuan-2026-10-25/gpu-independent-v1"
var continuous:=""
var model:="hero"
func _source_hashes()->Dictionary:
	var hashes:Dictionary={}
	for path in ["res://tools/verify-hero-fuchuan-gpu.gd","res://game/research/demos/hero_fuchuan_experiment.gd","res://modules/scene_engine/assets/hero_ship_provider.gd","res://tools/blender/build_hero_fuchuan_v3.py"]:hashes[path]=FileAccess.get_sha256(path)
	return hashes
func _initialize()->void:run.call_deferred()
func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg.begins_with("--continuous="):continuous=arg.trim_prefix("--continuous=")
		if arg.begins_with("--model="):model=arg.trim_prefix("--model=")
	if DirAccess.dir_exists_absolute(output) or (not continuous.is_empty() and DirAccess.dir_exists_absolute(continuous)):
		printerr("fresh output directories required");quit(1);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	if not continuous.is_empty():DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(continuous))
	root.size=Vector2i(1280,900)
	var demo:=Experiment.new();root.add_child(demo);demo.configure({"animated":false,"model":model})
	var hashes:=_source_hashes()
	var source_path:String=demo._ship.get_model().get_meta("source_path","")
	var asset_hash:=FileAccess.get_sha256(source_path)
	var initial:=demo.inspection_snapshot()
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("full-sail.png"))
	demo.orbit_camera(PI,0)
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("reverse-light.png"))
	demo.orbit_camera(-PI,0)
	var detail_frames:Array=[]
	var camera:Camera3D=demo._camera
	var camera_before:=camera.transform
	for view:Dictionary in [{"name":"stern-deck-detail","position":Vector3(-13,9,12),"target":Vector3(-7,3.7,0)},{"name":"hull-guns-detail","position":Vector3(1,4.5,12),"target":Vector3(1,1.5,0)},{"name":"cloth-detail","position":Vector3(0,16,12),"target":Vector3(0,14,0)}]:
		camera.position=view.position;camera.look_at(view.target)
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(view.name+".png"))
		detail_frames.append({"image":view.name+".png","position":view.position,"target":view.target,"time":demo.inspection_snapshot().time})
	camera.transform=camera_before
	demo.set_parameter("animated",true)
	var states:Array=[]
	var frame_hashes:Array=[]
	for i in range(257):
		if i>0:demo.advance(1.0/32.0)
		await process_frame
		states.append(demo.inspection_snapshot())
		if not continuous.is_empty():
			await RenderingServer.frame_post_draw
			var raw_path:=continuous.path_join("frame-%04d.png"%i)
			root.get_texture().get_image().save_png(raw_path)
			frame_hashes.append({"frame":i,"time":demo.inspection_snapshot().time,"path":raw_path,"sha256":FileAccess.get_sha256(raw_path)})
		if i%64==0:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("sequence-%03d.png"%i))
	demo.set_paused(true)
	var before:=demo.inspection_snapshot();demo.advance(1)
	var pause_ok:=before==demo.inspection_snapshot()
	var damage_frames:Array=[]
	for health:float in [80.0,60.0,30.0]:
		var damage_state:Dictionary=demo.inspection_snapshot().snapshot.duplicate(true)
		damage_state.sail=health;damage_state.sailDeployment=1.0;damage_state.sailAngle=0.0
		demo._ship.apply_snapshot(damage_state,{"direction":{"x":1,"y":0},"speed":14},0)
		await process_frame;await RenderingServer.frame_post_draw
		var filename:="sail-health-%d.png"%int(health)
		root.get_texture().get_image().save_png(output.path_join(filename))
		damage_frames.append({"image":filename,"snapshot":damage_state,"scope":"controlled intermediate cloth damage"})
	var reset:=demo.reset_experiment({"animated":false,"paused":false})
	var reset_ok:bool=reset.ok and demo.inspection_snapshot()==initial
	var source_ok:bool=hashes==_source_hashes() and asset_hash==FileAccess.get_sha256(source_path)
	var file:=FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"scope":"independent GPU rig; automated snapshot sequence, not native gameplay","model":model,"sourcePath":source_path,"assetSha256":asset_hash,"sourceSha256":hashes,"sourcesUnchanged":source_ok,"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"engine":Engine.get_version_info(),"fixedStep":1.0/32.0,"frames":states,"continuousFrames":frame_hashes,"damageFrames":damage_frames,"detailFrames":detail_frames,"pauseUnchanged":pause_ok,"resetInitialSnapshotEqual":reset_ok},"\t"));file.close()
	demo.dispose();demo.free();await process_frame
	print("HERO_FUCHUAN_GPU_CHECK frames=257 failures=",0 if pause_ok and reset_ok and source_ok else 1)
	quit(0 if pause_ok and reset_ok and source_ok else 1)
