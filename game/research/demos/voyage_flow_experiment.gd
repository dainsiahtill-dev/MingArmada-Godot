extends Node3D
const Parchment = preload("res://game/ui/shared/parchment_theme.gd")
## Declared display fixtures, never gameplay completion or a writable campaign.
const Campaign = preload("res://game/domain/mingqi/campaign.gd")
const Story = preload("res://game/domain/mingqi/opening_story.gd")
const Flow = preload("res://game/domain/mingqi/voyage_flow.gd")
const STEP := 1.0 / 32.0
const DEFAULTS := {"preset": "offered", "candidate_enabled": true, "paused": false, "camera_mode": "fixed"}
const PRESETS := ["offered", "underway", "overdue", "partial", "loss"]
var _options: Dictionary = DEFAULTS.duplicate(true)
var _state: Dictionary = {}
var _tick := 0
var _accumulator := 0.0
var _configured := false
var _disposed := false
var _label: Label
var _paper: PanelContainer
var _layout_viewport: Viewport

func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	if _configured and not _disposed: _build()

func get_default_options() -> Dictionary: return DEFAULTS.duplicate(true)
func configure(options: Dictionary) -> Dictionary:
	var candidate := DEFAULTS.duplicate(true)
	for key in options:
		if not DEFAULTS.has(key): return {"ok": false, "reason": "unknown-parameter"}
	candidate.merge(options, true)
	if candidate.preset not in PRESETS or not candidate.candidate_enabled is bool or not candidate.paused is bool or candidate.camera_mode != "fixed": return {"ok": false, "reason": "invalid-parameter"}
	dispose()
	_options = candidate
	_configured = true
	_disposed = false
	_tick = 0
	_accumulator = 0
	_state = _fixture(str(candidate.preset))
	set_process(false)
	set_physics_process(false)
	if is_inside_tree(): _build()
	return {"ok": true, "ready": is_inside_tree(), "pending": not is_inside_tree(), "options": _options.duplicate(true)}

func reset_experiment(options: Dictionary = {}) -> Dictionary:
	var candidate := _options.duplicate(true)
	candidate.merge(options, true)
	var receipt := configure(candidate)
	if receipt.ok: receipt.snapshot = inspection_snapshot()
	return receipt

func control_spec() -> Array:
	var choices: Array = []
	var labels := {"offered": "待接单", "underway": "护航中", "overdue": "已逾期", "partial": "部分交付", "loss": "全部损失"}
	for id in PRESETS: choices.append({"value": id, "label": labels[id]})
	return [{"id": "preset", "label": "只读显示夹具（重置）", "type": "choice", "value": _options.preset, "choices": choices}, {"id": "candidate_enabled", "label": "显示进度与真实回执", "type": "toggle", "value": _options.candidate_enabled}]

func set_parameter(id: String, value: Variant) -> Dictionary:
	if id == "preset" and value in PRESETS: return {"ok": true, "reset_required": value != _options.preset, "id": id, "value": value}
	if id != "candidate_enabled" or not value is bool: return {"ok": false, "reason": "invalid-parameter", "reset_required": false}
	_options[id] = value
	_refresh()
	return {"ok": true, "reset_required": false, "id": id, "value": value}

func advance(delta: float) -> void:
	if not is_instance_valid(_label) or _disposed or _options.paused or not is_finite(delta) or delta <= 0: return
	_accumulator += minf(delta, STEP * 8)
	while _accumulator + 1.0e-12 >= STEP:
		_tick += 1
		_state.simulationSeconds += STEP
		_accumulator -= STEP
	_refresh()

func set_paused(value: bool) -> void: _options.paused = value
func set_camera_mode(_value: String) -> void: pass # Text fixture has one fixed camera.
func orbit_camera(_yaw: float, _pitch: float) -> void: pass
func zoom_camera(_amount: float) -> void: pass

