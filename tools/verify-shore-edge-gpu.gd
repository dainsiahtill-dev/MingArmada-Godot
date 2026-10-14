extends SceneTree
const Lab = preload("res://game/research/laboratory.gd")
var output := "res://docs/research/evidence/laboratory-environment-2026-10-14/feather-study"
var lab: Control
var frames_saved: Array = []
var timings: Array = []
var failures: Array = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, why: String) -> void:
	if not ok: failures.append(why); printerr("FAIL ",why)
func frames(n: int) -> void:
	for _i in n: await process_frame
func capture(label: String) -> void:
	await frames(3)
	var receipt: Dictionary = await lab.save_experiment_frame(output+"/"+label+".png")
	check(receipt.ok,label)
	frames_saved.append({"image":label+".png","state":label+".png.json","sha256":FileAccess.get_sha256(output+"/"+label+".png")})
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(1600,1000); root.content_scale_size = root.size
	lab = Lab.new(); root.add_child(lab); await frames(3); lab.set_process(false)
	lab.select_topic("shore-surf")
	check(lab.start_demo({"paused":true,"camera_mode":"edge"}).ok,"shore fixture ready")
	for seconds: float in [0.0,0.5,2.0,8.0]:
		lab._demo.set_paused(false)
		while lab._demo.inspection_snapshot().tick < int(seconds*32): lab._demo.advance(1.0/32.0)
		lab._demo.set_paused(true)
		for mode: String in ["edge","close","low"]:
			lab._change_parameter("camera_mode","close" if mode == "low" else mode)
			if mode == "low":
				lab._demo._camera.position = lab._demo._focus+lab._demo._outward*45.0+Vector3.UP*9.0
				lab._demo._camera.look_at(lab._demo._focus); lab._demo.refresh_viewport()
			var before: Dictionary = lab._demo.inspection_snapshot()
			for width: float in [0.0,0.6]:
				lab._change_parameter("shore_edge_feather_m",width)
				check(lab._demo.inspection_snapshot().tick == before.tick,"same-time factor")
				await capture("%s-t%03d-w%02d" % [mode,int(seconds*32),int(width*100)])
	# Interleaved repeated paused draws; raw wall intervals, not GPU timestamps.
	lab._change_parameter("camera_mode","edge")
	await frames(40)
	for pair in 32:
		var widths: Array = [0.0,0.6] if pair%2 == 0 else [0.6,0.0]
		for width: float in widths:
			lab._change_parameter("shore_edge_feather_m",width)
			await RenderingServer.frame_post_draw
			var begin := Time.get_ticks_usec()
			await process_frame; await RenderingServer.frame_post_draw
			timings.append({"pair":pair,"width":width,"wall_ms":(Time.get_ticks_usec()-begin)/1000.0})
	var proof := {"valid":failures.is_empty(),"failures":failures,"frames":frames_saved,"timings":timings,"time":lab._demo.inspection_snapshot().time,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"shader_sha256":FileAccess.get_sha256("res://modules/scene_engine/ocean/reference_game_water.gdshader"),"helper_sha256":FileAccess.get_sha256("res://modules/scene_engine/ocean/shore_edge_coverage.gdshaderinc"),"scope":"Same Xiamen shore field, all foam enabled, fixed 32Hz time 0/.5/2/8s, edge/close/low camera. Low is an explicitly positioned diagnostic camera at focus+outward45m+up9m, actual matrix recorded. Paired 32 wall frame intervals after40 warm-up frames; no whole-game FPS or GPU-duration claim."}
	var file := FileAccess.open(output+"/GPU_VERIFY.json",FileAccess.WRITE); file.store_string(JSON.stringify(proof,"\t")); file.close()
	lab.free(); await frames(2)
	print("SHORE_EDGE_GPU frames=",frames_saved.size()," failures=",failures.size()); quit(0 if failures.is_empty() else 1)
