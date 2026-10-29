extends SceneTree
## Controlled ignition extension only. No live ballistic/campaign/production claim.
## Catches r1 fallback, early/nonadjacent spread, triple work/DOT, and projector feedback.
const DEMO_PATH: String = "res://game/research/demos/ship_fire_control_experiment.gd"
const Fire = preload("res://modules/naval_simulation/combat/fire_control.gd")
const Spread = preload("res://modules/naval_simulation/combat/fire_spread.gd")
const STEP: float = 1.0 / 60.0
const SCOPE: String = "controlled ignition candidate; no live ballistic/campaign/production claim"
const IDS: Array[String] = ["baseline", "candidate"]
const ZONES: Array[String] = ["bow", "mid", "stern"]
var assertions: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, reason: String) -> bool:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL LAB SHIP FIRE ZONES: ", reason)
	return value

func near(actual: float, expected: float, reason: String, tolerance: float = 0.00000001) -> void:
	check(absf(actual - expected) <= tolerance, reason + " actual=" + str(actual))

func _finish() -> void:
	print("LABORATORY_SHIP_FIRE_ZONES assertions=%d failures=%d" % [assertions, failures])
	quit(0 if failures == 0 else 1)

func _cleanup(demo: Node3D, viewport: SubViewport = null) -> void:
	if is_instance_valid(demo):
		demo.dispose()
		demo.free()
	if is_instance_valid(viewport):
		viewport.free()

func _choices(spec: Array, id: String) -> Array:
	var result: Array = []
	for control: Dictionary in spec:
		if str(control.get("id", "")) != id:
			continue
		for choice: Dictionary in control.get("choices", []):
			result.append(choice.get("value"))
	result.sort()
	return result

func _ship(snapshot: Dictionary, id: String) -> Dictionary:
	for ship: Dictionary in snapshot.get("visual", {}).get("ships", []):
		if str(ship.get("id", "")) == id:
			return ship
	return {}

func _zone_shape(snapshot: Dictionary) -> bool:
	var valid: bool = true
	for id: String in IDS:
		var lane: Dictionary = snapshot.get("lanes", {}).get(id, {})
		valid = check(Spread.valid(lane.get("fireControl")), id + " retains the sole valid r2 state, without a duplicate scalar heat") and valid
		valid = check(lane.get("spreadCount") is int and int(lane.get("spreadCount", -1)) >= 0 and lane.get("spreadEvents") is Array, id + " exposes an integer cumulative count and event ledger") and valid
	return valid

func _projection(snapshot: Dictionary, label: String) -> void:
	for id: String in IDS:
		var lane: Dictionary = snapshot.lanes[id]
		var ship: Dictionary = _ship(snapshot, id)
		check(ship.get("fireControl", {}) == Spread.summary(lane.fireControl), label + " " + id + " projects one r1 summary for existing consumers")
		check(ship.get("fireSpread", {}) == lane.fireControl, label + " " + id + " projects the complete authoritative r2 shares")
		var events: Array = lane.spreadEvents
		check(events.size() <= 32 and int(lane.spreadCount) >= events.size(), label + " " + id + " retains at most the last 32 cumulative propagation receipts")
		for event: Variant in events:
			if not check(event is Dictionary, label + " propagation receipt is a dictionary"):
				continue
			var receipt: Dictionary = event
			check(receipt.get("fromZone") is String and receipt.get("toZone") is String and receipt.fromZone in ZONES and receipt.toZone in ZONES, label + " propagation receipt has typed real zone IDs")
			check(receipt.get("heat") is float and float(receipt.get("heat", -1.0)) == 12.0, label + " propagation receipt transfers exactly twelve heat")
			check(absi(ZONES.find(str(receipt.get("fromZone", ""))) - ZONES.find(str(receipt.get("toZone", "")))) == 1, label + " propagation receipt connects adjacent zones only")

