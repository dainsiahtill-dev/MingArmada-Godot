extends "res://game/research/demos/hull_contact_experiment.gd"
## Tail-focused observer of the existing real ship/crew/ocean/runtime experiment.
## The candidate owns independent world history; toggling requires a clean reset.
const FLOW_SCOPE := "Production Ship/Crew/Ocean/SailingRuntime; source baseline, archived center-trail v2 or opt-in interactive GPU field use the same real accepted motion. GPU field is one-way ship-to-water; it does not alter buoyancy. Camera frames stern and two ship lengths behind. Reentry is an explicit2m presentation stress overlay, not a native physics event. No gameplay/save writes or full-game FPS claim."
const FIELD_PATH := "res://modules/scene_engine/water/interactive_wake_field.gd"
const INTERACTION_PATH := "res://modules/scene_engine/water/ship_water_interaction.gd"
const FIELD_DEBUG := ["none","height","foam","normal"]
var _field: RefCounted
var _interaction: RefCounted
var _field_error := ""
var _field_bound := false
var _field_generation := 0
var _interaction_receipt: Dictionary = {}
var _interaction_duplicate_skips := 0
var _field_center := Vector2.ZERO
var _field_requested_time := -1.0
var _field_surface_bounds := Vector4.ZERO
var _field_surface_generation := -1
var _camera_framing: Dictionary = {}

func get_default_options() -> Dictionary:
	var options := DEFAULTS.duplicate(true)
	options.flow_enabled = false
	options.field_enabled = false
	options.field_debug = "none"
	options.turn_direction = "right"
	options.carrier_mode = "projected"
	options.projected_resolution = 80
	return options

func configure(options: Dictionary) -> Dictionary:
	var candidate := get_default_options()
	for key in options:
		if not candidate.has(key) and key not in ["case", "camera"]: return {"ok":false,"reason":"unknown-"+str(key),"ready":_ready_experiment,"pending":false}
	candidate.merge(options.duplicate(true), true)
	if options.has("case") and not options.has("scenario"): candidate.scenario = options["case"]
	if options.has("camera") and not options.has("camera_mode"): candidate.camera_mode = options.camera
	if not candidate.flow_enabled is bool: return {"ok":false,"reason":"invalid-flow_enabled","ready":_ready_experiment,"pending":false}
	if not candidate.field_enabled is bool: return {"ok":false,"reason":"invalid-field_enabled","ready":_ready_experiment,"pending":false}
	if not candidate.field_debug is String or candidate.field_debug not in FIELD_DEBUG: return {"ok":false,"reason":"invalid-field_debug","ready":_ready_experiment,"pending":false}
	if not candidate.turn_direction is String or candidate.turn_direction not in ["left","right"]: return {"ok":false,"reason":"invalid-turn_direction","ready":_ready_experiment,"pending":false}
	if not candidate.carrier_mode is String or candidate.carrier_mode not in ["projected","plane"]: return {"ok":false,"reason":"invalid-carrier_mode","ready":_ready_experiment,"pending":false}
	if not candidate.projected_resolution is int or candidate.projected_resolution not in [80,96,160]: return {"ok":false,"reason":"invalid-projected_resolution","ready":_ready_experiment,"pending":false}
	if candidate.field_enabled and candidate.flow_enabled: return {"ok":false,"reason":"select-field-or-historical-flow","ready":_ready_experiment,"pending":false}
	return super.configure(candidate)

