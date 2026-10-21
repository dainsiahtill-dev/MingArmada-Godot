extends RefCounted
## Completed source cloud/fog replay adapted to Godot presentation coordinates.
## No independent process clock, physics, gameplay state or synthetic sky mesh.
const Native = preload("res://modules/scene_engine/fidelity_fx/cloud_native.gd")
const RenderCompiler = preload("res://modules/scene_engine/fidelity_fx/cloud_render_compiler.gd")
const CloudLifecycle = preload("res://modules/scene_engine/fidelity_fx/world_cloud_lifecycle.gd")
const SourceMath = preload("res://modules/scene_engine/fidelity_island/native_math.gd")
const SHADER = preload("res://modules/scene_engine/fidelity_fx/atmosphere.gdshader")
const SOURCE_METRES := 0.01
## The sea composites refraction at transparent priority 1 and writes depth.
## Clouds must blend afterwards while keeping depth tests against sea/land.
const CLOUD_RENDER_PRIORITY := 2
const AXES := Basis(Vector3(1,0,0),Vector3(0,0,-1),Vector3(0,1,0))

var _container: Node3D
var _assets := {}
var _textures := {}
var _texture_entries := {}
var _clouds: Array = []
var _fog: Array = []
var _ring := {}
var _seed := 1
var _time := 0.0
var _cloud_time := 0.0
var _journal: Array = []
var _sky_radius := 160.0
var _sky_height := 36.0
var _sky_origin := Vector3.ZERO
var _sky_bounds_layer := false
var _sky_floor := 80.0
var _sky_variation := 40.0
var _fog_duration := 33.333335876464844
var _fog_opacity := 1.0
var _reduced_motion := false
var _error := ""
var _compiled:Dictionary={}
var _render_compiler:=RenderCompiler.new()
var _cloud_cache:Array=[]
var _weather:Array=[]
var _environment_epoch:Variant=null
var _environment_revision:=-1
var _world_shadow_height:=0.12
var _world_shadow_opacity:=0.38
var _weather_shader_cache:Dictionary={}
var _light_material:Array=[]
var _display_environment:Dictionary={}
var _cloud_lifecycle:=CloudLifecycle.new()
var _cloud_lifecycle_enabled:=true

static func _json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

static func _native_to_godot(value: Array) -> Vector3:
	return Vector3(float(value[0]),float(value[2]),-float(value[1]))

static func _rotation(matrix: Array) -> Basis:
	var original := Basis(Vector3(float(matrix[0]),float(matrix[3]),float(matrix[6])),Vector3(float(matrix[1]),float(matrix[4]),float(matrix[7])),Vector3(float(matrix[2]),float(matrix[5]),float(matrix[8])))
	return AXES*original*AXES.inverse()

static func _camera_basis(camera: Camera3D) -> Dictionary:
	var inverse_axes := AXES.inverse()
	var direction := inverse_axes*(-camera.global_basis.z.normalized())
	var up := inverse_axes*camera.global_basis.y.normalized()
	var right := inverse_axes*camera.global_basis.x.normalized()
	return {"direction":[direction.x,direction.y,direction.z],"up":[up.x,up.y,up.z],"right":[right.x,right.y,right.z]}

