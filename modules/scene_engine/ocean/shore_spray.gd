extends MultiMeshInstance3D
## Small native billboard droplets at injected coastline samples. Visual only.
## Runtime supplies simulation time; pause freezes spray and ocean together.

const SPRAY_SHADER = preload("res://modules/scene_engine/ocean/shore_spray.gdshader")
const Descriptor = preload("res://modules/contracts/wave_descriptor.gd")
const WaveUniforms = preload("res://modules/scene_engine/ocean/wave_uniforms.gd")
var _material: ShaderMaterial

func configure(height_sampler: Callable, bounds: Rect2, maximum: int = 160) -> bool:
	if not height_sampler.is_valid() or bounds.size.x <= 0 or bounds.size.y <= 0:
		return false
	var candidates: Array[Vector3] = []
	# Even world-space coverage keeps this independent of UI, ports or ship rules.
	var spacing := 5.0
	var columns := int(ceil(bounds.size.x / spacing))
	var rows := int(ceil(bounds.size.y / spacing))
	for row in rows:
		for column in columns:
			var x := bounds.position.x + column * spacing
			var z := bounds.position.y + row * spacing
			var height: float = height_sampler.call(x, z)
			if height >= -1.4 and height <= -0.2:
				candidates.append(Vector3(x, 0.1, z))
	if candidates.is_empty():
		return false
	var count := mini(clampi(maximum, 1, 512), candidates.size())
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.7, 0.7)
	instances.mesh = quad
	instances.instance_count = count
	for index in count:
		var point: Vector3 = candidates[int(float(index) * candidates.size() / count)]
		instances.set_instance_transform(index, Transform3D(Basis.IDENTITY, point))
		instances.set_instance_custom_data(index, Color(fmod(index * 0.61803398875, 1.0), fmod(index * 0.381966, 1.0), 0, 1))
	multimesh = instances
	_material = ShaderMaterial.new()
	_material.shader = SPRAY_SHADER
	set_wave_descriptors(Descriptor.original_descriptors())
	_material.render_priority = 2
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 5.0
	return true

func set_wave_descriptors(descriptors: Array) -> bool:
	var values := WaveUniforms.components(descriptors)
	if not _material or values.is_empty(): return false
	_material.set_shader_parameter("wave_components", values)
	_material.set_shader_parameter("wave_count", descriptors.size())
	return true

func set_simulation_time(seconds: float) -> void:
	if _material and is_finite(seconds):
		_material.set_shader_parameter("simulation_time", seconds)

func set_shore_field(texture: Texture2D, bounds: Vector4) -> void:
	if not _material: return
	_material.set_shader_parameter("shore_height_texture", texture)
	_material.set_shader_parameter("shore_bounds", bounds)
	_material.set_shader_parameter("has_shore_field", texture != null and bounds.z > bounds.x and bounds.w > bounds.y)
	_material.set_shader_parameter("coastal_attenuation", true)
