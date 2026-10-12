extends SceneTree

const STATIC_PATH := "res://modules/scene_engine/fidelity_island/static_islands.gd"
const Profile = preload("res://modules/scene_engine/terrain/reference_island_profile.gd")
const HeightField = preload("res://modules/scene_engine/terrain/height_field.gd")
const FidelityMaterial = preload("res://modules/scene_engine/fidelity_island/terrain_material.gd")
var assertions := 0
var failures := 0
var sample_calls := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, reason: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", reason)

func _run() -> void:
	check(FileAccess.file_exists(STATIC_PATH), "source height-grid static island builder exists")
	if failures:
		_finish()
		return
	var StaticIslands: GDScript = load(STATIC_PATH)
	var builder: RefCounted = StaticIslands.new()
	var mapping := {"id":"cat_island", "width":120, "height":140, "sourceCenter":Vector2(9,11), "sourceOutward":Vector2.DOWN, "islandCenter":Vector2(50,-20), "inward":Vector2.UP, "scale":2.0}
	var material := ShaderMaterial.new()
	material.shader = FidelityMaterial.TerrainShader
	check(builder.configure([mapping], _plane_height, [material]), "valid original-grid mapping accepts injected height authority")
	var meshes: Array = builder.get_meshes()
	check(meshes.size() == 1, "one source island owns one immutable terrain mesh")
	if meshes.size() != 1:
		builder.dispose()
		_finish()
		return
	var island: MeshInstance3D = meshes[0]
	var arrays: Array = island.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	check(vertices.size() == 16800 and indices.size() == 119*139*6, "all original 120 by 140 pixels retain native one-pixel geometry detail")
	check(sample_calls == 16800, "height authority runs exactly once per retained source pixel, never again for normals")
	check((vertices[0]+island.position).distance_to(Vector3(68,-5.75,-42)) < .0001, "first source pixel maps through source rotation, center and metre scale")
	check((vertices[-1]+island.position).distance_to(Vector3(-170,670.25,236)) < .0001, "last source pixel retains rectangular footprint and injected height")
	check(uv[0].distance_to(Vector2(.5/120.0,.5/140.0)) < .000001 and uv[-1].distance_to(Vector2(119.5/120.0,139.5/140.0)) < .000001, "mesh UVs use original source pixel centers, never moving world-chunk coordinates")
	# ArrayMesh stores packed normals; the observed readback error is 4.4e-5.
	check(normals[0].distance_to(Vector3(-3,1,-5).normalized()) < .0001 and normals[8399].distance_to(normals[0]) < .0001 and normals[-1].distance_to(normals[0]) < .0001, "mapped neighbor tangents give correct world-space slope normals at edges and interior within packed mesh precision")
	var valid_faces := true
	for offset in range(0, indices.size(), 3):
		var a: Vector3 = vertices[indices[offset]]
		var b: Vector3 = vertices[indices[offset+1]]
		var c: Vector3 = vertices[indices[offset+2]]
		if (b-a).cross(c-a).dot(normals[indices[offset]]) >= -0.001:
			valid_faces = false
			break
	check(valid_faces, "every mapped source triangle has Godot clockwise winding and nonzero area")
	check(indices.slice(0,12) == PackedInt32Array([0,120,1,120,121,1,1,121,122,1,122,2]), "source grid alternates diagonals to preserve original indexed terrain relief")
	check(island.get_child_count() == 0, "static visual generation creates no collider or second physics authority")
	check(absf(builder.sample_mesh_height(65.5,-36.75)-13.0) < .0001, "shore queries interpolate actual cached source triangles")
	check(is_nan(builder.sample_mesh_height(10000,10000)), "mesh height query declines locations outside all source islands")
	check(builder.supports(Vector2(50,-20),0) and builder.supports(Vector2(70,-42),2), "source footprint supports interior and circle-edge intersection")
	check(not builder.supports(Vector2(10000,10000),5) and not builder.supports(Vector2(NAN,0),1) and not builder.supports(Vector2.ZERO,-1), "visibility support rejects distant and invalid requests")
	var first_id := island.get_instance_id()
	var before: Dictionary = builder.diagnostics()
	check(before.geometry_builds == 1 and before.triangles == 119*139*2 and before.sampleCalls == 16800 and before.sourceVertices == 16800, "diagnostics report deterministic mesh work and one-time authority sampling")
	check(builder.configure([mapping],_plane_height,[material]) and builder.get_meshes()[0].get_instance_id() == first_id and sample_calls == 16800, "identical configuration reuses source mesh without terrain resampling")
	check(builder.diagnostics() == before,"cached configuration retains deterministic diagnostics without a wall clock")
	var bad := mapping.duplicate(true)
	bad.scale = 0.0
	check(not builder.configure([bad],_plane_height,[material]) and builder.get_meshes()[0].get_instance_id() == first_id, "invalid mapping fails atomically and preserves accepted mesh")
	var bad_vector := mapping.duplicate(true)
	bad_vector.sourceCenter = [{"invalid":true},11]
	check(not builder.configure([bad_vector],_plane_height,[material]) and builder.get_meshes()[0].get_instance_id() == first_id, "nonnumeric vector components reject before coordinate conversion and preserve accepted mesh")
	check(not builder.configure([mapping],_nonfinite_height,[material]) and builder.get_meshes()[0].get_instance_id() == first_id, "nonfinite sampler fails atomically and releases candidate geometry")
	var wrong_size := mapping.duplicate(true)
	wrong_size.width = 119
	check(not builder.configure([wrong_size],_plane_height,[material]), "reported source dimensions must match validated immutable source asset")
	check(not builder.configure([mapping],_plane_height,[material],{"pixel_spacing":4}), "configuration cannot silently discard source height detail")
	var ocean := ShaderMaterial.new()
	ocean.shader = Shader.new()
	ocean.shader.code = "shader_type spatial; uniform float simulation_time=0.; uniform float u_tide=0.; uniform vec3 u_sun=vec3(0.,1.,0.); uniform vec3 u_sun_color=vec3(1.); uniform vec4 wave_components[8]; uniform int wave_count=0; uniform vec4 shore_bounds=vec4(0.); uniform bool has_shore_field=false; uniform bool u_caustics=true;"
	ocean.set_shader_parameter("simulation_time",12.25)
	ocean.set_shader_parameter("u_tide",.7)
	ocean.set_shader_parameter("wave_components",PackedVector4Array([Vector4(.3,.2,.1,-1)]))
	ocean.set_shader_parameter("wave_count",1)
	check(island.sync_surface_state(ocean), "static island shares validated ocean surface-state synchronization")
	check(island.material_override.get_shader_parameter("u_time") == 12.25 and island.material_override.get_shader_parameter("u_tide") == .7 and island.material_override.get_shader_parameter("wave_count") == 1, "terrain copies ocean clock, tide and wave aliases into existing shader")
	check(island.get_instance_id() == first_id and sample_calls == 16800, "surface synchronization cannot rebuild or resample static terrain")
	builder.dispose()
	check(not is_instance_valid(island) and builder.get_meshes().is_empty() and not builder.supports(Vector2(50,-20),1), "dispose frees owned nodes and drops coverage immediately")
	check(builder.diagnostics().meshCount == 0 and is_nan(builder.sample_mesh_height(50,-20)), "disposed terrain no longer supplies render-height samples")
	builder.dispose()
	_verify_formal_sources(StaticIslands)
	_finish()

