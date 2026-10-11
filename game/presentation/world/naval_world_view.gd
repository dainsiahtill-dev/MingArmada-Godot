extends Node3D
## Shared native sea presentation. Authority snapshots and samplers are injected;
## this node never advances combat, business state or a separate wave clock.
const World = preload("res://modules/scene_engine/world/world_view.gd")
const Library = preload("res://modules/scene_engine/assets/asset_library.gd")
const Waves = preload("res://modules/contracts/wave_descriptor.gd")
const Ship = preload("res://game/presentation/ships/ship_view.gd")
const Crew = preload("res://game/presentation/crew/crew_view.gd")
const Effects = preload("res://game/presentation/combat/combat_effects.gd")
const Wakes = preload("res://game/presentation/water/wake_trails.gd")
const QUALITY := {
	"low":{"resolution":40,"chunk_radius":2,"shadows":false,"bloom":false},
	"balanced":{"resolution":64,"chunk_radius":3,"shadows":true,"bloom":false},
	"high":{"resolution":96,"chunk_radius":4,"shadows":true,"bloom":true}}
var world: Node3D
var camera: Camera3D
var effects: Node3D
var wakes: Node3D
var library: RefCounted
var ships: Dictionary = {}
var sailors: Dictionary = {}
var _kinds: Dictionary = {}
var tactical := false
var zoom := 1.0
var _owned: Array[Node] = []
var _height: Callable
var _water: Callable
var _ports: Array = []
var _options: Dictionary = {}
var _settings := {"quality":"balanced","cameraFollow":true,"cameraShake":0.0,"horizonStability":1.0,"reducedMotion":false}
var _environment: Environment
var _sun: DirectionalLight3D
var _camera_target := Vector3.ZERO
var _last_target := Vector3.ZERO
var _camera_ready := false
var _last_tactical := false
var _battle_id := ""
var _snapshot: Dictionary = {}
var _disposed := true

static func find_ship(native: Dictionary, id: String) -> Dictionary:
	for ship: Dictionary in native.get("ships", []):
		if String(ship.get("id", "")) == id: return ship
	return {}

func configure(height_sampler: Callable, ports: Array, water_sampler: Callable, native: Dictionary, options: Dictionary = {}) -> bool:
	dispose()
	if not height_sampler.is_valid() or not water_sampler.is_valid(): return false
	_disposed = false
	_height = height_sampler; _water = water_sampler
	_ports = ports.duplicate(true); _options = options.duplicate(true)
	library = Library.new()
	var environment_node := WorldEnvironment.new()
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR; _environment.background_color = Color.html("87ceeb")
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color.html("a0c8ff"); _environment.ambient_light_energy = 0.45
	_environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_environment.tonemap_exposure = 1.0
	environment_node.environment = _environment; _own(environment_node)
	_sun = DirectionalLight3D.new(); _own(_sun)
	_sun.position = Vector3(300,150,100); _sun.look_at(Vector3.ZERO)
	_sun.light_energy = 1.2
	_sun.shadow_enabled = bool(QUALITY.get(_settings.quality,QUALITY.balanced).shadows)
	_environment.glow_enabled = bool(QUALITY.get(_settings.quality,QUALITY.balanced).bloom)
	camera = Camera3D.new(); _own(camera)
	camera.fov = 55; camera.near = 0.5; camera.far = 4000; camera.current = true
	_update_camera(native, 0.0) # Ocean projection needs the actual camera first.
	world = World.new(); _own(world)
	if not _configure_world(): dispose(); return false
	effects = Effects.new(); _own(effects); effects.set_water_sampler(_water)
	effects.set_surface_filter(_surface_is_water)
	wakes = Wakes.new(); _own(wakes); wakes.configure(_water)
	wakes.configure_surface_filter(_surface_is_water)
	apply_snapshot(native, [], 0.0)
	return true

func _own(node: Node) -> void:
	add_child(node); _owned.append(node)

func _configure_world() -> bool:
	var settings: Dictionary = QUALITY.get(_settings.quality, QUALITY.balanced).duplicate(true)
	settings.merge(_options, true)
	settings.merge({"camera":camera,"ports":_ports,"collision":false,"visual_style":1,"quality":_settings.quality,"reduced_motion":_settings.reducedMotion}, true)
	if not world.configure(_height, Waves.original_descriptors(), settings): return false
	_bind_reference_environment()
	return true

