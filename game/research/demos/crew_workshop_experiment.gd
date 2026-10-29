extends Node3D
## Real isolated crew rules. The laboratory owns the clock; no campaign or saves.
const Rules = preload("res://game/research/demos/crew_role_rules.gd")
const Maritime = preload("res://game/ui/shared/maritime_art_theme.gd")
const STEP := 1.0 / 32.0
const PRESETS := ["balanced", "scarce", "emergency"]
const DEFAULTS := {"preset":"balanced", "specialists":true, "repair_detachment":false, "paused":false, "camera_mode":"fixed"}
const ROLE_NAMES := {"cook":"炊事", "musician":"鼓乐", "carpenter":"修船", "gunner":"炮位", "rest":"休息"}

var _options: Dictionary = DEFAULTS.duplicate(true)
var _rules: RefCounted
var _configured := false
var _disposed := false
var _accumulator := 0.0
var _dropped_seconds := 0.0
var _panel: PanelContainer
var _scroll: ScrollContainer
var _grid: GridContainer
var _layout_viewport: Viewport
var _labels: Dictionary = {}
var _roster: VBoxContainer
var _roster_button: Button
var _roster_open := false

func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	if _configured and not _disposed: _build()

func get_default_options() -> Dictionary:
	var defaults := DEFAULTS.duplicate(true)
	# The preset supplies an initial assignment only when the caller has no choice.
	defaults.erase("repair_detachment")
	return defaults

func configure(options: Dictionary) -> Dictionary:
	return _configure(options, true)

func _configure(options: Dictionary, normalize_preset: bool) -> Dictionary:
	var candidate: Dictionary = DEFAULTS.duplicate(true)
	for key: Variant in options:
		if not DEFAULTS.has(key): return _invalid("未知参数")
	candidate.merge(options, true)
	if not candidate.preset is String or candidate.preset not in PRESETS: return _invalid("未知场景")
	for key: String in ["specialists", "repair_detachment", "paused"]:
		if not candidate[key] is bool: return _invalid("开关需要布尔值")
	if not candidate.camera_mode is String or candidate.camera_mode != "fixed": return _invalid("本实验使用固定视图")
	if normalize_preset and not options.has("repair_detachment"):
		candidate.repair_detachment = candidate.preset == "emergency"
	var next_rules: RefCounted = Rules.new()
	var receipt: Dictionary = next_rules.configure({"preset":candidate.preset, "specialists":candidate.specialists})
	if not receipt.get("ok", false): return _invalid("船员规则初始化失败")
	var role := "carpenter" if candidate.repair_detachment else "gunner"
	for worker_id: String in ["crew04", "crew05"]:
		var assigned: Dictionary = next_rules.assign(worker_id, role)
		if not assigned.get("ok", false): return _invalid("调岗配置失败")
	dispose()
	_options = candidate
	_rules = next_rules
	_configured = true
	_disposed = false
	_accumulator = 0.0
	_dropped_seconds = 0.0
	_roster_open = false
	set_process(false)
	set_physics_process(false)
	if is_inside_tree(): _build()
	return {"ok":true, "ready":is_inside_tree(), "pending":not is_inside_tree(), "options":_options.duplicate(true)}

func reset_experiment(overrides: Dictionary = {}) -> Dictionary:
	var candidate: Dictionary = _options.duplicate(true)
	candidate.merge(overrides, true)
	# Changing the fixture resets its initial detachment; other resets retain it.
	if overrides.has("preset") and not overrides.has("repair_detachment"):
		candidate.repair_detachment = candidate.preset == "emergency"
	var receipt := _configure(candidate, false)
	if receipt.ok: receipt.snapshot = inspection_snapshot()
	return receipt

func control_spec() -> Array:
	return [
		{"id":"preset", "label":"船上处境（重置）", "type":"choice", "value":_options.preset, "choices":[{"value":"balanced", "label":"常规休整"}, {"value":"scarce", "label":"缺粮少木"}, {"value":"emergency", "label":"抢修优先"}]},
		{"id":"specialists", "label":"本职专长（重置对照）", "type":"toggle", "value":_options.specialists},
		{"id":"repair_detachment", "label":"抽调两名炮手修船", "type":"toggle", "value":_options.repair_detachment}
	]

func set_parameter(id: String, value: Variant) -> Dictionary:
	if _disposed or not _configured: return _invalid("实验尚未就绪")
	if id == "preset":
		if not value is String or value not in PRESETS: return _invalid("未知场景")
		return {"ok":true, "id":id, "value":value, "reset_required":value != _options.preset}
	if id == "specialists":
		if not value is bool: return _invalid("开关需要布尔值")
		return {"ok":true, "id":id, "value":value, "reset_required":value != _options.specialists}
	if id != "repair_detachment" or not value is bool: return _invalid("无效参数")
	var role := "carpenter" if value else "gunner"
	for worker_id: String in ["crew04", "crew05"]:
		_rules.assign(worker_id, role)
	_options.repair_detachment = value
	_refresh()
	return {"ok":true, "id":id, "value":value, "reset_required":false}

