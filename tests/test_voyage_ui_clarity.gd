extends SceneTree
## Actual Control labels consume snapshots; fixed deadlines must count down as clock advances.
var assertions := 0
var failures := 0
const Campaign = preload("res://game/domain/mingqi/campaign.gd")
const Runtime = preload("res://game/runtime/mingqi_runtime.gd")

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL voyage UI clarity: ", message)

func _initialize() -> void:
	_run.call_deferred()

func _delayed_acceptance(seconds: float, timing: String) -> void:
	var campaign := Campaign.new()
	check(campaign.advance(seconds).ok, "real campaign advances before acceptance at " + str(seconds))
	var runtime := Runtime.new()
	check(runtime.configure(func(_x: float, _z: float) -> float: return -24.0, campaign).ok, "delayed campaign configures real runtime")
	var ui = load("res://game/ui/mingqi/mingqi_interface.gd").new()
	root.add_child(ui)
	await process_frame
	var results: Array = []
	ui.command_requested.connect(func(intent: Dictionary):
		results.append(runtime.command(intent))
		ui.apply_snapshot(runtime.snapshot()))
	ui.apply_snapshot(runtime.snapshot())
	ui.open_panel("convoy")
	var label: String = ui.find_child("contract_convoy-001", true, false).text
	check(label.contains("接单前也计时") and label.contains(timing), "first offered deadline remains visible before delayed acceptance at " + str(seconds))
	var accept = ui.find_child("contract_accept_convoy-001", true, false)
	check(not accept.disabled, "existing delayed acceptance remains available")
	accept.pressed.emit()
	check(results.size() == 1 and results[0].ok, "actual UI to runtime delayed acceptance succeeds")
	check(runtime.snapshot().campaign.contracts["convoy-001"].deadlineAt == 1800, "delayed acceptance preserves actual first deadline")
	check(ui.find_child("contract_convoy-001", true, false).text.contains(timing), "accepted first contract preserves same remaining or overdue timing")
	ui.free()
	runtime.dispose()
	await process_frame

func _run() -> void:
	await _delayed_acceptance(1000, "剩余 800秒")
	await _delayed_acceptance(1900, "逾期 100秒")
	var ui = load("res://game/ui/mingqi/mingqi_interface.gd").new()
	root.add_child(ui)
	await process_frame
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/mingqi-reference.json"))
	var state: Dictionary = fixture.initial.duplicate(true)
	var packet := {"campaign": state, "naval": {"ships": []}, "runtime": {"generation": 91, "status": "ready", "canDepart": false, "departReason": "unsafe-port", "eligibility": {"repayDebt": {"ok": false, "reason": "not-in-port"}}}, "story": {"debt": {"principal": 240, "creditorName": "林家商行", "canRepay": false, "reason": "not-in-port"}}}
	state.currentPortId = "kinmen"
	ui.apply_snapshot(packet)
	ui.open_panel("story")
	check(ui.find_child("repay_debt_reason", true, false).text.contains("厦门林家商行"), "anchored Kinmen debt refusal identifies the actual creditor port")
	check(ui.find_child("repay_debt", true, false).disabled, "wrong-port copy keeps repayment disabled")
	state.currentPortId = "xiamen"
	packet.story.debt.canRepay = true
	packet.story.debt.reason = ""
	packet.runtime.eligibility.repayDebt = {"ok": false, "reason": "unsafe-port"}
	ui.apply_snapshot(packet)
	check(ui.find_child("repay_debt_reason", true, false).text.contains("停稳") and ui.find_child("repay_debt", true, false).disabled, "unsafe Xiamen retains real safety refusal")
	packet.runtime.eligibility.repayDebt = {"ok": false, "reason": "not-in-port"}
	ui.apply_snapshot(packet)
	check(ui.find_child("repay_debt_reason", true, false).text.contains("厦门林家商行"), "native wrong-port debt reason identifies Xiamen too")
	var contract: Dictionary = state.contracts["convoy-001"]
	var voyage_id: String = contract.voyageIds[0]
	var voyage: Dictionary = state.voyages[voyage_id]
	contract.deadlineAt = 0
	ui.apply_snapshot(packet)
	ui.open_panel("convoy")
	check(ui.find_child("contract_convoy-001", true, false).text.contains("接单后开始计时"), "offered zero deadline is acceptance timing rather than expiry")
	check(not ui.find_child("voyage_" + voyage_id, true, false).text.contains("预计"), "loading voyage never shows stale ETA")
	check(ui.find_child("voyage_" + voyage_id, true, false).text.contains("接下委托"), "offered loading voyage identifies acceptance prerequisite")
	contract.status = "active"
	contract.deadlineAt = 1800
	voyage.status = "underway"
	voyage.eta = 1800
	state.simulationSeconds = 1500
	ui.apply_snapshot(packet)
	check(ui.find_child("contract_convoy-001", true, false).text.contains("剩余 300秒"), "active contract displays remaining deadline")
	check(ui.find_child("voyage_" + voyage_id, true, false).text.contains("预计还需 300秒"), "underway ETA is relative to campaign time")
	var before = ui.find_child("contract_convoy-001", true, false)
	state.simulationSeconds = 1600
	ui.apply_snapshot(packet)
	check(ui.find_child("contract_convoy-001", true, false) == before and before.text.contains("剩余 200秒"), "clock advance refreshes same contract label without stale duration")
	check(ui.find_child("voyage_" + voyage_id, true, false).text.contains("预计还需 200秒"), "clock advance refreshes voyage countdown")
	state.simulationSeconds = 1900
	ui.apply_snapshot(packet)
	check(before.text.contains("逾期 100秒"), "expired active contract shows actual overdue duration")
	check(ui.find_child("voyage_" + voyage_id, true, false).text.contains("尚未抵达"), "passed ETA never asserts arrival")
	voyage.status = "loading"
	ui.apply_snapshot(packet)
	check(ui.find_child("voyage_" + voyage_id, true, false).text.contains("停稳") and not ui.find_child("voyage_" + voyage_id, true, false).text.contains("已核验"), "loading voyage reports failed runtime preparation")
	packet.runtime.canDepart = true
	ui.apply_snapshot(packet)
	check(ui.find_child("voyage_" + voyage_id, true, false).text.contains("已核验"), "loading readiness uses actual runtime departure approval")
	packet.runtime.status = "loading"
	ui.apply_snapshot(packet)
	check(not ui.find_child("voyage_" + voyage_id, true, false).text.contains("已核验"), "unavailable runtime cannot promise departure readiness")
	packet.runtime.status = "ready"
	for status in ["arrived", "lost", "interrupted"]:
		voyage.status = status
		ui.apply_snapshot(packet)
		var label: String = ui.find_child("voyage_" + voyage_id, true, false).text
		check(not label.contains("预计") and not label.contains("航段"), status + " displays outcome rather than stale travel forecast")
	for status in ["delivered", "failed", "settled"]:
		contract.status = status
		ui.apply_snapshot(packet)
		var label: String = ui.find_child("contract_convoy-001", true, false).text
		check(not label.contains("逾期") and not label.contains("剩余") and not label.contains("期限"), status + " keeps recorded outcome without misleading deadline")
	var source := packet.duplicate(true)
	ui.apply_snapshot(packet)
	check(packet == source and ui.get("_packet") == source, "presenters never rewrite campaign deadlines or voyage outcomes")
	ui.free()
	await process_frame
	print("VOYAGE_UI_CLARITY_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