func _oracles(snapshot: Dictionary) -> Dictionary:
	# Build independent r1 states, rather than deriving expected heat/cost from r2.
	var result: Dictionary = {}
	for id: String in IDS:
		var lane: Dictionary = snapshot.lanes[id]
		var ignition: Dictionary = Fire.ignite(Fire.initial(24), "thorn-ball", 0.0)
		var assignment: Dictionary = Fire.assign(ignition.state, 4 if id == "candidate" else 0, int(lane.crew))
		result[id] = {"state":assignment.state, "hull":float(lane.hull), "maxHull":float(lane.maxHull), "sail":float(lane.sail), "maxSail":float(lane.maxSail), "crew":int(lane.crew), "maxCrew":int(lane.maxCrew), "damage":{"hull":0.0,"sail":0.0,"crew":0}, "workSeconds":0.0, "lastWorkSeconds":0.0, "suppliesSpent":0, "reservedCrew":Fire.reserved_crew(assignment.state, int(lane.crew)), "extinguishedAt":-1.0}
	return result

func _advance(demo: Node3D, ticks: int, oracles: Dictionary = {}) -> void:
	if not check(ticks >= 0 and ticks <= 3000, "fixture has a bounded accepted-tick budget"):
		return
	var initial_tick: int = int(demo.inspection_snapshot().tick)
	for index: int in range(ticks):
		demo.advance(STEP)
		for id: String in oracles:
			var oracle: Dictionary = oracles[id]
			var context: Dictionary = {"able":oracle.crew,"maxHull":oracle.maxHull,"maxSail":oracle.maxSail,"maxCrew":oracle.maxCrew,"rain01":0.0,"flammableLoad":0.0}
			var next: Dictionary = Fire.step(oracle.state, context)
			var hull_loss: float = minf(float(oracle.hull), float(next.damage.hull))
			var sail_loss: float = minf(float(oracle.sail), float(next.damage.sail))
			var crew_loss: int = mini(int(oracle.crew), int(next.damage.crew))
			oracle.state = next.state
			oracle.hull = maxf(0.0, float(oracle.hull) - hull_loss)
			oracle.sail = maxf(0.0, float(oracle.sail) - sail_loss)
			oracle.crew = maxi(0, int(oracle.crew) - crew_loss)
			oracle.damage.hull += hull_loss
			oracle.damage.sail += sail_loss
			oracle.damage.crew += crew_loss
			oracle.workSeconds += float(next.workSeconds)
			oracle.lastWorkSeconds = float(next.workSeconds)
			oracle.suppliesSpent += int(next.suppliesSpent)
			oracle.reservedCrew = int(next.reservedCrew)
			if next.extinguished:
				oracle.extinguishedAt = float(initial_tick + index + 1) * STEP

func _compare_oracles(snapshot: Dictionary, oracles: Dictionary, label: String) -> void:
	for id: String in IDS:
		var lane: Dictionary = snapshot.lanes[id]
		var oracle: Dictionary = oracles[id]
		var summary: Dictionary = Spread.summary(lane.fireControl)
		for field: String in ["heat", "fuelSeconds", "wetness", "crewDamageCarry", "workCarry"]:
			near(float(summary[field]), float(oracle.state[field]), label + " " + id + " one-step r1 " + field)
		for field: String in ["assignedFirefighters", "pendingFirefighters", "transferTicks", "supplies"]:
			check(summary[field] is int and summary[field] == oracle.state[field], label + " " + id + " shared integer " + field)
		for field: String in ["hull", "sail", "workSeconds", "lastWorkSeconds", "extinguishedAt"]:
			near(float(lane[field]), float(oracle[field]), label + " " + id + " single account " + field)
		for field: String in ["crew", "reservedCrew", "suppliesSpent"]:
			check(lane[field] is int and lane[field] == oracle[field], label + " " + id + " one actual " + field + " account")
		near(float(lane.damage.hull), float(oracle.damage.hull), label + " " + id + " one hull DOT integral")
		near(float(lane.damage.sail), float(oracle.damage.sail), label + " " + id + " one sail DOT integral")
		check(lane.damage.crew == oracle.damage.crew, label + " " + id + " one integer crew DOT integral")
		check(int(summary.supplies) + int(lane.suppliesSpent) == 24, label + " " + id + " conserves the shared 24 preparation stores")
	_projection(snapshot, label)

