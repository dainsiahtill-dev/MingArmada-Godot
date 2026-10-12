extends SceneTree
const Scene=preload("res://game/scenes/natural_island/natural_island_prototype.gd")
var output:="res://docs/migration/evidence/natural-island/native-v1"
var scene: Control
var captures: Array=[]
var failures:=0
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	if DisplayServer.get_name()=="headless" or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output)):
		printerr("fresh native GPU evidence directory required"); quit(1); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size=Vector2i(1600,900); root.title="海上明旗 · 自然海岛实拍"
	scene=Scene.new(); root.add_child(scene); await process_frame
	if not scene.ready_receipt.get("ok",false): _finish(); return
	scene.paused=true; scene.seconds=12.0
	await _capture("natural-1661-forest")
	scene.forest_visible=false; await _capture("natural-1661-terrain")
	scene.forest_visible=true; scene.focus=Vector3(0,17,0); scene.orbit={"yaw":-0.40,"elevation":0.66,"distance":530.0}
	await _capture("natural-1661-close")
	scene.focus=Vector3(30,3,-150); scene.orbit={"yaw":-0.30,"elevation":0.62,"distance":340.0}
	await _capture("natural-shore-12")
	scene.seconds=13.0; await _capture("natural-shore-13")
	for seed_number in [1662,1663]:
		scene.seed_value=seed_number; scene._clear_world(); scene._build_world(); scene.seconds=12.0
		scene.focus=Vector3(0,12,0); scene.orbit={"yaw":-0.38,"elevation":0.69,"distance":850.0}
		await _capture("natural-%d-forest"%seed_number)
	_finish()
func _capture(label: String) -> void:
	if not scene.ready_receipt.get("ok",false): failures+=1; return
	scene._render(); for frame in 5: await process_frame
	await RenderingServer.frame_post_draw
	var picture: Image=root.get_texture().get_image()
	var path: String=output+"/"+label+".png"
	if picture==null or picture.is_empty() or picture.save_png(path)!=OK: failures+=1; return
	var info:={"label":label,"imageSha256":FileAccess.get_sha256(path),"gpu":RenderingServer.get_video_adapter_name(),"renderingMethod":RenderingServer.get_current_rendering_method(),"viewport":[picture.get_width(),picture.get_height()],"snapshot":scene.inspect(),"scope":"Actual Godot natural-island visual baseline; no original-game-frame, performance, or formal campaign acceptance claim"}
	var file:=FileAccess.open(path.get_basename()+".json",FileAccess.WRITE)
	if file==null: failures+=1; return
	file.store_string(JSON.stringify(info,"\t")); file.close(); captures.append(info)
	print("NATURAL_ISLAND_CAPTURE image=",label)
func _finish() -> void:
	if captures.is_empty(): failures+=1
	var file:=FileAccess.open(output+"/capture-result.json",FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify({"captures":captures,"failures":failures},"\t")); file.close()
	if is_instance_valid(scene): scene.free()
	print("NATURAL_ISLAND_NATIVE_CAPTURE captures=",captures.size()," failures=",failures)
	quit(1 if failures else 0)
