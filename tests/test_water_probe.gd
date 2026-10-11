extends SceneTree

const WaveField = preload("res://modules/physics_engine/ocean/wave_field.gd")
const ProjectedOcean = preload("res://modules/scene_engine/ocean/projected_ocean.gd")
const HEIGHT_EPSILON := 1.0e-10
const VECTOR_EPSILON := 1.0e-6

var _failures: Array[String] = []
var _assertions := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, explanation: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(explanation)

func _run() -> void:
	_test_original_js_samples()
	await _test_screen_projection_and_injected_time()
	for failure in _failures:
		printerr("FAIL: ", failure)
	print("WATER_PROBE_TESTS assertions=", _assertions, " failures=", _failures.size())
	quit(0 if _failures.is_empty() else 1)

func _test_original_js_samples() -> void:
	# This fixture was exported by the existing JS implementation, not this port.
	# A flattened wave, changed amplitude/sign/time factor, or axis swap fails here.
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/original-ocean-reference.json"))
	_check(parsed is Dictionary and parsed.get("samples") is Array, "original JS fixture must be a valid object with samples")
	if not parsed is Dictionary or not parsed.get("samples") is Array:
		return
	var fixture: Dictionary = parsed
	var samples: Array = fixture.get("samples", [])
	_check(samples.size() == 48, "oracle must contain all 48 original JS samples")
	var field := WaveField.new()
	var bad_height := 0
	var bad_gradient := 0
	var bad_normal := 0
	var maximum_height_error := 0.0
	var maximum_gradient_error := 0.0
	var maximum_normal_error := 0.0
	for expected: Dictionary in samples:
		var actual: Dictionary = field.sample(expected.x, expected.z, expected.time)
		var height_error: float = absf(actual.height - expected.height)
		var gradient_error: float = actual.gradient.distance_to(Vector2(expected.gradient.x, expected.gradient.z))
		var normal_error: float = actual.normal.distance_to(Vector3(expected.normal.x, expected.normal.y, expected.normal.z))
		maximum_height_error = maxf(maximum_height_error, height_error)
		maximum_gradient_error = maxf(maximum_gradient_error, gradient_error)
		maximum_normal_error = maxf(maximum_normal_error, normal_error)
		if height_error > HEIGHT_EPSILON:
			bad_height += 1
		if gradient_error > VECTOR_EPSILON:
			bad_gradient += 1
		if normal_error > VECTOR_EPSILON:
			bad_normal += 1
		_check(absf(actual.normal.length() - 1.0) < VECTOR_EPSILON, "wave normal must be unit length")
	_check(bad_height == 0, "original JS wave heights differ in %d/48 samples; maximum error %.12f" % [bad_height, maximum_height_error])
	_check(bad_gradient == 0, "original JS wave gradients differ in %d/48 samples; maximum error %.12f" % [bad_gradient, maximum_gradient_error])
	_check(bad_normal == 0, "original JS wave normals differ in %d/48 samples; maximum error %.12f" % [bad_normal, maximum_normal_error])
	# Independent central differences also catch an incorrect derivative when later
	# fixture data is expanded, using scalar coordinates rather than copied formulas.
	var offset := 1.0e-4
	var at_point: Dictionary = field.sample(13.75, -21.5, 7.25)
	var finite_x: float = (field.sample(13.75 + offset, -21.5, 7.25).height - field.sample(13.75 - offset, -21.5, 7.25).height) / (2.0 * offset)
	var finite_z: float = (field.sample(13.75, -21.5 + offset, 7.25).height - field.sample(13.75, -21.5 - offset, 7.25).height) / (2.0 * offset)
	_check(at_point.gradient.distance_to(Vector2(finite_x, finite_z)) < VECTOR_EPSILON, "gradient must be the derivative of the sampled height")
	print("ORIGINAL_JS_ORACLE samples=", samples.size(), " height_max_error=", maximum_height_error, " gradient_max_error=", maximum_gradient_error, " normal_max_error=", maximum_normal_error)

