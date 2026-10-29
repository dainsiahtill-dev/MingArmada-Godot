extends SceneTree
## Predeclared deterministic CPU matrix through the frozen public fire rules API.
## Run with --output=res://docs/research/evidence/ship-fire-control/<fresh-run>/balance.json

const Fire = preload("res://modules/naval_simulation/combat/fire_control.gd")
const Profile = preload("res://modules/naval_simulation/combat/fire_profile.gd")
const SOURCES := [
	"res://modules/naval_simulation/combat/fire_control.gd",
	"res://modules/naval_simulation/combat/fire_profile.gd",
	"res://tools/research/scan_ship_fire_balance.gd",
]
const STEP := 1.0 / 60.0
const MAX_TICKS := 4800
const EPSILON := 0.000001
const PAYLOADS := ["fire-ball", "thorn-ball"]
const MOISTURE := {
	"dry":{"initialWetness":0.0,"rain01":0.0},
	"rain":{"initialWetness":0.0,"rain01":1.0},
	"wet-deck":{"initialWetness":1.0,"rain01":0.0},
}
const LOADS := [0.0, 1.0]
const SUPPLIES := [0, 4, 24]
const WORKERS := [0, 2, 4, 8]
const BENEFIT_MINIMIZE := ["hullDamage", "sailDamage", "crewLost", "extinguishTick"]
const COST_MINIMIZE := ["workSeconds", "suppliesSpent", "reservedCrewSeconds"]

