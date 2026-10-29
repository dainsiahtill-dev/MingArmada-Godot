extends Node3D
## Isolated real-ship showcase and real-hit cargo experiment. Host owns every tick.
const Encounter = preload("res://modules/naval_simulation/encounter.gd")
const Sea = preload("res://game/presentation/world/naval_world_view.gd")
const CargoDamage = preload("res://game/domain/mingqi/cargo_damage.gd")
const TerminalClock = preload("res://game/scenes/common/terminal_presentation_clock.gd")
const Maritime = preload("res://game/ui/shared/maritime_art_theme.gd")
const WaveField = preload("res://modules/physics_engine/ocean/wave_field.gd")
const WORLD_PATH := "res://game/presentation/cargo/cargo_world_view.gd"
const GOODS := ["grain", "water", "wood", "iron", "powder", "cloth", "silk", "porcelain", "tea", "sugar", "salt", "spices"]
const NAMES := {"all":"全部十二类", "grain":"粮食", "water":"淡水", "wood":"木料", "iron":"铁锭", "powder":"火药", "cloth":"布匹", "silk":"丝绸", "porcelain":"瓷器", "tea":"茶叶", "sugar":"糖", "salt":"盐", "spices":"香料"}
const STEP := 1.0 / 60.0
const WAVES := [{"direction":{"x":.8,"z":.6},"amplitude":.16,"wavelength":28.0,"speed":.75}, {"direction":{"x":-.6,"z":.8},"amplitude":.08,"wavelength":17.0,"speed":1.15}]
const DEFAULTS := {"stage":"showcase", "good":"all", "camera_mode":"deck", "paused":false, "seed":1661}
var _options := DEFAULTS.duplicate(true)
var _encounter: RefCounted
var _surface: RefCounted
var _sea: Node3D
var _cargo: Node3D
var _tail := TerminalClock.new()
var _native: Dictionary = {}
var _visual: Dictionary = {}
var _inventory: Dictionary = {}
var _drops: Array = []
var _events: Array = []
var _pending_events: Array = []
var _seen_hits: Dictionary = {}
var _event_counts := {"fire":0, "hit":0, "sink":0}
var _splash_count := 0
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
var _camera_focus := Vector3.ZERO
var _water_camera_source := ""

func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	if _configured and not _disposed: _build()

func get_default_options() -> Dictionary: return DEFAULTS.duplicate(true)
func _invalid(reason: String) -> Dictionary: return {"ok":false, "reason":reason, "reset_required":false}
func _ground(_x: float, _z: float) -> float: return -80.0
func _water(x: float, z: float, seconds: float) -> float:
	return _surface.sample_height(x, z, seconds) if _surface != null else NAN

func configure(options: Dictionary = {}) -> Dictionary:
	var next := DEFAULTS.duplicate(true)
	for key in options:
		if not next.has(key): return _invalid("未知货物实验参数")
	next.merge(options, true)
	if next.stage not in ["showcase", "combat"] or next.camera_mode not in ["deck", "water", "battle"]: return _invalid("阶段或镜头参数无效")
	if next.good != "all" and not next.good in GOODS: return _invalid("货种无效")
	if not next.paused is bool or not next.seed is int or next.seed < 0 or next.seed > 2147483647: return _invalid("暂停或随机种子无效")
	var surface := WaveField.new()
	if not surface.configure(WAVES): return _invalid("温和波面参数无效")
	var config := {"mode":"terminal", "referenceGunnery":true, "seed":next.seed, "battleId":"cargo-deck-drift", "playerId":"player", "wind":{"direction":{"x":1.0,"y":0.0},"speed":0.0}, "waveSampler":surface, "oceanWaves":WAVES.duplicate(true), "sampleTerrainHeight":_ground, "ships":[
		{"id":"player", "name":"载货福船", "kind":"fuchuan", "team":"player", "position":{"x":0.0,"z":0.0}, "heading":0.0, "sailDeployment":0.0, "hull":100.0},
		{"id":"enemy", "name":"实弹试射福船", "kind":"fuchuan", "team":"hostile", "position":{"x":0.0,"z":55.0}, "heading":0.0, "sailDeployment":0.0, "hull":100.0}
	]}
	var encounter := Encounter.new(config)
	if not encounter.last_error.is_empty(): return _invalid(encounter.last_error)
	dispose()
	_options = next
	_encounter = encounter
	_surface = surface
	_native = encounter.snapshot()
	_visual = _native.duplicate(true)
	var manifest: Dictionary = {}
	for good: String in GOODS:
		if next.good == "all" or next.good == good: manifest[good] = 10
	_inventory = {"player":manifest}
	_configured = true
	_disposed = false
	_error = ""
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
	var goods_choices: Array = [{"value":"all", "label":NAMES.all}]
	for good: String in GOODS: goods_choices.append({"value":good, "label":NAMES[good]})
	return [
		{"id":"stage", "label":"实验阶段（重置）", "type":"choice", "value":_options.stage, "choices":[{"value":"showcase","label":"甲板陈列"},{"value":"combat","label":"实弹击落"}]},
		{"id":"good", "label":"装载货物（重置）", "type":"choice", "value":_options.good, "choices":goods_choices},
		{"id":"camera_mode", "label":"观察镜头", "type":"choice", "value":_options.camera_mode, "choices":[{"value":"deck","label":"甲板近景"},{"value":"water","label":"落水跟随"},{"value":"battle","label":"双舰全景"}]}
	]

