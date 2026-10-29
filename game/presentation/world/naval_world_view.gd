extends Node3D
## Shared native sea presentation. Authority snapshots and samplers are injected;
## this node never advances combat, business state or a separate wave clock.
signal presentation_failed(receipt: Dictionary)
const Cargo = preload("res://game/presentation/cargo/cargo_world_view.gd")
const World = preload("res://modules/scene_engine/world/world_view.gd")
const Library = preload("res://modules/scene_engine/assets/asset_library.gd")
const Waves = preload("res://modules/contracts/wave_descriptor.gd")
const Ship = preload("res://game/presentation/ships/ship_view.gd")
const Crew = preload("res://game/presentation/crew/crew_view.gd")
const Effects = preload("res://game/presentation/combat/combat_effects.gd")
const Wakes = preload("res://game/presentation/water/wake_trails.gd")
const CameraRig = preload("res://game/presentation/world/ship_camera_controller.gd")
const WaterPacket = preload("res://game/presentation/world/source_water_packet.gd")
const ShadowRenderer = preload("res://modules/scene_engine/fidelity_fx/source_shadow_renderer.gd")
const RigidCasters = preload("res://game/presentation/world/target_rigid_shadow_caster.gd")
const InteractiveWater = preload("res://modules/scene_engine/water/interactive_wake_system.gd")
const QUALITY := {
	"low":{"resolution":40,"chunk_radius":2,"shadows":false,"bloom":false},
	"balanced":{"resolution":64,"chunk_radius":3,"shadows":true,"bloom":false},
	"high":{"resolution":96,"chunk_radius":4,"shadows":true,"bloom":true}}
var _cargo: Node3D
var _presentation_failure: Dictionary = {}
var world: Node3D
var camera: Camera3D
var effects: Node3D
var wakes: Node3D
var library: RefCounted
var source_shadows: RefCounted
var _rigid_casters := RigidCasters.new()
var _shadow_capability: Dictionary = {}
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
var _local_presentation_seconds: Dictionary = {}
var _disposed := true
var _camera_controller: Callable
var _camera_rig := CameraRig.new()
var _camera_dragging := false
var _camera_owner := ""
var _camera_tick := 0
var _interactive_water: RefCounted
var _water_mask_revision := -1
var _interactive_ocean_id := 0
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
	_presentation_failure.clear()
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
	var atmosphere: Dictionary=_prepare_atmosphere(effects)
	if not atmosphere.get("ok",false):
		dispose()
		_fail_presentation(atmosphere,"configure")
		return false
	wakes = Wakes.new(); _own(wakes); _configure_wakes()
	_configure_interactive_water()
	source_shadows=ShadowRenderer.new();_shadow_capability=source_shadows.configure(self,camera)
	apply_snapshot(native, [], 0.0)
	for ship: Dictionary in native.get("ships", []):
		if not ships.has(str(ship.id)) or not sailors.has(str(ship.id)):
			dispose()
			return false
	return true

func _destruction_anchor(id: String) -> Dictionary:
	return ships[id].source_destruction_anchor() if ships.has(id) else {}

func _prepare_atmosphere(owner: Node3D) -> Dictionary:
	return owner.configure_atmosphere({"enabled":bool(_options.get("combat_atmosphere",true)),"quality":_settings.quality},_destruction_anchor)

func _fail_presentation(receipt: Dictionary, phase: String) -> void:
	_presentation_failure=receipt.duplicate(true)
	_presentation_failure.ok=false
	_presentation_failure.reason=str(receipt.get("reason","combat-atmosphere-unavailable"))
	_presentation_failure.phase=phase
	presentation_failed.emit(_presentation_failure.duplicate(true))

func presentation_status() -> Dictionary:
	return {"ready":not _disposed and _presentation_failure.is_empty() and is_instance_valid(effects) and effects.atmosphere_diagnostics().get("ready",false),"failed":not _presentation_failure.is_empty(),"reason":_presentation_failure.get("reason",""),"failure":_presentation_failure.duplicate(true)}

func _cargo_source(id: String) -> Dictionary:
	if not ships.has(id): return {}
	var view: Node3D=ships[id]
	if view.damage_diagnostics().get("ended",false): return {}
	return {"model":view.source_deck_model(),"kind":_kinds.get(id,"")}

