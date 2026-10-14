extends Node3D
## Isolation and inspection adapter for unchanged production weather/atmosphere.
## Laboratory alone advances accepted time. Visibility never advances producers.
const Weather = preload("res://modules/environment_engine/weather_state.gd")
const Atmosphere = preload("res://modules/scene_engine/fidelity_fx/atmosphere.gd")
const Effects = preload("res://modules/scene_engine/fidelity_fx/presentation.gd")
const TransformTrial = preload("res://game/research/demos/cloud_transform_trial.gd")
const SkyShader = preload("res://modules/scene_engine/reference_island_water/reference_sky.gdshader")
const STEP := 1.0 / 32.0
const MAX_CATCHUP := 8
const PRESETS := ["clear", "storm", "sunset"]
const CAMERAS := ["overview", "sky", "ground"]
const DEFAULTS := {"preset": "clear", "camera_mode": "overview", "sky_enabled": true, "clouds_enabled": true, "shadows_enabled": true, "cpu_transform_batching": true, "paused": false, "crt_seed": 1, "sky_crt_seed": 1, "orbit_yaw": 0.0, "orbit_pitch": 0.0, "zoom": 1.0}
const SCOPE := "Unchanged production WeatherState integer three-center rules and explicit CRT RNG; Atmosphere original domecloud1..5 rotation, stormcloud_sound/KF, two cloud00 actors, full DDS mips and baked texture-shadow records. Fixed 32Hz and 10 source units/m are target adapters; sky shader and sun energy are Godot adapters. Clear/storm/sunset are declared initial-state fixtures, not an original weather enum. DIAGNOSTIC RECEIVER: unlit 5m calibration grid above unchanged source-color static sea, not original sea color or landscape. Fixed overview frames center0's first two accepted seconds; ground uses orthographic magnification, native modelScale remains 1. No campaign, ocean-wave, reflection, rain or full native pixel parity claim. Visibility controls never modify accepted weather, sky or controller state."
const RECEIVER_EXTENT := 10000.0
const GRID_SPACING := 5.0

var _options: Dictionary = DEFAULTS.duplicate(true)
var _configured := false
var _ready_experiment := false
var _disposed := false
var _reason := ""
var _tick := 0
var _accumulator := 0.0
var _weather: RefCounted
var _atmosphere: RefCounted
var _world: Node3D
var _camera: Camera3D
var _sun: DirectionalLight3D
var _environment: Environment
var _sky_material: ShaderMaterial
var _sea_material: StandardMaterial3D
var _calibration_material: StandardMaterial3D
var _grid_texture: ImageTexture
var _diagnostic_label: Label
var _packet: Dictionary = {}
var _source_options: Dictionary = {}
var _sky_records: Array = []
var _cloud_records: Array = []
var _shadow_records: Array = []

func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	if _configured and not _disposed:
		_build_experiment()

func get_default_options() -> Dictionary:
	return DEFAULTS.duplicate(true)

func _validated(options: Dictionary) -> Dictionary:
	for key: String in options:
		if not DEFAULTS.has(key):
			return {"ok": false, "reason": "unknown-" + key}
	var candidate: Dictionary = DEFAULTS.duplicate(true)
	candidate.merge(options.duplicate(true), true)
	if not candidate.preset is String or candidate.preset not in PRESETS:
		return {"ok": false, "reason": "invalid-preset"}
	if not candidate.camera_mode is String or candidate.camera_mode not in CAMERAS:
		return {"ok": false, "reason": "invalid-camera_mode"}
	for key: String in ["paused", "sky_enabled", "clouds_enabled", "shadows_enabled", "cpu_transform_batching"]:
		if not candidate[key] is bool:
			return {"ok": false, "reason": "invalid-" + key}
	for key: String in ["crt_seed", "sky_crt_seed"]:
		var value: Variant = candidate[key]
		if not value is int or value < 0 or value > 4294967295:
			return {"ok": false, "reason": "invalid-" + key}
	for key: String in ["orbit_yaw", "orbit_pitch", "zoom"]:
		var value: Variant = candidate[key]
		if not (value is int or value is float) or not is_finite(float(value)):
			return {"ok": false, "reason": "invalid-" + key}
	if float(candidate.zoom) <= 0.0:
		return {"ok": false, "reason": "invalid-zoom"}
	candidate.orbit_yaw = fposmod(float(candidate.orbit_yaw), TAU)
	candidate.orbit_pitch = clampf(float(candidate.orbit_pitch), -0.45, 0.8)
	candidate.zoom = clampf(float(candidate.zoom), 0.6, 2.5)
	return {"ok": true, "options": candidate}

