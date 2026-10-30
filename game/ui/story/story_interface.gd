extends CanvasLayer
## Thin story operations panel. Sends operation intents only — never outcomes.
## Renders the current stage briefing, chapter drama, per-objective live
## witnesses, the recovery exit and the transition card.

signal command_requested(intent: Dictionary)
const Catalog = preload("res://game/domain/story_campaign/catalog.gd")
const Heroes = preload("res://game/domain/story_campaign/heroes.gd")

var _title: Label
var _body: RichTextLabel
var _notice: Label
var _port: LineEdit
var _transition: PanelContainer
var _transition_label: Label
var _buttons: Dictionary = {}
var _help: PanelContainer
var _help_text: RichTextLabel
var _journal: PanelContainer
var _journal_text: RichTextLabel
var _journal_lines: Array = []

func _ready() -> void:
	layer = 40
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -430
	panel.offset_top = 12
	panel.offset_right = -12
	panel.offset_bottom = 560
	add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	_title = Label.new()
	_title.text = "主线航程"
	column.add_child(_title)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.custom_minimum_size = Vector2(390, 300)
	column.add_child(_body)
	_notice = Label.new()
	_notice.text = ""
	column.add_child(_notice)
	var option_column := VBoxContainer.new()
	option_column.name = "OptionColumn"
	column.add_child(option_column)
	var hero_column := VBoxContainer.new()
	hero_column.name = "HeroColumn"
	column.add_child(hero_column)
	_port = LineEdit.new()
	_port.text = "kinmen"
	_port.placeholder_text = "港口 id（靠港/交货）"
	column.add_child(_port)
	for entry: Array in [
		["begin-stage", "开始阶段"], ["settle-stage", "阶段结算"], ["continue-story", "继续航程"],
		["retry-stage", "失败重试"], ["transition", "章节转场"],
		["dock", "靠港"], ["depart", "离港"], ["deliver", "交货30粮"],
		["buy", "买粮10"], ["sell", "卖粮10"], ["store-goods", "存仓粮10"], ["withdraw-goods", "取仓粮10"],
		["upgrade-hull", "升级船体"], ["upgrade-cannons", "升级火炮"], ["upgrade-sails", "升级帆装"], ["upgrade-equipment", "升级操舵"],
		["identify-target", "核认目标"], ["advance-day", "过一日"], ["attend-banquet", "赴宴30两"], ["gather-intel", "探听行情20两"],
		["formation-line", "编队·鱼贯"], ["formation-abreast", "编队·雁行"], ["formation-convoy", "编队·紧随"],
		["assign-escort", "令随行船护航"], ["release-escort", "解除护航"], ["treat-wounded", "疗伤5人"],
		["partner-voyage", "合伙远航200两"], ["partner-return", "分红归建"], ["journal", "航海日志"], ["help", "航海手册"], ["save", "保存航程"],
	]:
		var button := Button.new()
		button.name = str(entry[0])
		button.text = str(entry[1])
		column.add_child(button)
		_buttons[entry[0]] = button
		button.pressed.connect(func() -> void: _send(str(entry[0])))
	_transition = PanelContainer.new()
	_transition.set_anchors_preset(Control.PRESET_CENTER)
	_transition.offset_left = -280
	_transition.offset_top = -70
	_transition.offset_right = 280
	_transition.offset_bottom = 70
	_transition.visible = false
	add_child(_transition)
	_transition_label = Label.new()
	_transition_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_transition_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_transition.add_child(_transition_label)
	_help = PanelContainer.new()
	_help.set_anchors_preset(Control.PRESET_CENTER)
	_help.offset_left = -300
	_help.offset_top = -260
	_help.offset_right = 300
	_help.offset_bottom = 260
	_help.visible = false
	add_child(_help)
	_help_text = RichTextLabel.new()
	_help_text.bbcode_enabled = true
	_help_text.fit_content = true
	_help_text.custom_minimum_size = Vector2(560, 480)
	_help.add_child(_help_text)
	_help_text.text = "[b]航海手册[/b]\n\n[b]操船[/b]　WASD/方向键掌舵 · 帆桁 [ ]　调帆 R\n[b]火炮[/b]　Q 左舷 · E 右舷 · 1/2/3 换弹（实心/链/葡萄）\n[b]相机[/b]　F 归位 · 右键拖拽环视\n\n[b]阶段流程[/b]　开始阶段 → 行动 → 阶段结算；失败可重试（保损），成功后继续航程；章节转场为叙事跳年。\n[b]港口[/b]　靠港/离港 · 买卖粮 · 存取仓 · 升级船体/火炮/帆装/操舵（限船坞）· 赴宴（声望改善议价）· 接受文书\n[b]船队[/b]　编队鱼贯/雁行/紧随 · 令随行船护航 · 招募同伴与英雄（本港意愿）· 合伙远航分利\n[b]终章[/b]　谈降签约 → 撤离装载 → 接收设施 → 离港 → 结算（三项缺一不可）\n\n[i]英雄专长即时生效：领水提速、炮手快装、账房省用、船匠半价、医者返岗……入伙前看名册。行情随日漂移，情报行能探听远方。[/i]"
	_journal = PanelContainer.new()
	_journal.set_anchors_preset(Control.PRESET_CENTER)
	_journal.offset_left = -320
	_journal.offset_top = -280
	_journal.offset_right = 320
	_journal.offset_bottom = 280
	_journal.visible = false
	add_child(_journal)
	_journal_text = RichTextLabel.new()
	_journal_text.bbcode_enabled = true
	_journal_text.fit_content = true
	_journal_text.custom_minimum_size = Vector2(600, 520)
	_journal.add_child(_journal_text)

