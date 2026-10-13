extends "res://tools/verify-wake-production-gpu.gd"
## Natural production loop at the player's low-quality/native-window setting.
## Frozen same-frame hardware-depth counterfactual, without changing inputs.
func proof(label:String)->void:
	await capture(label)
	var actor:Dictionary=scene.sea.wakes._source_wakes._actors.player
	var native:Dictionary=scene.runtime.snapshot().naval
	var file:=FileAccess.open(output+"/"+label+"-geometry.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"geometry":actor.geometry,"acceptedTime":native.time,"visual":native.ships[0].visual,"quality":scene.sea._settings.quality,"oceanShader":scene.sea.world.get_ocean().material_override.shader.resource_path},"\t"));file.close()
func run()->void:
	phase="final-low";output="res://docs/migration/evidence/wake-regression-2026-10-14/"+phase+"/gpu"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size=Vector2i(1069,600);root.content_scale_size=Vector2i(1600,900)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	scene=Practice.new();scene.startup_options={"mode":"sail","staged":true};scene.settings_storage=Settings.new("user://tests/wake-occlusion-%s.json"%OS.get_process_id());root.add_child(scene);await frames(2)
	check(scene.startup_receipt.get("ok",false),"production startup")
	if not scene.startup_receipt.get("ok",false):quit(1);return
	scene.activate_entry();scene.sea.apply_settings({"quality":"low"});scene.runtime.set_pause("blur",false)
	var turned:=false;var stages:=[4.0,12.0,24.0,40.0,60.0];var stage:=0
	while stage<stages.size():
		await process_frame;scene.runtime.set_pause("blur",false)
		var native:Dictionary=scene.runtime.snapshot().naval
		if not turned and native.time>=6.0:
			var projected:Dictionary=scene._mouse_course.project(scene.sea.camera,Vector2(1202.0,610.0),scene.heights.sample_height)
			check(projected.get("ok",false),"formal viewport mouse-course projection")
			if projected.get("ok",false):scene.runtime.command({"type":"mouse-course","point":projected.point})
			turned=true
		if native.time>=stages[stage]:await proof("live-%02d"%int(stages[stage]));stage+=1
	scene.set_process(false);scene.set_physics_process(false);scene._present(0.0)
	await proof("01-fixed")
	var originals:Dictionary={}
	for id:String in scene.sea.wakes._source_wakes._actors:
		var actor:Dictionary=scene.sea.wakes._source_wakes._actors[id];var node:MeshInstance3D=actor.surface.nodes.SceneStrip;originals[id]=node.material_override
		var material:ShaderMaterial=node.material_override.duplicate();var shader:=Shader.new();shader.code=material.shader.code.replace("depth_test_disabled,","");material.shader=shader;material.set_shader_parameter("soft_depth_distance",0.0);node.material_override=material
	# Diagnostic material intentionally does not pass the final shader checks.
	var saved_phase:=phase;phase="before";await proof("02-hardware-depth-original");phase=saved_phase
	for id:String in originals:scene.sea.wakes._source_wakes._actors[id].surface.nodes.SceneStrip.material_override=originals[id]
	await proof("03-fixed-restored")
	var frozen:Array=records.slice(records.size()-3)
	check(frozen[0].acceptedTime==frozen[1].acceptedTime and frozen[1].acceptedTime==frozen[2].acceptedTime,"same frozen accepted time")
	check(frozen[0].position==frozen[1].position and frozen[1].position==frozen[2].position,"same frozen ship pose")
	var file:=FileAccess.open(output+"/VERIFICATION.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"captures":records,"scope":"Natural low-quality production loop; frozen before/after depth counterfactual. No original DX9 pixel parity or sustained FPS claim."},"\t"));file.close()
	var playbacks:Array[WeakRef]=AudioCleanup.stop_players(scene);scene.free();scene=null;await frames(4);await AudioCleanup.wait_for_release(self,playbacks)
	print("PRODUCTION_WAKE_OCCLUSION_GPU failures=",failures.size()," captures=",records.size());quit(0 if failures.is_empty() else 1)
