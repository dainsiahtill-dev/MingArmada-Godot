extends Node3D
## Completed source demo NR water presentation. This observer renderer has no
## physics/sampling dependency and cannot change the formal five-wave ocean.

const Asset = preload("res://modules/scene_engine/fidelity_island/mesh_asset.gd")
const Native = preload("res://modules/scene_engine/fidelity_island/native_math.gd")
const WaterShader = preload("res://modules/scene_engine/fidelity_island/source_water.gdshader")
const SOURCE_PATH := "res://assets/data/fidelity_island/water-scene.json"
const MANIFEST_PATH := "res://assets/data/fidelity_island/water-manifest.json"
var _material: ShaderMaterial
var _camera: Camera3D
var _native_origin := Vector3.ZERO
var _time := 12.0
var _mip_levels := 0
var _mesh_count := 0
var _triangles := 0
var _water_plane := 0.0
var _root_native := Vector3.ZERO
var _node_translation := Vector3.ZERO
var _fog_enabled := true
var _terrain_material: ShaderMaterial
const BACKGROUND_UNIFORMS := ["source_water_texture", "source_time", "source_scale", "source_water_ambient", "source_fog_color", "source_fog_values", "source_fog_enabled", "source_water_uv_row_x", "source_water_uv_row_z", "source_water_uv_offset", "source_water_plane_y", "source_water_tile_span"]

static func ocean_coordinates(uv: Vector2, time: float, scale: float = 1.0) -> Dictionary:
	var period := 45.0 if time >= 0.0 else -45.0
	var q := Native.f32(Native.f32(1.0 / period) * Native.f32(time))
	var phase := Native.f32(Native.f32(period * Native.f32(q-floor(q))) * Native.f32(0.0222222))
	var u := Native.f32(Native.f32(float(uv.x)*scale)*45.0)
	var v := Native.f32(Native.f32(float(uv.y)*scale)*45.0)
	return {"bump":[u,v], "water0":[Native.f32(u+phase),v], "water1":[Native.f32(1.0-u),Native.f32(Native.f32(1.0-v)-phase)]}

static func nr_color(first: Vector3, second: Vector3, ambient: Vector3) -> Vector4:
	var result := Vector4(0.0,0.0,0.0,Native.f32(0.4))
	for i in 3:
		var a := clampf(Native.f32(float(ambient[i])*1.5),0.0,1.0)
		result[i] = Native.f32(Native.f32(a*Native.f32(float(first[i])*float(second[i]))) + Native.f32(Native.f32(1.0-a)*a))
	return result

static func composite_display_color(nr: Vector4, fog_color: Vector3, fog: float) -> Vector3:
	return (Vector3(nr.x,nr.y,nr.z).lerp(fog_color,clampf(fog,0.0,1.0)))*0.4 + fog_color*0.6

static func terrain_composite(sand: Vector3, alpha: float, additive: Vector3, lighting: Vector3, fog_color: Vector3, fog: float, background: Vector3) -> Vector3:
	var under := fog_color*fog + sand*lighting*(1.0-fog)
	return under*clampf(alpha,0.0,1.0) + background*(1.0-clampf(alpha,0.0,1.0)) + additive*lighting*(1.0-fog)

func configure(camera: Camera3D, native_origin: Vector3, options: Dictionary = {}) -> bool:
	dispose()
	if not is_instance_valid(camera) or not native_origin.is_finite(): return false
	var source := Asset.read_json(str(options.get("source_path",SOURCE_PATH)))
	if source.get("positions",[]).size() != 12 or source.get("uv",[]).size() != 8 or source.get("indices",[]).size() != 6: return false
	var entry: Dictionary = options.get("texture_entry",{})
	if entry.is_empty(): entry = Asset.read_json(MANIFEST_PATH).get("texture",{})
	var texture := Asset.texture_from_entry(entry)
	if texture == null: return false
	var far := float(options.get("far",30000.0))
	if not is_finite(far) or far <= 0.0: return false
	_camera=camera; _native_origin=native_origin; _fog_enabled=bool(options.get("fog_enabled",true))
	_mip_levels=int(entry.get("mipLevels",1))
	var node: Dictionary = source.get("node",{})
	var translation: Dictionary = node.get("translation",{})
	_node_translation=Vector3(float(translation.get("x",0.0)),float(translation.get("y",0.0)),float(translation.get("z",0.0)))
	_water_plane=_node_translation.z-native_origin.z
	_material=ShaderMaterial.new(); _material.shader=WaterShader
	_material.render_priority=-100
	_material.set_shader_parameter("source_water_texture",texture)
	_material.set_shader_parameter("source_fog_values",Vector3(far,0.4,0.6))
	_material.set_shader_parameter("source_fog_enabled",_fog_enabled)
	_material.set_shader_parameter("source_water_plane_y",_water_plane)
	var vertices := PackedVector3Array(); var normals := PackedVector3Array(); var uv := PackedVector2Array()
	for i in 4:
		vertices.append(Asset.native_to_godot(Vector3(float(source.positions[i*3]),float(source.positions[i*3+1]),float(source.positions[i*3+2]))))
		normals.append(Vector3.UP)
		uv.append(Vector2(float(source.uv[i*2]),float(source.uv[i*2+1])))
	var indices := PackedInt32Array(source.indices)
	for i in range(0,indices.size(),3):
		var previous:=indices[i+1]; indices[i+1]=indices[i+2]; indices[i+2]=previous
	var arrays: Array=[]; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_NORMAL]=normals; arrays[Mesh.ARRAY_TEX_UV]=uv; arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	for x in range(-1,2):
		for y in range(-1,2):
			var tile:=MeshInstance3D.new(); tile.name="SourceWater_%s_%s" % [x,y]; tile.mesh=mesh
			tile.material_override=_material; tile.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			tile.set_meta("source_tile",Vector2i(x,y)); add_child(tile)
			_mesh_count+=1; _triangles+=2
	update_source_target(Vector2.ZERO)
	return true

