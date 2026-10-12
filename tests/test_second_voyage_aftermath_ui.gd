extends SceneTree
## Presentation fixtures are constructed; real Runtime/receipt checks are separate below.
const Interface = preload("res://game/ui/mingqi/mingqi_interface.gd")
var assertions := 0
var failures := 0

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL second aftermath UI: ", message)

func _initialize() -> void:
	_run.call_deferred()

func _packet() -> Dictionary:
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/mingqi-reference.json"))
	var state: Dictionary = fixtures.initial.duplicate(true)
	state.captain.silver = 1165
	var bill := {"delivered":20,"lost":0,"baseReward":200,"bonus":50,"revenue":250,"silver":1165,"principal":400,"dividend":50,"remainingSilver":1115,"supportBefore":50,"supportAward":4,"supportAfter":54,"supportDelta":4,"beneficiaryCount":8,"verifiedDeaths":0,"currentWounded":2,"scopeNote":"本次仅含已核验承运船；护卫伤亡未列入本账。","exclusions":[]}
	var scene := {"id":"second-return","title":"第二趟交差：钱先给谁","npc":{"id":"aftermath-ledger","name":"交差账单","role":"船上账册"},"text":["这趟实交20粮，实收250两；现银1165两，旧债400两。","在厦门还债、给已核验随航船员分两成，或先留船本，这笔钱由你安排。"],"status":"available","selectedChoiceId":"","reply":"","bill":bill,"choices":[{"id":"return-xiamen","label":"在厦门偿债","consequence":"只记目标，实际付款仍由你决定。","silverCost":0,"enabled":true,"reason":""},{"id":"share-proceeds","label":"分给已核验随航船员 · 50两","consequence":"支出50两，拥护实际+4。","silverCost":50,"enabled":true,"reason":""},{"id":"keep-capital","label":"留作船本","consequence":"保留周转银，关系不变。","silverCost":0,"enabled":true,"reason":""}]}
	return {"campaign":state,"naval":{"ships":[]},"runtime":{"generation":991,"status":"ready","controllableShipIds":[state.flagshipId],"eligibility":{"story":{"old-ledger":{"ok":true},"second-return":{"ok":true}},"repayDebt":{"ok":true}}},"story":{"chapter":{"id":"opening-1650","title":"旧账新帆","summary":"两趟交差之后，决定怎样养船养人。"},"objective":{"id":"second-return-choice","title":"钱先给谁","detail":"先核账，再作安排。","panel":"story"},"scenes":[{"id":"old-ledger","title":"旧账与工钱","npc":{"name":"许福","role":"老水手"},"status":"completed","selectedChoiceId":"keep-reserve","reply":"留下周转银。","text":[],"choices":[]},scene],"relations":[],"history":[],"debt":{"principal":400,"creditorName":"林家商行","canRepay":true,"reason":""}}}