func control_spec() -> Array:
	var kinds: Array = []
	for id in KINDS: kinds.append({"value":id,"label":id})
	var scenarios: Array = []
	var labels := {"cruise":"巡航","slow":"低速","turn":"转弯（4秒后）","stop":"收帆（4秒后）","reentry":"再入水压力夹具"}
	for id in SCENARIOS: scenarios.append({"value":id,"label":labels[id]})
	return [
		{"id":"field_enabled","label":"交互水面场（实验，重置）","type":"toggle","value":_options.get("field_enabled",false)},
		{"id":"flow_enabled","label":"历史中线候选（未采用，重置）","type":"toggle","value":_options.get("flow_enabled",false)},
		{"id":"contact_enabled","label":"独立船边水沫 / 飞溅","type":"toggle","value":_options.contact_enabled},
		{"id":"field_debug","label":"场诊断显示","type":"choice","value":_options.get("field_debug","none"),"choices":[{"value":"none","label":"正常海面"},{"value":"height","label":"局部波高"},{"value":"foam","label":"持久泡沫"},{"value":"normal","label":"水面法线"}]},
		{"id":"carrier_mode","label":"海面载体（重置）","type":"choice","value":_options.get("carrier_mode","projected"),"choices":[{"value":"projected","label":"正式投影海面"},{"value":"plane","label":"有限平面对照"}]},
		{"id":"projected_resolution","label":"投影网格分段（重置）","type":"choice","value":_options.get("projected_resolution",80),"choices":[{"value":80,"label":"80 × 80 正式默认"},{"value":96,"label":"96 × 96 旧实验"},{"value":160,"label":"160 × 160 密网格实验"}]},
		{"id":"carrier_extent","label":"仅平面对照范围（重置）","type":"choice","value":_options.carrier_extent,"choices":[{"value":1200.0,"label":"1200m 原平面"},{"value":384.0,"label":"384m 近场平面"}]},
		{"id":"kind","label":"真实船型（重置）","type":"choice","value":_options.kind,"choices":kinds},
		{"id":"scenario","label":"航行场景（重置）","type":"choice","value":_options.scenario,"choices":scenarios},
		{"id":"turn_direction","label":"4秒后转舵方向（重置）","type":"choice","value":_options.get("turn_direction","right"),"choices":[{"value":"right","label":"右舵 +0.45"},{"value":"left","label":"左舵 −0.45"}]},
		{"id":"camera_mode","label":"尾部观察镜头","type":"choice","value":_options.camera_mode,"choices":[{"value":"side","label":"侧后方"},{"value":"high","label":"高位尾流"},{"value":"front","label":"船尾回望"}]}
	]

func set_parameter(id: String, value: Variant) -> Dictionary:
	if id in ["flow_enabled","field_enabled"]:
		if not value is bool: return {"ok":false,"reason":"invalid-"+id,"reset_required":false}
		var other := "flow_enabled" if id == "field_enabled" else "field_enabled"
		if value and _options.get(other,false): return {"ok":false,"reason":"select-field-or-historical-flow","reset_required":false}
	elif id == "contact_enabled":
		if not value is bool: return {"ok":false,"reason":"invalid-contact_enabled","reset_required":false}
		set_contact_enabled(value)
		return {"ok":true,"id":id,"value":value,"reset_required":false}
	elif id == "field_debug":
		if not value is String or value not in FIELD_DEBUG: return {"ok":false,"reason":"invalid-field_debug","reset_required":false}
		_options.field_debug = value
		_sync_field_presentation()
		return {"ok":true,"id":id,"value":value,"reset_required":false}
	elif id == "carrier_extent":
		if not (value is float or value is int) or float(value) not in [1200.0,384.0]: return {"ok":false,"reason":"invalid-carrier_extent","reset_required":false}
		value = float(value)
	elif id == "carrier_mode":
		if not value is String or value not in ["projected","plane"]: return {"ok":false,"reason":"invalid-carrier_mode","reset_required":false}
	elif id == "projected_resolution":
		if not value is int or value not in [80,96,160]: return {"ok":false,"reason":"invalid-projected_resolution","reset_required":false}
	elif id == "kind":
		if not value is String or value not in KINDS: return {"ok":false,"reason":"invalid-kind","reset_required":false}
	elif id == "scenario":
		if not value is String or value not in SCENARIOS: return {"ok":false,"reason":"invalid-scenario","reset_required":false}
	elif id == "turn_direction":
		if not value is String or value not in ["left","right"]: return {"ok":false,"reason":"invalid-turn_direction","reset_required":false}
	elif id == "camera_mode":
		if not value is String or value not in CAMERAS: return {"ok":false,"reason":"invalid-camera_mode","reset_required":false}
		set_camera_mode(value)
		return {"ok":true,"id":id,"value":value,"reset_required":false}
	else: return {"ok":false,"reason":"unknown-parameter","reset_required":false}
	return {"ok":true,"id":id,"value":value,"reset_required":value != _options.get(id),"reason":"independent-initial-history"}

