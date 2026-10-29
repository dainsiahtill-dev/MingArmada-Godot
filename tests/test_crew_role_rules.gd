extends SceneTree

var assertions := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		printerr("FAIL crew roles: ", message)

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var path := "res://game/research/demos/crew_role_rules.gd"
	check(ResourceLoader.exists(path), "crew work rules exist")
	if failures: finish(); return
	var rules = load(path).new()
	check(rules.configure({}).ok, "defaults accepted")
	var initial: Dictionary = rules.snapshot()
	check(initial.workers.size() == 12 and initial.counts.gunner == 4, "12 unique workers, four active gunners")
	var detached: Dictionary = rules.snapshot()
	detached.workers[0].role = "gunner"
	check(rules.snapshot() == initial, "snapshot cannot mutate workers")
	for options: Dictionary in [{"preset":"unknown"},{"specialists":1},{"extra":true}]:
		check(not rules.configure(options).ok and rules.snapshot() == initial, "bad configuration is atomic")
	for pair: Array in [["missing","cook"],["crew04","missing"]]:
		check(not rules.assign(pair[0],pair[1]).ok and rules.snapshot() == initial, "bad assignment is atomic")
	for i in range(32*8): rules.step()
	var advanced: Dictionary = rules.snapshot()
	check(advanced.tick == 256 and advanced.time == 8.0, "fixed step clock")
	check(advanced.hull > initial.hull and advanced.wood < initial.wood, "repair changes real hull and spends wood")
	check(advanced.morale > initial.morale and advanced.ledger.meals_eaten > 0, "music and meals have actual effects")
	check(advanced.workers[7].fatigue < initial.workers[7].fatigue, "rest group receives recovery")
	check(advanced.workers[0].fatigue == initial.workers[0].fatigue, "workers are not secretly resting")
	conserved(advanced, initial)
	var before_rate: float = advanced.rates.repair
	check(rules.assign("crew04","carpenter").ok and rules.assign("crew05","carpenter").ok, "can move two gunners")
	var reassigned: Dictionary = rules.snapshot()
	check(reassigned.gun_efficiency == 0.75 and reassigned.counts.gunner == 2, "moved gunners leave gun service")
	check(reassigned.rates.repair > before_rate and reassigned.rates.repair == 2.625, "three repair positions accept one specialist and two helpers")
	check(reassigned.hull == advanced.hull and reassigned.ledger == advanced.ledger, "assignment does not award or erase work")
	check(rules.assign("crew04","carpenter").ok and rules.snapshot() == reassigned, "repeating assignment does not duplicate worker")
	var other = load(path).new()
	other.configure({})
	for i in range(256): other.step()
	check(other.snapshot() == advanced, "deterministic identical run")
	other.configure({"specialists":false})
	for i in range(256): other.step()
	var baseline: Dictionary = other.snapshot()
	check(baseline.hull > initial.hull and baseline.ledger.meals_cooked > 0, "ordinary crew provide basic jobs")
	check(baseline.hull < advanced.hull and baseline.ledger.meals_cooked < advanced.ledger.meals_cooked, "specialists increase bounded work rate")
	check(rules.configure({"preset":"scarce"}).ok, "scarce fixture")
	var scarce: Dictionary = rules.snapshot()
	for i in range(32*60): rules.step()
	var exhausted: Dictionary = rules.snapshot()
	check(is_zero_approx(exhausted.grain) and is_zero_approx(exhausted.wood), "finite resources exhaust")
	check(is_equal_approx(exhausted.hull,56.0) and exhausted.ledger.meals_eaten == 0, "one wood repairs two points, half ration cannot feed")
	check(exhausted.repair_staffing.active == 0 and exhausted.repair_staffing.worker_ids.is_empty(),"no wood leaves no active repair workers")
	for i in range(320): rules.step()
	check(rules.snapshot().hull == exhausted.hull and rules.snapshot().ledger == exhausted.ledger, "no free repair or meals after exhaustion")
	conserved(rules.snapshot(), scarce)
	rules.configure({})
	for worker: Dictionary in rules.snapshot().workers: rules.assign(worker.id,"carpenter")
	check(rules.snapshot().gun_efficiency == 0.0, "all moved gunners mean no gun service")
	var work_only: Dictionary = rules.snapshot()
	for i in range(32*120): rules.step()
	check(rules.snapshot().morale == work_only.morale and rules.snapshot().ledger.meals_eaten == 0, "no resting group gets no rest benefits")
	check(rules.snapshot().hull == 80.0 and rules.snapshot().wood == 3.0, "at-sea repair stops at cap with spare wood")
	var capped: Dictionary = rules.snapshot()
	check(capped.repair_staffing.active == 0 and capped.repair_staffing.worker_ids.is_empty() and capped.repair_staffing.waiting == 12,"fully repaired hull releases work positions to standby")
	for i in range(320): rules.step()
	check(rules.snapshot().wood == capped.wood and rules.snapshot().hull == capped.hull, "capped hull spends no spare wood")
	rules.configure({})
	for worker: Dictionary in rules.snapshot().workers: rules.assign(worker.id,"cook")
	for i in range(32*30): rules.step()
	var full_larder: Dictionary = rules.snapshot()
	check(full_larder.cooked_rations == 12.0 and full_larder.grain == 12.0, "full cooked storage retains unspent grain")
	for i in range(320): rules.step()
	check(rules.snapshot().ledger == full_larder.ledger, "full storage prevents further resource spending")
	rules.configure({})
	for i in range(32*600): rules.step()
	var long_run: Dictionary = rules.snapshot()
	conserved(long_run, initial)
	check(long_run.morale <= 100.0 and long_run.hull <= 80.0, "long run remains bounded")
	for worker: Dictionary in long_run.workers: check(worker.fatigue >= 0.0 and worker.fatigue <= 100.0, "fatigue bounded")
	check(rules.configure({}).ok and rules.snapshot() == initial, "reset reproduces complete initial state")
	check(rules.snapshot().has("repair_staffing"),"repair staffing contract exposes real active positions")
	if not rules.snapshot().has("repair_staffing"): finish(); return
	var ids := ["crew03","crew04","crew05","crew06","crew07","crew08","crew09","crew10","crew11","crew12","crew01","crew02"]
	for specialists: bool in [false,true]:
		for people: int in [1,2,3,4,12]:
			rules.configure({"specialists":specialists})
			for worker: Dictionary in rules.snapshot().workers: rules.assign(worker.id,"rest")
			for i in range(people): rules.assign(ids[i],"carpenter")
			var staffed: Dictionary = rules.snapshot()
			var active := mini(people,3)
			check(is_equal_approx(staffed.rates.repair,(float(active)+(0.5 if specialists else 0.0))*0.75),"real slots bound ordinary and skilled repair labor")
			check(staffed.repair_staffing.active == active and staffed.repair_staffing.waiting == people-active,"excess repair assignments are visible standbys")
			if people == 12:
				check(staffed.repair_staffing.worker_ids == (["crew03","crew01","crew02"] if specialists else ["crew01","crew02","crew03"]),"highest skill then stable ID determines exact active workers")
	rules.configure({"repair_model":"legacy_cap"})
	rules.assign("crew04","carpenter")
	var old_one: Dictionary = rules.snapshot()
	rules.assign("crew05","carpenter")
	check(old_one.rates.repair == rules.snapshot().rates.repair and old_one.gun_efficiency > rules.snapshot().gun_efficiency,"retained baseline reproduces dominated second helper")
	rules.configure({"repair_model":"workstations"})
	rules.assign("crew04","carpenter")
	var new_one: Dictionary = rules.snapshot()
	rules.assign("crew05","carpenter")
	check(new_one.rates.repair < rules.snapshot().rates.repair and new_one.gun_efficiency > rules.snapshot().gun_efficiency,"second helper gains repair speed at gun cost in candidate")
	var candidate: Dictionary = rules.snapshot()
	check(not rules.configure({"repair_model":"invalid"}).ok and rules.snapshot() == candidate,"invalid balance model is atomic")
	var start := Time.get_ticks_usec()
	for i in range(32000): rules.step()
	print("CREW_RULES_COST steps=32000 microseconds=",Time.get_ticks_usec()-start," scope=kernel_only")
	finish()

func conserved(state: Dictionary, initial: Dictionary) -> void:
	check(absf(initial.grain-state.grain-state.ledger.grain_used) < 0.000001, "grain debit conserved")
	check(absf(state.ledger.grain_used-state.ledger.meals_cooked) < 0.000001, "grain converts equally to cooked rations")
	check(absf(state.ledger.meals_cooked-state.cooked_rations-state.ledger.meals_eaten) < 0.000001, "cooked food conserved")
	check(absf(initial.wood-state.wood-state.ledger.wood_used) < 0.000001, "wood debit conserved")
	check(absf(state.ledger.hull_repaired*0.5-state.ledger.wood_used) < 0.000001, "repair material conserved")
	check(absf(state.hull-initial.hull-state.ledger.hull_repaired) < 0.000001, "real hull matches work ledger")
	check(state.grain >= 0.0 and state.wood >= 0.0 and state.cooked_rations >= 0.0, "inventories nonnegative")

func finish() -> void:
	print("CREW_ROLE_RULES_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
