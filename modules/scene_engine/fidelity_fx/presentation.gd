extends Node3D
## Render completed source replay in the game. Runtime stays in native units;
## event placement, metre scale and wave-conforming rings are explicit adapters.
const MANIFEST := "res://assets/data/fidelity_fx/manifest.json"
const RUNTIME := "res://modules/scene_engine/fidelity_fx/particle_runtime.gd"
const MixShader = preload("res://modules/scene_engine/fidelity_fx/particle.gdshader")
const AddShader = preload("res://modules/scene_engine/fidelity_fx/particle_add.gdshader")
const NativeMath = preload("res://modules/scene_engine/fidelity_fx/native_particle_math.gd")
const CpuBatch = preload("res://modules/scene_engine/fidelity_fx/cpu_particle_batch.gd")
const METRES_PER_UNIT := 0.01
const GAME_SOURCES := ["fx_cannon_fire_01.nif","cannon_ball_splash_01.nif","cannon_ball_splash_02.nif","cannon_ball_splash_03.nif"]
static var _manifest: Dictionary = {}
static var _assets: Dictionary = {}
# Validated owned source data only; spawned lifecycles retain independent state.
static var _prepared_sources: Dictionary = {}
static var _textures: Dictionary = {}
var _replay: RefCounted
var _geometry: Dictionary = {}
var _surface_layouts: Dictionary = {}
# The dummy backend deliberately ignores region writes; retain real arrays there.
var _region_updates := DisplayServer.get_name() != "headless"
var _materials: Dictionary = {}
var _origin := Vector3.ZERO
var _orientation := Basis.IDENTITY
var _size := 1.0
var _camera: Camera3D
var _water: Callable
var _sea: Callable
var _source := ""
var _age := -1.0
var _absolute_time := -1.0
var _rendered := 0
var _triangles := 0
var _seed := 1
var _configured := false
var _render_profile := "native"
var _clock_mode := "observer"
var _render_unit := "particle"
var _expired := false
var _last_error := ""
var _draw_order: Array = []
var _game_flash := 0
var _present_key: Dictionary = {}
var _present_result := false
var _mesh_key: Dictionary = {}
var _display_meshes: Array = []
var _seek_age := NAN
var _seek_replay_id := 0
var _seek_error := ""
var _filter_revision := 0
var _pending_snapshot: Dictionary = {}
var _worker_job: Dictionary = {}
var _worker_task := -1
var _worker_dispatched := 0
var _worker_joined := 0
const GAME_FLASH_DURATION := 0.14

static func load_manifest() -> Dictionary:
	if _manifest.is_empty() and FileAccess.file_exists(MANIFEST):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if parsed is Dictionary and parsed.get("schema_version",0) == 1: _manifest = parsed
	return _manifest

static func _asset(name: String) -> Dictionary:
	if _assets.has(name): return _assets[name]
	for entry: Dictionary in load_manifest().get("effects",[]):
		if name not in String(entry.get("file",entry.get("id",""))): continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(entry.data_path)))
		if parsed is Dictionary: _assets[name] = parsed; return parsed
	return {}

static func _texture(name: String) -> Texture2D:
	var key := name.to_lower()
	if _textures.has(key): return _textures[key]
	for entry: Dictionary in load_manifest().get("textures",[]):
		if String(entry.name).to_lower() != key: continue
		var formats := {"FORMAT_DXT1":Image.FORMAT_DXT1,"FORMAT_DXT3":Image.FORMAT_DXT3,"FORMAT_DXT5":Image.FORMAT_DXT5}
		var format_key := String(entry.get("godotCompressedImageFormat",""))
		var image: Image
		if formats.has(format_key):
			image = Image.create_from_data(int(entry.width),int(entry.height),bool(entry.mipmaps),int(formats[format_key]),FileAccess.get_file_as_bytes(String(entry.compressedMipPath)))
		elif FileAccess.file_exists(String(entry.get("rgbaMipPath",""))):
			image = Image.create_from_data(int(entry.width),int(entry.height),bool(entry.mipmaps),Image.FORMAT_RGBA8,FileAccess.get_file_as_bytes(String(entry.rgbaMipPath)))
		if image == null or image.is_empty(): return null
		var texture := ImageTexture.create_from_image(image)
		_textures[key] = texture
		return texture
	return null

static func prewarm_game_sources() -> Dictionary:
	# Loading owns cold source validation and original texture uploads. No replay,
	# pool, material, render carrier or birth update is created by preparation.
	var report := {"ok":false,"sources":[],"textures":[],"errors":[]}
	var script: Script = load(RUNTIME) if FileAccess.file_exists(RUNTIME) else null
	if script == null:
		report.errors.append("Source replay runtime unavailable")
		return report
	for source: String in GAME_SOURCES:
		var asset := _asset(source)
		if asset.is_empty():
			report.errors.append("Source asset unavailable: "+source)
			continue
		var prepared: RefCounted = _prepared_sources.get(source)
		if prepared == null:
			prepared = script.new()
			if not prepared.configure(asset,1,false):
				report.errors.append(source+": "+prepared.get_last_error())
				continue
			_prepared_sources[source] = prepared
		report.sources.append(source)
		var blueprint: Dictionary = prepared.get("_asset")
		for block: Dictionary in blueprint.blocks:
			if block.type != "NiSourceTexture": continue
			var name := String(block.fields.get("file_name","")).to_lower()
			if report.textures.has(name): continue
			if name.is_empty() or _texture(name) == null:
				report.errors.append("Source texture unavailable: "+name)
				continue
			report.textures.append(name)
	report.ok = report.errors.is_empty()
	return report