func _compose_packet() -> Dictionary:
	var packet := super._compose_packet()
	if packet.get("ships", []).is_empty() or not is_instance_valid(_ship): return packet
	var attachment: Dictionary = _ship.source_water_attachment()
	var native: Dictionary = _native_snapshot.get("ship", {})
	var dimensions: Dictionary = native.get("dimensions", {})
	var profile: Dictionary = attachment.get("surfaceProfile", {})
	var beam := float(dimensions.get("width", 1.0))
	if profile.has("beam") and profile.get("hullToWorld") is Transform3D:
		beam = float(profile.beam) * (profile.hullToWorld as Transform3D).basis.x.length()
	var heading := float(native.get("heading", 0.0))
	var velocity: Dictionary = native.get("velocity", {})
	packet.ships[0].sourceWake.targetTrail = {"enabled":_options.get("flow_enabled",false),"position":attachment.get("flowStern", attachment.get("trail", Vector3.ZERO)),"forward":Vector3(cos(heading),0.0,sin(heading)),"speed":Vector2(float(velocity.get("x",0)),float(velocity.get("z",0))).length(),"beam":beam,"length":float(dimensions.get("length",1.0)),"hullAlive":true}
	if _field != null and _interaction != null:
		var seconds := float(_native_snapshot.get("time",0.0))
		var sampled: Dictionary = _interaction.sample("player",attachment,seconds,_water,true)
		if not sampled.get("diagnostics",{}).get("accepted",false):
			if sampled.get("diagnostics",{}).get("reason","")=="duplicate": _interaction_duplicate_skips+=1
			return packet
		_interaction_receipt = sampled
		var wakes: Array = []
		var wake: Dictionary = _interaction_receipt.get("wake",{})
		if not wake.is_empty(): wakes.append(wake)
		var diagnostics: Dictionary = _field.diagnostics()
		var extent := float(diagnostics.get("extent_m",96.0))
		var cell := extent / maxf(1.0,float(diagnostics.get("resolution",256)))
		var stern: Vector3 = attachment.get("flowStern",attachment.get("trail",Vector3.ZERO))
		var center := Vector2(stern.x,stern.z)-Vector2(cos(heading),sin(heading))*extent*0.25
		_field_center = center.snapped(Vector2(cell,cell))
		_field_requested_time = seconds
		_field.advance(seconds,_field_center,_interaction_receipt.get("emitters",[]),wakes)
	return packet

func _build_experiment() -> void:
	if _options.get("field_enabled",false):
		if not ResourceLoader.exists(FIELD_PATH) or not ResourceLoader.exists(INTERACTION_PATH):
			_field_error = "interactive-field-module-unavailable"
		else:
			_field = load(FIELD_PATH).new()
			_interaction = load(INTERACTION_PATH).new()
			var receipt: Dictionary = _field.configure()
			if not receipt.get("ok",true): _field_error = str(receipt.get("error",receipt.get("reason","field-configuration-failed")))
	super._build_experiment()
	if _ready_experiment and _options.get("carrier_mode","projected")=="projected":
		# The inherited close-contact demo deliberately substitutes a finite
		# PlaneMesh. Reconfigure only this derived lab through the production
		# owner's public API, restoring its actual projected mesh and optics.
		_ocean.configure(_camera,load("res://assets/textures/waternormals.jpg"),int(_options.projected_resolution),3000.0)
	_sync_field_presentation()

