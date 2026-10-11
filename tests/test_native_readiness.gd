extends SceneTree
const Runtime = preload("res://game/runtime/mingqi_runtime.gd")
const Campaign = preload("res://game/domain/mingqi/campaign.gd")
var failures := 0
var assertions := 0
func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ",detail)
func make_runtime(state: Dictionary) -> RefCounted:
	var session := Campaign.new(); session._state = state.duplicate(true)
	var runtime := Runtime.new()
	check(runtime.configure(func(_x: float,_z: float)->float: return -24.0,session).ok,"actual native authority builds source state")
	return runtime
func fact(runtime: RefCounted,key: String) -> bool: return runtime.snapshot().runtime.eligibility.get(key,{}).get("ok",false)
func _initialize() -> void:
	var f: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/mingqi-reference.json"))
	var opening := Runtime.new(); opening.configure(func(_x: float,_z: float)->float: return -24.0)
	check(not opening.snapshot().runtime.canDepart,"borrowed opening flagship cannot depart before authorization")
	check(not fact(opening,"repair:"+opening.snapshot().campaign.flagshipId),"uncontrolled borrowed hull has no service authority")
	opening.dispose()
	var care := make_runtime(f.careInitial)
	check(fact(care,"release-prisoners:care-heritage"),"ordinary owned berth can release prisoners without a prize")
	var result: Dictionary = care.command({"type":"release-prisoners","shipId":"care-heritage","commandId":"readiness-care","expectedRevision":care.snapshot().campaign.revision})
	check(result.ok,"enabled prisoner release executes through actual native fence")
	care.dispose()
	var held := make_runtime(f.heldInitial)
	check(fact(held,"take-prize-cargo:business-enemy:business-flagship"),"actual held prize exposes cargo transfer")
	check(fact(held,"resolve-prize:business-enemy"),"held prize can be released without a receiving ship")
	result = held.command({"type":"take-prize-cargo","targetId":"business-enemy","toShipId":"business-flagship","cargo":{"grain":3},"commandId":"readiness-cargo","expectedRevision":held.snapshot().campaign.revision})
	check(result.ok,"native enabled cargo transfer executes")
	held.dispose()
	var allocation := make_runtime(f.saleSteps[7].state)
	check(fact(allocation,"allocate-prize:sale-flagship:sale-enemy"),"actual captured encounter exposes prize crew allocation")
	result = allocation.command({"type":"allocate-prize","targetId":"sale-enemy","fromShipId":"sale-flagship","crew":12,"commandId":"readiness-allocate","expectedRevision":allocation.snapshot().campaign.revision})
	check(result.ok,"native enabled allocation executes")
	allocation.dispose()
	var sale := make_runtime(f.saleSteps[10].state)
	check(fact(sale,"incorporate-prize:sale-enemy"),"crewed anchored prize exposes incorporation")
	check(fact(sale,"sell-prize:sale-enemy:sale-heritage"),"actual port and receiver expose prize sale")
	result = sale.command({"type":"sell-prize","shipId":"sale-enemy","crewToShipId":"sale-heritage","commandId":"readiness-sell","expectedRevision":sale.snapshot().campaign.revision})
	check(result.ok,"enabled prize sale retires ship through real native projection")
	sale.dispose()
	print("NATIVE_READINESS_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
