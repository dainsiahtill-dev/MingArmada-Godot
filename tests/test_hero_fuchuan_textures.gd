extends SceneTree
const Provider=preload("res://modules/scene_engine/assets/hero_ship_provider.gd")
const Ship=preload("res://game/presentation/ships/ship_view.gd")
var assertions:=0
var failures:=0
func check(ok:bool,why:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL hero textures: ",why)
func _initialize()->void:run.call_deferred()
func run()->void:
	var ship:=Ship.new();root.add_child(ship)
	check(ship.configure("fuchuan",null,Provider.new("vintage")),"vintage candidate loads through real ship/damage path")
	for model:Node3D in ship.get("_models"):
		check(model.get_meta("texture_style","")=="imagegen_vintage_v2","candidate provenance is explicit")
		var seen:Dictionary={}
		for node in model.find_children("*","MeshInstance3D",true,false):
			for surface in node.mesh.get_surface_count():
				var source:Material=node.mesh.surface_get_material(surface)
				if not source is StandardMaterial3D:continue
				if source.resource_name not in ["teak","deck","canvas","iron"] or seen.has(source.resource_name):continue
				seen[source.resource_name]=true
				check(source.albedo_texture!=null and source.albedo_texture.get_size()==Vector2(1254,1254),"generated pixels survive GLB import: "+source.resource_name)
				check(source.albedo_texture!=null and source.albedo_texture.get_image().has_mipmaps(),"runtime texture has real mip levels, not only a mip-filter flag: "+source.resource_name)
				if source.resource_name=="canvas":
					check(source.uv1_scale.is_equal_approx(Vector3(12,18,1)),"fine cloth albedo scale roundtrips independently of damage UV")
					var active:ShaderMaterial=node.get_active_material(surface)
					check(active.get_shader_parameter("original_uv_scale").is_equal_approx(Vector2(12,18)),"production damage material preserves fine cloth texture scale")
					check(active.get_shader_parameter("original_albedo")==source.albedo_texture,"production damage material retains generated cloth pixels")
		check(seen.size()==4,"all four generated material families exist in each LOD")
	ship.dispose();ship.free();await process_frame
	print("HERO_FUCHUAN_TEXTURES_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
