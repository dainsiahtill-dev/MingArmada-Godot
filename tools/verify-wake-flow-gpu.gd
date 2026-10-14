extends SceneTree
## Real GPU sequence from the registered independent experiment. Never a live FPS proof.
const Experiment = preload("res://game/research/demos/wake_flow_experiment.gd")
const STEP := 1.0 / 32.0
var output := ""
var output_owned := false
var scenario := "cruise"
var camera_mode := "high"
var ship_kind := "fuchuan"
var observer_zoom := 1.0
var candidate := false
var sequence := false
var failures: Array[String] = []
var captures: Array = []
var demo: Node3D
var source_hashes: Dictionary = {}
const SOURCES := ["game/research/demos/wake_flow_experiment.gd", "game/research/demos/hull_contact_experiment.gd", "game/presentation/ships/ship_view.gd", "modules/scene_engine/water/wake_flow.gd", "modules/scene_engine/water/wake_flow.gdshader", "modules/scene_engine/water/source_wake_renderer.gd", "modules/scene_engine/ocean/reference_game_water.gdshader", "game/presentation/world/source_water_packet.gd"]
func _initialize() -> void: run.call_deferred()
func check(ok: bool, reason: String) -> void:
	if not ok: failures.append(reason); printerr("FAIL wake-flow GPU: ", reason)
func frames(n: int) -> void:
	for _i in n: await process_frame
func hashes() -> Dictionary:
	var result := {}
	for path: String in SOURCES:
		result[path] = FileAccess.get_sha256("res://"+path) if FileAccess.file_exists("res://"+path) else "missing"
	return result
func capture(tick: int) -> void:
	await RenderingServer.frame_post_draw
	var info: Dictionary = demo.inspection_snapshot()
	var file_name := "t%04d.png" % tick
	var img := root.get_texture().get_image()
	check(img.save_png(output+"/"+file_name) == OK,"save frame "+file_name)
	var frame := {"image":file_name,"sha256":FileAccess.get_sha256(output+"/"+file_name),"tick":tick,"time":info.time,"camera_transform":info.get("camera_transform",[]),"camera_projection":info.get("camera_projection",[]),"flow":info.get("flow",info.get("wake_flow",{})),"tail":info.get("tail",{}),"speed":info.get("target_trail",{}).get("speed",null)}
	captures.append(frame)
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		elif arg.begins_with("--scenario="): scenario = arg.trim_prefix("--scenario=")
		elif arg.begins_with("--camera="): camera_mode = arg.trim_prefix("--camera=")
		elif arg.begins_with("--kind="): ship_kind = arg.trim_prefix("--kind=")
		elif arg.begins_with("--zoom="): observer_zoom = float(arg.trim_prefix("--zoom="))
		elif arg == "--candidate": candidate = true
		elif arg == "--sequence": sequence = true
	check(not output.is_empty() and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output)),"new output directory required")
	if not failures.is_empty(): finish(); return
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))==OK,"create output directory")
	if not failures.is_empty(): finish(); return
	output_owned = true
	root.size = Vector2i(1200,760); root.content_scale_size = root.size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	source_hashes = hashes()
	demo = Experiment.new()
	var configured: Dictionary = demo.configure({"kind":ship_kind,"scenario":scenario,"camera_mode":camera_mode,"zoom":observer_zoom,"flow_enabled":candidate,"quality":"balanced"})
	check(configured.get("ok",false),"configuration accepted")
	root.add_child(demo); await frames(4)
	check(demo.inspection_snapshot().get("ready",false),"experiment ready")
	if not failures.is_empty(): finish(); return
	await capture(0)
	var ticks := 768 if scenario == "stop" else 512
	for tick in range(1,ticks+1):
		demo.advance(STEP)
		if tick%2 == 0: await frames(1)
		var keyframe := tick in [8,16,32,64,128,192,256,320,384,448,512,640,768]
		var clip_frame := sequence and tick>=256 and tick<=384 and tick%2==0
		if keyframe or clip_frame: await capture(tick)
	demo.set_paused(true)
	var frozen: Dictionary = demo.inspection_snapshot()
	demo.advance(1.0); demo.orbit_camera(0.0,0.0)
	check(demo.inspection_snapshot().tick == frozen.tick,"paused camera refresh preserves accepted tick")
	var expected_count := (14 if scenario=="stop" else 12) + (62 if sequence else 0)
	check(captures.size()==expected_count,"complete keyframe sequence: expected "+str(expected_count))
	check(hashes()==source_hashes,"source freeze held throughout capture")
	finish()
func finish() -> void:
	var final_info: Dictionary = demo.inspection_snapshot() if is_instance_valid(demo) else {}
	var result := {"valid":failures.is_empty(),"failures":failures,"scope":"Independent real GPU fixed-step sequence, real Ship/Crew/Ocean and SailingRuntime; no full-game FPS or original-game pixel parity claim.","scenario":scenario,"camera":camera_mode,"candidate":candidate,"sequence":sequence,"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"viewport":[1200,760],"sources":source_hashes,"captures":captures,"final":final_info}
	if output_owned:
		var file := FileAccess.open(output+"/GPU_VERIFY.json",FileAccess.WRITE)
		file.store_string(JSON.stringify(result,"\t"));file.close()
	if is_instance_valid(demo): demo.dispose();demo.free()
	await frames(2)
	print("WAKE_FLOW_GPU captures=",captures.size()," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
