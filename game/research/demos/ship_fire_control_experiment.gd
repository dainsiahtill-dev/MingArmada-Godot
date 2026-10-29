extends Node3D
## Isolated controlled ignition. FireControl owns fire rules; this experiment
## owns health/resource accounts. Encounter supplies only an immutable t=0 template.
const Encounter = preload("res://modules/naval_simulation/encounter.gd")
const FireControl = preload("res://modules/naval_simulation/combat/fire_control.gd")
const FireSpread = preload("res://modules/naval_simulation/combat/fire_spread.gd")
const ZoneAnchors = preload("res://game/research/demos/ship_fire_zone_anchors.gd")
const Sea = preload("res://game/presentation/world/naval_world_view.gd")
const Maritime = preload("res://game/ui/shared/maritime_art_theme.gd")
const WaveField = preload("res://modules/physics_engine/ocean/wave_field.gd")
const FIRE_VIEW_PATH := "res://game/presentation/combat/ship_fire_view.gd"
const ZONE_VIEW_PATH := "res://game/research/demos/ship_fire_zone_view.gd"
const STEP := 1.0 / 60.0
const SCOPE := "controlled ignition candidate; no live ballistic/campaign/production claim"
const LANE_IDS := ["baseline", "candidate"]
const WAVES := [{"direction":{"x":.8,"z":.6},"amplitude":.12,"wavelength":28.0,"speed":.75}, {"direction":{"x":-.6,"z":.8},"amplitude":.06,"wavelength":17.0,"speed":1.15}]
const DEFAULTS := {"payload":"thorn-ball", "firefighters":4, "supplies":24, "moisture":"dry", "load":"clear", "paused":false, "camera_mode":"overview", "seed":1661, "fire_model":"r1", "ignition_zone":"stern"}
var _options := DEFAULTS.duplicate(true)
var _surface: RefCounted
var _sea: Node3D
var _fire_view: Node3D
var _template: Dictionary = {}
var _visual: Dictionary = {}
var _lanes: Dictionary = {}
var _context: Dictionary = {}
var _tick := 0
var _accumulator := 0.0
var _dropped_seconds := 0.0
var _configured := false
var _disposed := true
var _ready_experiment := false
var _error := ""
var _viewport: Viewport
var _hud: Control
var _strip: Panel
var _label: Label
var _lane_labels: Dictionary = {}
var _camera_focus := Vector3.ZERO
var _zone_anchors: Dictionary = {}

func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	if _configured and not _disposed: _build()

func get_default_options() -> Dictionary: return DEFAULTS.duplicate(true)
func _invalid(reason: String) -> Dictionary: return {"ok":false, "reason":reason, "reset_required":false}
func _ground(_x: float, _z: float) -> float: return -80.0
func _water(x: float, z: float, seconds: float) -> float:
	return _surface.sample_height(x, z, seconds) if _surface != null else NAN

func _option_error(options: Dictionary) -> String:
	for key: Variant in options:
		if not DEFAULTS.has(key): return "未知受控火患实验参数"
	if options.payload not in ["fire-ball", "thorn-ball"]: return "引火载荷无效"
	if not options.firefighters is int or options.firefighters not in [0, 2, 4, 8]: return "扑救人数必须为0、2、4或8"
	if not options.supplies is int or options.supplies not in [0, 4, 24, 64]: return "损管准备份无效"
	if options.moisture not in ["dry", "rain", "wet-deck"] or options.load not in ["clear", "powder"]: return "实验湿润度或可燃负荷无效"
	if not options.paused is bool or options.camera_mode not in ["overview", "near", "baseline-near"]: return "暂停或镜头参数无效"
	if options.fire_model not in ["r1", "zones"] or options.ignition_zone not in ["bow", "mid", "stern"]: return "火势模型或点燃区域无效"
	if not options.seed is int or options.seed < 0 or options.seed > 2147483647: return "随机种子无效"
	return ""

