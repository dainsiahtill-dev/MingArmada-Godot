extends CanvasLayer
## Native current-1650 interface. Snapshot data is copied; only intents leave UI.
signal command_requested(intent: Dictionary)
signal view_requested(tactical: bool)

const Chart = preload("res://game/ui/mingqi/mingqi_chart.gd")
const Parchment = preload("res://game/ui/shared/parchment_theme.gd")
const Gunnery = preload("res://modules/naval_simulation/combat/cannon_system.gd")
const BUSINESS = ["accept-convoy", "buy", "sell", "depart", "choose-route", "assign-order", "claim-convoy", "dock", "repair", "refit", "start-boarding", "board-action", "allocate-prize", "release-prisoners", "treat-wounded", "take-prize-cargo", "resolve-prize", "sell-prize", "incorporate-prize", "story-choice", "repay-debt"]
const PANELS = {"ship": "旗舰与操船", "convoy": "船队与海图", "port": "靠港与贸易", "boarding": "接舷与俘获", "tactics": "船队战术", "story": "航海日志"}
const GOODS = {"grain": "粮食", "water": "淡水", "wood": "木材", "iron": "铁料", "powder": "火药", "cloth": "布匹", "silk": "丝绸", "porcelain": "瓷器", "tea": "茶", "sugar": "糖", "salt": "盐", "spices": "香料"}
const ORDER_NAMES = {"protect": "护航", "intercept": "拦截", "keep-distance": "保持距离", "focus": "集火", "prepare-boarding": "准备接舷", "rally": "集结"}
const STATUS_NAMES = {"offered": "待接", "active": "进行中", "delivered": "已交付", "failed": "失败", "settled": "已结算", "loading": "装载中", "underway": "航行中", "arrived": "已抵达", "lost": "损失", "interrupted": "中断", "held": "待接管", "crewed": "已押船", "incorporated": "已编入", "released": "已释放", "abandoned": "已救人弃船", "sold": "已售出", "won": "已获胜", "cut": "已断缆", "completed": "已完成", "blocked": "受阻", "history": "历史指令"}
var _packet: Dictionary = {}
var _catalog: Dictionary = {}
var _screen: Control
var _operation: PanelContainer
var _menu: PanelContainer
var _panels: Dictionary = {}
var _watchers: Array[Callable] = []
var _form: Dictionary = {"trade_quantity": 1, "treatment_quantity": 1, "prize_crew": 12, "prize_quantity": 1, "debt_quantity": 1, "tactics_range": 180, "point_x": 0, "point_z": 0, "tactics_kind": "protect", "prize_good": "grain"}
var _selected: Array = []
var _panel := "ship"
var _panel_open := true
var _menu_open := false
var _layout_queued := false
var _signature := ""
var _generation := ""
var _pending: Dictionary = {}
var _recent: Dictionary = {}
var _receipt_marker := ""
var _serial := 0
var _mount := 0
var _theme: Theme
var _chart_height: Callable
var _repay_refreshing := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_catalog = JSON.parse_string(FileAccess.get_file_as_string("res://game/domain/mingqi/catalog.json"))
	_theme = _make_theme()
	_build()

func apply_snapshot(packet: Dictionary) -> void:
	_packet = packet.duplicate(true)
	var generation := str(_state().get("campaignId", "")) + ":" + str(_runtime().get("generation", 0))
	var marker := str(_state().get("revision", -1)) + ":" + str(_runtime().get("noticeRevision", 0)) + ":" + str(_runtime().get("commandSerial", 0))
	if marker != _receipt_marker:
		_pending.clear()
		_receipt_marker = marker
	var signature := generation
	signature += JSON.stringify(_runtime().get("controllableShipIds", _runtime().get("policy", {}).get("controllableShipIds", [])))
	for key in ["vessels", "voyages", "contracts", "boardings", "works", "prizes"]:
		for item in _state().get(key, {}).values(): signature += "|" + str(item.get("id", item.get("targetId", ""))) + ":" + str(item.get("status", ""))
	signature += _story_signature()
	if generation != _generation:
		_form = {"trade_quantity": 1, "treatment_quantity": 1, "prize_crew": 12, "prize_quantity": 1, "debt_quantity": 1, "tactics_range": 180, "point_x": 0, "point_z": 0, "tactics_kind": "protect", "prize_good": "grain"}
		_selected.clear()
		_pending.clear()
		_recent.clear()
	_generation = generation
	if not _screen: return
	if signature != _signature:
		_signature = signature
		_build()
	for update in _watchers: update.call()
	_queue_layout()

func _state() -> Dictionary: return _packet.get("campaign", {})
func _runtime() -> Dictionary: return _packet.get("runtime", {})
func _naval() -> Dictionary: return _packet.get("naval", {})
func _vessels() -> Dictionary: return _state().get("vessels", {})
func _vessel(id: String) -> Dictionary: return _vessels().get(id, {})
func _flag() -> Dictionary: return _vessel(str(_state().get("flagshipId", "")))
func _native(id: String) -> Dictionary:
	for ship in _naval().get("ships", []):
		if ship.get("id") == id: return ship
	return {}
func _ports() -> Dictionary: return _state().get("ports", _state().get("portStates", {}))
func _profile(vessel: Dictionary) -> Dictionary: return _catalog.get("profiles", {}).get(vessel.get("profileId", ""), {})
func _name(id) -> String: return str(_vessel(str(id)).get("name", "失联船只"))
func _port_name(id) -> String: return str(_ports().get(str(id), {}).get("name", "海上航行"))
func _status(value) -> String: return str(STATUS_NAMES.get(str(value), str(value)))
func _sum(cargo: Dictionary) -> int:
	var total := 0
	for amount in cargo.values(): total += int(amount)
	return total
func _cargo(cargo: Dictionary) -> String:
	var texts: PackedStringArray = []
	for good in cargo:
		if cargo[good] > 0: texts.append(str(GOODS.get(good, good)) + " " + str(int(cargo[good])))
	return "、".join(texts) if not texts.is_empty() else "空舱"
func _authorized(id: String) -> bool: return id in _runtime().get("controllableShipIds", _runtime().get("policy", {}).get("controllableShipIds", []))
func _operational() -> bool: return not _state().is_empty() and not _runtime().get("error", false) and not _runtime().get("status", "ready") in ["loading", "disposed", "error"]
func _reason(value) -> String:
	if str(value) == "flagship-sunk": return "旗舰已沉没，本次航程结束。按 Esc 打开菜单，载入存档或返回主菜单。"
	var reasons := {"unsafe-port": "进入港口附近，收帆停稳并脱离交战。", "unsafe-dock": "靠港条件尚未满足，请安全停船。", "not-in-port": "请先靠泊港口。", "ship-not-docked": "所选船只尚未安全锚泊。", "save-safe-port-required": "请先将船队停在安全港口。", "save-active-boarding": "请先结束接舷战。", "save-local-hostile-threat": "附近有敌舰，请脱离威胁。", "save-pending-attacks": "炮击尚未结束，请稍候。", "save-pending-input": "操船尚未结束，请停船后重试。", "save-flagship-unavailable": "旗舰已沉没，当前航程无法保存。", "insufficient-silver": "银两不足。", "insufficient-stock": "港口库存不足。", "insufficient-capacity": "货舱余量不足。", "insufficient-cargo": "可售货物不足。", "invalid-quantity": "请输入有效的正整数。", "contract-cargo": "委托货物不能自行交易。", "ship-working": "船只仍在作业。", "no-damage": "船体与帆装无需修理。", "no-wounded": "所选船只没有伤员。", "insufficient-wounded": "治伤人数超过实际伤员。", "refit-forbidden": "帆装改造限厦门港的自有船只。", "no-prisoners": "所选船只没有俘虏。", "route-too-shallow": "航路水深不足，船只吃水过深。", "stale-revision": "航况已变化，请重新确认后下令。", "fast-forward-danger": "附近有威胁或浅水危险，无法快进。", "target-not-weakened": "敌舰尚未削弱。", "invalid-boarding": "检查两船距离、船速、船员与作业状态。", "prize-market-unavailable": "战利船市场仅在厦门与金门。", "prize-not-close": "两船须相距不超过 36 米且相对速度不超过 3 m/s。", "prize-cargo-not-empty": "售船前须清空货物。", "ship-ordered": "相关船只仍有航行或战术指令。", "unauthorized-order": "所选船只当前不受指挥。", "target-unavailable": "目标已离开或不可用。", "runtime-unavailable": "航程暂时无法接受操作。", "save-unverified": "等待航况核验。"}
	var text := str(value)
	if text.is_empty(): return ""
	if reasons.has(text): return reasons[text]
	if text.begins_with("save-fleet-") or text.begins_with("save-source-fleet-"): return "受指挥船只尚未全部停妥，请结束船队指令。"
	for i in text.length():
		if text.unicode_at(i) >= 0x3400: return text
	return "条件尚未满足，请检查航况与实际回执。"

func _fact(type: String, id: String = "", target: String = "") -> Dictionary:
	var facts: Dictionary = _runtime().get("eligibility", {})
	for key in [type + ":" + id + ":" + target, type + ":" + id, type]:
		if facts.has(key):
			var value = facts[key]
			return value if value is Dictionary else {"ok": value == true, "reason": "" if value == true else "save-unverified"}
	return {"ok": false, "reason": "save-unverified"}

func _token() -> String: return _generation + "@" + str(_mount)
func _send(payload: Dictionary, captured: String) -> void:
	if captured != _token() or not _operational(): return
	var intent := payload.duplicate(true)
	var payload_key := JSON.stringify(intent)
	var key := payload_key + ":" + str(_state().get("revision", -1))
	if _pending.has(key): return
	var now := Time.get_ticks_msec()
	var repeated_action: bool = intent.get("type") in BUSINESS or intent.get("type") in ["save", "save-and-menu", "import-save"] or intent.get("firePort", false) or intent.get("fireStarboard", false)
	if repeated_action and _recent.has(payload_key) and now - int(_recent[payload_key]) < 250: return
	_recent[payload_key] = now
	if _recent.size() > 256: _recent.erase(_recent.keys()[0])
	_pending[key] = true
	_serial += 1
	if intent.get("type") in BUSINESS:
		# Dictionary dot assignment creates StringName keys; pure domain commands require String keys.
		intent["commandId"] = "ui:%s:%d:%d" % [_state().get("campaignId", "voyage"), get_instance_id(), _serial]
		intent["expectedRevision"] = int(_state().get("revision", 0))
		if intent.type == "assign-order": intent["order"]["id"] = intent["commandId"]
	command_requested.emit(intent)

func captures_keyboard() -> bool:
	if not _screen: return false
	var focus := _screen.get_viewport().gui_get_focus_owner()
	if focus == null or not _screen.is_ancestor_of(focus): return false
	return (focus is LineEdit and focus.editable) or (focus is TextEdit and focus.editable)

func configure_chart(height_sampler: Callable) -> bool:
	_chart_height = height_sampler
	if not _screen: return height_sampler.is_valid()
	var chart = _screen.find_child("fleet_chart", true, false)
	if not chart: return false
	var configured: bool = chart.configure_geography(height_sampler)
	if configured:
		chart.apply_data(_vessels(), _ports(), _catalog.get("routes", {}), str(_runtime().get("selectedShipId", _state().get("flagshipId", ""))))
		chart.apply_packet(_packet)
	return configured

