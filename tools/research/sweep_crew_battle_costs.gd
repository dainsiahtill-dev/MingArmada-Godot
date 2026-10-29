extends SceneTree
## Fixed-position, scripted native combat experiment. Never a global balance score.
const Trial = preload("res://game/research/demos/crew_battle_trial.gd")
const STEP := 1.0 / 60.0
const MAX_TICKS := 3600
const EPSILON := 0.000001
const SOURCES := [
	"res://game/research/demos/crew_role_rules.gd",
	"res://game/research/demos/crew_contract.gd",
	"res://game/research/demos/crew_battle_trial.gd",
	"res://tools/research/sweep_crew_battle_costs.gd",
	"res://modules/naval_simulation/encounter.gd",
	"res://modules/naval_simulation/combat/cannon_system.gd",
	"res://modules/naval_simulation/combat/projectiles.gd",
]
var output := ""
var assertions := 0
var failures: Array = []
var cases: Array = []
var fixed_native: Dictionary = {}

func _initialize() -> void: run.call_deferred()

func check(ok: bool, reason: String) -> bool:
	assertions += 1
	if not ok:
		failures.append(reason)
		printerr("FAIL CREW BATTLE COST: ",reason)
	return ok

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output=") and output.is_empty(): output = arg.trim_prefix("--output=")
		else: check(false,"unknown or duplicate argument: " + arg)
	check(output.begins_with("res://docs/research/evidence/crew-role-effects/") and output.ends_with(".json") and not output.contains("..") and not output.contains("\\") and not FileAccess.file_exists(output) and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output)),"fresh confined JSON output required")
	if not failures.is_empty(): finish(); return
	var source_before := source_hashes()
	if not failures.is_empty(): finish(); return
	var started_utc := Time.get_datetime_string_from_system(true) + "Z"
	var started := Time.get_ticks_usec()
	for roster: String in ["ordinary","mixed","elite"]:
		for helpers: int in [0,1,2]:
			for pressure: String in ["duel","incoming"]:
				for supplies: String in ["normal","scarce"]:
					var options := {"roster":roster,"repair_helpers":helpers,"pressure":pressure,"supplies":supplies,"seed":1661}
					cases.append(run_case(options,cases.size()+1))
	var duration_us := Time.get_ticks_usec()-started
	check(cases.size() == 36,"exactly 36 declared cases recorded")
	var source_after := source_hashes()
	check(source_before == source_after,"declared source hashes stable throughout sweep")
	if not check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir())) == OK,"create evidence parent"): finish(); return
	if not check(not FileAccess.file_exists(output),"output remains absent before write"): finish(); return
	var report := {
		"schemaVersion":1,"topic":"crew-role-effects","recordType":"cpu-contract",
		"valid":failures.is_empty(),"failures":failures,"assertions":assertions,"caseCount":cases.size(),
		"startedUtc":started_utc,"finishedUtc":Time.get_datetime_string_from_system(true)+"Z",
		"scope":"36 deterministic fixed-position native projectile encounters, scripted fire commands, one seed. No global win rate, AI-policy comparison, manual combat, GPU, campaign or labor-market acceptance.",
		"engine":Engine.get_version_info(),"os":OS.get_name(),"cpu":OS.get_processor_name(),"logicalProcessorCount":OS.get_processor_count(),"displayServer":DisplayServer.get_name(),
		"sourceBefore":source_before,"sourceAfter":source_after,"sourceFreezeScope":"Declared direct kernel, contract, trial, tool and native gunnery sources; not a recursive dependency freeze.",
		"timing":{"microseconds":duration_us,"scope":"Elapsed time of all case configuration, native simulation, snapshots, event collection and assertions. CPU experiment workload, not measured CPU processor time, isolated kernel cost, GPU duration or game FPS."},
		"controls":{"seed":1661,"stepSeconds":STEP,"maxTicks":MAX_TICKS,"maxBattleSeconds":60,"budget":144,"contractDays":4,"contractDayDuringBattle":0,"playerHull":54,"enemyHull":100,"shipKind":"fuchuan","separationMeters":110,"headingRadians":0,"windSpeed":0,"waves":[],"repairTransferSeconds":2,"sampleEveryTicks":60,"fixedNativeExceptPaidPlayerCrew":fixed_native},
		"factors":{"roster":["ordinary","mixed","elite"],"repair_helpers":[0,1,2],"pressure":["duel","incoming"],"supplies":{"normal":{"grain":24,"wood":16},"scarce":{"grain":0.5,"wood":1}}},
		"comparisonContract":{"groupBy":["pressure","supplies"],"axes":["player_operational","enemy_operational","player_hull","enemy_hull","player_crew","enemy_crew","ammo_spent","enemy_ammo_spent","wood_used","duration_seconds","recruitment_paid","wages_paid","wage_reserved","total_committed","free_cash"],"policy":"Compare individual rows only within the same declared pressure and supplies. Headcount and qualification differ because the same 144-coin budget buys different rosters. No weighted score, expected winner or pooled win percentage.","wages":"Four voyage days are a separate reserved obligation. Battle seconds do not settle any contract day. Recruitment is paid; wage reserve is committed cash, not a second already-paid expense.","events":"Complete native event records retain their source event ID. Fire/hit shipId identifies the shooter; sink shipId identifies the sunk ship. Sink attribution is linked only to the immediately preceding same-time hit on that ship."},
		"limitations":["One seed and stationary opening geometry cannot establish general combat balance or AI quality.","Both sides use the native fuchuan weapons and finite ammunition; this does not sample other ship types, weapons, weather or maneuvering.","Casualty assignment and two-second transfer are declared experimental abstractions; no individual walking, medical recovery or historical labor-rate claim.","No training, recruitment market, wage arrears, long-voyage economy, campaign saves, GPU or human-input acceptance.","Recorded hit.damage is nominal projectile damage. Actual hull and crew losses come from native snapshots; the two are not treated as identical."],
		"comparisonGroups":comparison_groups(),"cases":cases,
	}
	var file := FileAccess.open(output,FileAccess.WRITE)
	if not check(file != null,"open fresh report"): finish(); return
	file.store_string(JSON.stringify(report,"\t"))
	file.flush()
	check(file.get_error() == OK,"write complete report")
	file.close()
	print("CREW_BATTLE_COST_RESULT cases=",cases.size()," cpu_experiment_elapsed_us=",duration_us," output=",output)
	finish()

