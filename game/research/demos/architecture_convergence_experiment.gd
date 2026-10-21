extends Node3D
## Paired production authorities. The laboratory host is the sole frame caller.
const Encounter = preload("res://modules/naval_simulation/encounter.gd")
const Simulation = preload("res://game/runtime/sailing_simulation.gd")
const Coastal = preload("res://modules/physics_engine/ocean/coastal_wave_field.gd")
const Descriptors = preload("res://modules/contracts/wave_descriptor.gd")
const Types = preload("res://modules/contracts/physics_types.gd")
const Ship = preload("res://game/presentation/ships/ship_view.gd")
const Ocean = preload("res://modules/scene_engine/ocean/projected_ocean.gd")
const Shore = preload("res://modules/scene_engine/ocean/shore_field.gd")
const TOPIC := "architecture-convergence-2026-10-21"
const STEP := 1.0 / 60.0
const SEED := 1661
const KINDS := ["fuchuan","fisherman","patrol","merchant","voc","heavy"]
const DEFAULTS := {"kind":"fuchuan","depth":4.0,"variant":"scalar","interpolation":true,"camera_mode":"side","paused":false}
const SCOPE := "Paired production Encounter/SailingSimulation and coastal wave samplers, one observed real ShipView, production five-wave ocean. Full baseline retains discarded gradient/normal work; scalar candidate requests height only. Same seed/commands/60Hz. Counts cover water sampler terrain calls only; shoreline checks, renderer and full-game FPS are outside the metric. No campaign/save/settings writes or additional demo RNG; production environment remains seeded. Crew and combat are omitted from this isolated workload. GPU appearance is not validated by headless contracts."
var _options := DEFAULTS.duplicate(true)
var _configured := false
var _ready_experiment := false
var _disposed := false
var _reason := ""
var _world: Node3D
var _camera: Camera3D
var _ship: Node3D
var _ocean: MeshInstance3D
var _shore: RefCounted
var _overlay: Label
var _baseline: RefCounted
var _candidate: RefCounted
var _full_ground: RefCounted
var _scalar_ground: RefCounted
var _full_surface: RefCounted
var _scalar_surface: RefCounted
var _presented: Dictionary = {}
var _tick := 0
var _exact := true
var _orbit_yaw := 0.0
var _orbit_pitch := 0.0
var _zoom := 1.0

class CountedGround:
	extends RefCounted
	var depth := 4.0
	var calls := 0
	func sample_height(_x: float, _z: float) -> float:
		calls += 1
		return -depth

class FullSurface:
	extends RefCounted
	var coastal: RefCounted
	var full_calls := 0
	func sample(x: float, z: float, seconds: float) -> Dictionary:
		full_calls += 1
		return coastal.sample(x, z, seconds)

class ScalarSurface:
	extends FullSurface
	var height_calls := 0
	func sample_height(x: float, z: float, seconds: float) -> float:
		height_calls += 1
		return coastal.sample_height(x, z, seconds)

func _ready() -> void:
	set_process(false); set_physics_process(false)
	if _configured and not _disposed: _build()

func get_default_options() -> Dictionary: return DEFAULTS.duplicate(true)

func _validate(options: Dictionary) -> bool:
	for key: String in options:
		if not DEFAULTS.has(key): return false
	return options.kind in KINDS and options.depth in [4.0,24.0] and options.variant in ["full","scalar"] and options.interpolation is bool and options.camera_mode in ["side","high"] and options.paused is bool

func configure(options: Dictionary) -> Dictionary:
	var candidate := DEFAULTS.duplicate(true); candidate.merge(options.duplicate(true),true)
	if not _validate(candidate): return {"ok":false,"reason":"unsupported-architecture-factor","ready":_ready_experiment,"pending":false}
	dispose()
	_options = candidate; _configured = true; _disposed = false; _reason = ""; _tick = 0; _exact = true; _presented.clear()
	_orbit_yaw = 0.0; _orbit_pitch = 0.0; _zoom = 1.0
	if is_inside_tree(): _build()
	return {"ok":_reason.is_empty(),"ready":_ready_experiment,"pending":not is_inside_tree(),"reason":_reason}

