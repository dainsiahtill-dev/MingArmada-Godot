extends Node3D
## Independent research owner. Host calls advance; production algorithms stay shared.
## configure may precede tree attachment: options validate immediately and _ready
## builds synchronously. Its pending receipt does not claim resources are ready.
const Ship = preload("res://game/presentation/ships/ship_view.gd")
const Crew = preload("res://game/presentation/crew/crew_view.gd")
const Packet = preload("res://game/presentation/world/source_water_packet.gd")
const Ocean = preload("res://modules/scene_engine/ocean/projected_ocean.gd")
const Runtime = preload("res://game/runtime/sailing_runtime.gd")
const WakeRenderer = preload("res://modules/scene_engine/water/source_wake_renderer.gd")
const STEP := 1.0 / 32.0
const MAX_CATCHUP := 8
const KINDS := ["fuchuan", "fisherman", "merchant", "voc", "patrol", "heavy"]
const SCENARIOS := ["cruise", "slow", "turn", "stop", "reentry"]
const CAMERAS := ["side", "front", "high"]
const DEFAULTS := {"kind": "fuchuan", "scenario": "cruise", "camera_mode": "side", "contact_enabled": true, "paused": false, "orbit_yaw": 0.0, "orbit_pitch": 0.0, "zoom": 1.0, "quality": "balanced", "carrier_extent": 1200.0}
const SCOPE := "Production Ship/Crew/WaterPacket/WakeRenderer and SailingRuntime physics; deep open water at -20m. Uniform 1200m PlaneMesh with 512 subdivisions carries unchanged production Ocean material, five waves, reflection, optics and depth. This close-view carrier differs from the game's projected grid. A/B toggles visibility of current local hull-contact foam and spray; same pose, source tail and contact timeline remain. Reentry adds an explicit 2m presentation stress overlay, not a native-physics event. Independent experiment is not full-game FPS or old-version comparison."

var _options: Dictionary = DEFAULTS.duplicate(true)
var _has_configuration := false
var _ready_experiment := false
var _disposed := false
var _reason := ""
var _world: Node3D
var _wake_root: Node3D
var _ship: Node3D
var _crew: Node3D
var _camera: Camera3D
var _ocean: MeshInstance3D
var _runtime: RefCounted
var _renderer: RefCounted
var _contact_container: Node3D
var _native_snapshot: Dictionary = {}
var _display_ship: Dictionary = {}
var _last_packet: Dictionary = {}
var _tick := 0
var _accumulator := 0.0
var _overlay := 0.0
var _orbit_yaw := 0.0
var _orbit_pitch := 0.0
var _zoom := 1.0

func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	if _has_configuration and not _disposed:
		_build_experiment()

func configure(options: Dictionary) -> Dictionary:
	var candidate: Dictionary = DEFAULTS.duplicate(true)
	candidate.merge(options.duplicate(true), true)
	if options.has("case") and not options.has("scenario"):
		candidate.scenario = options["case"]
	if options.has("camera") and not options.has("camera_mode"):
		candidate.camera_mode = options.camera
	for field: String in ["kind", "scenario", "camera_mode"]:
		if not candidate[field] is String:
			return {"ok": false, "ready": _ready_experiment, "pending": false, "reason": "invalid-" + field}
	if candidate.kind not in KINDS or candidate.scenario not in SCENARIOS or candidate.camera_mode not in CAMERAS:
		return {"ok": false, "ready": _ready_experiment, "pending": false, "reason": "unsupported-experiment-option"}
	for field: String in ["paused", "contact_enabled"]:
		if not candidate[field] is bool:
			return {"ok": false, "ready": _ready_experiment, "pending": false, "reason": "invalid-" + field}
	for field: String in ["orbit_yaw", "orbit_pitch", "zoom", "carrier_extent"]:
		var value: Variant = candidate[field]
		if not (value is float or value is int) or not is_finite(float(value)):
			return {"ok": false, "ready": _ready_experiment, "pending": false, "reason": "invalid-" + field}
	if float(candidate.zoom) <= 0.0:
		return {"ok": false, "ready": _ready_experiment, "pending": false, "reason": "invalid-zoom"}
	if not candidate.quality is String or candidate.quality not in ["low", "balanced", "high"]:
		return {"ok": false, "ready": _ready_experiment, "pending": false, "reason": "invalid-quality"}
	if float(candidate.carrier_extent) not in [1200.0, 384.0]:
		return {"ok": false, "ready": _ready_experiment, "pending": false, "reason": "unsupported-carrier-extent"}
	candidate.carrier_extent = float(candidate.carrier_extent)
	candidate.orbit_yaw = fposmod(float(candidate.orbit_yaw), TAU)
	candidate.orbit_pitch = clampf(float(candidate.orbit_pitch), -0.25, 0.8)
	candidate.zoom = clampf(float(candidate.zoom), 0.6, 2.5)
	dispose()
	_options = candidate
	_has_configuration = true
	_disposed = false
	_reason = ""
	_tick = 0
	_accumulator = 0.0
	_overlay = 0.0
	_orbit_yaw = _options.orbit_yaw
	_orbit_pitch = _options.orbit_pitch
	_zoom = _options.zoom
	set_process(false)
	set_physics_process(false)
	if is_inside_tree():
		_build_experiment()
	return {"ok": _reason.is_empty(), "ready": _ready_experiment, "pending": not is_inside_tree(), "reason": _reason, "options": _options.duplicate(true)}

