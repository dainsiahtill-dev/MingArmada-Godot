extends "res://tools/capture-fidelity-island.gd"
## Same paused ordinary-entry snapshot and actual sun; rendering-only factors.
var rows:Array=[]
func _run()->void:
	output=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	if output.is_empty() or DirAccess.dir_exists_absolute(output) or DisplayServer.get_name()=="headless":quit(1);return
	DirAccess.make_dir_recursive_absolute(output);output_owned=true;root.size=Vector2i(1600,900)
	main=Main.new();main.router=Router.new({"mingqi_storage":MemorySlot.new(),"legacy_storage":MemorySlot.new(),"settings_storage":Settings.new("user://verification/shadow-no-write.json")});root.add_child(main)
	await process_frame;seed(1661);main.menu.find_child("sail",true,false).pressed.emit()
	if not await _await_scene("sail"):quit(1);return
	var game:Node=main.current_scene;game.runtime.set_pause("player",true);game.set_process(false);game.set_physics_process(false)
	var sea:Node3D=game.sea
	var native:Dictionary=game.runtime.snapshot().naval
	var model:Node3D=sea.ships[native.playerId].get_model()
	var nodes:Array=[]
	for node:Node in model.find_children("*","MeshInstance3D",true,false):
		if node.get_meta("target_rigid_shadow_caster",false):nodes.append(node)
	var camera_before:Transform3D=sea.camera.transform
	for mode:String in ["visible","authored","native_maps","hull_only","deck_only","masts_only"]:
		sea._rigid_casters.dispose()
		for node:MeshInstance3D in nodes:
			node.set_meta("target_rigid_shadow_caster",mode!="native_maps")
			if node.has_meta("target_shadow_geometry"):node.remove_meta("target_shadow_geometry")
			if mode=="authored":node.set_meta("target_shadow_geometry",node.get_parent().get_node("shadow_"+str(node.name)).mesh)
			if mode.ends_with("_only"):
				node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				node.set_meta("target_rigid_shadow_caster",(node.name=="hull" if mode=="hull_only" else node.name=="deck" if mode=="deck_only" else str(node.name).begins_with("mast_timber_")))
		sea.camera.transform=camera_before
		for frame in 4:sea._apply_source_shadows(native);await process_frame;await RenderingServer.frame_post_draw
		var path:=output.path_join(mode+".png");root.get_texture().get_image().save_png(path)
		rows.append({"mode":mode,"image":path,"sha256":FileAccess.get_sha256(path),"sunBasis":str(sea._sun.global_basis),"worldLight":str(-sea._sun.global_basis.z),"state":native,"shadow":sea.source_shadow_status()})
	var file:=FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"scope":"Frozen ordinary-entry rendering diagnostic, no gameplay/FPS claim. *_only explicitly suppress other rigid native shadows; native_maps restores full detail native shadows.","gpu":RenderingServer.get_video_adapter_name(),"rows":rows},"\t"));file.close()
	main.free();main=null;await process_frame;print("HERO_NATIVE_SHADOW_DIAGNOSTIC frames=6 failures=",failures);quit(1 if failures else 0)
