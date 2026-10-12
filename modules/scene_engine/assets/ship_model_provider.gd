extends RefCounted
## One original rigid lowend source per game kind. LOD nodes are independent;
## DDS mip chains and topology remain authored. Rig controls are game adapters.

const Library = preload("res://modules/scene_engine/assets/asset_library.gd")
const MeshAsset = preload("res://modules/scene_engine/fidelity_island/mesh_asset.gd")
const PhysicsTypes = preload("res://modules/contracts/physics_types.gd")
const MANIFEST := "res://assets/data/fidelity_naval/ships-manifest.json"
const CACHE_META := &"reference_ship_provider"
var _manifest: Dictionary = {}
var _textures: Dictionary = {}
var _materials: Dictionary = {}
var _sail_meshes: Dictionary = {}
var _disposed := false

static func for_library(library: RefCounted) -> RefCounted:
	if library == null: return null
	if library.has_meta(CACHE_META): return library.get_meta(CACHE_META)
	var provider: RefCounted = load("res://modules/scene_engine/assets/ship_model_provider.gd").new()
	library.set_meta(CACHE_META, provider)
	return provider

func _entries() -> Dictionary:
	if _manifest.is_empty() and not _disposed: _manifest = MeshAsset.read_json(MANIFEST)
	return _manifest.get("mappings", {})

func source_kind(kind: String) -> String:
	return str(_entries().get(kind, {}).get("family", ""))

func instantiate_ship(kind: String, lod: int, library: RefCounted = null) -> Node3D:
	if _disposed or lod not in [0,1,2]: return null
	var entry: Dictionary = _entries().get(kind, {})
	if entry.is_empty(): return null
	var owns := library == null
	var owner: RefCounted = Library.new() if owns else library
	var model: Node3D = owner.instantiate_model(str(entry.get("modelPath", "")))
	if owns: owner.dispose()
	if model == null: return null
	model.set_meta("source_family", entry.family)
	model.set_meta("source_kind", entry.family)
	model.set_meta("source_path", entry.modelPath)
	model.set_meta("model_origin", "pirates_native_lowend")
	model.set_meta("source_lowend_shared", true)
	model.set_meta("lod_policy", "same_source_lowend")
	model.set_meta("game_kind", kind)
	var semantics: Dictionary = entry.get("semantics", {})
	var folded: Dictionary = {}
	for item: Dictionary in semantics.get("sailFurledMeshes", []):
		var closed := model.find_child(str(item.get("name","")),true,false) as MeshInstance3D
		if closed:
			closed.visible = false
			closed.set_meta("damage_surface","sail")
			folded[str(item.get("pairedOpenName",""))] = closed
	for role in ["hullMeshes", "sailMeshes", "deckMeshes"]:
		for item: Dictionary in semantics.get(role, []):
			var node := model.find_child(str(item.get("name", "")), true, false) as MeshInstance3D
			if node == null or node.mesh == null: continue
			if role == "deckMeshes": node.set_meta("deck_support", true)
			elif role == "hullMeshes": node.set_meta("damage_surface", "hull")
			else:
				node.set_meta("damage_surface", "sail")
				node.set_meta("source_sail_control", "game_furl_inflate_morph")
				_adapt_sail(node,folded.get(str(node.name)))
	for item: Dictionary in semantics.get("masts", []):
		var mast := model.find_child(str(item.get("name", "")), true, false) as Node3D
		if mast: mast.set_meta("sail_trim_origin", 0.0)
	for role in ["mastMeshes","riggingMeshes","flags"]:
		for item: Dictionary in semantics.get(role, []):
			var attachment := model.find_child(str(item.get("name","")),true,false) as Node3D
			if attachment:
				attachment.set_meta("source_fixed_attachment",item.get("mastName") == null)
				if role == "mastMeshes": attachment.set_meta("deck_obstacle",true)
	if not _bind_materials(model, entry):
		model.free()
		return null
	if not _adapt_cannons(model, kind, semantics.get("cannons", [])):
		model.free()
		return null
	return model

func _texture(name: String, entries: Dictionary) -> Texture2D:
	if name.is_empty(): return null
	if not _textures.has(name):
		var texture := MeshAsset.texture_from_entry(entries.get(name, {}))
		if texture == null: return null
		_textures[name] = texture
	return _textures[name]

