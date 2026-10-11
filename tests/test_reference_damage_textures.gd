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
	view.configure("voc")
	view.apply_snapshot({"id": "probe", "time": 1.0, "hull": 60.0, "sail": 63.0}, {}, 0.0)
	var sail := view.get_model().find_child("sail_01", true, false) as MeshInstance3D
	check(sail.material_override.get_shader_parameter("use_reference_damage") == true, "actual valid PNG replaces fallback sail mask")
	if sail.material_override.get_shader_parameter("use_reference_damage") == true:
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
	healthy.configure("voc")
	healthy.apply_snapshot({"id": "clean", "time": 1.0, "hull": 100.0, "sail": 100.0}, {}, 0.0)
	var clean_sail := healthy.get_model().find_child("sail_01", true, false) as MeshInstance3D
	for kind in ["fuchuan", "fisherman", "merchant", "voc", "patrol", "heavy"]:
		view.configure(kind)
		for row: Array in [[100.0, 100.0, 0, 0], [80.0, 63.0, 20, 20], [60.0, 52.0, 40, 40], [40.0, 28.0, 60, 60], [20.0, 4.0, 80, 80], [0.0, 0.0, 100, 80]]:
			view.apply_snapshot({"id": kind, "time": 2.0, "hull": row[0], "sail": row[1]}, {}, 0.0)
			for distance in [0.0, 300.0, 800.0]:
				view.set_lod_distance(distance)
				var model: Node3D = view.get_model()
				var hull := model.find_child("hull", true, false) as MeshInstance3D
				_check_texture(hull, "hull", row[2])
				for sail: MeshInstance3D in model.find_children("sail_*", "MeshInstance3D", true, false):
					_check_texture(sail, "sail", row[3])
					check(sail.material_override != clean_sail.material_override, "damaged material cannot mutate another ship")
	check(clean_sail.material_override.get_shader_parameter("use_reference_damage") == false, "healthy shared GLB stays intact after other ship texture changes")
	healthy.dispose()
	healthy.free()

func _check_texture(mesh: MeshInstance3D, surface: String, suffix: int) -> void:
	var material: ShaderMaterial = mesh.material_override
	check(material.get_shader_parameter("use_reference_damage") == (suffix > 0), "zero stage uses intact colors, damaged stages use reference")
	if suffix > 0:
		var texture: Texture2D = material.get_shader_parameter("reference_damage")
		check(texture != null and texture.resource_path == TEXTURES + "ship_%s_damage%03d.dds.png" % [surface, suffix], "quantized stage binds exact reference texture across LOD")
		if texture != null:
			check(texture.get_image().has_mipmaps(), "reference texture imported with mipmaps")

func _test_missing() -> void:
	var library = load("res://modules/scene_engine/assets/asset_library.gd").new()
	var model: Node3D = library.instantiate_model("res://assets/models/ships/voc-lod0.glb")
	root.add_child(model)
	var helper = load("res://game/presentation/ships/ship_damage.gd").new()
	var models: Array[Node3D] = [model]
	helper.configure(models, "res://assets/absent_reference_masks/")
	helper.apply_snapshot({"hull": 20.0, "sail": 4.0}, 1.0)
	var sail := model.find_child("sail_01", true, false) as MeshInstance3D
	check(sail.material_override.get_shader_parameter("use_reference_damage") == false, "missing PNG keeps organic procedural fallback")
	check(int(sail.material_override.get_shader_parameter("tear_count")) > 0, "missing reference still has finite tear clusters")
	helper.dispose()
	model.free()
	library.dispose()