func configure(options: Dictionary) -> Dictionary:
	var validated := _validated(options)
	if not validated.ok:
		return {"ok": false, "ready": _ready_experiment, "pending": false, "reason": validated.reason}
	dispose()
	_options = validated.options
	_configured = true
	_disposed = false
	_reason = ""
	_tick = 0
	_accumulator = 0.0
	set_process(false)
	set_physics_process(false)
	if is_inside_tree():
		_build_experiment()
	return {"ok": _reason.is_empty(), "ready": _ready_experiment, "pending": not is_inside_tree(), "reason": _reason, "options": _options.duplicate(true)}

func reset_experiment(options: Dictionary = {}) -> Dictionary:
	var candidate: Dictionary = _options.duplicate(true)
	candidate.merge(options.duplicate(true), true)
	var receipt := configure(candidate)
	if receipt.ok:
		receipt.snapshot = inspection_snapshot()
	return receipt

func control_spec() -> Array:
	return [
		{"id": "preset", "label": "初态预设（重置）", "type": "choice", "value": _options.preset, "choices": [{"value": "clear", "label": "晴天基准"}, {"value": "storm", "label": "风暴中心近景"}, {"value": "sunset", "label": "黄昏光照"}]},
		{"id": "sky_enabled", "label": "天空云环", "type": "toggle", "value": _options.sky_enabled},
		{"id": "clouds_enabled", "label": "三中心天气云", "type": "toggle", "value": _options.clouds_enabled},
		{"id": "shadows_enabled", "label": "烘焙纹理云影", "type": "toggle", "value": _options.shadows_enabled},
		{"id": "cpu_transform_batching", "label": "CPU矩阵批量存储（逐值对照）", "type": "toggle", "value": _options.cpu_transform_batching},
		{"id": "camera_mode", "label": "固定观察镜头", "type": "choice", "value": _options.camera_mode, "choices": [{"value": "overview", "label": "云与影近景（校准地面）"}, {"value": "sky", "label": "天空"}, {"value": "ground", "label": "云影俯视（校准地面）"}]}
	]

func set_parameter(id: String, value: Variant) -> Dictionary:
	if id not in ["preset", "sky_enabled", "clouds_enabled", "shadows_enabled", "cpu_transform_batching", "camera_mode"]:
		return {"ok": false, "reason": "unknown-parameter", "reset_required": false}
	var candidate: Dictionary = _options.duplicate(true)
	candidate[id] = value
	var validated := _validated(candidate)
	if not validated.ok:
		return {"ok": false, "reason": validated.reason, "reset_required": false}
	if id == "preset" and value != _options.preset:
		return {"ok": true, "reset_required": true, "id": id, "value": value, "reason": "initial-state-preset"}
	if id == "camera_mode":
		set_camera_mode(value)
	else:
		_options[id] = value
		if id == "cpu_transform_batching" and _atmosphere: _atmosphere.get("_render_compiler").batched = value
		_refresh_presentation()
	return {"ok": true, "reset_required": false, "id": id, "value": value}

func advance(delta: float) -> void:
	if not _ready_experiment or _disposed or _options.paused or not is_finite(delta) or delta <= 0.0:
		return
	_accumulator += minf(delta, STEP * MAX_CATCHUP)
	var count := 0
	while _accumulator + 1.0e-12 >= STEP and count < MAX_CATCHUP:
		_tick += 1
		_packet = _weather.advance(_tick * STEP, {"position": Vector2.ZERO, "heading": 0.0, "route": "weather-shadow-laboratory"}, {"speed": 0.0})
		_refresh_presentation()
		_accumulator -= STEP
		count += 1

func set_paused(value: bool) -> void:
	_options.paused = value

func set_camera_mode(value: String) -> void:
	if value not in CAMERAS:
		return
	_options.camera_mode = value
	_options.orbit_yaw = 0.0
	_options.orbit_pitch = 0.0
	_options.zoom = 1.0
	_update_camera()
	_refresh_presentation()

func orbit_camera(yaw_delta: float, pitch_delta: float) -> void:
	if not is_finite(yaw_delta) or not is_finite(pitch_delta):
		return
	_options.orbit_yaw = fposmod(float(_options.orbit_yaw) + yaw_delta, TAU)
	_options.orbit_pitch = clampf(float(_options.orbit_pitch) + pitch_delta, -0.45, 0.8)
	_update_camera()
	_refresh_presentation()