func _bind_materials(model: Node3D, entry: Dictionary) -> bool:
	var entries: Dictionary = entry.get("textures", {})
	for item: Dictionary in entry.get("materials", []):
		var node := model.find_child(str(item.get("nodeName", "")), true, false) as MeshInstance3D
		if node == null or node.mesh == null: return false
		var base := _texture(str(item.get("baseTexture", "")), entries)
		if base == null: return false
		for surface in node.mesh.get_surface_count():
			var key := "%s:%s:%d" % [entry.family,item.nodeName,surface]
			if _materials.has(key):
				node.set_surface_override_material(surface,_materials[key])
				continue
			var original := node.get_active_material(surface) as StandardMaterial3D
			var material := original.duplicate() as StandardMaterial3D if original else StandardMaterial3D.new()
			material.albedo_texture = base
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			material.vertex_color_use_as_albedo = bool(node.mesh.surface_get_format(surface) & Mesh.ARRAY_FORMAT_COLOR)
			var source: Dictionary = item.get("sourceMaterial", {})
			var color: Array = source.get("diffuse", [1.0,1.0,1.0])
			material.albedo_color = Color(float(color[0]),float(color[1]),float(color[2]),float(source.get("alpha",1.0)))
			var alpha: Variant = item.get("alpha")
			var layered := item.get("playerTexture") != null
			if alpha is Dictionary and not layered:
				var flags := int(alpha.get("flags",0))
				if flags & 512:
					material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					material.alpha_scissor_threshold = maxf(1.0 / 255.0, float(alpha.get("threshold",0)) / 255.0)
				elif flags & 1: material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			node.set_surface_override_material(surface, material)
			_materials[key] = material
		if item.get("playerTexture") != null:
			var player := _texture(str(item.playerTexture), entries)
			var upgrade := _texture(str(item.get("upgradeTexture", "")), entries)
			if player == null or upgrade == null: return false
			node.set_meta("source_hull_layers", {"player":player,"upgrade":upgrade,"damage_uv2":bool(item.get("damageUv2",false))})
		# UV2 can be the sail emblem; SailShader's damage address remains UV0.
		if item.get("playerTexture") != null: node.set_meta("damage_uv2", bool(item.get("damageUv2",false)))
	return true

func _adapt_sail(node: MeshInstance3D, closed: MeshInstance3D = null) -> void:
	# A declared rigid-mesh game control, not the original game's cloth solver.
	var original := node.mesh as ArrayMesh
	if original == null or original.get_blend_shape_count() > 0: return
	var native_furl := closed != null and closed.mesh != null and closed.mesh.get_surface_count() == original.get_surface_count()
	node.set_meta("source_furl_control","authored_furled_target" if native_furl else "game_fold2D")
	var key := original.get_instance_id()
	if _sail_meshes.has(key):
		node.mesh = _sail_meshes[key]
		return
	var mesh := ArrayMesh.new()
	mesh.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_RELATIVE
	mesh.add_blend_shape("furl")
	mesh.add_blend_shape("inflate")
	var bounds := original.get_aabb()
	var fold_anchor := Vector3.ZERO
	if not native_furl:
		var top_y := -INF
		var bottom_y := INF
		for surface in original.get_surface_count():
			for point: Vector3 in original.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				top_y=maxf(top_y,point.y); bottom_y=minf(bottom_y,point.y)
		var top_epsilon := maxf(0.00001,(top_y-bottom_y)*0.0001)
		var anchor_count := 0
		var anchor_x := 0.0
		var anchor_y := 0.0
		var anchor_z := 0.0
		for surface in original.get_surface_count():
			for point: Vector3 in original.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				if point.y >= top_y-top_epsilon:
					# Accumulate in scalar float64 so repeated seam vertices at one
					# source apex round back to exactly that authored float32 point.
					anchor_x += point.x; anchor_y += point.y; anchor_z += point.z
					anchor_count += 1
		fold_anchor = Vector3(anchor_x/float(maxi(1,anchor_count)),anchor_y/float(maxi(1,anchor_count)),anchor_z/float(maxi(1,anchor_count)))
	for surface in original.get_surface_count():
		var arrays := original.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var closed_vertices := PackedVector3Array()
		var closed_normals := PackedVector3Array()
		if native_furl:
			var closed_arrays := closed.mesh.surface_get_arrays(surface)
			closed_vertices = closed_arrays[Mesh.ARRAY_VERTEX]
			closed_normals = closed_arrays[Mesh.ARRAY_NORMAL]
			if closed_vertices.size() != vertices.size(): closed_vertices.clear()
		var furl: Array = []; furl.resize(Mesh.ARRAY_MAX)
		var inflate: Array = []; inflate.resize(Mesh.ARRAY_MAX)
		var furl_points := PackedVector3Array()
		var inflate_points := PackedVector3Array()
		var zero_normals := PackedVector3Array()
		var furl_normals := PackedVector3Array()
		for index in vertices.size():
			var point := vertices[index]
			var height := (point.y - bounds.position.y) / maxf(0.001,bounds.size.y)
			var transverse := (point.x - bounds.position.x) / maxf(0.001,bounds.size.x) if bounds.size.x >= bounds.size.z else (point.z - bounds.position.z) / maxf(0.001,bounds.size.z)
			if not closed_vertices.is_empty():
				furl_points.append(closed_vertices[index] - point)
			else:
				# Barque has no authored folded state. Collapse both sheet axes to
				# a small top-edge bundle, rather than retaining a full-width plane.
				var target := Vector3(lerpf(point.x,fold_anchor.x,0.96),lerpf(point.y,fold_anchor.y,0.985),lerpf(point.z,fold_anchor.z,0.96))
				furl_points.append(target - point)
			var normal := normals[index] if normals.size() == vertices.size() else Vector3.RIGHT
			# Lowend triangles can have only edge vertices. A small free-foot term
			# keeps them controllable while the top edge stays attached to its yard.
			var belly := sin(PI * height) * sin(PI * transverse) + 0.2 * (1.0-height)
			inflate_points.append(normal * belly * minf(0.65,bounds.size.y * 0.06))
			zero_normals.append(Vector3.ZERO)
			furl_normals.append(closed_normals[index]-normal if closed_normals.size() == normals.size() else Vector3.ZERO)
		furl[Mesh.ARRAY_VERTEX] = furl_points
		inflate[Mesh.ARRAY_VERTEX] = inflate_points
		if not normals.is_empty():
			furl[Mesh.ARRAY_NORMAL] = furl_normals
			inflate[Mesh.ARRAY_NORMAL] = zero_normals
		if arrays[Mesh.ARRAY_TANGENT] != null:
			var tangents := PackedFloat32Array(); tangents.resize(vertices.size() * 4)
			furl[Mesh.ARRAY_TANGENT] = tangents
			inflate[Mesh.ARRAY_TANGENT] = tangents
		# Runtime GLTF adds custom RG-float streams; preserve their descriptors.
		# Its compressed-attribute flag cannot be used with relative blend shapes.
		var custom_mask := (Mesh.ARRAY_FORMAT_CUSTOM_MASK << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_FORMAT_CUSTOM_MASK << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) | (Mesh.ARRAY_FORMAT_CUSTOM_MASK << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT) | (Mesh.ARRAY_FORMAT_CUSTOM_MASK << Mesh.ARRAY_FORMAT_CUSTOM3_SHIFT)
		mesh.add_surface_from_arrays(original.surface_get_primitive_type(surface), arrays, [furl,inflate], {}, original.surface_get_format(surface) & custom_mask)
		mesh.surface_set_material(surface,original.surface_get_material(surface))
	_sail_meshes[key] = mesh
	node.mesh = mesh

