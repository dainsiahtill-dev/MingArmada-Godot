extends SceneTree
const Library=preload("res://modules/scene_engine/assets/asset_library.gd")
const Production=preload("res://modules/scene_engine/assets/hero_ship_provider.gd")
const PATH="res://game/research/fixtures/hero_palette_provider.gd"
var assertions:=0
var failures:=0
func check(value:bool,detail:String)->void:
	assertions+=1
	if not value:failures+=1;printerr("FAIL: ",detail)
func _initialize()->void:run.call_deferred()
func run()->void:
	check(ResourceLoader.exists(PATH),"independent palette provider exists")
	if ResourceLoader.exists(PATH):
		var library:=Library.new()
		var provider:RefCounted=load(PATH).new("art_r6",true)
		# An incompatible source must never load a different model and label it R7b.
		for source_variant:String in ["art","art_r7c"]:
			var incompatible:RefCounted=load(PATH).new(source_variant,true,"r7b")
			for lod in 3:
				var rejected:Node3D=incompatible.instantiate_ship("fuchuan",lod,library)
				check(rejected==null,"incompatible source %s refuses palette relabeling at LOD%d"%[source_variant,lod])
				if rejected!=null:rejected.free()
			var reference:Node3D=incompatible.instantiate_ship("fisherman",0,library)
			check(reference!=null,"palette source restriction preserves other-ship delegation")
			if reference!=null:
				check(reference.get_meta("source_kind","")=="sloop1","delegated ship keeps its original source identity")
				reference.free()
		for lod in 3:
			var model:Node3D=provider.instantiate_ship("fuchuan",lod,library)
			check(model!=null,"R7 candidate loads LOD%d"%lod)
			if model==null:continue
			check(model.get_meta("source_path","")=="res://assets/models/hero_fuchuan_v3_r7c/fuchuan-lod%d.glb"%lod,"metadata names final candidate with preserved original UV")
			check(model.get_meta("model_origin","")=="blender_authored" and model.get_meta("art_revision",0)==7,"authored rig and candidate revision preserved")
			var roles:Dictionary={};var casters:=0
			for node:MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
				if node.get_meta("target_rigid_shadow_caster",false):
					casters+=1;check(node.has_meta("target_shadow_geometry"),"authored proxy kept on "+str(node.name))
				if node.mesh==null:continue
				for surface in node.mesh.get_surface_count():
					var material:Material=node.get_active_material(surface)
					roles[material.resource_name]=true
					if material.resource_name in ["sunwashed_teak","aged_hull_teak"]:
						check(material is StandardMaterial3D and material.albedo_texture!=null,"actual new material texture bound")
						check(material.albedo_texture.get_image().has_mipmaps(),"new generated wood has real mip levels")
						if material.resource_name=="aged_hull_teak":
							var gain:Color=material.albedo_color.srgb_to_linear()
							check(Vector3(gain.r,gain.g,gain.b).distance_to(Vector3(.68,.65,.61))<.00001,"actual exported hull factor reached Godot")
			check(casters==5,"five original authored shadow proxies retained")
			check(roles.has_all(["sunwashed_teak","aged_hull_teak","teak","tarred","deck","canvas"]),"spatial palette roles plus original materials exist")
			check(model.find_child("rudder_pivot",true,false)!=null and model.find_child("mast_1",true,false)!=null,"steering and reefing hierarchy retained")
			model.free()
		# Integration must select the accepted asset through the original seam.
		var baseline:Node3D=Production.new().instantiate_ship("fuchuan",0,library)
		check(baseline.get_meta("source_path","").contains("hero_fuchuan_v3_r7c") and baseline.get_meta("art_revision",0)==7,"formal default selects accepted palette resource")
		baseline.free()
		var previous:Node3D=Production.new("art_r6").instantiate_ship("fuchuan",0,library)
		check(previous.get_meta("source_path","").contains("hero_fuchuan_v3_r6"),"explicit R6 remains available as comparison/rollback")
		previous.free();library.dispose()
	print("HERO_PALETTE_PROVIDER_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
