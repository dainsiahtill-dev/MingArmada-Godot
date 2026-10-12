extends SceneTree

var failures: Array[String] = []
var assertions := 0
const TEXTURES := "res://assets/textures/pirates_damage_reference/"

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var manifest_path := "res://assets/provenance/pirates-damage-reference.json"
	check(FileAccess.file_exists(manifest_path), "exact source damage texture provenance exists")
	if FileAccess.file_exists(manifest_path):
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		check(manifest.files.size() == 11, "all six hull and five sail masks preserved")
		for entry: Dictionary in manifest.files:
			check(FileAccess.file_exists("res://" + entry.target), "reference PNG copied: " + entry.target)
			check(FileAccess.get_sha256("res://" + entry.target) == entry.sha256, "target keeps exact original PNG bytes")
	var script = load("res://game/presentation/ships/ship_view.gd")
	var view = script.new()
	root.add_child(view)
	check(view.configure("voc"), "actual source ship loads for reference texture probe")
	view.apply_snapshot({"id": "probe", "time": 1.0, "hull": 60.0, "sail": 63.0}, {}, 0.0)
	for sail: MeshInstance3D in _damage_meshes(view.get_model(), "sail"):
		for material: ShaderMaterial in _checked_materials(sail):
			check(material.get_shader_parameter("use_reference_damage") == true, "actual valid PNG replaces fallback sail mask")
	_test_bindings(view, script)
	_test_missing()
	view.dispose()
	view.free()
	for failure in failures:
		printerr("FAIL: ", failure)
	print("REFERENCE_DAMAGE_TEXTURES assertions=", assertions, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _test_bindings(view, script) -> void:
	var healthy = script.new()
	root.add_child(healthy)
	for kind in ["fuchuan", "fisherman", "merchant", "voc", "patrol", "heavy"]:
		check(view.configure(kind), "actual damaged source ship loads: " + kind)
		check(healthy.configure(kind), "independent healthy source ship loads: " + kind)
		healthy.apply_snapshot({"id": "clean-" + kind, "time": 1.0, "hull": 100.0, "sail": 100.0}, {}, 0.0)
		var clean_materials: Array[ShaderMaterial] = []
		for distance in [0.0, 300.0, 800.0]:
			healthy.set_lod_distance(distance)
			for role in ["hull", "sail"]:
				for mesh: MeshInstance3D in _damage_meshes(healthy.get_model(), role):
					clean_materials.append_array(_check_texture(mesh, role, 0))
		check(not clean_materials.is_empty(), "healthy comparison checks actual material slots: " + kind)
		for row: Array in [[100.0, 100.0, 0, 0], [80.0, 63.0, 20, 20], [60.0, 52.0, 40, 40], [40.0, 28.0, 60, 60], [20.0, 4.0, 80, 80], [0.0, 0.0, 100, 80]]:
			view.apply_snapshot({"id": kind, "time": 2.0, "hull": row[0], "sail": row[1]}, {}, 0.0)
			for distance in [0.0, 300.0, 800.0]:
				view.set_lod_distance(distance)
				var model: Node3D = view.get_model()
				for role in ["hull", "sail"]:
					for mesh: MeshInstance3D in _damage_meshes(model, role):
						for material: ShaderMaterial in _check_texture(mesh, role, row[2] if role == "hull" else row[3]):
							check(not clean_materials.has(material), "damaged material cannot mutate another ship")
		for distance in [0.0, 300.0, 800.0]:
			healthy.set_lod_distance(distance)
			for role in ["hull", "sail"]:
				for mesh: MeshInstance3D in _damage_meshes(healthy.get_model(), role):
					for material: ShaderMaterial in _checked_materials(mesh):
						check(material.get_shader_parameter("use_reference_damage") == false, "healthy shared GLB stays intact after other ship texture changes")
	healthy.dispose()
	healthy.free()

func _damage_meshes(model: Node3D, role: String) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	check(model != null, "damage inspection has an actual model: " + role)
	if model == null: return result
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var name := String(mesh.name)
		# Source imports declare their role. Legacy GLBs retain the same naming
		# fallback as ShipDamage.configure; do not assume one hull/sail node.
		var fallback := "sail" if name.begins_with("sail_") else ("hull" if name == "hull" or name.begins_with("hull_") else "")
		if String(mesh.get_meta("damage_surface", fallback)) == role:
			result.append(mesh)
	check(not result.is_empty(), "every inspected model has damageable " + role + " surfaces")
	return result

func _checked_materials(mesh: MeshInstance3D) -> Array[ShaderMaterial]:
	var result: Array[ShaderMaterial] = []
	check(mesh != null and mesh.mesh != null, "damage surface owns a mesh")
	if mesh == null or mesh.mesh == null: return result
	check(mesh.mesh.get_surface_count() > 0, "damage mesh contains material slots: " + String(mesh.name))
	for index in mesh.mesh.get_surface_count():
		var active: Material = mesh.get_active_material(index)
		check(active is ShaderMaterial, "every damage material slot uses the shader: %s[%d]" % [mesh.name, index])
		if not active is ShaderMaterial: continue
		result.append(active as ShaderMaterial)
	return result

func _check_texture(mesh: MeshInstance3D, role: String, suffix: int) -> Array[ShaderMaterial]:
	var materials := _checked_materials(mesh)
	for material: ShaderMaterial in materials:
		check(material.get_shader_parameter("use_reference_damage") == (suffix > 0), "zero stage uses intact colors, damaged stages use reference")
		if suffix > 0:
			var texture: Variant = material.get_shader_parameter("reference_damage")
			check(texture is Texture2D and texture.resource_path == TEXTURES + "ship_%s_damage%03d.dds.png" % [role, suffix], "quantized stage binds exact reference texture across LOD")
			if texture is Texture2D:
				var image: Image = texture.get_image()
				check(image != null and image.has_mipmaps(), "reference texture imported with mipmaps")
	return materials

func _test_missing() -> void:
	var library = load("res://modules/scene_engine/assets/asset_library.gd").new()
	var legacy: Node3D = library.instantiate_model("res://assets/models/ships/voc-lod0.glb")
	var provider = load("res://modules/scene_engine/assets/ship_model_provider.gd").for_library(library)
	var source: Node3D = provider.instantiate_ship("voc", 0, library)
	var models: Array[Node3D] = []
	for model: Node3D in [legacy, source]:
		check(model != null, "missing-texture fallback loads legacy and current source models")
		if model != null:
			root.add_child(model)
			models.append(model)
	var helper = load("res://game/presentation/ships/ship_damage.gd").new()
	helper.configure(models, "res://assets/absent_reference_masks/")
	helper.apply_snapshot({"hull": 20.0, "sail": 4.0}, 1.0)
	for model: Node3D in models:
		for role in ["hull", "sail"]:
			for mesh: MeshInstance3D in _damage_meshes(model, role):
				for material: ShaderMaterial in _checked_materials(mesh):
					check(material.get_shader_parameter("use_reference_damage") == false, "missing PNG keeps organic procedural fallback")
					if role == "sail":
						check(int(material.get_shader_parameter("tear_count")) > 0, "missing reference still has finite tear clusters")
	helper.dispose()
	for model: Node3D in models: model.free()
	library.dispose()
