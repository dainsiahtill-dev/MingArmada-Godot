extends Node3D
## Generic world composition. Receives plain geography and read-only samplers.

const TerrainChunk = preload("res://modules/scene_engine/terrain/terrain_chunk.gd")
const ProjectedOcean = preload("res://modules/scene_engine/ocean/projected_ocean.gd")
const VegetationLibrary = preload("res://modules/scene_engine/assets/vegetation_library.gd")
const Descriptor = preload("res://modules/contracts/wave_descriptor.gd")
const PIER_DECK_HEIGHT := 4.2 # Above the authored offshore 3.5m wave envelope.
var _height_sampler: Callable
var _camera: Camera3D
var _ocean: MeshInstance3D
var _ports: Array = []
var _chunks: Dictionary = {}
var _owned: Array[Node] = []
var _vegetation_library: RefCounted
var _chunk_size := 250.0
var _resolution := 32
var _radius := 2
var _vegetation := true
var _collision := true
var _builds := 0
var _disposed := true
var _simulation_time := 0.0
var _shore_field: RefCounted
var _shore_spray: Node3D
var _visual_style := 1

func configure(height_sampler: Callable, wave_descriptors: Array = [], options: Dictionary = {}) -> bool:
	dispose()
	if not height_sampler.is_valid():
		return false
	_disposed = false
	_height_sampler = height_sampler
	_camera = options.get("camera")
	_ports = options.get("ports", []).duplicate(true)
	_chunk_size = clampf(float(options.get("chunk_size", 250.0)), 25.0, 1000.0)
	_resolution = clampi(int(options.get("resolution", 32)), 4, 128)
	_radius = clampi(int(options.get("chunk_radius", 2)), 0, 4)
	_vegetation = bool(options.get("vegetation", true))
	_collision = bool(options.get("collision", true))
	_visual_style = int(options.get("visual_style", 1))
	_vegetation_library = VegetationLibrary.new()
	_ocean = ProjectedOcean.new()
	_ocean.name = "Ocean"
	add_child(_ocean)
	_owned.append(_ocean)
	var texture: Texture2D = options.get("normal_texture")
	if texture == null and ResourceLoader.exists("res://assets/textures/waternormals.jpg"):
		texture = load("res://assets/textures/waternormals.jpg") as Texture2D
	_ocean.configure(_camera, texture, int(options.get("ocean_resolution", 80)), float(options.get("ocean_distance", 3000.0)))
	var effective_waves: Array = Descriptor.original_descriptors() if wave_descriptors.is_empty() else wave_descriptors.duplicate(true)
	if not _ocean.set_wave_descriptors(effective_waves):
		dispose()
		return false
	if _ocean.has_method("set_visual_style"):
		_ocean.set_visual_style(int(options.get("visual_style", 1)))
	if _visual_style == 1: _ocean.set_projection_padding(0.10)
	_configure_shore(effective_waves)
	_build_ports()
	_update_window(Vector2.ZERO)
	return true

func _configure_shore(wave_descriptors: Array = []) -> void:
	var path := "res://modules/scene_engine/ocean/shore_field.gd"
	if _visual_style == 0 or _ports.is_empty() or not FileAccess.file_exists(path) or not _ocean.has_method("set_shore_field"):
		return
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for port: Dictionary in _ports:
		var center := Vector2(float(port.islandX), float(port.islandZ))
		var reach := Vector2(float(port.radius), float(port.radius) * 0.82) + Vector2.ONE * 100.0
		minimum = minimum.min(center - reach)
		maximum = maximum.max(center + reach)
	var shore_script = load(path)
	_shore_field = shore_script.new()
	if _shore_field.configure(_height_sampler, Rect2(minimum, maximum - minimum), 512):
		_ocean.set_shore_field(_shore_field.get_texture(), _shore_field.get_bounds(), _shore_field.get_coast_texture())
	var spray_path := "res://modules/scene_engine/ocean/shore_spray.gd"
	if FileAccess.file_exists(spray_path):
		var spray_script = load(spray_path)
		_shore_spray = spray_script.new()
		if _shore_spray.configure(_height_sampler, Rect2(minimum, maximum - minimum), 160):
			if not wave_descriptors.is_empty(): _shore_spray.set_wave_descriptors(wave_descriptors)
			if _shore_field: _shore_spray.set_shore_field(_shore_field.get_texture(), _shore_field.get_bounds())
			add_child(_shore_spray)
			_owned.append(_shore_spray)
		else:
			_shore_spray.free()
			_shore_spray = null

