extends SceneTree
## Geometry-only aliasing diagnostic. Does not alter files, textures or authority.
const Demo=preload("res://game/research/demos/hero_fuchuan_experiment.gd")
var output:=""
func _initialize()->void:run.call_deferred()
func joint_mesh(source:Mesh,gap:float)->ArrayMesh:
	var result:=ArrayMesh.new();var step:=8.86/44.0
	for surface in source.get_surface_count():
		var arrays:=source.surface_get_arrays(surface);var points:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		if source.surface_get_material(surface).resource_name=="deck":
			for i in points.size():
				var p:Vector3=points[i]
				if p.y>4.1:continue
				for column in range(45):
					var line:float=-4.43+column*step
					if absf(p.x-(line+.008))<.0001:p.x-=.008-gap*.5;break
					if absf(p.x-(line-.008))<.0001:p.x+=.008-gap*.5;break
				points[i]=p
		arrays[Mesh.ARRAY_VERTEX]=points;result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		result.surface_set_material(surface,source.surface_get_material(surface))
	return result
func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	if output.is_empty() or DirAccess.dir_exists_absolute(output) or DisplayServer.get_name()=="headless":quit(1);return
	DirAccess.make_dir_recursive_absolute(output);root.size=Vector2i(1280,900)
	var demo:=Demo.new();root.add_child(demo);demo.configure({"model":"art_r6","animated":true});demo.advance(6);demo.set_paused(true)
	var deck:=demo._ship.get_model().find_child("deck",true,false) as MeshInstance3D
	var source:Mesh=deck.mesh;var rows:Array=[];var camera:Transform3D=demo._camera.transform
	for gap in [.016,.004,0.0]:
		deck.mesh=source if gap==.016 else joint_mesh(source,gap)
		demo._camera.transform=camera
		for frame in 3:await process_frame;await RenderingServer.frame_post_draw
		var name:="joints-%03dmm.png"%roundi(gap*1000)
		root.get_texture().get_image().save_png(output.path_join(name))
		rows.append({"gapMetres":gap,"image":name,"sha256":FileAccess.get_sha256(output.path_join(name)),"time":demo.inspection_snapshot().time})
	var f:=FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"scope":"Frozen r6-b at accepted6s; renderer-only joint-width mutation, no textures/authority/assets edited; not production or FPS proof.","gpu":RenderingServer.get_video_adapter_name(),"rows":rows},"\t"));f.close()
	demo.dispose();demo.free();await process_frame;print("HERO_DECK_JOINT_DIAGNOSTIC frames=3 failures=0");quit()