func set_parameter(id: String, value: Variant) -> Dictionary:
	if _disposed or not _configured: return _invalid("实验尚未就绪")
	if id == "stage" and value in ["showcase", "combat"]: return {"ok":true, "id":id, "value":value, "reset_required":value != _options.stage}
	if id == "good" and (value == "all" or value in GOODS): return {"ok":true, "id":id, "value":value, "reset_required":value != _options.good}
	if id == "camera_mode" and value in ["deck", "water", "battle"]:
		set_camera_mode(str(value))
		return {"ok":true, "id":id, "value":value, "reset_required":false}
	return _invalid("货物参数无效")

func set_paused(value: bool) -> void:
	_options.paused = value
	_refresh_label()

func set_camera_mode(value: String) -> void:
	if not value in ["deck", "water", "battle"]: return
	_options.camera_mode = value
	_layout()

func orbit_camera(_yaw: float, _pitch: float) -> void: _layout()
func zoom_camera(_amount: float) -> void: pass

func _terminal() -> bool: return str(_native.get("status", "")) in ["victory", "defeat", "surrendered"]

func advance(delta: float) -> void:
	if _disposed or not _ready_experiment or _options.paused or not is_finite(delta) or delta <= 0.0: return
	# Showcase deliberately holds real native t=0; only explicit combat may fire.
	if _options.stage == "showcase": return
	var accepted := minf(delta, .25)
	_dropped_seconds += delta - accepted
	_accumulator += accepted
	var consumed := 0.0
	while _accumulator + 1e-12 >= STEP:
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
				_encounter.command({"type":"fire", "shipId":"player", "side":"starboard"})
			_encounter.step_fixed()
			_native = _encounter.snapshot()
			var events: Array = _encounter.drain_events()
			for event: Dictionary in events:
				_record_event(event)
				_commit_hit(event)
			_pending_events.append_array(events)
			_tick += 1
			consumed += STEP
			_tail.advance(_native, ["result"] if _terminal() else [], STEP, STEP)
			_visual = _tail.snapshot(_native)
			_sea.remember_authoritative_poses(_visual, STEP)
			if _terminal():
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
	_events.append(event.duplicate(true))
	while _events.size() > 512: _events.pop_front()

func _commit_hit(event: Dictionary) -> void:
	if event.get("type") != "hit": return
	var target := str(event.get("targetId", ""))
	if not _inventory.has(target) or _seen_hits.has(event.get("id")): return
	var ship := _ship(target)
	if ship.is_empty() or not event.get("position") is Dictionary: return
	var visual: Dictionary = ship.visual
	var velocity: Dictionary = visual.velocity
	var context := {"id":event.id, "campaignId":"cargo-laboratory", "battleId":_native.battleId, "vesselId":target, "sourceShipId":event.shipId, "ammo":event.ammo, "nativeTick":int(_native.tick), "eventTime":float(event.time), "nativeTime":float(_native.time), "campaignTime":float(_native.time), "position":event.position.duplicate(true), "pose":{"position":{"x":visual.position.x,"z":visual.position.z},"heading":visual.heading,"speed":Vector2(float(velocity.x),float(velocity.z)).length()}}
	var planned: Dictionary = CargoDamage.plan(_inventory[target], context)
	if not planned.get("ok", false):
		_error = "真实命中的货损计划被拒绝：" + str(planned.get("reason", ""))
		return
	# This isolated inventory is the sole authority for the experiment's cargo.
	# Commit quantity and receipt together, before handing either to presentation.
	_inventory[target] = planned.afterCargo.duplicate(true)
	_seen_hits[event.id] = true
	if int(planned.loss) > 0: _drops.append(planned.details.duplicate(true))

