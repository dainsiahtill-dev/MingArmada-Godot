extends Node3D
## Recovered Cat Island canopy and rigid palm streams. Exact viewer mode keeps
## the original world transforms; mapped mode only adapts real tree groups to
## existing game terrain and excludes retained harbor geometry. No random tree
## positions, generated crowns, camera-facing palm rotation or wall clock.
const MeshAsset = preload("res://modules/scene_engine/fidelity_island/mesh_asset.gd")
const Coordinates = preload("res://modules/scene_engine/fidelity_island/source_coordinates.gd")
const CanopyShader = preload("res://modules/scene_engine/fidelity_island/canopy.gdshader")
const BASE := "res://assets/data/fidelity_island/"
const PALM_HASH := "04fa5c279a1967c17fa91d573dde6909171dd33fc13546c761cf07ea79a06739"
const CANOPY_HASH := "e9cbafe21b5b0e6852426c720fb012f6936ac0af520921d25b484dd676cbf398"
const NORMALIZE := 0.003921568859368563
var _owned: Array[Node3D] = []
var _materials: Array[ShaderMaterial] = []
var _audit: Dictionary = {"owned_nodes":0,"accepted_tree_count":0,"anchors":[],"simulation_time":0.0,"camera_pool_restored":false}

static func canopy_table(source: Dictionary, metadata: Dictionary, column: int, row: int) -> Dictionary:
	var data := PackedFloat32Array(); data.resize(256)
	var exists := false
	var maps: Dictionary = source.get("maps", {})
	if not maps.has("height") or not maps.has("cull") or not maps.has("shadow") or not Coordinates.valid_metadata(metadata): return {"data":data,"exists":false}
	var width := int(maps.height.width); var height := int(maps.height.height)
	var scale := float(source.canopy.canopyscale)
	for x in 8:
		for y in 8:
			var px := column*8+x; var py := row*8+y
			if px < 0 or py < 0 or px >= width or py >= height: continue
			var pixel := px+py*width; var index := (x*8+7-y)*4
			data[index] = MeshAsset.float32((float(maps.height.bytes[pixel])-128.0)/scale*float(metadata.effectiveScale[2]))
			data[index+1] = MeshAsset.float32(float(maps.cull.bytes[pixel])*NORMALIZE)
			data[index+2] = MeshAsset.float32(float(maps.shadow.bytes[pixel])*NORMALIZE)
			if data[index+1] > 0.5: exists = true
	return {"data":data,"exists":exists}

static func _vector3(value: Variant) -> Vector3:
	if value is Vector3: return value
	if value is Array and value.size() == 3: return Vector3(float(value[0]),float(value[1]),float(value[2]))
	if value is Dictionary and value.has("x") and value.has("z"): return Vector3(float(value.x),float(value.get("y",0.0)),float(value.z))
	return Vector3(NAN,NAN,NAN)

static func _point(flat: Array, index: int) -> Vector3:
	return Vector3(float(flat[index*3]),float(flat[index*3+1]),float(flat[index*3+2]))

static func _sample_control(table: PackedFloat32Array, rgba: Vector4) -> Vector4:
	var color := rgba/255.0
	var k := int((color.x*6.0+0.04)*8.0+(color.y*6.0+0.04))
	if k < 0 or k+9 >= 64: return Vector4(NAN,NAN,NAN,NAN)
	var result := Vector4.ZERO
	for entry: Array in [[k,(1.0-color.z)*(1.0-color.w)],[k+8,color.z*(1.0-color.w)],[k+1,(1.0-color.z)*color.w],[k+9,color.z*color.w]]:
		var offset := int(entry[0])*4
		result += Vector4(table[offset],table[offset+1],table[offset+2],table[offset+3])*float(entry[1])
	return result

static func _root_of(parents: PackedInt32Array, index: int) -> int:
	var current := index
	while parents[current] != current: current = parents[current]
	return current