func _run() -> void:
	var ui = Interface.new()
	root.add_child(ui)
	await process_frame
	var packet := _packet()
	var original := packet.duplicate(true)
	ui.apply_snapshot(packet)
	ui.open_panel("story")
	await process_frame
	var bill = ui.find_child("story_bill_second-return", true, false)
	check(bill is Label, "new compact bill appears above actual choices")
	if bill is Label:
		for required in ["实交20粮","基础200两","奖金50两","实收250两","现银1165两","欠款400两","分红50两","余银1115两","现有拥护50","分红后54","拥护+4","当前伤员2人","8人","护卫伤亡未列入本账"]:
			check(bill.text.contains(required), "bill displays actual projected fact " + required)
	var old = ui.find_child("story_scene_old-ledger", true, false)
	var current = ui.find_child("story_scene_second-return", true, false)
	check(old != null and current != null and current.get_index() < old.get_index(), "current choice precedes completed history without deleting it")
	check(packet == original, "presentation never edits domain projection")
	var button = ui.find_child("story_choice_second-return_share-proceeds", true, false)
	check(button is Button and not button.disabled, "real share Control is actionable with both gates")
	packet.story.scenes[1].bill.silver = 857
	packet.story.scenes[1].bill.remainingSilver = 807
	packet.story.scenes[1].bill.supportDelta = 2
	packet.story.scenes[1].bill.supportBefore = 98
	packet.story.scenes[1].bill.supportAfter = 100
	packet.story.scenes[1].bill.exclusions = ["乙粮船人员曾跨船调动，本航受益人数暂不能核清。"]
	ui.apply_snapshot(packet)
	bill = ui.find_child("story_bill_second-return", true, false)
	check(bill is Label and bill.text.contains("现银857两") and bill.text.contains("余银807两") and bill.text.contains("现有拥护98") and bill.text.contains("分红后100") and bill.text.contains("拥护+2"), "bill refreshes live cash and actual capped gain")
	check(bill is Label and bill.text.contains("乙粮船人员曾跨船调动"), "actual bill names carrier excluded from verified payment")
	packet.runtime.eligibility.story["second-return"] = {"ok":false,"reason":"not-in-story-port"}
	ui.apply_snapshot(packet)
	button = ui.find_child("story_choice_second-return_share-proceeds", true, false)
	var reason = ui.find_child("story_choice_reason_second-return_share-proceeds", true, false)
	check(button is Button and button.disabled, "real native eligibility rejects at sea")
	check(reason is Label and reason.text.contains("厦门") and reason.text.contains("金门") and reason.text.contains("补给点"), "visible reason names three valid safe ports")
	packet.runtime.eligibility.story["second-return"] = {"ok":true}
	packet.story.scenes[1].choices[1].enabled = false
	packet.story.scenes[1].choices[1].reason = "unexplained-crew-support"
	ui.apply_snapshot(packet)
	reason = ui.find_child("story_choice_reason_second-return_share-proceeds", true, false)
	check(reason is Label and reason.text.contains("拥护来源") and reason.text.contains("留作船本"), "legacy unexplained support refusal keeps the other choices clear")
	packet.story.scenes[1].status = "completed"
	packet.story.scenes[1].selectedChoiceId = "share-proceeds"
	packet.story.scenes[1].reply = "实付50两，8人受益，船员拥护实际+4。"
	packet.story.scenes[1].bill.silver = 1115
	ui.apply_snapshot(packet)
	bill = ui.find_child("story_bill_second-return", true, false)
	check(bill is Label and bill.text.contains("现银1115两") and not bill.text.contains("支付后"), "completed bill shows live balance without proposing the same deduction again")
	var outcome = ui.find_child("story_outcome_second-return", true, false)
	check(outcome is Label and outcome.text.contains("实付50两"), "completed receipt keeps actual historical payment")
	check(ui.find_child("story_choice_second-return_share-proceeds", true, false) == null, "completed decision cannot be paid again through UI")
	ui.free()
	await process_frame
	await _real_controls()
	print("SECOND_VOYAGE_AFTERMATH_UI_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)

func _real_controls() -> void:
	# Formally generated domain fixtures and real native bridges; not voyage proof.
	var Factory = load("res://tests/test_second_voyage_aftermath_runtime.gd")
	var Codec = load("res://game/domain/persistence/save_codec.gd")
	for port: String in ["xiamen", "kinmen", "forward-supply"]:
		for choice: String in ["return-xiamen", "share-proceeds", "keep-capital"]:
			var made: Dictionary = Factory.at_port(port)
			check(made.get("ok", false), "constructed lawful claim plus actual native safe port " + port)
			if not made.get("ok", false): continue
			var runtime = made.runtime
			var ui = Interface.new()
			root.add_child(ui)
			await process_frame
			var commands: Array = []
			var results: Array = []
			ui.command_requested.connect(func(intent: Dictionary):
				commands.append(intent.duplicate(true))
				results.append(runtime.command(intent))
				ui.apply_snapshot(runtime.snapshot()))
			ui.apply_snapshot(runtime.snapshot())
			ui.open_panel("story")
			var before: Dictionary = runtime.snapshot().campaign
			var control = ui.find_child("story_choice_second-return_" + choice, true, false)
			check(control is Button and not control.disabled, "actual enabled branch Control " + port + ":" + choice)
			if control is Button and not control.disabled: control.pressed.emit()
			check(results.size() == 1 and results[0].ok, "Control crosses real Runtime/Campaign branch " + choice)
			if commands.size() == 1:
				check(Codec.command_data(commands[0]) and not commands[0].has("portId") and not commands[0].has("portWitness") and not commands[0].has("native"), "UI sends pure guarded command, never its own native witness")
			var after: Dictionary = runtime.snapshot().campaign
			var receipt: Dictionary = after.settlements.get(after.campaignId + ":story:second-return", {})
			check(receipt.get("details", {}).get("choiceId") == choice and receipt.get("details", {}).get("portId") == port, "real receipt records chosen branch and observed actual port")
			check(after.captain.silver == before.captain.silver - (50 if choice == "share-proceeds" else 0), "actual branch payment is derived from earned250")
			check(after.debt == before.debt and after.ports == before.ports, "decision alone neither pays debt nor changes port stocks")
			check(ui.find_child("story_choice_second-return_" + choice, true, false) == null, "committed branch removes repeat-payment control")
			var encoded: String = Codec.encode(after)
			check(not encoded.is_empty() and Codec.decode(encoded).ok, "actual UI branch survives strict V2 codec")
			if choice == "return-xiamen" and port == "xiamen":
				ui.find_child("debt_quantity", true, false).value = 100
				control = ui.find_child("repay_debt", true, false)
				check(control is Button and not control.disabled, "actual debt action available at home immediately")
				if control is Button and not control.disabled: control.pressed.emit()
				var paid: Dictionary = runtime.snapshot().campaign
				check(paid.debt.principal == 300 and paid.captain.silver == after.captain.silver - 100, "only separate actual repay Control deducts100")
				check(paid.reputations.merchantCredit == after.reputations.merchantCredit, "partial payment does not prematurely grant cleared-debt credit")
			ui.free()
			runtime.dispose()
			await process_frame