func set_readiness_provider(_provider: Callable) -> void:
	pass

func _send(type: String) -> void:
	if type == "help":
		_help.visible = not _help.visible
		return
	if type == "journal":
		var shown: Array = []
		var start: int = maxi(0, _journal_lines.size() - 60)
		for index in range(start, _journal_lines.size()):
			shown.append(str(_journal_lines[index]))
		_journal_text.text = "[b]航海日志[/b]\n" + "\n".join(shown)
		_journal.visible = not _journal.visible
		return
	var intent := {"type": type}
	if type.begins_with("upgrade-"):
		intent = {"type": "upgrade", "system": type.trim_prefix("upgrade-")}
	if type == "dock":
		intent.portId = _port.text.strip_edges()
	if type == "deliver":
		intent.good = "grain"
		intent.quantity = 30
	if type == "buy" or type == "sell" or type == "store-goods" or type == "withdraw-goods":
		intent.good = "grain"
		intent.quantity = 10
	if type == "identify-target":
		intent.shipId = _port.text.strip_edges()
	if type == "gather-intel":
		intent.portId = _port.text.strip_edges()
	if type.begins_with("formation-"):
		intent = {"type": "set-formation", "mode": type.trim_prefix("formation-")}
	if type == "assign-escort" and _fleet_ids.size() > 1:
		intent = {"type": "assign-escort", "shipId": _fleet_ids[1], "targetId": _port.text.strip_edges()}
	if type == "release-escort" and _fleet_ids.size() > 1:
		intent = {"type": "release-escort", "shipId": _fleet_ids[1]}
	if type == "treat-wounded":
		intent = {"type": "treat-wounded", "count": 5}
	if type == "partner-voyage" and not _first_person.is_empty() and _fleet_ids.size() >= 1:
		intent = {"type": "dispatch-convoy", "dispatchId": "partner-%s" % _first_person, "partnerId": _first_person, "capital": 200, "destinationPortId": _port.text.strip_edges(), "shipIds": [_fleet_ids.back()]}
	if type == "partner-return" and not _first_person.is_empty():
		intent = {"type": "return-dispatch", "dispatchId": "partner-%s" % _first_person, "resultManifest": {}}
	command_requested.emit(intent)

var _fleet_ids: Array = []
var _first_person := ""