func _plane_height(x: float, z: float) -> float:
	sample_calls += 1
	return 3.0*x+5.0*z+.25

func _nonfinite_height(_x: float, _z: float) -> float:
	return NAN

func _verify_formal_sources(StaticIslands: GDScript) -> void:
	var ports: Array = JSON.parse_string(FileAccess.get_file_as_string("res://game/data/mingqi_geography.json"))
	var field := HeightField.new()
	check(field.configure_ports(ports,true,{"reference_islands":true}), "formal height authority configures its three intact original source profiles")
	var profiles: Array = field.reference_profiles()
	var materials: Array = []
	var source_vertices := 0
	for profile: Dictionary in profiles:
		var source := Profile.load_source(str(profile.id))
		source_vertices += int(source.width)*int(source.height)
		materials.append(StandardMaterial3D.new())
	var builder: RefCounted = StaticIslands.new()
	check(builder.configure(profiles,field.sample_height,materials), "all actual original island maps compose into static formal-world terrain")
	var stats: Dictionary = builder.diagnostics()
	check(builder.get_meshes().size() == 3 and stats.sourceVertices == source_vertices and stats.vertices >= source_vertices and stats.sampleCalls == stats.vertices, "all three original resolutions and finite harbor additions survive without procedural chunk throttling")
	var bounded_vertices := 0
	for bounds: Dictionary in stats.renderBounds:
		var extent: Vector2i = bounds.pixelMax-bounds.pixelMin+Vector2i.ONE
		bounded_vertices += extent.x*extent.y
		check(bounds.pixelMin.x<=0 and bounds.pixelMin.y<=0 and bounds.pixelMax.x>=bounds.sourcePixelMax.x and bounds.pixelMax.y>=bounds.sourcePixelMax.y,"render bounds retain complete native source bounds")
	check(bounded_vertices == stats.vertices,"reported finite render bounds exactly account for generated vertices")
	print("STATIC_REFERENCE_ISLANDS_GEOMETRY ", JSON.stringify(builder.diagnostics().duplicate().merged({"sourceProfiles":[]},true)))
	for index in profiles.size():
		var island: MeshInstance3D = builder.get_meshes()[index]
		var arrays: Array = island.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var max_error := 0.0
		for vertex: Vector3 in vertices:
			var world := vertex+island.position
			max_error = maxf(max_error,absf(world.y-field.sample_height(world.x,world.z)))
		check(max_error < .00005, "every rendered source vertex agrees with retained harbor/navigation/physics height owner: "+str(profiles[index].id))
		check(builder.supports(Vector2(float(ports[index].islandX),float(ports[index].islandZ)),float(ports[index].radius)), "formal port retains visible source island coverage")
	builder.dispose()

func _finish() -> void:
	print("STATIC_REFERENCE_ISLANDS_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
