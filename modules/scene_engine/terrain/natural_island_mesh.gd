extends Node3D
## One finite presentation mesh from an immutable, numeric island grid.
## Owns its mesh child; no terrain authority, physics body, camera or clock.

const TerrainSurface = preload("res://modules/scene_engine/terrain/terrain_chunk.gd")
const FidelityMaterial = preload("res://modules/scene_engine/fidelity_island/terrain_material.gd")
const SurfaceShader = preload("res://modules/scene_engine/terrain/natural_island_surface.gdshader")
const CausticsTexture = preload("res://assets/textures/pirates_reference/duel_waterdetail.dds.png")
const BED_HEIGHT := -24.0
const MAX_GRID_SIDE := 1025
const OPTION_NAMES := ["caustics", "texture_world_scale"]
var _surface: MeshInstance3D
var _bounds := Rect2()
var _side := 0
var _heights := PackedFloat32Array()
var _configured := false
var _caustics := true

func configure(field: RefCounted, material: ShaderMaterial = null, options: Dictionary = {}) -> bool:
	if _configured or field == null or not field.has_method("get_grid"):
		return false
	for key: Variant in options:
		if not key is String or key not in OPTION_NAMES:
			return false
	var caustics: Variant = options.get("caustics", true)
	var texture_scale: Variant = options.get("texture_world_scale", 0.025)
	if not caustics is bool or not _finite_number(texture_scale) or float(texture_scale) <= 0.0 or float(texture_scale) > 1.0:
		return false
	if material != null and material.shader != SurfaceShader:
		return false
	var grid: Variant = field.call("get_grid")
	if not grid is Dictionary or not _valid_grid(grid):
		return false
	var next_material := create_material() if material == null else material
	if next_material == null:
		return false
	var bounds: Rect2 = grid.bounds
	var side: int = grid.side
	var heights: PackedFloat32Array = grid.heights.duplicate()
	var next_mesh := _build_mesh(bounds, side, heights)
	if next_mesh == null:
		return false
	# Nothing has been published or mutated before the full grid/material pass.
	var surface := TerrainSurface.new()
	surface.name = "NaturalIslandSurface"
	surface.mesh = next_mesh
	surface.material_override = next_material
	next_material.set_shader_parameter("texture_world_scale", float(texture_scale))
	next_material.set_shader_parameter("u_caustics", caustics)
	next_material.set_shader_parameter("caustics_enabled", caustics)
	add_child(surface)
	_surface = surface
	_bounds = bounds
	_side = side
	_heights = heights
	_caustics = caustics
	_configured = true
	return true

static func create_material() -> ShaderMaterial:
	# Borrow only read-only original DDS textures and source sand colors.
	# The natural field has no relationship to Cat's recovered BHI/normal map.
	var original := FidelityMaterial.create_material({}, {"material_kind":"game_adapted", "id":"natural"})
	if original == null:
		return null
	var material := ShaderMaterial.new()
	material.shader = SurfaceShader
	material.set_shader_parameter("reference_caustics_texture",CausticsTexture)
	for texture_name: String in FidelityMaterial.TEXTURE_UNIFORMS.values():
		var texture: Variant = original.get_shader_parameter(texture_name)
		if not texture is Texture2D:
			return null
		material.set_shader_parameter(texture_name, texture)
	for color_name: String in ["native_sand_color", "native_wet_color"]:
		material.set_shader_parameter(color_name, original.get_shader_parameter(color_name))
	material.set_shader_parameter("u_time", 0.0)
	material.set_shader_parameter("simulation_time", 0.0)
	material.set_shader_parameter("wave_count", 0)
	material.set_shader_parameter("wave_components", PackedVector4Array())
	material.set_meta("natural_island_material_kind", "authored_height_slope_original_textures")
	material.set_meta("original_mip_registry", FidelityMaterial.MANIFEST_PATH)
	material.set_meta("original_material_source", original.get_meta("fidelity_island_source", ""))
	return material

func get_mesh() -> MeshInstance3D:
	return _surface if is_instance_valid(_surface) else null