func configure(parent: Node3D, asset_manifest: Dictionary, options: Dictionary = {}) -> Dictionary:
	dispose()
	if not is_instance_valid(parent): return _fail("Atmosphere requires owned presentation parent")
	_seed = int(options.get("crt_seed",1))
	if _seed < 0 or _seed > 0xffffffff: return _fail("Explicit CRT seed must be uint32")
	_sky_radius = float(options.get("cloud_sky_radius",160.0))
	_sky_height = float(options.get("cloud_sky_height",36.0))
	_sky_bounds_layer = bool(options.get("cloud_bounds_layer",false))
	_sky_floor = float(options.get("cloud_min_height",80.0))
	_sky_variation = float(options.get("cloud_height_variation",40.0))
	if not is_finite(_sky_radius) or _sky_radius <= 0 or not is_finite(_sky_height): return _fail("Invalid explicit camera-follow sky adaptation")
	if not is_finite(_sky_floor) or _sky_floor <= 60.0 or not is_finite(_sky_variation) or _sky_variation < 0.0: return _fail("Invalid target cloud navigation clearance")
	_fog_opacity = float(options.get("fog_opacity",1.0))
	if not is_finite(_fog_opacity) or _fog_opacity < 0.0 or _fog_opacity > 1.0: return _fail("Invalid target ground-fog opacity")
	_reduced_motion = bool(options.get("reduced_motion",false))
	_cloud_lifecycle_enabled=bool(options.get("cloud_lifecycle",true))
	_world_shadow_height=float(options.get("cloud_shadow_surface_height",0.12))
	_world_shadow_opacity=clampf(float(options.get("cloud_shadow_opacity",0.38)),0.0,1.0)
	for entry: Dictionary in asset_manifest.get("atmosphere",{}).get("assets",[]):
		var asset := _json(str(entry.get("data_path","")))
		if not asset.is_empty(): _assets[str(entry.file)] = asset
	if _assets.size() != 6: return _fail("Five original cloud prototypes and original ground fog JSON required")
	for source: String in ["domecloud1.nif","domecloud2.nif","domecloud3.nif","domecloud4.nif","domecloud5.nif","fx_groundfog01.nif"]:
		if not _assets.has(source): return _fail("Original atmosphere source missing: "+source)
	for source:String in _assets:_compiled[source]=_render_compiler.compile_asset(_assets[source])
	for entry: Dictionary in asset_manifest.get("textures",[]):
		var name := str(entry.get("name","")).to_lower()
		if name not in ["cloud_bw.dds","fx_groundfog_crop01.dds"]: continue
		var format_name := str(entry.get("godotCompressedImageFormat",""))
		var formats := {"FORMAT_DXT1":Image.FORMAT_DXT1,"FORMAT_DXT3":Image.FORMAT_DXT3,"FORMAT_DXT5":Image.FORMAT_DXT5}
		var path := str(entry.get("compressedMipPath",""))
		if not formats.has(format_name) or not FileAccess.file_exists(path): return _fail("Full original compressed mip payload missing: "+name)
		# Image uses original BC bytes and all authored mips, never PNG mip0 or
		# generate_mipmaps. Godot creates its GPU texture from this Image.
		var image := Image.create_from_data(int(entry.width),int(entry.height),bool(entry.mipmaps),int(formats[format_name]),FileAccess.get_file_as_bytes(path))
		if image == null or image.is_empty(): return _fail("Original compressed Image rejected: "+name)
		_textures[name] = ImageTexture.create_from_image(image)
		_texture_entries[name] = entry
	if _textures.size() != 2: return _fail("Cloud and fog original DDS mip textures required")
	var weather_manifest:=_json("res://assets/data/fidelity_fx/weather/manifest.json")
	for entry:Dictionary in weather_manifest.get("assets",[]):
		var source:=_json(str(entry.data_path))
		if str(entry.file)=="stormcloud_sound.nif":source=_render_compiler.bind_sequence(source,_json(str(weather_manifest.stormSequence)))
		_assets[str(entry.file)]=source
	for entry:Dictionary in weather_manifest.get("textures",[]):
		var formats:Dictionary={"FORMAT_DXT1":Image.FORMAT_DXT1,"FORMAT_DXT3":Image.FORMAT_DXT3,"FORMAT_DXT5":Image.FORMAT_DXT5}
		if not formats.has(str(entry.godotCompressedImageFormat)) or not FileAccess.file_exists(str(entry.compressedMipPath)):return _fail("Original weather DDS mip payload missing")
		var image:=Image.create_from_data(int(entry.width),int(entry.height),bool(entry.mipmaps),int(formats[str(entry.godotCompressedImageFormat)]),FileAccess.get_file_as_bytes(str(entry.compressedMipPath)))
		if image==null or image.is_empty():return _fail("Original weather compressed Image rejected")
		_textures[str(entry.name)]=ImageTexture.create_from_image(image);_texture_entries[str(entry.name)]=entry
	_container = Node3D.new()
	_container.name = "OriginalCloudAndFog"
	parent.add_child(_container)
	_ring = Native.create_cloud_ring(_seed)
	for clone: Dictionary in _ring.nodes:
		var group: Array = []
		for mesh: Dictionary in Native.original_meshes(_assets[clone.prototype]):
			var record := _create_mesh(mesh,"OriginalCloud_%s_%d"%[str(clone.name).strip_edges(),int(mesh.block)],true)
			if record.is_empty(): return _fail("Unsupported original cloud render state")
			group.append(record)
		_clouds.append(group)
		_cloud_cache.append({})
	var placements: Array = options.get("fog_placements",[])
	if placements.size() > 20: return _fail("Original ground-fog system supports prototype plus 19 clones")
	for i in placements.size():
		if not placements[i] is Transform3D: return _fail("Fog world placement must be explicit Transform3D")
		var group: Array = []
		for mesh: Dictionary in Native.original_meshes(_assets["fx_groundfog01.nif"],0.0,{},true):
			var record := _create_mesh(mesh,"OriginalGroundFog_%d_%d"%[i,int(mesh.block)])
			if record.is_empty(): return _fail("Unsupported original fog render state")
			record.material.set_shader_parameter("display_opacity",_fog_opacity)
			group.append(record)
		_fog.append({"meshes":group,"placement":placements[i],"phase":Native.f32(i*_fog_duration*Native.FOG_PHASE_SCALE),"stateTime":-INF,"states":[],"compiled":_render_compiler.compile_asset(_assets["fx_groundfog01.nif"])})
	for index in 3:
		var resource:="stormcloud_sound.nif" if index==0 else "cloud00.nif"
		if not _assets.has(resource):return _fail("Original world weather source missing: "+resource)
		var graph:=_render_compiler.compile_asset(_assets[resource])
		var group:Array=[]
		for mesh:Dictionary in _render_compiler.render_states(graph):
			var record:=_create_mesh(mesh,"OriginalWorldWeather_%d_%d"%[index,int(mesh.block)])
			if record.is_empty():return _fail("Unsupported original world weather render state")
			record.bakedShadow=str(mesh.texture) in ["cloud_sh.dds","stormshadow.dds"]
			if record.bakedShadow:record.material.set_shader_parameter("display_opacity",_world_shadow_opacity)
			else:record.material.render_priority=CLOUD_RENDER_PRIORITY
			group.append(record)
		_weather.append({"meshes":group,"compiled":graph,"resource":resource,"stateTime":-INF,"states":[]})
	return {"ok":true,"cloudClones":_clouds.size(),"cloudMeshes":_mesh_count(_clouds),"fogInstances":_fog.size(),"fogMeshes":_fog.size()*20,"liveOriginalRandState":"unresolved; explicit target CRT seed","skyPlacement":"explicit camera-follow target adaptation","fogWorldPlacement":"explicit target adaptation; original placement unrecovered"}