func apply_snapshot(packet: Dictionary) -> void:
	var progress: Dictionary = packet.get("progress", {})
	var scenario: Dictionary = packet.get("runtime", {}).get("scenario", {})
	var witnesses: Dictionary = packet.get("runtime", {}).get("witnesses", {}).get("objectives", {})
	var stage: Dictionary = packet.get("runtime", {}).get("stage", {})
	var world: Dictionary = packet.get("world", {})
	var port_id: String = str(world.get("currentPortId", ""))
	_journal_lines = (packet.get("runtime", {}).get("journal", []) as Array).duplicate(true)
	_fleet_ids = []
	for ship: Dictionary in world.get("fleet", []):
		_fleet_ids.append(str(ship.id))
	_first_person = ""
	var people: Array = world.get("people", [])
	if not people.is_empty():
		_first_person = str(people[0].get("id", ""))
	_title.text = "主线航程 · %s" % str(progress.get("stageIndex", 0))
	var lines: Array = []
	var tier: int = int(packet.get("world", {}).get("meta", {}).get("difficultyTier", 1))
	var sea: String = str(packet.get("world", {}).get("weather", {}).get("sea", "breeze"))
	lines.append("[b]阶段[/b] %s（第%d次尝试 · %s · 压力档%d · 海况%s）" % [str(stage.get("id", "-")), int(progress.get("attempt", 1)), str(progress.get("phase", "")), tier, sea])
	lines.append(str(stage.get("title", "")))
	lines.append("[i]%s[/i]" % str(stage.get("briefing", "")))
	if stage.has("chapterId"):
		var chapter: Dictionary = Catalog.chapter(str(stage.get("chapterId", "")))
		if not chapter.is_empty():
			lines.append("[b]剧情[/b] %s（%s · %s）" % [str(chapter.title), str(chapter.protagonistId), str(chapter.year)])
			lines.append("想要：%s" % str(chapter.drama.want))
			lines.append("冲突：%s" % str(chapter.drama.conflict))
			lines.append("转折：%s" % str(chapter.drama.turn))
	for objective: Dictionary in stage.get("objectives", []):
		var witness: Dictionary = witnesses.get(str(objective.id), {})
		lines.append("· %s [%s] %s/%s %s" % [str(objective.id), str(objective.kind), str(witness.get("progress", 0)), str(objective.required), "✓" if bool(witness.get("ok", false)) else "…"])
	var options: Array = _charter_options(stage, scenario)
	for key: Variant in _option_buttons:
		(_option_buttons[key] as Button).visible = false
	for option: Dictionary in options:
		var button: Button = _option_button(str(option.id))
		if button != null:
			button.text = "文书中选：%s" % str(option.label)
			button.visible = true
			button.set_meta("charter", option)
	for key: Variant in _ending_buttons:
		(_ending_buttons[key] as Button).visible = false
	for binding: Dictionary in _ending_actions(stage, scenario):
		var ending_button: Button = _ending_button(str(binding.id))
		if ending_button != null:
			ending_button.text = str(binding.label)
			ending_button.visible = true
			ending_button.set_meta("ending", binding)
	lines.append("失败出口：%s" % str(stage.get("recovery", "")))
	if str(progress.get("phase", "")) == "complete":
		var summary: Dictionary = packet.get("runtime", {}).get("summary", {})
		lines.append("")
		lines.append("[b]尾声 · 航程结算[/b]")
		lines.append("两代人走完 %s 个阶段（%s 次尝试）" % [str(summary.get("stages", 0)), str(summary.get("attempts", 0))])
		lines.append("海上 %s 日 · 银 %s 两 · 舰 %s 艘 · 人手 %s（伤号 %s）" % [str(summary.get("days", 0)), str(summary.get("silver", 0)), str(summary.get("fleet", 0)), str(summary.get("crew", 0)), str(summary.get("wounded", 0))])
		lines.append("同伴 %s 人 · 俘获 %s 艘 · 文书 %s · 协议 %s" % [str(summary.get("people", 0)), str(summary.get("battles", 0)), str(summary.get("permits", 0)), str(summary.get("agreements", 0))])
		lines.append("交棒：%s" % ("郑成功接过船队与旧账" if bool(summary.get("handoff", false)) else "未交棒"))
		lines.append("")
		lines.append("[b]六幕回望[/b]")
		for act: Dictionary in summary.get("acts", []):
			lines.append("%s　%s" % ["✓" if bool(act.get("done", false)) else "…", str(act.get("title", ""))])
		lines.append("[i]此为原创戏剧收束；史实、争议与文学重建分属不同层次。[/i]")
	if not port_id.is_empty() and world.get("ports", {}).has(port_id):
		var entry: Dictionary = world.ports[port_id]
		var prices: Array = []
		for good: String in ["grain", "wood", "iron", "silk", "porcelain", "spices"]:
			var factor: float = float(entry.get("priceFactor", {}).get(good, 1.0))
			prices.append("%s %.1f" % [good, float(entry.prices[good]) * factor])
		var stored: Array = []
		for good: String in ["grain", "wood", "iron", "silk", "porcelain", "spices"]:
			var quantity: int = int(entry.get("warehouse", {}).get(good, 0))
			if quantity > 0:
				stored.append("%s %d" % [good, quantity])
		lines.append("行情：%s" % " ".join(prices))
		lines.append("仓栈：%s" % (" ".join(stored) if not stored.is_empty() else "空"))
		var intel: Array = []
		for remote_id: Variant in world.get("intel", {}):
			var report: Dictionary = world.intel[remote_id]
			intel.append("%s(%s)" % [str(remote_id), str(report.get("day", "?"))])
		if not intel.is_empty():
			lines.append("情报：%s" % " ".join(intel))
		var roster: Array = []
		for person: Dictionary in world.get("people", []):
			roster.append("%s·%s" % [str(person.get("name", person.get("id", ""))), str(person.get("role", ""))])
		if not roster.is_empty():
			lines.append("同伴：%s" % " ".join(roster))
		var wounded_total := 0
		for ship: Dictionary in world.get("fleet", []):
			wounded_total += int(ship.get("wounded", 0))
		if wounded_total > 0:
			lines.append("伤号：%d 人（港口疗伤或随医者康复）" % wounded_total)
		for key: Variant in _hero_buttons:
			(_hero_buttons[key] as Button).visible = false
		var signed: Array = []
		for person: Dictionary in world.get("people", []):
			signed.append(str(person.get("id", "")))
		for hero: Dictionary in Heroes.heroes_at(port_id, signed):
			var hero_button: Button = _hero_button(str(hero.id))
			if hero_button != null:
				hero_button.text = "邀%s入伙（%s·%d两）" % [str(hero.name), str(hero.role), int(hero.cost)]
				hero_button.visible = true
				hero_button.set_meta("hero", hero)
	_body.text = "\n".join(lines)
	_notice.text = str(packet.get("runtime", {}).get("notice", ""))
	var pending: Dictionary = scenario.get("transition", {})
	_transition.visible = not pending.is_empty() and str(progress.get("phase", "")) == "briefing"
	if _transition.visible:
		var meeting := ""
		if pending.has("meeting"):
			meeting = "\n%s" % str(pending.meeting)
		_transition_label.text = "转场 · %s年\n%s%s\n（点「章节转场」继续）" % [str(pending.get("yearMarker", "")), str(pending.get("note", "")), meeting]

