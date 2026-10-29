extends SceneTree
var assertions := 0
var failures := 0
func check(value: bool, reason: String) -> void:
	assertions += 1
	if not value: failures += 1; printerr("FAIL crew combat rules: ",reason)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var rules = load("res://game/research/demos/crew_role_rules.gd").new()
	var options := {"tick_hz":60,"transfer_seconds":2.0,"hired_ids":["crew01","crew02","crew03","crew04","crew05","crew06"],"qualified_ids":["crew03"],"casualty_seed":1661}
	check(rules.configure(options).ok,"combat configuration accepted")
	if failures: finish(); return
	var initial: Dictionary = rules.snapshot()
	check(initial.workers.size() == 6 and initial.crew_equivalent == 6.0,"only paid workers are present")
	check(initial.counts.rest == 0 and initial.counts.gunner == 3,"no free hired fillers")
	check(initial.gun_efficiency == 0.75 and initial.rates.repair == 1.125,"only paid qualification gives expertise")
	check(rules.assign("crew04","carpenter").ok,"transfer accepted")
	var transferring: Dictionary = rules.snapshot()
	check(transferring.counts.transit == 1 and transferring.gun_efficiency == 0.5,"worker leaves old position immediately")
	check(transferring.rates.repair == initial.rates.repair,"transit gives no new labor")
	check(rules.assign("crew04","carpenter").ok and rules.snapshot() == transferring,"same transfer order is idempotent")
	check(not rules.assign("crew04","rest").ok and rules.snapshot() == transferring,"conflicting transfer rejected without restart")
	for i in range(119): rules.step()
	var before: Dictionary = rules.snapshot()
	check(before.counts.transit == 1 and before.workers[3].transfer_remaining_ticks == 1,"119 of 120 ticks is still in transit")
	rules.step()
	var arrived: Dictionary = rules.snapshot()
	check(arrived.time == 2.0 and arrived.counts.transit == 0 and arrived.workers[3].role == "carpenter","arrival at exactly two seconds")
	check(is_equal_approx(arrived.ledger.hull_repaired,2.25),"arrival tick cannot retroactively produce worker labor")
	rules.step()
	check(rules.snapshot().hull > arrived.hull+1.125/60.0,"new role starts working after arrival")
	var stable: Dictionary = rules.snapshot()
	for invalid in [[NAN,6.0],[stable.hull+1.0,6.0],[stable.hull,7.0],[-1.0,6.0],[true,6.0]]:
		check(not rules.observe_combat(invalid[0],invalid[1]).ok and rules.snapshot() == stable,"invalid or healing observation is atomic")
	check(rules.observe_combat(stable.hull-8.0,4.5).ok,"actual hull and crew loss accepted")
	var damaged: Dictionary = rules.snapshot()
	check(damaged.ledger.hull_damage == 8.0 and damaged.ledger.crew_lost == 1.5,"actual damage recorded once")
	var health := 0.0
	for w: Dictionary in damaged.workers: health += w.health
	check(is_equal_approx(health,4.5) and is_equal_approx(damaged.crew_equivalent,4.5),"effective people match health weights")
	check(rules.observe_combat(damaged.hull,4.5).ok and rules.snapshot() == damaged,"same native observation does not repeat injury")
	check(is_equal_approx(damaged.hull,54.0-damaged.ledger.hull_damage+damaged.ledger.hull_repaired),"hull loss and paid repair conserved")
	var dead_id := ""
	for w: Dictionary in damaged.workers:
		if w.health == 0.0: dead_id = w.id
	check(not dead_id.is_empty() and not rules.assign(dead_id,"rest").ok,"incapacitated worker cannot take work")
	check(rules.observe_combat(0.0,4.5).ok,"sinking observed")
	var sunk: Dictionary = rules.snapshot()
	for i in range(120): rules.step()
	check(rules.snapshot().hull == 0.0 and rules.snapshot().ledger == sunk.ledger,"sunk ship cannot repair or produce meals")
	check(rules.snapshot().gun_efficiency == 0.0,"sunk vessel has no gun service")
	rules.configure(options)
	check(rules.snapshot() == initial,"reset restores exact roster health and clock")
	for bad: Dictionary in [{"tick_hz":59},{"tick_hz":true},{"transfer_seconds":-1.0},{"hired_ids":[]},{"hired_ids":["crew01","crew01"]},{"hired_ids":["crew01"],"qualified_ids":["crew02"]},{"casualty_seed":1.5}]:
		check(not rules.configure(bad).ok and rules.snapshot() == initial,"invalid personnel configuration leaves state intact")
	var repeat = load("res://game/research/demos/crew_role_rules.gd").new()
	repeat.configure(options)
	rules.observe_combat(40.0,3.5); repeat.observe_combat(40.0,3.5)
	check(rules.snapshot() == repeat.snapshot(),"casualty assignment deterministic for identical seed")
	finish()
func finish() -> void:
	print("CREW_COMBAT_RULES_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