func reset_experiment(options: Dictionary = {}) -> Dictionary:
	var observer := {"yaw":_orbit_yaw,"pitch":_orbit_pitch,"zoom":_zoom}
	var candidate := _options.duplicate(true); candidate.merge(options.duplicate(true),true)
	var result := configure(candidate)
	if result.ok and not options.has("camera_mode"):
		_orbit_yaw = observer.yaw; _orbit_pitch = observer.pitch; _zoom = observer.zoom; _refresh()
	return result

func control_spec() -> Array:
	return [
		{"id":"variant","label":"观察采样路径","type":"choice","value":_options.variant,"choices":[{"value":"full","label":"基线：完整波面"},{"value":"scalar","label":"候选：仅取水位"}]},
		{"id":"interpolation","label":"渲染插值（不改物理）","type":"toggle","value":_options.interpolation},
		{"id":"kind","label":"真实船型（重置）","type":"choice","value":_options.kind,"choices":[{"value":"fuchuan","label":"福船"},{"value":"fisherman","label":"渔舟"},{"value":"patrol","label":"巡逻船"},{"value":"merchant","label":"商船"},{"value":"voc","label":"荷兰商船"},{"value":"heavy","label":"重舰"}]},
		{"id":"depth","label":"固定水深（重置）","type":"choice","value":_options.depth,"choices":[{"value":4.0,"label":"浅水 4m"},{"value":24.0,"label":"深水 24m"}]},
		{"id":"camera_mode","label":"固定镜头","type":"choice","value":_options.camera_mode,"choices":[{"value":"side","label":"侧面跟船"},{"value":"high","label":"俯视"}]}
	]

func set_parameter(id: String, value: Variant) -> Dictionary:
	if id not in ["variant","interpolation","kind","depth","camera_mode"]: return {"ok":false,"reason":"unknown-parameter"}
	var candidate := _options.duplicate(true); candidate[id] = value
	if not _validate(candidate): return {"ok":false,"reason":"unsupported-architecture-factor"}
	if id in ["kind","depth"]: return {"ok":true,"value":value,"reset_required":value != _options[id]}
	_options = candidate
	if id == "camera_mode": _orbit_yaw = 0.0; _orbit_pitch = 0.0; _zoom = 1.0
	_refresh()
	return {"ok":true,"value":value,"reset_required":false}

func _ground(_x: float, _z: float) -> float: return -float(_options.depth)

func _new_simulation(scalar: bool) -> Dictionary:
	var ground := CountedGround.new(); ground.depth = float(_options.depth)
	var coastal := Coastal.new()
	if not coastal.configure(ground.sample_height): return {"ok":false,"reason":"coastal-fixture-failed"}
	var surface: RefCounted = ScalarSurface.new() if scalar else FullSurface.new(); surface.coastal = coastal
	var native := Encounter.new({"mode":"continuous","referenceHandling":true,"seed":SEED,"battleId":"architecture-laboratory","playerId":"player","controllableShipIds":["player"],"hostileTargets":{},"waveSampler":surface,"oceanWaves":Descriptors.original_descriptors(),"sampleTerrainHeight":_ground,"wind":{"direction":{"x":-0.8,"y":-0.6},"speed":14.0},"ships":[{"id":"player","name":"计数对照船","kind":_options.kind,"team":"player","position":{"x":0.0,"z":0.0},"heading":0.45,"speed":2.0,"sailDeployment":0.0}]})
	if not native.last_error.is_empty(): return {"ok":false,"reason":native.last_error}
	var simulation := Simulation.new(native); simulation.set_handling_mode("assisted"); simulation.set_sails(0.85); simulation.set_paused(_options.paused)
	ground.calls = 0; surface.full_calls = 0
	if scalar: surface.height_calls = 0
	return {"ok":true,"simulation":simulation,"ground":ground,"surface":surface}