func run_case(options: Dictionary, ordinal: int) -> Dictionary:
	var id := "%s-h%d-%s-%s" % [options.roster,options.repair_helpers,options.pressure,options.supplies]
	print("CREW_BATTLE_COST_CASE start=",ordinal,"/36 id=",id)
	var errors_before := failures.size()
	var case_started := Time.get_ticks_usec()
	var trial := Trial.new()
	var configured: Dictionary = trial.configure(options)
	if not check(configured.get("ok",false),id+": configure failed: "+str(configured)):
		return {"id":id,"options":options,"valid":false,"configureReceipt":configured,"failures":failures.slice(errors_before)}
	var initial: Dictionary = trial.snapshot()
	var state: Dictionary = initial
	var timeline: Array = [brief(initial)]
	var events: Array = []
	var event_ids: Dictionary = {}
	var initial_ok := validate_initial(initial,options,id)
	initial_ok = validate_state(initial,initial,id,0) and initial_ok
	collect_events(trial.drain_events(),events,event_ids,0,id)
	if initial_ok:
		for tick in range(1,MAX_TICKS+1):
			trial.step()
			state = trial.snapshot()
			var valid_events := collect_events(trial.drain_events(),events,event_ids,tick,id)
			var valid_state := validate_state(state,initial,id,tick)
			if tick % 60 == 0 or state.finished: timeline.append(brief(state))
			if not valid_events or not valid_state or state.finished: break
	if timeline[-1].tick != state.tick: timeline.append(brief(state))
	check(state.finished,id+": bounded run reaches finished state within 3600 steps")
	check(state.error.is_empty() and state.outcome != "error",id+": trial runtime error: "+str(state.error))
	check(events.size() == int(state.events_count),id+": complete native event list matches trial event count")
	if state.finished:
		for repeat in range(3):
			trial.step()
			check(trial.snapshot() == state,id+": finished state remains unchanged after step "+str(repeat+1))
			check(trial.drain_events().is_empty(),id+": finished step emits no new events")
	var summary := metrics(state)
	var case_failures: Array = failures.slice(errors_before)
	print("CREW_BATTLE_COST_CASE done=",ordinal,"/36 id=",id," outcome=",state.outcome," tick=",state.tick," hull=",summary.player_hull," crew=",summary.player_crew," ammo=",summary.ammo_spent," failures=",case_failures.size())
	return {"id":id,"options":options,"valid":case_failures.is_empty(),"failures":case_failures,"configureReceipt":configured,"initial":initial,"final":state,"summary":summary,"timeline":timeline,"events":events,"elapsedMicroseconds":Time.get_ticks_usec()-case_started}