func update_source_target(godot_target: Vector2) -> bool:
	if _material == null or not godot_target.is_finite(): return false
	var target:=Vector2(_native_origin.x+godot_target.x,_native_origin.y-godot_target.y)
	_root_native=Vector3(Native.f32(float(target.x)-fmod(float(target.x),100000.0)),Native.f32(float(target.y)-fmod(float(target.y),100000.0)),0.0)
	for child: Node in get_children():
		var tile: Vector2i=child.get_meta("source_tile")
		var translation:=_root_native+Vector3(tile.x*100000.0,tile.y*100000.0,0.0)+_node_translation-_native_origin
		child.position=Asset.native_to_godot(translation)
	var offset := Vector2((_native_origin.x-_root_native.x-_node_translation.x+50000.0)*0.00045,(50000.0-_native_origin.y+_root_native.y+_node_translation.y)*0.00045)
	_material.set_shader_parameter("source_water_uv_row_x",Vector2(0.00045,0.0))
	_material.set_shader_parameter("source_water_uv_row_z",Vector2(0.0,0.00045))
	_material.set_shader_parameter("source_water_uv_offset",offset)
	_sync_background()
	return true

func bind_terrain(material: ShaderMaterial, bounds: Rect2) -> bool:
	if _material == null or material == null or material.shader == null or not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size.x <= 0.0 or bounds.size.y <= 0.0: return false
	if _terrain_material != null: _terrain_material.set_shader_parameter("source_observer_composition",false)
	_terrain_material=material
	_terrain_material.set_shader_parameter("source_observer_composition",true)
	_material.set_shader_parameter("source_terrain_composition_enabled",true)
	_material.set_shader_parameter("source_terrain_min",bounds.position)
	_material.set_shader_parameter("source_terrain_max",bounds.end)
	_sync_background()
	return true

func _sync_background() -> void:
	if _material == null or _terrain_material == null: return
	for key: String in BACKGROUND_UNIFORMS:
		_terrain_material.set_shader_parameter(key,_material.get_shader_parameter(key))

static func _light_vector(value: Variant) -> Vector3:
	if value is Vector3: return value
	if value is Array and value.size()==3 and (value[0] is int or value[0] is float) and (value[1] is int or value[1] is float) and (value[2] is int or value[2] is float):
		return Vector3(float(value[0]),float(value[1]),float(value[2]))
	return Vector3(NAN,NAN,NAN)

func apply_snapshot(time: float, lighting: Dictionary) -> bool:
	if _material == null or not is_finite(time): return false
	var ambient:=_light_vector(lighting.get("ambient")); var fog:=_light_vector(lighting.get("fogColor"))
	if not ambient.is_finite() or not fog.is_finite(): return false
	_time=time; _material.set_shader_parameter("source_time",time)
	_material.set_shader_parameter("source_water_ambient",ambient); _material.set_shader_parameter("source_fog_color",fog)
	_sync_background()
	return true

func diagnostics() -> Dictionary:
	return {"mode":"completed-source-nr", "meshCount":_mesh_count, "triangles":_triangles, "waterPlaneY":_water_plane, "textureMipLevels":_mip_levels, "time":_time, "nrAlpha":0.4, "displayComposition":true, "terrainComposition":_terrain_material != null, "fogEnabled":_fog_enabled, "sourceRoot":_root_native, "uvScale":45.0, "physicsMutation":false, "scope":"Completed-demo NR observation branch with explicit Godot color/queue adapter; original active game graphics-quality branch was not captured."}

func dispose() -> void:
	if _terrain_material != null: _terrain_material.set_shader_parameter("source_observer_composition",false)
	_terrain_material=null
	for child: Node in get_children(): child.free()
	_material=null; _camera=null; _mesh_count=0; _triangles=0; _mip_levels=0

func _exit_tree() -> void: dispose()