func is_panel_open() -> bool: return _panel_open
func is_menu_open() -> bool: return _menu_open

func open_panel(id: String) -> void:
	if not PANELS.has(id): return
	_panel = id
	_panel_open = true
	if _screen:
		var heading = _screen.find_child("panel_heading", true, false)
		if heading: heading.text = PANELS[id]
	if _operation: _operation.show()
	for key in _panels: _panels[key].visible = key == id

func close_panel() -> void:
	_panel_open = false
	if _operation: _operation.hide()
	if _screen: _screen.get_viewport().gui_release_focus()

func open_menu() -> void:
	_menu_open = true
	if _menu: _menu.show()
	_send({"type": "menu", "value": true}, _token())

func close_menu() -> void:
	_menu_open = false
	if _menu: _menu.hide()
	_send({"type": "menu", "value": false}, _token())

func _build() -> void:
	var editor := _capture_editor()
	_mount += 1
	if _screen:
		remove_child(_screen)
		_screen.queue_free()
	_watchers.clear()
	_panels.clear()
	_screen = Control.new()
	_screen.name = "MingqiScreen"
	_screen.set_meta("generation", _generation)
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.theme = _theme
	add_child(_screen)
	_screen.resized.connect(_queue_layout)
	var hud := _box(_screen, "hud")
	hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	hud.minimum_size_changed.connect(_queue_layout)
	var hud_theme: Theme = _theme.duplicate()
	hud_theme.default_font_size = 14
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		hud_theme.set_stylebox(state, "Button", Parchment.button_style(state, false, 8))
	hud.theme = hud_theme
	var hud_style: StyleBox = Parchment.panel(12)
	hud.add_theme_stylebox_override("panel", hud_style)
	var head := _column(hud)
	head.add_theme_constant_override("separation", 6)
	_text(head, "title", func(): return "海上明旗  ·  1650", 24, Parchment.CINNABAR)
	_text(head, "identity", func():
		var c: Dictionary = _state().get("calendar", {})
		var captain: Dictionary = _state().get("captain", {})
		return "%d年%d月%d日  ·  %s  ·  %d岁" % [c.get("year", 1650), c.get("month", 1), c.get("day", 1), captain.get("name", "船长"), int(c.get("year", 1650)) - int(captain.get("birthYear", 1631))], 14)
	_text(head, "silver", func(): return "银 %d两   借债 %d两   航程 %.1f秒" % [_state().get("captain", {}).get("silver", 0), _state().get("debt", {}).get("principal", 0), _state().get("simulationSeconds", 0)], 14)
	_text(head, "navigation", _navigation_text, 14)
	var broadside := _text(head, "broadside_status", func():
		var id := str(_state().get("flagshipId",""))
		return "左舷 Q · %s\n右舷 E · %s" % [Gunnery.broadside_status(_naval(),id,"port",_runtime().get("policy",{})).label,Gunnery.broadside_status(_naval(),id,"starboard",_runtime().get("policy",{})).label], 13, Parchment.MUTED)
	_watchers.append(func(): broadside.visible = not _native(str(_state().get("flagshipId",""))).is_empty())
	_text(head, "time_state", func(): return ("航程结束" if _naval().get("status", "") == "defeat" else "已暂停" if _runtime().get("paused", false) else "航行中") + " · 时间速度 %s×" % str(_runtime().get("timeScale", 1)), 14, Parchment.MUTED)
	var goal := _row(head)
	goal.name = "objective_row"
	_text(goal, "current_objective", func(): return "当前目标 · " + str(_story().get("objective", {}).get("title", "")), 13, Parchment.CINNABAR)
	var goal_button := _local_button(goal, "objective_open", "查看", func(): open_panel(str(_story().get("objective", {}).get("panel", "story"))))
	goal_button.custom_minimum_size = Vector2(48, 28)
	_watchers.append(func():
		goal.visible = not str(_story().get("objective", {}).get("title", "")).is_empty()
		goal_button.disabled = not PANELS.has(str(_story().get("objective", {}).get("panel", ""))))
	var voyage_progress := _text(head, "voyage_progress", _voyage_progress_text, 13, Parchment.MUTED)
	_watchers.append(func(): voyage_progress.visible = not voyage_progress.text.is_empty())
	var time := _row(head)
	_button(time, "pause", "暂停", func(): return {"type": "pause", "value": not _runtime().get("paused", false)}, func(): return _operational())
	_watchers.append(func():
		var pause = _screen.find_child("pause", true, false)
		if pause: pause.text = "继续" if _runtime().get("paused", false) else "暂停")
	for value in [0.25, 1.0, 8.0]: _button(time, "speed_" + str(value).replace(".", "_"), str(value) + "×", func(): return {"type": "time-scale", "value": value}, func(): return _operational())
	_local_button(time, "menu_open", "菜单", open_menu)
	for button in time.get_children(): button.custom_minimum_size = Vector2(60, 32)
	var nav := HFlowContainer.new()
	head.add_child(nav)
	var nav_names := {"ship": "旗舰", "convoy": "船队海图", "port": "港口贸易", "boarding": "接舷俘获", "tactics": "战术", "story": "航海日志"}
	for key in PANELS:
		var button := _local_button(nav, "nav_" + key, nav_names[key], func(): open_panel(key))
		button.custom_minimum_size = Vector2(0, 32)
	var cameras := _row(head)
	_local_button(cameras, "camera_captain", "驾驶视角", func(): view_requested.emit(false))
	_local_button(cameras, "camera_tactical", "高位海图", func(): view_requested.emit(true))
	_button(cameras, "stop_sailing", "停船", func(): return {"type": "stop-sailing"}, _can_mouse_sail)
	var notice := _text(head, "notice", func(): return _reason(_runtime().get("notice", _runtime().get("reason", ""))), 14, Parchment.DANGER)
	_watchers.append(func(): notice.visible = not notice.text.is_empty())
	_text(head, "keys", func(): return ("先离港，再左键点海面航行 · 中键停船" if _state().get("currentPortId") != null else "左键点海面持续航行 · 中键停船") + "\n按住右键拖动视角 · 滚轮缩放 · F 恢复跟船\nW/S 升降帆 · A/D 转舵 · Q/E 齐射\nR 调帆 · [/] 手动帆角 · 空格 暂停 · Esc 菜单", 13, Parchment.MUTED)
	_operation = _box(_screen, "operation")
	var operation_column := _column(_operation)
	var heading := _row(operation_column)
	_text(heading, "panel_heading", func(): return PANELS.get(_panel, "航程操作"), 24, Parchment.CINNABAR)
	_local_button(heading, "panel_close", "收起", close_panel)
	var scroll := ScrollContainer.new()
	scroll.name = "operation_scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	operation_column.add_child(scroll)
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(stack)
	for id in PANELS:
		var panel := VBoxContainer.new()
		panel.name = "panel_" + id
		panel.add_theme_constant_override("separation", 10)
		stack.add_child(panel)
		_panels[id] = panel
	_build_ship(_panels.ship)
	_build_convoy(_panels.convoy)
	_build_port(_panels.port)
	_build_boarding(_panels.boarding)
	_build_tactics(_panels.tactics)
	_build_story(_panels.story)
	_build_menu()
	for key in _panels: _panels[key].visible = key == _panel
	_operation.visible = _panel_open
	_menu.visible = _menu_open
	for update in _watchers: update.call()
	_queue_layout()
	if not editor.is_empty(): _restore_editor.call_deferred(editor, _token())

func _capture_editor() -> Dictionary:
	if not _screen or str(_screen.get_meta("generation", "")) != _generation: return {}
	var focus := _screen.get_viewport().gui_get_focus_owner()
	if focus == null or not _screen.is_ancestor_of(focus): return {}
	if focus is LineEdit and focus.get_parent() is SpinBox:
		return {"id": str(focus.get_parent().name), "kind": "number", "text": focus.text, "caret": focus.caret_column}
	if focus is TextEdit:
		return {"id": str(focus.name), "kind": "text", "text": focus.text, "line": focus.get_caret_line(), "column": focus.get_caret_column()}
	return {}

func _restore_editor(editor: Dictionary, captured: String) -> void:
	if captured != _token() or not _screen: return
	var field = _screen.find_child(str(editor.id), true, false)
	if editor.kind == "number" and field is SpinBox and field.editable:
		var line: LineEdit = field.get_line_edit()
		var draft := str(editor.text).strip_edges()
		if draft.is_valid_int() and float(draft) >= field.min_value and float(draft) <= field.max_value:
			field.set_block_signals(true)
			field.value = int(draft)
			field.set_block_signals(false)
			_form[str(field.name)] = int(draft)
		line.grab_focus()
		# SpinBox queues its own editor sync on mounting/focus; restore after that sync.
		line.set_deferred("text", editor.text)
		line.set_deferred("caret_column", int(editor.caret))
	elif editor.kind == "text" and field is TextEdit and field.editable:
		field.text = editor.text
		field.grab_focus()
		field.set_caret_line(int(editor.line))
		field.set_caret_column(int(editor.column))

func _story() -> Dictionary:
	var data: Variant = _packet.get("story", {})
	return data if data is Dictionary else {}

func _story_scene(id: String) -> Dictionary:
	for scene in _story().get("scenes", []):
		if str(scene.get("id", "")) == id: return scene
	return {}

func _story_choice(scene_id: String, choice_id: String) -> Dictionary:
	for choice in _story_scene(scene_id).get("choices", []):
		if str(choice.get("id", "")) == choice_id: return choice
	return {}

func _story_native(scene_id: String) -> Dictionary:
	var fact: Variant = _runtime().get("eligibility", {}).get("story", {}).get(scene_id, {})
	if not fact is Dictionary or not fact.has("ok"): return {"ok": false, "reason": "save-unverified"}
	return {"ok": fact.ok, "reason": fact.get("reason", "") if fact.ok or not str(fact.get("reason", "")).is_empty() else "save-unverified"}

func _story_signature() -> String:
	var structure: Array = [not _story().is_empty(), _story().get("chapter", {}).get("id", "")]
	for scene in _story().get("scenes", []):
		var row: Array = [scene.get("id", ""), scene.get("status", "locked"), scene.get("selectedChoiceId", ""), _story_native(str(scene.get("id", "")))]
		for choice in scene.get("choices", []): row.append([choice.get("id", ""), choice.get("enabled", false), choice.get("reason", ""), choice.get("silverCost", 0)])
		structure.append(row)
	for relation in _story().get("relations", []): structure.append(str(relation.get("id", "")))
	return "|story:" + JSON.stringify(structure)

func _story_choice_ok(scene_id: String, choice_id: String) -> bool:
	var choice := _story_choice(scene_id, choice_id)
	return _operational() and _story_scene(scene_id).get("status", "locked") == "available" and choice.get("enabled", false) and _story_native(scene_id).get("ok", false) and int(choice.get("silverCost", 0)) <= int(_state().get("captain", {}).get("silver", 0))

