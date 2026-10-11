extends SceneTree

func _initialize() -> void:
	var mesh := PlaneMesh.new()
	var arrays := mesh.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var cross := (vertices[indices[1]] - vertices[indices[0]]).cross(vertices[indices[2]] - vertices[indices[0]])
	print("NATIVE_PLANE_FRONT_FACE cross=", cross, " normal=", arrays[Mesh.ARRAY_NORMAL][indices[0]])
	quit()
