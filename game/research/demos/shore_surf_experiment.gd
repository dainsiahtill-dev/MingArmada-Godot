extends Node3D
## Isolated actual Xiamen terrain and the existing three surf presentation seams.
## Host owns time. No new water shader, source controller or terrain equation.
const Height = preload("res://modules/scene_engine/terrain/height_field.gd")
const Geography = preload("res://game/scenes/common/reference_geography.gd")
const NaturalWorld = preload("res://modules/scene_engine/terrain/natural_world.gd")
const Ocean = preload("res://modules/scene_engine/ocean/projected_ocean.gd")
const ShoreField = preload("res://modules/scene_engine/ocean/shore_field.gd")
const Waves = preload("res://modules/contracts/wave_descriptor.gd")
const STEP := 1.0 / 32.0
const MAX_CATCHUP := 8
const CAMERAS := ["close", "wide"]
const FACTORS := ["analytic", "source", "residue"]
const DEFAULTS := {"camera_mode":"close","paused":false,"analytic_enabled":true,"source_enabled":true,"residue_enabled":true,"analytic_opacity":1.0,"source_opacity":1.0,"residue_opacity":1.0,"quality":"balanced","orbit_yaw":0.0,"orbit_pitch":0.0,"zoom":1.0}
const SCOPE := "Independent actual production Xiamen island: seed1661, 257x257 Float32 triangle terrain; NaturalWorld terrain/source surf, ProjectedOcean five waves and reference_game_water shader, ShoreField512 and exact local terrain-height texture. No fleet, crew, towns, vegetation, atmosphere or shore spray. Three existing presentation seams: analytic advancing fronts (including their tail/contact lace), source short fronts and ocean edge residue/contact lace. coastal_breaker_strength multiplies the analytic front+tail+lace; shoreline_residue_strength controls both edge foam and lace inside that analytic term. These factors have native multiplicative coupling, not three mathematically independent layers. Source heads stay reanchored to the same ocean phase; this is not a second independent trajectory or a complete old-version renderer. Each source sprite also contains its authored thin tail. This isolated scene does not establish full-game FPS, ship occlusion or shoal coverage."

var _options: Dictionary = DEFAULTS.duplicate(true)
var _has_configuration := false
var _ready_experiment := false
var _disposed := false
var _reason := ""
var _root: Node3D
var _terrain: Node3D
var _surf: Node3D
var _ocean: MeshInstance3D
var _camera: Camera3D
var _heights: RefCounted
var _shore_field: RefCounted
var _near_texture: ImageTexture
var _terrain_fingerprint := ""
var _source_seed := 0
var _source_updates := 0
var _focus := Vector3.ZERO
var _outward := Vector3.RIGHT
var _island_center := Vector3(-480.0,5.0,-60.0)
var _tick := 0
var _accumulator := 0.0

func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	if _has_configuration and not _disposed:
		_build_experiment()

func get_default_options() -> Dictionary:
	return DEFAULTS.duplicate(true)

func control_spec() -> Array:
	var result: Array = [{"id":"camera_mode","label":"岸线镜头","type":"choice","value":_options.camera_mode,"choices":[{"value":"close","label":"近岸浪头"},{"value":"wide","label":"整岛岸线"}]}]
	var labels := {"analytic":"解析推进浪与尾沫","source":"源短浪与薄尾","residue":"岸边残沫与接触花边"}
	for factor: String in FACTORS:
		result.append({"id":factor+"_enabled","label":labels[factor],"type":"toggle","value":_options[factor+"_enabled"]})
		result.append({"id":factor+"_opacity","label":labels[factor]+("透明度" if factor=="source" else "展示强度"),"type":"range","value":_options[factor+"_opacity"],"min":0.0,"max":1.0,"step":0.05})
	return result

func _validate(candidate: Dictionary) -> String:
	for key: Variant in candidate:
		if not key is String or not DEFAULTS.has(key): return "unknown-option"
	if not candidate.camera_mode is String or candidate.camera_mode not in CAMERAS: return "invalid-camera_mode"
	if not candidate.quality is String or candidate.quality not in ["low","balanced","high"]: return "invalid-quality"
	if not candidate.paused is bool: return "invalid-paused"
	for factor: String in FACTORS:
		if not candidate[factor+"_enabled"] is bool: return "invalid-"+factor+"_enabled"
		var value: Variant = candidate[factor+"_opacity"]
		if not _number(value) or float(value)<0.0 or float(value)>1.0: return "invalid-"+factor+"_opacity"
	for key: String in ["orbit_yaw","orbit_pitch","zoom"]:
		if not _number(candidate[key]): return "invalid-"+key
	if float(candidate.zoom)<0.6 or float(candidate.zoom)>2.5: return "invalid-zoom"
	if float(candidate.orbit_pitch)<-0.25 or float(candidate.orbit_pitch)>0.8: return "invalid-orbit_pitch"
	return ""

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func configure(options: Dictionary) -> Dictionary:
	var candidate: Dictionary = DEFAULTS.duplicate(true)
	candidate.merge(options.duplicate(true),true)
	var error := _validate(candidate)
	if not error.is_empty(): return {"ok":false,"ready":_ready_experiment,"pending":false,"reason":error}
	candidate.orbit_yaw = fposmod(float(candidate.orbit_yaw),TAU)
	dispose()
	_options = candidate
	_has_configuration = true
	_disposed = false
	_reason = ""
	_tick = 0
	_accumulator = 0.0
	_source_updates = 0
	set_process(false)
	set_physics_process(false)
	if is_inside_tree(): _build_experiment()
	return {"ok":_reason.is_empty(),"ready":_ready_experiment,"pending":not is_inside_tree(),"reason":_reason,"options":_options.duplicate(true)}

