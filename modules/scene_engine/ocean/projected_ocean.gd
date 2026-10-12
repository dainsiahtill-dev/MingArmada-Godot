extends MeshInstance3D

const WATER_SHADER := preload("res://modules/scene_engine/ocean/original_water.gdshader")
const OPTICS_SHADER := preload("res://modules/scene_engine/ocean/original_water_optics.gdshader")
const SurfaceOptics = preload("res://modules/scene_engine/ocean/surface_optics.gd")
const REFERENCE_GAME_SHADER = preload("res://modules/scene_engine/ocean/reference_game_water.gdshader")
const ReferenceRenderer = preload("res://modules/scene_engine/reference_island_water/ocean_renderer.gd")
const Descriptor = preload("res://modules/contracts/wave_descriptor.gd")
const WaveUniforms = preload("res://modules/scene_engine/ocean/wave_uniforms.gd")
const REFERENCE_SPARKLE = preload("res://assets/textures/pirates_reference/02_sparkle_b.dds.png")
const REFERENCE_ORIGINAL_SPARKLE = preload("res://assets/textures/pirates_reference/water_spaarkle.dds.png")
const REFERENCE_DEEP = preload("res://assets/textures/pirates_reference/duel_ocean deep.dds.png")
const REFERENCE_SURFACE = preload("res://assets/textures/pirates_reference/water.dds.png")
const REFERENCE_CAUSTICS = preload("res://assets/textures/pirates_reference/duel_waterdetail.dds.png")
const REFERENCE_FOAM_A = preload("res://assets/textures/pirates_reference/foam0008.dds.png")
const REFERENCE_FOAM_B = preload("res://assets/textures/pirates_reference/foam0009.dds.png")
const REFERENCE_WHITECAPS = preload("res://assets/textures/pirates_reference/foam0024.dds.png")
const MINIMUM_RESOLUTION := 16
const UNBOUNDED_FALLBACK_DISTANCE := 2500.0

var _camera: Camera3D
var _segments := 80
var _maximum_distance := 3000.0
var _has_maximum_distance := true
var _fallback_distance := 3000.0
var _simulation_time := 0.0
var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _uvs := PackedVector2Array()
var _indices := PackedInt32Array()
var _projected_mesh: ArrayMesh
var _water_material: ShaderMaterial
var _shore_texture: Texture2D
var _coast_texture: Texture2D
var _shore_bounds := Vector4.ZERO
var _visual_style := 1
var _descriptors: Array = Descriptor.original_descriptors()
var _projection_initialized := false
var _last_camera_transform := Transform3D.IDENTITY
var _last_camera_projection := Projection()
var _last_world_transform := Transform3D.IDENTITY
var _last_viewport_size := Vector2.ZERO
var _projection_padding := 0.0
var _surface_optics := SurfaceOptics.new()
var _reference_renderer: Node3D
var _original_layers := 1
var _layers_saved := false
var _near_shore_texture: Texture2D
var _near_shore_bounds := Vector4.ZERO
var _reference_state := {"preset":"clear","strength":1.0,"tide":0.0,"foamWidth":1.5,"waves":true,"reflection":true,"foam":true,"caustics":true}

func configure(camera: Camera3D, normal_texture: Texture2D, resolution: int = 80, max_distance: float = 3000.0) -> void:
	_camera = camera
	if _surface_optics.camera != _camera: _surface_optics.camera = null
	_segments = maxi(MINIMUM_RESOLUTION, resolution)
	_has_maximum_distance = is_finite(max_distance) and max_distance > 0.0
	_maximum_distance = max_distance if _has_maximum_distance else INF
	_fallback_distance = max_distance if _has_maximum_distance else UNBOUNDED_FALLBACK_DISTANCE
	if _water_material == null:
		_water_material = ShaderMaterial.new()
		_water_material.shader = WATER_SHADER
		_water_material.render_priority = 1
		# Bind the formal optical profile once. Owner updates must not reset the
		# same-camera legacy comparison or change the full body/detail normals.
		_water_material.set_shader_parameter("water_legacy_optics",false)
		_water_material.set_shader_parameter("water_environment_ripple_gain",0.16)
		_water_material.set_shader_parameter("water_environment_horizon_weight",0.52)
	_water_material.set_shader_parameter("normal_texture", normal_texture)
	_water_material.set_shader_parameter("reference_sparkle_texture", REFERENCE_SPARKLE)
	_water_material.set_shader_parameter("reference_original_sparkle_texture", REFERENCE_ORIGINAL_SPARKLE)
	_water_material.set_shader_parameter("reference_deep_texture", REFERENCE_DEEP)
	_water_material.set_shader_parameter("reference_surface_texture", REFERENCE_SURFACE)
	_water_material.set_shader_parameter("reference_caustics_texture", REFERENCE_CAUSTICS)
	_water_material.set_shader_parameter("has_reference_water_textures", true)
	_water_material.set_shader_parameter("reference_whitecaps_texture", REFERENCE_WHITECAPS)
	_water_material.set_shader_parameter("coastal_foam_texture_a", REFERENCE_FOAM_A)
	_water_material.set_shader_parameter("coastal_foam_texture_b", REFERENCE_FOAM_B)
	_water_material.set_shader_parameter("has_coastal_foam_textures", true)
	_water_material.set_shader_parameter("simulation_time", _simulation_time)
	_water_material.set_shader_parameter("visual_style", _visual_style)
	_water_material.set_shader_parameter("coastal_attenuation", _visual_style == 1)
	set_wave_descriptors(_descriptors)
	if _shore_texture != null:
		set_shore_field(_shore_texture, _shore_bounds, _coast_texture)
	material_override = _water_material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ignore_occlusion_culling = true
	# The CPU mesh lies on y=0, while the shader may displace it by +/-3.5m.
	extra_cull_margin = 8.0
	_create_grid()
	_projection_initialized = false
	_update_surface_optics()
	update_projection()

