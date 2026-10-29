extends Node3D
## Real terminal Encounter and production Sea in the laboratory's isolated world.
## The host alone advances 60 Hz authority and the official terminal visual tail.
const Encounter = preload("res://modules/naval_simulation/encounter.gd")
const Sea = preload("res://game/presentation/world/naval_world_view.gd")
const Atmosphere = preload("res://game/presentation/combat/combat_atmosphere.gd")
const TerminalClock = preload("res://game/scenes/common/terminal_presentation_clock.gd")
const Maritime = preload("res://game/ui/shared/maritime_art_theme.gd")
const STEP := 1.0 / 60.0
const DEFAULTS := {"enabled": true, "wind": "calm", "paused": false, "camera_mode": "battle", "seed": 1661}
var _options := DEFAULTS.duplicate(true)
var _encounter: RefCounted
var _sea: Node3D
var _atmosphere: Node3D
var _tail := TerminalClock.new()
var _native: Dictionary = {}
var _visual: Dictionary = {}
var _pending_events: Array = []
var _event_counts := {"fire": 0, "hit": 0, "sink": 0, "splash": 0, "destruction-explosion": 0}
var _event_log: Array = []
var _connected_ships: Dictionary = {}
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

func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	if _configured and not _disposed: _build()

func get_default_options() -> Dictionary: return DEFAULTS.duplicate(true)
func _invalid(reason: String) -> Dictionary: return {"ok": false, "reason": reason, "reset_required": false}

func configure(options: Dictionary = {}) -> Dictionary:
	var next := DEFAULTS.duplicate(true)
	for key: Variant in options:
		if not next.has(key): return _invalid("未知火烟实验参数")
	next.merge(options, true)
	if not next.enabled is bool or not next.paused is bool: return _invalid("火烟和暂停开关无效")
	if next.wind not in ["calm", "crosswind"] or next.camera_mode not in ["battle", "near"]: return _invalid("风或镜头参数无效")
	if not next.seed is int or next.seed < 0 or next.seed > 2147483647: return _invalid("随机种子无效")
	var config := {
		"mode": "terminal", "referenceGunnery": true, "seed": next.seed,
		"battleId": "naval-combat-atmosphere", "playerId": "player",
		"wind": {"direction": {"x": 1.0, "y": 0.0}, "speed": 12.0 if next.wind == "crosswind" else 0.0},
		"oceanWaves": [], "sampleTerrainHeight": _ground,
		"ships": [
			{"id": "player", "name": "受损福船", "kind": "fuchuan", "team": "player", "position": {"x": 0.0, "z": 0.0}, "heading": 0.0, "sailDeployment": 0.0, "hull": 42.0},
			{"id": "enemy", "name": "对射福船", "kind": "fuchuan", "team": "hostile", "position": {"x": 0.0, "z": 55.0}, "heading": 0.0, "sailDeployment": 0.0, "hull": 100.0}
		]
	}
	var encounter := Encounter.new(config)
	if not encounter.last_error.is_empty(): return _invalid(encounter.last_error)
	dispose()
	_options = next
	_encounter = encounter
	_native = encounter.snapshot()
	_visual = _native.duplicate(true)
	_configured = true
	_disposed = false
	_error = ""
	set_process(false)
	set_physics_process(false)
	if is_inside_tree(): _build()
	if not _error.is_empty(): return _invalid(_error)
	return {"ok": true, "ready": _ready_experiment, "pending": not is_inside_tree(), "options": _options.duplicate(true)}

func reset_experiment(overrides: Dictionary = {}) -> Dictionary:
	var next := _options.duplicate(true)
	next.merge(overrides, true)
	var receipt := configure(next)
	if receipt.get("ok", false): receipt.snapshot = inspection_snapshot()
	return receipt

func control_spec() -> Array:
	return [
		{"id": "enabled", "label": "原创火烟（重置对照）", "type": "toggle", "value": _options.enabled},
		{"id": "wind", "label": "风况（重置）", "type": "choice", "value": _options.wind, "choices": [{"value": "calm", "label": "无风"}, {"value": "crosswind", "label": "横风 12 米/秒"}]},
		{"id": "camera_mode", "label": "观察镜头", "type": "choice", "value": _options.camera_mode, "choices": [{"value": "battle", "label": "双舰全景"}, {"value": "near", "label": "受损船近景"}]}
	]