func _fail(reason: String) -> Dictionary:
	dispose()
	_error = reason
	return {"ok":false,"error":reason}

func _create_mesh(source: Dictionary, name: String, sky_cloud: bool = false) -> Dictionary:
	if int(source.filterMode) != 2 or not _textures.has(source.texture): return {}
	if int(source.clampMode) not in [0,3]: return {} # No current source asset uses mixed-axis addressing.
	var test_enabled := (int(source.alphaFlags)&512) != 0
	if test_enabled and ((int(source.alphaFlags)>>10)&7) != 4: return {}
	var vertices := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	for value: Array in source.localVertices: vertices.append(_native_to_godot(value)*SOURCE_METRES)
	for value: Dictionary in source.sourceUV: uv.append(Vector2(float(value.u),float(value.v)))
	for triangle: Array in source.triangles:
		# Source triangles retained; Godot's clockwise submission reverses order.
		indices.append_array(PackedInt32Array([int(triangle[0]),int(triangle[2]),int(triangle[1])]))
	var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material := ShaderMaterial.new()
	if sky_cloud:material.render_priority=CLOUD_RENDER_PRIORITY
	material.shader = SHADER
	# Preserve authored blend/depth gates where Godot exposes them. In particular
	# flags0 stormshadow is adapted to depth-test at sea height, avoiding an
	# always-on-top screen darkener. Stencil-disabled draw_mode3 is double-sided.
	if source.has("depthFlags"):
		var depth:=int(source.depthFlags)
		var modes:="unshaded, cull_disabled, blend_mix, depth_draw_never, fog_disabled"
		if depth&2:modes=modes.replace("depth_draw_never","depth_draw_always")
		var key:="%d:%d"%[depth,int(source.alphaFlags)]
		if not _weather_shader_cache.has(key):
			var shader:=Shader.new();shader.code=SHADER.code.replace("unshaded, cull_disabled, blend_mix, depth_draw_never, fog_disabled",modes)
			_weather_shader_cache[key]=shader
		material.shader=_weather_shader_cache[key]
	material.set_shader_parameter("original_texture",_textures[source.texture])
	material.set_shader_parameter("original_clamped_texture",_textures[source.texture])
	material.set_shader_parameter("original_alpha_threshold",float(source.threshold)/255.0 if test_enabled else -1.0)
	material.set_shader_parameter("source_wrap_u",(int(source.clampMode)&2) != 0)
	material.set_shader_parameter("source_wrap_v",(int(source.clampMode)&1) != 0)
	var entry: Dictionary = _texture_entries[source.texture]
	material.set_shader_parameter("source_half_texel",Vector2(0.5/float(entry.width),0.5/float(entry.height)))
	var node := MeshInstance3D.new()
	node.name = name
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visible = false
	_container.add_child(node)
	var radius := 0.0
	for point: Vector3 in vertices: radius=maxf(radius,point.length())
	return {"node":node,"material":material,"block":int(source.block),"radius":radius,"sourceDepthFlags":int(source.get("depthFlags",1)),"sourceAlphaFlags":int(source.alphaFlags)}