func configure(source: String, options: Dictionary = {}) -> bool:
	dispose()
	var script: Script = load(RUNTIME) if FileAccess.file_exists(RUNTIME) else null
	var asset := _asset(source)
	if script == null or asset.is_empty(): return false
	_origin = options.get("origin",Vector3.ZERO)
	_size = float(options.get("scale",1.0))
	if not _origin.is_finite() or not is_finite(_size) or _size <= 0.0: return false
	_seed = int(options.get("seed",1))
	_source = source
	_render_profile = String(options.get("render_profile","native"))
	_clock_mode = String(options.get("clock_mode","observer"))
	_render_unit = String(options.get("render_unit","particle"))
	if _render_unit not in ["particle","system"]:
		_last_error = "Unsupported effect render unit"
		return false
	if _clock_mode not in ["observer","native"]:
		_last_error = "Unsupported source clock mode"
		return false
	if _render_profile not in ["native","game_cannon","game_smoke"] or (_render_profile != "native" and not source.begins_with("fx_cannon_fire")):
		_last_error = "Unsupported effect display profile"
		return false
	_camera = options.get("camera")
	_water = options.get("water",Callable())
	_sea = options.get("sea",Callable())
	var direction: Vector3 = options.get("direction",Vector3.FORWARD)
	direction.y = 0.0
	if direction.is_finite() and direction.length_squared() > 0.000001: _orientation = Basis.looking_at(direction.normalized(),Vector3.UP)
	if _clock_mode == "native":
		var prepared: RefCounted = _prepared_sources.get(source)
		if prepared == null:
			prepared = script.new()
			if not prepared.configure(asset,1,false):
				_last_error = prepared.get_last_error()
				return false
			_prepared_sources[source] = prepared
		_replay = prepared.spawn_native(_seed)
		if _replay == null:
			_last_error = prepared.get_last_error()
			return false
	else:
		_replay = script.new()
		if not _replay.configure(asset,_seed): _replay = null; return false
	if _clock_mode == "native":
		# Gameplay clock adapter: preserve the existing zero birth anchor. The
		# recovered 60ms smoke/32ms splash counters and complete original clone
		# controller initial state are not integrated by this batching change.
		_replay.advance_native(0.0,false)
		_seek_age = 0.0; _seek_replay_id = _replay.get_instance_id()
		_seek_error = _replay.get_last_error()
	top_level = true
	global_transform = Transform3D.IDENTITY
	_configured = true
	return true

func set_camera(camera: Camera3D) -> void:
	if has_pending_snapshot(): finish_snapshot()
	if camera == _camera: return
	_camera = camera
	_present_key.clear()
func get_playback_duration() -> float:
	if _replay == null: return 0.0
	if _replay.has_method("get_playback_duration"): return float(_replay.call("get_playback_duration"))
	return float(_replay.diagnostics().get("max_time",0.0))
func configure_surface_filter(sea_at: Callable) -> void:
	if has_pending_snapshot(): finish_snapshot()
	_sea = sea_at
	# The same callable may now refer to changed terrain/provider state.
	_filter_revision += 1
	_present_key.clear()
static func native_to_godot(point: Array) -> Vector3: return Vector3(float(point[0]),float(point[2]),-float(point[1]))
static func godot_to_native(point: Vector3) -> Array: return [point.x,-point.z,point.y]
func _camera_native() -> Dictionary:
	var right := Vector3.RIGHT
	var up := Vector3.UP
	var direction := Vector3.BACK
	if is_instance_valid(_camera):
		right = _camera.global_basis.x; up = _camera.global_basis.y; direction = _camera.global_basis.z
	var inverse := _orientation.inverse()
	return {"right":godot_to_native(inverse*right),"up":godot_to_native(inverse*up),"direction":godot_to_native(inverse*direction)}

func _camera_key() -> Dictionary:
	return {"id":_camera.get_instance_id(),"transform":_camera.global_transform} if is_instance_valid(_camera) else {"id":0,"transform":Transform3D.IDENTITY}

func _seek_display(age: float, replay_id: int) -> void:
	if age == _seek_age and replay_id == _seek_replay_id: return
	if _clock_mode == "native": _replay.advance_native(age,false)
	else: _replay.seek(age,false)
	_seek_age = age; _seek_replay_id = replay_id
	_seek_error = String(_replay.call("get_last_error")) if _replay.has_method("get_last_error") else String(_replay.diagnostics().get("last_error",""))
	_mesh_key.clear(); _display_meshes.clear()

