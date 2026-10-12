extends SceneTree
## Actual three-port profiles keep finite native island meshes across camera moves.
const World = preload("res://modules/scene_engine/world/world_view.gd")
const Height = preload("res://modules/scene_engine/terrain/height_field.gd")
const Waves = preload("res://modules/contracts/wave_descriptor.gd")
const Geography = preload("res://game/scenes/common/reference_geography.gd")
var assertions := 0
var failures := 0

func check(value: bool, reason: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL: ", reason)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var ports: Array = JSON.parse_string(FileAccess.get_file_as_string("res://game/data/mingqi_geography.json"))
	var height := Height.new()
	check(height.configure_ports(ports, true, Geography.source_options()), "real three-port height owner accepts explicit source comparison profiles and art options")
	var accepted_profiles: Array = height.reference_profiles()
	var probes: Array[Vector2] = [Vector2(-480,-60),Vector2(420,160),Vector2(-60,390),Vector2(0,32)]
	var accepted_heights: Array[float] = []
	for point: Vector2 in probes:
		accepted_heights.append(height.sample_height(point.x, point.y))
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(-160,100,260)
	camera.look_at(Vector3(-480,0,-60))
	camera.current = true
	var world := World.new()
	root.add_child(world)
	var unrelated := Node3D.new()
	world.add_child(unrelated)
	var options := {"camera":camera,"ports":ports,"resolution":8,"chunk_radius":0,"vegetation":true,"island_details":false,"collision":false,"static_shore_resolution":256}
	check(world.configure(height.sample_height, Waves.original_descriptors(), options), "actual reference world composes with original five-wave ocean")
	var diagnostics: Dictionary = world.fidelity_diagnostics()
	check(diagnostics.get("geometryMode") == "static_source", "native reference world defaults to finite original island geometry")
	check(world.get_chunks().is_empty() and world.get_distant_chunks().is_empty(), "native reference world allocates no camera near/far terrain chunks")
	if diagnostics.get("geometryMode") != "static_source":
		world.dispose(); world.free(); camera.free(); _finish(); return
	var geometry: Dictionary = diagnostics.get("geometry", {})
	check(geometry.get("meshMaterialBindings",[]).size() == 3, "GPU inspection records materials bound to actual static mesh nodes")
	for binding: Dictionary in geometry.get("meshMaterialBindings",[]):
		check(binding.get("matchesOwnedMaterial") == true and binding.get("shader") == "res://modules/scene_engine/fidelity_island/terrain.gdshader", "actual static meshes retain intended source terrain shader binding")
	check(geometry.get("meshCount") == 3 and geometry.get("geometry_builds") == 3, "three actual source profiles build exactly once")
	check(int(geometry.get("triangles",0)) > 10000, "formal islands retain native source-grid detail")
	var meshes: Array = world.get_static_island_meshes()
	check(world._fidelity_vegetation.size() == 1 and int(world._fidelity_vegetation[0].diagnostics().get("accepted_tree_count",0)) > 0, "actual original source trees compose over frozen terrain")
	check(world._fidelity_shores.size() == 1, "actual Cat source surf composes with old ocean")
	var ids: Array[int] = []
	var references: Array[WeakRef] = []
	for island: MeshInstance3D in meshes:
		ids.append(island.get_instance_id())
		references.append(weakref(island))
		var arrays: Array = island.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for index in range(0,vertices.size(),maxi(1,vertices.size()/64)):
			var point: Vector3 = island.global_transform * vertices[index]
			check(absf(point.y-height.sample_height(point.x,point.z)) < 0.0002, "native mesh vertices preserve accepted authoritative height")
		check(island.get_collision_body() == null, "static formal geometry adds no new physics height owner")
	for port: Dictionary in ports:
		var group: Node3D = world.find_child(String(port.id),true,false)
		check(group != null and group.visible, "actual native terrain supports port " + String(port.id))
	check(not world._island_supported(Vector2(100000,100000),10), "unsupported location is outside finite native island coverage")
	var sea: ShaderMaterial = world.get_ocean().material_override
	check(sea.get_shader_parameter("surface_visual_scale") == 1.5, "finite source islands retain old physical waves while sea texture detail uses native visual scale")
	check(sea.get_shader_parameter("display_fog_density") == 0.00035, "finite source island scale uses shared clear sea fog density")
	for material: ShaderMaterial in world._fidelity_materials:
		check(material.get_shader_parameter("display_fog_density") == 0.00035, "native terrain and sea share accepted fog density")
	var accepted_waves: PackedVector4Array = sea.get_shader_parameter("wave_components")
	check(sea.get_shader_parameter("wave_count") == 5 and accepted_waves.size() >= 5 and world.get_ocean()._descriptors == Waves.original_descriptors(), "old original ocean retains all five accepted wave components")
	for index in 5:
		var component: Array = Waves.ORIGINAL_COMPONENTS[index]
		check(accepted_waves[index].is_equal_approx(Vector4(component[0],component[1],component[2],component[3])), "original sea component remains accepted without source-preview wave substitution")
	var field: ImageTexture = world._near_shore_texture
	var global_field: Texture2D = world._shore_field.get_texture()
	check(field != null and field.get_image().get_size() == Vector2i(256,256), "one-time finite terrain optical field obeys explicit bounded resolution")
	if field:
		var image: Image = field.get_image()
		var bounds: Vector4 = sea.get_shader_parameter("reference_near_bounds")
		for row in range(0,256,31):
			for column in range(0,256,31):
				var point := Vector2(bounds.x,bounds.y)+Vector2(bounds.z-bounds.x,bounds.w-bounds.y)*Vector2(column,row)/255.0
				var expected: float = world._static_islands.sample_mesh_height(point.x,point.y)
				if not is_finite(expected): expected = height.sample_height(point.x,point.y)
				check(absf(image.get_pixel(column,row).r-expected) < 0.0002, "static optical field matches real finite mesh triangles and authoritative submerged shelf")
	var sample_calls: int = int(geometry.get("sampleCalls",0))
	for focus: Vector2 in [Vector2(-480,-60),Vector2(420,160),Vector2(1600,900),Vector2(-3000,-1800)]:
		world.apply_snapshot({"time":17.25,"focus":focus},0)
		var now: Array = world.get_static_island_meshes()
		check(now.size() == ids.size(), "camera movement retains all source islands")
		for index in now.size():
			check(now[index].get_instance_id() == ids[index], "camera movement preserves static island identity")
		check(world._near_shore_texture == field and world._shore_field.get_texture() == global_field, "camera movement never rebuilds static shoreline fields")
		check(world.fidelity_diagnostics().geometry.get("sampleCalls") == sample_calls, "accepted snapshots perform no island height resampling")
		check(world.get_chunks().is_empty() and world.get_distant_chunks().is_empty(), "camera movement never allocates procedural terrain tiles")
	check(sea.get_shader_parameter("simulation_time") == 17.25, "zero consumed time preserves accepted authoritative ocean clock")
	check(sea.get_shader_parameter("wave_components") == accepted_waves, "camera movement and pause preserve original ocean waves")
	for index in meshes.size():
		check(meshes[index].material_override == world._fidelity_materials[index], "inherited accepted-surface sync cannot replace source mesh material")
	for island: MeshInstance3D in meshes:
		check(island.material_override.get_shader_parameter("simulation_time") == 17.25, "frozen terrain materials follow accepted sea clock")
	for trees: Node3D in world._fidelity_vegetation:
		check(trees.diagnostics().get("simulation_time") == 17.25, "source trees follow accepted simulation clock")
	world.apply_snapshot({"time":3.0,"focus":Vector2(NAN,0)},0)
	check(sea.get_shader_parameter("simulation_time") == 3.0 and world._near_shore_texture == field, "accepted rewind and invalid focus keep frozen geometry intact")
	check(height.reference_profiles() == accepted_profiles, "render configuration leaves native navigation profile owner unchanged")
	for index in probes.size():
		check(height.sample_height(probes[index].x,probes[index].y) == accepted_heights[index], "render snapshots leave terrain and shoal navigation heights unchanged")
	var tree_references: Array[WeakRef] = []
	for trees: Node3D in world._fidelity_vegetation: tree_references.append(weakref(trees))
	for surf: Node3D in world._fidelity_shores: tree_references.append(weakref(surf))
	var ocean_reference: WeakRef = weakref(world.get_ocean())
	meshes.clear()
	world.dispose(); world.dispose()
	for reference: WeakRef in references: check(reference.get_ref() == null, "world disposal frees owned native island meshes")
	for reference: WeakRef in tree_references: check(reference.get_ref() == null, "world disposal frees owned source tree roots")
	check(ocean_reference.get_ref() == null and world._near_shore_texture == null, "world disposal releases ocean and static fields")
	check(is_instance_valid(unrelated) and unrelated.get_parent() == world, "static world disposal preserves caller-owned nodes")
	options.vegetation = false
	options.sea_visual_scale = 2.0
	options.display_fog_density = 0.0006
	check(world.configure(height.sample_height,Waves.original_descriptors(),options), "disposed native world can reenter")
	check(world.get_static_island_meshes().size() == 3 and world.get_static_island_meshes()[0].get_instance_id() != ids[0], "reentry owns fresh source island nodes")
	world.apply_snapshot({"time":9.0,"focus":Vector2(420,160)},0)
	check(world.get_ocean().material_override.get_shader_parameter("surface_visual_scale") == 2.0 and world.get_ocean().material_override.get_shader_parameter("display_fog_density") == 0.0006, "explicit sea visual scale and fog density survive accepted snapshots")
	check(world.get_ocean()._descriptors == Waves.original_descriptors(), "visual scale leaves accepted physical wave descriptors unchanged")
	world.dispose()
	var classic := Height.new()
	classic.configure_ports(ports)
	options.erase("sea_visual_scale"); options.erase("display_fog_density")
	check(world.configure(classic.sample_height,Waves.original_descriptors(),options), "classic terrain remains configurable with legacy visual defaults")
	check(world.get_ocean().material_override.get_shader_parameter("surface_visual_scale") == 1.0 and world.get_ocean().material_override.get_shader_parameter("display_fog_density") == 0.0015, "non-reference world retains original sea detail scale and fog")
	check(world.get_chunk_count() == 1 and world.get_static_island_meshes().is_empty(), "non-reference world retains procedural chunk semantics")
	world.dispose(); world.free(); camera.free()
	_finish()

func _finish() -> void:
	print("STATIC_ISLAND_WORLD_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
