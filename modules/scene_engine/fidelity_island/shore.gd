extends Node3D
## Original authored short shoreline meshes and independent UV/alpha clocks.
## Mapped mode adapts only presentation coordinates and clips against retained
## terrain authority. It neither makes a ring nor changes water/physics heights.

const Native = preload("res://modules/scene_engine/fidelity_island/native_math.gd")
const Asset = preload("res://modules/scene_engine/fidelity_island/mesh_asset.gd")
const Coordinates = preload("res://modules/scene_engine/fidelity_island/source_coordinates.gd")
const SHADER = preload("res://modules/scene_engine/fidelity_island/shore.gdshader")
const SOURCE_PATH := "res://assets/data/fidelity_island/shore-scene.json"
const TERRAIN_PATH := "res://assets/data/fidelity_island/terrain-scene.json"
const MAPPED_HEIGHT := 0.035
const LAND_THRESHOLD := 0.08

var _source: Dictionary = {}
var _materials: Array[ShaderMaterial] = []
var _source_meshes: Array[Dictionary] = []
var _states: Array[Dictionary] = []
var _mode := "mapped"
var _triangles := 0
var _land_rejected := 0
var _clipped := 0
var _time := 0.0
var _follow_requested := false
var _follow_enabled := false
var _surface_state: Dictionary = {}
var _render_sources: Array[Array] = []
var _render_triangles := 0
var _render_edge_limit := INF

static func authored_state(mesh: Dictionary, curves: Dictionary, time: float) -> Dictionary:
	var controllers: Dictionary = mesh.get("controllers",{})
	if controllers.is_empty(): return {}
	return {"translationU":Native.evaluate_float_controller(controllers.translation,curves.translation,time),"scaleU":Native.evaluate_float_controller(controllers.scale,curves.scale,time),"alpha":Native.evaluate_float_controller(controllers.alpha,curves.alpha,time)}

func configure(mapping: Dictionary, height_sampler: Callable, options: Dictionary = {}) -> bool:
	dispose()
	_mode = str(options.get("mode","mapped"))
	if _mode not in ["exact","mapped"]: return false
	_follow_requested = bool(options.get("follow_surface",_mode == "mapped"))
	if _mode == "mapped" and (not Coordinates.valid_mapping(mapping) or not height_sampler.is_valid()): return false
	_source = Asset.read_json(SOURCE_PATH)
	var terrain: Dictionary = Asset.read_json(TERRAIN_PATH)
	if _source.get("meshes",[]).size() != 8 or not Coordinates.valid_metadata(terrain): return false
	var texture: Texture2D = Asset.texture_from_entry(_source.texture)
	if texture == null: return false
	var native_origin: Vector3 = options.get("native_origin",Vector3.ZERO)
	var source_translation := Vector3(float(_source.translation[0]),float(_source.translation[1]),float(_source.translation[2]))
	for item: Dictionary in _source.meshes:
		var vertices := PackedVector3Array()
		var uv := PackedVector2Array()
		var indices := PackedInt32Array()
		var raw: Array = item.vertices
		var raw_uv: Array = item.uv
		var original_indices: Array = item.indices
		if _mode == "exact":
			for i in int(raw.size()/3):
				var original := Vector3(float(raw[i*3]),float(raw[i*3+1]),float(raw[i*3+2]))+source_translation-native_origin
				vertices.append(Coordinates.native_to_godot(original))
				uv.append(Vector2(float(raw_uv[i*2]),float(raw_uv[i*2+1])))
			for i in range(0,original_indices.size(),3):
				# Source native CCW becomes Godot engine clockwise submission.
				indices.append_array(PackedInt32Array([int(original_indices[i]),int(original_indices[i+2]),int(original_indices[i+1])]))
		else:
			var points: Array[Dictionary] = []
			for i in int(raw.size()/3):
				var original := Vector3(float(raw[i*3]),float(raw[i*3+1]),float(raw[i*3+2]))
				var world: Vector2 = Coordinates.native_to_world_xz(original,terrain,mapping)
				points.append({"position":Vector3(world.x,MAPPED_HEIGHT,world.y),"uv":Vector2(float(raw_uv[i*2]),float(raw_uv[i*2+1]))})
			for i in range(0,original_indices.size(),3):
				var triangle: Array[Dictionary] = [points[int(original_indices[i])],points[int(original_indices[i+1])],points[int(original_indices[i+2])]]
				var polygon: Array[Dictionary] = _clip_water(triangle,height_sampler)
				if polygon.size() < 3:
					_land_rejected += 1
					continue
				if polygon.size() != 3 or polygon != triangle: _clipped += 1
				for j in range(1,polygon.size()-1):
					var fragment: Array[Dictionary] = [polygon[0],polygon[j],polygon[j+1]]
					# Guard non-linear terrain crossing the interior of an otherwise
					# water-side clipped triangle. Conservatively skip such a fragment.
					if not _interior_water(fragment,height_sampler):
						_land_rejected += 1
						continue
					var start: int = vertices.size()
					for p: Dictionary in fragment:
						vertices.append(p.position)
						uv.append(p.uv)
					indices.append_array(PackedInt32Array([start,start+2,start+1]))
		if indices.is_empty(): continue
		_triangles += int(indices.size()/3)
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var material := ShaderMaterial.new()
		material.shader = SHADER
		material.set_shader_parameter("shore_texture",texture)
		material.set_shader_parameter("source_alpha_threshold",float(item.alphaProperty.threshold)/255.0)
		material.set_shader_parameter("edge_softness",0.0 if _mode == "exact" else 0.012)
		material.set_shader_parameter("follow_surface",false)
		material.render_priority = 4
		var node := MeshInstance3D.new()
		node.name = "AuthoredShortWave_%d" % int(item.sourceIndex)
		node.mesh = mesh
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		_materials.append(material)
		_source_meshes.append(item)
		_render_sources.append(arrays)
	_render_triangles = _triangles
	apply_snapshot(float(options.get("time",12.0)))
	return true