func set_surface_wind(direction: Vector2, speed: float) -> void:
	if _water_material == null or not direction.is_finite() or not is_finite(speed): return
	# Scale before normalizing: large finite values must not overflow length².
	var largest := maxf(absf(direction.x),absf(direction.y))
	var heading := (direction / largest).normalized() if largest > 0.0 else Vector2.RIGHT
	_water_material.set_shader_parameter("surface_wind_direction", heading)
	_water_material.set_shader_parameter("surface_wind_speed", clampf(speed,0.0,60.0))

func set_surface_quality(quality: String) -> void:
	_surface_optics.quality = quality if quality in ["low", "balanced", "high"] else "balanced"
	if _water_material:
		_water_material.set_shader_parameter("surface_detail_strength", {"low":0.05,"balanced":0.09,"high":0.13}.get(quality,0.09))
	_update_surface_optics()

func configure_reflection(camera: Camera3D) -> void:
	# Main screen/depth stay viewport-local; mirror color uses the same World3D.
	_surface_optics.camera = camera if camera == _camera else null
	_update_surface_optics()

func enable_surface_optics(enabled: bool = true) -> void:
	_surface_optics.enabled = enabled
	_update_surface_optics()

func set_reflection_enabled(enabled: bool) -> void:
	_surface_optics.reflection_enabled = enabled
	_update_surface_optics()

func set_refraction_enabled(enabled: bool) -> void:
	_surface_optics.refraction_enabled = enabled
	_update_surface_optics()

func get_surface_optics_diagnostics() -> Dictionary:
	var result: Dictionary = _surface_optics.diagnostics()
	result.enabled=bool(result.enabled) and is_inside_tree()
	result.reflection_method="planar-subviewport" if _visual_style==1 else "disabled"
	result.reflection_steps=0
	result.reflection_enabled=bool(result.enabled) and _surface_optics.reflection_enabled
	result.refraction_enabled=bool(result.enabled) and _surface_optics.refraction_enabled
	result.offscreen_targets=0
	# This target draws the normal shared World3D 3D pass, including its
	# transparent materials. These describe the path/capability, not a count of
	# visible transparent objects or a claim that the scene currently has any.
	result.transparent_objects_supported=_visual_style==1
	result.includes_transparent_objects=false
	result.includes_offscreen_objects=false
	result.wave_profile="authoritative-five-wave"
	if is_instance_valid(_reference_renderer):
		var mirror: Dictionary=_reference_renderer.diagnostics()
		result.offscreen_targets=mirror.offscreenTargets
		result.shared_world=mirror.sharedWorld
		result.water_layer_excluded=mirror.waterLayerExcluded
		result.reflection_size=mirror.reflectionSize
		result.accepted_time=mirror.acceptedTime
		result.reflection_enabled=mirror.reflectionEnabled
		result.includes_transparent_objects=mirror.reflectionEnabled
		result.includes_offscreen_objects=mirror.reflectionEnabled
	return result

