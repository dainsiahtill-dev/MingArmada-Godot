extends SceneTree
const Experiment=preload("res://game/research/demos/hero_fuchuan_experiment.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
	var output:="res://docs/production/hero-fuchuan-2026-10-26-art/cloth-shadow-diagnostic-r2"
	var caster_test:=OS.get_cmdline_user_args().has("--casters")
	if caster_test:output="res://docs/production/hero-fuchuan-2026-10-26-art/cloth-caster-diagnostic-r3"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output));root.size=Vector2i(1280,900)
	var demo:=Experiment.new();root.add_child(demo);demo.configure({"model":"art","animated":false})
	var sails:Array=[];var masts:Array=[]
	for model:Node3D in demo._ship.get("_models"):
		for node in model.find_children("sail_*","MeshInstance3D",true,false):sails.append(node)
		for node in model.find_children("mast_timber_*","MeshInstance3D",true,false):masts.append(node)
	var light:DirectionalLight3D
	for child in demo._world.get_children():
		if child is DirectionalLight3D:light=child
	var bias:=light.shadow_normal_bias;var results:Array=[]
	for mode:String in (["default","mast_off","light_off"] if caster_test else ["default","double","off","bias0"]):
		light.shadow_normal_bias=0.0 if mode=="bias0" else bias
		light.shadow_enabled=mode!="light_off"
		for mast:MeshInstance3D in masts:mast.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if mode=="mast_off" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for sail:MeshInstance3D in sails:sail.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED if mode=="double" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if mode=="off" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for reverse in [false,true]:
			if reverse:demo.orbit_camera(PI,0)
			await process_frame;await RenderingServer.frame_post_draw
			var file:=mode+("-reverse" if reverse else "-front")+".png"
			root.get_texture().get_image().save_png(output.path_join(file))
			results.append({"file":file,"mode":mode,"normalBias":light.shadow_normal_bias,"state":demo.inspection_snapshot()})
			if reverse:demo.orbit_camera(-PI,0)
	var file:=FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"scope":"single-factor cloth shadow diagnosis at identical accepted time; off is diagnostic only","gpu":RenderingServer.get_video_adapter_name(),"captures":results},"\t"));file.close()
	demo.dispose();demo.free();print("HERO_CLOTH_SHADOW_DIAGNOSTIC captures=",results.size());quit()