func _snapshot_key(age: float, absolute_time: float) -> Dictionary:
	var accepted_time := age if absolute_time < 0.0 else absolute_time
	return {"age":age,"absolute_input":absolute_time,"absolute_time":accepted_time,"camera":_camera_key(),
		"transform":global_transform,"filter_revision":_filter_revision,"water":_water,"sea":_sea,
		"origin":_origin,"orientation":_orientation,"scale":_size,"profile":_render_profile,"clock_mode":_clock_mode,"render_unit":_render_unit,"replay_id":_replay.get_instance_id()}

static func _run_native_snapshot(job: Dictionary) -> void:
	# This Callable belongs to the Script resource, not a Node. The job owns the
	# provider exclusively until main joins it; all camera input is copied data.
	var provider: RefCounted = job.provider
	if job.advance:
		provider.advance_native(float(job.age),false)
		job.error = String(provider.call("get_last_error")) if provider.has_method("get_last_error") else String(provider.diagnostics().get("last_error",""))
		# Camera/batch generation may fail after this native advance succeeded.
		# Retain only the advance result in the simulation/age cache so a valid
		# same-age camera retry can regenerate data without another native update.
		job.advance_error = job.error
	if String(job.error).is_empty() and job.needs_mesh:
		job.records = provider.batch_meshes(job.camera) if job.get("render_unit","particle") == "system" else provider.display_meshes(job.camera)
		if job.get("render_unit","particle") == "system": job.error = provider.get_last_error()
	job.complete = true

func _join_native_snapshot() -> Dictionary:
	if _worker_task < 0: return {}
	var task := _worker_task
	var error := WorkerThreadPool.wait_for_task_completion(task)
	_worker_task = -1
	_worker_joined += 1
	var job := _worker_job
	_worker_job = {}
	if error != OK or not bool(job.get("complete",false)):
		job.error = "Native effect worker did not complete its accepted frame"
	return job

func has_pending_snapshot() -> bool:
	# Only main owns this frame dictionary; checking it never reads worker output.
	return not _pending_snapshot.is_empty()

func begin_snapshot(age: float, absolute_time: float = -1.0) -> bool:
	if not _configured or _replay == null or not is_finite(age) or age < 0.0 or not is_finite(absolute_time): return false
	var key := _snapshot_key(age,absolute_time)
	if has_pending_snapshot():
		if key == _pending_snapshot.key: return true
		finish_snapshot()
	# Study and the public synchronous path retain the original virtual seams.
	if _clock_mode != "native": return _apply_snapshot_sync(age,absolute_time)
	if key == _present_key: return _present_result
	var duration := get_playback_duration()
	var replay_id := _replay.get_instance_id()
	var seek_age := minf(age,duration)
	var advance := seek_age != _seek_age or replay_id != _seek_replay_id
	var expired := age > duration
	var mesh_key := {"age":age,"camera":key.camera,"replay_id":replay_id}
	var needs_mesh := not expired and (advance or mesh_key != _mesh_key)
	_pending_snapshot = {"key":key,"age":age,"absolute_time":key.absolute_time,"seek_age":seek_age,
		"replay_id":replay_id,"advance":advance,"expired":expired,"mesh_key":mesh_key,"needs_mesh":needs_mesh}
	if advance or needs_mesh:
		_worker_job = {"provider":_replay,"age":seek_age,"camera":_camera_native().duplicate(true),
			"advance":advance,"needs_mesh":needs_mesh,"render_unit":_render_unit,"advance_error":_seek_error,"error":_seek_error,"records":[],"complete":false}
		# Resolve the base Script resource on main. No Node-bound work or callbacks
		# enter the pool; texture/material/water/sea/render stay after the join.
		var script: Script = load("res://modules/scene_engine/fidelity_fx/presentation.gd")
		_worker_task = WorkerThreadPool.add_task(Callable(script,"_run_native_snapshot").bind(_worker_job),false,"Native source frame")
		_worker_dispatched += 1
	return true

func finish_snapshot() -> bool:
	if not has_pending_snapshot(): return _present_result
	var frame := _pending_snapshot
	_pending_snapshot = {}
	var job := _join_native_snapshot()
	if frame.advance:
		_seek_age = float(frame.seek_age); _seek_replay_id = int(frame.replay_id)
		_seek_error = String(job.get("advance_error",job.get("error","")))
		_mesh_key.clear(); _display_meshes.clear()
	if frame.needs_mesh:
		_display_meshes = job.get("records",[])
		if String(job.get("error","")).is_empty(): _mesh_key = frame.mesh_key
		else: _mesh_key.clear()
	_age = float(frame.age); _absolute_time = float(frame.absolute_time)
	_expired = bool(frame.expired)
	_last_error = "Explicit source controller clip expired" if _expired else String(job.get("error",_seek_error))
	if _expired or not _last_error.is_empty():
		_render([])
		_present_key = frame.key; _present_result = false
		return false
	_render(_display_meshes)
	_present_key = frame.key; _present_result = true
	return true