func _update_surface_optics() -> void:
	if _water_material == null: return
	_surface_optics.visual_style = _visual_style
	var active := bool(_surface_optics.diagnostics().enabled) and is_inside_tree()
	var shader: Shader = REFERENCE_GAME_SHADER if _visual_style==1 else WATER_SHADER
	if _water_material.shader != shader: _water_material.shader = shader
	if _visual_style==0:
		if is_instance_valid(_reference_renderer):
			_reference_renderer.dispose(); _reference_renderer.free(); _reference_renderer=null
		if _layers_saved: layers=_original_layers
		_surface_optics.apply(_water_material)
		return
	if not _layers_saved: _original_layers=layers; _layers_saved=true
	layers=ReferenceRenderer.WATER_LAYER
	if not is_instance_valid(_reference_renderer):
		_reference_renderer=ReferenceRenderer.new(); _reference_renderer.name="IntegratedReferenceWater"
		add_child(_reference_renderer)
		_reference_renderer.attach_surface(self,_water_material,_camera if is_instance_valid(_camera) else null)
	_water_material.set_shader_parameter("wave_components",WaveUniforms.components(_descriptors))
	_water_material.set_shader_parameter("wave_count",_descriptors.size())
	_water_material.set_shader_parameter("simulation_time",_simulation_time)
	_water_material.set_shader_parameter("visual_style",_visual_style)
	_water_material.set_shader_parameter("coastal_attenuation",true)
	_water_material.set_shader_parameter("shore_height_texture",_shore_texture)
	_water_material.set_shader_parameter("coast_distance_texture",_coast_texture)
	_water_material.set_shader_parameter("has_coast_distance",_coast_texture!=null and _coast_texture.get_width()>1 and _coast_texture.get_height()>1)
	_water_material.set_shader_parameter("shore_bounds",_shore_bounds)
	_water_material.set_shader_parameter("has_shore_field",_shore_texture!=null and _shore_bounds.z>_shore_bounds.x and _shore_bounds.w>_shore_bounds.y)
	_water_material.set_shader_parameter("reference_near_height_texture",_near_shore_texture)
	_water_material.set_shader_parameter("reference_near_bounds",_near_shore_bounds)
	_water_material.set_shader_parameter("has_reference_near_field",_near_shore_texture!=null and _near_shore_bounds.z>_near_shore_bounds.x and _near_shore_bounds.w>_near_shore_bounds.y)
	_water_material.set_shader_parameter("surface_optics_enabled",active)
	_water_material.set_shader_parameter("surface_reflection_enabled",active and _surface_optics.reflection_enabled)
	_water_material.set_shader_parameter("surface_refraction_enabled",active and _surface_optics.refraction_enabled)
	_water_material.set_shader_parameter("surface_reflection_steps",0)
	_water_material.set_shader_parameter("u_refraction_enabled",active and _surface_optics.refraction_enabled)
	_water_material.set_shader_parameter("u_caustics",bool(_reference_state.get("caustics",true)))
	var state := _reference_state.duplicate()
	state.reflection=active and _surface_optics.reflection_enabled
	_reference_renderer.render(state,_camera if is_instance_valid(_camera) else null,_simulation_time)

func get_sky_material() -> ShaderMaterial:
	return _reference_renderer.get_sky_material() if is_instance_valid(_reference_renderer) else null

func get_reflection_viewport() -> SubViewport:
	return _reference_renderer.get_reflection_viewport() if is_instance_valid(_reference_renderer) else null

func get_reflection_camera() -> Camera3D:
	return _reference_renderer.get_reflection_camera() if is_instance_valid(_reference_renderer) else null

func set_reference_surface_state(state: Dictionary) -> bool:
	# Tide/wave enable affect physics. The current formal profile is tide zero;
	# standalone preview retains its independent complete four-Gerstner controls.
	if state.has("tide") and (not state.tide is float and not state.tide is int or float(state.tide)!=0.0): return false
	if state.has("waves") and state.waves!=true: return false
	for key: String in ["strength","foamWidth"]:
		if state.has(key) and (not state[key] is float and not state[key] is int or not is_finite(float(state[key]))): return false
	if state.has("strength") and (float(state.strength)<0.0 or float(state.strength)>2.0): return false
	if state.has("foamWidth") and (float(state.foamWidth)<=0.0 or float(state.foamWidth)>4.0): return false
	if state.has("preset") and state.preset not in ["clear","sunset","storm"]: return false
	for key: String in ["foam","caustics"]:
		if state.has(key) and not state[key] is bool: return false
	for key: String in ["preset","strength","foamWidth","foam","caustics"]:
		if state.has(key): _reference_state[key]=state[key]
	_update_surface_optics()
	return true

func set_near_shore_field(texture: Texture2D,bounds: Vector4) -> void:
	if texture!=null and (not bounds.is_finite() or bounds.z<=bounds.x or bounds.w<=bounds.y or texture.get_width()<2 or texture.get_height()<2): return
	_near_shore_texture=texture; _near_shore_bounds=bounds
	_update_surface_optics()

func set_visual_style(style: int) -> void:
	_visual_style = clampi(style, 0, 1)
	if _water_material:
		_water_material.set_shader_parameter("visual_style", _visual_style)
		_water_material.set_shader_parameter("coastal_attenuation", _visual_style == 1)
	_update_surface_optics()

func set_wave_descriptors(descriptors: Array) -> bool:
	var values := WaveUniforms.components(descriptors)
	if values.is_empty(): return false
	_descriptors = descriptors.duplicate(true)
	if _water_material:
		_water_material.set_shader_parameter("wave_components", values)
		_water_material.set_shader_parameter("wave_count", descriptors.size())
	return true

