extends SceneTree
## CPU authority/input regression. No ray projection or viewport pixel claim.
const Encounter = preload("res://modules/naval_simulation/encounter.gd")
const Simulation = preload("res://game/runtime/sailing_simulation.gd")
const Career = preload("res://game/runtime/mingqi_runtime.gd")
const Practice = preload("res://game/runtime/naval_practice_runtime.gd")
const STEP := 1.0 / 60.0
var assertions := 0
var failures := 0

func check(value: bool, detail: String) -> bool:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL mouse course: ", detail)
	return value

func _initialize() -> void:
	_run.call_deferred()

func _finish() -> void:
	print("MOUSE_COURSE_CONTROL_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)

func _wrap(value: float) -> float:
	return atan2(sin(value), cos(value))

func _player(sim: RefCounted) -> Dictionary:
	var packet: Dictionary = sim.encounter.snapshot()
	return Simulation._ship(packet, packet.playerId)

func _pose(sim: RefCounted) -> Dictionary:
	var ship: Dictionary = _player(sim)
	return ship.visual.duplicate(true)

func _speed(sim: RefCounted) -> float:
	var visual: Dictionary = _pose(sim)
	return Vector2(visual.velocity.x, visual.velocity.z).length()

func _course_active(sim: RefCounted) -> bool:
	var status: Dictionary = sim.handling_status()
	var target: Variant = status.get("targetHeading")
	return typeof(target) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(target))

func _target_matches(sim: RefCounted, expected: float) -> bool:
	if not _course_active(sim) or not is_finite(expected): return false
	var status: Dictionary = sim.handling_status()
	return absf(_wrap(float(status.targetHeading) - expected)) < 1.0e-8

func _set_course(sim: RefCounted, point: Dictionary) -> Dictionary:
	var result: Variant = sim.call("set_course", point)
	if not check(result is Dictionary, "set_course returns a command receipt"):
		return {"ok": false}
	return result

func _stop_course(sim: RefCounted) -> Dictionary:
	var result: Variant = sim.call("stop_course")
	if not check(result is Dictionary, "stop_course returns a command receipt"):
		return {"ok": false}
	return result

func _point(sim: RefCounted, dx: float = 1000.0, dz: float = 0.0) -> Dictionary:
	var visual: Dictionary = _pose(sim)
	return {"x": float(visual.position.x) + dx, "z": float(visual.position.z) + dz}

func _make_sim() -> RefCounted:
	var native: RefCounted = Encounter.new({
		"mode": "continuous", "referenceHandling": true,
		"controllableShipIds": ["player", "other"], "oceanWaves": [],
		"sampleTerrainHeight": func(_x: float, _z: float) -> float: return -80.0,
		"wind": {"direction": {"x": 1.0, "y": 0.0}, "speed": 12.0},
		"ships": [
			{"id": "player", "kind": "fuchuan", "team": "player", "position": {"x": 0.0, "z": 0.0}, "heading": 0.0, "speed": 0.0, "sailDeployment": 0.0},
			{"id": "other", "kind": "fuchuan", "team": "player", "position": {"x": -10000.0, "z": -10000.0}, "heading": 0.0, "speed": 0.0, "sailDeployment": 0.0},
		],
	})
	check(native.last_error.is_empty(), "actual continuous deep-water encounter accepts healthy headwind fixture")
	var sim: RefCounted = Simulation.new(native)
	sim.set_handling_mode("assisted")
	return sim

func _advance(sim: RefCounted, ticks: int) -> Dictionary:
	var previous: Dictionary = _player(sim)
	var max_heading_delta := 0.0
	var max_rudder_delta := 0.0
	var finite := true
	for tick in ticks:
		sim.advance(STEP)
		var current: Dictionary = _player(sim)
		max_heading_delta = maxf(max_heading_delta, absf(_wrap(float(current.visual.heading) - float(previous.visual.heading))))
		max_rudder_delta = maxf(max_rudder_delta, absf(float(current.rudder) - float(previous.rudder)))
		finite = finite and is_finite(current.visual.heading) and is_finite(current.visual.position.x) and is_finite(current.visual.position.z) and absf(current.rudder) <= 1.0
		previous = current
	return {"maxHeadingDelta": max_heading_delta, "maxRudderDelta": max_rudder_delta, "finite": finite}