func zoom_camera(amount: float) -> void:
	if not is_finite(amount):
		return
	_options.zoom = clampf(float(_options.zoom) * exp(clampf(amount, -1.0, 1.0)), 0.6, 2.5)
	_update_camera()
	_refresh_presentation()

func _build_experiment() -> void:
	_world = Node3D.new()
	_world.name = "WeatherShadowArena"
	add_child(_world)
	_camera = Camera3D.new()
	_camera.name = "WeatherObserver"
	_camera.fov = 55.0
	_camera.near = 0.1
	_camera.far = 4000.0
	_world.add_child(_camera)
	_camera.current = true
	_update_camera()
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_SKY
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_energy = 0.75
	_sky_material = ShaderMaterial.new()
	_sky_material.shader = SkyShader
	var sky := Sky.new()
	sky.sky_material = _sky_material
	_environment.sky = sky
	var world_environment := WorldEnvironment.new()
	world_environment.environment = _environment
	_world.add_child(world_environment)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = false
	_world.add_child(_sun)
	_sea_material = StandardMaterial3D.new()
	_sea_material.roughness = 0.9
	_plane("StaticSeaObservationCarrier", Vector2(20000.0, 20000.0), Vector3(350.0, -0.02, 0.0), _sea_material)
	_calibration_material = StandardMaterial3D.new()
	_calibration_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_calibration_material.roughness = 1.0
	_grid_texture = _make_grid_texture()
	_calibration_material.albedo_texture = _grid_texture
	_calibration_material.uv1_scale = Vector3(RECEIVER_EXTENT / GRID_SPACING, RECEIVER_EXTENT / GRID_SPACING, 1.0)
	_plane("DiagnosticUnlit5mGridReceiver", Vector2(RECEIVER_EXTENT, RECEIVER_EXTENT), Vector3(350.0, 0.0, 0.0), _calibration_material)
	var overlay := CanvasLayer.new()
	overlay.name = "DiagnosticReceiverDisclosure"
	_world.add_child(overlay)
	_diagnostic_label = Label.new()
	_diagnostic_label.position = Vector2(16.0, 12.0)
	_diagnostic_label.add_theme_color_override("font_color", Color(0.98, 0.97, 0.88))
	_diagnostic_label.add_theme_color_override("font_shadow_color", Color(0.05, 0.08, 0.10))
	_diagnostic_label.add_theme_constant_override("shadow_offset_x", 1)
	_diagnostic_label.add_theme_constant_override("shadow_offset_y", 1)
	_diagnostic_label.add_theme_font_size_override("font_size", 16)
	_diagnostic_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_diagnostic_label)
	_source_options = {"epoch": 1, "crt_seed": _options.crt_seed, "sky_crt_seed": _options.sky_crt_seed, "source_calls_per_second": 32.0, "source_position_units_per_metre": 10.0, "model_scale": 1.0, "hold_light": true, "route": "weather-shadow-laboratory", "initial_state": {"lightTime": 1930 if _options.preset == "sunset" else 1200, "windHeading": 1073741760, "windDisplacement": 0, "windVelocity": 0, "centers": [{"x": 2000 if _options.preset == "storm" else 8000, "y": 0}, {"x": 3000, "y": 4000}, {"x": 6000, "y": -4000}]}}
	_weather = Weather.new()
	if not _weather.configure(_source_options):
		_fail_build("weather-configuration-failed")
		return
	_packet = _weather.snapshot()
	_atmosphere = Atmosphere.new()
	var trial := TransformTrial.new()
	trial.batched = _options.cpu_transform_batching
	_atmosphere.set("_render_compiler", trial)
	var receipt: Dictionary = _atmosphere.configure(_world, Effects.load_manifest(), {"crt_seed": _options.sky_crt_seed, "cloud_sky_radius": 1600.0, "cloud_sky_height": 380.0, "cloud_bounds_layer": true, "cloud_min_height": 80.0, "cloud_height_variation": 40.0, "fog_placements": [], "cloud_shadow_surface_height": 0.12, "cloud_shadow_opacity": 0.38})
	if not receipt.get("ok", false):
		_fail_build(String(receipt.get("error", "atmosphere-configuration-failed")))
		return
	# Production renderer owns records and resources. This local adapter retains
	# references only to gate current visibility after its normal packet update.
	for group: Array in _atmosphere.get("_clouds"):
		_sky_records.append_array(group)
	for actor: Dictionary in _atmosphere.get("_weather"):
		for record: Dictionary in actor.meshes:
			if record.get("bakedShadow", false):
				_shadow_records.append(record)
			else:
				_cloud_records.append(record)
	_ready_experiment = true
	_refresh_presentation()

