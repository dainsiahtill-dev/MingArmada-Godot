extends SceneTree

const Terrain = preload("res://modules/scene_engine/terrain/terrain_chunk.gd")
var failures := 0

func _initialize() -> void:
	var native := PlaneMesh.new().get_mesh_arrays()
	var native_vertices: PackedVector3Array = native[Mesh.ARRAY_VERTEX]
	var native_indices: PackedInt32Array = native[Mesh.ARRAY_INDEX]
	var native_cross := (native_vertices[native_indices[1]] - native_vertices[native_indices[0]]).cross(native_vertices[native_indices[2]] - native_vertices[native_indices[0]])
	var terrain := Terrain.new()
	terrain.configure(func(_x: float, _z: float) -> float: return 4.0, Vector2i.ZERO, 100.0, 4, false)
	var data: Array = terrain.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = data[Mesh.ARRAY_INDEX]
	for triangle in range(0, indices.size(), 3):
		var cross := (vertices[indices[triangle + 1]] - vertices[indices[triangle]]).cross(vertices[indices[triangle + 2]] - vertices[indices[triangle]])
		if cross.dot(native_cross) <= 0.0: failures += 1
	terrain.free()
	print("SCENE_GEOMETRY_TESTS triangles=", indices.size() / 3, " failures=", failures)
	quit(1 if failures else 0)