func apply_snapshot(age: float, absolute_time: float = -1.0) -> bool:
	if has_pending_snapshot():
		if _configured and _replay != null and is_finite(age) and age >= 0.0 and is_finite(absolute_time) and _snapshot_key(age,absolute_time) == _pending_snapshot.key:
			return finish_snapshot()
		finish_snapshot()
	return _apply_snapshot_sync(age,absolute_time)

func _apply_snapshot_sync(age: float, absolute_time: float = -1.0) -> bool:
	# Reject before touching the retained accepted frame or any replay clock.
	if not _configured or _replay == null or not is_finite(age) or age < 0.0 or not is_finite(absolute_time): return false
	var accepted_time := age if absolute_time < 0.0 else absolute_time
	var replay_id := _replay.get_instance_id()
	var camera_key := _camera_key()
	var key := {"age":age,"absolute_input":absolute_time,"absolute_time":accepted_time,"camera":camera_key,
		"transform":global_transform,"filter_revision":_filter_revision,"water":_water,"sea":_sea,
		"origin":_origin,"orientation":_orientation,"scale":_size,"profile":_render_profile,"clock_mode":_clock_mode,"render_unit":_render_unit,"replay_id":replay_id}
	if key == _present_key: return _present_result
	_age = age; _absolute_time = accepted_time
	var duration := get_playback_duration()
	_seek_display(minf(age,duration),replay_id)
	if age > duration:
		_expired = true; _last_error = "Explicit source controller clip expired"
		_render([])
		_present_key = key; _present_result = false
		return false
	_expired = false; _last_error = _seek_error
	if not _last_error.is_empty():
		_render([])
		_present_key = key; _present_result = false
		return false
	var mesh_key := {"age":age,"camera":camera_key,"replay_id":replay_id}
	if mesh_key != _mesh_key:
		if _render_unit == "system":
			_display_meshes = _replay.batch_meshes(_camera_native())
			_last_error = _replay.get_last_error()
		else: _display_meshes = _replay.display_meshes(_camera_native()) if _clock_mode == "native" else _replay.meshes(_camera_native())
		if _last_error.is_empty(): _mesh_key = mesh_key
		else: _mesh_key.clear()
		if not _last_error.is_empty():
			_render([])
			_present_key = key; _present_result = false
			return false
	# Absolute water time/filter or parent transform can require new placement
	# without advancing particles or regenerating camera-independent native data.
	_render(_display_meshes)
	_present_key = key; _present_result = true
	return true

func _material(mesh: Dictionary) -> ShaderMaterial:
	var flags := int(mesh.get("alphaFlags",0))
	var source := (flags >> 1) & 15
	var destination := (flags >> 5) & 15
	if (flags & 1) != 0 and (source != 6 or destination not in [0,7]): return null
	var clamp_mode := int(mesh.get("clampMode",0))
	var filter_mode := int(mesh.get("filterMode",0))
	# Completed current source descriptors are CC/WW/WC + trilinear. Never silently
	# substitute wrap or regenerate mips for an unverified sampler variant.
	if clamp_mode not in [0,1,2,3] or filter_mode != 2:
		_last_error = "Unsupported original effect sampler %d/%d" % [clamp_mode,filter_mode]
		return null
	var role := String(mesh.get("display_role","native"))
	var spark := _render_profile == "game_cannon" and String(mesh.get("name","")) == "SSpray INITIAL"
	var key := "%s:%d:%d:%d:%d:%s:%s" % [mesh.texture,flags,int(mesh.get("threshold",0)),clamp_mode,filter_mode,_render_profile,role]
	var material: ShaderMaterial = _materials.get(key)
	if material != null:
		if role == "game_flash": material.set_shader_parameter("display_tint",mesh.display_tint)
		return material
	var texture := _texture(String(mesh.texture))
	if texture == null: return null
	material = ShaderMaterial.new()
	# Additional fire is explicitly the game's display profile. Native source
	# blend flags, particle colour, controller keys and random stream stay intact.
	material.shader = AddShader if role == "game_flash" or spark or ((flags & 1) != 0 and destination == 0) else MixShader
	material.set_shader_parameter("source_texture",texture)
	material.set_shader_parameter("source_texture_repeat",texture)
	material.set_shader_parameter("source_repeat",clamp_mode == 3)
	material.set_shader_parameter("source_clamp_mode",clamp_mode)
	material.set_shader_parameter("source_mip_count",texture.get_image().get_mipmap_count()+1)
	material.set_shader_parameter("display_tint",Color.WHITE)
	material.set_shader_parameter("emission_gain",0.0)
	material.set_shader_parameter("soft_depth_distance",0.0)
	if role == "game_flash":
		material.set_shader_parameter("display_tint",mesh.display_tint)
		material.set_shader_parameter("emission_gain",1.6)
	elif spark:
		material.set_shader_parameter("display_tint",Color(1.0,.76,.24,.80))
		material.set_shader_parameter("emission_gain",0.15)
	elif _render_profile != "native":
		material.set_shader_parameter("display_tint",Color(.66,.65,.61,.58))
		material.set_shader_parameter("soft_depth_distance",.40*_size)
	material.set_shader_parameter("alpha_threshold",float(mesh.get("threshold",0))/255.0 if (flags & 512) != 0 else -1.0)
	material.render_priority = 4
	_materials[key] = material
	return material