func _test_screen_projection_and_injected_time() -> void:
	# A real Camera3D in a real viewport supplies the public camera projection.
	# Wrong screen Y, fixed-world grids, missing camera motion and unclamped rays
	# break these observable mesh positions.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800, 600)
	viewport.own_world_3d = true
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0.0, 10.0, 10.0)
	camera.fov = 60.0
	camera.far = 5000.0
	camera.look_at(Vector3.ZERO)
	camera.make_current()
	var ocean := ProjectedOcean.new()
	viewport.add_child(ocean)
	# Deliberately nonidentity: CPU projection is in world space, mesh is local.
	ocean.position = Vector3(3.0, 0.0, 7.0)
	var image := Image.create(2, 2, false, Image.FORMAT_RGB8)
	image.fill(Color(0.5, 0.5, 1.0))
	var texture := ImageTexture.create_from_image(image)
	await process_frame
	ocean.configure(camera, texture, 16, 3000.0)
	ocean.set_simulation_time(24.7)
	ocean.update_projection()
	_check(ocean.mesh != null and ocean.mesh.get_surface_count() == 1, "configure must create a projected ocean mesh")
	if ocean.mesh == null or ocean.mesh.get_surface_count() != 1:
		viewport.free()
		return
	var arrays: Array = ocean.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	_check(vertices.size() == 289, "16-segment screen grid needs 289 shared vertices")
	_check(indices.size() == 1536, "16-segment screen grid needs 512 triangles")
	_check(uvs[0] == Vector2.ZERO and uvs[288] == Vector2.ONE, "screen grid UV endpoints must retain original JS layout")
	var center := ocean.to_global(vertices[144])
	_check(center.distance_to(Vector3.ZERO) < 1.0e-4, "center camera ray must intersect the world sea plane at origin")
	# The bottom-screen row must be nearer than the top-screen row, retaining JS
	# clipY -1 -> +1 even though Godot screen coordinates grow downward.
	var bottom_center := ocean.to_global(vertices[8])
	var top_center := ocean.to_global(vertices[280])
	_check(bottom_center.z > top_center.z, "screen grid rows must preserve original clip-space vertical direction")
	var plane_ok := true
	var range_ok := true
	for vertex: Vector3 in vertices:
		var world_vertex := ocean.to_global(vertex)
		plane_ok = plane_ok and absf(world_vertex.y) < 1.0e-5
		range_ok = range_ok and Vector2(world_vertex.x - camera.global_position.x, world_vertex.z - camera.global_position.z).length() <= 3000.001
	_check(plane_ok, "base grid must remain on world y=0; shader owns wave displacement")
	_check(range_ok, "projected grid rays must respect the configured maximum distance")
	var material := ocean.material_override as ShaderMaterial
	_check(material != null, "ocean must use the original water shader material")
	if material != null:
		_check(material.get_shader_parameter("normal_texture") == texture, "normal texture must use the caller's injected asset")
		_check(absf(float(material.get_shader_parameter("simulation_time")) - 24.7) < 1.0e-4, "shader must receive the caller's simulation time")
		_check((material.get_shader_parameter("camera_position") as Vector3).distance_to(camera.global_position) < 1.0e-5, "shader camera uniform must follow the configured camera")
		await process_frame
		await process_frame
		_check(absf(float(material.get_shader_parameter("simulation_time")) - 24.7) < 1.0e-4, "paused simulation time must stay frozen across engine frames")
		ocean.set_simulation_time(NAN)
		_check(absf(float(material.get_shader_parameter("simulation_time")) - 24.7) < 1.0e-4, "invalid injected time must retain the last finite simulation timestamp")
		# Changing time changes wave displacement through the uniform, not the
		# projection plane, so snapshots share an identical underlying camera grid.
		ocean.set_simulation_time(80.0)
		_check(absf(float(material.get_shader_parameter("simulation_time")) - 80.0) < 1.0e-4, "a second injected timestamp must reach the shader")
		_check(ocean.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == vertices, "time injection must not move the undeformed projected grid")
	camera.position += Vector3(100.0, 0.0, 20.0)
	ocean.update_projection()
	var moved_vertices: PackedVector3Array = ocean.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_check(ocean.to_global(moved_vertices[144]).distance_to(Vector3(100.0, 0.0, 20.0)) < 1.0e-3, "camera translation must reproject the ocean in world space")
	# The parallel center ray uses the original fallback and cannot divide by 0.
	camera.position = Vector3(0.0, 10.0, 0.0)
	camera.rotation = Vector3.ZERO
	ocean.configure(camera, texture, 1, 3000.0)
	ocean.update_projection()
	var horizon_vertices: PackedVector3Array = ocean.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_check(horizon_vertices.size() == 289, "resolution below 16 must keep the original minimum screen-grid density")
	_check(ocean.to_global(horizon_vertices[144]).distance_to(Vector3(0.0, 0.0, -3000.0)) < 1.0e-3, "parallel ray must use the finite original distance fallback")
	# Nonpositive maxDistance is the original unbounded mode, with a 2500m
	# fallback for rays above/parallel to the ocean, not a collapsed zero grid.
	ocean.configure(camera, texture, 16, 0.0)
	ocean.update_projection()
	var unbounded_vertices: PackedVector3Array = ocean.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_check(ocean.to_global(unbounded_vertices[144]).distance_to(Vector3(0.0, 0.0, -2500.0)) < 1.0e-3, "nonpositive max distance must preserve the original 2500m horizon fallback")
	ocean.configure(camera, texture)
	var default_vertices: PackedVector3Array = ocean.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_check(default_vertices.size() == 6561, "default 80-segment projected grid must preserve the original 6561 vertices")
	_check(ocean.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() == 38400, "default projected grid must preserve the original 12800 triangles")
	_check(absf(float(material.get_shader_parameter("simulation_time")) - 80.0) < 1.0e-4, "reconfiguration must preserve the caller's last simulation time")
	viewport.free()