func _plane(label: String, size: Vector2, position_value: Vector3, material: Material) -> void:
	var node := MeshInstance3D.new()
	node.name = label
	var mesh := PlaneMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.position = position_value
	_world.add_child(node)

func _make_grid_texture() -> ImageTexture:
	# Synthetic calibration texture only. Native DDS bytes/mips remain untouched.
	var image := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:
			var color := Color(0.56, 0.58, 0.54)
			if x < 4 or y < 4:
				color = Color(0.40, 0.43, 0.41)
			image.set_pixel(x, y, color)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

func _update_camera() -> void:
	if not is_instance_valid(_camera):
		return
	# Fixed midpoint of center0's declared 0..2s observation window. Never follows
	# packet position; motion remains visible against the stationary 5m grid.
	var initial_x := 200.0 if _options.preset == "storm" else 800.0
	var target := Vector3(initial_x - 96.0, 18.0, 0.0)
	var offset := Vector3(0.0, 82.0, 128.0)
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	if _options.camera_mode == "sky":
		target = Vector3(400.0, 180.0, 0.0)
		offset = Vector3(0.0, -135.0, 500.0)
	elif _options.camera_mode == "ground":
		target = Vector3(initial_x - 96.0, 0.0, 0.0)
		offset = Vector3(0.0, 160.0, 40.0)
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.size = 180.0 * float(_options.zoom)
	offset = Basis(Vector3.UP, float(_options.orbit_yaw)) * Basis(Vector3.RIGHT, float(_options.orbit_pitch)) * offset
	_camera.position = target + offset * float(_options.zoom)
	_camera.look_at(target, Vector3.UP)

func _refresh_presentation() -> void:
	if not _ready_experiment or _disposed or _packet.is_empty():
		return
	_atmosphere.apply_snapshot({"environment": _packet}, _camera, Vector3.ZERO)
	for pair: Array in [[_sky_records, _options.sky_enabled], [_cloud_records, _options.clouds_enabled], [_shadow_records, _options.shadows_enabled]]:
		if not pair[1]:
			for record: Dictionary in pair[0]:
				record.node.visible = false
	var light: Dictionary = _packet.lighting.target
	var direction := Vector3(float(light.direction[0]), float(light.direction[1]), float(light.direction[2])).normalized()
	_sun.basis = Basis.looking_at(-direction, Vector3.RIGHT if absf(direction.dot(Vector3.UP)) > 0.999 else Vector3.UP)
	_sun.light_color = Color(float(light.color[0]), float(light.color[1]), float(light.color[2]))
	_sun.light_energy = float(light.energy)
	_environment.ambient_light_color = Color(float(light.ambientColor[0]), float(light.ambientColor[1]), float(light.ambientColor[2]))
	_sky_material.set_shader_parameter("u_sun", direction)
	_sky_material.set_shader_parameter("u_sun_color", Vector3(float(light.color[0]), float(light.color[1]), float(light.color[2])))
	_sky_material.set_shader_parameter("u_time", _tick * STEP)
	_sky_material.set_shader_parameter("u_eye", _camera.global_position)
	_sea_material.albedo_color = Color(float(light.waterColor[0]), float(light.waterColor[1]), float(light.waterColor[2]))
	_diagnostic_label.text = "天空云环 · 原资源 / 原接受时间" if _options.camera_mode == "sky" else "诊断接收面 · 5米网格 · 云与影保持原尺寸 / 原时间"

static func _matrix_values(value: Projection) -> Array:
	var values: Array = []
	for column: Vector4 in [value.x, value.y, value.z, value.w]:
		values.append_array([column.x, column.y, column.z, column.w])
	return values

static func _visible(records: Array) -> int:
	var count := 0
	for record: Dictionary in records:
		if is_instance_valid(record.node) and record.node.visible:
			count += 1
	return count