static func _palm_groups(mesh: Dictionary) -> Array:
	# The merged NIF contains 24 connected 16-vertex trunks and disconnected
	# foliage quads. Formal adaptation binds each foliage component to its
	# nearest authored crown. This association is a game adaptation, not a
	# recovered original per-tree scene graph. Exact mode never changes it.
	var parents := PackedInt32Array(); parents.resize(mesh.positions.size()/3)
	for i in parents.size(): parents[i] = i
	for i in range(0,mesh.indices.size(),3):
		var first := _root_of(parents,int(mesh.indices[i]))
		parents[_root_of(parents,int(mesh.indices[i+1]))] = first
		parents[_root_of(parents,int(mesh.indices[i+2]))] = first
	var components: Dictionary = {}
	for i in parents.size():
		var key := _root_of(parents,i)
		if not components.has(key): components[key] = []
		components[key].append(i)
	var groups: Array = []
	for indices: Array in components.values():
		if indices.size() != 16: continue
		var low := INF; var high := -INF
		for i: int in indices:
			low = minf(low,_point(mesh.positions,i).z); high = maxf(high,_point(mesh.positions,i).z)
		var root := Vector3.ZERO; var crown := Vector3.ZERO; var root_count := 0; var crown_count := 0
		for i: int in indices:
			var point := _point(mesh.positions,i)
			if point.z <= low+(high-low)*0.05: root += point; root_count += 1
			if point.z >= high-(high-low)*0.05: crown += point; crown_count += 1
		root /= maxf(1.0,float(root_count)); root.z = low
		crown /= maxf(1.0,float(crown_count))
		groups.append({"indices":indices.duplicate(),"anchor":root,"crown":crown})
	for indices: Array in components.values():
		if indices.size() == 16: continue
		var center := Vector3.ZERO
		for i: int in indices: center += _point(mesh.positions,i)
		center /= float(indices.size())
		var nearest := -1; var distance := INF
		for i in groups.size():
			var candidate: float = center.distance_squared_to(groups[i].crown)
			if candidate < distance: nearest = i; distance = candidate
		if nearest >= 0: groups[nearest].indices.append_array(indices)
	return groups

static func _canopy_groups(original: Dictionary, mesh: Dictionary) -> Array:
	var groups: Dictionary = {}
	for i in original.colors.size():
		var key := str(original.colors[i])
		if not groups.has(key): groups[key] = {"indices":[],"anchor":Vector3.ZERO,"minimum":INF,"color":MeshAsset.unpack_argb(MeshAsset.pack_geometry_color_argb(original.colors[i]))}
		groups[key].indices.append(i)
		groups[key].anchor += _point(mesh.positions,i)
		groups[key].minimum = minf(float(groups[key].minimum),_point(mesh.positions,i).z)
	var result: Array = []
	for group: Dictionary in groups.values():
		group.anchor /= float(group.indices.size()); group.anchor.z = group.minimum
		result.append(group)
	return result

static func _building_overlap(point: Vector3, sites: Array, clearance: float) -> bool:
	for site: Variant in sites:
		if site is AABB:
			var box: AABB = site.grow(clearance)
			if point.x >= box.position.x and point.x <= box.end.x and point.z >= box.position.z and point.z <= box.end.z: return true
		elif site is Rect2:
			if site.grow(clearance).has_point(Vector2(point.x,point.z)): return true
		elif site is Dictionary:
			if site.get("bounds") is AABB and _building_overlap(point,[site.bounds],clearance): return true
			var center := _vector3(site.get("position",site))
			if not center.is_finite(): continue
			var radius := float(site.get("radius",site.get("exclusion_radius",10.0)))
			if Vector2(point.x,point.z).distance_to(Vector2(center.x,center.z)) <= radius+clearance: return true
	return false