func set_projection_padding(fraction: float) -> void:
	if not is_finite(fraction): return
	_projection_padding = clampf(fraction, 0.0, 0.25)
	_projection_initialized = false

func set_shore_field(texture: Texture2D, bounds: Vector4, coast_texture: Texture2D = null) -> void:
	# Both enhanced samplers fetch four endpoint texels; reject malformed fields
	# atomically rather than replacing an accepted physical attenuation texture.
	if texture!=null and (not bounds.is_finite() or bounds.z<=bounds.x or bounds.w<=bounds.y or texture.get_width()<2 or texture.get_height()<2): return
	_shore_texture = texture
	_coast_texture = coast_texture
	_shore_bounds = bounds
	if _water_material:
		_water_material.set_shader_parameter("shore_height_texture", texture)
		_water_material.set_shader_parameter("coast_distance_texture", coast_texture)
		_water_material.set_shader_parameter("has_coast_distance", coast_texture != null)
		_water_material.set_shader_parameter("shore_bounds", bounds)
		_water_material.set_shader_parameter("has_shore_field", texture != null and bounds.z > bounds.x and bounds.w > bounds.y)

func set_simulation_time(seconds: float) -> void:
	# No process callback or shader TIME: the composing runtime owns all clocks.
	if not is_finite(seconds):
		return
	_simulation_time = seconds
	if _water_material != null:
		_water_material.set_shader_parameter("simulation_time", seconds)
		_water_material.set_shader_parameter("u_time",seconds)
	if _visual_style==1: _update_surface_optics()

func update_projection() -> void:
	if _visual_style==1: _update_surface_optics()
	if not is_inside_tree() or not is_instance_valid(_camera) or not _camera.is_inside_tree() or _projected_mesh == null:
		_update_surface_optics()
		_projection_initialized = false
		return
	var camera_viewport := _camera.get_viewport()
	if not is_instance_valid(camera_viewport):
		_update_surface_optics()
		_projection_initialized = false
		return
	var viewport_size := camera_viewport.get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var camera_position := _camera.global_position
	_water_material.set_shader_parameter("camera_position", camera_position)
	var camera_projection := _camera.get_camera_projection()
	if _projection_initialized and _last_camera_transform == _camera.global_transform and _last_camera_projection == camera_projection and _last_world_transform == global_transform and _last_viewport_size == viewport_size:
		return
	_last_camera_transform = _camera.global_transform
	_last_camera_projection = camera_projection
	_last_world_transform = global_transform
	_last_viewport_size = viewport_size
	_projection_initialized = true
	for index in _vertices.size():
		var uv := _uvs[index]
		# Original JS rows are clipY -1 -> +1. Godot screen Y points downward.
		var padded := (uv - Vector2(0.5, 0.5)) * (1.0 + _projection_padding * 2.0) + Vector2(0.5, 0.5)
		var screen_position := Vector2(padded.x * viewport_size.x, (1.0 - padded.y) * viewport_size.y)
		var direction := _camera.project_ray_normal(screen_position)
		var distance := _fallback_distance
		if absf(direction.y) >= 1.0e-4:
			var intersection_distance := -camera_position.y / direction.y
			if intersection_distance > 0.0 and is_finite(intersection_distance):
				distance = minf(intersection_distance, _maximum_distance) if _has_maximum_distance else intersection_distance
		var world_position := camera_position + direction * distance
		world_position.y = 0.0
		_vertices[index] = to_local(world_position)
	_upload_grid()

func _create_grid() -> void:
	var vertex_count := (_segments + 1) * (_segments + 1)
	_vertices.resize(vertex_count)
	_normals.resize(vertex_count)
	_uvs.resize(vertex_count)
	_indices.resize(_segments * _segments * 6)
	var vertex_index := 0
	for row in _segments + 1:
		for column in _segments + 1:
			_vertices[vertex_index] = Vector3.ZERO
			_normals[vertex_index] = Vector3.UP
			_uvs[vertex_index] = Vector2(float(column) / _segments, float(row) / _segments)
			vertex_index += 1
	var index := 0
	for row in _segments:
		for column in _segments:
			var a := row * (_segments + 1) + column
			var b := a + _segments + 1
			var c := b + 1
			var d := a + 1
			_indices[index] = a
			_indices[index + 1] = b
			_indices[index + 2] = d
			_indices[index + 3] = b
			_indices[index + 4] = c
			_indices[index + 5] = d
			index += 6
	_projected_mesh = ArrayMesh.new()
	mesh = _projected_mesh
	_upload_grid()

func _upload_grid() -> void:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_INDEX] = _indices
	_projected_mesh.clear_surfaces()
	_projected_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