func _surface_layout(mesh: ArrayMesh, indices: PackedInt32Array) -> Dictionary:
	var count := mesh.surface_get_array_len(0)
	var format := int(mesh.surface_get_format(0))
	var layout := {"mesh_id":mesh.get_instance_id(),"vertex_count":count,"indices":indices.duplicate(),
		"vertex_stride":RenderingServer.mesh_surface_get_format_vertex_stride(format,count),
		"attribute_stride":RenderingServer.mesh_surface_get_format_attribute_stride(format,count),
		"color_offset":RenderingServer.mesh_surface_get_format_offset(format,count,Mesh.ARRAY_COLOR),
		"uv_offset":RenderingServer.mesh_surface_get_format_offset(format,count,Mesh.ARRAY_TEX_UV)}
	var arrays_mask := (1 << Mesh.ARRAY_MAX)-1
	var expected := Mesh.ARRAY_FORMAT_VERTEX|Mesh.ARRAY_FORMAT_COLOR|Mesh.ARRAY_FORMAT_TEX_UV|Mesh.ARRAY_FORMAT_INDEX
	layout.supported = ((format & arrays_mask) == expected
		and (format & (Mesh.ARRAY_FLAG_USE_2D_VERTICES|Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)) == 0
		and layout.vertex_stride == 12 and layout.attribute_stride == 12 and layout.color_offset == 0 and layout.uv_offset == 4)
	return layout

static func _local_bounds(vertices: PackedVector3Array) -> AABB:
	var low := vertices[0]
	var high := low
	for vertex: Vector3 in vertices:
		low = low.min(vertex); high = high.max(vertex)
	# Match RenderingServer's minimum extent, including planar/degenerate quads.
	return AABB(low,(high-low).max(Vector3(0.00001,0.00001,0.00001)))

static func _surface_attributes(uv: PackedVector2Array, colors: PackedColorArray) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(uv.size()*12)
	for index in uv.size():
		var offset := index*12
		var color: Color = colors[index]
		# Match the original ArrayMesh writer: float Color fields, double *255,
		# clamp, then truncation. Keep UV float32, not half or compressed UNORM.
		data[offset] = int(clampf(color.r*255.0,0.0,255.0))
		data[offset+1] = int(clampf(color.g*255.0,0.0,255.0))
		data[offset+2] = int(clampf(color.b*255.0,0.0,255.0))
		data[offset+3] = int(clampf(color.a*255.0,0.0,255.0))
		data.encode_float(offset+4,uv[index].x)
		data.encode_float(offset+8,uv[index].y)
	return data

func _update_surface(key: String, arrays: Array, original_attributes: PackedByteArray = PackedByteArray()) -> void:
	var node: MeshInstance3D = _geometry[key]
	var mesh := node.mesh as ArrayMesh
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var layout: Dictionary = _surface_layouts.get(key,{})
	var reuse: bool = (_region_updates and mesh != null and not layout.is_empty() and bool(layout.supported)
		and int(layout.mesh_id) == mesh.get_instance_id() and int(layout.vertex_count) == vertices.size()
		and uv.size() == vertices.size() and colors.size() == vertices.size() and layout.indices == indices)
	if reuse:
		mesh.surface_update_vertex_region(0,0,vertices.to_byte_array())
		mesh.surface_update_attribute_region(0,0,original_attributes if not original_attributes.is_empty() else _surface_attributes(uv,colors))
		# Region writes retain the initial resource AABB. The renderer must use
		# this frame's exact local bounds for culling and transparent depth.
		var bounds := _local_bounds(vertices)
		if mesh.custom_aabb != bounds: mesh.custom_aabb = bounds
	else:
		mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
		node.mesh = mesh
		_surface_layouts[key] = _surface_layout(mesh,indices)
		if _region_updates and not original_attributes.is_empty() and bool(_surface_layouts[key].supported):
			mesh.surface_update_attribute_region(0,0,original_attributes)