func reset_experiment(options: Dictionary = {}) -> Dictionary:
	var candidate: Dictionary = _options.duplicate(true)
	candidate.merge(options.duplicate(true), true)
	if options.has("case") and not options.has("scenario"):
		candidate.scenario = options["case"]
	if options.has("camera") and not options.has("camera_mode"):
		candidate.camera_mode = options.camera
	return configure(candidate)

func advance(delta: float) -> void:
	if not _ready_experiment or _disposed or _options.paused or not is_finite(delta) or delta <= 0.0:
		return
	# Bound foreground stalls. Retain only the fractional source step; dropped
	# wall-clock duration never becomes unbounded future catch-up work.
	_accumulator += minf(delta, STEP * MAX_CATCHUP)
	var count := 0
	while _accumulator + 1.0e-12 >= STEP and count < MAX_CATCHUP:
		_tick += 1
		if _options.scenario == "turn":
			_runtime.command({"type": "turn", "value": 0.45 if _tick >= 128 else 0.0})
		elif _options.scenario == "stop" and _tick == 128:
			_runtime.command({"type": "sail", "value": 0.0})
		var consumed: float = _runtime.advance(STEP)
		_render_snapshot(consumed)
		_accumulator -= STEP
		count += 1

func set_paused(value: bool) -> void:
	# Demo owns pause gating. Native command("pause") clears rudder intent;
	# avoiding that command preserves current turn state when viewing a pause.
	_options.paused = value

func set_contact_enabled(value: bool) -> void:
	_options.contact_enabled = value
	_apply_contact_visibility()

func set_camera_mode(value: String) -> void:
	if value not in CAMERAS:
		return
	_options.camera_mode = value
	_orbit_yaw = 0.0
	_orbit_pitch = 0.0
	_zoom = 1.0
	_options.orbit_yaw = _orbit_yaw
	_options.orbit_pitch = _orbit_pitch
	_options.zoom = _zoom
	_redraw_camera()

func orbit_camera(yaw_delta: float, pitch_delta: float) -> void:
	if not is_finite(yaw_delta) or not is_finite(pitch_delta):
		return
	_orbit_yaw = fposmod(_orbit_yaw + yaw_delta, TAU)
	_orbit_pitch = clampf(_orbit_pitch + pitch_delta, -0.25, 0.8)
	_options.orbit_yaw = _orbit_yaw
	_options.orbit_pitch = _orbit_pitch
	_redraw_camera()

func zoom_camera(amount: float) -> void:
	if not is_finite(amount):
		return
	_zoom = clampf(_zoom * exp(clampf(amount, -1.0, 1.0)), 0.6, 2.5)
	_options.zoom = _zoom
	_redraw_camera()