func _render_snapshot(consumed: float) -> void:
	super._render_snapshot(consumed)
	_sync_field_presentation()

func _redraw_camera() -> void:
	super._redraw_camera()
	_sync_field_presentation()

func advance(delta: float) -> void:
	if _options.scenario == "turn":
		# Own this branch, rather than issuing an external command that the
		# inherited positive-rudder branch would overwrite before physics.
		if _ready_experiment and not _disposed and not _options.paused and is_finite(delta) and delta>0.0:
			_accumulator += minf(delta,STEP*MAX_CATCHUP)
			var count := 0
			while _accumulator+1.0e-12>=STEP and count<MAX_CATCHUP:
				_tick+=1
				var signed_rudder := -.45 if _options.get("turn_direction","right")=="left" else .45
				_runtime.command({"type":"turn","value":signed_rudder if _tick>=128 else 0.0})
				var consumed: float = _runtime.advance(STEP)
				_render_snapshot(consumed)
				_accumulator-=STEP
				count+=1
	else:
		super.advance(delta)
	# Async completion can arrive while paused; publishing it must not advance
	# physics, inject another force or take ownership of a private clock.
	_sync_field_presentation()

func _sync_field_presentation() -> void:
	_field_bound = false
	if not is_instance_valid(_ocean): return
	var diagnostics: Dictionary = _field.diagnostics() if _field != null else {}
	var error := str(diagnostics.get("error",""))
	if not error.is_empty(): _field_error = error
	if _ocean.has_method("set_interactive_wake_debug"):
		var debug_ok: bool = _ocean.set_interactive_wake_debug(_options.get("field_debug","none"))
		if not debug_ok and _options.get("field_enabled",false): _field_error = "ocean-field-debug-rejected"
	if _options.get("field_enabled",false) and diagnostics.get("ready",false) and _field_error.is_empty():
		var surface: Dictionary = _field.acquire_surface()
		var texture: Texture2D = surface.get("texture")
		var bounds: Vector4 = surface.get("bounds",Vector4.ZERO)
		if not _ocean.has_method("bind_interactive_wake_field"):
			_field_error = "ocean-field-binding-unavailable"
		elif texture == null or not bounds.is_finite() or bounds.z <= bounds.x or bounds.w <= bounds.y or not surface.has("generation"):
			_field_error = "published-field-texture-or-bounds-invalid"
		else:
			_field_bound = bool(_ocean.bind_interactive_wake_field(texture,bounds,true))
			if not _field_bound: _field_error = "ocean-field-binding-rejected"
			else:
				_field_surface_bounds = bounds
				_field_surface_generation = int(surface.generation)
				_field.acknowledge_surface(_field_surface_generation)
	if not _field_bound and _ocean.has_method("bind_interactive_wake_field"):
		_ocean.bind_interactive_wake_field(null,Vector4.ZERO,false)
	# Preserve native source geometry/history and local contact. Only the
	# source tail's visibility changes after a valid field reaches the ocean.
	if _renderer != null:
		_renderer.set_external_water_coverage(["player"] if _field_bound else [])
	if _options.get("carrier_mode","projected")=="projected":
		_ocean.update_projection()

func request_field_readback(callback: Callable) -> void:
	if not callback.is_valid(): return
	if _field == null:
		callback.call_deferred({"error":"field-unavailable","generation":_field_generation})
		return
	_field.request_readback(_receive_field_readback.bind(_field_generation,callback))

func _receive_field_readback(receipt: Dictionary, generation: int, callback: Callable) -> void:
	if not callback.is_valid(): return
	if generation != _field_generation or _disposed:
		callback.call({"error":"stale-field-readback","generation":generation})
		return
	var accepted := receipt.duplicate(true)
	accepted.generation = generation
	callback.call(accepted)