func apply_cargo_snapshot(native: Dictionary, packet: Dictionary) -> Dictionary:
	if _disposed: return {"ok":false,"reason":"world-disposed"}
	if not _presentation_failure.is_empty(): return _presentation_failure.duplicate(true)
	if _cargo==null:
		_cargo=Cargo.new();_cargo.name="CommittedCargo";_own(_cargo)
		var prepared: Dictionary=_cargo.configure(_water,_cargo_source)
		if not prepared.get("ok",false): return prepared
	var receipt: Dictionary=_cargo.apply_snapshot(native,packet)
	var splashes: Array=_cargo.drain_splashes()
	if not splashes.is_empty(): effects.apply_events(splashes)
	return receipt

func cargo_diagnostics() -> Dictionary:
	return _cargo.inspection_snapshot() if _cargo else {"ready":false,"decks":{},"floating":[]}

func _release_cargo() -> void:
	if _cargo:
		_owned.erase(_cargo);_cargo.dispose();_cargo.free();_cargo=null

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
	world.bind_environment(_environment,_sun)

func apply_settings(settings: Dictionary) -> void:
	var old_quality: String = _settings.quality
	for key: String in _settings:
		if settings.has(key): _settings[key] = settings[key]
	if _disposed: return
	_sun.shadow_enabled = bool(QUALITY.get(_settings.quality, QUALITY.balanced).shadows)
	_environment.glow_enabled = bool(QUALITY.get(_settings.quality, QUALITY.balanced).bloom)
	if old_quality != _settings.quality:
		_configure_world()
		world.apply_snapshot(_world_packet(_snapshot),0.0)
		_apply_interactive_water(_snapshot)
	for crew in sailors.values(): crew.set_reduced_motion(bool(_settings.reducedMotion))
	for ship in ships.values(): ship.set_reduced_motion(bool(_settings.reducedMotion))
	world.set_reduced_motion(bool(_settings.reducedMotion))
	_apply_source_shadows(_snapshot)

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

func _reset_fleet() -> bool:
	# Prepare required resources before releasing the last usable picture.
	# A failed replacement is latched and reported to the runtime owner; keep
	# its camera alive so scene/services can present the failure without nulls.
	var candidate := Effects.new(); _own(candidate)
	candidate.set_water_sampler(_water); candidate.set_camera(camera)
	candidate.set_surface_filter(_surface_is_water)
	var atmosphere: Dictionary=_prepare_atmosphere(candidate)
	if not atmosphere.get("ok",false):
		_owned.erase(candidate); candidate.dispose(); candidate.free()
		_fail_presentation(atmosphere,"reset")
		return false
	_release_cargo()
	_pending_crew_entries.clear()
	_local_presentation_seconds.clear()
	for id: String in ships.keys(): _release_ship(id)
	if effects:
		_owned.erase(effects); effects.dispose(); effects.free()
	effects=candidate
	if wakes:
		_configure_wakes()
	return true

func _configure_wakes() -> void:
	wakes.configure(_water)
	wakes.configure_surface_filter(_surface_is_water)
	var provider: Object = _height.get_object()
	if is_instance_valid(provider) and provider.has_method("begin_sampling_scope"):
		wakes.configure_sampling_scope(Callable(provider,"begin_sampling_scope"))

func _configure_interactive_water() -> void:
	if _interactive_water!=null:_interactive_water.dispose()
	_interactive_water=null;_water_mask_revision=-1;_interactive_ocean_id=0
	# Accepted in the wake-flow lab and actual free-sail GPU path. An explicit
	# false retains the original renderer for comparison and recovery.
	if not bool(_options.get("interactive_wake",true)):return
	_interactive_water=InteractiveWater.new()
	_water_mask_revision=world.get_interactive_water_mask_revision()
	_interactive_ocean_id=world.get_ocean().get_instance_id()
	_interactive_water.configure(world.get_ocean(),_water,world.get_interactive_water_mask(),_options.get("interactive_wake_options",{}))

func _apply_interactive_water(native: Dictionary) -> void:
	if _interactive_water==null:return
	var revision: int=world.get_interactive_water_mask_revision()
	var ocean: MeshInstance3D=world.get_ocean()
	# Rebuilds publish a new complete terrain mask; ordinary frames only read an
	# integer revision. No repeated terrain queries or GPU image download.
	if revision!=_water_mask_revision or _interactive_ocean_id!=ocean.get_instance_id():
		_water_mask_revision=revision
		_interactive_ocean_id=ocean.get_instance_id()
		_interactive_water.set_ocean(ocean,world.get_interactive_water_mask())
	var inputs: Array=[]
	for state: Dictionary in native.get("ships",[]):
		var id:=str(state.get("id",""))
		if not ships.has(id):continue
		inputs.append({"id":id,"attachment":ships[id].source_water_attachment(),"hull_alive":float(state.get("hull",100.0))>0.0 and not bool(state.get("sunk",false))})
	var environment: Dictionary=native.get("environment",{})
	var seconds:=float(environment.get("acceptedTime",native.get("time",0.0)))
	var epoch:=str(native.get("battleId",""))+":"+str(environment.get("epoch",""))+":"+str(environment.get("route","sailing"))
	_interactive_water.apply_snapshot(seconds,str(native.get("playerId","")),inputs,epoch)
	_interactive_water.poll()
	wakes.set_interactive_coverage(_interactive_water.covered_actor_ids())
	ocean.update_projection()

