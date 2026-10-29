extends Node3D
## Internal fixtures exercise progress only; no real world, campaign save or rewards.
const Maritime = preload("res://game/ui/shared/maritime_art_theme.gd")
const CATALOG_PATH := "res://game/domain/story_campaign/catalog.gd"
const PROGRESS_PATH := "res://game/domain/story_campaign/progress.gd"
const STEP := 1.0 / 60.0
const SCOPE := "synthetic-progress-fixture; no real gameplay completion"
const HEADING := "主线进度合成实验 · 非真实任务通关"
const DEFAULTS := {"fixture":"complete", "paused":false, "camera_mode":"overview", "seed":1661}
const REGIONS := {"REG-01":"闽南双门", "REG-02":"海峡沙洲", "REG-03":"东洋岛链", "REG-04":"粤海门庭", "REG-05":"吕宋外湾", "REG-06":"海峡转口", "REG-07":"爪哇北岸"}
const PHASES := {"briefing":"待出发", "active":"观察目标", "review":"结果复核", "recovery":"失败恢复", "complete":"合成序列完结"}
const OUTCOMES := {"success":"合成成功", "failure":"合成失败", "partial":"部分达成", "retreat":"撤退"}
var _options := DEFAULTS.duplicate(true)
var _progress: RefCounted
var _chapters: Array = []
var _tick := 0
var _accumulator := 0.0
var _transitions := 0
var _dropped_seconds := 0.0
var _configured := false
var _disposed := true
var _blocked := false
var _observed := false
var _failed_once := false
var _error := ""
var _viewport: Viewport
var _panel: Panel
var _content: VBoxContainer
var _scroll: ScrollContainer
var _grid: GridContainer
var _current: Label
var _status: Label
var _log: Label
var _cells: Array[Label] = []

func _ready() -> void:
	set_process(false); set_physics_process(false)
	if _configured and not _disposed: _build()

func get_default_options() -> Dictionary: return DEFAULTS.duplicate(true)
func _invalid(reason: String) -> Dictionary: return {"ok":false, "reason":reason, "reset_required":false}

func _option_error(options: Dictionary) -> String:
	for key: Variant in options:
		if not DEFAULTS.has(key): return "未知主线合成实验参数"
	if options.fixture not in ["complete", "recover", "missing-handover"]: return "合成夹具无效"
	if not options.paused is bool or options.camera_mode not in ["overview", "current"]: return "暂停或观察视图无效"
	if not options.seed is int or options.seed < 0 or options.seed > 2147483647: return "种子必须为非负整数"
	return ""

func configure(options: Dictionary = {}) -> Dictionary:
	var next := DEFAULTS.duplicate(true)
	next.merge(options, true)
	var reason := _option_error(next)
	if not reason.is_empty(): return _invalid(reason)
	if not FileAccess.file_exists(CATALOG_PATH) or not FileAccess.file_exists(PROGRESS_PATH): return _invalid("主线内容或进度合同尚未提供")
	var catalog: Script = load(CATALOG_PATH)
	var progress_script: Script = load(PROGRESS_PATH)
	if catalog == null or progress_script == null or not progress_script.can_instantiate(): return _invalid("主线合同无法加载")
	var loaded: Dictionary = catalog.call("load_content")
	if not loaded.get("ok", false): return _invalid(str(loaded.get("reason", "内容验证失败")))
	var progress: RefCounted = progress_script.new()
	var configured: Dictionary = progress.configure(int(next.seed), "story-campaign-fixture")
	if not configured.get("ok", false): return _invalid(str(configured.get("reason", "进度初始化失败")))
	dispose()
	_options = next; _progress = progress; _chapters = loaded.data.chapters.duplicate(true)
	_configured = true; _disposed = false; _error = ""
	set_process(false); set_physics_process(false)
	if is_inside_tree(): _build()
	return {"ok":true, "ready":is_instance_valid(_panel), "pending":not is_inside_tree(), "options":_options.duplicate(true)}

func reset_experiment(overrides: Dictionary = {}) -> Dictionary:
	var next := _options.duplicate(true)
	next.merge(overrides, true)
	var result := configure(next)
	if result.get("ok", false): result.snapshot = inspection_snapshot()
	return result

func control_spec() -> Array:
	return [
		{"id":"fixture", "label":"合成进度夹具（重置）", "type":"choice", "value":_options.fixture, "choices":[{"value":"complete","label":"30阶段声明事实齐备"},{"value":"recover","label":"首阶段失败再重试"},{"value":"missing-handover","label":"终章缺少港口接收"}]},
		{"id":"camera_mode", "label":"观察视图", "type":"choice", "value":_options.camera_mode, "choices":[{"value":"overview","label":"24章全程图"},{"value":"current","label":"当前章与目标"}]}
	]

func set_parameter(id: String, value: Variant) -> Dictionary:
	if _disposed or not _configured: return _invalid("实验尚未就绪")
	var next := _options.duplicate(true)
	next[id] = value
	var reason := _option_error(next)
	if not reason.is_empty(): return _invalid(reason)
	if id == "camera_mode": set_camera_mode(str(value))
	elif id == "paused": set_paused(value)
	return {"ok":true, "id":id, "value":value, "reset_required":id in ["fixture", "seed"] and value != _options[id]}