func _seek_cloud(time: float) -> void:
	if time == _cloud_time: return
	# Native update is input-sequence dependent. Retain actual supplied snapshot
	# deltas so rewind to an observed time replays exactly, including strict >.
	var recorded_end := float(_journal[-1].to) if not _journal.is_empty() else 0.0
	if time < _cloud_time or time <= recorded_end:
		_ring = Native.create_cloud_ring(_seed)
		var cursor := 0.0
		for step: Dictionary in _journal:
			if float(step.to) <= time:
				Native.advance_clouds(_ring,float(step.delta))
				cursor = float(step.to)
			else:
				if time > cursor: Native.advance_clouds(_ring,time-cursor)
				break
	elif time > recorded_end:
		if _cloud_time < recorded_end:
			# Rejoin retained original input history before appending a new delta.
			_ring = Native.create_cloud_ring(_seed)
			for step: Dictionary in _journal: Native.advance_clouds(_ring,float(step.delta))
		var delta := time-recorded_end
		Native.advance_clouds(_ring,delta)
		_journal.append({"to":time,"delta":delta})
	_cloud_time = time

func set_reduced_motion(enabled: bool) -> void:
	if _reduced_motion and not enabled:_cloud_lifecycle.rebase_time(_time)
	_reduced_motion = enabled

func set_cloud_lifecycle_enabled(enabled:bool)->void:
	if enabled==_cloud_lifecycle_enabled:return
	_cloud_lifecycle_enabled=enabled
	_cloud_lifecycle.clear()

