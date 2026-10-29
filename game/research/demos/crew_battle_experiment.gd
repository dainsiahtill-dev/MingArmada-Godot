extends Node3D
## Presentation of the isolated paid-crew trial. Only the host advances time.
const Trial = preload("res://game/research/demos/crew_battle_trial.gd")
const Sea = preload("res://game/presentation/world/naval_world_view.gd")
const Maritime = preload("res://game/ui/shared/maritime_art_theme.gd")
const STEP := 1.0 / 60.0
const DEFAULTS := {"roster":"ordinary", "repair_helpers":0, "pressure":"duel", "seed":1661, "paused":false, "camera_mode":"fixed"}
const ROSTERS := {"ordinary":"十二名普通水手", "mixed":"八名水手、两名专家", "elite":"六名专家"}
const PRESSURES := {"duel":"双舰对射", "incoming":"承受敌炮", "calm":"停火修船"}
var _options := DEFAULTS.duplicate(true)
var _trial: RefCounted
var _sea: Node3D
var _hud: Control
var _top: PanelContainer
var _bottom: PanelContainer
var _ledger_scroll: ScrollContainer
var _labels: Dictionary = {}
var _viewport: Viewport
var _last_snapshot: Dictionary = {}
var _accumulator := 0.0
var _dropped_seconds := 0.0
var _configured := false
var _disposed := true
var _ready_experiment := false
var _error := ""
var _notice := ""
var _last_contact := "双方尚未开炮"

func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	if _configured and not _disposed: _build()

func get_default_options() -> Dictionary:
	return DEFAULTS.duplicate(true)