func configure(profile_mapping: Variant, height_sampler: Callable, options: Dictionary = {}) -> bool:
	var mappings: Array = []
	if profile_mapping is Array: mappings = profile_mapping
	elif profile_mapping is Dictionary:
		if not profile_mapping.is_empty(): mappings = [profile_mapping]
	elif profile_mapping is Object and profile_mapping.has_method("reference_profiles"): mappings = profile_mapping.reference_profiles()
	else: return false
	var mode := str(options.get("mode","exact" if mappings.is_empty() else "mapped"))
	if options.has("exact_source") and not options.exact_source is bool: return false
	var exact_source: bool = options.get("exact_source",false)
	if mode not in ["exact","mapped"] or (mode == "mapped" and (mappings.is_empty() or (not exact_source and not height_sampler.is_valid()))): return false
	for mapping: Variant in mappings:
		if not mapping is Dictionary or not Coordinates.valid_mapping(mapping): return false
	if not options.get("existing_buildings",[]) is Array: return false
	var source := MeshAsset.read_json(BASE+"vegetation-original.json")
	var scene := MeshAsset.read_json(BASE+"vegetation-scene.json")
	var terrain := MeshAsset.read_json(BASE+"terrain-scene.json")
	var metadata: Dictionary = terrain.get("metadata",terrain)
	var manifest := MeshAsset.read_json(BASE+"manifest.json")
	if source.is_empty() or scene.is_empty() or not Coordinates.valid_metadata(metadata) or source.assets.size() != 2: return false
	if source.assets[0].sha256 != PALM_HASH or source.assets[1].sha256 != CANOPY_HASH: return false
	var textures: Dictionary = {}
	for entry: Dictionary in manifest.get("textures",[]):
		if entry.get("group") == "vegetation":
			var texture := MeshAsset.texture_from_entry(entry)
			if texture == null: return false
			textures[str(entry.name)] = texture
	if not textures.has("palm_plant.dds") or not textures.has("canopy tree.dds"): return false
	var candidate_nodes: Array[Node3D] = []; var candidate_materials: Array[ShaderMaterial] = []
	var anchors: Array = []; var accepted := 0; var patch_count := 0
	var root_translation := _vector3(scene.treeTranslation)
	var origin := _vector3(options.get("native_origin",Vector3.ZERO))
	if not origin.is_finite(): return false
	var palm_groups := _palm_groups(scene.palm)
	var canopy_groups := _canopy_groups(source.assets[1].meshes[0],scene.canopy)
	var targets: Array = [{}] if mode == "exact" else mappings
	for mapping: Dictionary in targets:
		var unit := 1.0 if mode == "exact" else float(mapping.scale)/float(metadata.effectiveScale[0])
		var bundles: Array = [{"kind":"palm","mesh":scene.palm,"groups":palm_groups,"translation":Vector3.ZERO,"scale":1.0,"table":PackedFloat32Array(),"texture":textures["palm_plant.dds"]}]
		for patch: Dictionary in scene.patches:
			var table: Dictionary = canopy_table(source,metadata,int(patch.column),int(patch.row))
			if not table.exists: continue
			bundles.append({"kind":"canopy","mesh":scene.canopy,"groups":canopy_groups,"translation":_vector3(patch.translation),"scale":float(scene.scale),"table":table.data,"texture":textures["canopy tree.dds"]})
			patch_count += 1
		for bundle: Dictionary in bundles:
			var mesh: Dictionary = bundle.mesh; var count := int(mesh.positions.size()/3)
			var vertices := PackedVector3Array(); var normals := PackedVector3Array(); var uv := PackedVector2Array()
			var colors := PackedFloat32Array(); var adjustments := PackedFloat32Array()
			var shader_offsets := PackedFloat32Array(); shader_offsets.resize(count)
			vertices.resize(count); normals.resize(count); uv.resize(count); colors.resize(count*4); adjustments.resize(count*4)
			var axes: Dictionary = {} if mode == "exact" else Coordinates.source_axes(mapping)
			for i in count:
				var local: Vector3 = _point(mesh.positions,i)*float(bundle.scale)+bundle.translation
				var native_normal := _point(mesh.normals,i)
				if mode == "exact":
					vertices[i] = MeshAsset.native_to_godot(local+root_translation-origin)
					normals[i] = MeshAsset.native_to_godot(native_normal)
				else:
					var horizontal := Coordinates.native_to_world_xz(local,metadata,mapping)
					vertices[i] = Vector3(horizontal.x,(local.z+root_translation.z)*unit,horizontal.y)
					var plane: Vector2 = axes.column*native_normal.x-axes.row*native_normal.y
					normals[i] = Vector3(plane.x,native_normal.z,plane.y).normalized()
				uv[i] = Vector2(float(mesh.uv[i*2]),float(mesh.uv[i*2+1]))
				adjustments[i*4+1] = 1.0
				if bundle.kind == "canopy":
					var packed := MeshAsset.unpack_argb(MeshAsset.pack_geometry_color_argb(source.assets[1].meshes[0].colors[i]))
					for channel in 4: colors[i*4+channel] = packed[channel]
			for group: Dictionary in bundle.groups:
				var local_anchor: Vector3 = group.anchor*float(bundle.scale)+bundle.translation
				var control := Vector4(0,1,1,0) if bundle.kind == "palm" else _sample_control(bundle.table,group.color)
				local_anchor.z += control.x*float(bundle.scale)
				var original_root := MeshAsset.native_to_godot(local_anchor+root_translation-origin)
				var anchor := original_root; var correction := 0.0; var keep := control.y >= 0.5
				if mode == "mapped":
					var source_horizontal := Coordinates.native_to_world_xz(local_anchor,metadata,mapping)
					anchor = Vector3(source_horizontal.x,(local_anchor.z+root_translation.z)*unit,source_horizontal.y)
				if mode == "mapped" and not exact_source:
					var horizontal := Coordinates.native_to_world_xz(local_anchor,metadata,mapping)
					var ground := float(height_sampler.call(horizontal.x,horizontal.y))
					anchor = Vector3(horizontal.x,ground,horizontal.y)
					correction = ground-(local_anchor.z+root_translation.z)*unit
					keep = keep and is_finite(ground) and ground >= float(options.get("minimum_land_height",0.12))
					keep = keep and not _building_overlap(anchor,options.get("existing_buildings",[]),float(options.get("building_clearance",4.0)))
				for i: int in group.indices:
					adjustments[i*4] = correction
					adjustments[i*4+1] = 1.0 if keep else 0.0
					shader_offsets[i] = MeshAsset.float32(control.x*unit*float(bundle.scale)+correction)
				if keep:
					accepted += 1
					anchors.append({"kind":bundle.kind,"position":anchor,"profile_id":str(mapping.get("id","exact")),"source_root":local_anchor})
			var array_mesh := MeshAsset.surface(vertices,normals,uv,PackedInt32Array(mesh.indices),colors,adjustments)
			if array_mesh == null:
				for node: Node3D in candidate_nodes: node.free()
				return false
			var material := ShaderMaterial.new(); material.shader = CanopyShader
			material.set_shader_parameter("original_image",bundle.texture)
			material.set_shader_parameter("is_canopy",bundle.kind == "canopy")
			material.set_shader_parameter("native_unit_scale",unit*float(bundle.scale))
			material.set_shader_parameter("alpha_threshold",70.0/255.0 if bundle.kind == "canopy" else float(mesh.alpha.threshold)/255.0)
			material.set_shader_parameter("material_alpha",float(mesh.material.alpha))
			for name: String in ["ambient","diffuse","emissive"]:
				var value: Dictionary = mesh.material[name+"_color"]
				material.set_shader_parameter("material_"+name,Vector3(float(value.r),float(value.g),float(value.b)))
			if bundle.kind == "canopy":
				var cxd := PackedVector4Array()
				for i in 64: cxd.append(Vector4(bundle.table[i*4],bundle.table[i*4+1],bundle.table[i*4+2],bundle.table[i*4+3]))
				material.set_shader_parameter("cxd",cxd)
			array_mesh.surface_set_material(0,material)
			var instance := MeshInstance3D.new(); instance.name = "Original_"+bundle.kind+"_"+str(candidate_nodes.size()); instance.mesh = array_mesh
			instance.material_override = material
			# Shader displacement and authority offsets must fit the CPU cull box.
			var first_point := vertices[0]+Vector3.UP*shader_offsets[0]
			var bounds := AABB(first_point,Vector3.ZERO)
			for i in count: bounds = bounds.expand(vertices[i]+Vector3.UP*shader_offsets[i])
			# Include both terms together, not max(abs(CXD),abs(anchorCorrection));
			# same-direction offsets can otherwise lie outside the CPU cull box.
			instance.custom_aabb = bounds.grow(1.0)
			candidate_nodes.append(instance); candidate_materials.append(material)
	dispose()
	_owned = candidate_nodes; _materials = candidate_materials
	for node: Node3D in _owned: add_child(node)
	_audit = {"mode":mode,"exact_source":exact_source,"owned_nodes":_owned.size(),"accepted_tree_count":accepted,"anchors":anchors,"simulation_time":0.0,"canopy_patch_count":patch_count,"palm_vertices":scene.palm.positions.size()/3,"palm_triangles":scene.palm.indices.size()/3,"canopy_vertices":scene.canopy.positions.size()/3,"canopy_triangles":scene.canopy.indices.size()/3,"palm_source_sha256":PALM_HASH,"canopy_source_sha256":CANOPY_HASH,"texture_mips":"original BC mip payload","camera_pool_restored":false,"palm_ffp_restored":false,"scope":"Original mesh, CXD and shader stream; mapped roots/building masks are explicit game terrain adaptation. exact_source bypasses anchoring and retains source Z while adapting horizontal axes. All positive patches, no claimed original camera/LOD/pool scheduler. Palm diffuse/ambient is diagnostic, not recovered full FFP."}
	apply_snapshot(options.get("snapshot",{}))
	return true