func reset_experiment(options: Dictionary = {}) -> Dictionary:
	var candidate := _options.duplicate(true)
	candidate.merge(options.duplicate(true),true)
	return configure(candidate)

func set_parameter(id: String, value: Variant) -> Dictionary:
	if not DEFAULTS.has(id): return {"ok":false,"reason":"unknown-parameter"}
	var candidate := _options.duplicate(true)
	candidate[id] = value
	var error := _validate(candidate)
	if not error.is_empty(): return {"ok":false,"reason":error}
	if id == "quality": return {"ok":false,"reset_required":true,"reason":"quality-requires-explicit-reset"}
	if id == "camera_mode":
		set_camera_mode(value)
	else:
		_options = candidate
		if id in ["orbit_yaw","orbit_pitch","zoom"]: _redraw_camera()
		else: _apply_layers()
	return {"ok":true,"ready":_ready_experiment,"parameters":_options.duplicate(true)}

func set_paused(value: bool) -> void:
	_options.paused = value

func set_camera_mode(value: String) -> void:
	if value not in CAMERAS: return
	_options.camera_mode = value
	_options.orbit_yaw = 0.0
	_options.orbit_pitch = 0.0
	_options.zoom = 1.0
	_redraw_camera()

func orbit_camera(yaw_delta: float, pitch_delta: float) -> void:
	if not is_finite(yaw_delta) or not is_finite(pitch_delta): return
	_options.orbit_yaw = fposmod(float(_options.orbit_yaw)+yaw_delta,TAU)
	_options.orbit_pitch = clampf(float(_options.orbit_pitch)+pitch_delta,-0.25,0.8)
	_redraw_camera()

func zoom_camera(amount: float) -> void:
	if not is_finite(amount): return
	_options.zoom = clampf(float(_options.zoom)*exp(clampf(amount,-1.0,1.0)),0.6,2.5)
	_redraw_camera()

func advance(delta: float) -> void:
	if not _ready_experiment or _disposed or _options.paused or not is_finite(delta) or delta<=0.0: return
	_accumulator += minf(delta,STEP*MAX_CATCHUP)
	var accepted := 0
	while _accumulator+1.0e-12>=STEP and accepted<MAX_CATCHUP:
		_tick += 1
		_apply_time()
		_accumulator -= STEP
		accepted += 1

