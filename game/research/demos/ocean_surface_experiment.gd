extends Node3D
## Isolated observer of production Ocean. Host alone accepts fixed-step time.
const Ocean = preload("res://modules/scene_engine/ocean/projected_ocean.gd")
const Waves = preload("res://modules/physics_engine/ocean/wave_field.gd")
const STEP := 1.0 / 32.0
const MAX_CATCHUP := 8
const CAMERAS := ["camera_near", "camera_mid", "camera_horizon"]
const DEFAULTS := {"paused": false, "camera_mode": "camera_near", "optics_mode": "soft", "reflection_enabled": true, "refraction_enabled": true, "detail_strength": 1.0}
const SCOPE := "Independent shared production five-wave Ocean, shader, textures and projected ArrayMesh. Fixed opaque posts and submerged color tiles are optical calibration fixtures, not ships or terrain. No shore field: production deep-water fallback is -20m. Low-view projected coverage retains production limits. Legacy selects existing mirror-response uniform, not a historical game build. No campaign, RNG, new water shader or water algorithm; no full-game performance claim."

var _options: Dictionary = DEFAULTS.duplicate(true)
var _configured := false
var _ready_experiment := false
var _disposed := false
var _reason := ""
var _world: Node3D
var _camera: Camera3D
var _ocean: MeshInstance3D
var _waves: RefCounted
var _fixture_materials: Array[Material] = []
var _tick := 0
var _accumulator := 0.0
var _orbit_yaw := 0.0
var _orbit_pitch := 0.0
var _zoom := 1.0

func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	if _configured and not _disposed:
		_build_experiment()

func get_default_options() -> Dictionary:
	return DEFAULTS.duplicate(true)

func control_spec() -> Array:
	return [
		{"id": "camera_mode", "label": "固定镜头", "type": "choice", "value": _options.camera_mode, "choices": [{"value": "camera_near", "label": "近海"}, {"value": "camera_mid", "label": "中景"}, {"value": "camera_horizon", "label": "低位远景"}]},
		{"id": "optics_mode", "label": "光学响应", "type": "choice", "value": _options.optics_mode, "choices": [{"value": "soft", "label": "当前柔化"}, {"value": "legacy", "label": "旧镜面响应"}]},
		{"id": "reflection_enabled", "label": "实际平面镜像", "type": "toggle", "value": _options.reflection_enabled},
		{"id": "refraction_enabled", "label": "场景深度折射", "type": "toggle", "value": _options.refraction_enabled},
		{"id": "detail_strength", "label": "细节强度", "type": "range", "value": _options.detail_strength, "min": 0.0, "max": 2.0, "step": 0.05}
	]

func _validate(candidate: Dictionary) -> String:
	for key: String in candidate:
		if not DEFAULTS.has(key):
			return "unknown-parameter:" + key
	for key: String in ["paused", "reflection_enabled", "refraction_enabled"]:
		if not candidate[key] is bool:
			return "invalid-" + key
	if not candidate.camera_mode is String or candidate.camera_mode not in CAMERAS:
		return "invalid-camera_mode"
	if not candidate.optics_mode is String or candidate.optics_mode not in ["soft", "legacy"]:
		return "invalid-optics_mode"
	var detail: Variant = candidate.detail_strength
	if not (detail is float or detail is int) or not is_finite(float(detail)) or float(detail) < 0.0 or float(detail) > 2.0:
		return "invalid-detail_strength"
	return ""

func configure(options: Dictionary) -> Dictionary:
	var candidate: Dictionary = DEFAULTS.duplicate(true)
	candidate.merge(options.duplicate(true), true)
	var error := _validate(candidate)
	if not error.is_empty():
		return {"ok": false, "ready": _ready_experiment, "pending": false, "reason": error}
	dispose()
	_options = candidate
	_options.detail_strength = float(candidate.detail_strength)
	_configured = true
	_disposed = false
	_reason = ""
	_tick = 0
	_accumulator = 0.0
	_orbit_yaw = 0.0
	_orbit_pitch = 0.0
	_zoom = 1.0
	set_process(false)
	set_physics_process(false)
	if is_inside_tree():
		_build_experiment()
	return {"ok": _reason.is_empty(), "ready": _ready_experiment, "pending": not is_inside_tree(), "reason": _reason, "options": _options.duplicate(true)}

func set_parameter(id: String, value: Variant) -> Dictionary:
	if not DEFAULTS.has(id):
		return {"ok": false, "reset_required": false, "reason": "unknown-parameter:" + id}
	var candidate: Dictionary = _options.duplicate(true)
	candidate[id] = value
	var error := _validate(candidate)
	if not error.is_empty():
		return {"ok": false, "reset_required": false, "reason": error}
	_options = candidate
	_options.detail_strength = float(candidate.detail_strength)
	if id == "camera_mode":
		_orbit_yaw = 0.0
		_orbit_pitch = 0.0
		_zoom = 1.0
	_refresh()
	return {"ok": true, "reset_required": false, "value": _options[id], "time": _tick * STEP}