func set_parameter(id: String, value: Variant) -> Dictionary:
	if _disposed or not _configured: return _invalid("实验尚未就绪")
	if id == "enabled" and value is bool:
		return {"ok": true, "id": id, "value": value, "reset_required": value != _options.enabled}
	if id == "wind" and value in ["calm", "crosswind"]:
		return {"ok": true, "id": id, "value": value, "reset_required": value != _options.wind}
	if id == "camera_mode" and value in ["battle", "near"]:
		set_camera_mode(String(value))
		return {"ok": true, "id": id, "value": value, "reset_required": false}
	return _invalid("火烟参数无效")

func set_paused(value: bool) -> void:
	_options.paused = value
	_refresh_label()

func set_camera_mode(value: String) -> void:
	if value not in ["battle", "near"]: return
	_options.camera_mode = value
	_layout()

func orbit_camera(_yaw: float, _pitch: float) -> void: _layout()
func zoom_camera(_amount: float) -> void: pass
func _ground(_x: float, _z: float) -> float: return -80.0
func _water(_x: float, _z: float, _seconds: float) -> float: return 0.0

func _terminal() -> bool: return str(_native.get("status", "")) in ["victory", "defeat", "surrendered"]

func advance(delta: float) -> void:
	if _disposed or not _ready_experiment or _options.paused or not is_finite(delta) or delta <= 0.0: return
	var accepted := minf(delta, 0.25)
	_dropped_seconds += delta - accepted
	_accumulator += accepted
	var consumed := 0.0
	while _accumulator + 1.0e-12 >= STEP:
		_accumulator = maxf(0.0, _accumulator - STEP)
		if _terminal():
			var tail_seconds: float = _tail.advance(_native, ["result"], STEP, 0.0)
			if tail_seconds <= 0.0:
				_accumulator = 0.0
				break
			_tick += 1
			consumed += tail_seconds
			_visual = _tail.snapshot(_native)
			_sea.remember_authoritative_poses(_visual, tail_seconds)
		else:
			_sea.observe_projectiles(_native)
			var player := _ship("player")
			if not player.is_empty() and player.hull > 0.0 and player.crew > 0.0 and player.cooldownSeconds.starboard <= 0.0 and player.ammo.solid > 0:
				_encounter.command({"type": "fire", "shipId": "player", "side": "starboard"})
			# The hostile ship uses normal Encounter AI; no fabricated fire/hit/sink.
			_encounter.step_fixed()
			_native = _encounter.snapshot()
			var events: Array = _encounter.drain_events()
			for event: Dictionary in events: _record_event(event)
			_pending_events.append_array(events)
			_tick += 1
			consumed += STEP
			_tail.advance(_native, ["result"] if _terminal() else [], STEP, STEP)
			_visual = _tail.snapshot(_native)
			_sea.remember_authoritative_poses(_visual, STEP)
			if _terminal():
				# The lethal native step must be displayed at its real time before
				# any visual tail, so ShipDamage owns the genuine destruction birth.
				_present(consumed)
				consumed = 0.0
	if consumed > 0.0: _present(consumed)

func _ship(id: String) -> Dictionary:
	for ship: Dictionary in _native.get("ships", []):
		if ship.id == id: return ship
	return {}

func _record_event(event: Dictionary) -> void:
	var kind := str(event.get("type", ""))
	_event_counts[kind] = int(_event_counts.get(kind, 0)) + 1
	_event_log.append(event.duplicate(true))
	while _event_log.size() > 256: _event_log.pop_front()

func _connect_ship_events() -> void:
	if not is_instance_valid(_sea): return
	for id: String in _sea.ships:
		var ship: Node3D = _sea.ships[id]
		var identity := ship.get_instance_id()
		if _connected_ships.get(id) == identity: continue
		ship.presentation_event.connect(_on_ship_presentation)
		_connected_ships[id] = identity

func _on_ship_presentation(event: Dictionary) -> void:
	if _disposed or not is_instance_valid(_atmosphere): return
	_record_event(event)
	_atmosphere.apply_events([event])