func _build() -> void:
	var full := _new_simulation(false); var scalar := _new_simulation(true)
	if not full.ok or not scalar.ok: _reason = full.get("reason",scalar.get("reason","simulation-failed")); return
	_baseline = full.simulation; _candidate = scalar.simulation
	_full_ground = full.ground; _scalar_ground = scalar.ground; _full_surface = full.surface; _scalar_surface = scalar.surface
	_world = Node3D.new(); _world.name = "ArchitectureExperimentWorld"; add_child(_world)
	var environment := WorldEnvironment.new(); var settings := Environment.new(); environment.environment = settings
	settings.background_mode = Environment.BG_COLOR; settings.background_color = Color("85aebd")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; settings.ambient_light_color = Color("b8d2df"); settings.ambient_light_energy = 0.7
	_world.add_child(environment)
	var light := DirectionalLight3D.new(); light.rotation_degrees = Vector3(-55,-30,0); light.light_energy = 1.4; _world.add_child(light)
	_camera = Camera3D.new(); _camera.name = "Camera"; _camera.current = true; _camera.fov = 50.0; _camera.near = 0.3; _camera.far = 1800.0; _world.add_child(_camera)
	_ship = Ship.new(); _ship.name = "ObservedProductionShip"; _world.add_child(_ship)
	if not _ship.configure(_options.kind): dispose(); _reason = "production-ship-unavailable"; return
	_presented = _candidate.snapshot(); _update_camera()
	_ocean = Ocean.new(); _ocean.name = "ProductionOcean"; _world.add_child(_ocean)
	_ocean.configure(_camera,load("res://assets/textures/waternormals.jpg"),64,1500.0)
	_ocean.set_visual_style(1); _ocean.set_surface_quality("balanced"); _ocean.enable_surface_optics(true); _ocean.configure_reflection(_camera)
	_shore = Shore.new()
	if not _shore.configure(_ground,Rect2(-1024,-1024,2048,2048),32): dispose(); _reason = "depth-texture-unavailable"; return
	_ocean.set_shore_field(_shore.get_texture(),_shore.get_bounds(),_shore.get_coast_texture())
	var sky_material: ShaderMaterial = _ocean.get_sky_material()
	if sky_material != null:
		var sky := Sky.new(); sky.sky_material = sky_material; settings.sky = sky; settings.background_mode = Environment.BG_SKY
	var overlay := CanvasLayer.new(); _world.add_child(overlay)
	_overlay = Label.new(); _overlay.position = Vector2(12,12); _overlay.add_theme_font_size_override("font_size",16); _overlay.add_theme_color_override("font_color",Color.WHITE); _overlay.add_theme_color_override("font_shadow_color",Color("142730")); _overlay.add_theme_constant_override("shadow_offset_x",1); _overlay.add_theme_constant_override("shadow_offset_y",1); overlay.add_child(_overlay)
	_ready_experiment = true; _refresh()

func advance(delta: float) -> void:
	refresh_viewport()
	if not _ready_experiment or _disposed or _options.paused or not is_finite(delta) or delta <= 0.0: return
	_baseline.advance(delta); _candidate.advance(delta)
	_tick = _candidate.current_tick()
	_exact = _exact and _baseline.snapshot() == _candidate.snapshot()
	_refresh()

func set_paused(value: bool) -> void:
	_options.paused = value
	if _baseline: _baseline.set_paused(value)
	if _candidate: _candidate.set_paused(value)
	_refresh()

func refresh_viewport() -> void:
	if _ready_experiment and is_instance_valid(_ocean): _ocean.update_projection()

func set_camera_mode(value: String) -> void: set_parameter("camera_mode",value)

func orbit_camera(yaw_delta: float, pitch_delta: float) -> void:
	if not is_finite(yaw_delta) or not is_finite(pitch_delta): return
	_orbit_yaw = fposmod(_orbit_yaw + yaw_delta,TAU); _orbit_pitch = clampf(_orbit_pitch + pitch_delta,-0.15,0.8); _refresh()

func zoom_camera(amount: float) -> void:
	if not is_finite(amount): return
	_zoom = clampf(_zoom * exp(clampf(amount,-1.0,1.0)),0.6,2.5); _refresh()

func _refresh() -> void:
	if not _ready_experiment or _disposed: return
	var simulation: RefCounted = _baseline if _options.variant == "full" else _candidate
	_presented = simulation.render_snapshot() if _options.interpolation else simulation.snapshot()
	var ship: Dictionary = Simulation._ship(_presented,"player"); ship.time = _presented.time
	_ship.apply_snapshot(ship,_presented.wind,0.0)
	_update_camera(); _ocean.set_simulation_time(float(_presented.time)); _ocean.update_projection()
	_overlay.text = "%s · %s\n权威 60Hz：%d 步 / %.3f s · 显示 %.3f s\n水位地形查询：full %d / scalar %d · 精确状态 %s\n同种真实船体、同一五波水面；重置清零计数。\nGPU 对照已留证；此处计数不代表整场 FPS。" % ["完整波面对照" if _options.variant == "full" else "仅取水位候选","生产渲染插值" if _options.interpolation else "固定步姿态",_tick,_candidate.current_time(),float(_presented.time),_full_ground.calls,_scalar_ground.calls,"相同" if _exact else "不一致"]

