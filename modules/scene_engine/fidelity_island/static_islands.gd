extends RefCounted
## One immutable source-pixel mesh per island. The retained HeightField remains
## the only height/navigation/physics authority; these nodes own render data.
## Unlike world chunks, camera movement never schedules or rebuilds geometry.

const Coordinates = preload("res://modules/scene_engine/fidelity_island/source_coordinates.gd")
const ReferenceProfile = preload("res://modules/scene_engine/terrain/reference_island_profile.gd")
static var _sources: Dictionary = {}

class IslandMesh:
	extends "res://modules/scene_engine/terrain/terrain_chunk.gd"
	var mapping: Dictionary = {}
	var source_width := 0
	var source_height := 0
	var grid_min := Vector2i.ZERO
	var grid_size := Vector2i.ZERO
	var heights := PackedFloat32Array()

	func sample_mesh_height(world_x: float, world_z: float) -> float:
		if mesh == null or grid_size.x < 2 or grid_size.y < 2 or not is_finite(world_x) or not is_finite(world_z):
			return NAN
		var pixel: Vector2 = Coordinates.world_to_source_pixel(Vector2(world_x,world_z),mapping)
		var local_pixel := pixel-Vector2(grid_min)
		if local_pixel.x < 0.0 or local_pixel.y < 0.0 or local_pixel.x > grid_size.x-1 or local_pixel.y > grid_size.y-1:
			return NAN
		var column := mini(int(floor(local_pixel.x)),grid_size.x-2)
		var row := mini(int(floor(local_pixel.y)),grid_size.y-2)
		var x := clampf(local_pixel.x-column,0.0,1.0)
		var y := clampf(local_pixel.y-row,0.0,1.0)
		var a := row*grid_size.x+column
		var ah := heights[a]
		var bh := heights[a+grid_size.x]
		var ch := heights[a+1]
		var dh := heights[a+grid_size.x+1]
		# Match the actual alternating source diagonal, not bilinear sampling.
		if ((column+grid_min.x) ^ (row+grid_min.y)) & 1:
			return ah+(dh-bh)*x+(bh-ah)*y if y >= x else ah+(ch-ah)*x+(dh-ch)*y
		return ah+(ch-ah)*x+(bh-ah)*y if x+y <= 1.0 else dh+(bh-dh)*(1.0-x)+(ch-dh)*(1.0-y)

	func dispose() -> void:
		super.dispose()
		mapping.clear()
		heights.clear()
		source_width = 0
		source_height = 0
		grid_min = Vector2i.ZERO
		grid_size = Vector2i.ZERO

var _meshes: Array[MeshInstance3D] = []
var _profiles: Array = []
var _materials: Array = []
var _sampler := Callable()
var _geometry_builds := 0
var _vertex_count := 0
var _source_vertex_count := 0
var _triangle_count := 0
var _sample_calls := 0
var _render_bounds: Array[Dictionary] = []

static func _source(id: String) -> Dictionary:
	if not _sources.has(id):
		var source := ReferenceProfile.load_source(id)
		if not source.is_empty():
			_sources[id] = source
	return _sources.get(id,{})

static func _safe_mapping(profile: Dictionary) -> bool:
	# Coordinate helpers accept trusted authority diagnostics. Check external
	# component types before they call float(), so rejected candidates cannot
	# continue after a Godot script error with partially converted coordinates.
	var vector_keys: Array[String] = ["sourceCenter","sourceOutward","islandCenter","inward"]
	if profile.has("dock"):
		vector_keys.append("dock")
	for key: String in vector_keys:
		var value: Variant = profile.get(key)
		if value is Vector2:
			if not value.is_finite():
				return false
		elif value is Array and value.size() == 2:
			for component: Variant in value:
				if not (component is int or component is float) or not is_finite(float(component)):
					return false
		else:
			return false
	return Coordinates.valid_mapping(profile)

func configure(profiles: Array, height_sampler: Callable, materials: Array, options: Dictionary = {}) -> bool:
	# Native source resolution is deliberate. Accept no option which silently
	# turns source terrain into a coarse camera-centered procedural surface.
	if profiles.is_empty() or not height_sampler.is_valid() or materials.size() != profiles.size() or not options.is_empty():
		return false
	for index in profiles.size():
		if not profiles[index] is Dictionary or not materials[index] is Material:
			return false
		var profile: Dictionary = profiles[index]
		if not _safe_mapping(profile) or not profile.get("id") is String:
			return false
		var source := _source(str(profile.id))
		if source.is_empty():
			return false
		for key: String in ["width","height"]:
			var reported: Variant = profile.get(key)
			if not (reported is int or reported is float) or not is_finite(float(reported)) or float(reported) != float(source[key]):
				return false
	if not _meshes.is_empty() and profiles == _profiles and height_sampler == _sampler and materials == _materials:
		return true
	var candidates: Array[MeshInstance3D] = []
	var candidate_bounds: Array[Dictionary] = []
	var vertices := 0
	var source_vertices := 0
	var triangles := 0
	for index in profiles.size():
		var profile: Dictionary = profiles[index]
		var island := _build_mesh(profile,height_sampler,materials[index])
		if island == null:
			_free_meshes(candidates)
			return false
		candidates.append(island)
		var source_count: int = int(profile.width)*int(profile.height)
		source_vertices += source_count
		vertices += island.grid_size.x*island.grid_size.y
		triangles += (island.grid_size.x-1)*(island.grid_size.y-1)*2
		candidate_bounds.append({"id":profile.id,"sourcePixelMin":Vector2i.ZERO,"sourcePixelMax":Vector2i(int(profile.width)-1,int(profile.height)-1),"pixelMin":island.grid_min,"pixelMax":island.grid_min+island.grid_size-Vector2i.ONE,"sourceVertices":source_count,"vertices":island.grid_size.x*island.grid_size.y})
	# Commit only after all sources, sampled heights and meshes succeed.
	_free_meshes(_meshes)
	_meshes = candidates
	_profiles = profiles.duplicate(true)
	_materials = materials.duplicate()
	_sampler = height_sampler
	_geometry_builds += candidates.size()
	_vertex_count = vertices
	_source_vertex_count = source_vertices
	_triangle_count = triangles
	_render_bounds = candidate_bounds
	return true

