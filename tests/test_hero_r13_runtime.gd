extends SceneTree
## Test-only redirect exercises the real asset library, hero provider and damage path.
const Library=preload("res://modules/scene_engine/assets/asset_library.gd")
const Provider=preload("res://modules/scene_engine/assets/hero_ship_provider.gd")
const Damage=preload("res://game/presentation/ships/ship_damage.gd")
const PNG="res://assets/textures/hero_fuchuan_r13/weathered-cinnabar-hemp.png"
var assertions:=0
var failures:=0

class Redirect extends RefCounted:
	var owner:RefCounted
	func _init(value:RefCounted)->void:owner=value
	func instantiate_model(path:String)->Node3D:
		return owner.instantiate_model(path.replace("/hero_fuchuan_v3_r6/","/hero_fuchuan_v3_r13/"))

func check(ok:bool,why:String)->bool:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL R13: ",why)
	return ok

func _initialize()->void:run.call_deferred()

func run()->void:
	var expected:=Image.load_from_file(PNG)
	if not check(expected!=null and not expected.is_empty(),"source image decodes"):quit(1);return
	expected.convert(Image.FORMAT_RGBA8)
	var pixels:=expected.get_data()
	var library:=Library.new();var provider:=Provider.new("art_r6",true)
	for lod in range(3):
		var model:Node3D=provider.instantiate_ship("fuchuan",lod,Redirect.new(library))
		if not check(model!=null,"real provider imports LOD%d"%lod):continue
		var damage:=Damage.new();damage.configure([model])
		for i in range(3):
			var sail:=model.find_child("sail_%d"%i,true,false) as MeshInstance3D
			if not check(sail!=null and sail.mesh!=null,"LOD%d sail%d exists"%[lod,i]):continue
			check(sail.mesh.get_blend_shape_count()==2 and sail.mesh.get_blend_shape_name(0)=="furl" and sail.mesh.get_blend_shape_name(1)=="inflate","LOD%d sail%d shape keys"%[lod,i])
			var found:=false
			for surface in range(sail.mesh.get_surface_count()):
				var material=sail.mesh.surface_get_material(surface)
				if not material is StandardMaterial3D or material.resource_name!="canvas":continue
				found=true
				var texture:Texture2D=material.albedo_texture
				if not check(texture!=null,"LOD%d sail%d albedo bound"%[lod,i]):continue
				var original_image:=texture.get_image()
				check(original_image!=null and original_image.has_mipmaps(),"LOD%d sail%d real mipmaps"%[lod,i])
				if original_image:
					# Sail surfaces share one texture; never mutate its live image while
					# inspecting level zero or later sails would lose their mipmaps.
					var actual:=original_image.duplicate() as Image
					actual.clear_mipmaps();actual.convert(Image.FORMAT_RGBA8)
					check(actual.get_size()==expected.get_size() and actual.get_data()==pixels,"LOD%d sail%d exact decoded image pixels"%[lod,i])
				var shader=sail.get_active_material(surface)
				check(shader is ShaderMaterial and shader.get_shader_parameter("original_albedo")==texture and shader.get_shader_parameter("use_original_albedo")==true,"LOD%d sail%d damage shader albedo binding"%[lod,i])
				check(shader is ShaderMaterial and shader.get_shader_parameter("use_original_vertex_color")==true,"LOD%d sail%d damage shader vertex color binding"%[lod,i])
				for health in [100.0,80.0,60.0,30.0]:
					damage.apply_snapshot({"hull":100.0,"maxHull":100.0,"sail":health,"maxSail":100.0},100.0-health)
					check(shader.get_shader_parameter("original_albedo")==texture,"LOD%d sail%d health %.0f keeps source"%[lod,i,health])
					if health<=60.0:check(shader.get_shader_parameter("use_reference_damage")==true,"LOD%d sail%d health %.0f uses damage texture"%[lod,i,health])
			check(found,"LOD%d sail%d canvas surface"%[lod,i])
		damage.dispose();model.free()
	library.dispose()
	await process_frame
	print("HERO_R13_RUNTIME assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
