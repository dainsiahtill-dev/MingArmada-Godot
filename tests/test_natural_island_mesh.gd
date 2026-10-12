extends SceneTree

const SURFACE_PATH := "res://modules/scene_engine/terrain/natural_island_mesh.gd"
const FidelityMaterial = preload("res://modules/scene_engine/fidelity_island/terrain_material.gd")
var assertions := 0
var failures := 0

class GridField extends RefCounted:
	var calls := 0
	var bounds := Rect2(-2.0, -2.0, 4.0, 4.0)
	var side := 3
	var heights := PackedFloat32Array([-24.0, -24.0, -24.0, -24.0, 6.0, -24.0, -24.0, -24.0, -24.0])
	func get_grid() -> Dictionary:
		calls += 1
		return {"bounds":bounds, "side":side, "heights":heights}

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, reason: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", reason)

func close_to(actual: float, expected: float, reason: String, tolerance: float = 0.00001) -> void:
	check(is_finite(actual) and absf(actual-expected) <= tolerance, reason)

func _run() -> void:
	check(ResourceLoader.exists(SURFACE_PATH), "natural island has its independent finite mesh implementation")
	if not ResourceLoader.exists(SURFACE_PATH):
		_finish()
		return
	var surface_script: Script = load(SURFACE_PATH)
	if surface_script == null or not surface_script.can_instantiate():
		check(false, "natural island mesh script loads")
		_finish()
		return
	var field := GridField.new()
	var island = surface_script.new()
	check(island.configure(field), "one cached numeric grid builds real mesh with original material")
	var mesh_node: MeshInstance3D = island.get_mesh()
	check(mesh_node != null and mesh_node.mesh is ArrayMesh, "renderable child owns one indexed ArrayMesh")
	if mesh_node == null or mesh_node.mesh == null:
		island.free()
		_finish()
		return
	var arrays: Array = mesh_node.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	check(vertices.size() == 9 and indices.size() == 24, "full grid retains nine vertices and eight triangles without chunks")
	check(vertices[0] == Vector3(-2.0, -24.0, -2.0) and vertices[4] == Vector3(0.0, 6.0, 0.0) and vertices[8] == Vector3(2.0, -24.0, 2.0), "vertices preserve finite cached heights and complete bounds")
	var native_arrays := PlaneMesh.new().get_mesh_arrays()
	var native_vertices: PackedVector3Array = native_arrays[Mesh.ARRAY_VERTEX]
	var native_indices: PackedInt32Array = native_arrays[Mesh.ARRAY_INDEX]
	var front := (native_vertices[native_indices[1]]-native_vertices[native_indices[0]]).cross(native_vertices[native_indices[2]]-native_vertices[native_indices[0]])
	for triangle in range(0, indices.size(), 3):
		var normal := (vertices[indices[triangle+1]]-vertices[indices[triangle]]).cross(vertices[indices[triangle+2]]-vertices[indices[triangle]])
		check(normal.dot(front) > 0.0, "every triangle has Godot clockwise upward front")
	for normal: Vector3 in normals:
		check(normal.is_finite() and normal.y > 0.0 and absf(normal.length()-1.0) < 0.00001, "cached finite differences produce unit upward normals")
	check(mesh_node.get_child_count() == 0 and island.get_child_count() == 1, "presentation creates no collider, camera, or chunk subtree")
	# Nonplanar cell has three -24 vertices and one +6 vertex. Hand-derived
	# triangle heights differ from bilinear interpolation at these locations.
	close_to(island.sample_height(-1.5,-1.5), -24.0, "lower triangle stays flat instead of leaking the fourth corner")
	close_to(island.sample_height(-0.5,-0.5), -9.0, "upper triangle height equals visible triangle plane")
	close_to(island.sample_height(0.0,0.0), 6.0, "grid vertex sampler agrees with actual peak")
	close_to(island.sample_height(-0.2,-0.2), 0.0, "continuous sloping coast crosses mean sea level")
	close_to(island.sample_height(-0.1,-0.1), 3.0, "coast inland sample follows same triangle slope")
	close_to(island.sample_height(-1.0,-1.0), -24.0, "diagonal is continuous at both triangle endpoints")
	close_to(island.sample_height(-1.0+0.000001,-1.0), -24.0, "triangle boundary has no height seam", 0.0001)
	close_to(island.sample_height(2.0,0.0), -24.0, "last column is included in bounded sampler")
	close_to(island.sample_height(300.0,300.0), -24.0, "outside finite grid returns surrounding deep bed")
	check(is_nan(island.sample_height(NAN,0.0)), "nonfinite sample fails explicitly")
	field.heights[4] = 99.0
	close_to(island.sample_height(0.0,0.0), 6.0, "sampler cache remains identical to immutable rendered mesh")
	check(field.calls == 1, "mesh creation and later sampling consume numeric grid only once")
	var material := mesh_node.material_override as ShaderMaterial
	var caustic: Variant=material.get_shader_parameter("reference_caustics_texture")
	check(caustic is Texture2D and caustic==load("res://assets/textures/pirates_reference/duel_waterdetail.dds.png"),"natural seabed uses the actual reference caustic image instead of a rigid procedural polygon net")
	check(material != null, "natural surface has its own shader material")
	if material != null:
		var original := FidelityMaterial.create_material({}, {"material_kind":"game_adapted", "id":"natural"})
		check(original != null and material != original and material.shader != original.shader, "new surface is distinct from shared original terrain shader")
		if original != null:
			for texture_name: String in FidelityMaterial.TEXTURE_UNIFORMS.values():
				var texture: Texture2D = material.get_shader_parameter(texture_name)
				check(texture != null and texture == original.get_shader_parameter(texture_name), "new material uses actual original DDS texture resources")
				if texture != null:
					var image := texture.get_image()
					check(image != null and image.has_mipmaps() and image.get_format() in [Image.FORMAT_DXT1,Image.FORMAT_DXT3,Image.FORMAT_DXT5], "imported original compressed mip chain retained")
			check(material.get_shader_parameter("native_sand_color") == original.get_shader_parameter("native_sand_color") and material.get_shader_parameter("native_wet_color") == original.get_shader_parameter("native_wet_color"), "original sand colors copied without unrelated original BHI weights")
		check(material.get_meta("natural_island_material_kind", "") == "authored_height_slope_original_textures", "material status identifies authored natural height/slope adaptation")
		var names: Array[String] = []
		for uniform: Dictionary in material.shader.get_shader_uniform_list():
			names.append(str(uniform.name))
		check("u_time" in names and "u_clip" in names and not "source_weight_0" in names, "independent surface exposes scene clock and reflection clipping without Cat BHI")
		for mountain_control: String in ["rock_slope_start", "rock_slope_end", "slope_rock_strength", "ridge_rock_strength", "rock_pattern_world_scale", "rock_pattern_strength", "rock_forest_mix"]:
			check(mountain_control in names, "mountain grade, altitude strength, original texture mix and continuous world variation are independently tunable")
		var authored_controls := {"rock_slope_start":0.30, "rock_slope_end":0.60, "slope_rock_strength":0.85, "ridge_start":25.0, "ridge_end":40.0, "ridge_rock_strength":0.72, "rock_pattern_world_scale":0.05, "rock_pattern_strength":0.1, "rock_forest_mix":0.2}
		for control: String in authored_controls:
			material.set_shader_parameter(control,authored_controls[control])
		var old_shader_sha := FileAccess.get_sha256("res://modules/scene_engine/fidelity_island/terrain.gdshader")
		var ocean := ShaderMaterial.new()
		ocean.shader = load("res://modules/scene_engine/ocean/reference_game_water.gdshader")
		ocean.set_shader_parameter("u_time", 12.0)
		ocean.set_shader_parameter("u_waves", PackedVector4Array([Vector4(1,0,0.3,0.12), Vector4(0,1,0.2,0.15), Vector4(.6,.8,.1,.2), Vector4(.8,-.6,.05,.25)]))
		ocean.set_shader_parameter("u_speeds", Vector4(1.4,1.8,2.2,2.8))
		ocean.set_shader_parameter("u_strength", 0.8)
		check(island.sync_surface_state(ocean, {"time":23.0, "tide":0.2}), "existing ocean descriptor synchronizes explicit injected scene state")
		close_to(float(material.get_shader_parameter("u_time")),23.0,"terrain uses injected scene clock")
		close_to(float(material.get_shader_parameter("u_tide")),0.2,"terrain uses injected tide")
		check(int(material.get_shader_parameter("wave_count")) == 4, "old wave descriptor contract retained")
		for control: String in authored_controls:
			close_to(float(material.get_shader_parameter(control)),float(authored_controls[control]), "water state synchronization preserves independently tuned mountain material controls")
		check(not island.sync_surface_state(ocean, {"time":NAN}), "invalid clock rejected atomically")
		close_to(float(material.get_shader_parameter("u_time")),23.0,"bad clock does not change working surface")
		check(FileAccess.get_sha256("res://modules/scene_engine/fidelity_island/terrain.gdshader") == old_shader_sha, "original shared terrain shader remains unchanged by configuration")
	var saved_mesh := mesh_node.mesh
	check(not island.configure(GridField.new(), null, {"surprise":true}), "unknown options rejected")
	check(island.get_mesh() == mesh_node and mesh_node.mesh == saved_mesh, "failed configuration preserves working presentation atomically")
	check(not island.configure(GridField.new()), "successful configuration is one-time")
	var malformed := GridField.new()
	malformed.heights.resize(8)
	var rejected = surface_script.new()
	check(not rejected.configure(GridField.new(), null, {"unknown":true}) and rejected.get_child_count() == 0, "unknown option cannot consume configuration or publish child")
	check(not rejected.configure(GridField.new(), null, {"caustics":3}), "nonboolean caustics rejected")
	check(not rejected.configure(GridField.new(), null, {"texture_world_scale":NAN}), "nonfinite texture scale rejected")
	check(not rejected.configure(malformed) and rejected.get_child_count() == 0, "invalid grid length cannot publish partial mesh")
	malformed = GridField.new()
	malformed.heights[0] = NAN
	check(not rejected.configure(malformed) and rejected.get_child_count() == 0, "nonfinite grid cannot publish partial mesh")
	malformed = GridField.new()
	malformed.bounds = Rect2(0,0,0,4)
	check(not rejected.configure(malformed), "empty grid bounds rejected")
	malformed = GridField.new()
	malformed.heights[0] = -10.0
	check(not rejected.configure(malformed), "invalid perimeter cannot create a visible seam to surrounding deep bed")
	malformed = GridField.new()
	malformed.bounds = Rect2(Vector2(3.0e38,3.0e38),Vector2(3.0e38,3.0e38))
	var overflow_island = surface_script.new()
	check(not overflow_island.configure(malformed), "finite bounds components with overflowing end cannot publish nonfinite geometry")
	overflow_island.dispose()
	overflow_island.free()
	malformed = GridField.new()
	malformed.bounds = Rect2(-0.0000001,-0.0000001,0.0000002,0.0000002)
	malformed.heights[4] = 3.0e38
	check(not rejected.configure(malformed), "overflowing derived normals cannot publish nonfinite mesh")
	var wrong_material := ShaderMaterial.new()
	check(not rejected.configure(GridField.new(), wrong_material), "material without the independent natural shader cannot publish incomplete surface")
	rejected.free()
	var quiet = surface_script.new()
	check(quiet.configure(GridField.new(), null, {"caustics":false, "texture_world_scale":0.03}), "accepted options configure authored surface")
	check(quiet.get_mesh().material_override.get_shader_parameter("u_caustics") == false and quiet.get_mesh().material_override.get_shader_parameter("texture_world_scale") == 0.03, "accepted options affect own surface uniforms")
	var injected := surface_script.create_material() as ShaderMaterial
	var supplied = surface_script.new()
	check(supplied.configure(GridField.new(), injected) and supplied.get_mesh().material_override == injected, "caller supplied natural material is used for presentation tuning")
	supplied.dispose()
	supplied.free()
	quiet.dispose()
	quiet.free()
	var duplicate = surface_script.new()
	check(duplicate.configure(GridField.new()), "same fixture builds independent deterministic presentation")
	check(duplicate.get_mesh().mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == vertices and duplicate.get_mesh().mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] == indices, "repeat build has identical geometry and topology")
	duplicate.dispose()
	duplicate.free()
	island.dispose()
	check(island.get_mesh() == null and island.get_child_count() == 0 and not is_instance_valid(mesh_node), "dispose releases owned mesh child")
	check(is_nan(island.sample_height(0.0,0.0)), "dispose drops cached sampler")
	check(not island.sync_surface_state(ShaderMaterial.new()), "disposed surface cannot synchronize uniforms")
	check(not island.configure(GridField.new()), "disposed one-time presentation cannot be resurrected")
	island.dispose()
	island.free()
	_test_generated_grid(surface_script)
	_finish()