var output := ""
var assertions := 0
var failures: Array = []
var cases: Array = []
var groups: Array = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> bool:
	assertions += 1
	if not ok and not failures.has(label):
		failures.append(label)
		printerr("FAIL SHIP FIRE BALANCE: ", label)
	return ok

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output=") and output.is_empty():
			output = arg.trim_prefix("--output=")
		else:
			check(false, "unknown or duplicate argument: " + arg)
	check(output.begins_with("res://docs/research/evidence/ship-fire-control/") and output.ends_with(".json") and not output.contains("..") and not output.contains("\\") and not FileAccess.file_exists(output) and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output)), "fresh confined JSON output required")
	check(close(Profile.STEP_SECONDS, STEP), "scanner and frozen kernel share 60 Hz")
	verify_comparison_contract()
	if not failures.is_empty():
		finish()
		return
	var source_before := source_hashes()
	if not failures.is_empty():
		finish()
		return
	var started_utc := Time.get_datetime_string_from_system(true) + "Z"
	var started := Time.get_ticks_usec()
	for payload: String in PAYLOADS:
		for moisture: String in MOISTURE:
			for load: float in LOADS:
				for supplies: int in SUPPLIES:
					var members: Array = []
					for workers: int in WORKERS:
						var options := {"payload":payload,"moisture":moisture,"flammableLoad":load,"supplies":supplies,"workers":workers}
						var row := run_case(options)
						cases.append(row)
						members.append(row)
					groups.append(compare_group(payload, moisture, load, supplies, members))
	check(cases.size() == 144 and groups.size() == 36, "exactly 144 declared cases and 36 matched four-worker groups")
	var source_after := source_hashes()
	check(source_before == source_after, "declared sources remain frozen throughout scan")
	var elapsed_us := Time.get_ticks_usec() - started
	var dominance_count := 0
	var pair_classifications := {"tradeoff":0,"higher-workers-dominates":0,"two-workers-dominates":0,"equivalent":0,"incomparable":0,"unavailable":0}
	for group: Dictionary in groups:
		dominance_count += group.dominance.size()
		for pair: Dictionary in group.twoVersusMore:
			pair_classifications[pair.classification] += 1
	check(_all_finite(cases) and _all_finite(groups), "all recorded case and comparison numbers are finite")
	var report := {
		"schemaVersion":1,"topic":"ship-fire-control","recordType":"cpu-contract",
		"valid":failures.is_empty(),"assertions":assertions,"failures":failures,
		"candidateVersion":Profile.VERSION,"caseCount":cases.size(),"comparisonGroupCount":groups.size(),
		"dominancePairCount":dominance_count,"twoVersusMoreClassifications":pair_classifications,
		"startedUtc":started_utc,"finishedUtc":Time.get_datetime_string_from_system(true) + "Z",
		"scope":"144 deterministic pure-kernel fixtures with one time-zero ignition and one simultaneous staffing order. No random samples, win rate, native projectile encounter, GPU, player acceptance or overall game balance.",
		"environment":{"engine":Engine.get_version_info(),"os":OS.get_name(),"cpu":OS.get_processor_name(),"displayServer":DisplayServer.get_name()},
		"sourceBefore":source_before,"sourceAfter":source_after,
		"sourceFreezeScope":"Direct fire kernel, parameter profile and this scan script; not a recursive dependency freeze.",
		"controls":{
			"seed":"not applicable: no RNG","stepSeconds":STEP,"maxTicks":MAX_TICKS,"maxSeconds":80.0,
			"initialHull":100.0,"maxHull":100.0,"initialSail":100.0,"maxSail":100.0,"initialCrew":100,"maxCrew":100,
			"policy":"At accepted time zero, ignite once and assign requested workers once. No pre-staffed advantage, later retargeting, reinforcements, repair or resupply. Continue after heat extinction until every reserved firefighter returns.",
			"damageApplication":"Apply each returned hull/sail recommendation with zero-floor clamping and each integer crew debit to the actual remaining population; next context.able is that remaining population. Record both recommendations and actual debits.",
			"reservationIntegral":"Sum reserved_crew(state at tick start, able at tick start) * 1/60. Deaths are applied at tick end. This counts every full outbound and return transfer tick, including the return tick ending with zero reservation.",
			"extinctionClock":"extinguishTick is the accepted tick whose step first returns extinguished=true. The actual within-tick extinction lies in the separately recorded lower/upper seconds bounds; no exact sub-tick time is invented.",
			"stop":"heat=0 and assigned=0 and pending=0 and transferTicks=0; otherwise fail at 4800 accepted ticks without erasing that failure.",
		},
		"factors":{"payload":PAYLOADS,"moisture":MOISTURE,"flammableLoad":LOADS,"supplies":SUPPLIES,"workers":WORKERS},
		"predeclaredChecks":[
			"Each case completes burning and all return travel within 80 seconds.",
			"Every returned state is valid and all recorded numbers are finite; all HP, population and inventory remain nonnegative.",
			"Hull/sail/crew initial state equals endpoint plus actual cumulative loss; crew damage is integer.",
			"supplies + cumulative suppliesSpent equals initial stock; cumulative work equals 2*spent + final workCarry and never exceeds initial stock*2.",
			"No preparation means zero work and spending, with fire damage and extinction tick equal to that matched zero-worker control.",
			"Zero workers means zero work, spending and reserved crew-seconds; every matched worker strategy records a delta against this control.",
			"The 2-versus-4 and 2-versus-8 comparisons report whether benefit and cost axes trade off; no winner or required tradeoff is prescribed.",
		],
		"comparisonContract":{
			"groupBy":["payload","moisture","flammableLoad","supplies"],
			"benefitMinimize":BENEFIT_MINIMIZE,"costMinimize":COST_MINIMIZE,"absoluteEpsilon":EPSILON,
			"units":{"hullDamage":"actual hull points lost","sailDamage":"actual sail points lost","crewLost":"actual integer people lost","extinguishTick":"accepted 1/60-second ticks","workSeconds":"effective firefighting person-seconds","suppliesSpent":"whole preparation portions fully consumed","reservedCrewSeconds":"people unavailable for other stations integrated over accepted seconds"},
			"dominance":"A dominates B only when A is no worse on every declared axis within absolute epsilon and strictly better by more than epsilon on at least one. All declared axes are minimized. No weights, scalar score, cross-group pooling or win percentage.",
			"partialSupplies":"A partially used portion remains in supplies and its workCarry records used person-seconds; workSeconds includes this partial consumption, while suppliesSpent counts only whole portions.",
			"peakCrew":"peakReservedCrew is recorded as descriptive instantaneous staffing pressure; it is not an extra objective that forces a tradeoff by definition.",
		},
		"sensitivity":{"status":"not-run","requestedVariation":"plus/minus 20 percent of candidate parameters","reason":"Frozen production parameters are constants. This script calls the real public kernel and does not duplicate formulas or invent an alternate parameter path for sensitivity."},
		"limitations":[
			"This is a local fire-versus-damage-control matrix, not a same-budget combat, weapon purchase, role allocation or long-voyage economy experiment.",
			"Reserved crew-seconds express occupation but do not simulate actual lost volleys, reload deadlines, boarding, movement, individual walking or fatigue.",
			"One deterministic result per cell is not a random sample, repeated statistical trial, probability estimate or win rate.",
			"Extinguish ticks resolve accepted 60 Hz boundaries; exact within-tick event timestamps are not exposed by the kernel.",
			"No neighboring-compartment spread, cargo loss, toxic effects, powder detonation, wind propagation, real thermodynamics or claim about historical damage rates.",
			"No GPU, official game entrypoint, save/bridge integration or full-scene performance acceptance. Elapsed scan time includes assertions and report collection, not isolated kernel cost or game FPS.",
			"Parameter sensitivity plus/minus 20 percent is explicitly unmeasured for this frozen-constant candidate.",
		],
		"timing":{"elapsedMicroseconds":elapsed_us,"scope":"Entire deterministic CPU scan including state copies, actual damage application, invariants and comparison collection; not a frame-time measurement."},
		"cases":cases,"groups":groups,
	}
	write_report(report)
	print("SHIP_FIRE_BALANCE_RESULT cases=", cases.size(), " groups=", groups.size(), " dominance_pairs=", dominance_count, " output=", output)
	finish()