func validate_initial(state: Dictionary, options: Dictionary, id: String) -> bool:
	var ok := check(state.ready and state.options == options,id+": accepted fixture matches exact requested options")
	var player := ship(state,"player")
	var enemy := ship(state,"enemy")
	var native_fixed: Dictionary = state.native.duplicate(true)
	for item: Dictionary in native_fixed.ships:
		if item.id == "player": item.crew = 0.0
	if fixed_native.is_empty(): fixed_native = native_fixed
	ok = check(native_fixed == fixed_native,id+": same native ships, weapons, ammo, positions and environment except paid player crew") and ok
	ok = check(player.kind == "fuchuan" and enemy.kind == "fuchuan" and player.hull == 54.0 and enemy.hull == 100.0,id+": fixed ship and initial damage fixture") and ok
	ok = check(state.contract.budget == 144 and state.contract.total_committed == 144 and state.contract.days == 4 and state.contract.day == 0 and state.contract.wages_paid == 0,id+": equal four-day hiring and pay budget") and ok
	ok = check(state.crew.wood == (1.0 if options.supplies == "scarce" else 16.0) and state.crew.grain == (0.5 if options.supplies == "scarce" else 24.0),id+": supplies equal the declared factor") and ok
	var hired: Array = []
	for worker: Dictionary in state.crew.workers: hired.append(worker.id)
	ok = check(hired == state.contract.hired_ids and hired.size() == int(state.contract.hired_count),id+": no unpaid labor added to roster") and ok
	return ok

func validate_state(state: Dictionary, initial: Dictionary, id: String, tick: int) -> bool:
	var at := id+" tick="+str(tick)
	var player := ship(state,"player")
	var enemy := ship(state,"enemy")
	var crew: Dictionary = state.crew
	var ledger: Dictionary = crew.ledger
	var account: Dictionary = state.contract
	var health := 0.0
	var bounded_health := true
	for worker: Dictionary in crew.workers:
		health += float(worker.health)
		bounded_health = bounded_health and is_finite(float(worker.health)) and worker.health >= 0.0 and worker.health <= 1.0
	var ok := check(state.error.is_empty(),at+": no runtime error: "+str(state.error))
	ok = check(int(state.tick) == tick and int(state.native.tick) == tick and close(state.time,float(tick)*STEP) and close(state.native.time,state.time),at+": one shared 60Hz accepted battle timeline") and ok
	ok = check(close(player.hull,crew.hull),at+": native and worker hull agree") and ok
	ok = check(bounded_health and close(player.crew,health) and close(crew.crew_equivalent,health),at+": native effective crew equals bounded worker-health sum") and ok
	ok = check(close(player.hull,54.0-float(ledger.hull_damage)+float(ledger.hull_repaired)),at+": initial hull minus actual loss plus material repair reconciles") and ok
	ok = check(close(crew.wood,float(initial.crew.wood)-0.5*float(ledger.hull_repaired)) and close(ledger.wood_used,0.5*float(ledger.hull_repaired)),at+": repair consumes half a wood unit per actual hull point") and ok
	ok = check(close(state.metrics.hull_damage_taken,ledger.hull_damage) and close(state.metrics.hull_repaired,ledger.hull_repaired) and close(float(initial.contract.hired_count)-health,ledger.crew_lost),at+": loss and repair metrics use actual state changes") and ok
	ok = check(close(float(account.recruitment_paid)+float(account.wage_reserved)+float(account.wages_paid)+float(account.free_cash),144.0),at+": hiring, reserved pay, paid wages and cash conserve budget") and ok
	ok = check(account == initial.contract,at+": battle seconds cannot change contract days, wages or receipts") and ok
	ok = check(crew.wood >= -EPSILON and player.hull >= 0.0 and player.hull <= 80.0+EPSILON and enemy.hull >= 0.0 and player.crew >= 0.0 and enemy.crew >= 0.0,at+": resources and ship states remain bounded") and ok
	ok = check(int(ship(initial,"player").ammo.solid)-int(player.ammo.solid) == int(state.metrics.ammo_spent) and int(ship(initial,"enemy").ammo.solid)-int(enemy.ammo.solid) == int(state.metrics.enemy_ammo_spent),at+": actual ammunition debits match recorded use") and ok
	return ok