func _ship_model(id: String) -> Dictionary:
	if not is_instance_valid(_sea) or not _sea.ships.has(id): return {}
	var actor: Node3D = _sea.ships[id]
	var models: Array = actor.get("_models")
	if models.is_empty(): return {}
	var model: Node3D = models[0]
	if not is_instance_valid(model) or not model.is_inside_tree(): return {}
	return {"model":model, "kind":str(actor.get("_kind"))}

func _present(consumed: float) -> void:
	if not is_instance_valid(_sea) or not is_instance_valid(_cargo): return
	_visual = _tail.snapshot(_native)
	_sea.apply_snapshot(_visual, _pending_events, consumed)
	_pending_events.clear()
	var receipt: Dictionary = _cargo.apply_snapshot(_visual, {"epoch":"cargo-deck-drift", "time":float(_visual.time), "manifests":_inventory, "drops":_drops})
	if not receipt.get("ok", false): _error = "货物呈现存在未完成项：" + str(receipt.get("errors", receipt.get("reason", "")))
	var splashes: Array = _cargo.drain_splashes()
	_splash_count += splashes.size()
	if not splashes.is_empty(): _sea.effects.apply_events(splashes)
	_place_camera()
	if is_instance_valid(_sea.world): _sea.world.get_ocean().update_projection()
	_refresh_label()

func _build() -> void:
	if _ready_experiment or _encounter == null or is_instance_valid(_sea): return
	var world_script: Script = load(WORLD_PATH)
	if world_script == null:
		_error = "货物世界呈现不可用"
		return
	_viewport = get_viewport()
	_sea = Sea.new()
	_sea.name = "CargoDeckProductionSea"
	add_child(_sea)
	_sea.apply_settings({"quality":"low", "cameraFollow":false, "cameraShake":0.0})
	if not _sea.configure(_ground, [], _water, _native, {"chunk_radius":0, "resolution":8, "ocean_resolution":40, "ocean_distance":1200.0, "vegetation":false, "island_details":false, "fidelity_islands":false, "interactive_wake":false}):
		_error = "正式海战场景初始化失败"
		_release_presentation()
		return
	var ocean: MeshInstance3D = _sea.world.get_ocean()
	if not ocean.set_wave_descriptors(_native.oceanWaves):
		_error = "温和波面参数未获接受"
		_release_presentation()
		return
	ocean.set_reflection_enabled(false)
	_sea.set_camera_controller(_place_camera)
	_cargo = world_script.new()
	_cargo.name = "IndependentCargoWorld"
	add_child(_cargo)
	var prepared: Dictionary = _cargo.configure(_water, _ship_model)
	if not prepared.get("ok", false):
		_error = str(prepared.get("reason", "货物呈现初始化失败"))
		_release_presentation()
		return
	_build_hud()
	_viewport.size_changed.connect(_layout)
	_ready_experiment = true
	_present(0.0)
	_layout()

