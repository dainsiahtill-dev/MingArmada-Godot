extends RefCounted
## Original Blender flagship; reference vessels remain available unchanged.
const Library=preload("res://modules/scene_engine/assets/asset_library.gd")
const Reference=preload("res://modules/scene_engine/assets/ship_model_provider.gd")
const PATHS=["res://assets/models/hero_fuchuan/fuchuan-lod0.glb","res://assets/models/hero_fuchuan/fuchuan-lod1.glb","res://assets/models/hero_fuchuan/fuchuan-lod2.glb"]
const VINTAGE_PATHS=["res://assets/models/hero_fuchuan_v2/fuchuan-lod0.glb","res://assets/models/hero_fuchuan_v2/fuchuan-lod1.glb","res://assets/models/hero_fuchuan_v2/fuchuan-lod2.glb"]
const ART_PATHS=["res://assets/models/hero_fuchuan_v3/fuchuan-lod0.glb","res://assets/models/hero_fuchuan_v3/fuchuan-lod1.glb","res://assets/models/hero_fuchuan_v3/fuchuan-lod2.glb"]
const REFINED_PATHS=["res://assets/models/hero_fuchuan_v3_r6/fuchuan-lod0.glb","res://assets/models/hero_fuchuan_v3_r6/fuchuan-lod1.glb","res://assets/models/hero_fuchuan_v3_r6/fuchuan-lod2.glb"]
var _vintage:=false
var _art:=false
var _refined:=false
var _authored_shadows:=false
func _init(variant:String="art_r6",authored_shadows:bool=true)->void:
	_refined=variant=="art_r6"
	_art=variant in ["art","art_r6"]
	_vintage=variant in ["vintage","art","art_r6"]
	_authored_shadows=authored_shadows
# Existing fuchuan water-effect coordinate adapter from ships-manifest.json.
# Mesh/marker units remain metres; the legacy effect history is in source units.
const WATER_EFFECT_UNIT:=0.021353528480495498

func source_kind(kind:String)->String:
	return "hero_fuchuan" if kind=="fuchuan" else str({"fisherman":"sloop1","merchant":"ship_merman","voc":"frigate","patrol":"ship_brigantine","heavy":"treasure_galleon"}.get(kind,""))

func instantiate_ship(kind:String,lod:int,library:RefCounted=null)->Node3D:
	if lod not in [0,1,2]:return null
	var owns:=library==null
	var owner:RefCounted=Library.new() if owns else library
	if kind!="fuchuan":
		var reference:Node3D=Reference.for_library(owner).instantiate_ship(kind,lod,owner)
		if owns:owner.dispose()
		return reference
	var paths:Array=REFINED_PATHS if _refined else ART_PATHS if _art else VINTAGE_PATHS if _vintage else PATHS
	var model:Node3D=owner.instantiate_model(paths[lod])
	if owns:owner.dispose()
	if model==null:return null
	model.set_meta("source_family","hero_fuchuan")
	model.set_meta("source_kind","hero_fuchuan")
	model.set_meta("source_path",paths[lod])
	model.set_meta("texture_style","art_v3_imagegen" if _art else "imagegen_vintage_v2" if _vintage else "procedural_v1")
	if _art:model.set_meta("art_revision",6 if _refined else 5)
	model.set_meta("model_origin","blender_authored")
	model.set_meta("game_kind",kind)
	model.set_meta("lod_policy","authored_geometry_lods")
	# Existing water consumer converts source [x,y,z] to Godot [x,z,-y].
	model.set_meta("source_water_markers",{"sourceToWorld":1.0,"effectSourceToWorld":WATER_EFFECT_UNIT,"sourceResourceName":"hero_fuchuan","wake":{"id":"water_wake","position":[0,15.6,0]},"bow":{"id":"water_bow","position":[0,-15.4,0]}})
	for node:Node3D in model.find_children("*","Node3D",true,false):
		var label:=String(node.name)
		if label.begins_with("shadow_") and node is MeshInstance3D:
			node.visible=false
			node.set_meta("hero_shadow_resource",true)
			continue
		if label=="deck":node.set_meta("deck_support",true)
		if label=="hull" or label=="deck" or label.begins_with("mast_timber_"):
			node.set_meta("target_rigid_shadow_caster",true)
			if _art and _authored_shadows:
				var proxy:=node.get_parent().get_node_or_null("shadow_"+label) as MeshInstance3D
				if proxy!=null and proxy.mesh!=null and proxy.transform.is_equal_approx(node.transform):
					# Keep visibility, animation frame and native-shadow fallback on
					# the full component. Only the stencil input resource differs.
					node.set_meta("target_shadow_geometry",proxy.mesh)
		if label=="hull":node.set_meta("damage_surface","hull")
		if label.begins_with("sail_"):
			node.set_meta("damage_surface","sail")
			node.set_meta("source_sail_control","authored_blender_morph")
		if label.begins_with("mast_") and label.trim_prefix("mast_").is_valid_int():node.set_meta("sail_trim_origin",0.0)
		if label in ["sterncastle","stern_transom"] or label.begins_with("cargo_hold_"):node.set_meta("deck_obstacle",true)
		if label.begins_with("rigging_") and label.trim_prefix("rigging_").is_valid_int():node.set_meta("authored_mast_index",int(label.trim_prefix("rigging_")))
		if label.begins_with("socket_smoke_"):
			var frame:=Transform3D.IDENTITY
			var current:=node
			while current!=model and current!=null:
				frame=current.transform*frame;current=current.get_parent() as Node3D
			node.set_meta("source_muzzle_position",frame.origin)
		if node is MeshInstance3D and node.mesh:
			for surface in node.mesh.get_surface_count():
				var material=node.mesh.surface_get_material(surface)
				if material is StandardMaterial3D:
					if _vintage:_prepare_mips(material)
					material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
					if label.begins_with("sail_"):material.cull_mode=BaseMaterial3D.CULL_DISABLED
	return model

func _prepare_mips(material:StandardMaterial3D)->void:
	# Runtime GLTF images lack mip levels. Prepare this shared cached material
	# once at load, never in a pose/frame update. Level-zero image stays intact.
	if material.has_meta("hero_mips_prepared") or material.albedo_texture==null:return
	var image:=material.albedo_texture.get_image()
	if image==null or image.is_empty():return
	if not image.has_mipmaps():
		if image.is_compressed() and image.decompress()!=OK:return
		if image.generate_mipmaps()!=OK:return
		material.albedo_texture=ImageTexture.create_from_image(image)
	material.set_meta("hero_mips_prepared",true)
