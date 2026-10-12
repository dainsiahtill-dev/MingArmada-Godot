extends "res://tools/capture-fidelity-island.gd"
## Fresh native pixels to diagnose the current sea, with ordinary menu entry.
func _run() -> void:
	output = "res://docs/migration/evidence/fidelity-island/wave-review-v1"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if not check(DisplayServer.get_name() != "headless", "native GPU required"): _finish(); return
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output)):
		check(false,"fresh output required"); _finish(); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output)); output_owned = true
	root.size = Vector2i(1600,900)
	settings = Settings.new("user://verification/wave-review-no-write-%d.json"%OS.get_process_id())
	main = Main.new(); main.router = Router.new({"mingqi_storage":MemorySlot.new(),"legacy_storage":MemorySlot.new(),"settings_storage":settings}); root.add_child(main)
	await process_frame
	var button: Button = main.menu.find_child("fidelity-source",true,false)
	if not check(button != null and not button.disabled,"ordinary island menu entry"): _finish(); return
	button.pressed.emit()
	if not await _await_scene("fidelity-island"): _finish(); return
	var scene: Control = main.current_scene; scene.paused = true; scene.seconds = 12.0
	await _capture("godot-current-default",scene)
	scene.camera.position = Vector3(500,2600,6500); scene.camera.look_at(Vector3(900,0,2400),Vector3.UP)
	for phase in [12.0,12.35,12.7,13.05]:
		scene.seconds = phase
		await _capture("godot-shore-%s"%str(phase).replace(".","-"),scene)
	scene.camera.position = Vector3(0,1250,4100); scene.camera.look_at(Vector3(700,0,2300),Vector3.UP)
	await _capture("godot-water-close",scene)
	_finish()