func _charter_options(stage: Dictionary, scenario: Dictionary) -> Array:
	var found: Array = []
	for objective: Dictionary in stage.get("objectives", []):
		var settlement: Dictionary = scenario.get("settlements", {}).get(str(objective.id), {})
		if str(settlement.get("kind", "")) == "charter" and settlement.has("options"):
			for option: Dictionary in settlement.options:
				var entry: Dictionary = option.duplicate(true)
				entry.permitId = str(settlement.permitId)
				entry.scope = str(settlement.scope)
				entry.issuer = str(settlement.issuer)
				found.append(entry)
	return found

var _option_buttons: Dictionary = {}
var _hero_buttons: Dictionary = {}
var _ending_buttons: Dictionary = {}

func _ending_actions(stage: Dictionary, scenario: Dictionary) -> Array:
	# Ending-flow settlements (terms / evacuation / handover) get real controls
	# driven by the stage's own bindings — the three-gate finish is playable.
	var found: Array = []
	for objective: Dictionary in stage.get("objectives", []):
		var settlement: Dictionary = scenario.get("settlements", {}).get(str(objective.id), {})
		match str(settlement.get("kind", "")):
			"accept-terms":
				found.append({"id": "terms-" + str(objective.id), "label": "谈降签约", "intent": {"type": "sign-terms", "agreementId": str(settlement.agreementId), "terms": {"template": str(settlement.termsTemplate)}, "parties": ["player", "garrison"]}})
			"evacuation-complete":
				found.append({"id": "evacuate-" + str(objective.id), "label": "撤离装载 %d人" % int(settlement.people), "intent": {"type": "load-manifest", "manifestId": str(settlement.manifestId), "fromId": str(settlement.fromId), "people": int(settlement.people), "cargo": (settlement.cargo as Dictionary).duplicate(true), "ontoShipIds": _fleet_ids.duplicate(true), "overflow": "sell"}})
			"port-handover":
				found.append({"id": "handover-" + str(objective.id), "label": "接收设施", "intent": {"type": "handover-facilities", "handoverId": str(settlement.handoverId), "facilityId": str(settlement.facilityId), "portId": str(settlement.portId)}})
			"charter", "dispatch-returned", "withdraw", "recruit", "stockpile", "deliver", "capture", "escort-arrived", "arrive", "protect", "rescue", "neutralize", "land-control", "hold-blockade", "trade-profit", "handoff":
				pass
	return found