func _update_camera() -> void:
	if not is_instance_valid(_camera) or _presented.is_empty(): return
	var ship: Dictionary = Simulation._ship(_presented,"player")
	if ship.is_empty(): return
	var p: Dictionary = ship.visual.position
	var focus := Vector3(p.x,p.y + 2.0,p.z)
	var distance := maxf(35.0,float(Types.ship_spec(_options.kind).length) * 1.5)
	var offset := Vector3(distance * 0.7,distance * 0.4,distance * 0.9) if _options.camera_mode == "side" else Vector3(0.0,distance * 1.4,distance * 0.25)
	offset = offset.rotated(Vector3.UP,_orbit_yaw)
	var right := Vector3.UP.cross(offset).normalized()
	offset = offset.rotated(right,_orbit_pitch) * _zoom
	_camera.position = focus + offset; _camera.position.y = maxf(5.0,_camera.position.y); _camera.look_at(focus)

static func _matrix(value: Projection) -> Array:
	var result: Array = []
	for column: Vector4 in [value.x,value.y,value.z,value.w]: result.append_array([column.x,column.y,column.z,column.w])
	return result

func inspection_snapshot() -> Dictionary:
	var full: Dictionary = _baseline.snapshot() if _baseline else {}
	var scalar: Dictionary = _candidate.snapshot() if _candidate else {}
	var state := {"topic":TOPIC,"ready":_ready_experiment,"disposed":_disposed,"reason":_reason,"parameters":_options.duplicate(true),"paused":_options.paused,"tick":_tick,"time":scalar.get("time",0.0),"render_time":_presented.get("time",0.0),"fixed_step":STEP,"seed":SEED,"rng_state":"seeded production WeatherState; no demo RNG","actual_inputs":{"sail_intent":0.85,"handling":"assisted","wind":{"x":-0.8,"z":-0.6,"speed_mps":14.0}},"baseline":full,"candidate":scalar,"counts":{"full_terrain":_full_ground.calls if _full_ground else 0,"scalar_terrain":_scalar_ground.calls if _scalar_ground else 0,"full_samples":_full_surface.full_calls if _full_surface else 0,"scalar_samples":_scalar_surface.height_calls if _scalar_surface else 0,"candidate_full_samples":_scalar_surface.full_calls if _scalar_surface else 0},"camera_controls":{"orbit_yaw":_orbit_yaw,"orbit_pitch":_orbit_pitch,"zoom":_zoom},"camera_transform":[],"camera_projection":[],"resources":{"world":1 if is_instance_valid(_world) else 0,"ship":1 if is_instance_valid(_ship) else 0,"ocean":1 if is_instance_valid(_ocean) else 0,"simulations":int(_baseline != null) + int(_candidate != null)},"surface":{"shader":"","wave_count":0,"shallow_field":false},"telemetry":{"exact":_exact,"accepted_hz":60,"counts_scope":"coastal sampler depth calls only; cumulative since reset"},"scope":SCOPE}
	if _ready_experiment:
		state.camera_transform = _matrix(Projection(_camera.global_transform)); state.camera_projection = _matrix(_camera.get_camera_projection())
		var material: ShaderMaterial = _ocean.material_override
		state.surface = {"shader":material.shader.resource_path,"wave_count":material.get_shader_parameter("wave_count"),"shallow_field":material.get_shader_parameter("has_shore_field"),"simulation_time":material.get_shader_parameter("simulation_time"),"u_time":material.get_shader_parameter("u_time")}
	return state

func dispose() -> void:
	_ready_experiment = false; _disposed = true
	if _baseline: _baseline.set_paused(true)
	if _candidate: _candidate.set_paused(true)
	_baseline = null; _candidate = null; _full_ground = null; _scalar_ground = null; _full_surface = null; _scalar_surface = null
	if is_instance_valid(_ship): _ship.dispose()
	if is_instance_valid(_ocean): _ocean.set_visual_style(0)
	if is_instance_valid(_world): _world.free()
	_world = null; _ship = null; _camera = null; _ocean = null; _overlay = null; _shore = null

func _exit_tree() -> void: dispose()