func _story_choice_reason(scene_id: String, choice_id: String) -> String:
	var choice := _story_choice(scene_id, choice_id)
	if not _operational(): return _reason("runtime-unavailable")
	if not choice.get("enabled", false): return _story_reason(scene_id, choice.get("reason", ""), choice) if not str(choice.get("reason", "")).is_empty() else "条件尚未满足。"
	if not _story_native(scene_id).get("ok", false): return _story_reason(scene_id, _story_native(scene_id).get("reason", "save-unverified"), choice)
	if int(choice.get("silverCost", 0)) > int(_state().get("captain", {}).get("silver", 0)): return _story_reason(scene_id, "insufficient-silver", choice)
	return ""

func _story_reason(scene_id: String, value, choice: Dictionary = {}) -> String:
	if scene_id != "second-return": return _reason(value)
	match str(value):
		"not-in-story-port", "not-in-port": return "在厦门、金门或近岸补给点安全锚泊后，再打开船上账册。"
		"second-convoy-unclaimed": return "先完成第二趟并领取实际报酬。"
		"no-dividend-proceeds": return "本航没有可分报酬。"
		"no-verified-beneficiaries": return "暂无可核验的存活随航船员，不能发放。"
		"insufficient-silver": return "当前银两不足支付%d两。" % int(choice.get("silverCost", 0))
		"story-completed": return "本次安排已记账，仍可自行港务或偿债。"
		"unverified-support-history", "unexplained-crew-support": return "船员拥护来源尚未核清，仍可留作船本或安排偿债。"
	return _reason(value)

func _story_bill(scene_id: String) -> String:
	var scene := _story_scene(scene_id)
	var bill: Dictionary = scene.get("bill", {})
	if bill.is_empty(): return "交差账单尚未载入。"
	if scene.get("status") == "completed":
		return "实交%d粮 · 实损%d粮\n基础%d两 + 奖金%d两 = 本航实收%d两\n现银%d两 · 欠款%d两 · 现有拥护%d\n本次安排已记账；实际支出见下方决定，后续港务与偿债仍由你选择。" % [int(bill.get("delivered", 0)), int(bill.get("lost", 0)), int(bill.get("baseReward", 0)), int(bill.get("bonus", 0)), int(bill.get("revenue", 0)), int(bill.get("silver", 0)), int(bill.get("principal", 0)), int(bill.get("supportBefore", 0))]
	var delta := int(bill.get("supportDelta", 0))
	var gain := ("+" if delta >= 0 else "") + str(delta)
	var exclusions := "\n".join(PackedStringArray(bill.get("exclusions", [])))
	return "实交%d粮 · 实损%d粮\n基础%d两 + 奖金%d两 = 本航实收%d两\n现银%d两 · 欠款%d两；两成分红%d两，支付后余银%d两\n分红可惠及已核验%d人；现有拥护%d，分红后%d，实际拥护%s\n当前伤员%d人，承运船已核实死亡%d人\n%s" % [int(bill.get("delivered", 0)), int(bill.get("lost", 0)), int(bill.get("baseReward", 0)), int(bill.get("bonus", 0)), int(bill.get("revenue", 0)), int(bill.get("silver", 0)), int(bill.get("principal", 0)), int(bill.get("dividend", 0)), int(bill.get("remainingSilver", 0)), int(bill.get("beneficiaryCount", 0)), int(bill.get("supportBefore", 0)), int(bill.get("supportAfter", 0)), gain, int(bill.get("currentWounded", 0)), int(bill.get("verifiedDeaths", 0)), str(bill.get("scopeNote", "本次仅含已核验承运船。"))] + ("\n" + exclusions if not exclusions.is_empty() else "")

func _story_lines(scene_id: String, only_first: bool = false) -> String:
	var text: Array = _story_scene(scene_id).get("text", [])
	if only_first: return str(text[0]) if not text.is_empty() else "先完成当前目标，再回来商议这一页。"
	return "\n\n".join(PackedStringArray(text))

func _story_choice_effect(scene_id: String, choice_id: String) -> String:
	var choice := _story_choice(scene_id, choice_id)
	var label := str(choice.get("label", "")).replace("+-", "-")
	var cost := int(choice.get("silverCost", 0))
	var compact := label.replace(" ", "").replace("\t", "").replace("　", "")
	if cost > 0 and not compact.contains("%d两" % cost): label += " · %d两" % cost
	return label + "\n" + str(choice.get("consequence", "")).replace("+-", "-")

func _story_relation(id: String) -> String:
	for relation in _story().get("relations", []):
		if str(relation.get("id", "")) == id:
			return "%s · %s\n%s" % [relation.get("name", ""), relation.get("role", ""), relation.get("stance", "")]
	return ""

func _repay_limit() -> int:
	return maxi(0, mini(int(_story().get("debt", {}).get("principal", 0)), int(_state().get("captain", {}).get("silver", 0))))

func _debt_quantity() -> int:
	var field = _screen.find_child("debt_quantity", true, false) if _screen else null
	if field is SpinBox:
		if not field.get_line_edit().has_focus(): return int(field.value)
		var draft: String = field.get_line_edit().text.strip_edges()
		return int(draft) if draft.is_valid_int() else 0
	return int(_form.get("debt_quantity", 1))

func _repay_ok() -> bool:
	var debt: Dictionary = _story().get("debt", {})
	var native: Dictionary = _runtime().get("eligibility", {}).get("repayDebt", {})
	return _operational() and int(debt.get("principal", 0)) > 0 and debt.get("canRepay", false) and native.get("ok", false) and _debt_quantity() >= 1 and _debt_quantity() <= _repay_limit()

func _repay_reason() -> String:
	var debt: Dictionary = _story().get("debt", {})
	if not debt.has("principal"): return "债务账目尚未载入。"
	if int(debt.principal) <= 0: return "已还清。"
	if not _operational(): return _reason("runtime-unavailable")
	if not debt.get("canRepay", false): return _debt_reason(debt.get("reason", "")) if not str(debt.get("reason", "")).is_empty() else "条件尚未满足。"
	var fact: Dictionary = _runtime().get("eligibility", {}).get("repayDebt", {"ok": false, "reason": "save-unverified"})
	if not fact.get("ok", false): return _debt_reason(fact.get("reason", "")) if not str(fact.get("reason", "")).is_empty() else _reason("save-unverified")
	if _repay_limit() < 1: return _reason("insufficient-silver")
	if _debt_quantity() < 1 or _debt_quantity() > _repay_limit(): return "请输入1至%d之间的整数。" % _repay_limit()
	return ""

func _debt_reason(value) -> String:
	return "请先靠泊厦门林家商行，再偿还欠款。" if str(value) == "not-in-port" else _reason(value)

func _build_story(parent: Control) -> void:
	if _story().is_empty():
		_text(parent, "story_fallback", func(): return "这段航程暂未载入航海日志。旗舰、船队、贸易与接舷仍可照常查看。")
		return
	_text(parent, "story_chapter", func(): return _story().get("chapter", {}).get("title", "航海日志"), 22, Parchment.CINNABAR)
	_text(parent, "story_premise", func(): return _story().get("chapter", {}).get("summary", ""))
	_heading(parent, "下一步")
	_text(parent, "story_objective", func():
		var objective: Dictionary = _story().get("objective", {})
		return str(objective.get("title", "")) + "\n" + str(objective.get("detail", "")))
	_local_button(parent, "story_objective_open", "前往目标页面", func(): open_panel(str(_story().get("objective", {}).get("panel", "story"))))
	var preparing: bool = _voyage_flow().get("settlements", []).is_empty() and _voyage_flow().get("active", {}).get("stage", "") in ["offered", "loading"]
	if not preparing: _build_voyage_flow(parent)
	# Put the newest decision within reach, retaining all earlier scenes below it.
	var display_scenes: Array = []
	for scene in _story().get("scenes", []):
		if scene.get("id") == "second-return": display_scenes.append(scene)
	for scene in _story().get("scenes", []):
		if scene.get("id") != "second-return": display_scenes.append(scene)
	for source_scene in display_scenes:
		var scene_id := str(source_scene.get("id", ""))
		var section := _column(_box(parent, "story_scene_" + scene_id))
		_text(section, "story_title_" + scene_id, func(): return _story_scene(scene_id).get("title", ""), 20, Parchment.CINNABAR)
		_text(section, "story_npc_" + scene_id, func():
			var npc: Dictionary = _story_scene(scene_id).get("npc", {})
			return str(npc.get("name", "")) + " · " + str(npc.get("role", "")), 15, Parchment.MUTED)
		if scene_id == "second-return":
			_text(section, "story_bill_" + scene_id, func(): return _story_bill(scene_id), 15, Parchment.CINNABAR)
		match source_scene.get("status", "locked"):
			"completed":
				_text(section, "story_outcome_" + scene_id, func():
					var scene := _story_scene(scene_id)
					var choice := _story_choice(scene_id, str(scene.get("selectedChoiceId", "")))
					return "你的决定：%s\n\n%s" % [choice.get("label", "已作出选择"), scene.get("reply", "")])
			"available":
				_text(section, "story_dialogue_" + scene_id, func(): return _story_lines(scene_id))
				var native_label := _text(section, "story_native_" + scene_id, func():
					return _reason("runtime-unavailable") if not _operational() else (_story_reason(scene_id, _story_native(scene_id).get("reason", "save-unverified")) if not _story_native(scene_id).get("ok", false) else ""), 15, Parchment.DANGER)
				_watchers.append(func(): native_label.visible = not native_label.text.is_empty())
				for source_choice in source_scene.get("choices", []):
					var choice_id := str(source_choice.get("id", ""))
					var choices := _column(section)
					_text(choices, "story_choice_effect_" + scene_id + "_" + choice_id, func(): return _story_choice_effect(scene_id, choice_id))
					var button := _button(choices, "story_choice_" + scene_id + "_" + choice_id, str(source_choice.get("label", "作出决定")), func(): return {"type": "story-choice", "sceneId": scene_id, "choiceId": choice_id}, func(): return _story_choice_ok(scene_id, choice_id))
					button.clip_text = true
					button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					_watchers.append(func():
						button.text = str(_story_choice(scene_id, choice_id).get("label", "作出决定"))
						button.tooltip_text = _story_choice_reason(scene_id, choice_id))
					var reason := _text(choices, "story_choice_reason_" + scene_id + "_" + choice_id, func(): return _story_choice_reason(scene_id, choice_id), 14, Parchment.DANGER)
					_watchers.append(func(): reason.visible = not reason.text.is_empty())
			_:
				_text(section, "story_locked_" + scene_id, func(): return _story_lines(scene_id, true), 15, Parchment.MUTED)
	if preparing: _build_voyage_flow(parent)
	_heading(parent, "账册与债务")
	_text(parent, "story_debt", func():
		var debt: Dictionary = _story().get("debt", {})
		if not debt.has("principal"): return "债务账目尚未载入。"
		return "债务已还清。" if int(debt.principal) <= 0 else "还欠%s %d两。周转银与偿债，都要由你决定。" % [debt.get("creditorName", "债主"), int(debt.principal)])
	var quantity := _number(parent, "debt_quantity", "本次偿还（两）", 1, maxi(1, _repay_limit()))
	_watchers.append(func():
		_repay_refreshing = true
		var line := quantity.get_line_edit()
		var draft := line.text
		var focused := line.has_focus()
		var caret := line.caret_column
		var limit := _repay_limit()
		quantity.set_block_signals(true)
		var minimum := 1 if limit > 0 else 0
		if quantity.min_value != minimum: quantity.min_value = minimum
		if quantity.max_value != limit: quantity.max_value = limit
		var editable := limit > 0 and _operational() and int(_story().get("debt", {}).get("principal", 0)) > 0
		if quantity.editable != editable: quantity.editable = editable
		quantity.set_block_signals(false)
		if focused and quantity.editable:
			line.text = draft
			line.caret_column = caret
		_repay_refreshing = false)
	var captured := _token()
	quantity.get_line_edit().text_changed.connect(func(_draft):
		if captured == _token() and not _repay_refreshing: _refresh())
	_text(parent, "repay_limit", func(): return "当前最多可还%d两；付款只减少这本账册记下的实际欠款。" % _repay_limit(), 14, Parchment.MUTED)
	_button(parent, "repay_debt", "偿还欠款", func(): return {"type": "repay-debt", "quantity": _debt_quantity()}, _repay_ok)
	var reason := _text(parent, "repay_debt_reason", _repay_reason, 15, Parchment.DANGER)
	_watchers.append(func(): reason.visible = not reason.text.is_empty())
	_heading(parent, "同行的人")
	for relation in _story().get("relations", []):
		var relation_id := str(relation.get("id", ""))
		_text(parent, "story_relation_" + relation_id, func(): return _story_relation(relation_id))
	_heading(parent, "最近的航海记录")
	_text(parent, "story_history", func():
		var messages: PackedStringArray = []
		var history: Array = _story().get("history", []).duplicate()
		history.reverse()
		for entry in history:
			var message := str(entry.get("message", ""))
			if not message.strip_edges().is_empty(): messages.append(message)
			if messages.size() == 6: break
		return "\n\n".join(messages) if not messages.is_empty() else "这一页还没有新的航海记录。")

