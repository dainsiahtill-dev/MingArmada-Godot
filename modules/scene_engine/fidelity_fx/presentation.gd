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
	_replay.seek(age)
	var meshes: Array = _replay.meshes(_camera_native())
	_render(meshes)
	return true

func _material(mesh: Dictionary) -> ShaderMaterial:
	var flags := int(mesh.get("alphaFlags",0))
	var source := (flags >> 1) & 15
	var destination := (flags >> 5) & 15
	if (flags & 1) != 0 and (source != 6 or destination not in [0,7]): return null
	var key := "%s:%d:%d:%d:%d" % [mesh.texture,flags,int(mesh.get("threshold",0)),int(mesh.get("clampMode",0)),int(mesh.get("filterMode",0))]
	if _materials.has(key): return _materials[key]
	var texture := _texture(String(mesh.texture))
	if texture == null: return null
	var material := ShaderMaterial.new()
	material.shader = AddShader if (flags & 1) != 0 and destination == 0 else MixShader
	material.set_shader_parameter("source_texture",texture)
	material.set_shader_parameter("alpha_threshold",float(mesh.get("threshold",0))/255.0 if (flags & 512) != 0 else -1.0)
	material.render_priority = 4
	_materials[key] = material
	return material

func _render(meshes: Array) -> void:
	_rendered = 0; _triangles = 0
	var groups: Dictionary = {}
	for record: Dictionary in meshes:
		var material := _material(record)
		if material == null: continue
		var key := str(material.get_instance_id())
		if not groups.has(key): groups[key] = {"material":material,"vertices":PackedVector3Array(),"uv":PackedVector2Array(),"colors":PackedColorArray(),"indices":PackedInt32Array()}
		var group: Dictionary = groups[key]
		var offset: int = group.vertices.size()
		var rgb: Array = record.get("color",[1.0,1.0,1.0])
		var alpha := float(record.get("alpha",1.0))
		var color := Color(float(rgb[0]),float(rgb[1]),float(rgb[2]),alpha)
		var points: Array = []
		var surface_ring: bool = _source.begins_with("cannon_ball") and record.get("kind","") == "authored mesh" and not String(record.get("name","")).begins_with("Cylinder")
		for value: Array in record.vertices:
			var point := _origin+_orientation*native_to_godot(value)*(METRES_PER_UNIT*_size)
			if surface_ring and _water.is_valid():
				var height := float(_water.call(point.x,point.z,_absolute_time))
				if is_finite(height): point.y = height+0.06
			points.append(point)
		for index in points.size():
			group.vertices.append(points[index])
			group.uv.append(Vector2(float(record.uvs[index][0]),float(record.uvs[index][1])))
			group.colors.append(color)
		for triangle: Array in record.triangles:
			var wet := true
			if _source.begins_with("cannon_ball") and _sea.is_valid():
				for index in triangle:
					var point: Vector3 = points[int(index)]
					if not bool(_sea.call(point.x,point.z)): wet = false
			if not wet: continue
			group.indices.append_array(PackedInt32Array([offset+int(triangle[0]),offset+int(triangle[1]),offset+int(triangle[2])]))
			_triangles += 1
		_rendered += 1
	for key in _geometry: _geometry[key].visible = false
	for key in groups:
		var group: Dictionary = groups[key]
		if group.indices.is_empty(): continue
		if not _geometry.has(key):
			var node := MeshInstance3D.new(); node.name = "SourceBatch_"+str(_geometry.size())
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(node); _geometry[key] = node
		var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=group.vertices; arrays[Mesh.ARRAY_TEX_UV]=group.uv
		arrays[Mesh.ARRAY_COLOR]=group.colors; arrays[Mesh.ARRAY_INDEX]=group.indices
		var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		_geometry[key].mesh = mesh; _geometry[key].material_override = group.material; _geometry[key].visible = true

func diagnostics() -> Dictionary:
	var state: Dictionary = _replay.diagnostics() if _replay != null else {}
	state.merge({"configured":_configured,"source":_source,"age":_age,"accepted_time":_absolute_time,"rendered_meshes":_rendered,"rendered_triangles":_triangles,"origin":_origin,"orientation":_orientation,"seed":_seed,"owned_nodes":_geometry.size(),"scope":"completed native replay with target event orientation, .01 metres/unit and wave-conforming water rings"},true)
	return state

func dispose() -> void:
	for node: Node in _geometry.values():
		if is_instance_valid(node): node.free()
	_geometry.clear(); _materials.clear(); _replay = null; _camera = null
	_water = Callable(); _sea = Callable(); _configured = false
	_origin = Vector3.ZERO; _orientation = Basis.IDENTITY; _age = -1.0; _rendered = 0; _triangles = 0
func _exit_tree() -> void: dispose()
