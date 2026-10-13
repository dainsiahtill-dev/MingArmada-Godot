extends SceneTree
var assertions:=0
var failures:=0
func check(ok:bool,message:String)->void:
	assertions+=1
	if not ok: failures+=1;printerr("FAIL: ",message)
func _initialize()->void:_run.call_deferred()
func _water(_x:float,_z:float,_time:float)->float:return 0.25
func _run()->void:
	var script=load("res://modules/scene_engine/water/source_froth.gd") if FileAccess.file_exists("res://modules/scene_engine/water/source_froth.gd") else null
	check(script!=null,"authored bow and nine sidefroth resource owner exists")
	if script:
		var parent:=Node3D.new();root.add_child(parent)
		for family in 9:
			var froth=script.new();var result:Dictionary=froth.configure(parent,family,1)
			check(result.get("ok",false),"source family loads "+str(family))
			froth.apply_snapshot({"sourcePosition":[100,100,0],"sourceBowPosition":[110,100,0],"modelScale":0.1,"sourceToWorld":0.01,"controllerAppTime":0.0,"sourceHeading":0.0,"enabled":true},0.0,_water,Callable())
			var before:Dictionary=froth.diagnostics()
			check(before.authored_meshes==2 and before.particle_systems==4,"one original bow mesh, one side mesh and four independent pools")
			var rendered_side:=false
			for node:Node in froth.get("_container").get_children():
				if not node is MeshInstance3D or not str(node.name).begins_with("side_"):continue
				rendered_side=true
				var arrays:Array=node.mesh.surface_get_arrays(0)
				var original:Dictionary=script.asset("fx_ship_sidefroth_"+script.FAMILIES[family]+".nif")
				for block:Dictionary in original.blocks:
					if block.type not in ["NiTriShapeData","NiTriStripsData"]:continue
					check(arrays[Mesh.ARRAY_VERTEX].size()==int(block.fields.num_vertices) and arrays[Mesh.ARRAY_INDEX].size()==block.effective_triangles.size()*3,"full original side topology reaches production mesh")
				for vertex:Vector3 in arrays[Mesh.ARRAY_VERTEX]:check(vertex.is_finite() and absf(vertex.y-0.35)<0.00001,"declared water-fit preserves finite authored horizontal footprint")
				var texture:Texture2D=node.material_override.get_shader_parameter("source_texture")
				check(texture!=null and texture.get_image().get_mipmap_count()>0,"source froth binds original compressed DDS mip chain")
			check(rendered_side,"authored side resource has a visible production mesh carrier")
			froth.apply_snapshot({"sourcePosition":[100,100,0],"sourceBowPosition":[110,100,0],"modelScale":0.1,"sourceToWorld":0.01,"controllerAppTime":0.25,"sourceHeading":0.0,"enabled":true},0.25,_water,Callable())
			var after:Dictionary=froth.diagnostics()
			check(after.native_births>0,"source bow emitters advance native pools")
			check(after.side_uv!=before.side_uv,"source side texture controller scrolls")
			check(after.native_equivalent==false and after.adaptations.has("water_surface_fit"),"Godot water-fit and unresolved lifecycle remain explicit")
			froth.dispose()
		parent.free()
	print("SOURCE_FROTH_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