func _fixture(preset: String) -> Dictionary:
	var state := Campaign.new().snapshot()
	if preset in ["underway", "overdue"]:
		state.contracts["convoy-001"].status = "active"
		state.currentPortId = null
		for id in state.contracts["convoy-001"].voyageIds: state.voyages[id].status = "underway"
		state.simulationSeconds = 1801.0 if preset == "overdue" else 300.0
	if preset in ["partial", "loss"]:
		var lost := preset == "loss"
		var id: String = state.campaignId + ":convoy-001:claim"
		state.contracts["convoy-001"].status = "failed" if lost else "settled"
		state.contracts["convoy-001"].receiptId = id
		state.settlements[id] = {"id": id, "kind": "claim-convoy", "details": {"kind": "convoy", "contractId": "convoy-001", "delivered": 0 if lost else 20, "lost": 40 if lost else 20, "baseReward": 0 if lost else 200, "bonus": 0, "ships": [{"dead": 2, "wounded": 3}]}}
	return state

func _build() -> void:
	var paper := PanelContainer.new()
	_paper = paper
	paper.name = "VoyageFlowPaper"
	paper.theme = Parchment.create()
	paper.position = Vector2(24,24)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.add_theme_stylebox_override("panel",Parchment.floating_panel(20))
	add_child(paper)
	_label = Label.new()
	_label.name = "VoyageFlowFixture"
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 22)
	paper.add_child(_label)
	_layout_viewport = get_viewport()
	_layout_viewport.size_changed.connect(_layout)
	_label.minimum_size_changed.connect(func(): _layout.call_deferred())
	_refresh()
	_layout()

func _layout() -> void:
	if not is_instance_valid(_paper) or not is_instance_valid(_layout_viewport): return
	_paper.size = Vector2(maxf(0,minf(720,_layout_viewport.get_visible_rect().size.x-48)),_paper.get_combined_minimum_size().y)

func _refresh() -> void:
	if not is_instance_valid(_label): return
	var flow := Flow.project(_state)
	var text := "首航流程 · 只读界面夹具\n本实验不航行、不发放奖励，不作为完整航程证据。\n\n"
	text += "原目标：" + str(Story.project(_state).objective.title)
	if _options.candidate_enabled:
		text += "\n\n阶段：%s\n期限：%s · 剩余 %.1f秒 · 逾期 %.1f秒" % [flow.active.stage, flow.active.deadlineMode, flow.active.remainingSeconds, flow.active.overdueSeconds]
		for bill: Dictionary in flow.settlements:
			text += "\n实交%d粮 · 损失%d粮\n实际收入%d两 · 死亡%d人 / 伤员%d人" % [bill.delivered, bill.lost, bill.paid, bill.dead, bill.wounded]
		text += "\n\n船务：自有承家号 · 厦门船坞\n检查船况后申请原有帆装改造。"
	_label.text = text

func inspection_snapshot() -> Dictionary:
	return {"topic": "voyage-flow", "ready": is_instance_valid(_label) and not _disposed, "disposed": _disposed, "tick": _tick, "time": _tick * STEP, "step_seconds": STEP, "paused": _options.paused, "parameters": _options.duplicate(true), "camera_mode": "fixed", "resources": {"labels": 1 if is_instance_valid(_label) else 0, "runtime": 0, "storage": 0}, "state": _state.duplicate(true), "flow": Flow.project(_state) if not _state.is_empty() else {}, "text": _label.text if is_instance_valid(_label) else "", "scope": "Read-only fabricated presentation fixtures, not actual gameplay or save evidence."}

func dispose() -> void:
	_disposed = true
	if is_instance_valid(_layout_viewport) and _layout_viewport.size_changed.is_connected(_layout):
		_layout_viewport.size_changed.disconnect(_layout)
	_layout_viewport = null
	if is_instance_valid(_paper):
		remove_child(_paper)
		_paper.free()
	_paper = null
	_label = null
	_state.clear()
	_accumulator = 0

func _exit_tree() -> void: dispose()