func _render(meshes: Array) -> void:
	if _render_unit == "system":
		_render_systems(meshes)
		return
	_rendered = 0; _triangles = 0
	_game_flash = 0; _draw_order.clear()
	var used: Dictionary = {}
	# Ground classification is read-only during this synchronous render. Reuse
	# exact world XZ results across triangles/records, never across snapshots.
	var sea_points: Dictionary = {}
	var ordered: Array = []
	var records := meshes.duplicate()
	if not _expired and _render_profile == "game_cannon": records.append_array(_game_flash_meshes())
	var camera_origin := _camera.global_position if is_instance_valid(_camera) else Vector3.ZERO
	var camera_forward := -_camera.global_basis.z if is_instance_valid(_camera) else Vector3.FORWARD
	for record: Dictionary in records:
		var points: Array = []
		var center := Vector3.ZERO
		var surface_ring: bool = _source.begins_with("cannon_ball") and record.get("kind","") == "authored mesh" and not String(record.get("name","")).begins_with("Cylinder")
		for value: Array in record.vertices:
			var point := _origin+_orientation*native_to_godot(value)*(METRES_PER_UNIT*_size)
			if surface_ring and _water.is_valid():
				var height := float(_water.call(point.x,point.z,_absolute_time))
				if is_finite(height): point.y = height+0.06
			points.append(point); center += point
		if points.is_empty(): continue
		center /= points.size()
		ordered.append({"record":record,"points":points,"center":center,"depth":(center-camera_origin).dot(camera_forward)})
	ordered.sort_custom(func(a,b): return a.depth > b.depth)
	for draw: Dictionary in ordered:
		var record: Dictionary = draw.record
		var material := _material(record)
		if material == null: continue
		var vertices := PackedVector3Array(); var uv := PackedVector2Array()
		var colors := PackedColorArray(); var indices := PackedInt32Array()
		var rgb: Array = record.get("color",[1.0,1.0,1.0])
		var alpha := float(record.get("alpha",1.0))
		var color := Color(float(rgb[0]),float(rgb[1]),float(rgb[2]),alpha)
		var points: Array = draw.points
		for index in points.size():
			vertices.append(points[index]-draw.center)
			uv.append(Vector2(float(record.uvs[index][0]),float(record.uvs[index][1])))
			colors.append(color)
		for triangle: Array in record.triangles:
			var wet := true
			if _source.begins_with("cannon_ball") and _sea.is_valid():
				for index in triangle:
					var point: Vector3 = points[int(index)]
					var xz := Vector2(point.x,point.z)
					if not sea_points.has(xz): sea_points[xz] = bool(_sea.call(point.x,point.z))
					if not sea_points[xz]: wet = false
			if not wet: continue
			indices.append_array(PackedInt32Array([int(triangle[0]),int(triangle[1]),int(triangle[2])]))
			_triangles += 1
		if indices.is_empty(): continue
		var role := String(record.get("display_role","native"))
		if role == "game_flash": _game_flash += 1
		else: _rendered += 1
		var key := str(_draw_order.size())
		if not _geometry.has(key):
			var node := MeshInstance3D.new(); node.name = "SourceDraw_"+str(_geometry.size())
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(node); _geometry[key] = node
		var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_TEX_UV]=uv
		arrays[Mesh.ARRAY_COLOR]=colors; arrays[Mesh.ARRAY_INDEX]=indices
		_update_surface(key,arrays)
		_geometry[key].position = draw.center
		if _geometry[key].material_override != material: _geometry[key].material_override = material
		if not _geometry[key].visible: _geometry[key].visible = true
		used[key] = true
		_geometry[key].set_meta("display_role",role)
		_draw_order.append({"name":record.get("name",""),"texture":record.texture,"depth":draw.depth,"display_role":role})
	for key in _geometry:
		if not used.has(key) and _geometry[key].visible: _geometry[key].visible = false

func _system_point(local: Vector3, world: Dictionary) -> Vector3:
	# Apply system.world once, retaining the native stores used by Math.point.
	# The GPU receives carrier-relative Godot positions. This is the Godot
	# placement adapter; vertex_bytes remains the original system-local stream.
	var m: Array = world.rotation; var t: Array = world.translation
	var v := Vector3(m[0]*local.x+m[1]*local.y+m[2]*local.z,m[3]*local.x+m[4]*local.y+m[5]*local.z,m[6]*local.x+m[7]*local.y+m[8]*local.z)
	var scaled := Vector2(world.scale*v.x,world.scale*v.y)
	var native := Vector3(scaled.x+t[0],scaled.y+t[1],world.scale*v.z+t[2])
	return _origin+_orientation*Vector3(native.x,native.z,-native.y)*(METRES_PER_UNIT*_size)