func reset_timeline() -> void:
	# A new encounter is a new input sequence, not a seek into a prior encounter.
	# Manual rewind within one encounter keeps the source replay journal.
	if _ring.is_empty(): return
	_ring = Native.create_cloud_ring(_seed)
	_journal.clear()
	_time = 0.0; _cloud_time = 0.0
	_display_environment.clear();_environment_epoch=null;_environment_revision=-1
	_clear_render_cache()

func _clear_render_cache()->void:
	_cloud_lifecycle.clear()
	for i in _cloud_cache.size():_cloud_cache[i]={}
	for instance:Dictionary in _fog:
		instance.stateTime=-INF;instance.states=[];instance.compiled=_render_compiler.compile_asset(_assets["fx_groundfog01.nif"])
	for instance:Dictionary in _weather:
		instance.stateTime=-INF;instance.states=[];instance.compiled=_render_compiler.compile_asset(_assets[instance.resource])
		instance.erase("lifecycleRadius")

func apply_snapshot(snapshot: Dictionary, camera: Camera3D, focus: Vector3 = Vector3.ZERO, reflection_camera:Camera3D=null) -> void:
	if not is_instance_valid(_container) or not is_instance_valid(camera): return
	var environment:Dictionary=snapshot.get("environment",{})
	if environment.is_empty():environment=snapshot.get("native",{}).get("environment",{})
	var supplied_time: Variant = environment.get("acceptedTime",snapshot.get("time_seconds",snapshot.get("time",0.0)))
	if not (supplied_time is int or supplied_time is float) or not is_finite(float(supplied_time)): return
	if float(supplied_time)<_time:
		_clear_render_cache();_display_environment.clear()
	_time = maxf(0.0,float(supplied_time))
	# Preserve accepted time even while the optional target motion preference
	# holds source animation. Rewinds still remove future presentation state.
	if not environment.is_empty() and environment.get("sky",{}).has("ring"):
		var new_epoch:bool=_environment_epoch!=environment.get("epoch")
		if new_epoch:_clear_render_cache();_environment_epoch=environment.get("epoch")
		_environment_revision=int(environment.get("revision",-1))
		# Accepted metadata always advances. Display state is a local motion
		# preference, detached from producer RNG and controller history. Epoch
		# changes install their first packet even when motion remains reduced.
		if new_epoch or _display_environment.is_empty() or not _reduced_motion:
			_display_environment=environment.duplicate(true)
			if not _same_ring_layout(_ring,_display_environment.sky.ring):_install_ring_layout(_display_environment.sky.ring)
			_ring=_display_environment.sky.ring.duplicate(true);_cloud_time=float(_display_environment.sky.appTime)
		environment=_display_environment
	else:
		_display_environment.clear()
		if not _reduced_motion or _time < _cloud_time:_seek_cloud(_time)
	_sky_origin = camera.global_position+Vector3(0,_sky_height,0)
	var native_camera := _camera_basis(camera)
	var scale_adaptation := _sky_radius/SOURCE_METRES
	var groups: Array = []
	var low_bounds: Array[float] = []
	for i in _ring.nodes.size():
		var clone: Dictionary = _ring.nodes[i]
		# Native cloud geometry is sampled at time=0, animate=false. Its only
		# dynamic inputs are clone rotation and main-view billboard basis. Camera
		# translation follows below on every snapshot, including cache hits.
		var key:Dictionary={"prototype":clone.prototype,"rotation":clone.rotation,"camera":native_camera,"radius":_sky_radius}
		var cached:Dictionary=_cloud_cache[i]
		if cached.is_empty() or cached.key!=key:
			var outer:Dictionary={"rotation":clone.rotation,"translation":_render_compiler._transform_vector(clone.rotation,[0,1,0]),"scale":1.0}
			var meshes:Array=_render_compiler.render_minimum_states(_compiled[clone.prototype],outer,native_camera)
			var lowest:=INF
			for mesh:Dictionary in meshes:lowest=minf(lowest,float(mesh.minimumZ)*_sky_radius)
			cached={"key":key.duplicate(true),"states":meshes,"lowest":lowest}
			_cloud_cache[i]=cached
		groups.append(cached.states)
		low_bounds.append(float(cached.lowest))
	var minimum: float = low_bounds.min() if not low_bounds.is_empty() else 0.0
	var maximum: float = low_bounds.max() if not low_bounds.is_empty() else 0.0
	for i in groups.size():
		var origin := _sky_origin
		if _sky_bounds_layer:
			# Explicit game sky placement: preserve each whole prototype's shape
			# and internal sparse downward patches, then translate the whole group.
			# The source's lower/higher group ordering remains visible in this deck.
			var variation := (low_bounds[i]-minimum)/maxf(0.001,maximum-minimum)
			origin.y = _sky_floor+variation*_sky_variation-low_bounds[i]
		_update_group(_clouds[i],groups[i],Transform3D(Basis.IDENTITY,origin),scale_adaptation)
	for index in _fog.size():
		var instance:Dictionary=_fog[index]
		var source_time:float=_cloud_time+float(instance.phase)
		if source_time!=float(instance.stateTime):
			var clocks:Array=environment.get("source",{}).get("fogClocks",[])
			if index<clocks.size():
				var restored:Array=[]
				for original:Dictionary in _render_compiler.controller_snapshot(instance.compiled):restored.append(clocks[index].duplicate(true))
				_render_compiler.restore_controllers(instance.compiled,restored)
			instance.states=_render_compiler.render_states(instance.compiled,source_time,{},true,{},false,false,true)
			instance.stateTime=source_time
		_update_group(instance.meshes,instance.states,instance.placement,1.0)
	_apply_weather(environment,native_camera,camera,reflection_camera)
	var light:Array=environment.get("lighting",{}).get("sourceLightFields",{}).get("lightColor",[1.0,1.0,1.0])
	if light!=_light_material:
		_light_material=light.duplicate()
		for group:Array in _clouds:
			for record:Dictionary in group:record.material.set_shader_parameter("source_environment_color",Vector3(float(light[0]),float(light[1]),float(light[2])))
	# Focus is accepted for caller's uniform presentation API. It never replaces
	# explicit authored fog placement or camera-directed source billboards.
	_container.set_meta("snapshot_focus",focus)