func _bind_reference_environment() -> void:
	var ocean: MeshInstance3D = world.get_ocean()
	if not ocean.has_method("get_sky_material"): return
	var material: ShaderMaterial = ocean.get_sky_material()
	if material == null: return
	var sky := Sky.new(); sky.sky_material = material
	_environment.sky = sky; _environment.background_mode = Environment.BG_SKY
	_environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR; _environment.tonemap_exposure = 1.0
	_environment.fog_enabled = false
	# Sea/terrain compute source light themselves; imported ships and buildings
	# still use native illumination, aligned with the same source sun.
	var sun_direction := Vector3(-0.5,0.8,0.3).normalized()
	_sun.basis = Basis.looking_at(-sun_direction,Vector3.UP)
	_sun.light_color = Color(1.0,0.95,0.82); _sun.light_energy = 1.1
	camera.environment = _environment

func apply_settings(settings: Dictionary) -> void:
	var old_quality: String = _settings.quality
	for key: String in _settings:
		if settings.has(key): _settings[key] = settings[key]
	if _disposed: return
	_sun.shadow_enabled = bool(QUALITY.get(_settings.quality, QUALITY.balanced).shadows)
	_environment.glow_enabled = bool(QUALITY.get(_settings.quality, QUALITY.balanced).bloom)
	if old_quality != _settings.quality:
		_configure_world()
		world.apply_snapshot({"time":_snapshot.get("time",0.0),"wind":_snapshot.get("wind",{}),"focus":{"x":_last_target.x,"z":_last_target.z}},0.0)
	for crew in sailors.values(): crew.set_reduced_motion(bool(_settings.reducedMotion))
	for ship in ships.values(): ship.set_reduced_motion(bool(_settings.reducedMotion))

func observe_projectiles(native: Dictionary) -> void:
	if not _disposed: effects.observe_projectiles(native)

func _reset_fleet() -> void:
	for id: String in ships.keys(): _release_ship(id)
	if effects:
		_owned.erase(effects); effects.free()
		effects = Effects.new(); _own(effects); effects.set_water_sampler(_water)
		effects.set_surface_filter(_surface_is_water)
	if wakes:
		wakes.configure(_water)
		wakes.configure_surface_filter(_surface_is_water)

func _surface_is_water(x: float, z: float) -> bool:
	if not _height.is_valid(): return false
	var height := float(_height.call(x,z))
	return is_finite(height) and height < 0.0

func _on_ship_presentation(event: Dictionary) -> void:
	if not _disposed and is_instance_valid(effects): effects.apply_events([event])

func _on_crew_water_entry(event: Dictionary) -> void:
	if _disposed or not is_instance_valid(effects) or event.get("type") != "crew-water-entry": return
	var point: Vector3 = event.get("position",Vector3.ZERO)
	effects.apply_events([{"type":"splash","id":"crew-entry:%s:%s" % [event.get("event_id",""),event.get("body_id","")],"time":event.get("time",0.0),"position":{"x":point.x,"y":point.y,"z":point.z},"scale":0.45}])

func _release_ship(id: String) -> void:
	_kinds.erase(id)
	if sailors.has(id):
		sailors[id].dispose(); sailors.erase(id)
	if ships.has(id):
		var view: Node3D = ships[id]
		view.dispose(); view.free(); ships.erase(id)

