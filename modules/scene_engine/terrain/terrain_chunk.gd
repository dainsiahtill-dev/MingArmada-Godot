extends MeshInstance3D
## A bounded chunk built from an injected authority. Collision uses this same mesh.

const LAYER_HEIGHTS := [-50.0, -35.0, -5.0, 2.0, 10.0, 60.0, 100.0, 140.0]
const LAYER_COLORS := ["002b4d", "002b4d", "8b7d6b", "e6dabf", "597d3e", "284024", "5a5552", "888888"]
const SurfaceShader = preload("res://modules/scene_engine/terrain/terrain_surface.gdshader")
var _body: StaticBody3D
var _sample: Callable
var _linear_colors: Array[Color] = []
var _surface_state: Dictionary = {}
var _caustics_allowed := true
var _mesh_heights := PackedFloat32Array()
var _mesh_size := 0.0
var _mesh_resolution := 0

func configure(sampler: Callable, coordinate: Vector2i, size: float = 250.0, resolution: int = 32, collision: bool = true, options: Dictionary = {}) -> bool:
	if not sampler.is_valid() or not is_finite(size) or size <= 0.0:
		return false
	_sample = sampler
	position = Vector3(coordinate.x * size, 0.0, coordinate.y * size)
	resolution = clampi(resolution, 4, 128)
	_linear_colors.clear()
	for color: String in LAYER_COLORS:
		_linear_colors.append(Color.html(color).srgb_to_linear())
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var weights := PackedVector2Array()
	var indices := PackedInt32Array()
	var step := size / resolution
	for row in resolution + 1:
		for column in resolution + 1:
			var x := column * step - size * 0.5
			var z := row * step - size * 0.5
			var wx := x + position.x
			var wz := z + position.z
			var height := float(_sample.call(wx, wz))
			if not is_finite(height):
				return false
			vertices.append(Vector3(x, height, z))
			var dx := float(_sample.call(wx + 0.5, wz)) - float(_sample.call(wx - 0.5, wz))
			var dz := float(_sample.call(wx, wz + 0.5)) - float(_sample.call(wx, wz - 0.5))
			var normal := Vector3(-dx, 1.0, -dz).normalized()
			normals.append(normal)
			colors.append(get_biome_color(height))
			var layers := get_surface_weights(height, normal)
			weights.append(Vector2(layers.x, layers.y))
	for row in resolution:
		for column in resolution:
			var a := row * (resolution + 1) + column
			var b := a + resolution + 1
			# Godot fronts are clockwise, opposite the original Three geometry.
			indices.append_array(PackedInt32Array([a, a + 1, b, b, a + 1, b + 1]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = weights
	arrays[Mesh.ARRAY_INDEX] = indices
	var terrain_mesh := ArrayMesh.new()
	terrain_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = terrain_mesh
	_mesh_size = size
	_mesh_resolution = resolution
	_mesh_heights.resize(vertices.size())
	for i: int in vertices.size():
		_mesh_heights[i] = vertices[i].y
	_surface_state.clear()
	_caustics_allowed = bool(options.get("caustics",true))
	if bool(options.get("detailed",false)):
		var surface := ShaderMaterial.new()
		surface.shader = SurfaceShader
		surface.set_shader_parameter("simulation_time",0.0)
		surface.set_shader_parameter("u_time",0.0)
		surface.set_shader_parameter("u_tide",0.0)
		surface.set_shader_parameter("u_sun",Vector3(-.5,.8,.3).normalized())
		surface.set_shader_parameter("u_sun_color",Vector3(1,.95,.82))
		surface.set_shader_parameter("u_clip",true)
		surface.set_shader_parameter("u_caustics",_caustics_allowed)
		surface.set_shader_parameter("wave_components",PackedVector4Array())
		surface.set_shader_parameter("wave_count",0)
		surface.set_shader_parameter("shore_bounds",Vector4.ZERO)
		surface.set_shader_parameter("has_shore_field",false)
		surface.set_shader_parameter("coastal_attenuation",false)
		surface.set_shader_parameter("sand_color",Color.html("ddc993").srgb_to_linear())
		surface.set_shader_parameter("grass_color",Color.html("668447").srgb_to_linear())
		surface.set_shader_parameter("rock_color",Color.html("8a8271").srgb_to_linear())
		surface.set_shader_parameter("caustics_enabled",_caustics_allowed)
		material_override = surface
	else:
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.vertex_color_is_srgb = false
		material.roughness = 0.9
		material.metallic = 0.1
		material_override = material
	if is_instance_valid(_body):
		_body.free()
	_body = null
	if collision:
		_body = StaticBody3D.new()
		var shape := CollisionShape3D.new()
		shape.shape = mesh.create_trimesh_shape()
		_body.add_child(shape)
		add_child(_body)
	return true

func get_surface_weights(height: float, normal: Vector3) -> Vector3:
	# x sand, y grass, z rock. UV carries x/y; the opaque shader recovers z.
	# Land geometry and its collision remain exclusively the injected sampler.
	var slope := 1.0 - clampf(normal.normalized().y,0.0,1.0)
	var rock := smoothstep(.22,.64,slope) * smoothstep(.2,3.0,height)
	rock = maxf(rock,smoothstep(80.0,140.0,height)*.60)
	var grass := smoothstep(3.0,12.0,height) * (1.0-rock)
	return Vector3(1.0-grass-rock,grass,rock)

func sync_surface_state(ocean_material: ShaderMaterial, state: Dictionary = {}) -> bool:
	var surface := material_override as ShaderMaterial
	if surface == null or ocean_material == null:
		return false
	var seconds = ocean_material.get_shader_parameter("simulation_time")
	if seconds == null:
		seconds = ocean_material.get_shader_parameter("u_time")
	if state.has("time"):
		seconds = state.time
	var components = ocean_material.get_shader_parameter("wave_components")
	var count = ocean_material.get_shader_parameter("wave_count")
	var source_waves = ocean_material.get_shader_parameter("u_waves")
	var source_speeds = ocean_material.get_shader_parameter("u_speeds")
	if components == null and count == null:
		if source_speeds == null:
			source_speeds = Vector4(1.4,1.8,2.2,2.8)
		if not (source_waves is PackedVector4Array or source_waves is Array) or source_waves.size() != 4 or not source_speeds is Vector4 or not source_speeds.is_finite():
			return false
		var strength = ocean_material.get_shader_parameter("u_strength")
		if strength == null:
			strength = 1.0
		if not _finite_number(strength):
			return false
		components = PackedVector4Array()
		for i: int in 4:
			if not source_waves[i] is Vector4 or not source_waves[i].is_finite():
				return false
			var wave: Vector4 = source_waves[i]
			components.append(Vector4(wave.z*float(strength),wave.w*wave.x,wave.w*wave.y,-source_speeds[i]))
		count = 4
	var bounds = ocean_material.get_shader_parameter("shore_bounds")
	var has_shore: bool = ocean_material.get_shader_parameter("has_shore_field") == true
	if bounds == null and not has_shore:
		bounds = Vector4.ZERO
	if not _finite_number(seconds):
		return false
	if not (count is int) or count < 0 or count > 8 or not (components is PackedVector4Array or components is Array) or components.size() < count:
		return false
	for i in count:
		if not components[i] is Vector4 or not components[i].is_finite():
			return false
	if not bounds is Vector4 or not bounds.is_finite() or (has_shore and (bounds.z <= bounds.x or bounds.w <= bounds.y)):
		return false
	var tide = state.get("tide",ocean_material.get_shader_parameter("u_tide"))
	if tide == null:
		tide = 0.0
	if not _finite_number(tide):
		return false
	var sun = ocean_material.get_shader_parameter("u_sun")
	var sun_color = ocean_material.get_shader_parameter("u_sun_color")
	if sun == null:
		sun = Vector3(-.5,.8,.3).normalized()
	if sun_color == null:
		sun_color = Vector3(1,.95,.82)
	if state.has("preset"):
		if not state.preset is String or not state.preset in ["clear","sunset","storm"]:
			return false
		sun = Vector3(-.8,.18,-.45).normalized() if state.preset == "sunset" else Vector3(-.5,.8,.3).normalized()
		sun_color = Vector3(1,.65,.35) if state.preset == "sunset" else Vector3(1,.95,.82)
	sun = state.get("sun",sun)
	sun_color = state.get("sunColor",sun_color)
	if not sun is Vector3 or not sun.is_finite() or sun.length_squared() < .000001 or not sun_color is Vector3 or not sun_color.is_finite():
		return false
	var caustics = state.get("caustics",ocean_material.get_shader_parameter("u_caustics"))
	if caustics == null:
		caustics = true
	if not caustics is bool:
		return false
	caustics = caustics and _caustics_allowed
	# All validation precedes mutation. Copy values; never retain the ocean node
	# or its material. Shared Texture2D resources are read-only shader inputs.
	var next_state := {
		"simulation_time":float(seconds),"wave_components":components,"wave_count":count,
		"shore_bounds":bounds,"has_shore_field":has_shore,
		"shore_height_texture":ocean_material.get_shader_parameter("shore_height_texture"),
		"coastal_attenuation":ocean_material.get_shader_parameter("coastal_attenuation") == true,
		"u_time":float(seconds),"u_tide":float(tide),"u_sun":sun,"u_sun_color":sun_color,
		"u_caustics":caustics,"caustics_enabled":caustics,
	}
	for key: String in next_state:
		if _surface_state.has(key) and _surface_state[key] == next_state[key]:
			continue
		var value = components.duplicate() if key == "wave_components" else next_state[key]
		surface.set_shader_parameter(key,value)
		_surface_state[key] = value
	return true

func _finite_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func sample_mesh_height(world_x: float, world_z: float) -> float:
	if _mesh_resolution < 1 or _mesh_size <= 0.0 or mesh == null or not is_finite(world_x) or not is_finite(world_z):
		return NAN
	# Runtime chunks are horizontal and translated. This query reads actual
	# Float32 vertices without changing the injected terrain or its collider.
	var origin: Vector3 = global_position if is_inside_tree() else position
	var u: float = (world_x-origin.x)/_mesh_size+.5
	var v: float = (world_z-origin.z)/_mesh_size+.5
	if u < 0 or u > 1 or v < 0 or v > 1:
		return NAN
	var px: float = u*_mesh_resolution
	var py: float = v*_mesh_resolution
	var ix: int = mini(int(floor(px)),_mesh_resolution-1)
	var iy: int = mini(int(floor(py)),_mesh_resolution-1)
	var ax: float = px-ix
	var ay: float = py-iy
	var a: int = iy*(_mesh_resolution+1)+ix
	var c: int = a+_mesh_resolution+1
	var ah: float = _mesh_heights[a]
	var bh: float = _mesh_heights[a+1]
	var ch: float = _mesh_heights[c]
	var dh: float = _mesh_heights[c+1]
	var height: float = ah+(bh-ah)*ax+(ch-ah)*ay if ax+ay <= 1 else dh+(ch-dh)*(1-ax)+(bh-dh)*(1-ay)
	return height+origin.y

func get_biome_color(height: float) -> Color:
	if _linear_colors.is_empty():
		for color: String in LAYER_COLORS:
			_linear_colors.append(Color.html(color).srgb_to_linear())
	if height <= LAYER_HEIGHTS[0]:
		return _linear_colors[0]
	for index in LAYER_HEIGHTS.size() - 1:
		if height <= LAYER_HEIGHTS[index + 1]:
			var t := smoothstep(LAYER_HEIGHTS[index], LAYER_HEIGHTS[index + 1], height)
			return _linear_colors[index].lerp(_linear_colors[index + 1], t)
	return _linear_colors.back()

func get_collision_body() -> StaticBody3D:
	return _body

func dispose() -> void:
	if is_instance_valid(_body):
		_body.free()
	_body = null
	mesh = null
	material_override = null
	_surface_state.clear()
	_sample = Callable()
	_mesh_heights.clear()
	_mesh_size = 0.0
	_mesh_resolution = 0