func collect_events(batch: Array, events: Array, ids: Dictionary, tick: int, id: String) -> bool:
	var ok := true
	for raw: Dictionary in batch:
		var source_event_id: String = str(raw.get("id",""))
		var valid_id := not source_event_id.is_empty() and not ids.has(source_event_id)
		ok = check(valid_id,id+": unique native source event ID at tick "+str(tick)) and ok
		ids[source_event_id] = true
		var record := {"accepted_tick":tick,"source":"Encounter.drain_events","source_event_id":source_event_id,"raw":raw.duplicate(true)}
		if raw.get("type") in ["fire","hit"]:
			record.source_ship_id = raw.get("shipId","")
			ok = check(record.source_ship_id in ["player","enemy"],id+": fire/hit has a real source ship") and ok
		elif raw.get("type") == "sink":
			record.sunk_ship_id = raw.get("shipId","")
			var previous: Dictionary = events[-1].raw if not events.is_empty() else {}
			var linked: bool = previous.get("type") == "hit" and previous.get("targetId") == record.sunk_ship_id and previous.get("time") == raw.get("time")
			ok = check(linked,id+": sink must retain an evidenced same-time causal hit") and ok
			record.source_ship_id = previous.get("shipId","") if linked else "unknown"
			record.causal_hit_source_event_id = previous.get("id","") if linked else ""
		events.append(record)
	return ok

func ship(state: Dictionary, id: String) -> Dictionary:
	for item: Dictionary in state.native.ships:
		if item.id == id: return item
	return {}

func close(a: float, b: float) -> bool:
	return is_finite(a) and is_finite(b) and absf(a-b) <= EPSILON

func brief(state: Dictionary) -> Dictionary:
	var player := ship(state,"player")
	var enemy := ship(state,"enemy")
	return {"tick":state.tick,"time":state.time,"finished":state.finished,"outcome":state.outcome,"player_hull":player.hull,"enemy_hull":enemy.hull,"player_crew":player.crew,"enemy_crew":enemy.crew,"player_ammo":player.ammo.solid,"enemy_ammo":enemy.ammo.solid,"gun_efficiency":state.crew.gun_efficiency,"repair_staffing":state.crew.repair_staffing.duplicate(true),"role_counts":state.crew.counts.duplicate(true),"wood":state.crew.wood,"hull_damage":state.crew.ledger.hull_damage,"hull_repaired":state.crew.ledger.hull_repaired,"events_count":state.events_count,"projectiles_in_flight":state.native.projectiles.size(),"contract_day":state.contract.day,"wages_paid":state.contract.wages_paid}

func metrics(state: Dictionary) -> Dictionary:
	var player := ship(state,"player")
	var enemy := ship(state,"enemy")
	var account: Dictionary = state.contract
	return {"outcome":state.outcome,"player_operational":player.hull > 0.0 and player.crew > 0.0,"enemy_operational":enemy.hull > 0.0 and enemy.crew > 0.0,"player_hull":player.hull,"enemy_hull":enemy.hull,"player_crew":player.crew,"enemy_crew":enemy.crew,"ammo_spent":state.metrics.ammo_spent,"enemy_ammo_spent":state.metrics.enemy_ammo_spent,"wood_used":state.crew.ledger.wood_used,"hull_damage_taken":state.crew.ledger.hull_damage,"hull_repaired":state.crew.ledger.hull_repaired,"duration_seconds":state.time,"recruitment_paid":account.recruitment_paid,"wages_paid":account.wages_paid,"wage_reserved":account.wage_reserved,"total_committed":account.total_committed,"free_cash":account.free_cash,"projectiles_remaining":state.native.projectiles.size(),"native_fire_count":state.metrics.fire_count,"native_hit_count":state.metrics.hit_count}

func comparison_groups() -> Array:
	var result: Array = []
	for pressure: String in ["duel","incoming"]:
		for supplies: String in ["normal","scarce"]:
			var rows: Array = []
			for row: Dictionary in cases:
				if row.options.pressure == pressure and row.options.supplies == supplies:
					rows.append({"id":row.id,"roster":row.options.roster,"repair_helpers":row.options.repair_helpers,"valid":row.valid,"metrics":row.get("summary",{})})
			result.append({"pressure":pressure,"supplies":supplies,"rows":rows})
	return result

func source_hashes() -> Dictionary:
	var result: Dictionary = {}
	for path: String in SOURCES:
		var sha := FileAccess.get_sha256(path)
		check(sha.length() == 64,"read declared SHA256 source: "+path)
		result[path] = sha
	return result

func finish() -> void:
	print("CREW_BATTLE_COST_TESTS assertions=",assertions," cases=",cases.size()," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
