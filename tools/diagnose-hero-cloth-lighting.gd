extends SceneTree
const Experiment=preload("res://game/research/demos/hero_fuchuan_experiment.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
	var output:="res://docs/production/hero-fuchuan-2026-10-26-art/cloth-lighting-diagnostic-r3"
	var wrap:=OS.get_cmdline_user_args().has("--wrap")
	if wrap:output+="-wrap"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output));root.size=Vector2i(1280,900)
	var demo:=Experiment.new();root.add_child(demo);demo.configure({"model":"art","animated":false})
	var sails:Array=[];var materials:Array=[];var records:Array=[]
	for model:Node3D in demo._ship.get("_models"):
		for node:MeshInstance3D in model.find_children("sail_*","MeshInstance3D",true,false):
			sails.append(node)
			for surface in node.mesh.get_surface_count():
				var source:=node.mesh.surface_get_material(surface)
				if source.resource_name=="canvas":materials.append({"node":node,"surface":surface,"source":source,"active":node.get_active_material(surface)})
	for shading:String in (["production","source_wrap"] if wrap else ["production","source"]):
		for item:Dictionary in materials:
			var chosen:Material=item.active
			if shading=="source":chosen=item.source
			if shading=="source_wrap":
				chosen=item.source.duplicate();chosen.diffuse_mode=BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
			item.node.set_surface_override_material(item.surface,chosen)
		for weight:float in [-1.0,0.0,1.0]:
			for sail:MeshInstance3D in sails:sail.set_blend_shape_value(1,weight)
			for reverse in [false,true]:
				if reverse:demo.orbit_camera(PI,0)
				await process_frame;await RenderingServer.frame_post_draw
				var file:="%s-inflate%d-%s.png"%[shading,int(weight),"reverse" if reverse else "front"]
				root.get_texture().get_image().save_png(output.path_join(file))
				records.append({"file":file,"shading":shading,"forcedInflation":weight,"state":demo.inspection_snapshot()})
				if reverse:demo.orbit_camera(-PI,0)
	var file:=FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"scope":"same accepted snapshot, forced inflation and source-vs-production material as explicit diagnostics","gpu":RenderingServer.get_video_adapter_name(),"captures":records},"\t"));file.close()
	demo.dispose();demo.free();print("HERO_CLOTH_LIGHTING_DIAGNOSTIC captures=12");quit()