func reset_experiment(options: Dictionary = {}) -> Dictionary:
	var candidate: Dictionary = _options.duplicate(true)
	candidate.merge(options.duplicate(true), true)
	var observer := Vector3(_orbit_yaw, _orbit_pitch, _zoom)
	var receipt := configure(candidate)
	# Reset button preserves observer. Explicit camera input selects its fixed pose.
	if receipt.ok and not options.has("camera_mode"):
		_orbit_yaw = observer.x
		_orbit_pitch = observer.y
		_zoom = observer.z
		_refresh()
	return receipt

func advance(delta: float) -> void:
	if not _ready_experiment or _disposed or _options.paused or not is_finite(delta) or delta <= 0.0:
		return
	_accumulator += minf(delta, STEP * MAX_CATCHUP)
	var count := 0
	while _accumulator + 1.0e-12 >= STEP and count < MAX_CATCHUP:
		_tick += 1
		_accumulator -= STEP
		count += 1
	if count > 0:
		_refresh()

func set_paused(value: bool) -> void:
	_options.paused = value

func set_camera_mode(value: String) -> void:
	set_parameter("camera_mode", value)

func orbit_camera(yaw_delta: float, pitch_delta: float) -> void:
	if not is_finite(yaw_delta) or not is_finite(pitch_delta):
		return
	_orbit_yaw = fposmod(_orbit_yaw + yaw_delta, TAU)
	_orbit_pitch = clampf(_orbit_pitch + pitch_delta, -0.08, 0.8)
	_refresh()

func zoom_camera(amount: float) -> void:
	if not is_finite(amount):
		return
	_zoom = clampf(_zoom * exp(clampf(amount, -1.0, 1.0)), 0.6, 2.5)
	_refresh()

func _build_experiment() -> void:
	_world = Node3D.new()
	_world.name = "OceanExperimentWorld"
	add_child(_world)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("a0c8ff")
	settings.ambient_light_energy = 0.65
	environment.environment = settings
	_world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60.0, -35.0, 0.0)
	sun.light_energy = 1.5
	_world.add_child(sun)
	_camera = Camera3D.new()
	_camera.current = true
	_camera.fov = 50.0
	_camera.near = 0.2
	_camera.far = 3000.0
	_world.add_child(_camera)
	_update_camera()
	_waves = Waves.new()
	_ocean = Ocean.new()
	_ocean.name = "ProductionOcean"
	_world.add_child(_ocean)
	_ocean.configure(_camera, load("res://assets/textures/waternormals.jpg"), 96, 3000.0)
	_ocean.set_surface_quality("balanced")
	_ocean.set_projection_padding(0.18)
	_ocean.configure_reflection(_camera)
	_ocean.enable_surface_optics(true)
	var sky_material: ShaderMaterial = _ocean.get_sky_material()
	if sky_material == null:
		dispose()
		_reason = "production-sky-unavailable"
		return
	var sky := Sky.new()
	sky.sky_material = sky_material
	settings.sky = sky
	settings.background_mode = Environment.BG_SKY
	# Geometry fixtures demonstrate actual reflected objects and opaque depth.
	# Submerged targets stay below the maximum +/-3.5m production wave excursion.
	for index in 3:
		_add_target(Vector3(5.0, 12.0 + index * 3.0, 5.0), Vector3(-16.0 + index * 16.0, 4.0 + index * 1.5, -28.0), [Color("a14930"), Color("d4be88"), Color("253846")][index])
	for row in 3:
		for column in 3:
			_add_target(Vector3(9.0, 0.25, 10.0), Vector3((column - 1) * 10.0, -5.0, (row - 1) * 11.0), Color("be793d") if (row + column) % 2 == 0 else Color("344d60"))
	_ready_experiment = true
	_refresh()

func _add_target(size: Vector3, position_value: Vector3, color: Color) -> void:
	var node := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	node.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	node.material_override = material
	_fixture_materials.append(material)
	_world.add_child(node)
	node.position = position_value

func _refresh() -> void:
	if not _ready_experiment or _disposed:
		return
	_update_camera()
	_ocean.set_simulation_time(_tick * STEP)
	_ocean.set_reference_surface_state({"strength": _options.detail_strength})
	_ocean.set_reflection_enabled(_options.reflection_enabled)
	_ocean.set_refraction_enabled(_options.refraction_enabled)
	_ocean.material_override.set_shader_parameter("water_legacy_optics", _options.optics_mode == "legacy")
	_ocean.update_projection()