func _voyage_flow() -> Dictionary: return _story().get("flow", {})

func _voyage_clock(seconds: float) -> String:
	var whole := int(ceil(maxf(0, seconds)))
	return "%02d:%02d" % [whole / 60, whole % 60]

func _voyage_progress_text() -> String:
	var active: Dictionary = _voyage_flow().get("active", {})
	if active.is_empty(): return ""
	var stage: String = active.get("stage", "")
	var phase := str({"offered": "接单", "loading": "整备离港", "underway": "护航送粮", "claim": "领取交差", "closed": "已结账"}.get(stage, "核对航程"))
	var text := ("首航" if active.get("contractId") == "convoy-001" else "补给航次") + " · " + phase
	match active.get("deadlineMode"):
		"remaining": text += " · 期限 " + _voyage_clock(float(active.get("remainingSeconds", 0)))
		"overdue": text += " · 逾期 " + _voyage_clock(float(active.get("overdueSeconds", 0)))
		"on-acceptance": text += " · 接单后计时"
	return text

func _voyage_bill_text() -> String:
	var lines: PackedStringArray = []
	for bill: Dictionary in _voyage_flow().get("settlements", []):
		lines.append("%s交差：实交%d粮 · 损失%d粮\n到账%d两（基础%d + 奖金%d）· 已付租费%d两\n回执所列船只死亡%d人 · 结算时伤员%d人；当前伤情请查船务。" % ["首航" if bill.contractId == "convoy-001" else "补给", bill.delivered, bill.lost, bill.paid, bill.baseReward, bill.bonus, bill.leasePaid, bill.dead, bill.wounded])
	return "\n\n".join(lines)

func _voyage_upgrade_text() -> String:
	var upgrade: Dictionary = _voyage_flow().get("upgrade", {})
	if upgrade.is_empty(): return "当前没有可改造的存活自有船；先检查船只与人员。"
	if upgrade.status == "working": return "%s · 帆装改造已付%d两，尚需%.0f秒。恢复航程时间后，船坞继续作业。" % [upgrade.name, upgrade.cost, ceil(float(upgrade.remainingSeconds))]
	if upgrade.status == "completed": return "%s · 帆装改造已完成，实际速度系数 %.2f。此项改造不会再次收费。" % [upgrade.name, upgrade.speedMultiplier]
	return "%s是你的自有船。厦门帆装改造需%d两、%d秒，完成后速度系数 %.2f → %.2f。%s" % [upgrade.name, upgrade.cost, upgrade.durationSeconds, upgrade.speedMultiplier, upgrade.targetSpeedMultiplier, "回厦门安全靠泊后可申请；金门没有这项船坞作业。" if _state().get("currentPortId") != "xiamen" else "在船务页核对报价并申请。"]

func _open_voyage_service() -> void:
	var ship_id: String = _voyage_flow().get("upgrade", {}).get("shipId", "")
	open_panel("port")
	var selector = _screen.find_child("service_ship", true, false)
	if selector is OptionButton:
		for index in selector.item_count:
			if str(selector.get_item_metadata(index)) == ship_id:
				selector.select(index)
				selector.item_selected.emit(index)
				break
	var scroll = _screen.find_child("operation_scroll", true, false)
	if scroll is ScrollContainer and selector is Control: scroll.ensure_control_visible(selector)

func _build_voyage_flow(parent: Control) -> void:
	if _voyage_flow().is_empty(): return
	var section := _column(_box(parent, "voyage_closure"))
	_text(section, "voyage_progress_detail", func():
		var active: Dictionary = _voyage_flow().get("active", {})
		var counts: Dictionary = active.get("counts", {})
		return _voyage_progress_text() + "\n粮船：在途%d · 到达%d · 损失%d。%s" % [counts.get("underway", 0), counts.get("arrived", 0), counts.get("lost", 0), "首航从开局计时；可先暂停，决定旧账与航路。对白可跳过。" if active.get("contractId") == "convoy-001" and active.get("stage") in ["offered", "loading"] else "按实际交付交差，逾期可能失去奖金。" if active.get("stage") != "closed" else "结算后仍须安全靠港，才能保存船队。"], 15)
	var bill := _text(section, "voyage_bill", _voyage_bill_text, 15, Parchment.CINNABAR)
	_watchers.append(func(): bill.visible = not bill.text.is_empty())
	var decisions := _text(section, "voyage_decisions", func():
		var entries: PackedStringArray = []
		for decision: Dictionary in _voyage_flow().get("branches", []): entries.append("%s · 实付%d两" % [_story_choice(str(decision.sceneId), str(decision.choiceId)).get("label", decision.choiceId), decision.silverCost])
		if not entries.is_empty(): entries.append("当前船员拥护%d · 军方信任%d · 商人信用%d" % [_state().get("reputations", {}).get("crewSupport", 0), _state().get("reputations", {}).get("militaryTrust", 0), _state().get("reputations", {}).get("merchantCredit", 0)])
		return "\n".join(entries), 14)
	_watchers.append(func(): decisions.visible = not decisions.text.is_empty())
	_text(section, "voyage_upgrade", _voyage_upgrade_text, 15)
	var services := _local_button(section, "voyage_upgrade_open", "查看自有船与改造", _open_voyage_service)
	_watchers.append(func(): services.disabled = _voyage_flow().get("upgrade", {}).is_empty())
	_local_button(section, "voyage_next_open", "查看本航 / 下一份委托", func(): open_panel("convoy"))
	_text(section, "voyage_save", func(): return ("船队已符合安全存档条件。" if _runtime().get("canSave", false) else "存档尚需：" + _reason(_runtime().get("saveReason", "save-unverified"))) + "\n菜单中选择保存并返回主菜单；继续航程时点击「继续海上明旗 · 1650」，恢复实际银两、伤亡和船务进度。", 14)
	_local_button(section, "voyage_save_open", "查看安全存档", open_menu)

func _navigation_text() -> String:
	var ship := _native(str(_state().get("flagshipId", "")))
	if ship.is_empty(): return _port_name(_state().get("currentPortId")) + " · 等待船况"
	var visual: Dictionary = ship.get("visual", {})
	var velocity: Dictionary = visual.get("velocity", {})
	var speed := Vector2(float(velocity.get("x", 0)), float(velocity.get("z", 0))).length() * 1.943844
	return "航向 %03d°   航速 %.1f节   风速 %.1fm/s   %s" % [int(fposmod(rad_to_deg(float(visual.get("heading", 0))) + 90, 360)), speed, _naval().get("wind", {}).get("speed", 0), _port_name(_state().get("currentPortId"))]

func _build_ship(parent: Control) -> void:
	_art(parent, "res://assets/art/characters/zheng-captain-v1.png", 94)
	_text(parent, "flagship_name", func(): return str(_flag().get("name", "旗舰尚未就绪")), 22)
	for metric in ["hull", "sail", "crew"]:
		var row := _row(parent)
		var names := {"hull": "船体", "sail": "帆装", "crew": "船员"}
		_text(row, "ship_" + metric + "_label", func(): return names[metric])
		var bar := ProgressBar.new()
		bar.name = "ship_" + metric + "_bar"
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.custom_minimum_size = Vector2(120, 22)
		bar.show_percentage = false
		row.add_child(bar)
		_text(row, "ship_" + metric + "_value", func():
			var current := _native(str(_state().get("flagshipId", "")))
			return "%d / %d" % [current.get(metric, 0), current.get("max" + metric.capitalize(), 0)])
		_watchers.append(func():
			var current := _native(str(_state().get("flagshipId", "")))
			bar.max_value = maxf(1, float(current.get("max" + metric.capitalize(), 100)))
			bar.value = float(current.get(metric, 0)))
	_text(parent, "ship_crew_detail", func(): return _crew_text(_flag()))
	_slider(parent, "ship_sail", "帆面部署", 0, 1, 0.05, "sailDeployment")
	_slider(parent, "ship_rudder", "操舵", -1, 1, 0.05, "rudder")
	_slider(parent, "ship_angle", "帆角（弧度）", -PI / 2, PI / 2, 0.05, "sailAngle")
	_button(parent, "ship_auto_trim", "自动 / 手动调帆", func(): return {"type": "controls", "shipId": _state().get("flagshipId"), "autoTrim": not _native(str(_state().get("flagshipId", ""))).get("autoTrim", true)}, _can_sail)
	_text(parent, "ship_trim_status", func(): return "自动调帆" if _native(str(_state().get("flagshipId", ""))).get("autoTrim", false) else "手动调帆")
	var salvos := _row(parent)
	for side in ["port", "starboard"]:
		_button(salvos, "ship_fire_" + side, "左舷齐射 Q" if side == "port" else "右舷齐射 E", func(): return {"type": "controls", "shipId": _state().get("flagshipId"), "firePort" if side == "port" else "fireStarboard": true}, func(): return _can_fire(side))
		_text(parent, "reload_" + side, func():
			var ship := _native(str(_state().get("flagshipId", "")))
			return ("左舷" if side == "port" else "右舷") + (" · 等待炮况" if ship.is_empty() else " · 装填 %.1f秒" % ship.get("cooldownSeconds", {}).get(side, 0)))
	var ammo := _row(parent)
	for kind in ["solid", "chain", "grape"]:
		var names := {"solid": "实心弹", "chain": "链弹", "grape": "葡萄弹"}
		_button(ammo, "ammo_" + kind, names[kind], func(): return {"type": "controls", "shipId": _state().get("flagshipId"), "ammoType": kind}, _can_sail)
	_text(parent, "ammo_count", func():
		var ship := _native(str(_state().get("flagshipId", "")))
		var counts: Dictionary = ship.get("ammo", {})
		return "实心弹 %d批  ·  链弹 %d批  ·  葡萄弹 %d批" % [counts.get("solid", 0), counts.get("chain", 0), counts.get("grape", 0)])
	_text(parent, "ship_ammo_selected", func(): return "当前装填：" + str({"solid": "实心弹", "chain": "链弹", "grape": "葡萄弹"}.get(_native(str(_state().get("flagshipId", ""))).get("ammoType"), "等待炮况")))
	_text(parent, "manual_hint", func(): return "手动操船接管旗舰后，旗舰退出当前战术；其余船只继续原指令。", 14)