func _movement(sim: RefCounted) -> void:
	# Removing real mouse propulsion, teleporting the hull, or delegating to
	# wind-dependent native navigation must break these observable assertions.
	var before: Dictionary = _pose(sim)
	check(_set_course(sim, {"x": 1000.0, "z": 0.0}).get("ok", false), "mouse-only headwind course is accepted from rest")
	check(_pose(sim) == before, "course click does not directly change heading, position or velocity")
	check(_course_active(sim), "accepted mouse course exposes its target heading")
	var start: Dictionary = _advance(sim, 360)
	var after: Dictionary = _player(sim)
	check(after.visual.position.x > 1.0 and _speed(sim) > 0.2, "six accepted seconds produce actual headwind forward progress without held keys")
	check(absf(_wrap(after.visual.heading)) < 0.1 and not after.has("navigation"), "headwind course keeps requested heading without native tack navigation")
	check(after.sailDeployment >= 0.8 and after.autoTrim, "mouse course raises useful sails and uses automatic trim")
	check(start.finite and start.maxHeadingDelta < 0.02, "headwind startup retains finite bounded physical steps")
	var clicked_pose: Dictionary = _pose(sim)
	check(_set_course(sim, _point(sim, 1000.0, 1000.0)).get("ok", false), "forty-five-degree mouse heading is accepted")
	check(_pose(sim) == clicked_pose, "new heading click changes intent rather than hull pose")
	check(_target_matches(sim, PI / 4.0), "target heading is derived from authoritative current player position")
	var initial_error: float = absf(_wrap(float(clicked_pose.heading) - PI / 4.0))
	var turning: Dictionary = _advance(sim, 480)
	var error: float = absf(_wrap(float(_pose(sim).heading) - PI / 4.0))
	check(error < initial_error * 0.7, "eight seconds of actual forces reduce forty-five-degree course error")
	check(turning.finite and turning.maxHeadingDelta < 0.02 and turning.maxRudderDelta < 0.25, "course controller applies smooth bounded rudder and physical yaw each fixed step")
	var released: Dictionary = _pose(sim)
	_advance(sim, 120)
	check(_course_active(sim) and _pose(sim).position != released.position, "course persists and keeps moving without a held mouse or keyboard input")
	var stopping_pose: Dictionary = _pose(sim)
	var stopping_speed: float = _speed(sim)
	check(_stop_course(sim).get("ok", false), "stop sailing accepts a real stop intent")
	check(not _course_active(sim) and _pose(sim) == stopping_pose, "stop cancels course without directly zeroing or moving authority")
	_advance(sim, 1)
	check(_speed(sim) > 0.0 and _speed(sim) <= stopping_speed + 0.02, "first stop step preserves motion and starts bounded deceleration")
	_advance(sim, 1800)
	check(_speed(sim) < 0.05 and _player(sim).sailDeployment <= 0.05, "furled stop converges to rest under real hull braking")
	sim.set_paused(true)

func _invalid_and_pause() -> void:
	var sim: RefCounted = _make_sim()
	check(_set_course(sim, _point(sim, 1000.0, 1000.0)).get("ok", false), "validation fixture starts a legal course")
	var legal: Dictionary = sim.handling_status().duplicate(true)
	var current: Dictionary = _pose(sim)
	var invalid: Array[Dictionary] = [{"z": 10.0}, {"x": NAN, "z": 1.0}, {"x": 1.0, "z": INF}, {"x": "east", "z": 1.0}, {"x": current.position.x, "z": current.position.z}]
	for point: Dictionary in invalid:
		check(not _set_course(sim, point).get("ok", true), "invalid or zero-direction point is rejected")
		check(sim.handling_status() == legal and _pose(sim) == current, "rejected point preserves the old legal course and authority")
	_advance(sim, 30)
	var heading: float = float(sim.handling_status().get("targetHeading", INF))
	sim.set_paused(true)
	var frozen: Dictionary = sim.encounter.snapshot().duplicate(true)
	sim.advance(30.0)
	check(sim.encounter.snapshot() == frozen, "paused course consumes no authority time or motion")
	check(not _set_course(sim, _point(sim)).get("ok", true), "paused simulation rejects replacement mouse intent")
	sim.set_held("KeyA", true)
	sim.set_paused(false)
	check(_target_matches(sim, heading), "pause/resume retains the legal course rather than stale held input")
	_advance(sim, 30)
	check(sim.encounter.snapshot().time > frozen.time and _course_active(sim), "resumed course continues only in newly accepted time")
	sim.set_paused(true)