func run_case(options: Dictionary) -> Dictionary:
	var id := "%s-%s-load%d-stock%d-workers%d" % [options.payload, options.moisture, int(options.flammableLoad), options.supplies, options.workers]
	var errors_before := failures.size()
	var state: Dictionary = Fire.initial(options.supplies)
	var cold_initial := state.duplicate(true)
	var moisture: Dictionary = MOISTURE[options.moisture]
	var ignition: Dictionary = Fire.ignite(state, options.payload, moisture.initialWetness)
	if not check(ignition.ok, id + ": ignition accepted"):
		return {"id":id,"options":options.duplicate(true),"valid":false,"failures":failures.slice(errors_before)}
	var assignment: Dictionary = Fire.assign(ignition.state, options.workers, 100)
	if not check(assignment.ok, id + ": time-zero transfer order accepted"):
		return {"id":id,"options":options.duplicate(true),"valid":false,"failures":failures.slice(errors_before)}
	state = assignment.state
	var initial := state.duplicate(true)
	var input := {"able":100,"maxHull":100.0,"maxSail":100.0,"maxCrew":100,"rain01":moisture.rain01,"flammableLoad":options.flammableLoad}
	var initial_context := input.duplicate(true)
	var actual := {"hull":100.0,"sail":100.0,"crew":100}
	var recommended := {"hull":0.0,"sail":0.0,"crew":0}
	var metrics := {"hullDamage":0.0,"sailDamage":0.0,"crewLost":0,"extinguishTick":-1,"workSeconds":0.0,"suppliesSpent":0,"reservedCrewSeconds":0.0,"peakReservedCrew":0}
	var ticks := 0
	var stopped := false
	var milestones := {"firstWorkTick":null,"suppliesExhaustedTick":0 if options.supplies == 0 else null,"firefightersReturnedTick":null}
	var timeline: Array = []
	for tick in range(1, MAX_TICKS + 1):
		var at := id + " tick=" + str(tick)
		input.able = actual.crew
		var reserved := Fire.reserved_crew(state, actual.crew)
		metrics.reservedCrewSeconds += reserved * STEP
		metrics.peakReservedCrew = maxi(metrics.peakReservedCrew, reserved)
		var next: Dictionary = Fire.step(state, input)
		if not check(next.ok, at + ": valid step accepted"):
			break
		state = next.state
		ticks = tick
		var damage: Dictionary = next.damage
		check(_all_finite(next) and damage.hull >= 0.0 and damage.sail >= 0.0 and next.workSeconds >= 0.0 and typeof(next.suppliesSpent) == TYPE_INT and next.suppliesSpent >= 0, at + ": finite nonnegative damage and work recommendations")
		check(typeof(damage.crew) == TYPE_INT and damage.crew >= 0 and damage.crew <= actual.crew, at + ": bounded integer crew debit")
		var hull_loss := minf(float(actual.hull), float(damage.hull))
		var sail_loss := minf(float(actual.sail), float(damage.sail))
		var crew_loss := mini(int(actual.crew), int(damage.crew))
		actual.hull -= hull_loss
		actual.sail -= sail_loss
		actual.crew -= crew_loss
		recommended.hull += float(damage.hull)
		recommended.sail += float(damage.sail)
		recommended.crew += int(damage.crew)
		metrics.hullDamage += hull_loss
		metrics.sailDamage += sail_loss
		metrics.crewLost += crew_loss
		metrics.workSeconds += float(next.workSeconds)
		metrics.suppliesSpent += int(next.suppliesSpent)
		if next.workSeconds > 0.0 and milestones.firstWorkTick == null:
			milestones.firstWorkTick = tick
		if state.supplies == 0 and milestones.suppliesExhaustedTick == null:
			milestones.suppliesExhaustedTick = tick
		if next.extinguished and metrics.extinguishTick == -1:
			metrics.extinguishTick = tick
		var valid_step := validate_case_state(state, actual, metrics, options, at)
		stopped = state.heat == 0.0 and state.assignedFirefighters == 0 and state.pendingFirefighters == 0 and state.transferTicks == 0
		if tick % 60 == 0 or next.extinguished or stopped:
			timeline.append({"tick":tick,"seconds":tick*STEP,"fire":state.duplicate(true),"actual":actual.duplicate(true),"cumulative":metrics.duplicate(true)})
		if stopped:
			milestones.firefightersReturnedTick = tick
		if stopped or not valid_step:
			break
	check(stopped and ticks <= MAX_TICKS and metrics.extinguishTick > 0, id + ": burn and return finish within 80 seconds")
	check(close(metrics.hullDamage + actual.hull, 100.0) and close(metrics.sailDamage + actual.sail, 100.0) and metrics.crewLost + actual.crew == 100, id + ": actual loss and remaining HP/population conserve initial state")
	check(metrics.suppliesSpent + state.supplies == options.supplies and close(metrics.workSeconds, 2.0 * metrics.suppliesSpent + float(state.workCarry)), id + ": stock and effective person-seconds reconcile exactly")
	check(close(float(metrics.crewLost) + float(state.crewDamageCarry), float(recommended.hull)), id + ": integer crew plus retained remainder conserve the equal hull/crew heat coefficient at equal maxima")
	if options.workers == 0:
		check(metrics.workSeconds == 0.0 and metrics.suppliesSpent == 0 and metrics.reservedCrewSeconds == 0.0, id + ": zero-worker control has no hidden labor or spending")
	if options.supplies == 0:
		check(metrics.workSeconds == 0.0 and metrics.suppliesSpent == 0 and state.workCarry == 0.0, id + ": zero stock never creates free work")
	return {
		"id":id,"valid":failures.size() == errors_before,"failures":failures.slice(errors_before),"options":options.duplicate(true),
		"inputs":{"coldInitial":cold_initial,"ignition":{"payload":options.payload,"wetness":moisture.initialWetness,"acceptedTick":0},"assignment":{"crew":options.workers,"able":100,"acceptedTick":0},"initialContext":initial_context,"stepSeconds":STEP,"maxTicks":MAX_TICKS},
		"initialFire":initial,"finalFire":state,"finalActual":actual,"recommendedDamageTotal":recommended,"metrics":metrics,
		"acceptedTicks":ticks,"acceptedSeconds":ticks*STEP,"stoppedAfterAllReturns":stopped,
		"extinctionSecondsBounds":{"lowerExclusive":maxi(0,metrics.extinguishTick-1)*STEP,"upperInclusive":metrics.extinguishTick*STEP},
		"milestones":milestones,"timelineEvery60TicksAndEvents":timeline,
	}

