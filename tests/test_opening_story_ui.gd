extends SceneTree
## Real Control tree, plain-data projection and original guarded command boundary.
var assertions := 0
var failures := 0
var emitted: Array = []

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL opening story UI: ", message)

func _initialize() -> void:
	_run.call_deferred()

func _packet() -> Dictionary:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/mingqi-reference.json"))
	var state: Dictionary = fixture.initial.duplicate(true)
	state.captain.silver = 100
	return {"campaign": state, "naval": {"ships": []}, "runtime": {"generation": 71, "status": "ready", "controllableShipIds": [state.flagshipId], "eligibility": {"story": {"old-ledger": {"ok": true}, "pilot-plan": {"ok": true}, "first-return": {"ok": true}}, "repayDebt": {"ok": true}}}, "story": {
		"chapter": {"id": "opening", "title": "一本旧账，两艘船", "summary": "承家号是你继承的负债小船；明旗号是郑军借给你的护航船。先让老伙计愿意与你继续出海。"},
		"objective": {"id": "ledger", "title": "与账房核对欠薪", "detail": "在厦门听完陈账房的话，决定如何安顿船员。", "panel": "story"},
		"scenes": [
			{"id": "old-ledger", "title": "父辈留下的旧账", "npc": {"id": "chen", "name": "陈账房", "role": "守账多年"}, "text": ["账册最后一页写着老船员的名字。欠银要还，人情更不能忘。", "先把话说清楚，再定这趟航程。"], "status": "available", "selectedChoiceId": "", "reply": "", "choices": [
				{"id": "settle-wages", "label": "先结清拖欠的工钱", "consequence": "支出80两，船员安心；留下的周转银减少。", "silverCost": 80, "enabled": true, "reason": ""},
				{"id": "keep-reserve", "label": "先保留周转银", "consequence": "不支出银两，船员会记住你的承诺。", "silverCost": 0, "enabled": true, "reason": ""}]},
			{"id": "pilot-plan", "title": "浅滩与领航员", "npc": {"id": "lin", "name": "林领航", "role": "熟悉湾口"}, "text": ["先处理旧账，再商议航路。", "不该提前展示的长篇未来对白。"], "status": "locked", "selectedChoiceId": "", "reply": "", "choices": [{"id": "hire-pilot", "label": "雇领航员", "consequence": "45两", "silverCost": 45, "enabled": false, "reason": "先核对旧账"}]}],
		"relations": [{"id": "old-crew", "name": "吴老舵", "role": "老水手", "stance": "他愿意再陪你跑一趟，但盼着你的承诺能够兑现。"}],
		"history": [{"id": "opening", "sceneId": "", "choiceId": "", "message": "在厦门接过父亲留下的旧账册。", "simTime": 0}],
		"debt": {"principal": 240, "creditorName": "陈账房", "canRepay": true, "reason": ""}}}

