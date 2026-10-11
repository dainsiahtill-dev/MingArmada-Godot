extends Node3D
## Godot port of demo/renderer.mjs water/sky passes. Main opaque color/depth are
## sampled before transparent water. Real planar color uses one shared-world camera.

const Model = preload("res://modules/scene_engine/reference_island_water/ocean_model.gd")
const WaterShader = preload("res://modules/scene_engine/reference_island_water/reference_water.gdshader")
const SkyShader = preload("res://modules/scene_engine/reference_island_water/reference_sky.gdshader")
const WATER_LAYER := 1<<19
var _water: MeshInstance3D
var _material: ShaderMaterial
var _sky_material: ShaderMaterial
var _reflection: SubViewport
var _mirror: Camera3D
var _field: Dictionary
var _state := {"preset":"clear","strength":1.0,"tide":0.0,"foamWidth":1.5,"waves":true,"reflection":true,"foam":true,"caustics":true}
var _accepted_time := 0.0
var _camera: Camera3D
var _reflection_enabled := false
var _disposed := false
var _last_error := ""
var _owns_water := true

static func _valid_state(state: Dictionary) -> bool:
	for key: String in ["tide","strength","foamWidth"]:
		if state.has(key) and not is_finite(float(state[key])): return false
	return true

func configure(field: Dictionary,camera: Camera3D,state: Dictionary={}) -> bool:
	if _disposed: return false
	var extent := float(field.get("extent",0.0))
	var resolution := int(field.get("oceanResolution",192))
	if not is_finite(extent) or extent<=0.0 or int(field.get("terrainResolution",160))<1: _last_error="invalid-field"; return false
	if resolution<1 or resolution>254: _last_error="invalid-ocean-resolution"; return false
	if not _valid_state(state): _last_error="invalid-surface-state"; return false
	var texture: Texture2D = field.get("heightTexture")
	if texture==null:
		var path := "res://modules/scene_engine/reference_island_water/reference_island_model.gd"
		if not FileAccess.file_exists(path): _last_error="missing-island-height-model"; return false
		var island_model: GDScript=load(path)
		texture=island_model.height_texture(field,int(field.get("terrainResolution",160)))
	if texture==null: _last_error="invalid-height-texture"; return false
	_field=field.duplicate()
	_camera=camera
	if _material==null:
		_material=ShaderMaterial.new(); _material.shader=WaterShader
		_sky_material=ShaderMaterial.new(); _sky_material.shader=SkyShader
		_water=MeshInstance3D.new(); _water.name="ReferenceDemoOcean"; _water.layers=WATER_LAYER
		_water.mesh=Model.ocean_mesh(int(field.get("oceanResolution",192)))
		if _water.mesh==null: _last_error="invalid-ocean-resolution"; _water.free(); _water=null; return false
		_water.material_override=_material
		_water.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_water.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
		_water.extra_cull_margin=2.0
		add_child(_water)
		_reflection=SubViewport.new(); _reflection.name="ReferencePlanarReflection"
		_reflection.disable_3d=false; _reflection.transparent_bg=false
		_reflection.render_target_update_mode=SubViewport.UPDATE_DISABLED
		_reflection.size=Vector2i(768,432)
		add_child(_reflection)
		_mirror=Camera3D.new(); _mirror.name="ReferenceMirrorCamera"; _reflection.add_child(_mirror)
		_mirror.current=true
		_material.set_shader_parameter("u_reflection",_reflection.get_texture())
		_material.set_shader_parameter("u_waves",Model.wave_uniforms())
	_material.set_shader_parameter("u_height",texture)
	_material.set_shader_parameter("u_extent",float(field.extent))
	_material.set_shader_parameter("u_terrain_resolution",float(field.get("terrainResolution",160)))
	render(state,camera,0.0)
	return true

func attach_surface(surface: MeshInstance3D,material: ShaderMaterial,camera: Camera3D) -> bool:
	# Integration reuses the caller's projected mesh/material, with exactly the
	# same mirror/sky contract. Standalone configure() defaults remain unchanged.
	if _disposed or not is_instance_valid(surface) or material==null or _material!=null: return false
	_owns_water=false; _water=surface; _material=material; _camera=camera
	_sky_material=ShaderMaterial.new(); _sky_material.shader=SkyShader
	_reflection=SubViewport.new(); _reflection.name="ReferencePlanarReflection"
	_reflection.disable_3d=false; _reflection.transparent_bg=false
	_reflection.render_target_update_mode=SubViewport.UPDATE_DISABLED; _reflection.size=Vector2i(768,432)
	add_child(_reflection)
	_mirror=Camera3D.new(); _mirror.name="ReferenceMirrorCamera"; _reflection.add_child(_mirror); _mirror.current=true
	_material.set_shader_parameter("u_reflection",_reflection.get_texture())
	return true