func _ending_button(id: String) -> Button:
	if _ending_buttons.has(id):
		return _ending_buttons[id]
	if find_child("HeroColumn", true, false) == null:
		return null
	var column: Node = find_child("HeroColumn", true, false)
	var button := Button.new()
	button.name = id
	button.visible = false
	column.add_child(button)
	button.pressed.connect(func() -> void: _send_ending(id))
	_ending_buttons[id] = button
	return button

func _send_ending(id: String) -> void:
	var button: Button = _ending_buttons.get(id)
	if button == null or not button.has_meta("ending"):
		return
	command_requested.emit((button.get_meta("ending") as Dictionary).intent)

func _hero_button(id: String) -> Button:
	if _hero_buttons.has(id):
		return _hero_buttons[id]
	if find_child("HeroColumn", true, false) == null:
		return null
	var column: Node = find_child("HeroColumn", true, false)
	var button := Button.new()
	button.name = id
	button.visible = false
	column.add_child(button)
	button.pressed.connect(func() -> void: _send_hero(id))
	_hero_buttons[id] = button
	return button

func _send_hero(id: String) -> void:
	var button: Button = _hero_buttons.get(id)
	if button == null or not button.has_meta("hero"):
		return
	var hero: Dictionary = button.get_meta("hero")
	command_requested.emit({"type": "sign-on", "personId": str(hero.id), "name": str(hero.name), "role": str(hero.role), "cost": int(hero.cost), "wage": int(hero.wage)})

func _option_button(id: String) -> Button:
	if _option_buttons.has(id):
		return _option_buttons[id]
	if find_child("OptionColumn", true, false) == null:
		return null
	var column: Node = find_child("OptionColumn", true, false)
	var button := Button.new()
	button.name = id
	button.visible = false
	column.add_child(button)
	button.pressed.connect(func() -> void: _send_option(id))
	_option_buttons[id] = button
	return button

func _send_option(id: String) -> void:
	var button: Button = _option_buttons.get(id)
	if button == null or not button.has_meta("charter"):
		return
	var option: Dictionary = button.get_meta("charter")
	command_requested.emit({"type": "sign-charter", "permitId": str(option.permitId), "scope": str(option.scope), "issuer": str(option.issuer), "cost": int(option.cost), "conditions": (option.conditions as Array).duplicate(true), "optionId": id})

func open_panel(_name: String) -> void:
	pass