func configure(options: Dictionary = {}) -> Dictionary:
	var next := DEFAULTS.duplicate(true)
	next.merge(options, true)
	var reason := _option_error(next)
	if not reason.is_empty(): return _invalid(reason)
	var surface := WaveField.new()
	if not surface.configure(WAVES): return _invalid("受控温和波面无效")
	# No Encounter is retained, advanced or commanded. This constructor only
	# normalizes real ship/model data once for this newly configured experiment.
	var encounter := Encounter.new({"mode":"terminal", "referenceGunnery":true, "seed":next.seed, "battleId":"ship-fire-control", "playerId":"baseline", "wind":{"direction":{"x":1.0,"y":0.0},"speed":0.0}, "waveSampler":surface, "oceanWaves":WAVES.duplicate(true), "sampleTerrainHeight":_ground, "ships":[
		{"id":"baseline", "name":"无人扑救对照", "kind":"fuchuan", "team":"player", "position":{"x":0.0,"z":-19.0}, "heading":0.0, "sailDeployment":.35, "hull":100.0},
		{"id":"candidate", "name":"损管候选", "kind":"fuchuan", "team":"player", "position":{"x":0.0,"z":19.0}, "heading":0.0, "sailDeployment":.35, "hull":100.0}
	]})
	if not encounter.last_error.is_empty(): return _invalid(encounter.last_error)
	var template: Dictionary = encounter.snapshot()
	var lanes: Dictionary = {}
	var wetness := 1.0 if next.moisture == "wet-deck" else 0.0
	var zones: bool = next.fire_model == "zones"
	for ship: Dictionary in template.ships:
		var ignited: Dictionary = FireSpread.ignite(FireSpread.initial(next.supplies), next.payload, wetness, next.ignition_zone) if zones else FireControl.ignite(FireControl.initial(next.supplies), next.payload, wetness)
		if not ignited.ok: return _invalid("受控点燃被纯核拒绝")
		var workers: int = int(next.firefighters) if ship.id == "candidate" else 0
		var assigned: Dictionary = FireSpread.assign(ignited.state, workers, int(ship.crew)) if zones else FireControl.assign(ignited.state, workers, int(ship.crew))
		if not assigned.ok: return _invalid("实验船员分配被纯核拒绝")
		var reserved: int = FireSpread.reserved_crew(assigned.state, int(ship.crew)) if zones else FireControl.reserved_crew(assigned.state, int(ship.crew))
		lanes[ship.id] = {"fireControl":assigned.state, "hull":float(ship.hull), "maxHull":float(ship.maxHull), "sail":float(ship.sail), "maxSail":float(ship.maxSail), "crew":int(ship.crew), "maxCrew":int(ship.maxCrew), "reservedCrew":reserved, "workSeconds":0.0, "lastWorkSeconds":0.0, "suppliesSpent":0, "damage":{"hull":0.0,"sail":0.0,"crew":0}, "extinguishedAt":-1.0}
		if zones:
			lanes[ship.id].spreadCount = 0
			lanes[ship.id].spreadEvents = []
	dispose()
	_options = next
	_surface = surface
	_template = template
	_lanes = lanes
	_context = {"rain01":1.0 if next.moisture == "rain" else 0.0, "flammableLoad":1.0 if next.load == "powder" else 0.0}
	_configured = true
	_disposed = false
	_error = ""
	_compose_visual()
	set_process(false)
	set_physics_process(false)
	if is_inside_tree(): _build()
	if not _error.is_empty(): return _invalid(_error)
	return {"ok":true, "ready":_ready_experiment, "pending":not is_inside_tree(), "options":_options.duplicate(true)}

func reset_experiment(overrides: Dictionary = {}) -> Dictionary:
	var next := _options.duplicate(true)
	next.merge(overrides, true)
	var result := configure(next)
	if result.get("ok", false): result.snapshot = inspection_snapshot()
	return result