func set_paused(value: bool) -> void:
	_options.paused = value
	_refresh()
func set_camera_mode(value: String) -> void:
	if value not in ["overview", "current"]: return
	_options.camera_mode = value
	_refresh(); _layout()
func orbit_camera(_yaw: float, _pitch: float) -> void: _layout()
func zoom_camera(_amount: float) -> void: pass

func advance(delta: float) -> void:
	if _disposed or not is_instance_valid(_panel) or _options.paused or not _error.is_empty() or not is_finite(delta) or delta <= 0.0: return
	var accepted := minf(delta, .25)
	_dropped_seconds += delta - accepted
	_accumulator += accepted
	while _accumulator + 1.0e-12 >= STEP:
		_accumulator = maxf(0.0, _accumulator - STEP)
		_tick += 1
		if _tick % 15 == 0 and not _blocked: _act()
	_refresh()

func _act() -> void:
	var state: Dictionary = _progress.snapshot()
	var stage: Dictionary = _progress.inspection_snapshot().currentStage
	var result: Dictionary = {"ok":true}
	match str(state.phase):
		"briefing":
			_observed = false
			result = _progress.begin(int(state.revision))
		"active":
			if _options.fixture == "recover" and not _failed_once:
				result = _progress.settle(int(state.revision), "failure", false)
				_failed_once = true
			elif not _observed:
				var facts: Array = []
				for objective: Dictionary in stage.objectives:
					if _options.fixture == "missing-handover" and stage.id == "T10" and objective.kind == "port-handover": continue
					facts.append({"id":"fixture:%s:%d:%s" % [stage.id, state.attempt, objective.id], "runId":state.runId, "stageId":stage.id, "attempt":int(state.attempt), "objectiveId":objective.id, "progress":int(objective.required), "source":"world-snapshot"})
				result = _progress.observe(facts)
				_observed = true
				_blocked = _options.fixture == "missing-handover" and stage.id == "T10"
			else: result = _progress.settle(int(state.revision), "success", true)
		"review": result = _progress.continue_story(int(state.revision))
		"recovery": result = _progress.retry(int(state.revision))
		"complete": return
	if result.get("ok", false): _transitions += 1
	else: _error = "合成合同拒绝：" + str(result.get("reason", "未知原因"))

func _build() -> void:
	if is_instance_valid(_panel): return
	_panel = Panel.new(); _panel.name = "StoryCampaignFlowDashboard"
	_panel.theme = Maritime.create(); _panel.clip_contents = true
	_panel.add_theme_stylebox_override("panel", Maritime.panel(12, "inset")); add_child(_panel)
	_content = VBoxContainer.new(); _content.add_theme_constant_override("separation", 10); _panel.add_child(_content)
	_label(_content, "CampaignScopeHeading", HEADING, 22, Maritime.PALE)
	_label(_content, "CampaignEvidenceBoundary", "内部声明事实夹具 · 仅验证进度合同；真实操船、交易、战斗与单存档全程尚待接线。", 14, Maritime.MUTED)
	_status = _label(_content, "CampaignAcceptedState", "", 16, Maritime.SEA)
	_scroll = ScrollContainer.new(); _scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; _content.add_child(_scroll)
	var body := VBoxContainer.new(); body.size_flags_horizontal = Control.SIZE_EXPAND_FILL; body.add_theme_constant_override("separation", 16); _scroll.add_child(body)
	_grid = GridContainer.new(); _grid.add_theme_constant_override("h_separation", 18); _grid.add_theme_constant_override("v_separation", 14)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL; body.add_child(_grid)
	for chapter: Dictionary in _chapters: _cells.append(_label(_grid, str(chapter.id), "", 14, Maritime.MUTED))
	_current = _label(body, "CampaignCurrentChapter", "", 17, Maritime.INK)
	_log = _label(body, "CampaignSyntheticOutcomeLog", "", 14, Maritime.MUTED)
	_viewport = get_viewport(); _viewport.size_changed.connect(_layout)
	_refresh(); _layout()

func _label(parent: Node, id: String, text: String, size: int, color: Color) -> Label:
	var label := Label.new(); label.name = id; label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size); label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _layout() -> void:
	if not is_instance_valid(_panel) or not is_instance_valid(_viewport): return
	var extent := _viewport.get_visible_rect().size
	var inset := minf(14.0, minf(extent.x, extent.y) * .1)
	_panel.position = Vector2(inset, inset); _panel.size = (extent - Vector2.ONE * inset * 2.0).max(Vector2.ZERO)
	_content.position = Vector2(14, 14); _content.size = (_panel.size - Vector2(28,28)).max(Vector2.ZERO)
	_grid.columns = 4 if _content.size.x >= 1000 else (3 if _content.size.x >= 660 else (2 if _content.size.x >= 420 else 1))