func dispose() -> void:
	_field_generation += 1
	if is_instance_valid(_ocean) and _ocean.has_method("bind_interactive_wake_field"):
		_ocean.bind_interactive_wake_field(null,Vector4.ZERO,false)
	if _field != null: _field.dispose()
	if _interaction != null: _interaction.clear()
	_field = null
	_interaction = null
	_field_bound = false
	_field_error = ""
	_interaction_receipt.clear()
	_interaction_duplicate_skips = 0
	_field_center = Vector2.ZERO
	_field_requested_time = -1.0
	_field_surface_bounds = Vector4.ZERO
	_field_surface_generation = -1
	_camera_framing.clear()
	super.dispose()

func _update_camera() -> void:
	if not is_instance_valid(_ship) or not is_instance_valid(_camera): return
	var attachment: Dictionary = _ship.source_water_attachment()
	var stern: Variant = attachment.get("flowStern", attachment.get("trail"))
	if not stern is Vector3: return
	var native: Dictionary = _native_snapshot.get("ship", {})
	var length := maxf(1.0, float(native.get("dimensions", {}).get("length", 20.0)))
	var heading := float(native.get("heading", 0.0))
	var forward := Vector3(cos(heading),0.0,sin(heading))
	var right := Vector3(-forward.z,0.0,forward.x)
	var focus: Vector3 = stern - forward * length * 0.45
	focus.y = _water(focus.x, focus.z, float(_native_snapshot.get("time",0)))
	var offset := (right*3.2-forward*0.2+Vector3.UP*1.6)*length
	if _options.camera_mode == "front": offset = (-forward*3.5+right*0.4+Vector3.UP*1.5)*length
	elif _options.camera_mode == "high": offset = (right*0.35-forward*0.6+Vector3.UP*4.2)*length
	offset = offset.rotated(Vector3.UP,_orbit_yaw)
	var horizontal := Vector2(offset.x,offset.z).length()
	var elevation := clampf(atan2(offset.y,horizontal)+_orbit_pitch,0.08,1.4)
	var direction := Vector3(offset.x,0.0,offset.z).normalized()
	offset = (direction*cos(elevation)+Vector3.UP*sin(elevation))*offset.length()*_zoom
	_camera.global_position = focus+offset
	_camera.look_at(focus)
	# A nominal hull length cannot bound the real sails/masts. Fit the actual
	# visible mesh AABBs and aft inspection span in the perspective frustum.
	# This uses only ship/camera data, so all tail candidates share one camera.
	var points := PackedVector3Array()
	for node: Node in _ship.get_model().find_children("*","MeshInstance3D",true,false):
		if not node.is_visible_in_tree(): continue
		var box: AABB = node.get_aabb()
		for corner in 8: points.append(node.global_transform*box.get_endpoint(corner))
	var mesh_corners := points.size()
	var waterline_length := length
	var profile: Dictionary = attachment.get("surfaceProfile",{})
	if profile.get("sections",[]).size()>=2 and profile.get("hullToWorld") is Transform3D:
		waterline_length = absf(float(profile.sections[-1].z)-float(profile.sections[0].z))*(profile.hullToWorld as Transform3D).basis.z.length()
	# Retain the original nominal-length inspection promise too, when longer.
	var aft_span := maxf(length,waterline_length)*2.0
	points.append(stern)
	points.append(stern-forward*aft_span)
	var projection := _camera.get_camera_projection()
	var tan_x := 1.0/absf(projection.x.x)
	var tan_y := 1.0/absf(projection.y.y)
	var eye_direction := offset.normalized()
	var required_distance := 0.0
	for point: Vector3 in points:
		var relative := point-focus
		var toward_eye := relative.dot(eye_direction)
		required_distance=maxf(required_distance,toward_eye+maxf(absf(relative.dot(_camera.global_basis.x))/(tan_x*.90),absf(relative.dot(_camera.global_basis.y))/(tan_y*.90)))
		required_distance=maxf(required_distance,toward_eye+_camera.near*2.0)
	var effective_distance := maxf(offset.length(),required_distance*1.01)
	_camera.global_position=focus+eye_direction*effective_distance
	_camera_framing={"mesh_aabb_corners":mesh_corners,"waterline_length_m":waterline_length,"aft_span_m":aft_span,"requested_distance_m":offset.length(),"minimum_distance_m":required_distance,"effective_distance_m":effective_distance,"frustum_usable_fraction":.90}