func control_spec() -> Array:
	return [
		{"id":"fire_model", "label":"火势模型（重置）", "type":"choice", "value":_options.fire_model, "choices":[{"value":"r1","label":"原全船热量基线"},{"value":"zones","label":"三区蔓延候选"}]},
		{"id":"ignition_zone", "label":"三区初始火点（重置）", "type":"choice", "value":_options.ignition_zone, "choices":[{"value":"bow","label":"船首"},{"value":"mid","label":"船中"},{"value":"stern","label":"船尾"}]},
		{"id":"payload", "label":"受控引火载荷（重置）", "type":"choice", "value":_options.payload, "choices":[{"value":"fire-ball","label":"普通引火候选"},{"value":"thorn-ball","label":"蒺藜火毬灵感候选"}]},
		{"id":"firefighters", "label":"右船扑救人数（重置）", "type":"choice", "value":_options.firefighters, "choices":[{"value":0,"label":"0人"},{"value":2,"label":"2人"},{"value":4,"label":"4人"},{"value":8,"label":"8人"}]},
		{"id":"supplies", "label":"两船损管准备份（重置）", "type":"choice", "value":_options.supplies, "choices":[{"value":0,"label":"0份"},{"value":4,"label":"4份"},{"value":24,"label":"24份"},{"value":64,"label":"64份"}]},
		{"id":"moisture", "label":"实验湿润条件（重置）", "type":"choice", "value":_options.moisture, "choices":[{"value":"dry","label":"干燥"},{"value":"rain","label":"实验降雨输入"},{"value":"wet-deck","label":"预湿甲板"}]},
		{"id":"load", "label":"可燃负荷（重置）", "type":"choice", "value":_options.load, "choices":[{"value":"clear","label":"清空负荷"},{"value":"powder","label":"可燃负荷 1（无殉爆）"}]},
		{"id":"camera_mode", "label":"固定观察镜头", "type":"choice", "value":_options.camera_mode, "choices":[{"value":"overview","label":"双船全景"},{"value":"near","label":"右船近景"},{"value":"baseline-near","label":"左船蔓延近景"}]}
	]

func set_parameter(id: String, value: Variant) -> Dictionary:
	if _disposed or not _configured: return _invalid("实验尚未就绪")
	if not DEFAULTS.has(id): return _invalid("未知受控火患参数")
	var next := _options.duplicate(true)
	next[id] = value
	var reason := _option_error(next)
	if not reason.is_empty(): return _invalid(reason)
	if id == "camera_mode":
		set_camera_mode(str(value))
		return {"ok":true, "id":id, "value":value, "reset_required":false}
	if id == "paused":
		set_paused(value)
		return {"ok":true, "id":id, "value":value, "reset_required":false}
	return {"ok":true, "id":id, "value":value, "reset_required":value != _options[id]}

func set_paused(value: bool) -> void:
	_options.paused = value
	_refresh_label()

func set_camera_mode(value: String) -> void:
	if value not in ["overview", "near", "baseline-near"]: return
	_options.camera_mode = value
	_layout()

func orbit_camera(_yaw: float, _pitch: float) -> void: _layout()
func zoom_camera(_amount: float) -> void: pass

func advance(delta: float) -> void:
	if _disposed or not _ready_experiment or _options.paused or not _error.is_empty() or not is_finite(delta) or delta <= 0.0: return
	var accepted := minf(delta, .25)
	_dropped_seconds += delta - accepted
	_accumulator += accepted
	var consumed := 0.0
	while _accumulator + 1e-12 >= STEP:
		_accumulator = maxf(0.0, _accumulator - STEP)
		for id: String in LANE_IDS:
			var lane: Dictionary = _lanes[id]
			var input := {"able":lane.crew, "maxHull":lane.maxHull, "maxSail":lane.maxSail, "maxCrew":lane.maxCrew, "rain01":_context.rain01, "flammableLoad":_context.flammableLoad}
			var result: Dictionary = FireSpread.step(lane.fireControl, input) if _options.fire_model == "zones" else FireControl.step(lane.fireControl, input)
			if not result.get("ok", false):
				_error = "纯火控核拒绝受控实验状态"
				_refresh_label()
				return
			lane.fireControl = result.state
			if _options.fire_model == "zones":
				for event: Dictionary in result.spreadEvents:
					lane.spreadCount += 1
					lane.spreadEvents.append(event.duplicate(true))
					if lane.spreadEvents.size() > 32: lane.spreadEvents.pop_front()
			# Health and inventory belong solely to these independent experiment
			# accounts. Presentation never feeds damage back into the rules.
			var hull_loss := minf(float(lane.hull), float(result.damage.hull))
			var sail_loss := minf(float(lane.sail), float(result.damage.sail))
			var crew_loss := mini(int(lane.crew), int(result.damage.crew))
			lane.hull = maxf(0.0, float(lane.hull) - hull_loss)
			lane.sail = maxf(0.0, float(lane.sail) - sail_loss)
			lane.crew = maxi(0, int(lane.crew) - crew_loss)
			lane.damage.hull += hull_loss
			lane.damage.sail += sail_loss
			lane.damage.crew += crew_loss
			lane.reservedCrew = int(result.reservedCrew)
			lane.lastWorkSeconds = float(result.workSeconds)
			lane.workSeconds += float(result.workSeconds)
			lane.suppliesSpent += int(result.suppliesSpent)
			if result.extinguished: lane.extinguishedAt = (_tick + 1) * STEP
		_tick += 1
		consumed += STEP
		_compose_visual()
		_sea.remember_authoritative_poses(_visual, STEP)
	if consumed > 0.0: _present(consumed)