func inspection_snapshot() -> Dictionary:
	var viewport_size := Vector2i.ZERO
	var camera: Dictionary = {}
	if is_instance_valid(_camera):
		viewport_size = Vector2i(_camera.get_viewport().get_visible_rect().size)
		camera = {"mode": _options.camera_mode, "transform": _matrix_values(Projection(_camera.get_camera_transform())), "projection": _matrix_values(_camera.get_camera_projection()), "projection_type": "orthographic" if _camera.projection == Camera3D.PROJECTION_ORTHOGONAL else "perspective", "orthographic_size_m": _camera.size if _camera.projection == Camera3D.PROJECTION_ORTHOGONAL else 0.0, "fov_degrees": _camera.fov, "near_m": _camera.near, "far_m": _camera.far}
	var renderer: Dictionary = _atmosphere.diagnostics() if _atmosphere else {}
	var resources := {"weather": 1 if _weather else 0, "atmosphere": 1 if _atmosphere else 0, "world": 1 if is_instance_valid(_world) else 0, "meshes": _sky_records.size() + _cloud_records.size() + _shadow_records.size() + (2 if _ready_experiment else 0), "textures": (_atmosphere.get("_textures").size() if _atmosphere else 0) + (1 if _grid_texture else 0), "materials": _sky_records.size() + _cloud_records.size() + _shadow_records.size() + (3 if _ready_experiment else 0)}
	var rng := {"weather": {"seed_decimal": str(_options.crt_seed), "state_decimal": str(_packet.get("source", {}).get("rngState", 0)), "draws": int(_packet.get("source", {}).get("rngDraws", 0)), "word_bits": 32}, "sky": {"seed_decimal": str(_options.sky_crt_seed), "initialization_draws": int(_packet.get("sky", {}).get("ring", {}).get("draws", 0)), "live_rng": "none after deterministic initialization; native ring packet does not retain initializer RNG state", "word_bits": 32}}
	var observation := {"diagnostic_surface": true, "grid_spacing_m": GRID_SPACING, "surface_extent_m": RECEIVER_EXTENT, "surface_material": "unlit calibration texture; not original sea/land color", "camera_anchor": [(200.0 if _options.preset == "storm" else 800.0) - 96.0, 0.0, 0.0], "native_model_scale": 1.0, "fixed_observation_window_seconds": [0.0, 2.0], "overlay_label": _diagnostic_label.text if is_instance_valid(_diagnostic_label) else ""}
	return {"topic": "weather-shadow", "ready": _ready_experiment, "disposed": _disposed, "reason": _reason, "tick": _tick, "time": _tick * STEP, "step_seconds": STEP, "max_catchup": MAX_CATCHUP, "paused": _options.paused, "parameters": _options.duplicate(true), "camera_mode": _options.camera_mode, "camera": camera, "viewport": [viewport_size.x, viewport_size.y], "resources": resources, "scope": SCOPE, "rng": rng, "environment": _packet.duplicate(true), "observation": observation, "inputs": {"weather_options": _source_options.duplicate(true), "observer": {"position": [0.0, 0.0], "heading": 0.0}, "wind": {"speed": 0.0}, "preset_scope": "target fixed initial lightTime/centers; original scene day modes are not weather presets"}, "telemetry": {"world_weather_instances": int(renderer.get("worldWeatherInstances", 0)), "sky_clones": int(renderer.get("cloudClones", 0)), "sky_meshes": _sky_records.size(), "world_cloud_meshes": _cloud_records.size(), "shadow_meshes": _shadow_records.size(), "visible_sky_meshes": _visible(_sky_records), "visible_world_cloud_meshes": _visible(_cloud_records), "visible_shadow_meshes": _visible(_shadow_records), "source_calls": int(_packet.get("sourceCallIndex", 0)), "renderer": renderer, "weather": _weather.diagnostics() if _weather else {}}}

func _fail_build(reason: String) -> void:
	dispose()
	_reason = reason

func dispose() -> void:
	_ready_experiment = false
	_disposed = true
	if _atmosphere:
		_atmosphere.dispose()
	_atmosphere = null
	_weather = null
	_sky_records.clear()
	_cloud_records.clear()
	_shadow_records.clear()
	if is_instance_valid(_world):
		remove_child(_world)
		_world.free()
	_world = null
	_camera = null
	_sun = null
	_environment = null
	_sky_material = null
	_sea_material = null
	_calibration_material = null
	_grid_texture = null
	_diagnostic_label = null
	_packet.clear()
	_source_options.clear()
	_accumulator = 0.0

func _exit_tree() -> void:
	dispose()