func _update_camera() -> void:
	if not is_instance_valid(_camera):
		return
	var eye: Vector3 = {"camera_near": Vector3(20.0, 8.0, 26.0), "camera_mid": Vector3(70.0, 28.0, 120.0), "camera_horizon": Vector3(0.0, 7.0, 180.0)}[_options.camera_mode]
	var focus := Vector3(0.0, 0.0, -12.0) if _options.camera_mode != "camera_horizon" else Vector3(0.0, 1.0, -220.0)
	var offset := (eye - focus).rotated(Vector3.UP, _orbit_yaw)
	var right := Vector3.UP.cross(offset).normalized()
	offset = offset.rotated(right, _orbit_pitch) * _zoom
	_camera.position = focus + offset
	_camera.position.y = maxf(4.5, _camera.position.y)
	_camera.look_at(focus)

static func _matrix_values(value: Projection) -> Array:
	var result: Array = []
	for column: Vector4 in [value.x, value.y, value.z, value.w]:
		result.append_array([column.x, column.y, column.z, column.w])
	return result

func inspection_snapshot() -> Dictionary:
	var state := {"ready": _ready_experiment, "disposed": _disposed, "reason": _reason, "topic": "ocean-surface", "tick": _tick, "time": _tick * STEP, "fixed_step": STEP, "paused": _options.paused, "camera_mode": _options.camera_mode, "parameters": _options.duplicate(true), "seed": "not_applicable", "rng_state": "not_applicable", "scope": SCOPE, "camera_transform": [], "camera_projection": [], "camera_parameters": {}, "camera_controls": {"orbit_yaw": _orbit_yaw, "orbit_pitch": _orbit_pitch, "zoom": _zoom}, "viewport_size": [], "resources": {"world": 0, "ocean": 0, "mirror": 0, "ship": 0, "fixtures": 0, "materials": 0, "wave_owner": 0}, "telemetry": {}}
	if not _ready_experiment:
		return state
	state.camera_transform = _matrix_values(Projection(_camera.get_camera_transform()))
	state.camera_projection = _matrix_values(_camera.get_camera_projection())
	state.camera_parameters = {"projection": _camera.projection, "fov": _camera.fov, "near": _camera.near, "far": _camera.far, "keep_aspect": _camera.keep_aspect, "size": _camera.size, "frustum_offset": [_camera.frustum_offset.x, _camera.frustum_offset.y], "h_offset": _camera.h_offset, "v_offset": _camera.v_offset, "cull_mask": _camera.cull_mask}
	var dimensions := _camera.get_viewport().get_visible_rect().size
	state.viewport_size = [int(dimensions.x), int(dimensions.y)]
	var mirror: SubViewport = _ocean.get_reflection_viewport()
	state.resources = {"world": 1, "ocean": 1, "mirror": 1 if is_instance_valid(mirror) else 0, "ship": 0, "fixtures": _fixture_materials.size(), "materials": _fixture_materials.size() + 2, "wave_owner": 1}
	var material: ShaderMaterial = _ocean.material_override
	var uniforms := {}
	for key: String in ["simulation_time", "u_time", "u_strength", "water_legacy_optics", "u_use_reflection", "u_refraction_enabled"]:
		uniforms[key] = material.get_shader_parameter(key)
	var optics: Dictionary = _ocean.get_surface_optics_diagnostics()
	var reflection_size: Vector2i = optics.get("reflection_size", Vector2i.ZERO)
	optics.reflection_size = [reflection_size.x, reflection_size.y]
	state.telemetry = {"uniforms": uniforms, "wave_count": material.get_shader_parameter("wave_count"), "wave_samples": [_waves.sample_height(0.0, 0.0, state.time), _waves.sample_height(25.0, -12.0, state.time), _waves.sample_height(-45.0, 75.0, state.time)], "shader": material.shader.resource_path, "normal_texture": material.get_shader_parameter("normal_texture").resource_path, "carrier": "production-projected-ArrayMesh", "vertices": _ocean.mesh.surface_get_array_len(0), "quality": "balanced", "optics": optics, "projection_work": _ocean.get_projection_work_diagnostics()}
	return state

func dispose() -> void:
	_ready_experiment = false
	_disposed = true
	# Explicit production shutdown frees mirror before its shared-world parent.
	if is_instance_valid(_ocean):
		_ocean.set_visual_style(0)
	if is_instance_valid(_world):
		_world.free()
	_world = null
	_camera = null
	_ocean = null
	_waves = null
	_fixture_materials.clear()
	_accumulator = 0.0

func _exit_tree() -> void:
	dispose()
