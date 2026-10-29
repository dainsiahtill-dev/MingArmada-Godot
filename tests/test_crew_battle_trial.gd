extends SceneTree
var assertions := 0
var failures := 0
func check(value: bool, reason: String) -> void:
	assertions += 1
	if not value: failures += 1; printerr("FAIL crew battle: ",reason)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var path := "res://game/research/demos/crew_battle_trial.gd"
	check(ResourceLoader.exists(path),"real battle trial exists")
	if failures: finish(); return
	var trial = load(path).new()
	check(trial.configure({"roster":"ordinary","pressure":"duel"}).ok,"ordinary paid crew enters actual duel")
	if failures: finish(); return
	var initial: Dictionary = trial.snapshot()
	check(initial.contract.total_committed == 144 and initial.crew.workers.size() == 12,"full paid cohort")
	check(initial.native.ships.size() == 2 and initial.crew.tick_hz == 60,"two actual native ships, one 60Hz clock")
	check(initial.has("gunnery"),"actual next-cycle reload quote exposed")
	if not initial.has("gunnery"): finish(); return
	check(is_equal_approx(initial.gunnery.next_reload_seconds,7.0),"full ordinary gun crew gives native seven-second reload")
	trial.step()
	var fired: Dictionary = trial.snapshot()
	check(trial.assign_helpers(2).ok,"transfer accepted during existing reload")
	var transferred: Dictionary = trial.snapshot()
	check(transferred.gunnery.current_cooldown == fired.gunnery.current_cooldown and is_equal_approx(transferred.gunnery.next_reload_seconds,14.0),"live job change affects next cycle but does not rewrite active cooldown")
	trial.configure({"roster":"ordinary","pressure":"duel"})
	for i in range(240): trial.step()
	var fought: Dictionary = trial.snapshot()
	check(fought.tick == 240 and is_equal_approx(fought.time,4.0) and is_equal_approx(fought.crew.time,fought.native.time),"exact native and crew timeline")
	check(fought.metrics.fire_count > 0 and fought.metrics.hit_count > 0,"real projectile fire and collisions occurred")
	check(fought.metrics.hull_damage_taken > 0 and fought.crew.ledger.hull_damage > 0,"native damage reaches worker simulation")
	conserved(fought)
	check(fought.contract == initial.contract,"battle seconds cannot settle voyage wages")
	var events: Array = trial.drain_events()
	check(events.any(func(e): return e.type == "fire") and events.any(func(e):return e.type == "hit"),"unmodified native event types available to renderer")
	check(trial.drain_events().is_empty(),"events consumed exactly once")
	var other = load(path).new()
	other.configure({"roster":"ordinary","pressure":"duel"})
	for i in range(240): other.step()
	check(other.snapshot() == fought,"same source and inputs reproduce whole battle state")
	check(not trial.configure({"roster":"unknown"}).ok and trial.snapshot() == fought,"invalid reset does not destroy battle")
	check(trial.configure({"roster":"mixed","pressure":"calm"}).ok,"mixed roster accepted")
	check(trial.snapshot().crew.workers.size() == 10 and trial.snapshot().contract.total_committed == 144,"experts replace paid headcount, not free upgrades")
	check(trial.assign_helpers(2).ok,"two helpers move")
	var transitioning: Dictionary = trial.snapshot()
	check(transitioning.crew.counts.transit == 2 and transitioning.crew.counts.carpenter == 1,"repair helpers are truly in transit")
	check(not trial.assign_helpers(1).ok and trial.snapshot() == transitioning,"multi-worker conflicting order is atomic")
	for i in range(120): trial.step()
	check(trial.snapshot().crew.counts.transit == 0 and trial.snapshot().crew.repair_staffing.active == 3,"three actual repair positions after arrival")
	check(trial.snapshot().metrics.fire_count == 0 and trial.snapshot().metrics.hit_count == 0,"calm control has no invented shots")
	conserved(trial.snapshot())
	trial.configure({"roster":"elite","pressure":"incoming"})
	for i in range(3600):
		trial.step()
		if trial.snapshot().finished: break
	var ended: Dictionary = trial.snapshot()
	check(ended.finished and ended.time <= 60.0,"trial reaches bounded actual outcome")
	check(ended.metrics.player_fire_count == 0 and ended.metrics.enemy_fire_count > 0,"incoming pressure uses native enemy fire only")
	conserved(ended)
	trial.step()
	check(trial.snapshot() == ended,"finished trial no longer spends resources")
	var found_fixture := false
	for seed_value in range(64):
		trial.configure({"pressure":"incoming","repair_helpers":2,"seed":seed_value})
		var order: Array = trial.snapshot().crew.casualty_order
		if order.find("crew04") < 4 and order.find("crew05") >= 4:
			found_fixture = true
			break
	check(found_fixture,"deterministic actual-fire fixture separates helper casualties")
	for i in range(180): trial.step()
	var casualties: Dictionary = trial.snapshot()
	var helper_a: Dictionary = casualties.crew.workers.filter(func(w):return w.id == "crew04")[0]
	var helper_b: Dictionary = casualties.crew.workers.filter(func(w):return w.id == "crew05")[0]
	check(helper_a.health == 0.0 and helper_b.health > 0.0,"actual native volley incapacitates one helper, leaves other")
	check(trial.assign_helpers(0).ok,"incapacitated helper cannot prevent survivor returning to guns")
	for i in range(120): trial.step()
	check(trial.assign_helpers(1).ok,"one helper request selects surviving available worker")
	finish()
func conserved(state: Dictionary) -> void:
	var player: Dictionary = state.native.ships.filter(func(s):return s.id == "player")[0]
	check(is_equal_approx(player.hull,state.crew.hull),"repair and native hull share authority")
	check(is_equal_approx(player.crew,state.crew.crew_equivalent),"native effective crew equals worker health sum")
	check(is_equal_approx(player.hull,54.0-state.crew.ledger.hull_damage+state.crew.ledger.hull_repaired),"actual loss and paid repair reconcile")
	check(is_equal_approx(state.crew.wood,16.0-state.crew.ledger.hull_repaired*0.5),"native repairs spend actual material")
func finish() -> void:
	print("CREW_BATTLE_TRIAL_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
