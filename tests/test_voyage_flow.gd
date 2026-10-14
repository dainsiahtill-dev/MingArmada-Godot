extends SceneTree
const Campaign = preload("res://game/domain/mingqi/campaign.gd")
const Runtime = preload("res://game/runtime/mingqi_runtime.gd")
var assertions := 0
var failures := 0
var Flow: Script

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL voyage flow: ", message)

func command(runtime, type: String, extra: Dictionary = {}) -> Dictionary:
	var state: Dictionary = runtime.campaign.snapshot()
	var intent := {"type": type, "commandId": "flow-" + str(state.revision), "expectedRevision": state.revision}
	intent.merge(extra)
	return runtime.command(intent)

func _initialize() -> void:
	check(ResourceLoader.exists("res://game/domain/mingqi/voyage_flow.gd"), "receipt-derived voyage flow projection exists")
	if failures:
		finish()
		return
	Flow = load("res://game/domain/mingqi/voyage_flow.gd")
	var runtime := Runtime.new()
	check(runtime.configure(func(_x: float, _z: float) -> float: return -24.0).ok, "real runtime starts")
	var state: Dictionary = runtime.campaign.snapshot()
	var before := var_to_bytes(state)
	var initial: Dictionary = Flow.project(state)
	check(initial.active.contractId == "convoy-001" and initial.active.stage == "offered", "first offer is active flow")
	check(initial.active.remainingSeconds == 1800 and initial.active.deadlineMode == "remaining", "first clock already runs before acceptance")
	check(initial.branches.is_empty() and initial.settlements.is_empty(), "no invented choices or rewards")
	check(initial.upgrade.shipId == state.campaignId + "-heritage" and initial.upgrade.portId == "xiamen", "upgrade points to actual own ship and authorized port")
	check(var_to_bytes(state) == before, "projection never mutates authority")
	check(command(runtime, "story-choice", {"sceneId": "old-ledger", "choiceId": "settle-wages"}).ok, "wages use real command")
	var paid: Dictionary = Flow.project(runtime.campaign.snapshot())
	check(paid.branches.size() == 1 and paid.branches[0].silverCost == 80 and paid.branches[0].choiceId == "settle-wages", "actual branch cost remains visible")
	check(command(runtime, "accept-convoy").ok, "real convoy accepted")
	check(Flow.project(runtime.campaign.snapshot()).active.stage == "loading", "loading is distinct from sailing")
	check(command(runtime, "story-choice", {"sceneId": "pilot-plan", "choiceId": "stay-deep"}).ok, "free route choice stays playable")
	check(command(runtime, "depart").ok, "real departure")
	check(Flow.project(runtime.campaign.snapshot()).active.stage == "underway", "departure updates stage without extra state")
	runtime.dispose()
	# Pure projection counterexamples only: these are not voyage completion evidence.
	state.simulationSeconds = 1801.2
	var late: Dictionary = Flow.project(state)
	check(late.active.deadlineMode == "overdue" and late.active.remainingSeconds == 0 and is_equal_approx(late.active.overdueSeconds, 1.2), "overdue separates duration from remaining time")
	state.contracts["convoy-001"].status = "settled"
	state.contracts["convoy-001"].receiptId = state.campaignId + ":convoy-001:claim"
	check(Flow.project(state).settlements.is_empty(), "terminal status alone cannot manufacture payment")
	var receipt := {"id": state.contracts["convoy-001"].receiptId, "kind": "claim-convoy", "details": {"kind": "convoy", "contractId": "convoy-001", "delivered": 20, "lost": 20, "baseReward": 200, "bonus": 0, "leasePaid": 50, "ships": [{"dead": 2, "wounded": 3}]}}
	state.settlements[receipt.id] = receipt
	var partial: Dictionary = Flow.project(state)
	check(partial.settlements.size() == 1 and partial.settlements[0].delivered == 20 and partial.settlements[0].lost == 20, "partial delivery and loss retained")
	check(partial.settlements[0].paid == 200 and partial.settlements[0].dead == 2 and partial.settlements[0].wounded == 3, "receipt income and casualties retained exactly")
	check(partial.active.deadlineMode == "closed", "settled receipt has no live countdown")
	state.settlements[receipt.id].details.contractId = "other"
	check(Flow.project(state).settlements.is_empty(), "wrong-contract receipt excluded")
	state.vessels[state.campaignId + "-heritage"].damage.hull = 0
	check(Flow.project(state).upgrade.is_empty(), "sunk own ship never suggested for upgrade")
	finish()

func finish() -> void:
	print("VOYAGE_FLOW_PASS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
