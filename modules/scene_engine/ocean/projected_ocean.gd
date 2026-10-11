extends MeshInstance3D

const WATER_SHADER := preload("res://modules/scene_engine/ocean/original_water.gdshader")
const Descriptor = preload("res://modules/contracts/wave_descriptor.gd")
const WaveUniforms = preload("res://modules/scene_engine/ocean/wave_uniforms.gd")
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

func configure(camera: Camera3D, normal_texture: Texture2D, resolution: int = 80, max_distance: float = 3000.0) -> void:
	_camera = camera
	_segments = maxi(MINIMUM_RESOLUTION, resolution)
	_has_maximum_distance = is_finite(max_distance) and max_distance > 0.0
	_maximum_distance = max_distance if _has_maximum_distance else INF
	_fallback_distance = max_distance if _has_maximum_distance else UNBOUNDED_FALLBACK_DISTANCE
	if _water_material == null:
		_water_material = ShaderMaterial.new()
		_water_material.shader = WATER_SHADER
		_water_material.render_priority = 1
	_water_material.set_shader_parameter("normal_texture", normal_texture)
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
	update_projection()

func set_visual_style(style: int) -> void:
	_visual_style = clampi(style, 0, 1)
	if _water_material:
		_water_material.set_shader_parameter("visual_style", _visual_style)
		_water_material.set_shader_parameter("coastal_attenuation", _visual_style == 1)

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

func update_projection() -> void:
	if not is_instance_valid(_camera) or _projected_mesh == null:
		return
	var viewport_size := _camera.get_viewport().get_visible_rect().size
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