func apply_snapshot(native: Dictionary, events: Array = [], consumed: float = 0.0) -> Array:
	if _disposed: return []
	var next_battle := String(native.get("battleId", ""))
	if next_battle != _battle_id and not _battle_id.is_empty(): _reset_fleet()
	_battle_id = next_battle
	_snapshot = native.duplicate(true)
	effects.apply_snapshot(native,consumed)
	_update_camera(native, consumed)
	var requests: Array = []
	for ship: Dictionary in native.get("ships", []):
		var p: Dictionary = ship.visual.position
		var distance := camera.position.distance_to(Vector3(p.x,p.y,p.z))
		var count := int(ship.crew)
		var requested := mini(24,count) if distance <= 220 else mini(8,count) if distance <= 650 else mini(2,count) if distance <= 1200 else 0
		requests.append({"id":ship.id,"distance":distance,"requested":requested})
	var allocations: Dictionary = Crew.allocate_sailors(requests)
	var live: Dictionary = {}
	for ship: Dictionary in native.get("ships", []):
		var id: String = ship.id; live[id] = true
		if ships.has(id) and _kinds.get(id) != String(ship.kind): _release_ship(id)
		if not ships.has(id):
			var view := Ship.new(); add_child(view)
			if not view.configure(String(ship.kind),library): view.free(); continue
			ships[id] = view
			view.presentation_event.connect(_on_ship_presentation)
			_kinds[id] = String(ship.kind)
			view.set_reduced_motion(bool(_settings.reducedMotion))
			var crew := Crew.new(); view.add_child(crew)
			crew.configure(String(ship.kind),view.get_model(),library)
			crew.set_environment(_water); crew.set_reduced_motion(bool(_settings.reducedMotion))
			crew.get_impact_pool().visual_event.connect(_on_crew_water_entry)
			sailors[id] = crew
		var view: Node3D = ships[id]
		var timed := ship.duplicate(true); timed.time = native.get("time",0.0)
		view.apply_snapshot(timed,native.get("wind",{}),consumed)
		view.set_lod_distance(camera.position.distance_to(view.position))
		var crew: Node3D = sailors[id]; crew.set_ship_model(view.get_model())
		crew.set_lod_distance(camera.position.distance_to(view.position)); crew.set_allocation(int(allocations.get(id,0)))
		crew.apply_snapshot(timed,native.get("wind",{}),consumed)
	for id: String in ships.keys():
		if not live.has(id): _release_ship(id)
	var presented_events: Array = effects.presentation_events(events)
	for id: String in ships:
		ships[id].apply_events(presented_events); sailors[id].apply_events(presented_events)
	effects.apply_events(presented_events)
	wakes.apply_snapshot(native)
	world.apply_snapshot({"time":native.get("time",0.0),"wind":native.get("wind",{}),"focus":{"x":_last_target.x,"z":_last_target.z}},consumed)
	return presented_events

func _update_camera(native: Dictionary, consumed: float) -> void:
	var ship := find_ship(native,String(native.get("playerId","")))
	if ship.is_empty(): return
	var point: Dictionary = ship.visual.position
	var target := Vector3(point.x,point.y+3.0,point.z)
	var mode_changed := _last_tactical != tactical
	if not _camera_ready or mode_changed:
		_camera_target = target
	elif bool(_settings.cameraFollow) or tactical:
		if consumed > 0.0: _camera_target = _camera_target.lerp(target,1.0-exp(-6.0*consumed))
		elif target != _last_target: _camera_target += target-_last_target
	_last_target = target; _camera_ready = true; _last_tactical = tactical
	var offset := Vector3(80,115,-110) if tactical else Vector3(33,24,-39)
	var seconds := fmod(float(native.get("time",0.0)),10000.0)
	var strength := float(_settings.cameraShake)*0.35 if not tactical and not bool(_settings.reducedMotion) else 0.0
	var shake := Vector3(sin(seconds*13.0),sin(seconds*17.0)*0.6,sin(seconds*11.0))*strength
	camera.position = _camera_target+offset*zoom+shake
	var roll := 0.0 if bool(_settings.reducedMotion) else float(ship.visual.get("heel",0.0))*(1.0-float(_settings.horizonStability))
	var heading := float(ship.visual.get("heading",0.0))
	var up := Vector3(sin(roll)*cos(heading),cos(roll),-sin(roll)*sin(heading))
	camera.look_at(_camera_target,up)

func dispose() -> void:
	_disposed = true
	for id: String in ships.keys(): _release_ship(id)
	for node in _owned:
		if is_instance_valid(node):
			if node == world: world.dispose()
			node.free()
	_owned.clear()
	if library: library.dispose()
	library = null; world = null; camera = null; effects = null; wakes = null
	_environment = null; _sun = null; _height = Callable(); _water = Callable()
	_ports.clear(); _snapshot.clear(); _battle_id = ""; _camera_ready = false

func _exit_tree() -> void: dispose()