func _water(point: Vector3, sampler: Callable) -> bool:
	var result: Variant = sampler.call(point.x,point.z)
	return (result is float or result is int) and is_finite(float(result)) and float(result) <= LAND_THRESHOLD

func _crossing(a: Dictionary, b: Dictionary, sampler: Callable) -> Dictionary:
	var low := 0.0
	var high := 1.0
	var a_inside: bool = _water(a.position,sampler)
	for _i in 14:
		var middle: float = (low+high)*0.5
		var p: Vector3 = a.position.lerp(b.position,middle)
		if _water(p,sampler) == a_inside: low = middle
		else: high = middle
	# Bias toward the proven water side rather than introducing foam on land.
	var amount: float = low if a_inside else high
	return {"position":a.position.lerp(b.position,amount),"uv":a.uv.lerp(b.uv,amount)}

func _clip_water(input: Array[Dictionary], sampler: Callable) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var previous: Dictionary = input[-1]
	var previous_inside: bool = _water(previous.position,sampler)
	for current: Dictionary in input:
		var current_inside: bool = _water(current.position,sampler)
		if current_inside != previous_inside: output.append(_crossing(previous,current,sampler))
		if current_inside: output.append(current)
		previous = current
		previous_inside = current_inside
	return output

func _interior_water(triangle: Array[Dictionary], sampler: Callable) -> bool:
	var a: Vector3 = triangle[0].position
	var b: Vector3 = triangle[1].position
	var c: Vector3 = triangle[2].position
	return _water((a+b+c)/3.0,sampler) and _water((a+b)/2.0,sampler) and _water((b+c)/2.0,sampler) and _water((c+a)/2.0,sampler)

func apply_snapshot(time: float) -> void:
	if not is_finite(time) or _source.is_empty(): return
	_time = time
	_states.clear()
	for i in _materials.size():
		var state: Dictionary = authored_state(_source_meshes[i],_source.curves,time)
		_states.append(state)
		_materials[i].set_shader_parameter("controller_alpha",state.alpha)
		_materials[i].set_shader_parameter("texture_matrix",Native.texture_basis(Native.texture_transform(_source_meshes[i].texture,state)))