func _adapt_cannons(model: Node3D, kind: String, source: Array) -> bool:
	var dimensions: Dictionary = PhysicsTypes.ship_spec(kind)
	var count := int(dimensions.get("guns",0))
	if count <= 0: return true
	for side in ["port", "starboard"]:
		var guns: Array[Dictionary] = []
		for item: Dictionary in source:
			if item.get("side") == side: guns.append(item)
		guns.sort_custom(func(a: Dictionary,b: Dictionary): return float(a.pivot[2]) < float(b.pivot[2]))
		if guns.size() < count: return false
		for index in count:
			var selected := roundi(float(index) * float(guns.size()-1) / float(maxi(1,count-1)))
			var item: Dictionary = guns[selected]
			var group := model.find_child(str(item.get("name", "")), true, false) as Node3D
			var socket := model.find_child(str(item.get("socketName", "")), true, false) as Node3D
			var barrel := model.find_child(str(item.get("barrelName", "")), true, false) as Node3D
			if group == null or socket == null or barrel == null: return false
			var length := float(dimensions.length)
			var longitudinal := length * (-0.138 + float(index)*0.092) if count == 4 else length*(-0.23+float(index)*0.46/float(maxi(1,count-1)))
			var curve := pow(1.0-pow(longitudinal/(length/2.0),2.0),0.64)
			var out := float(dimensions.width)*0.435*curve+0.87
			var canonical := Vector3(out if side == "port" else -out,float(dimensions.freeboard)+0.3,longitudinal)
			# Original beam is independent of physical gameplay dimensions. Keep
			# actual cannon geometry seated; only the logical event socket adapts.
			socket.set_meta("source_muzzle_position",_local_frame(socket,model).origin)
			socket.position = _local_frame(socket.get_parent() as Node3D,model).affine_inverse() * canonical
			barrel.set_meta("game_cannon_index", index)
			group.set_meta("game_muzzle_adapter", "authoritative_broadside")
	return true

func _local_frame(node: Node3D, model: Node3D) -> Transform3D:
	var frame := Transform3D.IDENTITY
	var current := node
	while current != model and current != null:
		frame = current.transform * frame
		current = current.get_parent() as Node3D
	return frame

func diagnostics() -> Dictionary:
	return {"families":_entries().size(),"textures":_textures.size(),"sail_adapters":_sail_meshes.size(),"lod_policy":"same_source_lowend","disposed":_disposed}

func dispose() -> void:
	_disposed = true
	_manifest.clear()
	_textures.clear()
	_materials.clear()
	_sail_meshes.clear()