func _same_ring_layout(left:Dictionary,right:Dictionary)->bool:
	var a:Array=left.get("nodes",[]);var b:Array=right.get("nodes",[])
	if a.size()!=b.size():return false
	for index in a.size():
		if a[index].name!=b[index].name or a[index].prototype!=b[index].prototype:return false
	return true
func _install_ring_layout(ring:Dictionary)->void:
	for group:Array in _clouds:
		for record:Dictionary in group:record.node.free()
	_clouds.clear();_cloud_cache.clear();_light_material.clear()
	for clone:Dictionary in ring.nodes:
		var group:Array=[]
		for mesh:Dictionary in Native.original_meshes(_assets[clone.prototype]):group.append(_create_mesh(mesh,"OriginalCloud_%s_%d"%[str(clone.name).strip_edges(),int(mesh.block)],true))
		_clouds.append(group);_cloud_cache.append({})

func _weather_radius(instance:Dictionary,scale_adaptation:float,root_height:float)->float:
	# Enclose the complete hierarchy, including invisible KF parts and any
	# billboard orientation. Receiver shadows are placed on a separate sea plane.
	var radius:=0.0
	for i in mini(instance.meshes.size(),instance.states.size()):
		var record:Dictionary=instance.meshes[i]
		var state:Dictionary=instance.states[i]
		var offset:=_native_to_godot(state.world.translation)*SOURCE_METRES*scale_adaptation
		var extent:=float(record.radius)*absf(float(state.world.scale)*scale_adaptation)
		var billboard:Dictionary=state.get("billboard",{})
		if not billboard.is_empty():
			var frame:Dictionary=billboard.parent
			var relative:Dictionary=billboard.relative
			offset=_native_to_godot(frame.translation)*SOURCE_METRES*scale_adaptation
			extent=(_native_to_godot(relative.translation).length()*SOURCE_METRES+float(record.radius)*absf(float(relative.scale)))*absf(float(frame.scale)*scale_adaptation)
		if record.get("bakedShadow",false):offset.y=_world_shadow_height-root_height
		radius=maxf(radius,offset.length()+extent)
	return radius

