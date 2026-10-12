extends SceneTree
## Imported source textures must survive state-driven damage binding.
var failures: Array[String] = []
var assertions := 0
func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures.append(message)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var damage = load("res://game/presentation/ships/ship_damage.gd").new()
	var model := Node3D.new()
	root.add_child(model)
	var mesh := ArrayMesh.new()
	var source_materials: Array[StandardMaterial3D] = []
	for index in 2:
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		for point in [Vector3.ZERO, Vector3.RIGHT, Vector3.FORWARD]:
			tool.set_uv(Vector2(point.x, -point.z)); tool.add_vertex(point + Vector3.UP * index)
		var original := StandardMaterial3D.new()
		var pixels := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		pixels.fill(Color(0.2 + index * 0.3, 0.3, 0.4, 1.0))
		original.albedo_texture = ImageTexture.create_from_image(pixels)
		original.albedo_color = Color(0.7, 0.8, 0.9, 1.0)
		original.uv1_scale = Vector3(2, 3, 1)
		original.uv1_offset = Vector3(0.1, 0.2, 0)
		tool.set_material(original); tool.commit(mesh); source_materials.append(original)
	var hull := MeshInstance3D.new(); hull.name = "hull"; hull.mesh = mesh; model.add_child(hull)
	var models: Array[Node3D] = [model]
	damage.configure(models)
	damage.apply_snapshot({"hull": 60.0, "maxHull": 100.0, "sail": 100.0, "maxSail": 100.0}, 1.0)
	check(hull.material_override == null, "multi-surface hull retains separate source materials")
	for index in 2:
		var bound = hull.get_surface_override_material(index)
		check(bound is ShaderMaterial, "each imported hull surface accepts damage")
		if bound is ShaderMaterial:
			check(bound.get_shader_parameter("original_albedo") == source_materials[index].albedo_texture, "damage retains each source albedo texture")
			check(bound.get_shader_parameter("use_original_albedo") == true, "source albedo remains enabled")
			check(bound.get_shader_parameter("original_uv_scale") == Vector2(2, 3), "source UV scale survives damage binding")
			check(bound.get_shader_parameter("original_uv_offset") == Vector2(0.1, 0.2), "source UV offset survives damage binding")
			check(bound.get_shader_parameter("damage_stage") == 2.0, "damage updates every source surface")
	damage.dispose()
	for index in 2:
		check(hull.get_active_material(index) == source_materials[index], "disposing damage restores original imported material slots")
	model.free()
	_test_fixed_rig()
	print("SHIP_DAMAGE_MATERIALS assertions=", assertions, " failures=", failures.size())
	for failure in failures: printerr(failure)
	quit(0 if failures.is_empty() else 1)

func _test_fixed_rig() -> void:
	var model := Node3D.new(); root.add_child(model)
	var mast := Node3D.new(); mast.name = "mast_01"; mast.position = Vector3(0, 1, 2)
	mast.set_meta("sail_trim_origin", 0.0); model.add_child(mast)
	var stern_flag := Node3D.new(); stern_flag.name = "flag_stern"; stern_flag.position = Vector3(0, 3, -6)
	stern_flag.set_meta("source_fixed_attachment", true); model.add_child(stern_flag)
	var helper = load("res://game/presentation/ships/ship_damage.gd").new()
	var models: Array[Node3D] = [model]; helper.configure(models)
	var healthy := {"hull":100.0, "sail":100.0, "sailAngle":0.0}
	helper.apply_snapshot(healthy, 1.0, true)
	check(mast.basis.is_equal_approx(Basis.IDENTITY), "native zero trim preserves original mast rest basis")
	var flag_rest := stern_flag.transform
	helper.apply_snapshot({"hull":100.0, "sail":0.0}, 2.0, true)
	helper.apply_snapshot({"hull":100.0, "sail":0.0}, 3.0, true)
	check(not mast.basis.is_equal_approx(Basis.IDENTITY), "real mast still falls from authoritative sail loss")
	check(stern_flag.transform.is_equal_approx(flag_rest), "fixed stern attachment cannot fall with a nearby unrelated mast")
	helper.dispose(); model.free()