func inspection_snapshot() -> Dictionary:
	var result := super.inspection_snapshot()
	result.topic = "wake-flow"
	result.scope = FLOW_SCOPE
	result.parameters = _options.duplicate(true)
	result.parameters.flow_enabled = _options.get("flow_enabled", false)
	result.parameters.field_enabled = _options.get("field_enabled", false)
	result.parameters.field_debug = _options.get("field_debug", "none")
	result.camera_framing = _camera_framing.duplicate(true)
	result.carrier = _carrier_snapshot()
	result.carrier_mode = _options.get("carrier_mode","projected")
	if result.carrier_mode=="projected":
		result.scope += " Carrier is the actual production projected Ocean, bounded at3000m; its screen-dependent cell size is not the0.375m field cell size."
		result.carrier_extent = null
		result.carrier_dimensions_m = []
		result.carrier_subdivisions = [int(_options.get("projected_resolution",80)),int(_options.get("projected_resolution",80))]
		result.carrier_spacing_m = null
	else:
		result.scope += " Explicit finite PlaneMesh comparison, extent=%sm,512 subdivisions; side views may expose its boundary."%str(_options.carrier_extent)
	result.field = _field.diagnostics() if _field != null else {}
	result.field_error = _field_error if not _field_error.is_empty() else str(result.field.get("error",""))
	result.field_bound = _field_bound
	result.field_status = "disposed" if _disposed else ("disabled" if not _options.get("field_enabled",false) else ("error" if not result.field_error.is_empty() else ("ready" if _field_bound else "pending")))
	result.field_requested_center = _field_center
	result.field_requested_time = _field_requested_time
	result.field_published_bounds = _field_surface_bounds
	result.field_surface_generation = _field_surface_generation
	result.interaction = _interaction_receipt.duplicate(true)
	result.interaction_duplicate_skips = _interaction_duplicate_skips
	result.field_generation = _field_generation
	result.telemetry = {"field_status":result.field_status,"field_error":result.field_error,"field":result.field,"debug":result.parameters.field_debug}
	result.target_trail = _last_packet.get("ships", [{}])[0].get("sourceWake", {}).get("targetTrail", {}).duplicate(true) if not _last_packet.get("ships", []).is_empty() else {}
	result.renderer = _renderer.diagnostics() if _renderer != null else {}
	result.flow = {}
	if _renderer != null and _renderer._actors.has("player"):
		var flow: RefCounted = _renderer._actors.player.get("flow")
		if flow != null and flow.has_method("diagnostics"): result.flow = flow.diagnostics()
	return result

func _carrier_snapshot() -> Dictionary:
	var result := {"mode":_options.get("carrier_mode","projected"),"ready":is_instance_valid(_ocean),"resolution":0,"vertices":0,"indices":0,"projection":{}}
	if not is_instance_valid(_ocean) or _ocean.mesh==null:return result
	result.mesh_class = _ocean.mesh.get_class()
	if _ocean.mesh is ArrayMesh and _ocean.mesh.get_surface_count()>0:
		result.resolution = int(_ocean.get("_segments"))
		result.vertices = _ocean.mesh.surface_get_array_len(0)
		result.indices = _ocean.mesh.surface_get_array_index_len(0)
		result.projection = _ocean.get_projection_work_diagnostics()
		result.maximum_distance_m = float(_ocean.get("_maximum_distance"))
		result.bounds = _ocean.get_aabb()
	elif _ocean.mesh is PlaneMesh:
		result.extent_m = _ocean.mesh.size.x
		result.resolution = _ocean.mesh.subdivide_width
		result.cell_spacing_m = _ocean.mesh.size.x/float(_ocean.mesh.subdivide_width+1)
	return result