func interactive_water_status() -> Dictionary:
	return _interactive_water.diagnostics() if _interactive_water!=null else {"enabled":false,"covered":[]}

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
	_local_presentation_seconds.erase(id)
	if sailors.has(id):
		sailors[id].dispose(); sailors.erase(id)
	if ships.has(id):
		var view: Node3D = ships[id]
		view.dispose(); view.free(); ships.erase(id)

static func requires_full_event_presentation(events: Array) -> bool:
	for event: Dictionary in events:
		if event.get("type") == "hit" and float(event.get("damage",{}).get("crew",0.0)) > 0.0: return true
	return false

func _prepare_ship(ship: Dictionary) -> Node3D:
	var id: String = ship.id
	if ships.has(id) and _kinds.get(id) != String(ship.kind): _release_ship(id)
	if ships.has(id): return ships[id]
	var view := Ship.new(); add_child(view)
	if not view.configure(String(ship.kind),library): view.free(); return null
	ships[id] = view
	view.presentation_event.connect(_on_ship_presentation)
	_kinds[id] = String(ship.kind)
	view.set_reduced_motion(bool(_settings.reducedMotion))
	var crew := Crew.new(); view.add_child(crew)
	if not crew.configure(String(ship.kind),view.get_model(),library):
		crew.free(); _release_ship(id); return null
	crew.set_environment(_water); crew.set_reduced_motion(bool(_settings.reducedMotion))
	crew.get_impact_pool().visual_event.connect(_on_crew_water_entry)
	sailors[id] = crew
	return view

func _source_fire_events(events: Array) -> Array:
	var result: Array = effects.presentation_events(events)
	for event: Dictionary in result:
		if event.get("type") == "fire" and not event.has("source_muzzle_position") and ships.has(str(event.get("shipId",""))):
			var source_point: Variant = ships[str(event.shipId)].source_fire_position(event)
			if source_point is Vector3: event.source_muzzle_position={"x":source_point.x,"y":source_point.y,"z":source_point.z}
	return result

func apply_local_fire(native: Dictionary, events: Array, consumed: float = 0.0) -> Array:
	if _disposed or not _presentation_failure.is_empty(): return []
	if float(native.get("time",0.0)) < float(_snapshot.get("time",0.0)):
		_pending_crew_entries.clear(); _local_presentation_seconds.clear()
	var next_battle := String(native.get("battleId", ""))
	if next_battle != _battle_id:
		_local_presentation_seconds.clear()
		if not _battle_id.is_empty() and not _reset_fleet(): return []
	_battle_id = next_battle
	_snapshot = native.duplicate(true)
	# Keep exactly the accepted times formerly submitted by immediate fire
	# _present. Existing source controllers still advance before new births.
	effects.begin_snapshot(native,consumed)
	var firing: Dictionary = {}
	for event: Dictionary in events:
		if event.get("type") != "fire": continue
		var id := String(event.get("shipId",""))
		if firing.has(id): continue
		var ship := find_ship(native,id)
		if ship.is_empty(): continue
		var view := _prepare_ship(ship)
		if view == null: continue
		var timed := ship.duplicate(true); timed.time = native.get("time",0.0)
		var actor_seconds := maxf(0.0,consumed-float(_local_presentation_seconds.get(id,0.0)))
		view.apply_snapshot(timed,native.get("wind",{}),actor_seconds)
		var crew: Node3D = sailors[id]; crew.set_ship_model(view.get_model())
		crew.apply_snapshot(timed,native.get("wind",{}),actor_seconds)
		_local_presentation_seconds[id] = consumed
		firing[id] = true
	effects.finish_snapshot()
	var presented_events := _source_fire_events(events)
	for id: String in firing: ships[id].apply_events(presented_events)
	# Preserve ordered fire velocity caches and reload/reconcile semantics for
	# every crew owner; only the firing crews received a snapshot above.
	for crew: Node3D in sailors.values(): crew.apply_events(presented_events)
	effects.apply_events(presented_events)
	effects.refresh_attached_effects()
	_flush_crew_water_entries()
	return presented_events