func validate_case_state(state: Dictionary, actual: Dictionary, metrics: Dictionary, options: Dictionary, at: String) -> bool:
	var ok := check(Fire.valid(state) and _all_finite(state) and _all_finite(actual) and _all_finite(metrics), at + ": valid finite state and metrics")
	ok = check(actual.hull >= 0.0 and actual.hull <= 100.0 and actual.sail >= 0.0 and actual.sail <= 100.0 and actual.crew >= 0 and actual.crew <= 100 and state.supplies >= 0, at + ": bounded HP, people and inventory") and ok
	ok = check(state.assignedFirefighters <= actual.crew and state.pendingFirefighters <= actual.crew and Fire.reserved_crew(state,actual.crew) <= actual.crew, at + ": no reserved person beyond current population") and ok
	ok = check(metrics.suppliesSpent + state.supplies == options.supplies and metrics.workSeconds <= 2.0 * options.supplies + EPSILON and close(metrics.workSeconds, 2.0 * metrics.suppliesSpent + float(state.workCarry)), at + ": conserved preparation and person-second budget") and ok
	return ok

func compare_group(payload: String, moisture: String, load: float, supplies: int, members: Array) -> Dictionary:
	var key := {"payload":payload,"moisture":moisture,"flammableLoad":load,"supplies":supplies}
	var result := {"key":key,"dominance":[],"equivalentOnDeclaredAxes":[],"nonDominatedWorkers":[],"againstZeroWorkers":[],"twoVersusMore":[]}
	var rows := {}
	for row: Dictionary in members:
		rows[row.options.workers] = row
		var declared: Dictionary = row.options.duplicate(true)
		declared.erase("workers")
		check(declared == key, row.id + ": comparison never mixes different payload, moisture, load or stock")
	if not check(members.size() == 4 and rows.has(0) and rows.has(2) and rows.has(4) and rows.has(8), str(key) + ": complete declared worker set"):
		return result
	var baseline: Dictionary = rows[0]
	for workers: int in WORKERS:
		var row: Dictionary = rows[workers]
		if not row.valid or not baseline.valid:
			continue
		check(row.inputs.initialContext == baseline.inputs.initialContext and row.inputs.coldInitial == baseline.inputs.coldInitial, row.id + ": matched zero-worker control shares full physical initial inputs")
		var delta := comparison(row.metrics, baseline.metrics)
		result.againstZeroWorkers.append({"workers":workers,"baselineId":baseline.id,"caseId":row.id,"deltasCaseMinusZero":delta.deltas})
		if supplies == 0:
			check(close(row.metrics.hullDamage,baseline.metrics.hullDamage) and close(row.metrics.sailDamage,baseline.metrics.sailDamage) and row.metrics.crewLost == baseline.metrics.crewLost and row.metrics.extinguishTick == baseline.metrics.extinguishTick, row.id + ": no-stock staffing cannot suppress fire compared with matched zero-worker control")
	var dominated := {}
	for i in range(members.size()):
		for j in range(members.size()):
			if i == j or not members[i].valid or not members[j].valid:
				continue
			var a: Dictionary = members[i]
			var b: Dictionary = members[j]
			var relation := comparison(a.metrics, b.metrics)
			if relation.dominates:
				dominated[b.options.workers] = true
				result.dominance.append({"dominantWorkers":a.options.workers,"dominatedWorkers":b.options.workers,"betterAxes":relation.betterAxes,"deltasDominantMinusDominated":relation.deltas})
			elif relation.equivalent and i < j:
				result.equivalentOnDeclaredAxes.append([a.options.workers,b.options.workers])
	for workers: int in WORKERS:
		if rows[workers].valid and not dominated.has(workers):
			result.nonDominatedWorkers.append(workers)
	for workers: int in [4,8]:
		var pair := {"twoWorkerId":rows[2].id,"higherWorkerId":rows[workers].id,"higherWorkers":workers,"classification":"unavailable"}
		if rows[2].valid and rows[workers].valid:
			var relation := comparison(rows[workers].metrics, rows[2].metrics)
			var reverse := comparison(rows[2].metrics, rows[workers].metrics)
			pair.deltasHigherMinusTwo = relation.deltas
			pair.higherWorkerBenefitAxes = relation.betterBenefitAxes
			pair.higherWorkerCostAxes = relation.worseCostAxes
			if relation.dominates:
				pair.classification = "higher-workers-dominates"
			elif reverse.dominates:
				pair.classification = "two-workers-dominates"
			elif relation.equivalent:
				pair.classification = "equivalent"
			elif not relation.betterBenefitAxes.is_empty() and not relation.worseCostAxes.is_empty():
				pair.classification = "tradeoff"
			else:
				pair.classification = "incomparable"
		result.twoVersusMore.append(pair)
	return result