func apply_snapshot(snapshot: Dictionary, consumed: float = 0.0) -> void:
	if _disposed:
		return
	# Runtime time is authoritative, including pause and rewind. No wall clock.
	var seconds := float(snapshot.get("time", _simulation_time))
	if is_finite(seconds):
		_simulation_time = seconds
		_ocean.set_simulation_time(seconds)
		if is_instance_valid(_shore_spray):
			_shore_spray.set_simulation_time(seconds)
	var focus := Vector2.ZERO
	if snapshot.has("focus"):
		var point = snapshot.focus
		if point is Vector2:
			focus = point
		elif point is Dictionary:
			focus = Vector2(float(point.get("x", 0.0)), float(point.get("z", 0.0)))
	elif is_instance_valid(_camera):
		focus = Vector2(_camera.global_position.x, _camera.global_position.z)
	if is_finite(focus.x) and is_finite(focus.y):
		_update_window(focus)
	_ocean.update_projection()
	# consumed is accepted for shared presentation API; this world does not bill it.
	if consumed < 0.0:
		return

func _update_window(focus: Vector2) -> void:
	var center := Vector2i(floori(focus.x / _chunk_size), floori(focus.y / _chunk_size))
	var active: Dictionary = {}
	for row in range(center.y - _radius, center.y + _radius + 1):
		for column in range(center.x - _radius, center.x + _radius + 1):
			var key := Vector2i(column, row)
			active[key] = true
	for key in _chunks.keys():
		if not active.has(key):
			var chunk: Node = _chunks[key]
			_owned.erase(chunk)
			chunk.free()
			_chunks.erase(key)
	for coordinate: Vector2i in active:
		if _chunks.has(coordinate):
			continue
		var chunk := TerrainChunk.new()
		if not chunk.configure(_height_sampler, coordinate, _chunk_size, _resolution, _collision):
			chunk.free()
			continue
		chunk.name = "Terrain_%d_%d" % [coordinate.x, coordinate.y]
		add_child(chunk)
		_owned.append(chunk)
		_chunks[coordinate] = chunk
		_builds += 1
		if _vegetation:
			_vegetation_library.populate(chunk, _height_sampler, coordinate, _chunk_size, _resolution, _ports)

func _build_ports() -> void:
	var root := Node3D.new()
	root.name = "Ports"
	add_child(root)
	_owned.append(root)
	var wood := _material("785033")
	var walls := _material("ddd7c5")
	var roof := _material("a6573e")
	for port: Dictionary in _ports:
		var group := Node3D.new()
		group.name = String(port.get("id", "Port"))
		group.position = Vector3(float(port.x), 0.0, float(port.z))
		group.rotation.y = atan2(float(port.islandX) - float(port.x), float(port.islandZ) - float(port.z))
		root.add_child(group)
		var pier := _box(group, Vector3(8, 0.5, 55), Vector3(0, PIER_DECK_HEIGHT, 20), wood)
		pier.name = "PierDeck"
		for z in range(-4, 48, 9):
			for x: float in [-3.1, 3.1]:
				_box(group, Vector3(0.55, 10.7, 0.55), Vector3(x, -1.4, z), wood)
		for index in 9:
			var x := float(port.islandX) + cos(index * 2.15) * float(port.radius) * 0.42
			var z := float(port.islandZ) + sin(index * 2.15) * float(port.radius) * 0.32
			var height := float(_height_sampler.call(x, z))
			if height < 2.0 or not is_finite(height):
				continue
			var house := Node3D.new()
			house.position = Vector3(x, height, z)
			house.rotation.y = index * 0.7
			root.add_child(house)
			var width := 8.0 + (index % 3) * 2.0
			var wall_height := 4.0 + index % 2
			_box(house, Vector3(width, wall_height, 7), Vector3(0, wall_height / 2.0, 0), walls)
			_box(house, Vector3(width * 0.32, wall_height * 0.65, 0.15), Vector3(0, wall_height * 0.325, 3.58), wood)
			for side: float in [-1.0, 1.0]:
				var slope := _box(house, Vector3(width + 2, 0.35, 5.04), Vector3(0, wall_height + 1.4, side * 1.96), roof)
				slope.rotation.x = side * 0.42
			_box(house, Vector3(width + 2, 0.4, 0.55), Vector3(0, wall_height + 2.8, 0), roof)

func _material(hex: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.html(hex)
	material.roughness = 0.95
	return material

func _box(parent: Node3D, dimensions: Vector3, point: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = dimensions
	node.mesh = box
	node.material_override = material
	node.position = point
	parent.add_child(node)
	return node

func get_ocean() -> MeshInstance3D:
	return _ocean

func get_chunk_count() -> int:
	return _chunks.size()

func get_chunk_build_count() -> int:
	return _builds

func get_chunks() -> Array:
	return _chunks.values()

func dispose() -> void:
	_disposed = true
	for node in _owned:
		if is_instance_valid(node):
			node.free()
	_owned.clear()
	_chunks.clear()
	_ocean = null
	_shore_field = null
	_shore_spray = null
	_vegetation_library = null
	_height_sampler = Callable()
	_camera = null