func _can_sail() -> bool:
	var id := str(_state().get("flagshipId", ""))
	return _operational() and not _runtime().get("paused", true) and _authorized(id) and not _native(id).is_empty()
func _can_mouse_sail() -> bool:
	if not _operational() or _runtime().get("paused", true) or _state().get("currentPortId") != null: return false
	var id: String = str(_naval().get("playerId", _state().get("flagshipId", "")))
	var ship: Dictionary = _native(id)
	return _authorized(id) and ship.get("hull", 0) > 0 and ship.get("crew", 0) > 0
func _can_fire(side: String) -> bool:
	var ship := _native(str(_state().get("flagshipId", "")))
	return _can_sail() and ship.get("hull", 0) > 0 and ship.get("cannonsPerSide", 0) > 0 and ship.get("cooldownSeconds", {}).get(side, 1) <= 0 and ship.get("ammo", {}).get(ship.get("ammoType", "solid"), 0) > 0
func _crew_text(ship: Dictionary) -> String:
	var crew: Dictionary = ship.get("crew", {})
	return "可战 %d  /  伤员 %d  /  俘虏 %d  ·  最低船员 %d" % [crew.get("able", 0), crew.get("wounded", 0), crew.get("prisoners", 0), crew.get("minimum", 0)]

func _build_convoy(parent: Control) -> void:
	var chart := Chart.new()
	chart.name = "fleet_chart"
	parent.add_child(chart)
	if _chart_height.is_valid(): chart.configure_geography(_chart_height)
	_watchers.append(func():
		chart.apply_data(_vessels(), _ports(), _catalog.get("routes", {}), str(_runtime().get("selectedShipId", _state().get("flagshipId", ""))))
		chart.apply_packet(_packet))
	var chart_token := _token()
	chart.point_requested.connect(func(point):
		if chart_token != _token(): return
		_form.point_x = round(float(point.x))
		_form.point_z = round(float(point.z))
		for coordinate in ["point_x", "point_z"]:
			var field = _screen.find_child(coordinate, true, false)
			if field: field.set_value_no_signal(float(_form[coordinate]))
		_refresh())
	_text(parent, "chart_legend", func(): return "金舟：旗舰 · 青舟：同盟 · 朱舟：敌舰\n点击海图填写航位；确认航行仍须使用战术页按钮。\n浅路水深 2.4m；航路选择按实际吃水核验。", 14)
	_heading(parent, "护粮委托")
	for id in _state().get("contracts", {}):
		_text(parent, "contract_" + id, func():
			var contract: Dictionary = _state().get("contracts", {}).get(id, {})
			return ("首程护粮" if id == "convoy-001" else "补给护粮") + " · " + _status(contract.get("status", "")) + "\n" + _contract_timing(contract) + " · 奖励按实交粮、人船状况结算")
		_button(parent, "contract_accept_" + id, "接下委托", func(): return {"type": "accept-convoy", "contractId": id}, func(): return _operational() and _state().get("contracts", {}).get(id, {}).get("status") == "offered" and _state().get("currentPortId") != null)
		_button(parent, "contract_claim_" + id, "领取实际报酬", func(): return {"type": "claim-convoy", "contractId": id}, func(): return _claim_ready(id))
	_button(parent, "depart", "离港起航", func(): return {"type": "depart"}, func(): return _runtime().get("canDepart", false) == true)
	_text(parent, "depart_reason", func(): return _reason(_runtime().get("departReason", "save-unverified")) if not _runtime().get("canDepart", false) else "离港条件已核验。", 14)
	_heading(parent, "逐船实况")
	for id in _vessels():
		_text(parent, "fleet_" + id, func():
			var ship := _vessel(id)
			var profile := _profile(ship)
			var damage: Dictionary = ship.get("damage", {})
			var occupied := _sum(ship.get("cargo", {}))
			var draft := float(profile.get("baseDraftMeters", 0)) + occupied * float(profile.get("cargoDraftMetersPerUnit", 0))
			return "%s · %s · %s\n船体 %.0f / 帆 %.0f · %s\n货舱 %d/%d · %s · 吃水 %.2fm" % [ship.get("name", id), "近场" if ship.get("representation") == "near" else "航线", "自有" if ship.get("ownerId") == "captain" else "敌方" if ship.get("ownerId") == "enemy" else "林家", damage.get("hull", 0), damage.get("sail", 0), _crew_text(ship), occupied, profile.get("capacity", 0), _cargo(ship.get("cargo", {})), draft])
		_button(parent, "select_ship_" + id, "选择此船", func(): return {"type": "select-ship", "shipId": id}, func(): return _authorized(id))
		var voyage_id = _vessel(id).get("voyageId")
		if voyage_id == null: continue
		_text(parent, "voyage_" + str(voyage_id), func():
			var voyage: Dictionary = _state().get("voyages", {}).get(voyage_id, {})
			return "%s · %s · %s" % [_port_name(voyage.get("destinationId")), _status(voyage.get("status", "")), _voyage_detail(voyage)])
		var lanes: Dictionary = {}
		var voyage: Dictionary = _state().get("voyages", {}).get(voyage_id, {})
		for route_id in _catalog.get("routes", {}):
			var route: Dictionary = _catalog.routes[route_id]
			if route.originId == voyage.get("originId") and route.destinationId == voyage.get("destinationId"):
				lanes[route_id] = _route_name(route_id) + " · " + str(route.minimumDepth) + "m"
		var selection := _select(parent, "voyage_route_" + str(voyage_id), "航路", lanes, str(voyage.get("routeId", "")))
		var captured := _token()
		selection.item_selected.connect(func(index):
			var route_id := str(selection.get_item_metadata(index))
			var ship := _vessel(id)
			var profile := _profile(ship)
			var draft := float(profile.get("baseDraftMeters", 0)) + _sum(ship.get("cargo", {})) * float(profile.get("cargoDraftMetersPerUnit", 0))
			if draft < float(_catalog.routes[route_id].minimumDepth): _send({"type": "choose-route", "voyageId": voyage_id, "routeId": route_id}, captured))
		_watchers.append(func():
			var current: Dictionary = _state().get("voyages", {}).get(voyage_id, {})
			var active := false
			for contract in _state().get("contracts", {}).values():
				if contract.get("status") == "active" and voyage_id in contract.get("voyageIds", []): active = true
			selection.disabled = not active or not current.get("status") in ["loading", "underway"]
			var ship := _vessel(id)
			var profile := _profile(ship)
			var draft := float(profile.get("baseDraftMeters", 0)) + _sum(ship.get("cargo", {})) * float(profile.get("cargoDraftMetersPerUnit", 0))
			for index in selection.item_count: selection.set_item_disabled(index, draft >= float(_catalog.routes[selection.get_item_metadata(index)].minimumDepth)))
	_heading(parent, "情报与凭单")
	_text(parent, "intelligence", func():
		var entries: PackedStringArray = []
		for info in _state().get("intelligence", []): entries.append("%s · 粮估计 %d · %.0f秒采集 · 可信度 %.0f%%" % [_port_name(info.get("portId")), info.get("stock", {}).get("grain", 0), info.get("observedAt", 0), float(info.get("confidence", 0)) * 100])
		return "\n".join(entries) if not entries.is_empty() else "尚无采集情报。")
	_receipts(parent, "fleet_receipts", ["accept-convoy", "claim-convoy", "shipment-arrived", "choose-route", "depart"])

func _contract_timing(contract: Dictionary) -> String:
	match str(contract.get("status", "")):
		"offered": return "接单前也计时 · " + _deadline_timing(contract) if float(contract.get("deadlineAt", 0)) > 0 else "接单后开始计时"
		"active": return _deadline_timing(contract)
		"delivered": return "交付已记录，待核对报酬"
		"failed": return "失败结果已记录"
		"settled": return "实际报酬已结算"
	return "等待委托核验"

func _deadline_timing(contract: Dictionary) -> String:
	var remaining := float(contract.get("deadlineAt", 0)) - float(_state().get("simulationSeconds", 0))
	return "期限剩余 %.0f秒" % ceil(remaining) if remaining >= 0 else "已逾期 %.0f秒" % ceil(-remaining)

func _voyage_detail(voyage: Dictionary) -> String:
	match str(voyage.get("status", "")):
		"underway":
			var remaining := float(voyage.get("eta", 0)) - float(_state().get("simulationSeconds", 0))
			var timing := "预计还需 %.0f秒" % ceil(remaining) if remaining > 0 else "预计时间已过，尚未抵达"
			return "航段 %d / %.0f%% · %s" % [int(voyage.get("leg", 0)) + 1, float(voyage.get("progress", 0)) * 100, timing]
		"loading":
			for contract in _state().get("contracts", {}).values():
				if voyage.get("id") in contract.get("voyageIds", []) and contract.get("status") == "offered": return "请先接下委托，再核对航线、吃水与离港条件"
			if not _operational(): return _reason("runtime-unavailable")
			if _runtime().get("canDepart", false): return "离港条件已核验，等待离港起航"
			return "等待出航整备 · " + _reason(_runtime().get("departReason", "save-unverified"))
		"arrived": return "抵达已记录，交付与报酬按实际回执核对"
		"lost": return "船只损失已记录，请核对货物与人员回执"
		"interrupted": return "航程中断，请核对船员与船况"
	return "等待航程核验"

func _route_name(id: String) -> String:
	return {"xiamen-kinmen-deep": "厦门—金门深水道", "xiamen-kinmen-shallow": "厦门—金门浅水捷径", "xiamen-kinmen-outer": "厦门—金门外海线", "kinmen-supply-deep": "金门—近岸补给线"}.get(id, id)
func _claim_ready(id: String) -> bool:
	var contract: Dictionary = _state().get("contracts", {}).get(id, {})
	if not _operational() or not contract.get("status") in ["active", "delivered", "failed"] or contract.get("voyageIds", []).is_empty(): return false
	var loaded := false
	for receipt in _state().get("settlements", {}).values():
		var details: Dictionary = receipt.get("details", {})
		if details.get("kind") == "convoy-load" and details.get("contractId") == id and details.get("loaded", 0) > 0: loaded = true
	if not loaded: return false
	for voyage_id in contract.get("voyageIds", []):
		if not _state().get("voyages", {}).get(voyage_id, {}).get("status") in ["arrived", "lost"]: return false
	return true

