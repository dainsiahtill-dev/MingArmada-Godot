extends RefCounted
## Geometry exported from original author functions; native MultiMesh rendering.

var _meshes: Dictionary = {}

func get_mesh(type: String) -> ArrayMesh:
	if _meshes.has(type):
		return _meshes[type]
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/reference/vegetation-geometry.json"))
	if not fixture.geometry.has(type):
		return null
	var data: Dictionary = fixture.geometry[type]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for index in range(0, data.positions.size(), 3):
		vertices.append(Vector3(data.positions[index], data.positions[index + 1], data.positions[index + 2]))
		normals.append(Vector3(data.normals[index], data.normals[index + 1], data.normals[index + 2]))
		if not data.colors.is_empty():
			colors.append(Color(data.colors[index], data.colors[index + 1], data.colors[index + 2]))
	var indices := PackedInt32Array(data.indices)
	# Three glTF authoring is CCW; Godot uses clockwise front faces.
	for index in range(0, indices.size(), 3):
		var swap := indices[index + 1]
		indices[index + 1] = indices[index + 2]
		indices[index + 2] = swap
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	if not colors.is_empty():
		arrays[Mesh.ARRAY_COLOR] = colors
	if not indices.is_empty():
		arrays[Mesh.ARRAY_INDEX] = indices
	var geometry := ArrayMesh.new()
	geometry.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = not colors.is_empty()
	material.vertex_color_is_srgb = false
	material.albedo_color = Color.html("557a40") if type == "palm" else Color.WHITE
	material.roughness = 0.8 if type == "palm" else 0.95
	material.cull_mode = BaseMaterial3D.CULL_DISABLED if type in ["palm", "grass"] else BaseMaterial3D.CULL_BACK
	geometry.surface_set_material(0, material)
	_meshes[type] = geometry
	return geometry

func populate(parent: Node3D, sampler: Callable, coordinate: Vector2i, size: float, resolution: int, exclusions: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(coordinate.x) * 8191 + int(coordinate.y) * 131071 + 1650
	var instances := {"palm": [], "broadleaf": [], "grass": []}
	var count := 0
	for row in resolution + 1:
		for column in resolution + 1:
			if count >= 64:
				break
			var x := (float(column) / resolution - 0.5) * size
			var z := (float(row) / resolution - 0.5) * size
			var wx := x + coordinate.x * size
			var wz := z + coordinate.y * size
			var height := float(sampler.call(wx, wz))
			if not is_finite(height) or height <= 0.3 or height >= 90.0 or rng.randf() > 0.06:
				continue
			# Authored reference islands have real cliffs and narrow ridge shoulders.
			# Preserve source tree geometry, but require stable soil for its roots.
			var slope_x: float=(float(sampler.call(wx+0.75,wz))-float(sampler.call(wx-0.75,wz)))/1.5
			var slope_z: float=(float(sampler.call(wx,wz+0.75))-float(sampler.call(wx,wz-0.75)))/1.5
			if not is_finite(slope_x) or not is_finite(slope_z) or slope_x*slope_x+slope_z*slope_z>0.49:
				continue
			var excluded := false
			for port: Dictionary in exclusions:
				if Vector2(wx - float(port.x), wz - float(port.z)).length() < 65.0:
					excluded = true
			if excluded:
				continue
			var type := "palm" if height >= 2.0 else "grass"
			var roll := rng.randf()
			if height > 3.0 and roll > 0.83:
				type = "broadleaf"
			elif roll > 0.92:
				type = "grass"
			var basis := Basis.from_euler(Vector3(rng.randf_range(-0.125, 0.125), rng.randf() * TAU, rng.randf_range(-0.1, 0.1)))
			basis = basis.scaled(Vector3.ONE * rng.randf_range(0.8, 1.4))
			instances[type].append(Transform3D(basis, Vector3(x, height, z)))
			count += 1
	for type: String in instances:
		var transforms: Array = instances[type]
		if transforms.is_empty():
			continue
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = get_mesh(type)
		multimesh.instance_count = transforms.size()
		for index in transforms.size():
			multimesh.set_instance_transform(index, transforms[index])
		var node := MultiMeshInstance3D.new()
		node.name = type + "_vegetation"
		node.multimesh = multimesh
		parent.add_child(node)