func _apply_weather(environment:Dictionary,camera:Dictionary,view:Camera3D,reflection:Camera3D)->void:
	var packets:Array=environment.get("worldClouds",[])
	var planes:Array[Plane]=[]
	var additional:Array[Plane]=[]
	if _cloud_lifecycle_enabled:planes.assign(view.get_frustum())
	if _cloud_lifecycle_enabled and is_instance_valid(reflection) and reflection.is_inside_tree():additional.assign(reflection.get_frustum())
	var visible:=func(center:Vector3,radius:float)->bool:return CloudLifecycle.sphere_in_views(center,radius,planes,additional)
	for index in _weather.size():
		var instance:Dictionary=_weather[index]
		if index>=packets.size():
			for record:Dictionary in instance.meshes:record.node.visible=false
			continue
		var packet:Dictionary=packets[index]
		var time:=float(packet.appTime)
		if time!=float(instance.stateTime):
			if packet.has("controllerState"):_render_compiler.restore_controllers(instance.compiled,packet.controllerState)
			instance.states=_render_compiler.render_states(instance.compiled,time,{},true,camera,false,false,true)
			instance.stateTime=time
		var pose:Array=packet.worldPosition
		var placement:=Transform3D(Basis.IDENTITY,Vector3(float(pose[0]),float(pose[1]),float(pose[2])))
		if _cloud_lifecycle_enabled and packet.has("driftVelocity") and packet.has("generation"):
			# Never shrink the actor envelope as a KF part fades or contracts.
			instance.lifecycleRadius=maxf(float(instance.get("lifecycleRadius",0.0)),_weather_radius(instance,float(packet.modelScale),placement.origin.y))
			var display:Dictionary=_cloud_lifecycle.advance(index,packet,time,instance.lifecycleRadius,visible)
			if not display.is_empty():placement.origin=display.position
		_update_group(instance.meshes,instance.states,placement,float(packet.modelScale))
		for record:Dictionary in instance.meshes:
			if record.get("bakedShadow",false):
				# Original hierarchy/XY motion is retained. Receiver sea height is a
				# target adapter because game-world and source model units differ.
				var transform:Transform3D=record.node.global_transform
				transform.origin.y=_world_shadow_height
				record.node.global_transform=transform

func _update_group(records: Array, meshes: Array, placement: Transform3D, scale_adaptation: float) -> void:
	for i in mini(records.size(),meshes.size()):
		var state: Dictionary = meshes[i]
		var record: Dictionary = records[i]
		var native_basis := _rotation(state.world.rotation).scaled(Vector3.ONE*float(state.world.scale)*scale_adaptation)
		var position := _native_to_godot(state.world.translation)*SOURCE_METRES*scale_adaptation
		record.node.global_transform = placement*Transform3D(native_basis,position)
		var billboard: Dictionary = state.get("billboard",{})
		record.material.set_shader_parameter("source_billboard_enabled",not billboard.is_empty())
		if not billboard.is_empty():
			var frame: Dictionary = billboard.parent
			var relative: Dictionary = billboard.relative
			var parent_origin := placement * (_native_to_godot(frame.translation)*SOURCE_METRES*scale_adaptation)
			var parent_scale := float(frame.scale)*scale_adaptation
			var relative_transform := Transform3D(_rotation(relative.rotation).scaled(Vector3.ONE*float(relative.scale)),_native_to_godot(relative.translation)*SOURCE_METRES)
			record.material.set_shader_parameter("source_billboard_rotation",placement.basis*_rotation(frame.rotation))
			record.material.set_shader_parameter("source_billboard_origin",parent_origin)
			record.material.set_shader_parameter("source_billboard_scale",parent_scale)
			record.material.set_shader_parameter("source_billboard_relative",relative_transform)
			# Cover the whole source billboard sphere in every view, including the
			# existing reflection camera, without touching its pass or cull mask.
			var radius := (relative_transform.origin.length()+float(record.radius)*float(relative.scale))*parent_scale/maxf(0.00001,record.node.global_basis.x.length())
			var center: Vector3 = record.node.global_transform.affine_inverse()*parent_origin
			record.node.custom_aabb=AABB(center-Vector3.ONE*radius,Vector3.ONE*(2.0*radius))
		var color: Array = state.color
		record.material.set_shader_parameter("original_material",Color(float(color[0]),float(color[1]),float(color[2]),float(state.alpha)))
		record.material.set_shader_parameter("original_uv_matrix",SourceMath.texture_basis(state.uvMatrix))
		record.node.visible = float(state.alpha) > 0.0

