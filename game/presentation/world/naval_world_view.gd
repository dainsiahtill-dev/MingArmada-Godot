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
const CameraRig = preload("res://game/presentation/world/ship_camera_controller.gd")
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
var _pending_crew_entries: Dictionary = {}
var _disposed := true
var _camera_controller: Callable
var _camera_rig := CameraRig.new()
var _camera_dragging := false
var _camera_owner := ""
var _camera_tick := 0
func set_camera_controller(controller: Callable) -> void:
	_camera_controller = controller
	cancel_camera_drag()

func handle_camera_input(event: InputEvent) -> bool:
	if _disposed or _camera_controller.is_valid(): return false
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_camera_dragging = event.pressed
			return true
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			var steps: float = event.factor*(1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0)
			if _camera_rig.zoom_by(steps):
				zoom = float(_camera_rig.status().zoom)
				return true
	elif event is InputEventMouseMotion and _camera_dragging:
		return _camera_rig.orbit(event.relative)
	return false

func cancel_camera_drag() -> void:
	_camera_dragging = false

func recenter_camera() -> void:
	if _disposed or _camera_controller.is_valid(): return
	cancel_camera_drag()
	tactical = false
	zoom = 1.0
	_camera_rig.recenter()

func camera_status() -> Dictionary:
	var result := _camera_rig.status()
	result.dragging = _camera_dragging
	return result

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
	effects.set_camera(camera)
	effects.set_surface_filter(_surface_is_water)
	wakes = Wakes.new(); _own(wakes); wakes.configure(_water)
	wakes.configure_surface_filter(_surface_is_water)
	apply_snapshot(native, [], 0.0)
	for ship: Dictionary in native.get("ships", []):
		if not ships.has(str(ship.id)) or not sailors.has(str(ship.id)):
			dispose()
			return false
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
		world.apply_snapshot({"time":_snapshot.get("time",0.0),"wind":_snapshot.get("wind",{}),"battleId":_snapshot.get("battleId",""),"focus":{"x":_last_target.x,"z":_last_target.z}},0.0)
	for crew in sailors.values(): crew.set_reduced_motion(bool(_settings.reducedMotion))
	for ship in ships.values(): ship.set_reduced_motion(bool(_settings.reducedMotion))
	world.set_reduced_motion(bool(_settings.reducedMotion))

func observe_projectiles(native: Dictionary) -> void:
	if not _disposed: effects.observe_projectiles(native)

func remember_authoritative_poses(native:Dictionary,consumed:float=0.0)->void:
	# Existing actor/model IDs are authoritative for this lightweight physics
	# path. Creating actors and presenting meshes/world remains apply_snapshot.
	if _disposed:return
	var supplied:Variant=native.get("time",0.0)
	if not (supplied is int or supplied is float) or not is_finite(float(supplied)):return
	var next_battle:=String(native.get("battleId",""))
	if next_battle!=_battle_id:
		# Old actors may already have a sinking/damaged model-root offset. Until
		# the normal epoch reset builds the new actors, there is no valid source
		# pose to capture; delayed events honestly use their native mouth.
		for view:Node3D in ships.values():view.get("_source_poses").clear()
		return
	for ship:Dictionary in native.get("ships",[]):
		var id:=String(ship.get("id",""))
		if not ships.has(id) or _kinds.get(id)!=String(ship.get("kind","")):continue
		var pose:Variant=ships[id].remember_authoritative_pose(ship,float(supplied))
		if pose is Transform3D and sailors.has(id):sailors[id].advance_impacts(float(supplied),consumed,pose)

func _reset_fleet() -> void:
	_pending_crew_entries.clear()
	for id: String in ships.keys(): _release_ship(id)
	if effects:
		_owned.erase(effects); effects.free()
		effects = Effects.new(); _own(effects); effects.set_water_sampler(_water)
		effects.set_camera(camera)
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
	var stamp: Variant = event.get("time",0.0)
	if not point.is_finite() or not (stamp is int or stamp is float) or not is_finite(float(stamp)) or float(stamp) < 0.0: return
	var id := "crew-entry:%s:%s" % [event.get("event_id",""),event.get("body_id","")]
	# Jolt contact can arrive during physics before the next drawn snapshot.
	# Preserve its actual birth instead of feeding a future event into Effects'
	# reject-and-deduplicate guard. The presentation owner flushes it below.
	_pending_crew_entries[id] = {"type":"splash","id":id,"time":float(stamp),"position":{"x":point.x,"y":point.y,"z":point.z},"scale":0.45}