func _build_port(parent: Control) -> void:
	_art(parent, "res://assets/art/ports/xiamen-harbor-v1.png", 120)
	_text(parent, "port_current", func(): return "当前：" + _port_name(_state().get("currentPortId")), 22)
	for id in _catalog.get("ports", {}):
		_button(parent, "port_dock_" + id, "请求靠泊 " + _catalog.ports[id].name, func(): return {"type": "dock", "portId": id}, func(): return _dock_ok(id))
		_text(parent, "port_dock_reason_" + id, func(): return "可请求安全靠泊。" if _dock_ok(id) else _reason(_dock_reason(id)), 14)
	_heading(parent, "粮食交易")
	_text(parent, "trade_stock", func():
		var stock = _ports().get(str(_state().get("currentPortId")), {}).get("stock", {}).get("grain")
		var occupied := _sum(_flag().get("cargo", {}))
		return "港口库存 %s  ·  自有粮 %d\n旗舰货舱 %d/%d · 委托货物不可出售" % [str(stock) if stock != null else "未靠港", _flag().get("cargo", {}).get("grain", 0) if _flag().get("voyageId") == null else 0, occupied, _profile(_flag()).get("capacity", 0)])
	_number(parent, "trade_quantity", "交易数量", 1, 10000)
	_text(parent, "trade_quote", func():
		var buy := _trade_quote("buy")
		var sell := _trade_quote("sell")
		return "买入：%s\n卖出：%s" % [str(buy.get("total", 0)) + "两" if buy.ok else _reason(buy.reason), str(sell.get("total", 0)) + "两" if sell.ok else _reason(sell.reason)])
	var trade := _row(parent)
	for type in ["buy", "sell"]: _button(trade, "trade_" + type, "买入粮食" if type == "buy" else "卖出粮食", func(): return {"type": type, "good": "grain", "quantity": int(_form.trade_quantity)}, func(): return _trade_quote(type).ok and _fact(type).get("ok", false))
	_text(parent, "trade_native_reason", func():
		var reasons: PackedStringArray = []
		for type in ["buy", "sell"]:
			var fact := _fact(type)
			if not fact.get("ok", false): reasons.append(("买入：" if type == "buy" else "卖出：") + _reason(fact.get("reason", "save-unverified")))
		return "\n".join(reasons), 14, Parchment.DANGER)
	_heading(parent, "船务与治伤")
	_select(parent, "service_ship", "作业船只", _ship_options(true), str(_state().get("flagshipId", "")))
	_text(parent, "service_crew", func(): return _crew_text(_vessel(str(_form.get("service_ship", "")))))
	_number(parent, "treatment_quantity", "治伤人数", 1, 10000)
	for type in ["repair", "refit", "release-prisoners", "treat-wounded"]:
		var names := {"repair": "请求修理", "refit": "申请帆装改造", "release-prisoners": "释放俘虏", "treat-wounded": "申请治伤"}
		_button(parent, "service_" + type.replace("-", "_"), names[type], func():
			var intent := {"type": type, "shipId": _form.get("service_ship", "")}
			if type == "refit": intent["slot"] = "sails"
			if type == "treat-wounded": intent["quantity"] = int(_form.treatment_quantity)
			return intent, func(): return _service_ok(type))
		_text(parent, "service_reason_" + type.replace("-", "_"), func():
			var quote := _service_quote(type)
			var fact := _fact(type, str(_form.get("service_ship", "")))
			return "预计 %d两 · %.0f模拟秒；受理后等待完成。" % [quote.get("cost", 0), quote.get("duration", 0)] if quote.ok and fact.get("ok", false) else _reason(quote.get("reason", fact.get("reason", "save-unverified"))), 14)
	_text(parent, "service_note", func(): return "补给点单次最多修复船体20、帆20；帆装改造仅厦门自有船。暂停时工期不推进，伤员须治疗完成才能转为可战。", 14)
	_heading(parent, "作业记录")
	_text(parent, "works", func():
		var entries: PackedStringArray = []
		for work in _state().get("works", {}).values():
			entries.append("%s · %s · %s\n实付 %d两 · 到期 %.0f秒 · 尚需 %.0f秒" % [_name(work.get("shipId")), {"treatment": "治伤", "repair": "修理", "refit": "帆装"}.get(work.get("kind"), "船务"), _status(work.get("status")), work.get("cost", 0), work.get("completeAt", 0), maxf(0, float(work.get("completeAt", 0)) - float(_state().get("simulationSeconds", 0)))])
		return "\n\n".join(entries) if not entries.is_empty() else "暂无作业。")
	_receipts(parent, "port_receipts", ["dock", "buy", "sell", "repair", "refit", "treat-wounded", "release-prisoners", "work-completed"])

func _dock_ok(id: String) -> bool:
	var value = _runtime().get("canDock")
	if value is Dictionary:
		var fact = value.get(id, false)
		return fact.get("ok", false) == true if fact is Dictionary else fact == true
	return value == true and _runtime().get("portId") == id
func _dock_reason(id: String) -> String:
	var facts = _runtime().get("canDock")
	if facts is Dictionary and facts.get(id) is Dictionary: return str(facts[id].get("reason", "save-unverified"))
	var reason = _runtime().get("dockReason", "save-unverified")
	return str(reason.get(id, "save-unverified")) if reason is Dictionary else str(reason)
func _trade_quote(type: String) -> Dictionary:
	var quantity := int(_form.get("trade_quantity", 1))
	if quantity <= 0 or quantity > 10000: return {"ok": false, "reason": "invalid-quantity"}
	var port: Dictionary = _ports().get(str(_state().get("currentPortId")), {})
	var ship := _flag()
	if port.is_empty() or ship.is_empty(): return {"ok": false, "reason": "not-in-port"}
	if ship.get("voyageId") != null: return {"ok": false, "reason": "contract-cargo"}
	if float(ship.get("pose", {}).get("speed", 1)) > 0.5 or float(ship.get("controls", {}).get("sailDeployment", 1)) > 0 or ship.get("damage", {}).get("hull", 0) <= 0 or ship.get("damage", {}).get("fire", 0) > 0 or ship.get("damage", {}).get("flooding", 0) > 0: return {"ok": false, "reason": "unsafe-port"}
	var stock := int(port.get("stock", {}).get("grain", 0))
	if type == "buy" and quantity > stock: return {"ok": false, "reason": "insufficient-stock"}
	if type == "buy" and quantity + _sum(ship.get("cargo", {})) > int(_profile(ship).get("capacity", 0)): return {"ok": false, "reason": "insufficient-capacity"}
	if type == "sell" and quantity > int(ship.get("cargo", {}).get("grain", 0)): return {"ok": false, "reason": "insufficient-cargo"}
	var total := 0
	for unit in quantity:
		total += maxi(2, 10 + int(floor((100.0 - (stock - 1 if type == "buy" else stock)) / 20.0))) + (1 if type == "buy" else -1)
		stock += -1 if type == "buy" else 1
	if type == "buy" and total > int(_state().get("captain", {}).get("silver", 0)): return {"ok": false, "reason": "insufficient-silver"}
	return {"ok": true, "total": total}
func _service_quote(type: String) -> Dictionary:
	var id := str(_form.get("service_ship", ""))
	var ship := _vessel(id)
	if ship.is_empty() or _state().get("currentPortId") == null: return {"ok": false, "reason": "not-in-port"}
	for work in _state().get("works", {}).values():
		if work.get("shipId") == id and work.get("status") == "active": return {"ok": false, "reason": "ship-working"}
	var cost := 0
	var duration := 0.0
	if type == "refit":
		if _state().get("currentPortId") != "xiamen" or ship.get("ownerId") != "captain" or _profile(ship).get("refitProfileId") == null: return {"ok": false, "reason": "refit-forbidden"}
		cost = 150
		duration = 120
	elif type == "repair":
		var limit := 20.0 if _state().get("currentPortId") == "forward-supply" else 100.0
		var damage: Dictionary = ship.get("damage", {})
		var repairs := minf(limit, 100 - float(damage.get("hull", 100))) + minf(limit, 100 - float(damage.get("sail", 100)))
		cost = int(ceil(repairs * 2))
		duration = maxf(1, ceil(repairs / 2))
		if cost <= 0: return {"ok": false, "reason": "no-damage"}
	elif type == "treat-wounded":
		var quantity := int(_form.treatment_quantity)
		if ship.get("crew", {}).get("wounded", 0) <= 0: return {"ok": false, "reason": "no-wounded"}
		if quantity <= 0 or quantity > int(ship.get("crew", {}).get("wounded", 0)): return {"ok": false, "reason": "insufficient-wounded"}
		cost = 4 * quantity
		duration = 30 * quantity
	elif ship.get("crew", {}).get("prisoners", 0) <= 0: return {"ok": false, "reason": "no-prisoners"}
	if cost > int(_state().get("captain", {}).get("silver", 0)): return {"ok": false, "reason": "insufficient-silver"}
	return {"ok": true, "cost": cost, "duration": duration}
func _service_ok(type: String) -> bool:
	return _operational() and _service_quote(type).ok and _fact(type, str(_form.get("service_ship", ""))).get("ok", false)

