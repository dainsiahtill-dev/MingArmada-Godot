extends SceneTree
const Main = preload("res://game/scenes/main/main_scene.tscn")
var output := "res://docs/research/evidence/laboratory-environment-2026-10-14/production"
var failures: Array = []
var captures: Array = []
func _initialize() -> void: run.call_deferred()
func frames(n: int) -> void:
	for _i in n: await process_frame
func check(ok: bool,why: String) -> void:
	if not ok: failures.append(why); printerr("FAIL ",why)
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size=Vector2i(1600,1000); root.content_scale_size=root.size
	var main: Node=Main.instantiate();root.add_child(main);await frames(4)
	var button: Button=main.menu.find_child("fidelity-island",true,false)
	check(button!=null,"existing ordinary shared-world preview entry")
	button.pressed.emit()
	for _i in 120:
		await process_frame
		if is_instance_valid(main.current_scene):break
	var scene: Control=main.current_scene
	check(is_instance_valid(scene) and scene.startup_receipt.ok,"shared production island/world ready")
	scene.paused=true;scene.set_process(false);scene.seconds=24.0
	var original_controller: Callable=scene._update_camera
	var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/research/evidence/laboratory-environment-2026-10-14/candidate/shore-edge-width-35.png.json"))
	var values: Array=source.demo.camera_transform
	var pose:=Transform3D(Basis(Vector3(values[0],values[1],values[2]),Vector3(values[4],values[5],values[6]),Vector3(values[8],values[9],values[10])),Vector3(values[12],values[13],values[14]))
	var ocean: MeshInstance3D=scene.world._ocean
	var material: ShaderMaterial=ocean.material_override
	check(material.shader.code.contains("shore_edge_feather_m : hint_range(0.0,1.0) = 0.6"),"actual shared production shader enables accepted default")
	for mode: String in ["wide","edge"]:
		if mode=="edge":scene.sea.set_camera_controller(func():scene.camera.transform=pose)
		else:scene.sea.set_camera_controller(original_controller)
		scene._render();await frames(4)
		for width: float in [0.0,0.6]:
			material.set_shader_parameter("shore_edge_feather_m",width);scene._render();await frames(3);await RenderingServer.frame_post_draw
			var name: String="production-%s-w%02d"%[mode,int(width*100)]
			var image: Image=scene.view.get_texture().get_image()
			check(image.save_png(output+"/"+name+".png")==OK,"production frame "+name)
			captures.append({"image":name+".png","width":width,"sha256":FileAccess.get_sha256(output+"/"+name+".png"),"state":scene.inspection_snapshot(),"opaque_objects":"Production NaturalWorld terrain, vegetation, rocks, props, pier; retained ship and 3D crew. No diagnostic material overrides."})
	scene.main_menu_requested.emit();await frames(4)
	check(main.current_scene==null and main.menu.is_visible_in_tree(),"shared world returns through actual owner")
	var proof: Dictionary={"valid":failures.is_empty(),"failures":failures,"captures":captures,"shader_sha256":FileAccess.get_sha256("res://modules/scene_engine/ocean/reference_game_water.gdshader"),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"scope":"Existing ordinary main-menu shared game-world preview with production objects and water, same-time width A/B and menu return. Not full sailing gameplay, arbitrary coast coverage or transparent effect occlusion certification."}
	var file:=FileAccess.open(output+"/GPU_VERIFY.json",FileAccess.WRITE);file.store_string(JSON.stringify(proof,"\t"));file.close()
	main.free();await frames(2);print("SHORE_EDGE_PRODUCTION captures=",captures.size()," failures=",failures.size());quit(0 if failures.is_empty() else 1)
