extends SceneTree

var assertions := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		printerr("FAIL crew contract: ", message)

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var path := "res://game/research/demos/crew_contract.gd"
	check(ResourceLoader.exists(path), "crew contract ledger exists")
	if failures: finish(); return
	var contract = load(path).new()
	check(contract.snapshot().is_empty(), "new contract has no hired people or money")
	check(not contract.configure({"budget":143}).ok and contract.snapshot().is_empty(), "unaffordable first hire leaves empty state")
	check(not contract.settle("before-hiring",0).ok and contract.snapshot().is_empty(), "cannot settle an absent contract")
	check(contract.configure({}).ok, "default ordinary four-day contract is affordable")
	var initial: Dictionary = contract.snapshot()
	var all_ids := ["crew01","crew02","crew03","crew04","crew05","crew06","crew07","crew08","crew09","crew10","crew11","crew12"]
	check(initial.roster == "ordinary" and initial.hired_ids == all_ids and initial.qualified_ids.is_empty(), "ordinary roster hires twelve identities with no free specialists")
	check(initial.hired_count == 12 and initial.budget == 144 and initial.days == 4 and initial.day == 0, "default contract exposes budget, headcount and voyage days")
	check(initial.recruitment_paid == 96 and initial.wage_reserved == 48 and initial.wages_paid == 0 and initial.free_cash == 0 and initial.total_committed == 144, "default cash pays hiring and reserves the entire wage obligation")
	check(initial.phase_receipts.is_empty(), "configuration does not invent a settlement receipt")
	conserved(initial)
	var detached: Dictionary = contract.snapshot()
	detached.hired_ids.clear()
	detached.qualified_ids.append("crew12")
	detached.phase_receipts["forged"] = 4
	check(contract.snapshot() == initial, "snapshot cannot mutate hires, qualifications or receipts")
	var invalid_options := [
		{"roster":"missing"},{"roster":true},{"extra":1},
		{"budget":143},{"budget":-1},{"budget":true},{"budget":"144"},{"budget":NAN},{"budget":INF},
		{"days":0},{"days":-1},{"days":true},{"days":4.5},{"days":"4"},{"days":NAN},{"days":INF},
		{"days":5,"budget":144},
	]
	for options: Dictionary in invalid_options:
		check(not contract.configure(options).ok and contract.snapshot() == initial, "invalid or unaffordable configuration is atomic: " + str(options))
	var rosters := [
		{"roster":"ordinary","ids":all_ids,"qualified":[]},
		{"roster":"mixed","ids":["crew01","crew02","crew03","crew04","crew05","crew06","crew07","crew08","crew09","crew10"],"qualified":["crew03","crew04"]},
		{"roster":"elite","ids":["crew01","crew02","crew03","crew04","crew05","crew06"],"qualified":["crew01","crew02","crew03","crew04","crew05","crew06"]},
	]
	for fixture: Dictionary in rosters:
		check(contract.configure({"roster":fixture.roster,"budget":144,"days":4}).ok, "same budget accepts " + fixture.roster)
		var state: Dictionary = contract.snapshot()
		check(state.hired_ids == fixture.ids and state.hired_count == fixture.ids.size(), "only paid identities are hired in " + fixture.roster)
		check(state.qualified_ids == fixture.qualified, "only paid specialists are qualified in " + fixture.roster)
		check(state.recruitment_paid == 96 and state.wage_reserved == 48 and state.total_committed == 144 and state.free_cash == 0, "headcount and expertise compete inside the same hiring and wage budget")
		for id: String in state.qualified_ids:
			check(id in state.hired_ids, "an unhired identity never appears as qualified labor")
		check(contract.settle("departure",0).ok, "explicit day zero receipt is accepted")
		check(contract.snapshot().wages_paid == 0, "day zero pays no wages")
		check(contract.settle("outbound",1).ok, "one explicit voyage day settles")
		state = contract.snapshot()
		check(state.day == 1 and state.wages_paid == 12 and state.wage_reserved == 36 and state.free_cash == 0, "one day moves twelve reserved coins to wages, never charging free cash twice")
		check(state.phase_receipts.get("outbound") == 1, "receipt binds its exact absolute voyage day")
		conserved(state)
		check(contract.settle("outbound",1).ok and contract.snapshot() == state, "same phase and day replay is idempotent")
		check(not contract.settle("outbound",2).ok and contract.snapshot() == state, "same phase with a different day is rejected atomically")
		check(contract.settle("battle-ended",1).ok, "new phase may refer to the same voyage day")
		state = contract.snapshot()
		check(state.wages_paid == 12 and state.wage_reserved == 36 and state.phase_receipts.get("battle-ended") == 1, "same-day phase does not duplicate wages")
		for request: Array in [["",2],["   ",2],["negative",-1],["future",5],["backwards",0]]:
			check(not contract.settle(request[0],request[1]).ok and contract.snapshot() == state, "invalid phase or nonmonotonic day is atomic")
		check(contract.settle("return",4).ok, "explicit return settles remaining contract days")
		state = contract.snapshot()
		check(state.day == 4 and state.wages_paid == 48 and state.wage_reserved == 0 and state.total_committed == 144, "return pays exactly the reserved four-day obligation")
		conserved(state)
		check(contract.settle("outbound",1).ok and contract.snapshot() == state, "old valid receipt remains an idempotent replay after later days")
		check(not contract.settle("late-backwards",1).ok and contract.snapshot() == state, "new receipt cannot roll contract time backward")
		var independent = load(path).new()
		independent.configure({"roster":fixture.roster,"budget":144,"days":4})
		check(independent.snapshot().day == 0 and independent.snapshot().wages_paid == 0, "another contract and battle activity cannot advance this ledger")
	check(contract.configure({"roster":"mixed","budget":160.0,"days":2}).ok, "shorter contract preserves genuinely uncommitted cash")
	var spare: Dictionary = contract.snapshot()
	check(spare.recruitment_paid == 96 and spare.wage_reserved == 24 and spare.total_committed == 120 and spare.free_cash == 40, "price uses stated voyage days and leaves unspent budget available")
	check(contract.settle("two-day-return",2).ok, "short contract can settle directly at its endpoint")
	spare = contract.snapshot()
	check(spare.wages_paid == 24 and spare.wage_reserved == 0 and spare.free_cash == 40, "settlement preserves forty uncommitted coins")
	conserved(spare)
	check(contract.configure({}).ok and contract.snapshot() == initial, "reconfiguration restores the full default contract without old receipts")
	for day in [1.5,true]:
		check(not contract.call("settle","invalid-type",day).ok and contract.snapshot() == initial,"settlement rejects fractional or boolean days before conversion")
	finish()

func conserved(state: Dictionary) -> void:
	check(is_equal_approx(state.free_cash + state.recruitment_paid + state.wage_reserved + state.wages_paid,state.budget), "budget equals free cash, hiring paid and reserved or paid wages")
	check(is_equal_approx(state.recruitment_paid + state.wage_reserved + state.wages_paid,state.total_committed), "settlement never changes total committed cost")
	check(state.free_cash >= 0 and state.wage_reserved >= 0 and state.wages_paid >= 0, "cash and wage balances never become negative")

func finish() -> void:
	print("CREW_CONTRACT_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