func _render_systems(meshes: Array) -> void:
	_rendered = 0; _triangles = 0; _game_flash = 0; _draw_order.clear()
	var used: Dictionary = {}; var sea_points: Dictionary = {}
	var records := meshes.duplicate()
	if not _expired and _render_profile == "game_cannon": records.append_array(_game_flash_meshes())
	var draws: Array = []; var ids := PackedInt32Array(); var depths := PackedFloat32Array()
	var forward := -_camera.global_basis.z if is_instance_valid(_camera) else Vector3.FORWARD
	var adapter_index := 0
	for record: Dictionary in records:
		var system: bool = record.get("kind","") == "particle system"
		# Adapter identity follows its source record order, independently of the
		# active native-system count and before any geometry/sea filtering.
		var key := "system:"+str(record.block) if system else "authored:"+str(record.block) if record.has("block") else "adapter:"+str(adapter_index)
		if not record.has("block"): adapter_index += 1
		var points := PackedVector3Array()
		var uv := PackedVector2Array(); var colors := PackedColorArray(); var source_indices := PackedInt32Array()
		var attributes := PackedByteArray(); var center := Vector3.ZERO
		if system:
			var batch: RefCounted = record.batch
			var count := int(batch.vertex_count)
			if count == 0: continue
			points.resize(count)
			for index in count: points[index] = _system_point(batch.vertices[index],record.world)
			uv = batch.uvs.slice(0,count); colors = batch.colors.slice(0,count)
			source_indices = batch.indices.slice(0,int(batch.index_count))
			attributes = batch.attribute_bytes.slice(0,count*12)
		else:
			var source_points: Array = record.vertices
			points.resize(source_points.size()); uv.resize(source_points.size()); colors.resize(source_points.size())
			var rgb: Array = record.get("color",[1.0,1.0,1.0])
			var color := Color(float(rgb[0]),float(rgb[1]),float(rgb[2]),float(record.get("alpha",1.0)))
			var ring: bool = _source.begins_with("cannon_ball") and record.get("kind","") == "authored mesh" and not String(record.get("name","")).begins_with("Cylinder")
			for index in source_points.size():
				var point := _origin+_orientation*native_to_godot(source_points[index])*(METRES_PER_UNIT*_size)
				if ring and _water.is_valid():
					var height := float(_water.call(point.x,point.z,_absolute_time))
					if is_finite(height): point.y = height+0.06
				points[index] = point
				uv[index] = Vector2(float(record.uvs[index][0]),float(record.uvs[index][1])); colors[index] = color
			for triangle: Array in record.triangles:
				source_indices.append(int(triangle[0])); source_indices.append(int(triangle[1])); source_indices.append(int(triangle[2]))
		if points.is_empty(): continue
		if record.has("bounds"):
			var native_center: Array = NativeMath.point(record.world,record.bounds.center)
			center = _origin+_orientation*native_to_godot(native_center)*(METRES_PER_UNIT*_size)
		else:
			# Explicit game muzzle adapter has no recovered native geometry bound.
			for point: Vector3 in points: center += point
			center /= points.size()
		var indices := PackedInt32Array()
		if _source.begins_with("cannon_ball") and _sea.is_valid():
			for offset in range(0,source_indices.size(),3):
				var wet := true
				for corner in 3:
					var point: Vector3 = points[source_indices[offset+corner]]; var xz := Vector2(point.x,point.z)
					if not sea_points.has(xz): sea_points[xz] = bool(_sea.call(point.x,point.z))
					if not sea_points[xz]: wet = false
				if wet:
					indices.append(source_indices[offset]); indices.append(source_indices[offset+1]); indices.append(source_indices[offset+2])
		else: indices = source_indices
		if indices.is_empty(): continue
		for index in points.size(): points[index] -= center
		var depth := NativeMath.f32(center.z*forward.z+center.y*forward.y+center.x*forward.x)
		ids.append(draws.size()); depths.append(depth)
		draws.append({"record":record,"key":key,"vertices":points,"uv":uv,"colors":colors,"indices":indices,"attributes":attributes,"center":center,"depth":depth})
	# 5538F0/553A60 equal-key swaps, then original reverse submission. Godot's
	# renderer orders geometry globally using the native bound center origin;
	# CPU list equality does not claim original driver/pixel/tie-order equality.
	CpuBatch.sort_transparent(ids,depths,ids.size())
	for index in range(ids.size()-1,-1,-1):
		var draw: Dictionary = draws[ids[index]]; var record: Dictionary = draw.record
		var material := _material(record)
		if material == null: continue
		var key: String = draw.key; var kind := String(record.get("kind","game adapter"))
		if not _geometry.has(key):
			var node := MeshInstance3D.new(); node.name = "SourceSystem_"+str(_geometry.size())
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.sorting_use_aabb_center = false
			add_child(node); _geometry[key] = node
		var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = draw.vertices; arrays[Mesh.ARRAY_TEX_UV] = draw.uv
		arrays[Mesh.ARRAY_COLOR] = draw.colors; arrays[Mesh.ARRAY_INDEX] = draw.indices
		_update_surface(key,arrays,draw.attributes)
		var node: MeshInstance3D = _geometry[key]
		node.position = draw.center; node.custom_aabb = _local_bounds(draw.vertices)
		if node.material_override != material: node.material_override = material
		if not node.visible: node.visible = true
		node.set_meta("display_role",record.get("display_role","native"))
		node.set_meta("source_block",int(record.get("block",-1))); node.set_meta("source_kind",kind)
		used[key] = true
		_triangles += int(draw.indices.size()/3.0)
		if record.get("display_role","native") == "game_flash": _game_flash += 1
		else: _rendered += 1
		_draw_order.append({"name":record.get("name",""),"texture":record.texture,"depth":draw.depth,"display_role":record.get("display_role","native"),"block":record.get("block",-1),"kind":kind})
	for key: Variant in _geometry:
		if not used.has(key) and _geometry[key].visible: _geometry[key].visible = false