func inspection_snapshot() -> Dictionary:
	var time := float(_native_snapshot.get("time", 0.0))
	var result := {"ready": _ready_experiment, "disposed": _disposed, "reason": _reason, "kind": _options.kind, "scenario": _options.scenario, "camera_mode": _options.camera_mode, "paused": _options.paused, "contact_enabled": _options.contact_enabled, "tick": _tick, "time": time, "presentation_time": _tick * STEP, "fixed_step": STEP, "native_step": Runtime.STEP, "native_owner": "SailingRuntime", "native_runtime_id": _runtime.get_instance_id() if _runtime != null else 0, "ship": _display_ship.duplicate(true), "native_ship": _native_snapshot.get("ship", {}).duplicate(true), "diagnostic_overlay_m": _overlay, "scope": SCOPE, "seed_policy": "production WaterPacket: absi('player'.hash()) % 2147483647", "camera_position": _camera.global_position if is_instance_valid(_camera) else Vector3.ZERO, "contact_visible": is_instance_valid(_contact_container) and _contact_container.visible, "tail_visible": false, "tail": {}, "contact": {}, "crew": {}, "resources": {"world": 1 if is_instance_valid(_world) else 0, "ship": 1 if is_instance_valid(_ship) else 0, "crew": 1 if is_instance_valid(_crew) else 0, "ocean": 1 if is_instance_valid(_ocean) else 0, "wake": 1 if _renderer != null else 0, "runtime": 1 if _runtime != null else 0}}
	result.merge(_replay_metadata())
	if _options.carrier_extent == 384.0:
		result.scope = SCOPE.replace("Uniform 1200m PlaneMesh with 512 subdivisions", "Controlled experimental 384m PlaneMesh with 512 subdivisions and only +/-192m local water coverage")
	if is_instance_valid(_crew):
		result.crew = _crew.diagnostics()
	if _renderer != null and _renderer._actors.has("player"):
		var actor: Dictionary = _renderer._actors.player
		result.tail = {"updates": actor.history.updates, "history_fingerprint": var_to_bytes(actor.history.points).hex_encode().sha256_text(), "geometry_fingerprint": var_to_bytes(actor.geometry).hex_encode().sha256_text()}
		for node: MeshInstance3D in actor.surface.nodes.values():
			result.tail_visible = result.tail_visible or node.visible
		if actor.froth != null:
			result.contact = actor.froth.diagnostics()
	return result

func _replay_metadata() -> Dictionary:
	# Plain numeric arrays survive JSON receipts. Matrices use column-major
	# x/y/z/w columns, matching Godot Projection; the affine eye is [12..14].
	var result := {"orbit_yaw": _orbit_yaw, "orbit_pitch": _orbit_pitch, "zoom": _zoom, "quality": _options.quality, "carrier_extent": _options.carrier_extent, "carrier_dimensions_m": [], "carrier_subdivisions": [], "carrier_spacing_m": null, "camera_transform": [], "camera_projection": [], "camera_parameters": {}, "viewport_size": [], "waterpacket_seed": null, "froth_rng_state": null, "froth_rng_state_decimal": "", "replay_scope": "Reset initial state, replay fixed ticks and camera inputs in their original order. Contact LOD changes particle births; current camera and RNG metadata alone are not a complete particle-state restore."}
	if is_instance_valid(_camera):
		result.camera_transform = _matrix_values(Projection(_camera.get_camera_transform()))
		result.camera_projection = _matrix_values(_camera.get_camera_projection())
		result.camera_parameters = {"projection": _camera.projection, "fov": _camera.fov, "near": _camera.near, "far": _camera.far, "size": _camera.size, "keep_aspect": _camera.keep_aspect, "frustum_offset": [_camera.frustum_offset.x, _camera.frustum_offset.y], "h_offset": _camera.h_offset, "v_offset": _camera.v_offset, "cull_mask": _camera.cull_mask}
		var dimensions: Vector2 = _camera.get_viewport().get_visible_rect().size
		result.viewport_size = [int(dimensions.x), int(dimensions.y)]
	if is_instance_valid(_ocean):
		# Its full diagnostics assumes an ArrayMesh, whereas this close-view
		# experiment deliberately uses PlaneMesh. Read the actual quality owner
		# without invoking that unrelated projected-carrier vertex counter.
		var optics: RefCounted = _ocean.get("_surface_optics")
		result.quality = optics.get("quality") if optics != null else _options.quality
		if _ocean.mesh is PlaneMesh:
			var carrier: PlaneMesh = _ocean.mesh
			result.carrier_extent = carrier.size.x
			result.carrier_dimensions_m = [carrier.size.x, carrier.size.y]
			result.carrier_subdivisions = [carrier.subdivide_width, carrier.subdivide_depth]
			result.carrier_spacing_m = float(carrier.size.x) / float(carrier.subdivide_width + 1)
	if not _last_packet.is_empty():
		result.waterpacket_seed = _last_packet.ships[0].sourceWake.froth.seed
	if _renderer != null and _renderer._actors.has("player"):
		var effect: RefCounted = _renderer._actors.player.froth
		var rng: RandomNumberGenerator = effect.get("_rng") if effect != null else null
		if rng != null:
			result.froth_rng_state = rng.state
			# The integer is concrete engine state; decimal text additionally
			# avoids loss when a JSON consumer only supports 53-bit numbers.
			result.froth_rng_state_decimal = str(rng.state)
	return result

