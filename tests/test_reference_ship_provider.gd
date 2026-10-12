extends SceneTree
const Provider = preload("res://modules/scene_engine/assets/ship_model_provider.gd")
const Library = preload("res://modules/scene_engine/assets/asset_library.gd")
const ShipView = preload("res://game/presentation/ships/ship_view.gd")
var failures := 0
var assertions := 0
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures += 1; printerr("FAIL: ",message)
func _initialize() -> void:
	var library := Library.new()
	var provider := Provider.for_library(library)
	check(provider == Provider.for_library(library),"one immutable resource provider per library owner")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Provider.MANIFEST))
	for kind: String in manifest.mappings:
		var entry: Dictionary = manifest.mappings[kind]
		if kind != "fuchuan": check(not entry.semantics.get("sailFurledMeshes",[]).is_empty(),"original hidden folded cloth supplies authored target: " + kind)
		var raw: Node3D = library.instantiate_model(entry.modelPath)
		var model: Node3D = provider.instantiate_ship(kind,0,library)
		check(model != null,"original source load: " + kind)
		if model == null: raw.free(); continue
		check(model.get_meta("source_family") == entry.family and model.scale == Vector3.ONE,"family and uniform pre-scaled metres preserved: " + kind)
		var other: Node3D = provider.instantiate_ship(kind,2,library)
		check(other != null and other != model,"same lowend family owns independent LOD nodes: " + kind)
		if other: other.free()
		for material_entry: Dictionary in entry.materials:
			var node := model.find_child(material_entry.nodeName,true,false) as MeshInstance3D
			check(node != null,"actual named original material mesh exists")
			if node == null: continue
			for surface in node.mesh.get_surface_count():
				var material := node.get_active_material(surface) as StandardMaterial3D
				check(material != null and material.albedo_texture != null,"source material binds real DDS texture")
				if material == null or material.albedo_texture == null: continue
				var image := material.albedo_texture.get_image()
				var texture_entry: Dictionary = entry.textures[material_entry.baseTexture]
				check(image.get_mipmap_count() == int(texture_entry.mipLevels)-1,"every authored source mip retained")
				check(image.get_data() == FileAccess.get_file_as_bytes(texture_entry.compressedMipPath),"original compressed mip payload not regenerated")
		var furling_panels := 0
		for item: Dictionary in entry.semantics.sailMeshes:
			var node := model.find_child(item.name,true,false) as MeshInstance3D
			var original := raw.find_child(item.name,true,false) as MeshInstance3D
			check(node.mesh.get_blend_shape_count() == 2 and original.mesh.get_blend_shape_count() == 0,"declared game sail controls never mutate cached original")
			var moving_furl := false
			var moving_inflate := false
			for surface in node.mesh.get_surface_count():
				var actual := node.mesh.surface_get_arrays(surface)
				var native := original.mesh.surface_get_arrays(surface)
				for stream in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2,Mesh.ARRAY_INDEX]:
					check(actual[stream] == native[stream],"sail source topology and UV remain exact at rest")
				var normal_error := 0.0
				for index in actual[Mesh.ARRAY_NORMAL].size(): normal_error=maxf(normal_error,actual[Mesh.ARRAY_NORMAL][index].distance_to(native[Mesh.ARRAY_NORMAL][index]))
				check(normal_error < 0.0003,"Godot uncompressed morph-normal repack remains below 0.0003")
				var morphs := node.mesh.surface_get_blend_shape_arrays(surface)
				for delta: Vector3 in morphs[0][Mesh.ARRAY_VERTEX]: moving_furl = moving_furl or delta.length() > 0.01
				for delta: Vector3 in morphs[1][Mesh.ARRAY_VERTEX]: moving_inflate = moving_inflate or delta.length() > 0.001
			check(moving_inflate,"actual sail inflation deforms submitted vertices: %s %s" % [kind,node.name])
			if moving_furl: furling_panels += 1
			if node.get_meta("source_furl_control","") == "game_fold2D":
				check(moving_furl,"declared fallback collapses both sheet axes")
				_check_fold_anchor(node,original,kind)
		check(furling_panels > 0,"actual source vessel has visibly controllable authored furl panels: " + kind)
		for pair: Dictionary in entry.semantics.get("sailFurledMeshes",[]):
			var open := model.find_child(pair.pairedOpenName,true,false) as MeshInstance3D
			var closed := model.find_child(pair.name,true,false) as MeshInstance3D
			check(open != null and closed != null and not closed.visible,"original folded target stays hidden alongside its controlled source panel")
			if open == null or closed == null: continue
			check(open.get_meta("source_furl_control","") == "authored_furled_target","partial furl interpolates actual original folded source")
			check(open.get_parent() == closed.get_parent(),"original open/fold pair share real mast-local coordinates")
			for surface in open.mesh.get_surface_count():
				var rest: PackedVector3Array = open.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
				var delta: PackedVector3Array = open.mesh.surface_get_blend_shape_arrays(surface)[0][Mesh.ARRAY_VERTEX]
				var target: PackedVector3Array = closed.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
				var error := 0.0
				for index in rest.size(): error=maxf(error,(rest[index]+delta[index]).distance_to(target[index]))
				check(error < 0.00002,"full furl reaches submitted original folded vertices within 20 micrometres")
		model.free(); raw.free()
		var view := ShipView.new(); root.add_child(view)
		check(view.configure(kind,library),"actual damage-wrapped presentation reuses source provider")
		view.apply_snapshot({"id":"source","kind":kind,"time":0.0,"hull":100.0,"sail":0.0,"maxHull":100.0,"maxSail":100.0,"sailDeployment":1.0,"sailAngle":0.0,"visual":{"position":{"x":0.0,"y":0.0,"z":0.0},"heading":0.0}})
		view.dispose(); view.free()
	var actual_manifest: Dictionary = provider._manifest
	provider._manifest = actual_manifest.duplicate(true)
	provider._manifest.mappings.fuchuan.semantics.cannons = []
	var missing: Node3D = provider.instantiate_ship("fuchuan",0,library)
	check(missing == null,"missing actual cannon geometry rejects armed presentation atomically")
	if missing: missing.free()
	provider._manifest = actual_manifest
	check(provider.instantiate_ship("missing",0,library) == null and provider.instantiate_ship("fuchuan",9,library) == null,"invalid selection cannot fabricate source geometry")
	library.dispose()
	check(provider.diagnostics().disposed and provider.instantiate_ship("fuchuan",0,library) == null,"library lifecycle releases provider cache and fences reentry")
	print("REFERENCE_SHIP_PROVIDER assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)

func _check_fold_anchor(node: MeshInstance3D, original: MeshInstance3D, kind: String) -> void:
	# Read the source's real top edge independently. Its centroid must remain at
	# the original attachment when the rest of the sheet collapses around it.
	var top := -INF
	var bottom := INF
	for surface in original.mesh.get_surface_count():
		for point: Vector3 in original.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
			top=maxf(top,point.y); bottom=minf(bottom,point.y)
	var epsilon := maxf(0.00001,(top-bottom)*0.0001)
	var source_centroid := Vector3.ZERO
	var folded_centroid := Vector3.ZERO
	var count := 0
	var apex := Vector3.ZERO
	var one_apex := true
	var apex_error := 0.0
	for surface in original.mesh.get_surface_count():
		var source: PackedVector3Array = original.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		var delta: PackedVector3Array = node.mesh.surface_get_blend_shape_arrays(surface)[0][Mesh.ARRAY_VERTEX]
		for index in source.size():
			if source[index].y >= top-epsilon:
				if count == 0: apex=source[index]
				elif source[index] != apex: one_apex=false
				apex_error=maxf(apex_error,delta[index].length())
				source_centroid += source[index]
				folded_centroid += source[index]+delta[index]
				count += 1
	check(count > 0 and (source_centroid/float(count)).distance_to(folded_centroid/float(count)) < 0.00002,"fallback furl keeps actual source top-edge centroid attached: %s %s" % [kind,node.name])
	if one_apex: check(apex_error == 0.0,"single actual source apex has exactly zero furl displacement: %s %s" % [kind,node.name])