static func _helper_count(value: Variant) -> int:
	if value is String: return int(value) if value in ["0", "1", "2"] else -1
	if (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= 0.0 and float(value) <= 2.0: return int(value)
	return -1

func configure(options: Dictionary) -> Dictionary:
	var candidate := DEFAULTS.duplicate(true)
	for key: Variant in options:
		if not DEFAULTS.has(key): return _invalid("未知参数")
	candidate.merge(options, true)
	if not candidate.roster is String or not ROSTERS.has(candidate.roster): return _invalid("未知船员编组")
	if not candidate.pressure is String or not PRESSURES.has(candidate.pressure): return _invalid("未知炮战条件")
	if not candidate.paused is bool or candidate.camera_mode != "fixed": return _invalid("暂停或镜头参数无效")
	var helpers := _helper_count(candidate.repair_helpers)
	if helpers < 0: return _invalid("抢修抽调只接受零、一或二人")
	candidate.repair_helpers = helpers
	var next_trial: RefCounted = Trial.new()
	var receipt: Dictionary = next_trial.configure({"roster":candidate.roster, "repair_helpers":helpers, "pressure":candidate.pressure, "seed":candidate.seed})
	if not receipt.get("ok", false): return _invalid(str(receipt.get("reason", receipt.get("error", "炮战初始化失败"))))
	dispose()
	_options = candidate
	_trial = next_trial
	_last_snapshot = _trial.snapshot()
	_configured = true
	_disposed = false
	_error = ""
	_notice = ""
	_last_contact = "停火中，观察修船" if candidate.pressure == "calm" else "双方尚未开炮"
	set_process(false)
	set_physics_process(false)
	if is_inside_tree(): _build()
	if not _error.is_empty(): return _invalid(_error)
	return {"ok":true, "ready":_ready_experiment, "pending":not is_inside_tree(), "options":_options.duplicate(true)}

func reset_experiment(overrides: Dictionary = {}) -> Dictionary:
	var candidate := _options.duplicate(true)
	candidate.merge(overrides, true)
	var receipt := configure(candidate)
	if receipt.get("ok", false): receipt.snapshot = inspection_snapshot()
	return receipt

func control_spec() -> Array:
	return [
		{"id":"roster", "label":"同预算招聘（重置）", "type":"choice", "value":_options.roster, "choices":[{"value":"ordinary", "label":ROSTERS.ordinary}, {"value":"mixed", "label":ROSTERS.mixed}, {"value":"elite", "label":ROSTERS.elite}]},
		{"id":"repair_helpers", "label":"抽调炮手抢修", "type":"choice", "value":_options.repair_helpers, "choices":[{"value":0, "label":"零人"}, {"value":1, "label":"一人"}, {"value":2, "label":"二人"}]},
		{"id":"pressure", "label":"战况（重置）", "type":"choice", "value":_options.pressure, "choices":[{"value":"duel", "label":PRESSURES.duel}, {"value":"incoming", "label":PRESSURES.incoming}, {"value":"calm", "label":PRESSURES.calm}]}
	]

func set_parameter(id: String, value: Variant) -> Dictionary:
	if _disposed or not _configured: return _invalid("实验尚未就绪")
	if id == "roster":
		if not value is String or not ROSTERS.has(value): return _invalid("未知船员编组")
		return {"ok":true, "id":id, "value":value, "reset_required":value != _options.roster}
	if id == "pressure":
		if not value is String or not PRESSURES.has(value): return _invalid("未知炮战条件")
		return {"ok":true, "id":id, "value":value, "reset_required":value != _options.pressure}
	if id != "repair_helpers": return _invalid("未知参数")
	var count := _helper_count(value)
	if count < 0: return _invalid("抢修抽调只接受零、一或二人")
	var receipt: Dictionary = _trial.assign_helpers(count)
	if not receipt.get("ok", false):
		_notice = "调岗未执行：" + str(receipt.get("reason", receipt.get("error", "请等在途船员到位后再下令")))
		_refresh_labels()
		return _invalid(_notice)
	_options.repair_helpers = count
	_last_snapshot = _trial.snapshot()
	_notice = "已下令抽调 %d 人；离岗后需两秒到位。" % count
	_refresh_labels()
	return {"ok":true, "id":id, "value":count, "reset_required":false}

func _invalid(reason: String) -> Dictionary:
	return {"ok":false, "reason":reason, "reset_required":false}

func advance(delta: float) -> void:
	if _disposed or not _ready_experiment or _options.paused or not is_finite(delta) or delta <= 0.0 or _last_snapshot.get("finished", false): return
	var accepted := minf(delta, 0.25)
	_dropped_seconds += delta - accepted
	_accumulator += accepted
	var events: Array = []
	var consumed := 0.0
	while _accumulator + 1.0e-12 >= STEP:
		_trial.step()
		_accumulator = maxf(0.0, _accumulator - STEP)
		consumed += STEP
		events.append_array(_trial.drain_events())
		_last_snapshot = _trial.snapshot()
		if _last_snapshot.get("finished", false):
			_accumulator = 0.0
			break
	if consumed > 0.0:
		_record_events(events)
		_sea.apply_snapshot(_last_snapshot.native, events, consumed)
		_refresh_labels()

func set_paused(value: bool) -> void:
	_options.paused = value
	_refresh_labels()

func set_camera_mode(_value: String) -> void: pass
func orbit_camera(_yaw: float, _pitch: float) -> void: _layout()
func zoom_camera(_amount: float) -> void: pass

func _ground(_x: float, _z: float) -> float: return -80.0
func _water(_x: float, _z: float, _seconds: float) -> float: return 0.0

func _build() -> void:
	if _ready_experiment or _trial == null or is_instance_valid(_sea): return
	_viewport = get_viewport()
	_sea = Sea.new()
	_sea.name = "CrewBattleProductionSea"
	add_child(_sea)
	_sea.apply_settings({"quality":"low", "cameraFollow":false, "cameraShake":0.0})
	var built: bool = _sea.configure(_ground, [], _water, _last_snapshot.native, {"chunk_radius":0, "resolution":8, "ocean_resolution":40, "ocean_distance":1200.0, "vegetation":false, "island_details":false, "fidelity_islands":false, "interactive_wake":false})
	if not built:
		_error = "正式海战场景初始化失败"
		_release_presentation()
		return
	# This fixture uses flat authoritative water. Configure the production sea
	# through its public wave API, which otherwise retains the normal voyage waves.
	var ocean: MeshInstance3D = _sea.world.get_ocean()
	if not ocean.set_wave_descriptors([]):
		_error = "平静海面参数未获接受"
		_release_presentation()
		return
	ocean.set_reflection_enabled(false)
	_sea.set_camera_controller(_place_camera)
	_place_camera()
	_build_hud()
	_viewport.size_changed.connect(_layout)
	_ready_experiment = true
	_refresh_labels()
	_layout()
	_sea.apply_snapshot(_last_snapshot.native, [], 0.0)

func _place_camera() -> void:
	if not is_instance_valid(_sea) or not is_instance_valid(_sea.camera): return
	var camera: Camera3D = _sea.camera
	var extent := get_viewport().get_visible_rect().size
	var aspect := extent.x / maxf(extent.y, 1.0)
	# Both hulls and the 110m firing corridor remain in one fixed observation.
	# Only viewport aspect changes the framing; accepted combat poses are intact.
	# The production projected sea uses perspective rays from one eye origin.
	# Keep that supported projection instead of flattening its mesh with an
	# orthographic camera whose parallel rays need separate origins.
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = 42.0
	var distance := maxf(145.0, 190.0 / maxf(aspect, 0.5)) / (2.0 * tan(deg_to_rad(camera.fov) * 0.5))
	camera.position = Vector3(0.0, 0.0, 55.0) + Vector3(175.0, 205.0, 0.0).normalized() * distance
	camera.look_at(Vector3(0.0, 0.0, 55.0), Vector3.UP)

func _build_hud() -> void:
	_hud = Control.new()
	_hud.name = "CrewBattleHud"
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.theme = Maritime.create()
	add_child(_hud)
	_top = _panel("CrewBattleShips")
	var ships_row := HBoxContainer.new()
	ships_row.add_theme_constant_override("separation", 18)
	_top.add_child(ships_row)
	_label(ships_row, "CrewBattlePlayer", Maritime.PALE, 16)
	_label(ships_row, "CrewBattleEnemy", Maritime.DANGER, 16)
	_bottom = _panel("CrewBattleLedger")
	_ledger_scroll = ScrollContainer.new()
	_ledger_scroll.name = "CrewBattleLedgerScroll"
	_ledger_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_ledger_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_ledger_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ledger_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bottom.add_child(_ledger_scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 3)
	_ledger_scroll.add_child(rows)
	_label(rows, "CrewBattleGunnery", Maritime.INK, 15)
	_label(rows, "CrewBattleCosts", Maritime.SEA, 15)
	_label(rows, "CrewBattleCombat", Maritime.INK, 15)
	_label(rows, "CrewBattleState", Maritime.MUTED, 14)
	_label(rows, "CrewBattleNotice", Maritime.DANGER, 14)

func _panel(id: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = id
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	# Reuse the generated maritime painting, cropped as an inset information
	# strip so a second ornamental frame does not consume the battle viewport.
	panel.add_theme_stylebox_override("panel", Maritime.panel(7, "inset"))
	_hud.add_child(panel)
	return panel

func _label(parent: Node, id: String, color: Color, font_size: int) -> Label:
	var label := Label.new()
	label.name = id
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	_labels[id] = label
	return label

func _layout() -> void:
	if not is_instance_valid(_hud) or not is_instance_valid(_viewport): return
	var extent := _viewport.get_visible_rect().size
	_hud.position = Vector2.ZERO
	_hud.size = extent
	var width := maxf(1.0, extent.x - 16.0)
	_top.position = Vector2(8.0, 8.0)
	_top.size = Vector2(width, 0.0)
	var ledger_height := minf(106.0, maxf(60.0, extent.y * 0.30))
	_bottom.position = Vector2(8.0, maxf(8.0, extent.y - ledger_height - 8.0))
	_bottom.size = Vector2(width, ledger_height)
	_place_camera()
	# Host layout and paused resize can move the camera after configure's last
	# apply_snapshot. Refresh projection only; never advance the accepted clock.
	if is_instance_valid(_sea) and is_instance_valid(_sea.world):
		var ocean: MeshInstance3D = _sea.world.get_ocean()
		if is_instance_valid(ocean): ocean.update_projection()

func _find_ship(id: String) -> Dictionary:
	for ship: Dictionary in _last_snapshot.get("native", {}).get("ships", []):
		if ship.get("id") == id: return ship
	return {}

func _number(data: Dictionary, field: String, decimals: int = 0) -> String:
	var value: Variant = data.get(field)
	if not (value is float or value is int): return "—"
	return "%.1f" % float(value) if decimals > 0 else "%.0f" % float(value)

func _refresh_labels() -> void:
	if _labels.is_empty() or _last_snapshot.is_empty(): return
	var native: Dictionary = _last_snapshot.get("native", {})
	var player := _find_ship(str(native.get("playerId", "player")))
	var enemy := _find_ship("enemy")
	var crew: Dictionary = _last_snapshot.get("crew", {})
	var contract: Dictionary = _last_snapshot.get("contract", {})
	var metrics: Dictionary = _last_snapshot.get("metrics", {})
	var gunnery: Dictionary = _last_snapshot.get("gunnery", {})
	var transit := 0
	var remaining := 0.0
	for worker: Dictionary in crew.get("workers", []):
		if not str(worker.get("pending_role", "")).is_empty():
			transit += 1
			remaining = maxf(remaining, float(worker.get("transfer_remaining_seconds", 0.0)))
	_labels.CrewBattlePlayer.text = "我船  %s / %s\n有效船员 %s 人" % [_number(player, "hull", 1), _number(player, "maxHull"), _number(crew, "crew_equivalent", 1)]
	_labels.CrewBattleEnemy.text = "敌舰  %s / %s\n有效船员 %s 人" % [_number(enemy, "hull", 1), _number(enemy, "maxHull"), _number(enemy, "crew", 1)]
	var reload_text := "当前 %s秒 · %s" % [_number(gunnery, "current_cooldown", 1), str(gunnery.get("reason", "炮组无法作业"))]
	if gunnery.get("can_work", false):
		reload_text = "当前 %s秒 · 下轮 %s秒" % [_number(gunnery, "current_cooldown", 1), _number(gunnery, "next_reload_seconds", 1)]
	var transit_text := "%d人转岗，还需 %.1f秒" % [transit, remaining] if transit > 0 else "无人转岗"
	_labels.CrewBattleGunnery.text = "炮位 %d人 · %s · %s" % [int(crew.get("counts", {}).get("gunner", 0)), reload_text, transit_text]
	_labels.CrewBattleCosts.text = "招聘 %s · 工资预留 %s · 余款 %s  实验币" % [_number(contract, "recruitment_paid"), _number(contract, "wage_reserved"), _number(contract, "free_cash")]
	_labels.CrewBattleCombat.text = "我方发炮 %s · 命中 %s · 耗弹 %s · 实损 %s · 修复 %s · 木 %s" % [_number(metrics, "player_fire_count"), _number(metrics, "player_hit_count"), _number(metrics, "ammo_spent"), _number(metrics, "hull_damage_taken", 1), _number(metrics, "hull_repaired", 1), _number(crew, "wood", 1)]
	var state_text := "已暂停" if _options.paused else "进行中"
	if _last_snapshot.get("finished", false):
		var outcome := str(_last_snapshot.get("outcome", ""))
		state_text = {"victory":"我方获胜", "defeat":"我方失利", "draw":"双方失去战力", "mutual_loss":"双方失去战力", "timeout":"观察时限已到", "time_limit":"观察时限已到", "stalemate":"观察时限已到", "error":"实验出错，已停止"}.get(outcome, "观察结束")
	_labels.CrewBattleState.text = "%s · %.1f秒 · %s\n调岗影响下轮装填，当前冷却保持原进度。\n固定阵位实验；战斗时间不结算合同日。" % [state_text, float(_last_snapshot.get("time", 0.0)), _last_contact]
	_labels.CrewBattleNotice.text = _notice
	_labels.CrewBattleNotice.visible = not _notice.is_empty()

func _record_events(events: Array) -> void:
	for event: Dictionary in events:
		var owner := "我船" if event.get("shipId") == _last_snapshot.get("native", {}).get("playerId", "player") else "敌舰"
		match event.get("type", ""):
			"fire": _last_contact = owner + "开炮"
			"hit": _last_contact = owner + "炮弹命中"
			"splash": _last_contact = owner + "炮弹落水"
			"sink": _last_contact = owner + "沉没"

func inspection_snapshot() -> Dictionary:
	var visible_text: Dictionary = {}
	for key: String in _labels:
		if is_instance_valid(_labels[key]): visible_text[key] = _labels[key].text
	var camera: Dictionary = {}
	if is_instance_valid(_sea) and is_instance_valid(_sea.camera):
		var eye: Vector3 = _sea.camera.position
		camera = {"position":[eye.x, eye.y, eye.z], "projection":_sea.camera.projection, "fov":_sea.camera.fov, "fixed":true}
	return {"topic":"crew-role-effects", "mode":"battle", "presentation":"dashboard", "ready":_ready_experiment and not _disposed, "disposed":_disposed, "tick":_last_snapshot.get("tick", 0), "time":_last_snapshot.get("time", 0.0), "fixed_step":STEP, "paused":_options.paused, "parameters":_options.duplicate(true), "camera_mode":"fixed", "camera":camera, "state":_last_snapshot.duplicate(true), "native":_last_snapshot.get("native", {}).duplicate(true), "crew":_last_snapshot.get("crew", {}).duplicate(true), "contract":_last_snapshot.get("contract", {}).duplicate(true), "metrics":_last_snapshot.get("metrics", {}).duplicate(true), "finished":_last_snapshot.get("finished", false), "outcome":_last_snapshot.get("outcome", ""), "dropped_seconds":_dropped_seconds, "text":visible_text, "error":_error, "resources":{"controls":_labels.size(), "runtime":1 if _trial != null else 0, "storage":0, "production_sea":is_instance_valid(_sea)}, "scope":"Paid-crew fixed-position native battle experiment; no campaign save, payroll progression, manoeuvring battle win-rate or full-game performance acceptance."}

func _release_presentation() -> void:
	if is_instance_valid(_viewport) and _viewport.size_changed.is_connected(_layout): _viewport.size_changed.disconnect(_layout)
	_viewport = null
	if is_instance_valid(_hud):
		remove_child(_hud)
		_hud.free()
	_hud = null
	_top = null
	_bottom = null
	_ledger_scroll = null
	_labels.clear()
	if is_instance_valid(_sea):
		_sea.dispose()
		remove_child(_sea)
		_sea.free()
	_sea = null
	_ready_experiment = false

func dispose() -> void:
	_disposed = true
	_release_presentation()
	_trial = null
	_last_snapshot.clear()
	_accumulator = 0.0
	_dropped_seconds = 0.0
	_notice = ""
	set_process(false)
	set_physics_process(false)

func _exit_tree() -> void:
	dispose()