func _ownership() -> void:
	for code: String in ["KeyW", "KeyA", "KeyD"]:
		var sim: RefCounted = _make_sim()
		_set_course(sim, _point(sim))
		sim.set_held(code, true)
		_advance(sim, 1)
		check(not _course_active(sim), "manual " + code + " takes control and cancels mouse course")
		sim.set_held(code, false)
		sim.set_paused(true)
	var switched: RefCounted = _make_sim()
	_set_course(switched, _point(switched))
	check(switched.encounter.setPlayerId("other").get("ok", false), "public native player switch is accepted")
	switched.refresh_snapshot()
	check(not _course_active(switched), "player identity switch clears former ship course")
	switched.set_paused(true)
	var navigation: RefCounted = _make_sim()
	_set_course(navigation, _point(navigation))
	check(navigation.encounter.navigate("player", {"x": 500.0, "z": 500.0}).get("ok", false), "public native navigation takes ownership")
	navigation.refresh_snapshot()
	check(not _course_active(navigation), "native navigation clears the independent mouse course")
	navigation.set_paused(true)
	var restored: RefCounted = _make_sim()
	_set_course(restored, _point(restored))
	var initial: Dictionary = restored.encounter.config.duplicate(true)
	check(restored.encounter.reset(initial), "public reset reconstructs actual native authority")
	restored.refresh_snapshot()
	check(not _course_active(restored), "restored native identity clears stale mouse intent")
	restored.set_paused(true)

func _set_policy(sim: RefCounted, field: String) -> void:
	var policy: Dictionary = sim.encounter.policy.duplicate(true)
	policy[field] = [sim.encounter.snapshot().playerId]
	var result: Dictionary = sim.encounter.reconcile_ships(sim.encounter.config.ships, policy)
	check(result.get("ok", false), "public reconciliation validates " + field + " fixture")
	sim.refresh_snapshot()

func _authority_gates() -> void:
	for field: String in ["lockedShipIds", "disabledMotionShipIds", "capturedShipIds"]:
		var sim: RefCounted = _make_sim()
		_set_policy(sim, field)
		var before: Dictionary = sim.encounter.snapshot().duplicate(true)
		check(not _set_course(sim, _point(sim)).get("ok", true), field + " denies mouse control")
		check(sim.encounter.snapshot() == before and not _course_active(sim), field + " rejection preserves every native field")
		sim.set_paused(true)
	var dead: RefCounted = _make_sim()
	check(dead.encounter.update_ship_stats("player", {"hull": 0.0}).get("ok", false), "public lethal hull fixture reaches actual terminal authority")
	dead.encounter.step(STEP)
	dead.refresh_snapshot()
	var terminal: Dictionary = dead.encounter.snapshot().duplicate(true)
	check(terminal.status == "defeat" and not _set_course(dead, _point(dead)).get("ok", true), "real defeat denies mouse sailing")
	check(dead.encounter.snapshot() == terminal, "terminal denial does not rewrite authority")
	dead.set_paused(true)

func _career_fixture() -> RefCounted:
	var runtime: RefCounted = Career.new()
	var result: Dictionary = runtime.configure(func(_x: float, _z: float) -> float: return -80.0)
	check(result.get("ok", false), "actual career configures through public domain/runtime")
	return runtime

func _runtime_point(runtime: RefCounted) -> Dictionary:
	return _point(runtime.simulation)

