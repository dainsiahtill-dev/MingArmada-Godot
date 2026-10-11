extends Node3D
## Native GPU ocean feasibility scene. Composition owns time; no gameplay is simulated.

const Ocean = preload("res://modules/scene_engine/ocean/projected_ocean.gd")
const Waves = preload("res://modules/physics_engine/ocean/wave_field.gd")
const Heights = preload("res://modules/scene_engine/terrain/height_field.gd")
const ShoreField = preload("res://modules/scene_engine/ocean/shore_field.gd")
const ShoreSpray = preload("res://modules/scene_engine/ocean/shore_spray.gd")
const SHIP_POSITION := Vector3(-282.15, 0.0, -33.02)
const CAPTURE_ROOT := "res://docs/migration/evidence/water-probe"
const VIEWS := ["captain", "tactical", "horizon"]
const CAPTURE_TIMES := [0.0, 24.7, 80.0]

var ocean: MeshInstance3D
var camera: Camera3D
var ship: Node3D
var waves := Waves.new()
var simulation_time := 24.7
var running := true
var view_index := 0
var capture_mode := false
var status: Label
var metadata: Dictionary = {}
var frame_times: Array[float] = []
var heights := Heights.new()
var shore_spray: MultiMeshInstance3D

func _ready() -> void:
	DisplayServer.window_set_title("海上明旗 · Godot 原生海面验证")
	get_window().size = Vector2i(1600, 900)
	get_viewport().msaa_3d = Viewport.MSAA_4X
	capture_mode = "--capture" in OS.get_cmdline_user_args()
	_build_environment()
	if not _build_terrain():
		return
	_load_ship()
	if ship == null:
		return
	camera = Camera3D.new()
	camera.fov = 55.0
	camera.near = 0.5
	camera.far = 4000.0
	add_child(camera)
	camera.current = true
	_set_view(0)
	var image := Image.load_from_file(ProjectSettings.globalize_path("res://assets/textures/waternormals.jpg"))
	if image == null:
		_fail("Cannot load original water normal texture")
		return
	image.generate_mipmaps()
	ocean = Ocean.new()
	add_child(ocean)
	ocean.configure(camera, ImageTexture.create_from_image(image), 80, 3000.0)
	ocean.set_visual_style(1)
	ocean.set_projection_padding(0.10)
	var shore := ShoreField.new()
	var shore_bounds := Rect2(-770.0, -350.0, 1510.0, 970.0)
	if not shore.configure(heights.sample_height, shore_bounds, 512):
		_fail("Native shoreline field creation failed")
		return
	ocean.set_shore_field(shore.get_texture(), shore.get_bounds(), shore.get_coast_texture())
	shore_spray = ShoreSpray.new()
	add_child(shore_spray)
	shore_spray.configure(heights.sample_height, shore_bounds, 160)
	_build_hud()
	metadata = {
		"engine": Engine.get_version_info(),
		"rendering_method": ProjectSettings.get_setting("rendering/renderer/rendering_method", "gl_compatibility"),
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"viewport": [1600, 900],
		"sun_position": [SHIP_POSITION.x + 300.0, 150.0, SHIP_POSITION.z + 100.0],
		"color_pipeline": "Bright Godot art direction per user reference; original style0 remains available",
		"shoreline": "512x512 signed original terrain height field, moving breaker contours, 160 native droplet billboards",
		"source_head": "9ad6a44daecd4ec36a8172d83ff27493feffe5dd",
		"ship_scope": "Static original GLB with wave pose reference; no buoyancy or gameplay migration claimed",
		"captures": []
	}
	if capture_mode:
		running = false
		_capture_sequence.call_deferred()