func _game_flash_meshes() -> Array:
	# This small axial streak is a game muzzle-light adapter using original DDS.
	# It is NOT claimed as a recovered extra native emitter or original fire mesh.
	if _age < 0.0 or _age >= GAME_FLASH_DURATION: return []
	var fraction := _age/GAME_FLASH_DURATION
	# Keep the short flash readable through its middle phase; it still expires at .14s.
	var opacity := 1.0-fraction
	var tint := Color(1.0,.82,.22,opacity).lerp(Color(1.0,.35,.035,opacity),smoothstep(.018,.09,_age))
	var forward := Vector3.FORWARD
	var side := Vector3.RIGHT
	if is_instance_valid(_camera):
		side = _orientation.inverse()*_camera.global_basis.x
		side -= forward*side.dot(forward)
		if side.length_squared() < .000001: side = Vector3.UP
		side = side.normalized()
	var up := forward.cross(side).normalized()
	var native_scale := METRES_PER_UNIT*_size
	var length := (1.55+.035*(_seed%11))*(1.0-fraction*.35)*_size
	var width := (.48+.009*(_seed%7))*(1.0-fraction*.15)*_size
	var out := []
	for axis in [side,up]:
		var start := forward*.04*_size; var end := forward*length
		var points := [start-axis*width,end-axis*width*.22,end+axis*width*.22,start+axis*width]
		var values: Array = []
		for point: Vector3 in points: values.append(godot_to_native(point/native_scale))
		out.append({"name":"Game muzzle streak","display_role":"game_flash","display_tint":tint,"texture":"fx_streakin_001.dds","vertices":values,"uvs":[[0.0,0.0],[1.0,0.0],[1.0,1.0],[0.0,1.0]],"triangles":[[0,1,2],[0,2,3]],"color":[1.0,1.0,1.0],"alpha":1.0,"alphaFlags":4621,"threshold":0,"clampMode":0,"filterMode":2})
	return out

func diagnostics() -> Dictionary:
	if has_pending_snapshot(): finish_snapshot()
	var state: Dictionary = _replay.diagnostics() if _replay != null else {}
	state["worker"] = {"dispatched":_worker_dispatched,"joined":_worker_joined,"pending":int(_worker_task >= 0)}
	state.merge({"configured":_configured,"source":_source,"age":_age,"accepted_time":_absolute_time,"rendered_meshes":_rendered,"rendered_triangles":_triangles,"origin":_origin,"orientation":_orientation,"seed":_seed,"owned_nodes":_geometry.size(),"mesh_resource_reuse":_region_updates,"mesh_update_scope":"stable layout/index region writes with exact per-instance bounds" if _region_updates else "headless dummy region writes are no-ops; rebuild actual ArrayMesh arrays","render_profile":_render_profile,"clock_mode":_clock_mode,"game_flash":_game_flash,"game_flash_duration":GAME_FLASH_DURATION,"playback_duration":get_playback_duration(),"expired":_expired,"render_error":_last_error,"draw_order":_draw_order.duplicate(true),"sort_scope":"one quad/mesh per spatial instance; local far-to-near list; engine transparent sorting across effects, GPU order unverified","scope":"native replay/packed RGBA/UV/mips unchanged; .01 metres/unit and water-ring adapter; game profiles add warm muzzle streak or grey soft smoke"},true)
	state.render_unit = _render_unit
	state.time_adapter_scope = "Gameplay appTime seconds and zero birth anchor retained; original 60ms smoke/32ms splash counters and full clone/controller initial state not integrated"
	if _render_unit == "system":
		state.sort_scope = "one packed particle-system geometry plus separate authored meshes; original CPU quicksort/equal-depth swaps; engine geometry sorting uses native world-bound center; global GPU tie/order/pixels unverified"
		state.mesh_update_scope = "actual 4N vertices/6N indices per active system; stable topology reuses native ArrayMesh regions, changed active count rebuilds; headless dummy rebuilds readable arrays"
	return state

func dispose() -> void:
	# Retire the task before releasing its provider. Destruction never renders an
	# old payload or touches camera/water owners that may already be leaving.
	_join_native_snapshot()
	_pending_snapshot.clear()
	for node: Node in _geometry.values():
		if is_instance_valid(node): node.free()
	_geometry.clear(); _surface_layouts.clear(); _materials.clear(); _replay = null; _camera = null
	_water = Callable(); _sea = Callable(); _configured = false
	_origin = Vector3.ZERO; _orientation = Basis.IDENTITY; _age = -1.0; _rendered = 0; _triangles = 0
	_absolute_time = -1.0; _render_profile = "native"; _clock_mode = "observer"; _render_unit = "particle"; _expired = false; _last_error = ""
	_draw_order.clear(); _game_flash = 0
	_present_key.clear(); _present_result = false
	_mesh_key.clear(); _display_meshes.clear()
	_seek_age = NAN; _seek_replay_id = 0; _seek_error = ""; _filter_revision = 0
func _exit_tree() -> void: dispose()