func _disable_surface_follow() -> bool:
	_follow_enabled = false
	_surface_state.clear()
	for material: ShaderMaterial in _materials: material.set_shader_parameter("follow_surface",false)
	return false

func _refine_render_surface(components: PackedVector4Array, count: int) -> void:
	# Original 600 vertices belong to a static source surface. Their edges can
	# span dozens of metre-scale game wave periods, so displaced endpoints do
	# not define the same surface as the water between them. Refine only mapped
	# presentation topology; linear midpoint UVs preserve the authored texture.
	if _mode != "mapped": return
	var shortest := INF
	var curvature := 0.0
	for i in count:
		var wave := components[i]
		var frequency_squared := float(wave.y)*float(wave.y)+float(wave.z)*float(wave.z)
		if frequency_squared <= 0.0 or wave.x == 0.0: continue
		shortest = minf(shortest,TAU/sqrt(frequency_squared))
		curvature += absf(float(wave.x))*frequency_squared
	if curvature == 0.0: return
	# For a triangle of diameter D, barycentric interpolation error is bounded
	# by (sum |amplitude|*|frequency|^2)*D^2/6. Keep that below one quarter of
	# the presentation offset, in addition to resolving each wave at least /8.
	var edge_limit := minf(shortest/8.0,sqrt(6.0*(MAPPED_HEIGHT/4.0)/curvature))
	if _render_edge_limit <= edge_limit: return
	_render_triangles = 0
	for i in _render_sources.size():
		var source: Array = _render_sources[i]
		var vertices: PackedVector3Array = source[Mesh.ARRAY_VERTEX].duplicate()
		var uv: PackedVector2Array = source[Mesh.ARRAY_TEX_UV].duplicate()
		var pending: PackedInt32Array = source[Mesh.ARRAY_INDEX].duplicate()
		var indices := PackedInt32Array()
		var midpoints: Dictionary = {}
		while not pending.is_empty():
			var c := pending[pending.size()-1]; pending.resize(pending.size()-1)
			var b := pending[pending.size()-1]; pending.resize(pending.size()-1)
			var a := pending[pending.size()-1]; pending.resize(pending.size()-1)
			var ab := vertices[a].distance_squared_to(vertices[b])
			var bc := vertices[b].distance_squared_to(vertices[c])
			var ca := vertices[c].distance_squared_to(vertices[a])
			if maxf(ab,maxf(bc,ca)) <= edge_limit*edge_limit:
				indices.append_array(PackedInt32Array([a,b,c]))
				continue
			# Rotate the longest edge into (a,b), retaining original submission winding.
			if bc >= ab and bc >= ca:
				var saved := a; a = b; b = c; c = saved
			elif ca >= ab and ca >= bc:
				var saved := c; c = b; b = a; a = saved
			var key := Vector2i(mini(a,b),maxi(a,b))
			var middle: int = int(midpoints.get(key,-1))
			if middle < 0:
				middle = vertices.size()
				vertices.append((vertices[a]+vertices[b])*0.5)
				uv.append((uv[a]+uv[b])*0.5)
				midpoints[key] = middle
			pending.append_array(PackedInt32Array([a,middle,c,middle,b,c]))
		var arrays: Array = source.duplicate()
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		get_child(i).mesh = mesh
		_render_triangles += indices.size()/3
	_render_edge_limit = edge_limit