func _process(delta: float) -> void:
	if running:
		simulation_time += minf(delta, 0.1)
	_apply_ocean_time()
	if status:
		status.text = "海上明旗  /  GODOT 原生海面验证\n五波原公式 · 原水纹 · 当前 %.1f 秒\n1 船长镜头   2 高位镜头   3 地平线\n空格 暂停波浪   F12 截图\n船只为水线参照，尚未迁移操船物理" % simulation_time
	if capture_mode:
		frame_times.append(delta * 1000.0)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1: _set_view(0)
		KEY_2: _set_view(1)
		KEY_3: _set_view(2)
		KEY_SPACE: running = not running
		KEY_F12: _capture("manual-%d" % Time.get_unix_time_from_system())
		KEY_ESCAPE: get_tree().quit()

func _build_environment() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("87ceeb")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("a0c8ff")
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	add_child(sun)
	sun.position = SHIP_POSITION + Vector3(300.0, 150.0, 100.0)
	sun.look_at(SHIP_POSITION)
	sun.light_energy = 2.0
	sun.shadow_enabled = true

func _build_terrain() -> bool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/water-probe-terrain.json"))
	if not parsed is Dictionary or not parsed.get("meshes") is Array or parsed["meshes"].size() != 3:
		_fail("Missing or invalid three-island terrain fixture")
		return false
	var fixture: Dictionary = parsed
	heights.configure_ports(fixture.get("ports", []))
	for entry: Dictionary in fixture["meshes"]:
		if not entry.get("vertices") is Array or not entry.get("n") is float and not entry.get("n") is int:
			_fail("Invalid terrain mesh fixture")
			return false
		if entry["vertices"].size() != int(pow(entry["n"] + 1, 2)):
			_fail("Invalid terrain vertex count")
			return false
		var vertices := PackedVector3Array()
		var colors := PackedColorArray()
		var indices := PackedInt32Array()
		for v: Array in entry["vertices"]:
			vertices.append(Vector3(v[0], v[1], v[2]))
			var color := Color("002b4d")
			if v[1] >= -5.0: color = Color("8b7d6b")
			if v[1] >= 2.0: color = Color("e6dabf")
			if v[1] >= 10.0: color = Color("597d3e")
			if v[1] >= 35.0: color = Color("6b6b58")
			colors.append(color.srgb_to_linear())
		var n: int = entry["n"]
		for z in n:
			for x in n:
				var a := z * (n + 1) + x
				indices.append_array(PackedInt32Array([a, a + n + 1, a + 1, a + 1, a + n + 1, a + n + 2]))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		var terrain := MeshInstance3D.new()
		var surface := ArrayMesh.new()
		surface.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		terrain.mesh = surface
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		terrain.material_override = material
		add_child(terrain)
	var bed := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8000.0, 8000.0)
	bed.mesh = plane
	bed.position.y = -50.0
	var bed_material := StandardMaterial3D.new()
	bed_material.albedo_color = Color("002b4d")
	bed_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bed.material_override = bed_material
	add_child(bed)
	return true

func _load_ship() -> void:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var result := document.append_from_file(ProjectSettings.globalize_path("res://assets/models/ships/fuchuan-lod0.glb"), state)
	if result != OK:
		_fail("Original fuchuan GLB load error: %d" % result)
		return
	ship = document.generate_scene(state)
	ship.name = "OriginalFuchuanReference"
	add_child(ship)
	ship.position = SHIP_POSITION
	_enable_original_vertex_colors(ship)

func _enable_original_vertex_colors(node: Node) -> void:
	# Runtime GLTFDocument loading leaves this material flag disabled in this build.
	# Ship colors are in COLOR_0, not PBR baseColorFactor or a diffuse texture.
	if node is MeshInstance3D:
		for index in node.mesh.get_surface_count():
			var material := node.mesh.surface_get_material(index) as StandardMaterial3D
			if capture_mode and index == 0:
				var arrays: Array = node.mesh.surface_get_arrays(index)
				var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
				print("GLTF_MATERIAL_REFERENCE ", JSON.stringify({"node": node.name, "class": node.get_class(), "color_count": colors.size(), "first_color": str(colors[0]) if not colors.is_empty() else "none", "vertex_color_enabled_before": material.vertex_color_use_as_albedo if material else false, "material": str(material)}))
			if material:
				material.vertex_color_use_as_albedo = true
	for child in node.get_children():
		_enable_original_vertex_colors(child)