func _test_generated_grid(surface_script: Script) -> void:
	var field_path := "res://modules/scene_engine/terrain/natural_island_field.gd"
	check(ResourceLoader.exists(field_path), "independent generated numeric field is available for integration")
	if not ResourceLoader.exists(field_path):
		return
	var field_script: Script = load(field_path)
	var generated = field_script.new()
	check(generated.configure(), "default independent natural field generates")
	var grid: Dictionary = generated.get_grid()
	var island = surface_script.new()
	check(island.configure(generated), "default 257-side numeric field publishes one full finite mesh")
	if island.get_mesh() == null:
		island.free()
		return
	var arrays: Array = island.get_mesh().mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	check(vertices.size() == 66049 and indices.size() == 393216, "default full mesh has 66049 vertices and 131072 triangles")
	var max_diagonal_twist := 0.0
	var heights: PackedFloat32Array = grid.heights
	var side: int = grid.side
	for row: int in side-1:
		for column: int in side-1:
			var a := row*side+column
			max_diagonal_twist = maxf(max_diagonal_twist,absf(heights[a]-heights[a+1]-heights[a+side]+heights[a+side+1]))
	# For a cell's four heights a/b/c/d, the largest possible bilinear-to-
	# triangle difference is |a-b-c+d|/4 at the chosen diagonal midpoint.
	var bound := max_diagonal_twist*0.25
	check(bound < 0.25, "full-grid bilinear versus visible triangle mismatch remains below 25 cm")
	var bounds: Rect2 = grid.bounds
	var step := bounds.size/float(side-1)
	var largest_observed := 0.0
	for row: int in range(0,side-1,7):
		for column: int in range(0,side-1,7):
			var point := bounds.position+Vector2(float(column)+0.5,float(row)+0.5)*step
			var actual: float = island.sample_height(point.x,point.y)
			var difference := absf(actual-float(generated.sample_height(point.x,point.y)))
			largest_observed = maxf(largest_observed,difference)
			check(is_finite(actual) and difference <= bound+0.0001, "cached rendered triangles stay within independently derived bilinear error bound")
	close_to(island.sample_height(bounds.position.x,bounds.position.y),-24.0,"generated full grid starts at surrounding deep bed")
	close_to(island.sample_height(bounds.end.x,bounds.end.y),-24.0,"generated full grid ends at surrounding deep bed")
	print("NATURAL_ISLAND_MESH_DIAGNOSTICS samples=",vertices.size()," triangles=",indices.size()/3," bilinear_triangle_bound=",bound," largest_observed=",largest_observed)
	island.dispose()
	island.free()

func _finish() -> void:
	print("NATURAL_ISLAND_MESH_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