static func _mesh_count(groups: Array) -> int:
	var count := 0
	for group: Array in groups: count += group.size()
	return count

func diagnostics() -> Dictionary:
	var fog_phases: Array = []
	for instance: Dictionary in _fog: fog_phases.append(instance.phase)
	var weather_meshes:=0;var shadow_meshes:=0
	for instance:Dictionary in _weather:
		weather_meshes+=instance.meshes.size()
		for record:Dictionary in instance.meshes:
			if record.get("bakedShadow",false):shadow_meshes+=1
	return {"worldCloudLifecycle":{"enabled":_cloud_lifecycle_enabled,"states":_cloud_lifecycle.snapshot(),"viewMarginMetres":CloudLifecycle.VIEW_MARGIN_METRES,"authority":"target display policy; original source reset/RNG retained"},"time":_time,"animationTime":_cloud_time,"historySteps":_journal.size(),"reducedMotion":_reduced_motion,"fogOpacity":_fog_opacity,"cloudClones":_clouds.size(),"cloudMeshes":_mesh_count(_clouds),"fogInstances":_fog.size(),"fogMeshes":_fog.size()*20,"fogPhases":fog_phases,"cloudUpdates":int(_ring.get("updates",0)),"cloudAccumulator":float(_ring.get("accumulator",0.0)),"firstCloudRotation":_ring.nodes[0].rotation.duplicate() if not _ring.is_empty() else [],"skyOrigin":_sky_origin,"sourceMetres":SOURCE_METRES,"cameraFollowSky":true,"skyBoundsLayer":_sky_bounds_layer,"cloudMinimumHeight":_sky_floor,"skyRadius":_sky_radius,"independentClock":false,"error":_error,"worldWeatherInstances":_weather.size(),"worldWeatherMeshes":weather_meshes,"bakedCloudShadowMeshes":shadow_meshes,"independentInstanceClocks":true,"environmentEpoch":_environment_epoch,"environmentRevision":_environment_revision,"bakedShadowAdaptation":{"surfaceHeight":_world_shadow_height,"opacity":_world_shadow_opacity,"depthTest":true},"stormAnimationAuthority":"authored KF target binding; target sequence selection; original KFM event selection unrecovered"}

func dispose() -> void:
	if is_instance_valid(_container):
		if is_instance_valid(_container.get_parent()): _container.get_parent().remove_child(_container)
		_container.free()
	_container = null
	_assets.clear(); _textures.clear(); _texture_entries.clear()
	_compiled.clear();_cloud_cache.clear();_weather.clear();_weather_shader_cache.clear()
	_clouds.clear(); _fog.clear(); _ring.clear(); _journal.clear()
	_time = 0.0; _cloud_time = 0.0; _sky_origin = Vector3.ZERO; _error = ""
	_fog_opacity = 1.0; _reduced_motion = false
	_sky_bounds_layer = false; _sky_floor=80.0; _sky_variation=40.0
	_environment_epoch=null;_environment_revision=-1
	_light_material.clear();_display_environment.clear();_cloud_lifecycle.clear();_cloud_lifecycle_enabled=true