static func _matrix_values(value: Projection) -> Array:
	var result: Array = []
	for column: Vector4 in [value.x, value.y, value.z, value.w]:
		result.append_array([column.x, column.y, column.z, column.w])
	return result

func dispose() -> void:
	_ready_experiment = false
	_disposed = true
	if _renderer != null:
		_renderer.dispose()
	_renderer = null
	_contact_container = null
	if is_instance_valid(_crew):
		_crew.dispose()
	if is_instance_valid(_ship):
		_ship.dispose()
	if is_instance_valid(_world):
		_world.free()
	_world = null
	_wake_root = null
	_ship = null
	_crew = null
	_camera = null
	_ocean = null
	_runtime = null
	_native_snapshot.clear()
	_display_ship.clear()
	_last_packet.clear()
	_accumulator = 0.0
	_overlay = 0.0

func _exit_tree() -> void:
	dispose()

func _ground(_x: float, _z: float) -> float:
	return -20.0

func _water(x: float, z: float, time: float) -> float:
	return _runtime.sample_water_height(x, z, time) if _runtime != null else NAN

func _build_experiment() -> void:
	_world = Node3D.new()
	_world.name = "ExperimentWorld"
	add_child(_world)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("87ceeb")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("a0c8ff")
	settings.ambient_light_energy = 0.65
	environment.environment = settings
	_world.add_child(environment)
	var sun := DirectionalLight3D.new()
	_world.add_child(sun)
	sun.rotation_degrees = Vector3(-60.0, -35.0, 0.0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	_runtime = Runtime.new()
	var slow: bool = _options.scenario == "slow"
	if not _runtime.configure(_ground, {"kind": _options.kind, "position": {"x": 0.0, "z": 0.0}, "heading": 0.45, "speed": 0.8 if slow else 3.086, "time": 0.0, "wind": {"direction": {"x": -1.0, "z": 0.3}, "speed": 14.0}, "sailDeployment": 0.2 if slow else 1.0}):
		_fail_build("runtime-configuration-failed")
		return
	_ship = Ship.new()
	_ship.name = "Ship"
	_world.add_child(_ship)
	if not _ship.configure(_options.kind):
		_fail_build("ship-configuration-failed")
		return
	_crew = Crew.new()
	_crew.name = "Crew"
	_world.add_child(_crew)
	if not _crew.configure(_options.kind, _ship.get_model()):
		_fail_build("crew-configuration-failed")
		return
	_crew.set_environment(_water)
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_world.add_child(_camera)
	_camera.current = true
	_camera.fov = 45.0
	_camera.far = 3000.0
	_camera.near = 0.1
	# Give the production projected ocean a nondegenerate initial view before
	# replacing only its carrier with the close-view research plane.
	_camera.position = Vector3(25.0, 5.5, 8.0)
	_camera.look_at(Vector3(0.0, 1.0, 0.0))
	_ocean = Ocean.new()
	_ocean.name = "Ocean"
	_world.add_child(_ocean)
	_ocean.configure(_camera, load("res://assets/textures/waternormals.jpg"), 96, 3000.0)
	_ocean.set_visual_style(1)
	_ocean.set_surface_quality(_options.quality)
	_ocean.set_projection_padding(0.18)
	_ocean.enable_surface_optics(true)
	_ocean.configure_reflection(_camera)
	var carrier := PlaneMesh.new()
	carrier.size = Vector2(_options.carrier_extent, _options.carrier_extent)
	carrier.subdivide_width = 512
	carrier.subdivide_depth = 512
	_ocean.mesh = carrier
	var sky_material: ShaderMaterial = _ocean.get_sky_material()
	if sky_material != null:
		var sky := Sky.new()
		sky.sky_material = sky_material
		settings.sky = sky
		settings.background_mode = Environment.BG_SKY
	_wake_root = Node3D.new()
	_wake_root.name = "WaterEffects"
	_world.add_child(_wake_root)
	_renderer = WakeRenderer.new(_wake_root)
	_ready_experiment = true
	_render_snapshot(0.0)

func _fail_build(reason: String) -> void:
	dispose()
	_reason = reason

func _render_snapshot(consumed: float) -> void:
	_native_snapshot = _runtime.snapshot()
	var time := float(_native_snapshot.time)
	_display_ship = _native_snapshot.ship.duplicate(true)
	_display_ship.id = "player"
	_display_ship.time = time
	_display_ship.crew = 24
	_overlay = 2.0 * smoothstep(2.0, 2.5, time) * (1.0 - smoothstep(3.85, 4.30, time)) if _options.scenario == "reentry" else 0.0
	_display_ship.position.y += _overlay
	_ship.apply_snapshot(_display_ship, _native_snapshot.wind, consumed)
	_crew.global_transform = _ship.get_model().global_transform
	_crew.apply_snapshot(_display_ship, _native_snapshot.wind, consumed)
	_update_camera()
	_ocean.set_simulation_time(time)
	_renderer.apply_snapshot(_compose_packet(), _water, Callable())
	_contact_container = _wake_root.get_node_or_null("SourceWake_player/HullContactFroth")
	_apply_contact_visibility()

func _compose_packet() -> Dictionary:
	# Runtime's accepted 120Hz physics time remains authoritative; experiment
	# sourceCallIndex is independently exact 32Hz cadence, never wall time.
	var environment: Dictionary = _native_snapshot.get("environment", {}).duplicate(true)
	environment.acceptedTime = _native_snapshot.time
	environment.sourceCallIndex = _tick
	environment.route = "sailing"
	_last_packet = Packet.compose({"time": _native_snapshot.time, "environment": environment, "ships": [_display_ship]}, {"player": _ship}, _camera)
	return _last_packet

func _apply_contact_visibility() -> void:
	if is_instance_valid(_contact_container):
		_contact_container.visible = _options.contact_enabled

func _redraw_camera() -> void:
	if not _ready_experiment or _disposed:
		return
	_update_camera()
	# The production ocean also owns a mirror camera. Synchronize its eye and
	# projection at the unchanged accepted time when observing a paused scene.
	_ocean.set_simulation_time(float(_native_snapshot.time))
	# Duplicate accepted source-call index refreshes spray billboards without
	# advancing tail history, RNG, relative-entry state or simulation time.
	_renderer.apply_snapshot(_compose_packet(), _water, Callable())
	_apply_contact_visibility()

func _update_camera() -> void:
	var attachment: Dictionary = _ship.source_water_attachment()
	var profile: Dictionary = attachment.get("surfaceProfile", {})
	if profile.is_empty():
		return
	var local_marker: Vector3 = profile.worldToHull * attachment.bow
	var first := float(profile.sections[0].z)
	var last := float(profile.sections[-1].z)
	var at_first := absf(local_marker.z - first) < absf(local_marker.z - last)
	var forward_sign := -1.0 if at_first else 1.0
	var forward: Vector3 = profile.hullToWorld.basis.z * forward_sign
	forward.y = 0.0
	forward = forward.normalized()
	var right := Vector3(-forward.z, 0.0, forward.x)
	var focus: Vector3 = profile.hullToWorld * Vector3(0.0, 0.0, (first if at_first else last) - forward_sign * 0.8 / profile.hullToWorld.basis.z.length())
	focus.y = _water(focus.x, focus.z, float(_native_snapshot.time)) + 0.08
	var offset := right * 10.0 + forward * 2.0 + Vector3.UP * 4.0
	if _options.camera_mode == "front":
		offset = forward * 12.0 + right * 2.0 + Vector3.UP * 4.0
	elif _options.camera_mode == "high":
		offset = right * 15.0 + Vector3.UP * 25.0
	offset = offset.rotated(Vector3.UP, _orbit_yaw)
	var horizontal := Vector2(offset.x, offset.z).length()
	var elevation := clampf(atan2(offset.y, horizontal) + _orbit_pitch, 0.08, 1.4)
	var direction := Vector3(offset.x, 0.0, offset.z).normalized()
	offset = (direction * cos(elevation) + Vector3.UP * sin(elevation)) * offset.length() * _zoom
	_camera.global_position = focus + offset
	_camera.look_at(focus)
	_ocean.position = Vector3(focus.x, 0.0, focus.z)