func sync_surface_state(ocean_material: ShaderMaterial) -> bool:
	# Read-only observation of the retained water's current owner uniforms.
	# Source UV/alpha time and water time are intentionally separate: callers
	# can seek/offset source surf playback without altering physics/water clocks.
	if not _follow_requested:
		_disable_surface_follow()
		return true
	if ocean_material == null or ocean_material.shader == null: return _disable_surface_follow()
	var components: Variant = ocean_material.get_shader_parameter("wave_components")
	var count_value: Variant = ocean_material.get_shader_parameter("wave_count")
	var time_value: Variant = ocean_material.get_shader_parameter("simulation_time")
	if not (components is PackedVector4Array or components is Array): return _disable_surface_follow()
	if not (count_value is float or count_value is int) or not is_finite(float(count_value)): return _disable_surface_follow()
	var count: int = int(count_value)
	if float(count) != float(count_value) or count < 0 or count > 8 or components.size() < count: return _disable_surface_follow()
	if not (time_value is float or time_value is int) or not is_finite(float(time_value)): return _disable_surface_follow()
	var copied_components := PackedVector4Array()
	for i in 8:
		var component := Vector4.ZERO
		if i < components.size():
			if not components[i] is Vector4 or not components[i].is_finite(): return _disable_surface_follow()
			component = components[i]
		copied_components.append(component)
	var has_field: bool = bool(ocean_material.get_shader_parameter("has_shore_field"))
	var attenuation: bool = bool(ocean_material.get_shader_parameter("coastal_attenuation"))
	var field: Variant = ocean_material.get_shader_parameter("shore_height_texture")
	var bounds_value: Variant = ocean_material.get_shader_parameter("shore_bounds")
	var bounds := Vector4.ZERO
	if bounds_value is Vector4: bounds = bounds_value
	if has_field and (not field is Texture2D or not bounds.is_finite() or bounds.z <= bounds.x or bounds.w <= bounds.y): return _disable_surface_follow()
	var tide_value: Variant = ocean_material.get_shader_parameter("u_tide")
	var tide := 0.0
	if tide_value is float or tide_value is int:
		if not is_finite(float(tide_value)): return _disable_surface_follow()
		tide = float(tide_value)
	_surface_state = {"wave_components":copied_components,"wave_count":count,"simulation_time":float(time_value),"has_shore_field":has_field,"coastal_attenuation":attenuation,"shore_bounds":bounds,"shore_height_texture_present":field is Texture2D,"surface_tide":tide}
	_refine_render_surface(copied_components,count)
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter("wave_components",copied_components)
		material.set_shader_parameter("wave_count",count)
		material.set_shader_parameter("simulation_time",float(time_value))
		material.set_shader_parameter("has_shore_field",has_field)
		material.set_shader_parameter("coastal_attenuation",attenuation)
		material.set_shader_parameter("shore_bounds",bounds)
		material.set_shader_parameter("shore_height_texture",field if field is Texture2D else null)
		material.set_shader_parameter("surface_tide",tide)
		material.set_shader_parameter("surface_height_offset",MAPPED_HEIGHT)
		material.set_shader_parameter("follow_surface",true)
	_follow_enabled = true
	return true

func diagnostics() -> Dictionary:
	return {"mode":_mode,"meshCount":_materials.size(),"triangles":_triangles,"renderedTriangles":_render_triangles,"renderEdgeLimit":_render_edge_limit if is_finite(_render_edge_limit) else 0.0,"landRejectedTriangles":_land_rejected,"clippedTriangles":_clipped,"waterPlaneY":MAPPED_HEIGHT if _mode == "mapped" else float(_source.get("translation",[0.0,0.0,0.0])[2]),"time":_time,"states":_states.duplicate(true),"followSurface":_follow_enabled,"surfaceState":_surface_state.duplicate(true),"originalMeshCount":8,"scope":"Original short meshes/UV/alpha; mapped coordinate/.035 elevation/land clipping/extra soft-edge and cached render-only wave refinement follow current water. Exact observer keeps original static topology. Complete original FFP lighting remains unknown."}

func dispose() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.free()
	_materials.clear()
	_source_meshes.clear()
	_render_sources.clear()
	_states.clear()
	_source.clear()
	_triangles = 0
	_land_rejected = 0
	_clipped = 0
	_follow_requested = false
	_follow_enabled = false
	_surface_state.clear()
	_render_triangles = 0
	_render_edge_limit = INF