func _run() -> void:
	if not check(FileAccess.file_exists(DEMO_PATH), "existing controlled fire experiment is available"):
		_finish()
		return
	var script: Script = load(DEMO_PATH)
	if not check(script != null, "existing controlled fire experiment loads"):
		_finish()
		return
	var demo: Node3D = script.new()
	var default_receipt: Dictionary = demo.configure({"paused":true})
	check(default_receipt.get("ok", false) and Fire.valid(demo.inspection_snapshot().get("lanes", {}).get("baseline", {}).get("fireControl")), "default experiment retains its r1 behavior")
	var receipt: Dictionary = demo.configure({"fire_model":"zones","ignition_zone":"stern","paused":true})
	# First RED is a single missing-feature assertion, with no missing-module preload.
	if not check(receipt.get("ok", false), "FIRE_ZONE_DEMO_MISSING: existing experiment must accept zones and stern ignition"):
		_cleanup(demo)
		_finish()
		return
	check(demo.get_child_count() == 0, "pre-tree zones configuration owns no renderer")
	check(demo.get_default_options().get("fire_model", "") == "r1", "new model selection preserves the r1 default")
	var spec: Array = demo.control_spec()
	check(_choices(spec, "fire_model") == ["r1", "zones"], "model control exposes both retained r1 and spatial zones")
	check(_choices(spec, "ignition_zone") == ["bow", "mid", "stern"], "ignition control exposes all three real regions independent of choice order")
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1100, 720)
	viewport.own_world_3d = true
	root.add_child(viewport)
	viewport.add_child(demo)
	for _frame: int in range(2):
		await process_frame
	var initial: Dictionary = demo.inspection_snapshot()
	if not check(initial.get("ready", false), "zones fixture initializes real ship, sea and read-only presentation") or not _zone_shape(initial):
		_cleanup(demo, viewport)
		_finish()
		return
	check(initial.scope == SCOPE and initial.topic == "ship-fire-control", "spatial extension retains controlled ignition scope")
	check(initial.tick == 0 and initial.time == 0.0 and initial.fixed_step == STEP, "zones start at fixed deterministic zero tick")
	check(initial.resources.storage == 0 and initial.events.is_empty(), "zones create neither campaign storage nor fabricated ballistic events")
	for id: String in IDS:
		var lane: Dictionary = initial.lanes[id]
		check(lane.fireControl.heatByZone == [0.0,0.0,28.0] and lane.fireControl.exposureTicks == [0,0,0], id + " initially ignites only selected stern with no exposure credit")
		check(lane.fireControl.supplies == 24 and lane.fireControl.fuelSeconds == 36.0 and lane.spreadCount == 0 and lane.spreadEvents.is_empty(), id + " starts one common fuel/inventory account and clean propagation ledger")
	check(initial.lanes.baseline.fireControl.pendingFirefighters == 0 and initial.lanes.candidate.fireControl.pendingFirefighters == 4, "both r2 lanes retain actual zero/four-person allocation")
	_projection(initial, "initial")
	var untouched: Dictionary = initial.duplicate(true)
	var returned_ship: Dictionary = _ship(initial, "baseline")
	returned_ship.fireSpread.heatByZone[2] = 999.0
	returned_ship.fireControl.heat = 999.0
	check(demo.inspection_snapshot() == untouched, "returned visual projection cannot mutate r2 authority or subsequent inspection")
	demo.advance(0.25)
	demo.set_camera_mode("near")
	var paused: Dictionary = demo.inspection_snapshot()
	check(paused.tick == 0 and paused.lanes == untouched.lanes and paused.visual == untouched.visual, "pause and same-tick camera switch preserve r2 shares, exposure, accounts and visual state")
	demo.set_camera_mode("overview")
	demo.set_camera_mode("baseline-near")
	var baseline_camera: Dictionary = demo.inspection_snapshot()
	check(baseline_camera.camera_mode == "baseline-near" and baseline_camera.lanes == untouched.lanes and baseline_camera.visual == untouched.visual and baseline_camera.tick == 0, "unattended close observation selects its camera without advancing either lane")
	demo.set_camera_mode("overview")
	var valid_before: Dictionary = demo.inspection_snapshot()
	for invalid: Dictionary in [{"fire_model":"unknown"},{"ignition_zone":"side"},{"fire_model":true},{"ignition_zone":0}]:
		check(not demo.configure(invalid).get("ok", true) and demo.inspection_snapshot() == valid_before, "invalid spatial option rejects atomically: " + str(invalid))
	check(not demo.set_parameter("fire_model", "zones").get("reset_required", true), "same model needs no reset")
	check(demo.set_parameter("fire_model", "r1").get("reset_required", false), "model switch requests clean reset")
	check(demo.set_parameter("ignition_zone", "bow").get("reset_required", false), "zone switch requests clean reset")
	check(demo.inspection_snapshot() == valid_before, "pending choices do not edit running r2 authority")
	var oracles: Dictionary = _oracles(untouched)
	demo.set_paused(false)
	demo.advance(STEP * 0.5)
	check(demo.inspection_snapshot().tick == 0 and demo.inspection_snapshot().lanes == untouched.lanes, "half accepted tick cannot advance either r2 lane")
	# Reset the half-step so the oracle and demo accept exactly the same ticks.
	check(demo.reset_experiment({"paused":false}).get("ok", false), "spatial half-step fixture resets cleanly")
	_advance(demo, 120, oracles)
	var transferred: Dictionary = demo.inspection_snapshot()
	check(transferred.tick == 120 and transferred.lanes.candidate.fireControl.transferTicks == 0 and transferred.lanes.candidate.workSeconds == 0.0, "120 shared ticks complete transfer without free work")
	near(float(Spread.summary(transferred.lanes.baseline.fireControl).heat), 32.0, "two-second unattended heat is integrated once")
	_compare_oracles(transferred, oracles, "transfer")
	_advance(demo, 1, oracles)
	var first_work: Dictionary = demo.inspection_snapshot()
	near(float(first_work.lanes.candidate.lastWorkSeconds), 4.0 * STEP, "four people earn one work charge per accepted tick")
	_compare_oracles(first_work, oracles, "first work")
	_advance(demo, 238, oracles)
	var before_spread: Dictionary = demo.inspection_snapshot()
	check(before_spread.tick == 359 and before_spread.lanes.baseline.spreadCount == 0 and before_spread.lanes.baseline.fireControl.heatByZone[1] == 0.0 and before_spread.lanes.baseline.fireControl.exposureTicks[1] == 359, "359 complete ticks cannot ignite mid")
	_advance(demo, 1, oracles)
	var spread: Dictionary = demo.inspection_snapshot()
	check(spread.tick == 360 and spread.lanes.baseline.spreadCount == 1 and spread.lanes.baseline.spreadEvents.size() == 1, "exact six-second tick commits one cumulative propagation receipt")
	check(spread.lanes.baseline.fireControl.heatByZone[0] == 0.0 and spread.lanes.baseline.fireControl.heatByZone[1] == 12.0, "stern reaches adjacent mid while bow remains cold")
	near(float(spread.lanes.baseline.fireControl.heatByZone[2]), 28.0, "stern pays twelve heat without creating another source")
	check(spread.lanes.baseline.spreadEvents[0] == {"fromZone":"stern","toZone":"mid","heat":12.0}, "stern receipt identifies the actual transfer")
	check(spread.lanes.candidate.spreadCount == 0 and spread.lanes.candidate.fireControl.heatByZone[0] == 0.0 and spread.lanes.candidate.fireControl.heatByZone[1] == 0.0, "one funded four-person team prevents its own propagation")
	_compare_oracles(spread, oracles, "six seconds")
	demo.set_camera_mode("near")
	var same_tick: Dictionary = demo.inspection_snapshot()
	check(same_tick.tick == spread.tick and same_tick.lanes == spread.lanes and same_tick.visual == spread.visual, "running same-tick camera switch cannot reintegrate or project changes into r2")
	demo.set_camera_mode("overview")
	_advance(demo, 1800, oracles)
	var completed: Dictionary = demo.inspection_snapshot()
	if float(Spread.summary(completed.lanes.baseline.fireControl).heat) > 0.0:
		_advance(demo, 1, oracles)
		completed = demo.inspection_snapshot()
	_compare_oracles(completed, oracles, "fuel completion")
	check(Spread.summary(completed.lanes.baseline.fireControl).heat == 0.0 and Spread.summary(completed.lanes.candidate.fireControl).heat == 0.0, "bounded 36-second run reaches cold accounts")
	check(completed.lanes.candidate.extinguishedAt > 0.0 and completed.lanes.candidate.extinguishedAt < 36.0 and completed.lanes.candidate.spreadCount == 0, "funded candidate extinguishes before any candidate propagation")
	near(float(completed.lanes.candidate.workSeconds), 32.0, "complete suppression earns 32 shared person-seconds", 0.0000001)
	check(completed.lanes.candidate.suppliesSpent == 16 and completed.lanes.candidate.fireControl.supplies == 8, "four-person suppression spends sixteen shared stores, not three inventories")
	near(float(completed.lanes.candidate.damage.hull), 1.504, "complete candidate incurs one hand-integrated hull DOT account", 0.0000001)
	demo.set_paused(true)
	var stopped: Dictionary = demo.inspection_snapshot()
	demo.advance(0.25)
	check(demo.inspection_snapshot() == stopped, "pause also freezes completed propagation history, work and finite stores")
	check(demo.reset_experiment({"ignition_zone":"mid","paused":false}).get("ok", false), "mid ignition reuses the same experiment")
	var mid_initial: Dictionary = demo.inspection_snapshot()
	for id: String in IDS:
		check(mid_initial.lanes[id].fireControl.heatByZone == [0.0,28.0,0.0] and mid_initial.lanes[id].fireControl.exposureTicks == [0,0,0] and mid_initial.lanes[id].fireControl.supplies == 24 and mid_initial.lanes[id].suppliesSpent == 0 and mid_initial.lanes[id].workSeconds == 0.0 and mid_initial.lanes[id].spreadCount == 0 and mid_initial.lanes[id].spreadEvents.is_empty(), id + " reset clears propagation/work and restores one inventory")
	var mid_oracles: Dictionary = _oracles(mid_initial)
	_advance(demo, 360, mid_oracles)
	var mid_spread: Dictionary = demo.inspection_snapshot()
	check(mid_spread.lanes.baseline.spreadCount == 2 and mid_spread.lanes.baseline.spreadEvents.size() == 2, "six-second mid ignition records both adjacent transfers cumulatively")
	check(mid_spread.lanes.baseline.fireControl.heatByZone[0] == 12.0 and mid_spread.lanes.baseline.fireControl.heatByZone[2] == 12.0, "mid shares exactly twelve heat to each end")
	near(float(mid_spread.lanes.baseline.fireControl.heatByZone[1]), 16.0, "both transfers debit the same mid heat budget")
	_compare_oracles(mid_spread, mid_oracles, "two-end mid spread")
	check(demo.reset_experiment({"ignition_zone":"bow","paused":false}).get("ok", false), "bow ignition reuses the same experiment")
	var bow_initial: Dictionary = demo.inspection_snapshot()
	check(bow_initial.lanes.baseline.fireControl.heatByZone == [28.0,0.0,0.0], "bow orientation selects the opposite end from stern")
	var bow_oracles: Dictionary = _oracles(bow_initial)
	_advance(demo, 360, bow_oracles)
	var bow_spread: Dictionary = demo.inspection_snapshot()
	check(bow_spread.lanes.baseline.spreadCount == 1 and bow_spread.lanes.baseline.spreadEvents == [{"fromZone":"bow","toZone":"mid","heat":12.0}] and bow_spread.lanes.baseline.fireControl.heatByZone[2] == 0.0, "bow spreads toward mid without mirroring the stern ID or skipping to stern")
	_compare_oracles(bow_spread, bow_oracles, "bow orientation")
	demo.dispose()
	var disposed: Dictionary = demo.inspection_snapshot()
	check(demo.get_child_count() == 0 and disposed.disposed and disposed.lanes.is_empty() and disposed.visual.is_empty() and not disposed.resources.production_sea and not disposed.resources.candidate and disposed.resources.storage == 0, "dispose releases owned zone state, renderers and resource accounts")
	_cleanup(demo, viewport)
	await process_frame
	_finish()
