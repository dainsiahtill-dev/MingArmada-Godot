extends RefCounted
## Caches immutable PackedScenes; every consumer owns fresh nodes and skeletons.

var _scenes: Dictionary = {}
var _disposed := false

func instantiate_model(path: String) -> Node3D:
	if _disposed or not path.begins_with("res://assets/models/"):
		return null
	if not _scenes.has(path):
		# Exported projects may store only Godot's imported PackedScene. Runtime
		# authoring uses original GLB bytes; both paths retain separate skeletons.
		if not FileAccess.file_exists(path):
			if not ResourceLoader.exists(path):
				return null
			var imported = load(path)
			if not imported is PackedScene:
				return null
			_scenes[path] = imported
			var exported_instance := imported.instantiate() as Node3D
			_enable_authored_colors(exported_instance)
			return exported_instance
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		if document.append_from_file(path, state) != OK:
			return null
		var model := document.generate_scene(state)
		if model == null:
			return null
		_enable_authored_colors(model)
		var packed := PackedScene.new()
		var error := packed.pack(model)
		model.free()
		if error != OK:
			return null
		_scenes[path] = packed
	return _scenes[path].instantiate() as Node3D

func _enable_authored_colors(node: Node) -> void:
	if node is MeshInstance3D and node.mesh:
		for surface in node.mesh.get_surface_count():
			var material = node.mesh.surface_get_material(surface)
			if material is StandardMaterial3D and node.mesh.surface_get_format(surface) & Mesh.ARRAY_FORMAT_COLOR:
				# glTF COLOR_0 stores authored ship/sailor colors. Runtime import in
				# Godot 4.7.2 leaves this flag off, producing pale uncolored models.
				material.vertex_color_use_as_albedo = true
	for child in node.get_children():
		_enable_authored_colors(child)

func get_cached_count() -> int:
	return _scenes.size()

func dispose() -> void:
	_disposed = true
	if has_meta("reference_ship_provider"):
		get_meta("reference_ship_provider").dispose()
		remove_meta("reference_ship_provider")
	_scenes.clear()