func comparison(a: Dictionary, b: Dictionary) -> Dictionary:
	var no_worse := true
	var better: Array = []
	var benefit: Array = []
	var cost: Array = []
	var deltas := {}
	for axis: String in BENEFIT_MINIMIZE + COST_MINIMIZE:
		var delta := float(a[axis]) - float(b[axis])
		deltas[axis] = delta
		if delta > EPSILON:
			no_worse = false
			if axis in COST_MINIMIZE:
				cost.append(axis)
		if delta < -EPSILON:
			better.append(axis)
			if axis in BENEFIT_MINIMIZE:
				benefit.append(axis)
	return {"dominates":no_worse and not better.is_empty(),"equivalent":no_worse and better.is_empty(),"betterAxes":better,"betterBenefitAxes":benefit,"worseCostAxes":cost,"deltas":deltas}

func verify_comparison_contract() -> void:
	var base := {}
	for axis: String in BENEFIT_MINIMIZE + COST_MINIMIZE:
		base[axis] = 10.0
	check(not comparison(base,base).dominates and comparison(base,base).equivalent, "identical metrics never imply strict dominance")
	var better := base.duplicate(true)
	better.hullDamage = 9.0
	check(comparison(better,base).dominates and not comparison(base,better).dominates, "less actual damage is beneficial")
	better.reservedCrewSeconds = 11.0
	check(not comparison(better,base).dominates and not comparison(base,better).dominates and comparison(better,base).betterBenefitAxes == ["hullDamage"] and comparison(better,base).worseCostAxes == ["reservedCrewSeconds"], "damage benefit and extra actual occupation remain an unweighted tradeoff")
	var cheaper := base.duplicate(true)
	cheaper.suppliesSpent = 9.0
	check(comparison(cheaper,base).dominates, "lower preparation spending is a benefit")
	var noise := base.duplicate(true)
	noise.hullDamage -= EPSILON * 0.5
	check(comparison(noise,base).equivalent and not comparison(noise,base).dominates, "numeric epsilon cannot invent strict dominance")