func _anchor(ship_id: String) -> Dictionary:
	# Research-only read adapter. Production APIs stay unchanged in this stage.
	if not is_instance_valid(_sea) or not _sea.ships.has(ship_id): return {}
	var view: Node3D = _sea.ships[ship_id]
	var support: Variant = view.get("_destruction_support")
	var models: Array = view.get("_models")
	var damage: Dictionary = view.damage_diagnostics()
	if not support is Vector3 or models.is_empty() or damage.get("ended", true): return {}
	var model: Node3D = models[0]
	if not is_instance_valid(model) or not model.is_inside_tree(): return {}
	var point: Vector3 = model.global_transform * support
	var seconds: float = float(view.get("_time"))
	if not point.is_finite() or seconds != float(_visual.get("time", -1.0)): return {}
	return {"position": point, "time": seconds, "shipId": ship_id}

func _present(consumed: float) -> void:
	if not is_instance_valid(_sea) or not is_instance_valid(_atmosphere): return
	_visual = _tail.snapshot(_native)
	_atmosphere.apply_snapshot(_visual)
	_connect_ship_events()
	var events: Array = _sea.apply_snapshot(_visual, _pending_events, consumed)
	_pending_events.clear()
	_atmosphere.apply_events(events)
	_atmosphere.refresh_anchors()
	_refresh_label()

func _build() -> void:
	if _ready_experiment or _encounter == null or is_instance_valid(_sea): return
	_viewport = get_viewport()
	_sea = Sea.new()
	_sea.name = "CombatAtmosphereProductionSea"
	add_child(_sea)
	_sea.apply_settings({"quality": "low", "cameraFollow": false, "cameraShake": 0.0})
	if not _sea.configure(_ground, [], _water, _native, {"combat_atmosphere":false,"chunk_radius": 0, "resolution": 8, "ocean_resolution": 40, "ocean_distance": 1200.0, "vegetation": false, "island_details": false, "fidelity_islands": false, "interactive_wake": false}):
		_error = "正式海战场景初始化失败"
		_release_presentation()
		return
	var ocean: MeshInstance3D = _sea.world.get_ocean()
	if not ocean.set_wave_descriptors([]):
		_error = "平静海面参数未获接受"
		_release_presentation()
		return
	ocean.set_reflection_enabled(false)
	_sea.set_camera_controller(_place_camera)
	_atmosphere = Atmosphere.new()
	_atmosphere.name = "IndependentCombatAtmosphere"
	add_child(_atmosphere)
	var prepared: Dictionary = _atmosphere.configure({"enabled": _options.enabled, "quality": "balanced"}, _sea.camera, _water, _anchor)
	if not prepared.get("ok", false):
		_error = str(prepared.get("reason", "原创火烟初始化失败"))
		_release_presentation()
		return
	_connect_ship_events()
	_build_hud()
	_viewport.size_changed.connect(_layout)
	_ready_experiment = true
	_present(0.0)
	_layout()

func _place_camera() -> void:
	if not is_instance_valid(_sea) or not is_instance_valid(_sea.camera): return
	var camera: Camera3D = _sea.camera
	var extent := get_viewport().get_visible_rect().size
	var aspect := extent.x / maxf(1.0, extent.y)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = 45.0
	var focus := Vector3(0.0, 4.0, 27.5)
	var distance := maxf(130.0, 130.0 / maxf(aspect, 0.5))
	if _options.camera_mode == "near":
		focus = Vector3(0.0, 3.5, 0.0)
		distance = maxf(62.0, 62.0 / maxf(aspect, 0.5))
	camera.position = focus + Vector3(0.78, 0.52, -0.48).normalized() * distance
	camera.look_at(focus, Vector3.UP)

func _build_hud() -> void:
	_hud = Control.new()
	_hud.name = "CombatAtmosphereHud"
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.theme = Maritime.create()
	add_child(_hud)
	# Bound telemetry independently of a wrapping label's deferred minimum size.
	_strip = Panel.new()
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.clip_contents = true
	_strip.add_theme_stylebox_override("panel", Maritime.panel(6, "inset"))
	_hud.add_child(_strip)
	_label = Label.new()
	_label.name = "CombatAtmosphereTelemetry"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.clip_text = true
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Maritime.PALE)
	_strip.add_child(_label)
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.offset_left = 10.0; _label.offset_right = -10.0
	_label.offset_top = 6.0; _label.offset_bottom = -6.0