func _build_experiment() -> void:
	_root = Node3D.new()
	_root.name = "ShoreExperimentWorld"
	add_child(_root)
	_heights = Height.new()
	var geography: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/reference/mingqi-geography.json"))
	if not geography is Dictionary or not geography.get("ports") is Array:
		_fail("geography-unavailable")
		return
	var ports: Array = []
	for port: Dictionary in geography.ports:
		if port.id == "xiamen": ports.append(port.duplicate(true))
	if ports.size()!=1 or not _heights.configure_ports(ports,false,Geography.options()):
		_fail("accepted-terrain-configuration-failed")
		return
	var grids: Array = _heights.natural_terrain_grids()
	var grid: Dictionary = grids[0].field.get_grid()
	_terrain_fingerprint = var_to_bytes({"bounds":grid.bounds,"side":grid.side,"heights":grid.heights}).hex_encode().sha256_text()
	# Exact production seed expression. Its local generator is discarded after
	# configure; no current RNG state exists to export during accepted updates.
	_source_seed = hash([grid.bounds.position,grid.bounds.size,grid.side,grid.heights])
	_terrain = NaturalWorld.new()
	_terrain.name = "AcceptedNaturalIsland"
	_root.add_child(_terrain)
	if not _terrain.configure(grids,_heights.sample_height,{"vegetation":false,"shore_surf":true}):
		_fail("natural-world-configuration-failed")
		return
	var shores: Array = _terrain.get("_dynamic_shore")
	if shores.size()!=1:
		_fail("source-shore-owner-unavailable")
		return
	_surf = shores[0]
	# Eastmost real shore patch gives a reproducible view facing the terrain.
	var packets: Array = _surf.get("_packets")
	var selected: Dictionary = packets[0]
	for packet: Dictionary in packets:
		if packet.center.x>selected.center.x: selected = packet
	var center: Vector2 = selected.center
	var outward: Vector2 = selected.outward
	_focus = Vector3(center.x,0.0,center.y)+Vector3(outward.x,0.0,outward.y)*6.0
	_outward = Vector3(outward.x,0.0,outward.y)
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_root.add_child(_camera)
	_camera.fov = 45.0
	_camera.near = 0.1
	_camera.far = 3000.0
	_camera.current = true
	_redraw_camera()
	_ocean = Ocean.new()
	_ocean.name = "Ocean"
	_root.add_child(_ocean)
	_ocean.configure(_camera,load("res://assets/textures/waternormals.jpg"),80,3000.0)
	_ocean.set_surface_quality(_options.quality)
	_ocean.set_wave_descriptors(Waves.original_descriptors())
	_ocean.set_visual_style(1)
	_ocean.configure_reflection(_camera)
	_ocean.enable_surface_optics(true)
	_ocean.set_projection_padding(0.10)
	_ocean.set_surface_wind(Vector2(-1.0,0.0),12.0)
	_shore_field = ShoreField.new()
	var bounds: Rect2 = grid.bounds.grow(100.0)
	if not _shore_field.configure(_heights.sample_height,bounds,512):
		_fail("coast-field-configuration-failed")
		return
	_ocean.set_shore_field(_shore_field.get_texture(),_shore_field.get_bounds(),_shore_field.get_coast_texture())
	var image := Image.create_from_data(grid.side,grid.side,false,Image.FORMAT_RF,grid.heights.to_byte_array())
	_near_texture = ImageTexture.create_from_image(image)
	var local: Rect2 = grid.bounds
	_ocean.set_near_shore_field(_near_texture,Vector4(local.position.x,local.position.y,local.end.x,local.end.y))
	var material := _ocean.material_override as ShaderMaterial
	material.set_shader_parameter("mask_dry_terrain",true)
	material.set_shader_parameter("surface_visual_scale",1.0)
	material.set_shader_parameter("display_fog_density",0.00035)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	var sky := Sky.new()
	sky.sky_material = _ocean.get_sky_material()
	settings.sky = sky
	settings.background_mode = Environment.BG_SKY
	settings.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(0.35,0.40,0.30)
	settings.ambient_light_energy = 0.65
	settings.fog_enabled = false
	environment.environment = settings
	_root.add_child(environment)
	_camera.environment = settings
	_ready_experiment = true
	_apply_time()

func _fail(reason: String) -> void:
	dispose()
	_reason = reason

func _apply_time() -> void:
	if not _ready_experiment: return
	var seconds := _tick*STEP
	_ocean.set_simulation_time(seconds)
	_terrain.sync_surface_state(_ocean.material_override as ShaderMaterial,{"time":seconds})
	_terrain.apply_snapshot({"time":seconds},0.0)
	_source_updates += 1
	_apply_layers()

func _effective(factor: String) -> float:
	return float(_options[factor+"_opacity"]) if _options[factor+"_enabled"] else 0.0

func _apply_layers() -> void:
	if not is_instance_valid(_ocean) or not is_instance_valid(_surf): return
	var material := _ocean.material_override as ShaderMaterial
	material.set_shader_parameter("coastal_breaker_strength",0.36*_effective("analytic"))
	material.set_shader_parameter("shoreline_residue_strength",0.38*_effective("residue"))
	_surf.visible = _options.source_enabled
	# Scale only current submitted alpha; never call source controllers again.
	var states: Array = _surf.get("_states")
	var materials: Array = _surf.get("_materials")
	for i in states.size():
		materials[i].set_shader_parameter("controller_alpha",float(states[i].visibleAlpha)*_effective("source"))

func _redraw_camera() -> void:
	if not is_instance_valid(_camera): return
	var focus := _focus if _options.camera_mode == "close" else _island_center
	var offset := _outward*90.0+Vector3.UP*45.0 if _options.camera_mode == "close" else _outward*330.0+Vector3.UP*230.0
	offset = offset.rotated(Vector3.UP,float(_options.orbit_yaw))
	var horizontal := Vector2(offset.x,offset.z).length()
	var elevation := clampf(atan2(offset.y,horizontal)+float(_options.orbit_pitch),0.08,1.4)
	var direction := Vector3(offset.x,0.0,offset.z).normalized()
	offset = (direction*cos(elevation)+Vector3.UP*sin(elevation))*offset.length()*float(_options.zoom)
	_camera.position = focus+offset
	# Orbit may face inland; maintain a valid observer above actual terrain.
	if _heights != null:
		_camera.position.y = maxf(_camera.position.y,float(_heights.sample_height(_camera.position.x,_camera.position.z))+4.0)
	_camera.look_at(focus)
	if is_instance_valid(_ocean): _ocean.update_projection()