func _place_camera() -> void:
	if not is_instance_valid(_sea) or not is_instance_valid(_sea.camera): return
	var camera: Camera3D = _sea.camera
	var size := get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(1.0, size.y)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = 42.0
	var focus := Vector3(0, 3.2, 0)
	var distance := 23.0
	var direction := Vector3(.72, 1.25, -.65).normalized()
	var state: Dictionary = _cargo.inspection_snapshot() if is_instance_valid(_cargo) else {}
	var deck: Dictionary = state.get("decks", {}).get("player", {})
	var displayed: Array = deck.get("goods", [])
	if not displayed.is_empty():
		var low: Vector3 = displayed[0].world_anchor
		var high := low
		for entry: Dictionary in displayed:
			var p: Vector3 = entry.world_anchor
			low = low.min(p); high = high.max(p)
		focus = (low + high) * .5 + Vector3.UP * .3
		distance = maxf(6.5, maxf(high.x-low.x, high.z-low.z) * 1.7 + 4.0)
	if _options.camera_mode == "water":
		var lots: Array = state.get("floating", [])
		var source_id := str(lots[0].get("shipId", "player")) if not lots.is_empty() else "player"
		var source: Dictionary = _ship_model(source_id)
		var model: Node3D = source.get("model")
		if not is_instance_valid(model): return
		var hull := model.find_child("hull", true, false) as MeshInstance3D
		if hull == null or hull.mesh == null: return
		var center := model.global_position
		if not lots.is_empty():
			var p: Array = lots[0].position
			focus = Vector3(float(p[0]), float(p[1]) + .2, float(p[2]))
			var surface_y := _water(focus.x, focus.z, float(_visual.get("time", 0.0)))
			if is_finite(surface_y): focus.y = maxf(focus.y, surface_y + .15)
		else:
			# Model-local X is the cross-ship direction. At native heading zero
			# ShipView rotates it onto world Z; fixed world X points into the hull.
			var side_axis := hull.global_basis.x
			side_axis.y = 0.0; side_axis = side_axis.normalized()
			var other: Dictionary = _ship_model("enemy" if source_id == "player" else "player")
			var other_model: Node3D = other.get("model")
			var sign_side := 1.0
			if is_instance_valid(other_model) and side_axis.dot(other_model.global_position-center) < 0.0: sign_side = -1.0
			var bounds := hull.mesh.get_aabb()
			var local_focus := hull.to_local(focus)
			local_focus.x = bounds.end.x + 2.0 if sign_side > 0.0 else bounds.position.x - 2.0
			local_focus.z = clampf(local_focus.z,bounds.position.z+.5,bounds.end.z-.5)
			local_focus.y = 0.0
			focus = hull.to_global(local_focus)
			focus.y = _water(focus.x, focus.z, float(_visual.get("time", 0.0))) + .15
		var outward := focus-center
		outward.y = 0.0
		if outward.length_squared() < 1e-8: return
		outward = outward.normalized()
		var tangent := Vector3(-outward.z,0,outward.x)
		var offset := outward*6.6 + Vector3.UP*4.4 + tangent*1.2
		distance = offset.length()
		direction = offset.normalized()
		_water_camera_source = source_id
	elif _options.camera_mode == "battle":
		focus = Vector3(0, 4, 27.5)
		distance = 130.0
		direction = Vector3(.78,.52,-.48).normalized()
	distance /= minf(1.0, maxf(.5, aspect))
	camera.global_position = focus + direction * distance
	camera.look_at(focus, Vector3.UP)
	_camera_focus = focus
	if _options.camera_mode != "water": _water_camera_source = ""

func _build_hud() -> void:
	_hud = Control.new(); _hud.name = "CargoExperimentHud"
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.theme = Maritime.create(); add_child(_hud)
	# Telemetry has a fixed viewport budget. A wrapping Label must not feed its
	# stale 1px-width minimum height back into a root-level PanelContainer.
	_strip = Panel.new(); _strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.clip_contents = true
	_strip.add_theme_stylebox_override("panel", Maritime.panel(6, "inset")); _hud.add_child(_strip)
	_label = Label.new(); _label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.clip_text = true
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Maritime.PALE); _strip.add_child(_label)
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.offset_left = 10.0; _label.offset_right = -10.0
	_label.offset_top = 6.0; _label.offset_bottom = -6.0

func _layout() -> void:
	if not is_instance_valid(_viewport): return
	var size := _viewport.get_visible_rect().size
	if is_instance_valid(_hud):
		var margin := minf(8.0, minf(size.x, size.y) * .25)
		_hud.size = size
		_strip.position = Vector2(margin, margin)
		_strip.size = Vector2(minf(650.0,maxf(0.0,size.x-margin*2.0)),minf(72.0,maxf(0.0,size.y-margin*2.0)))
		_strip.visible = _strip.size.x >= 32.0 and _strip.size.y >= 20.0
	_place_camera()
	if is_instance_valid(_sea) and is_instance_valid(_sea.world): _sea.world.get_ocean().update_projection()
	_refresh_label()