func _all_finite(value: Variant) -> bool:
	if typeof(value) == TYPE_FLOAT:
		return is_finite(value)
	if typeof(value) == TYPE_DICTIONARY:
		for child: Variant in value.values():
			if not _all_finite(child):
				return false
	elif typeof(value) == TYPE_ARRAY:
		for child: Variant in value:
			if not _all_finite(child):
				return false
	return true

func close(a: float, b: float) -> bool:
	return is_finite(a) and is_finite(b) and absf(a - b) <= EPSILON

func source_hashes() -> Dictionary:
	var result := {}
	for path: String in SOURCES:
		var sha := FileAccess.get_sha256(path)
		check(sha.length() == 64, "read declared source SHA256: " + path)
		result[path] = sha
	return result

func write_report(report: Dictionary) -> void:
	if not check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir())) == OK, "create evidence parent"):
		return
	if not check(not FileAccess.file_exists(output), "output remains absent before writing"):
		return
	var file := FileAccess.open(output, FileAccess.WRITE)
	if not check(file != null, "open fresh report"):
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.flush()
	check(file.get_error() == OK, "complete report write")
	file.close()

func finish() -> void:
	print("SHIP_FIRE_BALANCE_TEST_COMPLETE assertions=", assertions, " cases=", cases.size(), " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