func _compose_visual() -> void:
	_visual = _template.duplicate(true)
	_visual.time = _tick * STEP
	_visual.tick = _tick
	_visual.battleId = "ship-fire-control"
	for ship: Dictionary in _visual.get("ships", []):
		var lane: Dictionary = _lanes[ship.id]
		for key: String in ["hull", "sail", "crew"]: ship[key] = lane[key]
		ship.fireControl = _fire_summary(lane.fireControl)
		if _options.fire_model == "zones": ship.fireSpread = lane.fireControl.duplicate(true)
		ship.time = _visual.time
		# Fixed horizontal/body attitude, gently heaving on the same visible
		# sampler. This is an observation fixture, not a buoyancy experiment.
		var p: Dictionary = ship.visual.position
		p.y = _water(float(p.x), float(p.z), float(_visual.time))
		ship.visual.pitch = 0.0
		ship.visual.heel = 0.0
		ship.visual.velocity = {"x":0.0,"y":0.0,"z":0.0}

func _anchor(ship_id: String) -> Dictionary:
	if not is_instance_valid(_sea) or not _sea.ships.has(ship_id): return {}
	return _sea.ships[ship_id].source_destruction_anchor()

func _fire_summary(state: Dictionary) -> Dictionary:
	return FireSpread.summary(state) if _options.fire_model == "zones" else state.duplicate(true)

func _zone_anchor(key: String) -> Dictionary:
	var parts: PackedStringArray = key.rsplit("|", true, 1)
	if parts.size() != 2 or not _zone_anchors.has(parts[0]) or not is_instance_valid(_sea) or not _sea.ships.has(parts[0]): return {}
	var local: Dictionary = _zone_anchors[parts[0]].sample(parts[1])
	var model: Node3D = _sea.ships[parts[0]].source_deck_model()
	if local.is_empty() or not is_instance_valid(model): return {}
	return {"shipId":parts[0], "zone":parts[1], "time":_tick * STEP, "position":model.global_transform * (local.point + Vector3.UP * .35)}

func _present(consumed: float) -> void:
	if not is_instance_valid(_sea) or not is_instance_valid(_fire_view): return
	# Commit current real deck/model transforms before the read-only flame view
	# queries anchors. No combat events are invented by controlled ignition.
	_sea.apply_snapshot(_visual, [], consumed)
	_fire_view.apply_snapshot(_visual)
	_fire_view.refresh_anchors()
	_refresh_label()

func _build() -> void:
	if _ready_experiment or _template.is_empty() or is_instance_valid(_sea): return
	var fire_script: Script = load(ZONE_VIEW_PATH if _options.fire_model == "zones" else FIRE_VIEW_PATH)
	if fire_script == null:
		_error = "热量驱动火烟呈现不可用"
		return
	_viewport = get_viewport()
	_sea = Sea.new()
	_sea.name = "ControlledShipFireProductionSea"
	add_child(_sea)
	_sea.apply_settings({"quality":"low", "cameraFollow":false, "cameraShake":0.0})
	if not _sea.configure(_ground, [], _water, _visual, {"combat_atmosphere":false, "chunk_radius":0, "resolution":8, "ocean_resolution":40, "ocean_distance":1200.0, "vegetation":false, "island_details":false, "fidelity_islands":false, "interactive_wake":false}):
		_error = "受控火患实验的正式海面初始化失败"
		_release_presentation()
		return
	var ocean: MeshInstance3D = _sea.world.get_ocean()
	if not ocean.set_wave_descriptors(WAVES):
		_error = "受控实验温和波面未获接受"
		_release_presentation()
		return
	ocean.set_reflection_enabled(false)
	if _options.fire_model == "zones":
		for id: String in LANE_IDS:
			var anchors: RefCounted = ZoneAnchors.new()
			var result: Dictionary = anchors.configure("fuchuan", _sea.ships[id].source_deck_model())
			if not result.get("ok", false):
				_error = "三区真实甲板不可用：" + str(result.get("reason", ""))
				_release_presentation()
				return
			_zone_anchors[id] = anchors
	_sea.set_camera_controller(_place_camera)
	_place_camera()
	_fire_view = fire_script.new()
	_fire_view.name = "ControlledHeatFireView"
	add_child(_fire_view)
	var prepared: Dictionary = _fire_view.configure({"enabled":true,"quality":"balanced"}, _sea.camera, _water, _zone_anchor if _options.fire_model == "zones" else _anchor)
	if not prepared.get("ok", false):
		_error = str(prepared.get("reason", "热量驱动火烟初始化失败"))
		_release_presentation()
		return
	_build_hud()
	_viewport.size_changed.connect(_layout)
	_ready_experiment = true
	_present(0.0)
	_layout()