func _run() -> void:
	var Interface = load("res://game/ui/mingqi/mingqi_interface.gd")
	if not Interface or not Interface.can_instantiate():
		check(false, "interface parses before Control tree test")
		_finish()
		return
	var ui = Interface.new()
	root.add_child(ui)
	await process_frame
	ui.command_requested.connect(func(intent): emitted.append(intent))
	var packet := _packet()
	var untouched := packet.duplicate(true)
	ui.apply_snapshot(packet)
	var nav = ui.find_child("nav_story", true, false)
	check(nav is Button, "story navigation exists")
	if not nav is Button:
		ui.free()
		_finish()
		return
	check(nav.text == "航海日志", "journal navigation label")
	ui.open_panel("story")
	packet.story.scenes[0].choices[0].label = "先结清拖欠的工钱 · 80两"
	packet.story.scenes[0].choices[1].consequence = "保留应急周转银，船员拥护+-4。"
	ui.apply_snapshot(packet)
	var cost_text: String = ui.find_child("story_choice_effect_old-ledger_settle-wages", true, false).text.split("\n")[0]
	check(cost_text.count("80两") == 1, "cost already present in supplied label is shown once")
	check(ui.find_child("story_choice_effect_old-ledger_keep-reserve", true, false).text.contains("拥护-4") and not ui.find_child("story_choice_effect_old-ledger_keep-reserve", true, false).text.contains("+-"), "negative emergency consequence uses readable sign")
	check(ui.get("_packet").story.scenes[0].choices[1].consequence.contains("+-4"), "presentation sign formatting never edits domain projection")
	untouched = packet.duplicate(true)
	check(ui.find_child("panel_story", true, false).visible, "journal is an actual operation panel")
	check(ui.find_child("story_chapter", true, false).text == packet.story.chapter.title, "chapter is projection text")
	check(ui.find_child("story_premise", true, false).text.contains("承家号") and ui.find_child("story_premise", true, false).text.contains("明旗号"), "owned/borrowed ships are distinguished by supplied premise")
	var objective = ui.find_child("current_objective", true, false)
	check(objective is Label and objective.visible and objective.text.contains("核对欠薪"), "one visible current objective in HUD")
	var link = ui.find_child("objective_open", true, false)
	check(link is Button and not link.disabled, "objective has existing target-panel link")
	ui.open_panel("port")
	var count := emitted.size()
	link.pressed.emit()
	check(ui.find_child("panel_story", true, false).visible and emitted.size() == count, "objective only opens a panel")
	var choice = ui.find_child("story_choice_old-ledger_settle-wages", true, false)
	check(choice is Button and not choice.disabled, "affordable, available, native-eligible choice")
	choice.pressed.emit()
	check(emitted.size() == count + 1 and emitted.back().type == "story-choice" and emitted.back().sceneId == "old-ledger" and emitted.back().choiceId == "settle-wages", "real choice intent")
	check(emitted.back().expectedRevision == packet.campaign.revision and str(emitted.back().commandId).begins_with("ui:"), "choice uses canonical revision and commandId")
	check(packet == untouched and ui.get("_packet") == untouched, "choice emits intent without mutating source or copied campaign")
	choice.pressed.emit()
	check(emitted.size() == count + 1, "duplicate choice callback suppressed")
	check(ui.find_child("story_choice_pilot-plan_hire-pilot", true, false) == null, "locked scene has no actionable choice")
	check(not ui.find_child("story_locked_pilot-plan", true, false).text.contains("未来对白"), "locked scene shows prerequisite without future dialogue")
	packet.campaign.captain.silver = 40
	ui.apply_snapshot(packet)
	check(ui.find_child("story_choice_old-ledger_settle-wages", true, false).disabled, "actual affordability also guarded")
	packet.campaign.captain.silver = 100
	packet.runtime.eligibility.story["old-ledger"] = {"ok": false, "reason": "unsafe-port"}
	ui.apply_snapshot(packet)
	choice = ui.find_child("story_choice_old-ledger_keep-reserve", true, false)
	check(choice.disabled and ui.find_child("story_native_old-ledger", true, false).text.contains("停稳"), "native dock refusal overrides zero-cost choice with readable reason")
	count = emitted.size()
	choice.pressed.emit()
	check(emitted.size() == count, "disabled native callback cannot bypass guard")
	packet.runtime.eligibility.story["old-ledger"] = {"ok": true}
	packet.story.scenes[0].choices[0].enabled = false
	packet.story.scenes[0].choices[0].reason = "这笔欠薪已经核实，另一个决定正在处理。"
	ui.apply_snapshot(packet)
	check(ui.find_child("story_choice_old-ledger_settle-wages", true, false).disabled, "domain choice gate also required")
	packet.story.scenes[0].choices[0].enabled = true
	ui.apply_snapshot(packet)
	var quantity = ui.find_child("debt_quantity", true, false)
	check(quantity is SpinBox and quantity.max_value == 100, "debt form constrained by current purse and principal")
	quantity.value = 25
	var repay = ui.find_child("repay_debt", true, false)
	check(not repay.disabled, "actual model and native debt eligibility")
	repay.pressed.emit()
	check(emitted.back().type == "repay-debt" and emitted.back().quantity == 25 and emitted.back().expectedRevision == packet.campaign.revision, "repayment is canonical positive integer intent")
	packet.story.debt.canRepay = false
	packet.story.debt.reason = ""
	ui.apply_snapshot(packet)
	check(ui.find_child("repay_debt", true, false).disabled, "false debt eligibility cannot be enabled by an empty reason")
	packet.story.debt.canRepay = true
	packet.runtime.eligibility.repayDebt = {"ok": false, "reason": ""}
	ui.apply_snapshot(packet)
	check(ui.find_child("repay_debt", true, false).disabled, "false native eligibility cannot be enabled by an empty reason")
	packet.runtime.eligibility.repayDebt = {"ok": false, "reason": "not-in-port"}
	ui.apply_snapshot(packet)
	check(ui.find_child("repay_debt", true, false).disabled and ui.find_child("repay_debt_reason", true, false).text.contains("靠泊"), "native debt gate has readable reason")
	packet.runtime.eligibility.repayDebt = {"ok": true}
	ui.apply_snapshot(packet)
	quantity = ui.find_child("debt_quantity", true, false)
	quantity.get_line_edit().grab_focus()
	await process_frame
	quantity.get_line_edit().text = "7"
	check(ui.captures_keyboard(), "repay editor captures sailing keys")
	for draft in ["2.5", "0", "101", "-2", "abc"]:
		quantity.get_line_edit().text = draft
		quantity.get_line_edit().text_changed.emit(draft)
		check(ui.find_child("repay_debt", true, false).disabled, "invalid/out-of-limit draft rejected: " + draft)
	quantity.get_line_edit().text = "7"
	packet.story.debt.canRepay = false
	packet.story.debt.reason = "账房正在核实这笔债务，稍候再付款。"
	ui.apply_snapshot(packet)
	check(ui.find_child("repay_debt", true, false).disabled and ui.find_child("repay_debt_reason", true, false).text.contains("核实"), "projection debt gate required alongside native approval")
	packet.story.debt.canRepay = true
	packet.story.debt.reason = ""
	ui.apply_snapshot(packet)
	var before = quantity
	packet.campaign.simulationSeconds += 0.1
	packet.story.history[0].simTime += 0.1
	ui.apply_snapshot(packet)
	check(ui.find_child("debt_quantity", true, false) == before and quantity.get_line_edit().text == "7" and quantity.get_line_edit().has_focus(), "clock tick keeps editor node, draft and focus")
	var stale_callback: Callable = ui.find_child("story_choice_old-ledger_keep-reserve", true, false).pressed.get_connections()[0].callable
	packet.story.scenes[0].choices[0].enabled = false
	ui.apply_snapshot(packet)
	await process_frame
	quantity = ui.find_child("debt_quantity", true, false)
	check(quantity.get_line_edit().text == "7" and quantity.get_line_edit().has_focus(), "meaningful choice-gate remount restores focused draft")
	count = emitted.size()
	stale_callback.call()
	check(emitted.size() == count, "same-generation stale remounted callback rejected")
	packet.story.scenes[0].status = "completed"
	packet.story.scenes[0].selectedChoiceId = "keep-reserve"
	packet.story.scenes[0].reply = "吴老舵收好账册，说他会等你带着第一趟收益回来。"
	packet.story.objective = {"id": "pilot", "title": "与领航员商议路线", "detail": "靠港后决定是否雇用领航员。", "panel": "convoy"}
	ui.apply_snapshot(packet)
	check(ui.find_child("story_outcome_old-ledger", true, false).text.contains("吴老舵"), "completed choice outcome refreshes")
	check(ui.find_child("story_choice_old-ledger_keep-reserve", true, false) == null, "completed choice cannot repeat")
	ui.find_child("objective_open", true, false).pressed.emit()
	check(ui.find_child("panel_convoy", true, false).visible, "new objective links to existing convoy panel")
	ui.open_panel("story")
	packet.story.debt.principal = 0
	ui.apply_snapshot(packet)
	check(ui.find_child("story_debt", true, false).text.contains("已还清"), "full debt has factual completed label")
	check(not ui.find_child("debt_quantity", true, false).editable and ui.find_child("repay_debt", true, false).disabled, "paid debt disables editor and command")
	var old = ui.find_child("objective_open", true, false)
	packet.runtime.generation += 1
	ui.apply_snapshot(packet)
	ui.open_panel("story")
	old.pressed.emit()
	check(ui.find_child("panel_story", true, false).visible, "old-generation navigation callback rejected")
	packet = _packet()
	packet.runtime.generation = 72
	packet.runtime.status = "disposed"
	ui.apply_snapshot(packet)
	check(ui.find_child("story_choice_old-ledger_keep-reserve", true, false).disabled and ui.find_child("repay_debt", true, false).disabled, "disposed runtime rejects story/debt")
	for status in ["loading", "error"]:
		packet.runtime.status = status
		ui.apply_snapshot(packet)
		check(ui.find_child("story_choice_old-ledger_keep-reserve", true, false).disabled, status + " runtime rejects story")
	check(untouched.campaign == _packet().campaign, "fixture campaign never mutated by UI")
	packet = _packet()
	packet.runtime.generation = 73
	packet.story.scenes[0].text = []
	for i in 25:
		packet.story.scenes[0].text.append("码头边的人记得你父亲每一次兑现承诺，也记得每一次拖欠。".repeat(5))
	ui.apply_snapshot(packet)
	ui.open_panel("story")
	for size in [Vector2i(1280, 720), Vector2i(1600, 900)]:
		root.size = size
		root.content_scale_size = Vector2i.ZERO
		for frame in 8:
			await process_frame
		var operation = ui.find_child("operation", true, false)
		var scroll = ui.find_child("operation_scroll", true, false)
		check(operation.position.y + operation.size.y <= size.y - 17 and operation.position.x + operation.size.x <= size.x - 17, "journal stays within viewport " + str(size))
		check(scroll is ScrollContainer and scroll.get_v_scroll_bar().max_value > scroll.size.y, "long original NPC dialogue scrolls " + str(size))
		check(scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "journal wraps rather than horizontal scroll")
	packet.erase("story")
	ui.apply_snapshot(packet)
	ui.open_panel("story")
	check(ui.find_child("story_fallback", true, false) is Label, "old packet has usable no-story fallback")
	check(not ui.find_child("current_objective", true, false).is_visible_in_tree(), "absent-story HUD does not invent an objective")
	ui.open_panel("port")
	check(ui.find_child("panel_port", true, false).visible, "old trade panel preserved")
	packet = _packet()
	packet.runtime.generation = 74
	packet.story.scenes[1].status = "available"
	packet.story.scenes[1].choices[0].enabled = true
	ui.apply_snapshot(packet)
	ui.open_panel("story")
	count = emitted.size()
	ui.find_child("story_choice_pilot-plan_hire-pilot", true, false).pressed.emit()
	check(emitted.size() == count + 1 and emitted.back().sceneId == "pilot-plan" and emitted.back().choiceId == "hire-pilot", "independent second scene captures its own IDs")
	ui.find_child("story_choice_old-ledger_keep-reserve", true, false).pressed.emit()
	check(emitted.back().sceneId == "old-ledger" and emitted.back().choiceId == "keep-reserve", "each choice closure retains the canonical choice ID")
	ui.free()
	await process_frame
	_finish()

func _finish() -> void:
	print("OPENING_STORY_UI_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