func _invalid(reason: String) -> Dictionary:
	return {"ok":false, "reason":reason, "reset_required":false}

func advance(delta: float) -> void:
	if _disposed or not is_instance_valid(_panel) or _options.paused or not is_finite(delta) or delta <= 0.0: return
	var accepted := minf(delta, STEP * 8.0)
	_dropped_seconds += delta - accepted
	_accumulator += accepted
	while _accumulator + 1.0e-12 >= STEP:
		_rules.step()
		_accumulator = maxf(0.0, _accumulator - STEP)
	_refresh()

func set_paused(value: bool) -> void:
	_options.paused = value
	_refresh()

func set_camera_mode(_value: String) -> void: pass
func orbit_camera(_yaw: float, _pitch: float) -> void: pass
func zoom_camera(_amount: float) -> void: pass

func _build() -> void:
	if is_instance_valid(_panel): return
	_panel = PanelContainer.new()
	_panel.name = "CrewRolePanel"
	_panel.theme = Maritime.create()
	_panel.add_theme_stylebox_override("panel", Maritime.panel(12))
	_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_panel)
	_scroll = ScrollContainer.new()
	_scroll.name = "CrewRoleScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(_scroll)
	var content := VBoxContainer.new()
	content.name = "CrewRoleContent"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	_scroll.add_child(content)
	var title := _label(content, "CrewRoleTitle", "一船人的分工", 27, Maritime.PALE)
	title.add_theme_font_override("font", Maritime.title_font())
	_label(content, "CrewRoleStatus", "", 16, Maritime.MUTED)
	_label(content, "CrewRoleDecision", "", 21, Maritime.SEA)
	_grid = GridContainer.new()
	_grid.name = "CrewRoleMetrics"
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 24)
	_grid.add_theme_constant_override("v_separation", 18)
	content.add_child(_grid)
	_metric("CrewHull", "船体", "海上修补受木材与结构上限约束。")
	_metric("CrewGuns", "炮位战备", "调离炮手会立即减少可用人手。")
	_metric("CrewFood", "伙食", "粮食煮熟后供休息者进食。")
	_metric("CrewMorale", "士气与疲劳", "鼓乐服务休息者；关声音不影响规则。")
	_label(content, "CrewRoleAssignments", "", 17, Maritime.INK)
	_label(content, "CrewRoleLedger", "", 16, Maritime.MUTED)
	_roster_button = Button.new()
	_roster_button.name = "CrewRosterButton"
	_roster_button.text = "查看船员名册"
	_roster_button.custom_minimum_size.y = 38
	_roster_button.add_theme_font_size_override("font_size", 17)
	_roster_button.pressed.connect(_toggle_roster)
	content.add_child(_roster_button)
	_roster = VBoxContainer.new()
	_roster.name = "CrewRoster"
	_roster.add_theme_constant_override("separation", 7)
	content.add_child(_roster)
	for worker: Dictionary in _rules.snapshot().workers:
		_label(_roster, "CrewWorker_" + str(worker.id), "", 16, Maritime.MUTED)
	_roster.hide()
	_label(content, "CrewRoleScope", "船员规则独立实验 · 十二人、五种作业。尚未接入正式航程。", 15, Maritime.MUTED)
	_layout_viewport = get_viewport()
	_layout_viewport.size_changed.connect(_layout)
	_refresh()
	_layout()

func _metric(id: String, title: String, note: String) -> void:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)
	_grid.add_child(column)
	_label(column, id + "Heading", title, 16, Maritime.MUTED)
	_label(column, id, "", 22, Maritime.INK)
	_label(column, id + "Note", note, 15, Maritime.MUTED)

