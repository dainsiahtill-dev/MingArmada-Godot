extends RefCounted
## Completed source cloud/fog replay adapted to Godot presentation coordinates.
## No independent process clock, physics, gameplay state or synthetic sky mesh.
const Native = preload("res://modules/scene_engine/fidelity_fx/cloud_native.gd")
const SourceMath = preload("res://modules/scene_engine/fidelity_island/native_math.gd")
const SHADER = preload("res://modules/scene_engine/fidelity_fx/atmosphere.gdshader")
const SOURCE_METRES := 0.01
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
	for entry: Dictionary in asset_manifest.get("atmosphere",{}).get("assets",[]):
		var asset := _json(str(entry.get("data_path","")))
		if not asset.is_empty(): _assets[str(entry.file)] = asset
	if _assets.size() != 6: return _fail("Five original cloud prototypes and original ground fog JSON required")
	for source: String in ["domecloud1.nif","domecloud2.nif","domecloud3.nif","domecloud4.nif","domecloud5.nif","fx_groundfog01.nif"]:
		if not _assets.has(source): return _fail("Original atmosphere source missing: "+source)
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
	_container = Node3D.new()
	_container.name = "OriginalCloudAndFog"
	parent.add_child(_container)
	_ring = Native.create_cloud_ring(_seed)
	for clone: Dictionary in _ring.nodes:
		var group: Array = []
		for mesh: Dictionary in Native.original_meshes(_assets[clone.prototype]):
			var record := _create_mesh(mesh,"OriginalCloud_%s_%d"%[str(clone.name).strip_edges(),int(mesh.block)])
			if record.is_empty(): return _fail("Unsupported original cloud render state")
			group.append(record)
		_clouds.append(group)
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
		_fog.append({"meshes":group,"placement":placements[i],"phase":Native.f32(i*_fog_duration*Native.FOG_PHASE_SCALE)})
	return {"ok":true,"cloudClones":_clouds.size(),"cloudMeshes":_mesh_count(_clouds),"fogInstances":_fog.size(),"fogMeshes":_fog.size()*20,"liveOriginalRandState":"unresolved; explicit target CRT seed","skyPlacement":"explicit camera-follow target adaptation","fogWorldPlacement":"explicit target adaptation; original placement unrecovered"}

func _fail(reason: String) -> Dictionary:
	dispose()
	_error = reason
	return {"ok":false,"error":reason}

func _create_mesh(source: Dictionary, name: String) -> Dictionary:
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
	material.shader = SHADER
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
	return {"node":node,"material":material,"block":int(source.block),"radius":radius}

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
	_reduced_motion = enabled

func reset_timeline() -> void:
	# A new encounter is a new input sequence, not a seek into a prior encounter.
	# Manual rewind within one encounter keeps the source replay journal.
	if _ring.is_empty(): return
	_ring = Native.create_cloud_ring(_seed)
	_journal.clear()
	_time = 0.0; _cloud_time = 0.0

func apply_snapshot(snapshot: Dictionary, camera: Camera3D, focus: Vector3 = Vector3.ZERO) -> void:
	if not is_instance_valid(_container) or not is_instance_valid(camera): return
	var supplied_time: Variant = snapshot.get("time_seconds",snapshot.get("time",0.0))
	if not (supplied_time is int or supplied_time is float) or not is_finite(float(supplied_time)): return
	_time = maxf(0.0,float(supplied_time))
	# Preserve accepted time even while the optional target motion preference
	# holds source animation. Rewinds still remove future presentation state.
	if not _reduced_motion or _time < _cloud_time: _seek_cloud(_time)
	_sky_origin = camera.global_position+Vector3(0,_sky_height,0)
	var native_camera := _camera_basis(camera)
	var scale_adaptation := _sky_radius/SOURCE_METRES
	var groups: Array = []
	var low_bounds: Array[float] = []
	for i in _ring.nodes.size():
		var clone: Dictionary = _ring.nodes[i]
		var outer := {"rotation":clone.rotation,"translation":Native.transform_vector(clone.rotation,[0,1,0]),"scale":1.0}
		var meshes := Native.original_meshes(_assets[clone.prototype],0.0,outer,false,native_camera)
		groups.append(meshes)
		var lowest := INF
		for mesh: Dictionary in meshes:
			for vertex: Array in mesh.vertices: lowest=minf(lowest,float(vertex[2])*_sky_radius)
		low_bounds.append(lowest)
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
	for instance: Dictionary in _fog:
		var meshes := Native.original_meshes(_assets["fx_groundfog01.nif"],_cloud_time+float(instance.phase),{},true)
		_update_group(instance.meshes,meshes,instance.placement,1.0)
	# Focus is accepted for caller's uniform presentation API. It never replaces
	# explicit authored fog placement or camera-directed source billboards.
	_container.set_meta("snapshot_focus",focus)

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
	return {"time":_time,"animationTime":_cloud_time,"historySteps":_journal.size(),"reducedMotion":_reduced_motion,"fogOpacity":_fog_opacity,"cloudClones":_clouds.size(),"cloudMeshes":_mesh_count(_clouds),"fogInstances":_fog.size(),"fogMeshes":_fog.size()*20,"fogPhases":fog_phases,"cloudUpdates":int(_ring.get("updates",0)),"cloudAccumulator":float(_ring.get("accumulator",0.0)),"firstCloudRotation":_ring.nodes[0].rotation.duplicate() if not _ring.is_empty() else [],"skyOrigin":_sky_origin,"sourceMetres":SOURCE_METRES,"cameraFollowSky":true,"skyBoundsLayer":_sky_bounds_layer,"cloudMinimumHeight":_sky_floor,"skyRadius":_sky_radius,"independentClock":false,"error":_error}

func dispose() -> void:
	if is_instance_valid(_container):
		if is_instance_valid(_container.get_parent()): _container.get_parent().remove_child(_container)
		_container.free()
	_container = null
	_assets.clear(); _textures.clear(); _texture_entries.clear()
	_clouds.clear(); _fog.clear(); _ring.clear(); _journal.clear()
	_time = 0.0; _cloud_time = 0.0; _sky_origin = Vector3.ZERO; _error = ""
	_fog_opacity = 1.0; _reduced_motion = false
	_sky_bounds_layer = false; _sky_floor=80.0; _sky_variation=40.0