static func _matrix_values(value: Projection) -> Array:
	var result: Array = []
	for column: Vector4 in [value.x,value.y,value.z,value.w]:
		result.append_array([column.x,column.y,column.z,column.w])
	return result

func inspection_snapshot() -> Dictionary:
	var resources := {"world":1 if is_instance_valid(_root) else 0,"terrain":1 if is_instance_valid(_terrain) else 0,"source_surf":1 if is_instance_valid(_surf) else 0,"source_patches":_surf.get_child_count() if is_instance_valid(_surf) else 0,"ocean":1 if is_instance_valid(_ocean) else 0,"camera":1 if is_instance_valid(_camera) else 0,"shore_field":1 if _shore_field != null else 0,"near_texture":1 if _near_texture != null else 0,"offscreen_targets":0,"ships":0}
	var telemetry := {"terrain_seed":1661,"terrain_resolution":257,"shore_field_resolution":512,"terrain_fingerprint":_terrain_fingerprint,"source_seed":_source_seed,"source_seed_decimal":str(_source_seed),"rng_state_retained":false,"rng_state_policy":"Production NaturalShoreSurf creates a grid-seeded local RNG only at configure then discards it. Accepted-time sampling, visibility and cameras use no RNG; no current source RNG state exists.","source_updates":_source_updates,"geometry_builds":0,"source":{},"layers":{},"sample_period":STEP,"source_controller_period_seconds":29.96666717529297}
	if is_instance_valid(_terrain): telemetry.geometry_builds = _terrain.get("_geometry_builds")
	if is_instance_valid(_surf):
		telemetry.source = _surf.diagnostics()
		var source_error := 0.0
		var states: Array = _surf.get("_states")
		var materials: Array = _surf.get("_materials")
		for i in states.size():
			source_error = maxf(source_error,absf(float(materials[i].get_shader_parameter("controller_alpha"))-float(states[i].visibleAlpha)*_effective("source")))
		telemetry.layers.source = {"enabled":_options.source_enabled,"opacity":_options.source_opacity,"effective_opacity":_effective("source"),"carrier_visible":_surf.visible,"bound_alpha_error":source_error,"seam":"NaturalShoreSurf controller_alpha and owner visibility"}
	if is_instance_valid(_ocean):
		var material := _ocean.material_override as ShaderMaterial
		for factor: String in ["analytic","residue"]:
			var key := "coastal_breaker_strength" if factor=="analytic" else "shoreline_residue_strength"
			telemetry.layers[factor] = {"enabled":_options[factor+"_enabled"],"opacity":_options[factor+"_opacity"],"effective_opacity":_effective(factor),"bound_strength":material.get_shader_parameter(key),"seam":key}
		telemetry.ocean_shader = material.shader.resource_path
		telemetry.optics = _ocean.get_surface_optics_diagnostics()
		resources.offscreen_targets = telemetry.optics.offscreen_targets
	var result := {"ready":_ready_experiment,"disposed":_disposed,"reason":_reason,"topic":"shore-surf","time":_tick*STEP,"tick":_tick,"fixed_step":STEP,"paused":_options.paused,"camera_mode":_options.camera_mode,"parameters":_options.duplicate(true),"resources":resources,"scope":SCOPE,"telemetry":telemetry,"camera_transform":[],"camera_projection":[],"viewport_size":[],"quality":_options.quality}
	if is_instance_valid(_camera):
		result.camera_position = _camera.global_position
		result.camera_transform = _matrix_values(Projection(_camera.get_camera_transform()))
		result.camera_projection = _matrix_values(_camera.get_camera_projection())
		result.camera_parameters = {"projection":_camera.projection,"fov":_camera.fov,"near":_camera.near,"far":_camera.far,"size":_camera.size,"keep_aspect":_camera.keep_aspect,"cull_mask":_camera.cull_mask}
		var dimensions: Vector2 = _camera.get_viewport().get_visible_rect().size
		result.viewport_size = [int(dimensions.x),int(dimensions.y)]
	return result

func dispose() -> void:
	_ready_experiment = false
	_disposed = true
	if is_instance_valid(_terrain): _terrain.dispose()
	if is_instance_valid(_ocean):
		var renderer: Node3D = _ocean.get("_reference_renderer")
		if is_instance_valid(renderer): renderer.dispose()
	if is_instance_valid(_root): _root.free()
	_root = null
	_terrain = null
	_surf = null
	_ocean = null
	_camera = null
	_heights = null
	_shore_field = null
	_near_texture = null
	_accumulator = 0.0

func _exit_tree() -> void:
	dispose()