func _label(parent: Node, id: String, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = id
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	_labels[id] = label
	return label

func _layout() -> void:
	if not is_instance_valid(_panel) or not is_instance_valid(_layout_viewport): return
	var extent: Vector2 = _layout_viewport.get_visible_rect().size
	# Painted gold edge and alpha shadow extend beyond the native panel bounds.
	var reference := Rect2(Vector2.ZERO,Vector2(100,100))
	var style: StyleBox = _panel.get_theme_stylebox("panel")
	var painted: Rect2 = style.call("_get_draw_rect",reference) if style.has_method("_get_draw_rect") else reference
	var left := maxf(16.0,-painted.position.x+2.0)
	var top := maxf(16.0,-painted.position.y+2.0)
	var right := maxf(16.0,painted.end.x-reference.end.x+2.0)
	var bottom := maxf(16.0,painted.end.y-reference.end.y+2.0)
	var width := maxf(1.0, minf(920.0, extent.x-left-right))
	_panel.position = Vector2(left+maxf(0.0,(extent.x-left-right-width)*0.5),top)
	_panel.size = Vector2(width,maxf(1.0,extent.y-top-bottom))
	_grid.columns = 2 if width >= 540.0 else 1
	# The host retains the topic title, parameter switches and a compact clock.
	# Short dashboard viewports spend their first screen on decisions/results.
	_labels.CrewRoleTitle.visible = extent.y >= 560.0
	_labels.CrewRoleStatus.visible = extent.y >= 560.0

func _toggle_roster() -> void:
	_roster_open = not _roster_open
	_roster.visible = _roster_open
	_roster_button.text = "收起船员名册" if _roster_open else "查看船员名册"

func _refresh() -> void:
	if not is_instance_valid(_panel) or _rules == null: return
	var state: Dictionary = _rules.snapshot()
	var counts: Dictionary = state.counts
	var ledger: Dictionary = state.ledger
	var rates: Dictionary = state.rates
	var mean_fatigue := 0.0
	for worker: Dictionary in state.workers:
		mean_fatigue += float(worker.fatigue)
		var text := "%s · %s · 疲劳 %.1f" % [str(worker.name), ROLE_NAMES.get(worker.role, worker.role), float(worker.fatigue)]
		var id := "CrewWorker_" + str(worker.id)
		if _labels.has(id): _labels[id].text = text
	if not state.workers.is_empty(): mean_fatigue /= float(state.workers.size())
	_labels.CrewRoleStatus.text = "%s · %.1f 秒 · %s" % ["专业骨干" if _options.specialists else "普通水手对照", float(state.time), "已暂停" if _options.paused else "作业中"]
	_labels.CrewRoleDecision.text = "抢修优先：两名炮手已离岗。" if _options.repair_detachment else "常规值守：四名炮手留在炮位。"
	_labels.CrewFood.text = "粮 %.1f · 熟食 %.1f" % [float(state.grain), float(state.cooked_rations)]
	_labels.CrewHull.text = "%.1f / 100 · 木 %.1f" % [float(state.hull), float(state.wood)]
	_labels.CrewMorale.text = "士气 %.1f · 均疲劳 %.1f" % [float(state.morale), mean_fatigue]
	_labels.CrewGuns.text = "%.0f%% · %d 人在炮位" % [float(state.gun_efficiency) * 100.0, int(counts.get("gunner", 0))]
	_labels.CrewGuns.add_theme_color_override("font_color", Maritime.DANGER if float(state.gun_efficiency) < 1.0 else Maritime.INK)
	_labels.CrewFoodNote.text = "粮食耗尽，炊事已停；已供餐 %.0f 份。" % float(ledger.meals_eaten) if float(state.grain) <= 0.0 else "炊事 %.3f 份/秒；已供餐 %.0f 份。" % [float(rates.cooking), float(ledger.meals_eaten)]
	_labels.CrewMoraleNote.text = "鼓乐恢复 %.3f 点/秒；静音不影响规则。" % float(rates.morale)
	if float(state.wood) <= 0.0:
		_labels.CrewHullNote.text = "木材耗尽，修船已停。"
	elif float(state.hull) >= float(state.sea_repair_cap):
		_labels.CrewHullNote.text = "已达海修上限，完整修复需要船坞。"
	else:
		_labels.CrewHullNote.text = "修船 %.3f 点/秒；海修上限 %.0f。" % [float(rates.repair), float(state.sea_repair_cap)]
	_labels.CrewRoleAssignments.text = "炊事 %d · 鼓乐 %d · 修船 %d在岗/%d分配 · 炮位 %d · 休息 %d" % [int(counts.get("cook", 0)), int(counts.get("musician", 0)), int(state.repair_staffing.active), int(state.repair_staffing.assigned), int(counts.get("gunner", 0)), int(counts.get("rest", 0))]
	_labels.CrewRoleLedger.text = "累计耗粮 %.2f，制餐 %.2f；耗木 %.2f，修复 %.2f。" % [float(ledger.grain_used), float(ledger.meals_cooked), float(ledger.wood_used), float(ledger.hull_repaired)]

func inspection_snapshot() -> Dictionary:
	var state: Dictionary = _rules.snapshot() if _rules != null else {}
	var visible_text: Dictionary = {}
	for key: String in _labels:
		if is_instance_valid(_labels[key]): visible_text[key] = _labels[key].text
	return {"topic":"crew-role-effects", "presentation":"dashboard", "ready":is_instance_valid(_panel) and not _disposed, "disposed":_disposed, "tick":state.get("tick", 0), "time":state.get("time", 0.0), "fixed_step":STEP, "paused":_options.paused, "parameters":_options.duplicate(true), "camera_mode":"fixed", "state":state, "dropped_seconds":_dropped_seconds, "text":visible_text, "roster_open":_roster_open, "resources":{"controls":_labels.size(), "runtime":0, "storage":0}, "scope":"Isolated crew gameplay rules; not production campaign or full-game performance."}

func dispose() -> void:
	_disposed = true
	if is_instance_valid(_layout_viewport) and _layout_viewport.size_changed.is_connected(_layout):
		_layout_viewport.size_changed.disconnect(_layout)
	_layout_viewport = null
	if is_instance_valid(_panel):
		remove_child(_panel)
		_panel.free()
	_panel = null
	_scroll = null
	_grid = null
	_roster = null
	_roster_button = null
	_labels.clear()
	_rules = null
	_accumulator = 0.0
	_dropped_seconds = 0.0
	_roster_open = false

func _exit_tree() -> void:
	dispose()