func _refresh_label() -> void:
	if not is_instance_valid(_label): return
	var total := 0
	for count in _inventory.get("player", {}).values(): total += int(count)
	var loss := 0
	for drop: Dictionary in _drops: loss += int(drop.quantity)
	var state: Dictionary = _cargo.inspection_snapshot() if is_instance_valid(_cargo) else {}
	var deck: Dictionary = state.get("decks", {}).get("player", {})
	var visible_goods: Array = deck.get("goods", [])
	var overflow: Array = deck.get("overflow_goods", [])
	var phase := "甲板陈列" if _options.stage == "showcase" else "实弹交战"
	if _options.paused: phase += " · 已暂停"
	_label.text = "%s · %s\n船货 %d · 货损 %d · 可见 %d 类 · 水花 %d" % [phase,NAMES[_options.good],total,loss,visible_goods.size(),_splash_count]
	if not overflow.is_empty(): _label.text += "\n安全位置不足：%d 类货物未展示" % overflow.size()
	elif _strip.size.x >= 500.0:
		if _options.stage == "showcase": _label.text += "\n选择单类可近看包装；切换实弹阶段观察真实击落。"
		else: _label.text += "\n落水来自实弹命中；每件模型代表一批货物。"

func inspection_snapshot() -> Dictionary:
	var camera: Dictionary = {}
	if is_instance_valid(_sea) and is_instance_valid(_sea.camera):
		var p: Vector3 = _sea.camera.global_position
		camera = {"position":[p.x,p.y,p.z], "focus":[_camera_focus.x,_camera_focus.y,_camera_focus.z], "water_source_ship":_water_camera_source, "fov":_sea.camera.fov}
	var phase := float(_visual.get("time",0.0))
	var wave_state := {"descriptors":_native.get("oceanWaves",[]).duplicate(true), "phase_time":phase, "probe_position":[6.0,2.0], "probe_height":_water(6.0,2.0,phase) if _surface != null else 0.0}
	return {"topic":"cargo-deck-drift", "presentation":"dashboard", "ready":_ready_experiment and not _disposed, "disposed":_disposed, "tick":_tick, "time":phase, "fixed_step":STEP, "paused":_options.paused, "parameters":_options.duplicate(true), "camera_mode":_options.camera_mode, "camera":camera, "native":_native.duplicate(true), "visual":_visual.duplicate(true), "inventory":_inventory.duplicate(true), "drops":_drops.duplicate(true), "events":_events.duplicate(true), "event_counts":_event_counts.duplicate(true), "splash_count":_splash_count, "cargo":_cargo.inspection_snapshot() if is_instance_valid(_cargo) else {}, "wave_surface":wave_state, "tail":_tail.diagnostics(), "error":_error, "dropped_seconds":_dropped_seconds, "resources":{"runtime":1 if _encounter != null else 0, "production_sea":is_instance_valid(_sea), "cargo_world":is_instance_valid(_cargo), "storage":0}, "scope":"Original GLBs on actual HeroShipView deck; isolated CargoDamage commit from real Encounter hits. Encounter physics, visible sea and drifting cargo share gentle accepted-time waves. No campaign persistence, fake hit, recovered inventory, sea-engineering buoyancy or full-game performance claim."}

func _release_presentation() -> void:
	if is_instance_valid(_viewport) and _viewport.size_changed.is_connected(_layout): _viewport.size_changed.disconnect(_layout)
	_viewport = null
	if is_instance_valid(_cargo):
		_cargo.dispose(); remove_child(_cargo); _cargo.free()
	_cargo = null
	if is_instance_valid(_sea):
		_sea.dispose(); remove_child(_sea); _sea.free()
	_sea = null
	if is_instance_valid(_hud): remove_child(_hud); _hud.free()
	_hud = null; _strip = null; _label = null
	_ready_experiment = false

func dispose() -> void:
	_disposed = true
	_release_presentation()
	_encounter = null
	_surface = null
	_native.clear(); _visual.clear(); _inventory.clear(); _drops.clear(); _events.clear(); _pending_events.clear(); _seen_hits.clear()
	_event_counts = {"fire":0,"hit":0,"sink":0}
	_splash_count = 0; _tick = 0; _accumulator = 0.0; _dropped_seconds = 0.0
	_camera_focus = Vector3.ZERO; _water_camera_source = ""
	_tail.reset(); set_process(false); set_physics_process(false)

func _exit_tree() -> void: dispose()
