extends SceneTree
## Actual runtime GLTF import, not editor metadata or a rendered-art claim.
const Library=preload("res://modules/scene_engine/assets/asset_library.gd")
const Damage=preload("res://game/presentation/ships/ship_damage.gd")
var assertions:=0
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,detail:String)->void:
	assertions+=1
	if not ok:failures.append(detail);printerr("FAIL: ",detail)

func run()->void:
	var library=Library.new()
	for lod in range(3):
		var old:Node3D=library.instantiate_model("res://assets/models/hero_fuchuan_v3_r9b/fuchuan-lod%d.glb"%lod)
		var candidate:Node3D=library.instantiate_model("res://assets/models/hero_fuchuan_v3_r11/fuchuan-lod%d.glb"%lod)
		check(old!=null and candidate!=null,"actual source-authoring import of both LOD%d assets"%lod)
		if old==null or candidate==null:continue
		old.set_meta("model_origin","blender_authored");candidate.set_meta("model_origin","blender_authored")
		for index in range(3):
			var prior:=old.find_child("sail_%d"%index,true,false) as MeshInstance3D
			var next:=candidate.find_child("sail_%d"%index,true,false) as MeshInstance3D
			check(prior!=null and next!=null,"both imports contain sail%d LOD%d"%[index,lod])
			if prior==null or next==null:continue
			var a:=prior.mesh as ArrayMesh;var b:=next.mesh as ArrayMesh
			check(a.get_surface_count()==b.get_surface_count() and a.get_blend_shape_count()==2 and b.get_blend_shape_count()==2,"surface count and two sail morphs preserved")
			var changed:=0
			for surface in range(a.get_surface_count()):
				var am=a.surface_get_material(surface);var bm=b.surface_get_material(surface)
				check(am is StandardMaterial3D and bm is StandardMaterial3D and am.resource_name==bm.resource_name,"imported material identity retained")
				if not am is StandardMaterial3D or not bm is StandardMaterial3D:continue
				var aa:=a.surface_get_arrays(surface);var ba:=b.surface_get_arrays(surface)
				for field:int in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_INDEX]:
					check(aa[field]==ba[field],"geometry, normals, UV and index unchanged on %s"%am.resource_name)
				check(a.surface_get_blend_shape_arrays(surface)==b.surface_get_blend_shape_arrays(surface),"morph arrays unchanged on %s"%am.resource_name)
				var ac:PackedColorArray=aa[Mesh.ARRAY_COLOR];var bc:PackedColorArray=ba[Mesh.ARRAY_COLOR]
				check(ac.size()==bc.size(),"imported color count unchanged")
				if am.resource_name=="canvas":
					check(am.vertex_color_use_as_albedo and bm.vertex_color_use_as_albedo,"canvas material consumes vertex colors")
					for point in range(mini(ac.size(),bc.size())):
						if ac[point]!=bc[point]:changed+=1
				else:check(ac==bc,"noncanvas color array unchanged on %s"%am.resource_name)
			check(changed>0,"actual imported canvas colors change in sail%d LOD%d"%[index,lod])
		var damage=Damage.new();damage.configure([candidate])
		for index in range(3):
			var sail:=candidate.find_child("sail_%d"%index,true,false) as MeshInstance3D
			if sail==null:continue
			var found:=false
			for surface in sail.mesh.get_surface_count():
				var original=sail.mesh.surface_get_material(surface)
				if original is StandardMaterial3D and original.resource_name=="canvas":
					var active=sail.get_active_material(surface)
					found=active is ShaderMaterial and active.get_shader_parameter("use_original_vertex_color")==true
			check(found,"actual damage shader consumes canvas color LOD%d sail%d"%[lod,index])
		damage.dispose();old.free();candidate.free()
	var diagnostics:Dictionary=library.get_model_load_diagnostics()
	check(diagnostics.get("runtimeImports",0)==6,"all six models used normal raw GLTF runtime import")
	library.dispose()
	print("HERO_R11_IMPORT_TEST assertions=",assertions," failures=",failures.size())
	quit(1 if not failures.is_empty() else 0)
