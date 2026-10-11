extends MeshInstance3D
## A bounded chunk built from an injected authority. Collision uses this same mesh.

const LAYER_HEIGHTS := [-50.0, -35.0, -5.0, 2.0, 10.0, 60.0, 100.0, 140.0]
const LAYER_COLORS := ["002b4d", "002b4d", "8b7d6b", "e6dabf", "597d3e", "284024", "5a5552", "888888"]
var _body: StaticBody3D
var _sample: Callable
var _linear_colors: Array[Color] = []

func configure(sampler: Callable, coordinate: Vector2i, size: float = 250.0, resolution: int = 32, collision: bool = true) -> bool:
	if not sampler.is_valid() or not is_finite(size) or size <= 0.0:
		return false
	_sample = sampler
	position = Vector3(coordinate.x * size, 0.0, coordinate.y * size)
	resolution = clampi(resolution, 4, 128)
	_linear_colors.clear()
	for color: String in LAYER_COLORS:
		_linear_colors.append(Color.html(color).srgb_to_linear())
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var step := size / resolution
	for row in resolution + 1:
		for column in resolution + 1:
			var x := column * step - size * 0.5
			var z := row * step - size * 0.5
			var wx := x + position.x
			var wz := z + position.z
			var height := float(_sample.call(wx, wz))
			if not is_finite(height):
				return false
			vertices.append(Vector3(x, height, z))
			var dx := float(_sample.call(wx + 0.5, wz)) - float(_sample.call(wx - 0.5, wz))
			var dz := float(_sample.call(wx, wz + 0.5)) - float(_sample.call(wx, wz - 0.5))
			normals.append(Vector3(-dx, 1.0, -dz).normalized())
			colors.append(get_biome_color(height))
	for row in resolution:
		for column in resolution:
			var a := row * (resolution + 1) + column
			var b := a + resolution + 1
			# Godot fronts are clockwise, opposite the original Three geometry.
			indices.append_array(PackedInt32Array([a, a + 1, b, b, a + 1, b + 1]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var terrain_mesh := ArrayMesh.new()
	terrain_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = terrain_mesh
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = false
	material.roughness = 0.9
	material.metallic = 0.1
	material_override = material
	if is_instance_valid(_body):
		_body.free()
	if collision:
		_body = StaticBody3D.new()
		var shape := CollisionShape3D.new()
		shape.shape = mesh.create_trimesh_shape()
		_body.add_child(shape)
		add_child(_body)
	return true

func get_biome_color(height: float) -> Color:
	if _linear_colors.is_empty():
		for color: String in LAYER_COLORS:
			_linear_colors.append(Color.html(color).srgb_to_linear())
	if height <= LAYER_HEIGHTS[0]:
		return _linear_colors[0]
	for index in LAYER_HEIGHTS.size() - 1:
		if height <= LAYER_HEIGHTS[index + 1]:
			var t := smoothstep(LAYER_HEIGHTS[index], LAYER_HEIGHTS[index + 1], height)
			return _linear_colors[index].lerp(_linear_colors[index + 1], t)
	return _linear_colors.back()

func get_collision_body() -> StaticBody3D:
	return _body

func dispose() -> void:
	if is_instance_valid(_body):
		_body.free()
	_body = null
	mesh = null
	material_override = null
	_sample = Callable()