func _apply_ocean_time() -> void:
	if not ocean:
		return
	ocean.set_simulation_time(simulation_time)
	ocean.update_projection()
	if shore_spray:
		shore_spray.set_simulation_time(simulation_time)
	var material := ocean.material_override as ShaderMaterial
	if material:
		material.set_shader_parameter("sun_position", SHIP_POSITION + Vector3(300.0, 150.0, 100.0))
	if ship:
		var sample: Dictionary = waves.sample(SHIP_POSITION.x, SHIP_POSITION.z, simulation_time)
		ship.position.y = sample["height"]
		var normal: Vector3 = sample["normal"]
		ship.rotation = Vector3(atan2(normal.z, normal.y), 0.0, -atan2(normal.x, normal.y))

func _set_view(index: int) -> void:
	view_index = index
	match index:
		0:
			camera.position = SHIP_POSITION + Vector3(38.0, 29.0, -48.0)
			camera.look_at(SHIP_POSITION + Vector3(0.0, 5.0, 0.0))
		1:
			camera.position = SHIP_POSITION + Vector3(90.0, 145.0, -100.0)
			camera.look_at(SHIP_POSITION)
		2:
			camera.position = Vector3(-90.0, 10.0, -220.0)
			camera.look_at(Vector3(420.0, 0.0, 160.0))

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	status = Label.new()
	status.position = Vector2(26.0, 22.0)
	status.add_theme_color_override("font_color", Color("fff0ca"))
	status.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	status.add_theme_constant_override("shadow_offset_x", 2)
	status.add_theme_constant_override("shadow_offset_y", 2)
	status.add_theme_font_size_override("font_size", 20)
	layer.add_child(status)

func _capture_sequence() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_ROOT))
	for index in VIEWS.size():
		_set_view(index)
		for seconds: float in CAPTURE_TIMES:
			simulation_time = seconds
			_apply_ocean_time()
			for frame in 12:
				await get_tree().process_frame
			await _capture("%s-t%s" % [VIEWS[index], str(seconds).replace(".", "_")])
	# Measure a settled native scene, separate from initial shader/import warmup.
	frame_times.clear()
	for frame in 180:
		await get_tree().process_frame
	frame_times.sort()
	metadata["frame_measurement"] = {"count": frame_times.size(), "median_ms": frame_times[frame_times.size() / 2], "p95_ms": frame_times[int(frame_times.size() * 0.95)], "view": VIEWS[view_index], "simulation_time": simulation_time, "animation_running": false, "note": "Frozen ocean/ship horizon view; CPU frame interval, not GPU elapsed or full-game performance"}
	var output := FileAccess.open(CAPTURE_ROOT + "/capture-metadata.json", FileAccess.WRITE)
	if output == null:
		_fail("Cannot write capture metadata: %d" % FileAccess.get_open_error())
		return
	output.store_string(JSON.stringify(metadata, "\t"))
	print("NATIVE_WATER_CAPTURE_COMPLETE ", JSON.stringify(metadata))
	get_tree().quit()

func _capture(label: String) -> void:
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_ROOT))
	if directory_error != OK:
		_fail("Cannot create screenshot directory: %d" % directory_error)
		return
	await RenderingServer.frame_post_draw
	var pixels := get_viewport().get_texture().get_image()
	if pixels == null or pixels.is_empty():
		_fail("Native viewport returned no pixels")
		return
	var path := CAPTURE_ROOT + "/" + label + ".png"
	var result := pixels.save_png(path)
	if result != OK:
		_fail("Screenshot save error %d" % result)
		return
	metadata["captures"].append({"path": path, "time": simulation_time, "view": VIEWS[view_index], "camera": [camera.position.x, camera.position.y, camera.position.z], "camera_transform": str(camera.global_transform), "width": pixels.get_width(), "height": pixels.get_height(), "utc": Time.get_datetime_string_from_system(true)})
	print("NATIVE_VIEWPORT_SAVED ", path)

func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