func apply_snapshot(snapshot: Dictionary, _delta: float = 0.0) -> void:
	var time: Variant = snapshot.get("time",_audit.get("simulation_time",0.0))
	if (time is int or time is float) and is_finite(float(time)): _audit.simulation_time = float(time)
	var lighting: Dictionary = snapshot.get("lighting",{}) if snapshot.get("lighting",{}) is Dictionary else {}
	var uniforms := {"lightDirection":"light_direction","lightColor":"light_color","ambient":"ambient_color","ambientAlpha":"ambient_alpha","fogColor":"fog_color","fogValues":"fog_values","customFog":"custom_fog"}
	for material: ShaderMaterial in _materials:
		for key: String in uniforms:
			if not lighting.has(key): continue
			var value: Variant = lighting[key]
			if key not in ["ambientAlpha","customFog"]:
				value = _vector3(value)
				if not value.is_finite(): continue
			material.set_shader_parameter(uniforms[key],value)
		if not material.get_shader_parameter("is_canopy"):
			for key: String in ["palmLightColor","palmAmbient"]:
				if lighting.has(key):
					var value := _vector3(lighting[key])
					if value.is_finite(): material.set_shader_parameter("light_color" if key == "palmLightColor" else "ambient_color",value)
	if snapshot.get("visible") is bool:
		for node: Node3D in _owned: node.visible = snapshot.visible

func diagnostics() -> Dictionary: return _audit.duplicate(true)

func dispose() -> void:
	for node: Node3D in _owned:
		if is_instance_valid(node):
			if node.get_parent() == self: remove_child(node)
			node.free()
	_owned.clear(); _materials.clear()
	_audit = {"owned_nodes":0,"accepted_tree_count":0,"anchors":[],"simulation_time":0.0,"camera_pool_restored":false}