func render(state: Dictionary,camera: Camera3D,accepted_seconds: float) -> void:
	if _disposed or _material==null: return
	if not is_finite(accepted_seconds): _last_error="invalid-accepted-time"; return
	if not _valid_state(state): _last_error="invalid-surface-state"; return
	_state.merge(state,true)
	_accepted_time=accepted_seconds
	_camera=camera
	var tide := float(_state.get("tide",0.0))
	var strength := clampf(float(_state.get("strength",1.0)),0.0,2.0) if _state.get("waves",true) else 0.0
	var sunset: bool=_state.get("preset","clear")=="sunset"
	var sun := Vector3(-.8,.18,-.45).normalized() if sunset else Vector3(-.5,.8,.3).normalized()
	var sun_color := Vector3(1,.65,.35) if sunset else Vector3(1,.95,.82)
	for material: ShaderMaterial in [_material,_sky_material]:
		material.set_shader_parameter("u_time",accepted_seconds)
		material.set_shader_parameter("u_tide",tide)
		material.set_shader_parameter("u_sun",sun)
		material.set_shader_parameter("u_sun_color",sun_color)
	_material.set_shader_parameter("u_strength",strength)
	_material.set_shader_parameter("u_foam_width",float(_state.get("foamWidth",1.5)))
	_material.set_shader_parameter("u_foam",bool(_state.get("foam",true)))
	var camera_valid := is_instance_valid(camera) and camera.is_inside_tree() and is_instance_valid(camera.get_viewport()) and is_inside_tree()
	_reflection_enabled=camera_valid and bool(_state.get("reflection",true))
	if camera_valid:
		var eye := camera.get_camera_transform().origin
		_material.set_shader_parameter("u_eye",eye)
		_sky_material.set_shader_parameter("u_eye",eye)
		_sync_mirror(camera,tide)
	_material.set_shader_parameter("u_use_reflection",_reflection_enabled)
	_reflection.render_target_update_mode=SubViewport.UPDATE_ALWAYS if _reflection_enabled else SubViewport.UPDATE_DISABLED

func _sync_mirror(camera: Camera3D,tide: float) -> void:
	var visible_size := camera.get_viewport().get_visible_rect().size
	var width := maxi(2,mini(768,int(visible_size.x)))
	var height := maxi(2,int(round(float(width)*visible_size.y/maxf(visible_size.x,1.0))))
	_reflection.size=Vector2i(width,height)
	_reflection.world_3d=camera.get_world_3d()
	_mirror.cull_mask=camera.cull_mask & ~WATER_LAYER
	_mirror.environment=camera.environment
	_mirror.attributes=camera.attributes
	_mirror.keep_aspect=camera.keep_aspect
	_mirror.projection=camera.projection
	_mirror.fov=camera.fov; _mirror.size=camera.size
	_mirror.near=camera.near; _mirror.far=camera.far
	_mirror.frustum_offset=camera.frustum_offset
	# Same reflectCamera eye/target/up construction as model.mjs, not a negative
	# scale camera basis. Camera.transform includes optional source camera offsets.
	var source := camera.get_camera_transform()
	var eye := source.origin
	var target := eye-source.basis.z
	var up := source.basis.y
	eye.y=2.0*tide-eye.y; target.y=2.0*tide-target.y; up.y=-up.y
	_mirror.global_transform=Transform3D(Basis.looking_at(target-eye,up),eye)
	var matrix := _mirror.get_camera_projection()*Projection(_mirror.get_camera_transform().affine_inverse())
	_material.set_shader_parameter("u_reflection_vp",matrix)

func get_sky_material() -> ShaderMaterial: return _sky_material
func get_water_material() -> ShaderMaterial: return _material
func get_reflection_viewport() -> SubViewport: return _reflection
func get_reflection_camera() -> Camera3D: return _mirror

func reflection_uv(world_position: Vector3) -> Vector2:
	if not is_instance_valid(_mirror): return Vector2(INF,INF)
	var projected := _mirror.get_camera_projection()*Projection(_mirror.get_camera_transform().affine_inverse())*Vector4(world_position.x,world_position.y,world_position.z,1.0)
	return Vector2(projected.x/projected.w*.5+.5,.5-projected.y/projected.w*.5)

func diagnostics() -> Dictionary:
	return {"reflectionMethod":"planar-subviewport","offscreenTargets":1 if is_instance_valid(_reflection) else 0,"sharedWorld":is_instance_valid(_camera) and _camera.is_inside_tree() and is_instance_valid(_reflection) and _reflection.world_3d==_camera.get_world_3d(),"waterLayerExcluded":is_instance_valid(_mirror) and (_mirror.cull_mask&WATER_LAYER)==0,"acceptedTime":_accepted_time,"tide":float(_state.get("tide",0.0)),"reflectionEnabled":_reflection_enabled,"mirrorEye":_mirror.global_position if is_instance_valid(_mirror) and _mirror.is_inside_tree() else Vector3.ZERO,"reflectionSize":_reflection.size if is_instance_valid(_reflection) else Vector2i.ZERO,"waterVertices":_water.mesh.surface_get_array_len(0) if is_instance_valid(_water) else 0,"disposed":_disposed,"lastError":_last_error}

func dispose() -> void:
	if _disposed: return
	_disposed=true; _reflection_enabled=false
	if is_instance_valid(_reflection): _reflection.free()
	if _owns_water and is_instance_valid(_water): _water.free()
	_reflection=null; _mirror=null; _water=null; _camera=null; _material=null; _sky_material=null