func _build_boarding(parent: Control) -> void:
	_heading(parent, "接舷作战")
	_select(parent, "boarding_source", "供船", _ship_options(true), str(_state().get("flagshipId", "")))
	var enemies: Dictionary = {}
	for id in _vessels():
		if _vessel(id).get("ownerId") == "enemy" and not _state().get("prizes", {}).has(id): enemies[id] = _name(id)
	_select(parent, "boarding_target", "敌舰", enemies)
	_text(parent, "boarding_preview", func():
		var source := _vessel(str(_form.get("boarding_source", "")))
		var target := _vessel(str(_form.get("boarding_target", "")))
		return _crew_text(source) + "\n目标：" + str(target.get("name", "请选择敌舰")) + " · 船体 %.0f · 可战 %d" % [target.get("damage", {}).get("hull", 0), target.get("crew", {}).get("able", 0)])
	_button(parent, "board_start", "请求接舷", func(): return {"type": "start-boarding", "fromShipId": _form.get("boarding_source", ""), "targetId": _form.get("boarding_target", "")}, func(): return not str(_form.get("boarding_target", "")).is_empty() and _fact("start-boarding", str(_form.get("boarding_source", "")), str(_form.get("boarding_target", ""))).get("ok", false))
	_text(parent, "boarding_conditions", func(): return "须接近削弱敌舰：相距≤36m、相对速度≤3m/s、供船保留最低船员，且未在作业。", 14)
	_text(parent, "boarding_reason", func(): return _reason(_fact("start-boarding", str(_form.get("boarding_source", "")), str(_form.get("boarding_target", ""))).get("reason", "")), 14)
	for id in _state().get("boardings", {}):
		_text(parent, "boarding_" + id, func():
			var encounter: Dictionary = _state().get("boardings", {}).get(id, {})
			var morale: Dictionary = encounter.get("morale", {})
			var names: PackedStringArray = []
			for participant in encounter.get("participants", []): names.append(_name(participant))
			return "%s 对 %s · %s\n士气 我%.1f / 敌%.1f · 交锋%.1f秒\n参与：%s" % [_name(encounter.get("attackerId")), _name(encounter.get("targetId")), _status(encounter.get("status")), morale.get("attacker", 0), morale.get("defender", 0), encounter.get("elapsedSeconds", 0), "、".join(names)])
		for point in ["bow", "deck", "helm"]:
			var names := {"bow": "船首", "deck": "甲板", "helm": "舵楼"}
			_text(parent, "point_" + id + "_" + point, func():
				var current: Dictionary = _state().get("boardings", {}).get(id, {}).get("points", {}).get(point, {})
				return names[point] + " · 控制 %.1f · " % current.get("control", 0) + ("推进" if current.get("action") == "advance" else "守住"))
			var actions := _row(parent)
			for action in ["advance", "hold", "cut-lines"]:
				_button(actions, "board_action_" + id + "_" + point + "_" + action, {"advance": "推进", "hold": "守住", "cut-lines": "断缆"}[action], func(): return {"type": "board-action", "encounterId": id, "point": point, "action": action}, func(): return _operational() and _state().get("boardings", {}).get(id, {}).get("status") == "active")
	_heading(parent, "战利船与押船员")
	var prizes: Dictionary = {}
	for id in _state().get("prizes", {}): prizes[id] = _name(id) + " · " + _status(_state().prizes[id].get("status"))
	_select(parent, "prize_target", "战利船", prizes)
	_text(parent, "prize_state", func():
		var id := str(_form.get("prize_target", ""))
		if id.is_empty(): return "尚无经过胜利回执核验的战利船。"
		var ship := _vessel(id)
		return _name(id) + " · " + _status(_state().get("prizes", {}).get(id, {}).get("status")) + "\n" + _crew_text(ship) + "\n" + _cargo(ship.get("cargo", {})) + " · 货舱 %d/%d" % [_sum(ship.get("cargo", {})), _profile(ship).get("capacity", 0)])
	_number(parent, "prize_crew", "押船员人数", 1, 1000)
	_button(parent, "prize_allocate", "调拨押船员", func(): return {"type": "allocate-prize", "fromShipId": _form.get("boarding_source", ""), "targetId": _form.get("prize_target", ""), "crew": int(_form.prize_crew)}, func(): return _prize_status() == "held" and _prize_fact("allocate-prize").get("ok", false) and int(_form.prize_crew) >= maxi(12, int(_vessel(str(_form.get("prize_target", ""))).get("crew", {}).get("minimum", 0))))
	_text(parent, "prize_allocation_note", func(): return "至少调拨12人并满足目标最低船员；供船须保留最低船员及俘虏看守。等待押船员时，人员与银两保持实际状态。", 14)
	_select(parent, "prize_receiver", "货物 / 救人接收船", _ship_options(true))
	_select(parent, "prize_good", "货物", GOODS, "grain")
	_number(parent, "prize_quantity", "取货数量", 1, 10000)
	_button(parent, "prize_take_cargo", "取出实有货物", func(): return {"type": "take-prize-cargo", "targetId": _form.get("prize_target", ""), "toShipId": _form.get("prize_receiver", ""), "cargo": {str(_form.prize_good): int(_form.prize_quantity)}}, func(): return _prize_status() == "held" and _prize_fact("take-prize-cargo").get("ok", false) and _prize_cargo_ok())
	var resolution := _row(parent)
	_button(resolution, "prize_release", "释放战利船", func(): return {"type": "resolve-prize", "targetId": _form.get("prize_target", ""), "choice": "release"}, func(): return _prize_status() == "held" and _fact("resolve-prize", str(_form.get("prize_target", ""))).get("ok", false))
	_button(resolution, "prize_abandon", "救人弃船", func(): return {"type": "resolve-prize", "targetId": _form.get("prize_target", ""), "choice": "abandon", "toShipId": _form.get("prize_receiver", "")}, func(): return _prize_status() == "held" and _rescue_fact().get("ok", false) and _prize_people_ok(false))
	_text(parent, "prize_rescue_note", func(): return "救人弃船须接收全部伤员与俘虏；释放将俘虏恢复为该船可战人员。接收船须有真实容量与看守，两船须安全停稳。", 14)
	_heading(parent, "售船与永久编入")
	_select(parent, "prize_sale_receiver", "售船人员接收船", _owned_options())
	_text(parent, "prize_sale_value", func():
		var ship := _vessel(str(_form.get("prize_target", "")))
		var profile := _profile(ship)
		var damage: Dictionary = ship.get("damage", {})
		var price := 200 * float(damage.get("hull", 0)) / maxf(1, float(profile.get("maxHull", 100))) + 100 * float(damage.get("sail", 0)) / maxf(1, float(profile.get("maxSail", 100)))
		return "船体估价 %d两 · 以实际售船回执为准" % int(maxf(1, floor(price))))
	_button(parent, "prize_sell", "出售战利船", func(): return {"type": "sell-prize", "shipId": _form.get("prize_target", ""), "crewToShipId": _form.get("prize_sale_receiver", "")}, func(): return _prize_status() == "crewed" and _prize_fact("sell-prize").get("ok", false) and _sum(_vessel(str(_form.get("prize_target", ""))).get("cargo", {})) == 0 and _prize_people_ok(true) and _state().get("currentPortId") in ["xiamen", "kinmen"])
	_button(parent, "prize_incorporate", "永久编入船队", func(): return {"type": "incorporate-prize", "shipId": _form.get("prize_target", "")}, func(): return _prize_status() == "crewed" and _prize_fact("incorporate-prize").get("ok", false) and _state().get("currentPortId") in ["xiamen", "kinmen"])
	_text(parent, "prize_market_note", func(): return "厦门、金门同港安全锚泊才可处置；补给点没有售船市场。售船须先清空货物，全部人员转入自有接收船。", 14)
	_text(parent, "prize_reason", func(): return _reason(_prize_fact("allocate-prize" if _prize_status() == "held" else "sell-prize").get("reason", "")), 14)
	_receipts(parent, "boarding_receipts", ["start-boarding", "boarding", "allocate-prize", "take-prize-cargo", "resolve-prize", "sell-prize", "incorporate-prize"])

func _prize_status() -> String: return str(_state().get("prizes", {}).get(str(_form.get("prize_target", "")), {}).get("status", ""))
func _rescue_fact() -> Dictionary:
	var target := str(_form.get("prize_target", ""))
	var receiver := str(_form.get("prize_receiver", ""))
	var missing := {"ok": false, "reason": "save-unverified"}
	if target.is_empty() or receiver.is_empty(): return missing
	var fact = _runtime().get("eligibility", {}).get("resolve-prize:" + target + ":" + receiver, missing)
	return fact if fact is Dictionary else missing
func _prize_fact(type: String) -> Dictionary:
	var target := str(_form.get("prize_target", ""))
	if type == "allocate-prize": return _fact(type, str(_form.get("boarding_source", "")), target)
	if type == "sell-prize": return _fact(type, target, str(_form.get("prize_sale_receiver", "")))
	if type == "incorporate-prize": return _fact(type, target)
	return _fact(type, target, str(_form.get("prize_receiver", "")))
func _prize_cargo_ok() -> bool:
	var id := str(_form.get("prize_target", ""))
	var target := _vessel(id)
	var receiver_id := str(_form.get("prize_receiver", ""))
	var receiver := _vessel(receiver_id)
	var quantity := int(_form.get("prize_quantity", 0))
	return id != receiver_id and not receiver.is_empty() and _authorized(receiver_id) and quantity > 0 and quantity <= int(target.get("cargo", {}).get(str(_form.prize_good), 0)) and quantity + _sum(receiver.get("cargo", {})) <= int(_profile(receiver).get("capacity", 0))
func _prize_people_ok(sale: bool) -> bool:
	var id := str(_form.get("prize_target", ""))
	var receiver_id := str(_form.get("prize_sale_receiver" if sale else "prize_receiver", ""))
	var source: Dictionary = _vessel(id).get("crew", {})
	var receiver := _vessel(receiver_id)
	if id == receiver_id or receiver.is_empty() or (sale and receiver.get("ownerId") != "captain"): return false
	var crew: Dictionary = receiver.get("crew", {})
	var added := int(source.get("wounded", 0)) + int(source.get("prisoners", 0)) + (int(source.get("able", 0)) if sale else 0)
	var able := int(crew.get("able", 0)) + (int(source.get("able", 0)) if sale else 0)
	return _sum(crew_without_minimum(crew)) + added <= int(_profile(receiver).get("maxCrew", 0)) and able >= int(ceil((float(crew.get("prisoners", 0)) + float(source.get("prisoners", 0))) / 5)) and able >= int(crew.get("minimum", 0))
func crew_without_minimum(crew: Dictionary) -> Dictionary: return {"able": crew.get("able", 0), "wounded": crew.get("wounded", 0), "prisoners": crew.get("prisoners", 0)}

func _build_tactics(parent: Control) -> void:
	_heading(parent, "受指挥船只")
	for id in _ship_options(true):
		var box := CheckBox.new()
		box.name = "tactics_ship_" + id
		box.text = _name(id)
		box.button_pressed = id in _selected
		parent.add_child(box)
		var captured := _token()
		box.toggled.connect(func(value):
			if captured != _token(): return
			if value and not id in _selected: _selected.append(id)
			elif not value: _selected.erase(id)
			_refresh())
		_watchers.append(func(): box.disabled = not _authorized(id))
	_select(parent, "tactics_kind", "战术指令", ORDER_NAMES, "protect")
	_select(parent, "tactics_target", "明确目标", _ship_options(false))
	_number(parent, "tactics_range", "保持距离（米）", 1, 10000)
	_number(parent, "point_x", "集结 / 航位 X", -100000, 100000)
	_number(parent, "point_z", "集结 / 航位 Z", -100000, 100000)
	_text(parent, "tactics_target_text", func(): return "当前目标：" + ("海图点 (%.1f, %.1f)" % [_form.point_x, _form.point_z] if _form.tactics_kind == "rally" else _name(_form.get("tactics_target", ""))))
	_button(parent, "tactics_submit", "下达战术指令", _order_payload, _order_valid)
	_button(parent, "navigate", "旗舰驶向指定航位", func(): return {"type": "navigate", "shipId": _state().get("flagshipId"), "point": {"x": float(_form.point_x), "z": float(_form.point_z)}}, func(): return _can_sail())
	_text(parent, "tactics_pause_note", func(): return "航程暂停；战术草案恢复后检查原目标与版本。" if _runtime().get("paused", false) else "指令按真实船况与目标检查；手动操船接管旗舰。", 14)
	_heading(parent, "实际指令与草案")
	_text(parent, "orders", func():
		var texts: PackedStringArray = []
		var statuses: Dictionary = {}
		for order in _runtime().get("orderStatuses", []): statuses[order.get("id", "")] = order
		for order in _state().get("orders", []):
			var names: PackedStringArray = []
			for id in order.get("shipIds", []): names.append(_name(id))
			var intent: Dictionary = order.get("intent", {})
			var current: Dictionary = statuses.get(order.get("id", ""), {})
			texts.append("%s · %s\n%s · %s\n%s" % [ORDER_NAMES.get(intent.get("kind"), "战术"), _status(current.get("state", current.get("status", "history"))), "、".join(names), _name(intent.get("targetId")) if intent.has("targetId") else "海图集结点", _reason(current.get("reason", ""))])
		for draft in _runtime().get("drafts", []): texts.append("指令草案 · " + _reason(draft.get("reason", "")))
		return "\n\n".join(texts) if not texts.is_empty() else "暂无战术指令。")