func apply_snapshot(native: Dictionary, events: Array = [], consumed: float = 0.0) -> Array:
	if _disposed or not _presentation_failure.is_empty(): return []
	if float(native.get("time",0.0)) < float(_snapshot.get("time",0.0)):
		_pending_crew_entries.clear(); _local_presentation_seconds.clear()
	var next_battle := String(native.get("battleId", ""))
	if next_battle != _battle_id and not _battle_id.is_empty() and not _reset_fleet(): return []
	_battle_id = next_battle
	_snapshot = native.duplicate(true)
	_update_camera(native, consumed)
	# Source particle math overlaps the independent ship/crew presentation.
	# All jobs finish in this frame; rendering and callbacks stay on main.
	effects.begin_snapshot(native,consumed)
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
		var view := _prepare_ship(ship)
		if view == null: continue
		var timed := ship.duplicate(true); timed.time = native.get("time",0.0)
		var actor_seconds := maxf(0.0,consumed-float(_local_presentation_seconds.get(id,0.0)))
		view.apply_snapshot(timed,native.get("wind",{}),actor_seconds)
		view.set_lod_distance(camera.position.distance_to(view.position))
		var crew: Node3D = sailors[id]; crew.set_ship_model(view.get_model())
		crew.set_lod_distance(camera.position.distance_to(view.position)); crew.set_allocation(int(allocations.get(id,0)))
		crew.apply_snapshot(timed,native.get("wind",{}),actor_seconds)
	for id: String in ships.keys():
		if not live.has(id): _release_ship(id)
	effects.finish_snapshot()
	var presented_events := _source_fire_events(events)
	for id: String in ships:
		ships[id].apply_events(presented_events); sailors[id].apply_events(presented_events)
	effects.apply_events(presented_events)
	effects.refresh_attached_effects()
	_flush_crew_water_entries()
	wakes.apply_snapshot(WaterPacket.compose(native,ships,camera))
	world.apply_snapshot(_world_packet(native),consumed)
	_apply_interactive_water(native)
	_apply_source_shadows(native)
	_local_presentation_seconds.clear()
	return presented_events

func _world_packet(native:Dictionary)->Dictionary:
	var packet:=native.duplicate(false)
	packet.focus={"x":_last_target.x,"z":_last_target.z}
	return packet

func _apply_source_shadows(native:Dictionary)->void:
	if source_shadows==null:return
	var packet:=_rigid_casters.compose(native,ships,-_sun.global_basis.z,source_shadow_status().stencilActive,bool(QUALITY.get(_settings.quality,QUALITY.balanced).shadows))
	packet.actors.merge(ships,false)
	source_shadows.apply_snapshot(packet.native,packet.actors,native.get("environment",{}))

func source_shadow_status()->Dictionary:
	var report:Dictionary=source_shadows.diagnostics() if source_shadows else {}
	var gpu:Dictionary=report.get("gpu",{})
	var active:=bool(_shadow_capability.get("activeCompositor",false)) and bool(gpu.get("initialized",false)) and str(gpu.get("error","")).is_empty()
	report.stencilActive=active
	report.presentationMode="source_stencil" if active else "target_shadow_maps_fallback"
	report.casterAdapter=_rigid_casters.diagnostics()
	return report

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
	_release_cargo()
	if _interactive_water!=null:_interactive_water.dispose()
	_interactive_water=null;_water_mask_revision=-1;_interactive_ocean_id=0
	if source_shadows:source_shadows.dispose()
	source_shadows=null;_shadow_capability.clear();_rigid_casters.dispose()
	_camera_controller = Callable()
	_camera_rig.reset(); cancel_camera_drag()
	_camera_owner = ""; _camera_tick = 0
	for id: String in ships.keys(): _release_ship(id)
	for node in _owned:
		if is_instance_valid(node):
			if node == world: world.dispose()
			elif node == effects: effects.dispose()
			node.free()
	_owned.clear()
	if library: library.dispose()
	library = null; world = null; camera = null; effects = null; wakes = null
	_environment = null; _sun = null; _height = Callable(); _water = Callable()
	_ports.clear(); _snapshot.clear(); _battle_id = ""; _camera_ready = false
	_pending_crew_entries.clear()
	_local_presentation_seconds.clear()

func _exit_tree() -> void: dispose()