func sample_height(world_x: float, world_z: float) -> float:
	if _side < 2 or not is_instance_valid(_surface) or not is_finite(world_x) or not is_finite(world_z):
		return NAN
	# Presentation is horizontal. Translation is supported, rotations/scaling
	# would change the meaning of this world-height API and are not configured.
	var origin: Vector3 = global_position if is_inside_tree() else position
	var point := Vector2(world_x-origin.x, world_z-origin.z)
	var end := _bounds.end
	if point.x < _bounds.position.x or point.x > end.x or point.y < _bounds.position.y or point.y > end.y:
		return BED_HEIGHT+origin.y
	var pixel := (point-_bounds.position)/_bounds.size*float(_side-1)
	var column := mini(int(floor(pixel.x)), _side-2)
	var row := mini(int(floor(pixel.y)), _side-2)
	var x := pixel.x-float(column)
	var z := pixel.y-float(row)
	var a := row*_side+column
	var c := a+_side
	var ah: float = _heights[a]
	var bh: float = _heights[a+1]
	var ch: float = _heights[c]
	var dh: float = _heights[c+1]
	# Same a/b/c, c/b/d diagonal as the actual clockwise mesh triangles.
	var height := ah+(bh-ah)*x+(ch-ah)*z if x+z <= 1.0 else dh+(ch-dh)*(1.0-x)+(bh-dh)*(1.0-z)
	return height+origin.y

func sync_surface_state(ocean_material: ShaderMaterial, state: Dictionary = {}) -> bool:
	if not is_instance_valid(_surface):
		return false
	var next_state := state.duplicate()
	if not _caustics:
		next_state["caustics"] = false
	return _surface.sync_surface_state(ocean_material, next_state)

func dispose() -> void:
	if is_instance_valid(_surface):
		_surface.dispose()
		_surface.free()
	_surface = null
	_heights.clear()
	_bounds = Rect2()
	_side = 0
	_caustics = true
	# Disposed presentation cannot accidentally be resurrected by configuration.
	_configured = true

func _valid_grid(grid: Dictionary) -> bool:
	if not grid.get("bounds") is Rect2 or not grid.get("side") is int or not grid.get("heights") is PackedFloat32Array:
		return false
	var bounds: Rect2 = grid.bounds
	var side: int = grid.side
	if not bounds.position.is_finite() or not bounds.size.is_finite() or not bounds.end.is_finite() or bounds.size.x <= 0.0 or bounds.size.y <= 0.0 or side < 2 or side > MAX_GRID_SIDE:
		return false
	var heights: PackedFloat32Array = grid.heights
	if heights.size() != side*side:
		return false
	for height: float in heights:
		if not is_finite(height):
			return false
	# Boundary must meet the surrounding mean-depth bed continuously.
	for coordinate: int in side:
		if heights[coordinate] != BED_HEIGHT or heights[(side-1)*side+coordinate] != BED_HEIGHT or heights[coordinate*side] != BED_HEIGHT or heights[coordinate*side+side-1] != BED_HEIGHT:
			return false
	return true

func _build_mesh(bounds: Rect2, side: int, heights: PackedFloat32Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	vertices.resize(side*side)
	normals.resize(side*side)
	uv.resize(side*side)
	indices.resize((side-1)*(side-1)*6)
	var step := bounds.size/float(side-1)
	if not step.is_finite() or step.x <= 0.0 or step.y <= 0.0:
		return null
	for row: int in side:
		for column: int in side:
			var index := row*side+column
			var coordinate := bounds.position+Vector2(float(column)*step.x, float(row)*step.y)
			if not coordinate.is_finite():
				return null
			vertices[index] = Vector3(coordinate.x, heights[index], coordinate.y)
			var left := maxi(column-1,0)
			var right := mini(column+1,side-1)
			var above := maxi(row-1,0)
			var below := mini(row+1,side-1)
			var dx := (heights[row*side+right]-heights[row*side+left])/(float(right-left)*step.x)
			var dz := (heights[below*side+column]-heights[above*side+column])/(float(below-above)*step.y)
			var gradient := Vector3(-dx,1.0,-dz)
			if not gradient.is_finite():
				return null
			var normal := gradient.normalized()
			if not normal.is_finite() or normal.y <= 0.0 or absf(normal.length_squared()-1.0) > 0.00001:
				return null
			normals[index] = normal
			uv[index] = Vector2(float(column),float(row))/float(side-1)
	for row: int in side-1:
		for column: int in side-1:
			var a := row*side+column
			var c := a+side
			var offset := (row*(side-1)+column)*6
			indices[offset] = a
			indices[offset+1] = a+1
			indices[offset+2] = c
			indices[offset+3] = c
			indices[offset+4] = a+1
			indices[offset+5] = c+1
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result

func _finite_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))