func _order_valid() -> bool:
	if not _operational() or _selected.is_empty(): return false
	for id in _selected:
		if not _authorized(id): return false
	if _form.tactics_kind == "rally": return is_finite(float(_form.point_x)) and is_finite(float(_form.point_z))
	var target_id := str(_form.get("tactics_target", ""))
	if target_id in _selected or _vessel(target_id).is_empty(): return false
	var hostile: bool = _vessel(target_id).get("ownerId") == "enemy" and not _state().get("prizes", {}).has(target_id)
	return not hostile if _form.tactics_kind == "protect" else true if _form.tactics_kind == "keep-distance" else hostile
func _order_payload() -> Dictionary:
	var intent := {"kind": _form.tactics_kind}
	if _form.tactics_kind == "rally": intent["point"] = {"x": float(_form.point_x), "z": float(_form.point_z)}
	else: intent["targetId"] = _form.get("tactics_target", "")
	if _form.tactics_kind == "keep-distance": intent["range"] = float(_form.tactics_range)
	return {"type": "assign-order", "order": {"id": "", "shipIds": _selected.duplicate(), "intent": intent, "issuedAt": float(_state().get("simulationSeconds", 0))}}

func _build_menu() -> void:
	_menu = _box(_screen, "voyage_menu")
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_menu.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	scroll.add_child(body)
	_heading(body, "海上明旗 · 航程菜单")
	_text(body, "menu_state", func(): return "世界已暂停。" if _runtime().get("paused", false) else "暂停航行后可安心查看账本与存档。")
	_local_button(body, "menu_resume", "继续航行", func():
		close_menu()
		_send({"type": "pause", "value": false}, _token()))
	_text(body, "save_reason", func(): return "安全条件已核验，可保存航程。" if _runtime().get("canSave", false) == true else _reason(_runtime().get("saveReason", "save-unverified")), 16, Parchment.DANGER)
	_button(body, "save", "保存安全航程", func(): return {"type": "save"}, func(): return _runtime().get("canSave", false) == true)
	_button(body, "save_and_menu", "保存并返回主菜单", func(): return {"type": "save-and-menu"}, func(): return _runtime().get("canSave", false) == true)
	_local_button(body, "menu_settings", "画面与声音设置", func(): _send({"type":"open-settings"}, _token()))
	_button(body, "export_current", "导出当前安全航程", func(): return {"type": "export-save", "kind": "current"}, func(): return _runtime().get("canSave", false) == true)
	_button(body, "export_backup", "导出上次安全存档", func(): return {"type": "export-save", "kind": "backup"}, func(): return _runtime().get("hasCheckpoint", false) == true)
	_text(body, "save_status", func(): return str(_runtime().get("saveStatus", "")))
	_heading(body, "导入存档")
	var input := TextEdit.new()
	input.name = "import_json"
	input.custom_minimum_size = Vector2(0, 125)
	input.placeholder_text = "粘贴完整 JSON 存档"
	input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	body.add_child(input)
	_button(body, "import_save", "验证并导入", func(): return {"type": "import-save", "json": input.text}, func(): return not input.text.strip_edges().is_empty() and not _runtime().get("importing", false))
	input.text_changed.connect(_refresh)
	var picker := FileDialog.new()
	picker.name = "import_file_picker"
	picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.filters = PackedStringArray(["*.json ; JSON 存档"])
	_screen.add_child(picker)
	picker.theme = Parchment.create()
	var captured := _token()
	picker.file_selected.connect(func(path): _send({"type": "import-save", "path": path}, captured))
	_local_button(body, "import_choose_file", "选择 JSON 存档文件", func():
		picker.popup_centered_ratio(0.7)
		picker.title = "导入航程存档"
		picker.ok_button_text = "导入"
		picker.get_cancel_button().text = "取消")
	_text(body, "import_note", func(): return "导入先核验完整存档。验证失败时保留当前航程；原文件不改动。", 14)
	_local_button(body, "menu_close", "收起菜单", close_menu)

func _ship_options(authorized: bool) -> Dictionary:
	var options: Dictionary = {}
	for id in _vessels():
		if not authorized or _authorized(id) or (_vessel(id).get("ownerId") == "captain" and _vessel(id).get("damage", {}).get("hull", 0) > 0): options[id] = _name(id)
	return options
func _owned_options() -> Dictionary:
	var options: Dictionary = {}
	for id in _vessels():
		if _vessel(id).get("ownerId") == "captain": options[id] = _name(id)
	return options
func _refresh() -> void:
	for update in _watchers: update.call()

func _receipts(parent: Control, id: String, kinds: Array) -> void:
	_text(parent, id, func():
		var texts: PackedStringArray = []
		var receipts: Array = _state().get("settlements", {}).values()
		receipts.reverse()
		for receipt in receipts:
			if not receipt.get("kind") in kinds: continue
			texts.append(str(receipt.get("message", "")))
			var detail: Dictionary = receipt.get("details", {})
			if detail.get("kind") == "convoy":
				texts.append("实交 %d粮 · 待交 %d · 损失 %d · 实收 %d两（奖金%d）" % [detail.get("delivered", 0), detail.get("pending", 0), detail.get("lost", 0), int(detail.get("baseReward", 0)) + int(detail.get("bonus", 0)), detail.get("bonus", 0)])
			if texts.size() >= 12: break
		return "\n\n".join(texts) if not texts.is_empty() else "暂无实际回执。")

func _box(parent: Node, id: String) -> PanelContainer:
	var box := PanelContainer.new()
	box.name = id
	if id.begins_with("story_scene_") or id == "voyage_closure":
		box.add_theme_stylebox_override("panel", Parchment.panel(14, "inset"))
	parent.add_child(box)
	return box
func _column(parent: Node) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	parent.add_child(column)
	return column
func _row(parent: Node) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	return row
func _heading(parent: Control, text: String) -> void:
	var separator := HSeparator.new()
	parent.add_child(separator)
	_text(parent, "heading_" + str(parent.get_child_count()), func(): return text, 20, Parchment.CINNABAR)
func _text(parent: Node, id: String, source: Callable, font_size: int = 16, color: Color = Parchment.INK) -> Label:
	var label := Label.new()
	label.name = id
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if font_size >= 20: label.add_theme_font_override("font", Parchment.title_font())
	parent.add_child(label)
	_watchers.append(func(): label.text = str(source.call()))
	return label
func _local_button(parent: Node, id: String, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = id
	button.text = text
	button.custom_minimum_size = Vector2(80, 36)
	parent.add_child(button)
	var captured := _token()
	var button_ref: WeakRef = weakref(button)
	button.pressed.connect(func():
		if captured != _token(): return
		var live: Variant = button_ref.get_ref()
		if live is Button and not live.disabled: action.call())
	return button
func _button(parent: Node, id: String, text: String, payload: Callable, enabled: Callable) -> Button:
	var captured := _token()
	var button := _local_button(parent, id, text, func():
		if enabled.call(): _send(payload.call(), captured))
	_watchers.append(func(): button.disabled = not bool(enabled.call()))
	return button
func _number(parent: Node, id: String, text: String, minimum: float, maximum: float) -> SpinBox:
	var row := _row(parent)
	_text(row, id + "_label", func(): return text)
	var field := SpinBox.new()
	field.name = id
	field.min_value = minimum
	field.max_value = maximum
	field.step = 1
	field.custom_minimum_size = Vector2(130, 36)
	field.value = float(_form.get(id, minimum))
	row.add_child(field)
	var captured := _token()
	field.value_changed.connect(func(value):
		if captured != _token(): return
		_form[id] = value
		_refresh())
	return field
func _select(parent: Node, id: String, text: String, options: Dictionary, default: String = "") -> OptionButton:
	_text(parent, id + "_label", func(): return text)
	var field := OptionButton.new()
	field.name = id
	field.custom_minimum_size = Vector2(0, 36)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.fit_to_longest_item = false
	parent.add_child(field)
	var value := str(_form.get(id, default))
	if not options.has(value): value = str(options.keys()[0]) if not options.is_empty() else ""
	_form[id] = value
	for key in options:
		field.add_item(str(options[key]))
		field.set_item_metadata(field.item_count - 1, key)
		if key == value: field.select(field.item_count - 1)
	var captured := _token()
	field.item_selected.connect(func(index):
		if captured != _token(): return
		_form[id] = field.get_item_metadata(index)
		_refresh())
	return field
func _slider(parent: Node, id: String, text: String, minimum: float, maximum: float, step: float, field: String) -> void:
	_text(parent, id + "_label", func(): return text + " · %.2f" % _native(str(_state().get("flagshipId", ""))).get(field, 0))
	var slider := HSlider.new()
	slider.name = id
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.custom_minimum_size = Vector2(0, 30)
	parent.add_child(slider)
	var captured := _token()
	slider.value_changed.connect(func(value):
		if _can_sail(): _send({"type": "controls", "shipId": _state().get("flagshipId"), field: value}, captured))
	_watchers.append(func():
		slider.editable = _can_sail()
		if not slider.has_focus(): slider.set_value_no_signal(float(_native(str(_state().get("flagshipId", ""))).get(field, 0))))
func _art(parent: Node, path: String, height: float) -> void:
	if not ResourceLoader.exists(path): return
	var art := TextureRect.new()
	art.texture = load(path)
	art.custom_minimum_size = Vector2(0, height)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(art)

func _queue_layout() -> void:
	if _layout_queued: return
	_layout_queued = true
	_flush_layout.call_deferred()

func _flush_layout() -> void:
	_layout_queued = false
	_layout()

func _layout() -> void:
	if not _screen or not _operation: return
	var viewport := _screen.get_viewport_rect().size
	var hud = _screen.find_child("hud", true, false)
	if hud:
		hud.position = Vector2(18, 18)
		hud.size = Vector2(minf(430, viewport.x - 36), hud.get_combined_minimum_size().y)
	var width := minf(470, viewport.x - 36)
	var narrow := viewport.x < 960
	_operation.position = Vector2(18 if narrow else viewport.x - width - 18, hud.position.y + hud.size.y + 16 if narrow and hud else 18)
	_operation.size = Vector2(width, maxf(0, viewport.y - _operation.position.y - 18))
	_menu.position = Vector2(maxf(18, (viewport.x - 500) / 2), 24)
	_menu.size = Vector2(minf(500, viewport.x - 36), maxf(220, viewport.y - 48))

func _make_theme() -> Theme:
	return Parchment.create()