func _refresh() -> void:
	if not is_instance_valid(_panel) or _progress == null: return
	var state: Dictionary = _progress.snapshot()
	var stage: Dictionary = _progress.inspection_snapshot().currentStage
	_status.text = "%s · %d / 30 阶段 · %.2f 接受秒 · %s" % [PHASES[state.phase], mini(int(state.stageIndex) + 1, 30), _tick * STEP, "已暂停" if _options.paused else "运行中"]
	if _blocked: _status.text += "\n已停在T10：缺少港口接收事实，未结算。"
	if not _error.is_empty(): _status.text += "\n" + _error
	_grid.visible = _options.camera_mode == "overview"
	_current.visible = not _grid.visible
	var chapter_index := 0
	for index: int in _chapters.size():
		var chapter: Dictionary = _chapters[index]
		var current: bool = not stage.is_empty() and stage.chapterId == chapter.id
		if current: chapter_index = index
		var passed: bool = state.phase == "complete" or int(chapter.order) < int(_chapter_order(stage))
		_cells[index].text = "%s %s · %d\n%s" % ["当前" if current else ("已结" if passed else "待接"), chapter.id, chapter.year, chapter.title]
		_cells[index].add_theme_color_override("font_color", Maritime.PALE if current else (Maritime.SEA if passed else Maritime.MUTED))
	if stage.is_empty():
		_current.text = "30阶段合成序列已结束。\n真实世界适配、实际任务通关及存档验收尚未发生。"
	else:
		var chapter: Dictionary = _chapters[chapter_index]
		var regions: Array[String] = []
		for id: String in chapter.regionIds: regions.append(str(REGIONS.get(id,id)))
		_current.text = "%s · %s · %d年 · %s\n%s\n\n所求：%s\n冲突：%s\n转折：%s\n\n引入：%s\n复用：%s\n\n%s\n%s\n\n待核目标（合成计数）" % [chapter.id, "郑芝龙" if state.protagonistId == "zheng-zhilong" else "郑成功", chapter.year, " / ".join(regions), chapter.title, chapter.drama.want, chapter.drama.conflict, chapter.drama.turn, "、".join(chapter.teaches), "、".join(chapter.reuses), stage.title, stage.briefing]
		for objective: Dictionary in stage.objectives:
			_current.text += "\n%s · %d / %d %s" % [objective.target, state.objectiveProgress.get(objective.id,0), objective.required, objective.unit]
		_current.text += "\n\n失败出口：" + str(stage.recovery)
	_log.text = "合成回执记录 · 尚无真实行动回执"
	for index: int in range(maxi(0, state.receipts.size() - 3), state.receipts.size()):
		var receipt: Dictionary = state.receipts[index]
		_log.text += "\n%s · 尝试%d · %s" % [receipt.stageId, receipt.attempt, OUTCOMES[receipt.outcome]]
	if state.handoff.get("done", false): _log.text += "\n交棒标记已记录：郑芝龙 → 郑成功；未交接真实船货。"

func _chapter_order(stage: Dictionary) -> int:
	if stage.is_empty(): return 25
	for chapter: Dictionary in _chapters:
		if chapter.id == stage.chapterId: return int(chapter.order)
	return 0

func inspection_snapshot() -> Dictionary:
	var progress: Dictionary = _progress.snapshot() if _progress != null else {}
	var stage: Dictionary = _progress.inspection_snapshot().currentStage if _progress != null else {}
	var text := HEADING
	if is_instance_valid(_panel):
		text += "\n" + _status.text + "\n"
		if _grid.visible:
			for cell: Label in _cells: text += cell.text + "\n"
		else: text += _current.text
		text += "\n" + _log.text
	return {"topic":"story-campaign-flow", "scope":SCOPE, "presentation":"dashboard", "ready":is_instance_valid(_panel) and not _disposed, "disposed":_disposed, "parameters":_options.duplicate(true), "paused":_options.paused, "camera_mode":_options.camera_mode, "time":_tick * STEP, "tick":_tick, "fixed_step":STEP, "dropped_seconds":_dropped_seconds, "progress":progress, "currentStage":stage, "transitionCount":_transitions, "blocked":_blocked, "resources":{"world":0,"runtime":0,"storage":0,"controls":_cells.size() + 4 if is_instance_valid(_panel) else 0}, "error":_error, "text":text, "ui":{"panel":_panel.get_rect() if is_instance_valid(_panel) else Rect2(), "scroll":_scroll.get_global_rect() if is_instance_valid(_scroll) else Rect2()}}

func dispose() -> void:
	_disposed = true
	if is_instance_valid(_viewport) and _viewport.size_changed.is_connected(_layout): _viewport.size_changed.disconnect(_layout)
	_viewport = null
	if is_instance_valid(_panel): remove_child(_panel); _panel.free()
	_panel = null; _content = null; _scroll = null; _grid = null; _current = null; _status = null; _log = null
	_cells.clear(); _chapters.clear(); _progress = null
	_tick = 0; _accumulator = 0.0; _transitions = 0; _dropped_seconds = 0.0
	_blocked = false; _observed = false; _failed_once = false; _error = ""

func _exit_tree() -> void: dispose()
