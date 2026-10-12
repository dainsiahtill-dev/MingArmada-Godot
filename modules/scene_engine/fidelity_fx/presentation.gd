extends Node3D
## Render completed source replay in the game. Runtime stays in native units;
## event placement, metre scale and wave-conforming rings are explicit adapters.
const MANIFEST := "res://assets/data/fidelity_fx/manifest.json"
const RUNTIME := "res://modules/scene_engine/fidelity_fx/particle_runtime.gd"
const MixShader = preload("res://modules/scene_engine/fidelity_fx/particle.gdshader")
const AddShader = preload("res://modules/scene_engine/fidelity_fx/particle_add.gdshader")
const METRES_PER_UNIT := 0.01
static var _manifest: Dictionary = {}
static var _assets: Dictionary = {}
static var _textures: Dictionary = {}
var _replay: RefCounted
var _geometry: Dictionary = {}
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
var _expired := false
var _last_error := ""
var _draw_order: Array = []
var _game_flash := 0
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
	if _render_profile not in ["native","game_cannon","game_smoke"] or (_render_profile != "native" and not source.begins_with("fx_cannon_fire")):
		_last_error = "Unsupported effect display profile"
		return false
	_camera = options.get("camera")
	_water = options.get("water",Callable())
	_sea = options.get("sea",Callable())
	var direction: Vector3 = options.get("direction",Vector3.FORWARD)
	direction.y = 0.0
	if direction.is_finite() and direction.length_squared() > 0.000001: _orientation = Basis.looking_at(direction.normalized(),Vector3.UP)
	_replay = script.new()
	if not _replay.configure(asset,_seed): _replay = null; return false
	top_level = true
	global_transform = Transform3D.IDENTITY
	_configured = true
	return true

func set_camera(camera: Camera3D) -> void: _camera = camera
func get_playback_duration() -> float:
	return float(_replay.diagnostics().get("max_time",0.0)) if _replay != null else 0.0
func configure_surface_filter(sea_at: Callable) -> void: _sea = sea_at
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

func apply_snapshot(age: float, absolute_time: float = -1.0) -> bool:
	if not _configured or not is_finite(age) or age < 0.0: return false
	_age = age
	_absolute_time = age if absolute_time < 0.0 else absolute_time
	if not is_finite(_absolute_time): return false
	if age > get_playback_duration():
		_replay.seek(get_playback_duration())
		_render([])
		_expired = true
		_last_error = "Explicit source controller clip expired"
		return false
	_expired = false
	_replay.seek(age)
	_last_error = String(_replay.diagnostics().get("last_error",""))
	if not _last_error.is_empty(): _render([]); return false
	var meshes: Array = _replay.meshes(_camera_native())
	_render(meshes)
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

func _render(meshes: Array) -> void:
	_rendered = 0; _triangles = 0
	_game_flash = 0; _draw_order.clear()
	for key in _geometry: _geometry[key].visible = false
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
					if not bool(_sea.call(point.x,point.z)): wet = false
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
		var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		_geometry[key].position = draw.center
		_geometry[key].mesh = mesh; _geometry[key].material_override = material; _geometry[key].visible = true
		_geometry[key].set_meta("display_role",role)
		_draw_order.append({"name":record.get("name",""),"texture":record.texture,"depth":draw.depth,"display_role":role})

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
	var state: Dictionary = _replay.diagnostics() if _replay != null else {}
	state.merge({"configured":_configured,"source":_source,"age":_age,"accepted_time":_absolute_time,"rendered_meshes":_rendered,"rendered_triangles":_triangles,"origin":_origin,"orientation":_orientation,"seed":_seed,"owned_nodes":_geometry.size(),"render_profile":_render_profile,"game_flash":_game_flash,"game_flash_duration":GAME_FLASH_DURATION,"playback_duration":get_playback_duration(),"expired":_expired,"render_error":_last_error,"draw_order":_draw_order.duplicate(true),"sort_scope":"one quad/mesh per spatial instance; local far-to-near list; engine transparent sorting across effects, GPU order unverified","scope":"native replay/packed RGBA/UV/mips unchanged; .01 metres/unit and water-ring adapter; game profiles add warm muzzle streak or grey soft smoke"},true)
	return state

func dispose() -> void:
	for node: Node in _geometry.values():
		if is_instance_valid(node): node.free()
	_geometry.clear(); _materials.clear(); _replay = null; _camera = null
	_water = Callable(); _sea = Callable(); _configured = false
	_origin = Vector3.ZERO; _orientation = Basis.IDENTITY; _age = -1.0; _rendered = 0; _triangles = 0
	_absolute_time = -1.0; _render_profile = "native"; _expired = false; _last_error = ""
	_draw_order.clear(); _game_flash = 0
func _exit_tree() -> void: dispose()