func _runtime_gates() -> void:
	var career: RefCounted = _career_fixture()
	var port: Dictionary = career.snapshot().duplicate(true)
	check(port.campaign.currentPortId != null, "career fixture begins in its actual port")
	check(not career.command({"type": "mouse-course", "point": _runtime_point(career)}).get("ok", true), "in-port career denies mouse sailing before departure")
	check(career.snapshot().campaign == port.campaign and career.snapshot().naval == port.naval, "in-port denial preserves domain/native authority")
	var accepted: Dictionary = career.command({"type": "accept-convoy", "commandId": "mouse-course-accept", "expectedRevision": career.snapshot().campaign.revision})
	check(accepted.get("ok", false), "career accepts its real convoy through domain command")
	var departed: Dictionary = career.command({"type": "depart", "commandId": "mouse-course-depart", "expectedRevision": career.snapshot().campaign.revision})
	if not check(departed.get("ok", false) and career.snapshot().campaign.currentPortId == null, "public departure releases actual career port gate"):
		career.dispose()
		return
	var before: Dictionary = _pose(career.simulation)
	check(career.command({"type": "mouse-course", "point": _runtime_point(career)}).get("ok", false), "departed career adapts mouse-course into actual simulation")
	check(_pose(career.simulation) == before and _course_active(career.simulation), "runtime click sets a course without changing hull pose")
	for reason: String in ["player", "menu", "blur", "loading", "tactical"]:
		career.set_pause(reason, true)
		var frozen: Dictionary = career.snapshot().duplicate(true)
		check(not career.command({"type": "mouse-course", "point": _runtime_point(career)}).get("ok", true) and not career.command({"type": "stop-sailing"}).get("ok", true), reason + " rejects runtime sailing intents while paused")
		career.advance(10.0)
		check(career.snapshot().naval == frozen.naval and career.snapshot().campaign == frozen.campaign, reason + " freezes native and career authority")
		career.set_pause(reason, false)
	var ordinary_policy: Dictionary = career.simulation.encounter.policy.duplicate(true)
	for field: String in ["lockedShipIds", "disabledMotionShipIds", "capturedShipIds"]:
		_set_policy(career.simulation, field)
		var gated: Dictionary = career.snapshot().duplicate(true)
		check(not career.command({"type": "mouse-course", "point": _runtime_point(career)}).get("ok", true), "career public command enforces " + field)
		check(career.snapshot().naval == gated.naval and career.snapshot().campaign == gated.campaign, "career " + field + " denial preserves native/business authority")
		var cleared: Dictionary = career.simulation.encounter.reconcile_ships(career.simulation.encounter.config.ships, ordinary_policy)
		check(cleared.get("ok", false), "public reconciliation removes completed gate fixture")
		career.simulation.refresh_snapshot()
	check(career.command({"type": "stop-sailing"}).get("ok", false) and not _course_active(career.simulation), "departed runtime stop-sailing cancels mouse intent")
	var career_id: String = career.snapshot().naval.playerId
	check(career.simulation.encounter.update_ship_stats(career_id, {"hull": 0.0}).get("ok", false), "public career lethal fixture passes native validator")
	career.advance(STEP)
	var defeated: Dictionary = career.snapshot().duplicate(true)
	check(defeated.naval.status == "defeat" and defeated.runtime.pauseReasons.has("result"), "career lethal fixture reaches actual domain/runtime defeat")
	check(not career.command({"type": "mouse-course", "point": _runtime_point(career)}).get("ok", true) and career.snapshot().naval == defeated.naval and career.snapshot().campaign == defeated.campaign, "career terminal command cannot revive or move defeated authority")
	career.dispose()
	var practice: RefCounted = Practice.new()
	check(practice.configure(func(_x: float, _z: float) -> float: return -80.0, {"mode": "sail"}).get("ok", false), "actual standalone sail practice configures")
	check(practice.command({"type": "mouse-course", "point": _runtime_point(practice)}).get("ok", false), "practice accepts public mouse-course")
	for reason: String in ["player", "menu", "blur", "loading", "chart"]:
		practice.set_pause(reason, true)
		var frozen: Dictionary = practice.snapshot().naval.duplicate(true)
		check(not practice.command({"type": "mouse-course", "point": _runtime_point(practice)}).get("ok", true) and not practice.command({"type": "stop-sailing"}).get("ok", true), "practice " + reason + " denies paused sailing intents")
		practice.advance(10.0)
		check(practice.snapshot().naval == frozen, "practice " + reason + " freezes actual motion")
		practice.set_pause(reason, false)
	check(practice.command({"type": "stop-sailing"}).get("ok", false) and not _course_active(practice.simulation), "practice public stop-sailing cancels course")
	var practice_id: String = practice.snapshot().naval.playerId
	check(practice.simulation.encounter.update_ship_stats(practice_id, {"crew": 0.0}).get("ok", false), "public practice fixture removes operational crew")
	practice.simulation.refresh_snapshot()
	var uncrewed: Dictionary = practice.snapshot().naval.duplicate(true)
	check(not practice.command({"type": "mouse-course", "point": _runtime_point(practice)}).get("ok", true) and practice.snapshot().naval == uncrewed, "practice operational gate denies zero-crew mouse control")
	check(practice.command({"type": "restart"}).get("ok", false), "actual practice restart clears the crew fixture")
	practice_id = practice.snapshot().naval.playerId
	check(practice.simulation.encounter.update_ship_stats(practice_id, {"hull": 0.0}).get("ok", false), "public practice lethal fixture passes native validator")
	practice.advance(STEP)
	var practice_terminal: Dictionary = practice.snapshot().naval.duplicate(true)
	check(practice_terminal.status == "defeat" and not practice.command({"type": "mouse-course", "point": _runtime_point(practice)}).get("ok", true), "practice actual defeat denies mouse sailing")
	check(practice.snapshot().naval == practice_terminal, "practice terminal denial preserves all native authority")
	practice.dispose()

func _run() -> void:
	var sim: RefCounted = _make_sim()
	if not check(sim.has_method("set_course") and sim.has_method("stop_course"), "real Simulation owns mouse set_course/stop_course API"):
		sim.set_paused(true)
		_finish()
		return
	_movement(sim)
	_invalid_and_pause()
	_ownership()
	_authority_gates()
	_runtime_gates()
	_finish()