static func _render_window(profile: Dictionary) -> Rect2i:
	return ReferenceProfile.target_render_window(profile)

func _build_mesh(profile: Dictionary, sampler: Callable, material: Material) -> IslandMesh:
	var window := _render_window(profile)
	var width := window.size.x
	var height := window.size.y
	var center: Vector2 = Coordinates._vector2(profile.islandCenter)
	var source_center: Vector2 = Coordinates._vector2(profile.sourceCenter)
	var axes := Coordinates.source_axes(profile)
	var column_axis: Vector2 = axes.column
	var row_axis: Vector2 = axes.row
	var scale := float(profile.scale)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	var heights := PackedFloat32Array()
	vertices.resize(width*height)
	normals.resize(width*height)
	uv.resize(width*height)
	heights.resize(width*height)
	indices.resize((width-1)*(height-1)*6)
	for row in height:
		for column in width:
			var index := row*width+column
			# Same rigid map as Coordinates.source_pixel_to_world. Rebase before
			# converting to final float32 render coordinates, then sample exactly
			# those coordinates, so port adaptations and other height owners agree.
			var source_column := column+window.position.x
			var source_row := row+window.position.y
			var offset := (column_axis*(float(source_column)-source_center.x)+row_axis*(float(source_row)-source_center.y))*scale
			var world := center+offset
			_sample_calls += 1
			var h := float(sampler.call(world.x,world.y))
			if not is_finite(h):
				return null
			vertices[index] = Vector3(offset.x,h,offset.y)
			heights[index] = h
			uv[index] = Vector2((float(source_column)+.5)/float(profile.width),(float(source_row)+.5)/float(profile.height))
	for row in height:
		for column in width:
			var index := row*width+column
			var tangent_x := vertices[row*width+mini(column+1,width-1)]-vertices[row*width+maxi(column-1,0)]
			var tangent_y := vertices[mini(row+1,height-1)*width+column]-vertices[maxi(row-1,0)*width+column]
			var normal := tangent_x.cross(tangent_y).normalized()
			normals[index] = normal if normal.y >= 0.0 else -normal
	var cursor := 0
	for row in height-1:
		for column in width-1:
			var a := row*width+column
			var b := a+width
			var c := a+1
			var d := b+1
			# The source/world map reverses image handedness; these are clockwise
			# fronts in Godot while retaining the source alternating diagonals.
			var cell := PackedInt32Array([a,b,d,a,d,c]) if ((column+window.position.x) ^ (row+window.position.y)) & 1 else PackedInt32Array([a,b,c,b,d,c])
			for value: int in cell:
				indices[cursor] = value
				cursor += 1
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	var source_mesh := ArrayMesh.new()
	source_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var instance := IslandMesh.new()
	instance.name = "StaticSourceIsland_"+str(profile.id)
	instance.position = Vector3(center.x,0.0,center.y)
	instance.mesh = source_mesh
	instance.material_override = material
	instance.mapping = profile.duplicate(true)
	instance.source_width = int(profile.width)
	instance.source_height = int(profile.height)
	instance.grid_min = window.position
	instance.grid_size = window.size
	instance.heights = heights
	instance.set_meta("source_profile",str(profile.id))
	return instance

func get_meshes() -> Array[MeshInstance3D]:
	return _meshes.duplicate()

func sample_mesh_height(world_x: float, world_z: float) -> float:
	var height := -INF
	for island: MeshInstance3D in _meshes:
		var h: float = island.sample_mesh_height(world_x,world_z)
		if is_finite(h):
			height = maxf(height,h)
	return height if is_finite(height) else NAN

func supports(center: Vector2, radius: float) -> bool:
	if not center.is_finite() or not is_finite(radius) or radius < 0.0:
		return false
	for index in _profiles.size():
		var profile: Dictionary = _profiles[index]
		var bounds: Dictionary = _render_bounds[index]
		var pixel := Coordinates.world_to_source_pixel(center,profile)
		var closest := pixel.clamp(Vector2(bounds.pixelMin),Vector2(bounds.pixelMax))
		if pixel.distance_to(closest)*float(profile.scale) <= radius:
			return true
	return false

func diagnostics() -> Dictionary:
	return {"meshCount":_meshes.size(), "geometry_builds":_geometry_builds,
		"vertices":_vertex_count, "sourceVertices":_source_vertex_count, "triangles":_triangle_count, "sampleCalls":_sample_calls,
		"renderBounds":_render_bounds.duplicate(true), "nativePixelSpacing":1,
		"sourceProfiles":_profiles.duplicate(true), "collisionBodies":0,
		"scope":"Immutable original source-pixel topology mapped to retained height authority; neighbor normals, native UV centers, no moving chunk generator or physics mutation."}

static func _free_meshes(meshes: Array[MeshInstance3D]) -> void:
	for island: MeshInstance3D in meshes:
		if is_instance_valid(island):
			island.dispose()
			island.free()
	meshes.clear()

func dispose() -> void:
	_free_meshes(_meshes)
	_profiles.clear()
	_materials.clear()
	_sampler = Callable()
	_vertex_count = 0
	_source_vertex_count = 0
	_triangle_count = 0
	_render_bounds.clear()