func _place_camera() -> void:
	if not is_instance_valid(_sea) or not is_instance_valid(_sea.camera): return
	var extent := get_viewport().get_visible_rect().size
	var aspect := extent.x / maxf(1.0, extent.y)
	var camera: Camera3D = _sea.camera
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = 42.0
	var focus := Vector3(0.0, 3.5, 0.0)
	var distance := 125.0
	# Negative X makes increasing world Z read from left to right: the
	# unattended z=-19 lane stays beneath its left-hand telemetry column.
	var direction := Vector3(-.86,.65,-.30).normalized()
	if _options.camera_mode in ["near", "baseline-near"]:
		focus = Vector3(0.0, 3.5, -19.0 if _options.camera_mode == "baseline-near" else 19.0)
		distance = 63.0
		direction = Vector3(-.78,.56,-.44).normalized()
	distance /= minf(1.0, maxf(.5, aspect))
	camera.global_position = focus + direction * distance
	camera.look_at(focus, Vector3.UP)
	_camera_focus = focus

func _build_hud() -> void:
	_hud = Control.new(); _hud.name = "ControlledShipFireHud"
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.theme = Maritime.create(); add_child(_hud)
	# A root Panel has a fixed viewport budget. Wrapping labels cannot inflate it.
	_strip = Panel.new(); _strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.clip_contents = true
	_strip.add_theme_stylebox_override("panel", Maritime.panel(6, "inset")); _hud.add_child(_strip)
	_label = _hud_label("ControlledIgnitionScope")
	for id: String in LANE_IDS: _lane_labels[id] = _hud_label(id.capitalize() + "FireAccount")

func _hud_label(node_name: String) -> Label:
	var label := Label.new(); label.name = node_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.clip_text = true
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Maritime.PALE)
	_strip.add_child(label)
	return label

func _layout() -> void:
	if not is_instance_valid(_viewport): return
	var extent := _viewport.get_visible_rect().size
	if is_instance_valid(_hud):
		_hud.size = extent
		var margin := minf(8.0, minf(extent.x, extent.y) * .25)
		_strip.position = Vector2(margin, margin)
		_strip.size = Vector2(maxf(0.0, extent.x - margin * 2.0), minf(132.0, maxf(0.0, extent.y - margin * 2.0)))
		_strip.visible = _strip.size.x >= 32.0 and _strip.size.y >= 20.0
		_label.position = Vector2(10, 6)
		_label.size = Vector2(maxf(0.0, _strip.size.x - 20.0), 22.0)
		var width := maxf(0.0, (_strip.size.x - 30.0) * .5)
		for i in LANE_IDS.size():
			var label: Label = _lane_labels[LANE_IDS[i]]
			label.position = Vector2(10.0 + i * (width + 10.0), 29.0)
			label.size = Vector2(width, maxf(0.0, _strip.size.y - 35.0))
	_place_camera()
	if is_instance_valid(_sea) and is_instance_valid(_sea.world): _sea.world.get_ocean().update_projection()
	_refresh_label()

