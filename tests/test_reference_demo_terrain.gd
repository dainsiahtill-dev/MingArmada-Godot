extends SceneTree

const MODEL_PATH := "res://modules/scene_engine/reference_island_water/reference_island_model.gd"
const DATA_PATH := "res://assets/data/reference_cat_island_h.json"
const DATA_SHA := "d1b4f3b42347916ef7f85262e1ac16a65234c4981a374039b55ab0b417d30a1c"
var assertions := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, reason: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", reason)

func _finish() -> void:
	print("REFERENCE_DEMO_TERRAIN_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)

func _run() -> void:
	check(FileAccess.file_exists(MODEL_PATH), "reference demo terrain module exists")
	if not FileAccess.file_exists(MODEL_PATH):
		_finish()
		return
	var model = load(MODEL_PATH)
	check(model != null, "reference demo module loads")
	if model == null:
		_finish()
		return
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference-demo-terrain.json"))
	var field: Dictionary = model.load_field()
	check(not field.is_empty(), "original height index file loads")
	if field.is_empty():
		_finish()
		return
	check(FileAccess.get_sha256(DATA_PATH) == DATA_SHA, "original height index JSON is preserved byte for byte")
	check(field.width == 120 and field.height == 140 and field.values.size() == 16800, "palette indices retain source dimensions and order")
	check(model.is_valid_field(field), "validated original data is usable")
	for row: Dictionary in fixture.samples:
		check(absf(model.height_at(field, row.x, row.z) - row.height) < 1e-10, "bilinear source height at (%s,%s)" % [row.x, row.z])
		check(absf(model.mesh_height_at(field, row.x, row.z) - row.meshHeight) < 2e-6, "drawn triangular coast height at (%s,%s)" % [row.x, row.z])
	for row: Dictionary in fixture.terrain:
		var data: Dictionary = model.terrain_arrays(field, int(row.resolution))
		_verify_arrays(data, row, true)
		var mesh: ArrayMesh = model.terrain_mesh(field, int(row.resolution))
		check(mesh != null and mesh.get_surface_count() == 1, "renderable terrain mesh is generated")
		check(mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] == data.indices, "render mesh retains source triangle winding and diagonal")
	for row: Dictionary in fixture.apron:
		var data: Dictionary = model.seabed_arrays(field, int(row.segments))
		_verify_arrays(data, row, false)
		var mesh: ArrayMesh = model.seabed_mesh(field, int(row.segments))
		check(mesh != null and mesh.get_surface_count() == 1, "renderable background seabed is generated")
		check(mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] == data.indices, "seabed render mesh retains source ring topology")
	var drawn: Dictionary = model.terrain_arrays(field)
	var texture: ImageTexture = model.height_texture(field)
	check(texture != null and texture.get_width() == 161 and texture.get_height() == 161, "height LUT has one texel per drawn terrain vertex")
	var image: Image = texture.get_image()
	check(image.get_format() == Image.FORMAT_RF and not image.has_mipmaps(), "height LUT remains R32F with no interpolating mip levels")
	check(_sha(image.get_data()) == fixture.terrain[2].heightLutSha256, "entire R32F coast LUT matches original renderer Float32 vertex heights byte for byte")
	for index: int in [0,1,160,161,12880,15017,25920]:
		check(image.get_pixel(index % 161, index / 161).r == drawn.positions[index].y, "LUT stores exact Float32 draw height at vertex %d" % index)
	var corner_field := {"width":2,"height":2,"values":[128,138,148,168],"extent":2.0,"heightScale":1.0,"seaIndex":128.0}
	check(model.mesh_height_at(corner_field,-0.5,-0.5,1) == 7.5, "lower source triangle interpolation differs from bilinear on a saddle cell")
	check(model.mesh_height_at(corner_field,0.5,0.5,1) == 27.5, "upper source triangle preserves opposite corner and diagonal")
	check(model.height_at(corner_field,-0.5,-0.5) == 8.125, "bilinear generation retains the four-corner source weighting")
	for resolution: int in [0,-1,255]:
		check(model.terrain_arrays(field,resolution).is_empty(), "invalid source terrain resolution is rejected")
		check(model.terrain_mesh(field,resolution) == null, "invalid terrain mesh cannot reach the renderer")
		check(model.height_texture(field,resolution) == null, "invalid height LUT cannot diverge from terrain mesh")
	for invalid: Dictionary in [{},{"width":1,"height":2,"values":[0,0],"extent":160.0,"heightScale":0.35,"seaIndex":128.0},{"width":2,"height":2,"values":[0,0,0],"extent":160.0,"heightScale":0.35,"seaIndex":128.0},{"width":2,"height":2,"values":[0,0,0,256],"extent":160.0,"heightScale":0.35,"seaIndex":128.0},{"width":2,"height":2,"values":[0,0,0,1.5],"extent":160.0,"heightScale":0.35,"seaIndex":128.0},{"width":2,"height":2,"values":[0,0,0,0],"extent":0.0,"heightScale":0.35,"seaIndex":128.0}]:
		check(not model.is_valid_field(invalid), "malformed source field is rejected")
		check(model.terrain_arrays(invalid).is_empty(), "malformed field produces no terrain")
	check(model.load_field("res://assets/data/missing-reference-island.json").is_empty(), "missing data is handled without partial field")
	var shader: Shader = load("res://modules/scene_engine/reference_island_water/reference_terrain.gdshader")
	check(shader != null, "source terrain shader loads")
	var uniforms := {}
	for entry: Dictionary in shader.get_shader_uniform_list():
		uniforms[entry.name] = entry.type
	for required: String in ["u_time","u_tide","u_sun","u_sun_color","u_clip","u_caustics"]:
		check(uniforms.has(required), "compiled terrain shader exposes source state %s" % required)
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("u_tide",2.5)
	material.set_shader_parameter("u_time",19.0)
	check(material.get_shader_parameter("u_tide") == 2.5 and material.get_shader_parameter("u_time") == 19.0, "same terrain material accepts wet sand and caustic time inputs")
	_finish()