func _flush_crew_water_entries() -> void:
	var ready: Array = []
	for id: String in _pending_crew_entries.keys():
		var event: Dictionary = _pending_crew_entries[id]
		if float(event.time) <= float(effects.get("_time")):
			ready.append(event); _pending_crew_entries.erase(id)
	if not ready.is_empty(): effects.apply_events(ready)

func _release_ship(id: String) -> void:
	_kinds.erase(id)
	if sailors.has(id):
		sailors[id].dispose(); sailors.erase(id)
	if ships.has(id):
		var view: Node3D = ships[id]
		view.dispose(); view.free(); ships.erase(id)

func apply_snapshot(native: Dictionary, events: Array = [], consumed: float = 0.0) -> Array:
	if _disposed: return []
	if float(native.get("time",0.0)) < float(_snapshot.get("time",0.0)): _pending_crew_entries.clear()
	var next_battle := String(native.get("battleId", ""))
	if next_battle != _battle_id and not _battle_id.is_empty(): _reset_fleet()
	_battle_id = next_battle
	_snapshot = native.duplicate(true)
	_update_camera(native, consumed)
	effects.apply_snapshot(native,consumed)
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
			if not crew.configure(String(ship.kind),view.get_model(),library):
				crew.free(); _release_ship(id); continue
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
	for event: Dictionary in presented_events:
		if event.get("type") == "fire" and not event.has("source_muzzle_position") and ships.has(str(event.get("shipId",""))):
			var source_point: Variant = ships[str(event.shipId)].source_fire_position(event)
			if source_point is Vector3: event.source_muzzle_position={"x":source_point.x,"y":source_point.y,"z":source_point.z}
	for id: String in ships:
		ships[id].apply_events(presented_events); sailors[id].apply_events(presented_events)
	effects.apply_events(presented_events)
	_flush_crew_water_entries()
	wakes.apply_snapshot(native)
	world.apply_snapshot({"time":native.get("time",0.0),"wind":native.get("wind",{}),"battleId":native.get("battleId",""),"focus":{"x":_last_target.x,"z":_last_target.z}},consumed)
	return presented_events

func _update_camera(native: Dictionary, consumed: float) -> void:
	var ship := find_ship(native,String(native.get("playerId","")))
	if ship.is_empty(): return
	var point: Dictionary = ship.visual.position
	var target := Vector3(point.x,point.y+3.0,point.z)
	if _camera_controller.is_valid():
		_last_target = target
		_camera_controller.call()
		return
	var owner := "%s/%s/%s" % [native.get("battleId",""),ship.get("id",""),ship.get("kind","")]
	if owner != _camera_owner:
		_camera_rig.reset(); cancel_camera_drag()
		if not _camera_owner.is_empty(): zoom = 1.0
		_camera_owner = owner
		_camera_tick = 0
	var now := Time.get_ticks_usec()
	var input_seconds := minf(float(now-_camera_tick)/1000000.0,0.1) if _camera_tick > 0 else 0.0
	_camera_tick = now
	var frame := _camera_rig.step(ship,consumed,_settings,tactical,zoom,input_seconds)
	if frame.is_empty(): return
	_camera_target = frame.target
	_last_target = target; _camera_ready = true; _last_tactical = tactical
	var eye: Vector3 = frame.position
	# A low orbit near a mountainous shore must remain above terrain as well
	# as water. This is a single sampler lookup, not a new world presentation.
	if _height.is_valid():
		var world_eye := to_global(eye)
		var terrain: Variant = _height.call(world_eye.x,world_eye.z)
		if (terrain is float or terrain is int) and is_finite(float(terrain)):
			world_eye.y = maxf(world_eye.y,float(terrain)+4.0)
			eye = to_local(world_eye)
	camera.position = eye
	camera.look_at(_camera_target,frame.up)

func dispose() -> void:
	_disposed = true
	_camera_controller = Callable()
	_camera_rig.reset(); cancel_camera_drag()
	_camera_owner = ""; _camera_tick = 0
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
	_pending_crew_entries.clear()

func _exit_tree() -> void: dispose()