func _refresh_label() -> void:
	if not is_instance_valid(_label): return
	_label.text = "受控点燃候选 · %.2f秒%s · 2秒转岗，准备份不足不扑救，灭火不回血" % [_tick * STEP, " · 暂停" if _options.paused else ""]
	if not _error.is_empty(): _label.text = _error
	for id: String in LANE_IDS:
		var lane: Dictionary = _lanes[id]
		var fire: Dictionary = _fire_summary(lane.fireControl)
		var label: Label = _lane_labels[id]
		label.text = "%s · 热 %.1f / 燃料 %.1f秒\nHP %.2f · 帆 %.2f · 人员 %d/%d\n储备 %d · 占用 %d · 转岗 %.2f秒\n工作 %.2f人秒 · 损伤 %.2f船/%.2f帆/%d人" % ["左船：无人对照" if id == "baseline" else "右船：%d人候选" % _options.firefighters, float(fire.heat), float(fire.fuelSeconds), float(lane.hull), float(lane.sail), int(lane.crew), int(lane.maxCrew), int(fire.supplies), int(lane.reservedCrew), int(fire.transferTicks) * STEP, float(lane.workSeconds), float(lane.damage.hull), float(lane.damage.sail), int(lane.damage.crew)]
		if _options.fire_model == "zones":
			var heats: Array = lane.fireControl.heatByZone
			# Keep the existing four-line budget: a fifth line is clipped on the
			# real laboratory viewport, hiding the very spatial account under test.
			label.text = "%s · 首 %.1f / 中 %.1f / 尾 %.1f\nHP %.2f · 帆 %.2f · 人员 %d/%d · 传播 %d次\n储备 %d · 占用 %d · 转岗 %.2f秒 · 燃料 %.1f秒\n工作 %.2f人秒 · 损伤 %.2f船/%.2f帆/%d人" % ["左船：无人对照" if id == "baseline" else "右船：%d人候选" % _options.firefighters, float(heats[0]), float(heats[1]), float(heats[2]), float(lane.hull), float(lane.sail), int(lane.crew), int(lane.maxCrew), int(lane.spreadCount), int(fire.supplies), int(lane.reservedCrew), int(fire.transferTicks) * STEP, float(fire.fuelSeconds), float(lane.workSeconds), float(lane.damage.hull), float(lane.damage.sail), int(lane.damage.crew)]

func inspection_snapshot() -> Dictionary:
	var camera: Dictionary = {}
	if is_instance_valid(_sea) and is_instance_valid(_sea.camera):
		var eye: Vector3 = _sea.camera.global_position
		camera = {"position":[eye.x,eye.y,eye.z], "focus":[_camera_focus.x,_camera_focus.y,_camera_focus.z], "fixed":true, "fov":_sea.camera.fov}
	return {"topic":"ship-fire-control", "presentation":"dashboard", "ready":_ready_experiment and not _disposed, "disposed":_disposed, "tick":_tick, "time":_tick * STEP, "fixed_step":STEP, "paused":_options.paused, "parameters":_options.duplicate(true), "camera_mode":_options.camera_mode, "camera":camera, "lanes":_lanes.duplicate(true), "context":_context.duplicate(true), "template":_template.duplicate(true), "visual":_visual.duplicate(true), "events":[], "fire_view":_fire_view.diagnostics() if is_instance_valid(_fire_view) else {}, "wave_surface":{"descriptors":WAVES.duplicate(true),"phase_time":_tick * STEP}, "dropped_seconds":_dropped_seconds, "error":_error, "resources":{"runtime":0,"production_sea":is_instance_valid(_sea),"candidate":is_instance_valid(_fire_view),"storage":0}, "scope":SCOPE}

func _release_presentation() -> void:
	for helper: RefCounted in _zone_anchors.values(): helper.clear()
	_zone_anchors.clear()
	if is_instance_valid(_viewport) and _viewport.size_changed.is_connected(_layout): _viewport.size_changed.disconnect(_layout)
	_viewport = null
	if is_instance_valid(_fire_view):
		_fire_view.dispose(); remove_child(_fire_view); _fire_view.free()
	_fire_view = null
	if is_instance_valid(_sea):
		_sea.dispose(); remove_child(_sea); _sea.free()
	_sea = null
	if is_instance_valid(_hud): remove_child(_hud); _hud.free()
	_hud = null; _strip = null; _label = null
	_lane_labels.clear()
	_ready_experiment = false

func dispose() -> void:
	_disposed = true
	_configured = false
	_release_presentation()
	_surface = null
	_template.clear(); _visual.clear(); _lanes.clear(); _context.clear()
	_tick = 0; _accumulator = 0.0; _dropped_seconds = 0.0
	_camera_focus = Vector3.ZERO
	set_process(false)
	set_physics_process(false)

func _exit_tree() -> void: dispose()