func _verify_arrays(data: Dictionary, row: Dictionary, with_uv: bool) -> void:
	check(data.positions.size() == int(row.vertexCount), "source mesh vertex count")
	check(data.indices.size() == int(row.indexCount), "source mesh triangle count")
	check(_sha(data.positions.to_byte_array()) == row.positionsSha256, "all source Float32 positions match byte for byte")
	check(_sha(data.normals.to_byte_array()) == row.normalsSha256, "all source Float32 normals match byte for byte")
	check(_sha(data.indices.to_byte_array()) == row.indicesSha256, "all source mesh indices match byte for byte after Uint16-to-Int32 type widening")
	if with_uv:
		check(_sha(data.uv.to_byte_array()) == row.uvSha256, "all source Float32 UVs match byte for byte")
	for vertex: Dictionary in row.vertices:
		var index: int = int(vertex.index)
		check(data.positions[index].distance_to(Vector3(vertex.position[0],vertex.position[1],vertex.position[2])) < 1e-7, "actual Float32 vertex %d position" % index)
		check(data.normals[index].distance_to(Vector3(vertex.normal[0],vertex.normal[1],vertex.normal[2])) < 2e-7, "source analytic or ring normal at vertex %d" % index)
		if with_uv:
			check(data.uv[index].distance_to(Vector2(vertex.uv[0],vertex.uv[1])) < 1e-7, "source UV at vertex %d" % index)
	for index: int in row.indices.size():
		check(data.indices[index] == int(row.indices[index]), "first mesh strip follows source winding")
	for index: int in row.lastIndices.size():
		check(data.indices[data.indices.size()-row.lastIndices.size()+index] == int(row.lastIndices[index]), "last mesh strip closes source topology")

func _sha(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()