func _layout() -> void:
	if not is_instance_valid(_viewport): return
	if is_instance_valid(_hud):
		var extent := _viewport.get_visible_rect().size
		_hud.size = extent
		var margin := minf(8.0,minf(extent.x,extent.y)*0.25)
		_strip.position = Vector2(margin,margin)
		_strip.size = Vector2(maxf(0.0,extent.x-margin*2.0),minf(72.0,maxf(0.0,extent.y-margin*2.0)))
		_strip.visible = _strip.size.x>=32.0 and _strip.size.y>=20.0
	_place_camera()
	if is_instance_valid(_sea) and is_instance_valid(_sea.world):
		var ocean: MeshInstance3D = _sea.world.get_ocean()
		if is_instance_valid(ocean): ocean.update_projection()
	if is_instance_valid(_atmosphere): _atmosphere.set_camera(_sea.camera)
	_refresh_label()

func _refresh_label() -> void:
	if not is_instance_valid(_label): return
	var particles: Dictionary = _atmosphere.diagnostics() if is_instance_valid(_atmosphere) else {}
	var phase := "暂停" if _options.paused else "终局尾声" if _terminal() else "实弹交战"
	_label.text = "%s · %s   原生 %.2f秒 / 画面 %.2f秒   命中 %d / 击沉 %d\n原创层：烟 %d · 火 %d · 火星 %d；仅真实事件触发，船损与存档不由特效修改。" % ["火烟候选" if _options.enabled else "原有效果基线", phase, float(_native.get("time", 0.0)), float(_visual.get("time", 0.0)), int(_event_counts.hit), int(_event_counts.sink), int(particles.get("active_smoke", 0)), int(particles.get("active_flames", 0)), int(particles.get("active_embers", 0))]

func inspection_snapshot() -> Dictionary:
	var camera: Dictionary = {}
	if is_instance_valid(_sea) and is_instance_valid(_sea.camera):
		var eye: Vector3 = _sea.camera.position
		camera = {"position": [eye.x, eye.y, eye.z], "projection": _sea.camera.projection, "fov": _sea.camera.fov, "fixed": true}
	return {"topic": "naval-combat-atmosphere", "presentation": "dashboard", "ready": _ready_experiment and not _disposed, "disposed": _disposed, "tick": _tick, "time": float(_visual.get("time", 0.0)), "visual_time": float(_visual.get("time", 0.0)), "fixed_step": STEP, "paused": _options.paused, "parameters": _options.duplicate(true), "camera_mode": _options.camera_mode, "camera": camera, "native": _native.duplicate(true), "visual": _visual.duplicate(true), "state": _native.duplicate(true), "tail": _tail.diagnostics(), "atmosphere": _atmosphere.diagnostics() if is_instance_valid(_atmosphere) else {}, "event_counts": _event_counts.duplicate(true), "events": _event_log.duplicate(true), "finished": _terminal() and not _tail.is_playing(), "dropped_seconds": _dropped_seconds, "error": _error, "resources": {"runtime": 1 if _encounter != null else 0, "production_sea": is_instance_valid(_sea), "candidate": is_instance_valid(_atmosphere), "storage": 0}, "scope": "Isolated real terminal Encounter and production sea. Original source effects retained; generated sprites are an explicit candidate. No campaign save, continuous live-fire mechanics or full-game FPS claim."}

func _release_presentation() -> void:
	if is_instance_valid(_viewport) and _viewport.size_changed.is_connected(_layout): _viewport.size_changed.disconnect(_layout)
	_viewport = null
	_connected_ships.clear()
	if is_instance_valid(_atmosphere):
		_atmosphere.dispose()
		remove_child(_atmosphere)
		_atmosphere.free()
	_atmosphere = null
	if is_instance_valid(_sea):
		_sea.dispose()
		remove_child(_sea)
		_sea.free()
	_sea = null
	if is_instance_valid(_hud):
		remove_child(_hud)
		_hud.free()
	_hud = null
	_strip = null
	_label = null
	_ready_experiment = false

func dispose() -> void:
	_disposed = true
	_release_presentation()
	_encounter = null
	_native.clear()
	_visual.clear()
	_pending_events.clear()
	_event_log.clear()
	_event_counts = {"fire": 0, "hit": 0, "sink": 0, "splash": 0, "destruction-explosion": 0}
	_tail.reset()
	_tick = 0
	_accumulator = 0.0
	_dropped_seconds = 0.0
	set_process(false)
	set_physics_process(false)

func _exit_tree() -> void: dispose()
