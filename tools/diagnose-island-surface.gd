extends "res://tools/capture-fidelity-island.gd"
## Read-only GPU isolation of geometry versus water and shoreline presentation.
func _run() -> void:
	output="res://docs/migration/evidence/fidelity-island/terrain-isolation-v1"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	if not check(DisplayServer.get_name()!="headless","actual native GPU required"): _finish(); return
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output)):
		check(false,"fresh evidence directory required"); _finish(); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output)); output_owned=true
	root.size=Vector2i(1600,900)
	settings=Settings.new("user://verification/terrain-isolation-%d.json"%OS.get_process_id())
	main=Main.new(); main.router=Router.new({"mingqi_storage":MemorySlot.new(),"legacy_storage":MemorySlot.new(),"settings_storage":settings}); root.add_child(main)
	await process_frame
	main.menu.find_child("fidelity-island",true,false).pressed.emit()
	if not await _await_scene("fidelity-island"): _finish(); return
	var scene: Control=main.current_scene; scene.paused=true; scene.seconds=12.0
	scene.focus=Vector3(-460,8,-75); scene.orbit={"yaw":-0.28,"elevation":0.63,"distance":300.0}
	await _capture("composed",scene)
	scene.world.get_ocean().hide()
	for surf: Node3D in scene.world._fidelity_shores: surf.hide()
	if is_instance_valid(scene.world._shore_spray): scene.world._shore_spray.hide()
	await _capture("terrain-no-water",scene)
	for plant: Node3D in scene.world._fidelity_vegetation: plant.hide()
	await _capture("terrain-no-water-no-trees",scene)
	var flat:=StandardMaterial3D.new(); flat.albedo_color=Color("6b7b42"); flat.roughness=1.0
	for mesh: MeshInstance3D in scene.world.get_static_island_meshes(): mesh.material_override=flat
	await _capture("terrain-solid",scene)
	_finish()
