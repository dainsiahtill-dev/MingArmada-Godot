extends SceneTree
## Public queued controls and the real Mingqi sail widget must retain casual input.
const Encounter = preload("res://modules/naval_simulation/encounter.gd")
const Simulation = preload("res://game/runtime/sailing_simulation.gd")
const Runtime = preload("res://game/runtime/mingqi_runtime.gd")
const Interface = preload("res://game/ui/mingqi/mingqi_interface.gd")
const STEP := 1.0 / 60.0
const WIND := {"direction":{"x":1.0,"y":0.0},"speed":12.0}
var assertions := 0
var failures := 0

class MemorySlot extends RefCounted:
	var writes := 0
	func read_checkpoint() -> Dictionary: return {"ok":false,"reason":"save-not-found"}
	func write_checkpoint(_raw: String) -> Dictionary:
		writes += 1
		return {"ok":false,"reason":"test-write-forbidden"}

func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", detail)

func _player(native: Dictionary) -> Dictionary:
	return Simulation._ship(native, native.get("playerId", "player"))

func _controls(ship: Dictionary, deployment: float) -> Dictionary:
	return {"type":"controls", "shipId":ship.id, "rudder":ship.rudder,
		"sailDeployment":deployment, "sailAngle":ship.sailAngle, "autoTrim":ship.autoTrim}

func _fixture(kind: String = "fuchuan", enhanced: bool = false) -> RefCounted:
	var native := Encounter.new({
		"mode":"continuous", "routePlanning":true, "referenceHandling":enhanced,
		"oceanWaves":[], "wind":WIND.duplicate(true), "playerId":"player",
		"controllableShipIds":["player","ally"], "hostileTargets":{},
		"sampleTerrainHeight":func(_x: float, _z: float) -> float: return -80.0,
		"ships":[
			{"id":"player", "kind":kind, "team":"player", "heading":0.0,
				"speed":0.0, "sailDeployment":0.0, "autoTrim":true,
				"position":{"x":0.0,"z":0.0}, "stats":{"cargoMass":0.0}},
			{"id":"ally", "kind":"fuchuan", "team":"player", "heading":0.0,
				"speed":0.0, "sailDeployment":0.0, "autoTrim":true,
				"position":{"x":0.0,"z":200.0}, "stats":{"cargoMass":0.0}},
		],
	})
	check(native.last_error.is_empty(), "deep-water healthy source fixture configures: " + kind)
	var sim := Simulation.new(native)
	sim.set_handling_mode("assisted")
	return sim

func _sample(before: Dictionary, at_two: Dictionary, after: Dictionary, label: String) -> Dictionary:
	var initial := _player(before)
	var two := _player(at_two)
	var final := _player(after)
	var forward := Vector2(cos(initial.visual.heading), sin(initial.visual.heading))
	var result := {
		"case":label, "acceptedTicks":after.tick-before.tick, "acceptedSeconds":after.time-before.time,
		"forward2":Vector2(two.visual.velocity.x,two.visual.velocity.z).dot(forward),
		"forward6":Vector2(final.visual.velocity.x,final.visual.velocity.z).dot(forward),
		"forwardMeters6":Vector2(final.visual.position.x-initial.visual.position.x,final.visual.position.z-initial.visual.position.z).dot(forward),
		"headingDegrees":rad_to_deg(absf(atan2(sin(final.visual.heading-initial.visual.heading),cos(final.visual.heading-initial.visual.heading)))),
		"sails":final.sailDeployment,
	}
	check(result.acceptedTicks == 360 and absf(result.acceptedSeconds-6.0) < 1e-9, "public route consumes six real accepted seconds: " + label)
	check(result.forward2 > 0.5, "public controls start above 0.5m/s at 2s: " + label)
	check(result.forward6 >= 1.5, "public controls sustain at least 1.5m/s at 6s: " + label)
	check(result.forwardMeters6 >= 6.0, "public controls produce at least 6m real forward travel: " + label)
	check(result.headingDegrees < 5.0, "public controls preserve the chosen headwind course: " + label)
	print("CASUAL_SAILING_RUNTIME_CONTROLS_SAMPLE ", JSON.stringify(result))
	return result

func _queued_start(kind: String, enhanced: bool) -> void:
	var sim := _fixture(kind, enhanced)
	var before: Dictionary = sim.snapshot()
	var command := _controls(_player(before), 0.8)
	var untouched := command.duplicate(true)
	sim.action(command)
	check(command == untouched and sim.snapshot() == before, "queue keeps caller payload and native motion detached")
	check(sim.pending_controls(before.playerId) == command, "full public controls queue until accepted physics")
	# A single frame contains six fixed ticks. Old action applies .8 only once,
	# then the unchanged input adapter silently overwrites it with the old zero.
	sim.advance(0.1)
	check(sim.snapshot().tick-before.tick == 6 and absf(_player(sim.snapshot()).sailDeployment-0.8) < 1e-9,
		"multiple fixed ticks retain the newly accepted sail intent: " + kind)
	var at_two: Dictionary = {}
	var deployment_retained := true
	for tick in range(6,360):
		sim.advance(STEP)
		var accepted: Dictionary = sim.snapshot()
		deployment_retained = deployment_retained and absf(_player(accepted).sailDeployment-0.8) < 1e-9
		if tick == 119: at_two = accepted
	check(deployment_retained, "all later fixed steps retain adopted UI intent: " + kind)
	_sample(before, at_two, sim.snapshot(), kind + " reference=" + str(enhanced))

func _waypoint_guards() -> void:
	for gate in ["invalid", "other-ship", "unchanged"]:
		var sim := _fixture()
		var goal := {"x":300.0,"z":0.0}
		check(sim.encounter.navigate("player", goal).ok, "real waypoint installs: " + gate)
		sim.refresh_snapshot()
		var ship := _player(sim.snapshot())
		var command := _controls(ship, ship.sailDeployment)
		if gate == "invalid": command.rudder = NAN
		elif gate == "other-ship":
			command = _controls(Simulation._ship(sim.snapshot(), "ally"), 0.6)
		sim.action(command)
		check(_player(sim.encounter.snapshot()).get("navigation") == goal,
			"non-player takeover is rejected before queue consumption: " + gate)
		sim.advance(0.1)
		check(_player(sim.snapshot()).get("navigation") == goal and not sim.handling_status().get("phase", "").contains("wind-recovery"),
			"invalid, other-ship and unchanged controls retain the real waypoint after fixed steps: " + gate)
		if gate == "invalid":
			var results: Array = sim.drain_results()
			check(results.size() == 1 and not results[0].result.ok, "invalid controls remain an explicit rejected receipt")
		elif gate == "other-ship":
			check(absf(Simulation._ship(sim.snapshot(), "ally").sailDeployment-0.6) < 1e-9,
				"another authorized ship receives its own controls without adopting player intent")

func _runtime_fixture() -> RefCounted:
	var runtime := Runtime.new()
	check(runtime.configure(func(_x: float, _z: float) -> float: return -80.0).ok, "actual Mingqi runtime configures without a save slot")
	check(runtime.simulation.encounter.set_wind(WIND).ok, "actual native source accepts the headwind fixture")
	runtime.simulation.refresh_snapshot()
	return runtime

func _accept(runtime: RefCounted, suffix: String) -> bool:
	var campaign: Dictionary = runtime.snapshot().campaign
	var result: Dictionary = runtime.command({"type":"accept-convoy", "commandId":"controls-accept-"+suffix, "expectedRevision":campaign.revision})
	check(result.ok, "actual lease acceptance grants source sailing permission: " + suffix)
	return result.ok

func _ui(runtime: RefCounted, slot: RefCounted, receipts: Array) -> CanvasLayer:
	var ui := Interface.new()
	root.add_child(ui)
	ui.apply_snapshot(runtime.snapshot())
	ui.open_panel("ship")
	ui.command_requested.connect(func(intent: Dictionary):
		if intent.get("type") == "save": receipts.append(runtime.save_checkpoint(slot, "2026-10-13T00:00:00.000Z"))
		else: receipts.append(runtime.command(intent)))
	return ui

func _port_boundary() -> void:
	# Each permission boundary gets a fresh runtime, so a failing movement assertion
	# cannot leave raised sails and invalidate the separate departure fixture.
	for lease in [false,true]:
		var runtime := _runtime_fixture()
		if lease and not _accept(runtime, "port"): runtime.dispose(); continue
		var before: Dictionary = runtime.snapshot().naval
		var origin: Dictionary = _player(before).visual.position.duplicate(true)
		runtime.command({"type":"controls","sailDeployment":0.8})
		for tick in 120: runtime.advance(STEP)
		var after: Dictionary = runtime.snapshot()
		var ship := _player(after.naval)
		check(after.campaign.currentPortId == "xiamen" and Vector2(ship.visual.position.x-origin.x,ship.visual.position.z-origin.z).length() < 1e-6 and Vector2(ship.visual.velocity.x,ship.visual.velocity.z).length() < 1e-6,
			"port controls cannot acquire player propulsion before departure; leased=" + str(lease))
		runtime.dispose()

func _runtime_slider() -> void:
	var slot := MemorySlot.new()
	var runtime := _runtime_fixture()
	if not _accept(runtime, "depart"): runtime.dispose(); return
	var campaign: Dictionary = runtime.snapshot().campaign
	var departure: Dictionary = runtime.command({"type":"depart","commandId":"controls-public-depart","expectedRevision":campaign.revision})
	check(departure.ok and runtime.snapshot().campaign.currentPortId == null, "actual business departure opens public sailing")
	if not departure.ok: runtime.dispose(); return
	var receipts: Array = []
	var ui := _ui(runtime, slot, receipts)
	var slider := ui.find_child("ship_sail", true, false) as HSlider
	check(slider != null and slider.editable, "actual Mingqi sail widget is available after departure")
	if slider == null: ui.free(); runtime.dispose(); return
	var before: Dictionary = runtime.snapshot().naval
	slider.value = 0.8
	check(receipts.size() == 1 and receipts[0].ok and runtime.simulation.has_pending_input(), "actual slider queues partial controls through the public runtime adapter")
	var at_two: Dictionary = {}
	var retained := true
	for tick in 360:
		runtime.advance(STEP)
		var packet: Dictionary = runtime.snapshot()
		retained = retained and absf(_player(packet.naval).sailDeployment-0.8) < 1e-9
		if tick == 119: at_two = packet.naval
	check(retained, "real bridge reconciliation and later ticks retain slider sail intent")
	var final: Dictionary = runtime.snapshot()
	check(final.runtime.status == "ready" and not final.runtime.paused, "real runtime stays live through six accepted seconds")
	_sample(before, at_two, final.naval, "actual Mingqi ship_sail UI")
	# An editable widget causes the real scene to release all sailing keys each
	# physics callback. A key that was never held must not erase slider ownership.
	ui.apply_snapshot(final)
	var rudder := ui.find_child("ship_rudder", true, false) as HSlider
	check(rudder != null and rudder.editable, "actual rudder slider is editable for the unheld-key release regression")
	if rudder != null:
		rudder.value = 0.6
		runtime.advance(STEP)
		check(absf(_player(runtime.snapshot().naval).rudder-0.6) < 1e-9, "public rudder slider intent is accepted before key releases")
		runtime.set_held("KeyA", false)
		runtime.set_held("KeyD", false)
		for tick in 10: runtime.advance(STEP)
		check(absf(_player(runtime.snapshot().naval).rudder-0.6) < 1e-9,
			"releasing never-held A/D keys preserves accepted mouse rudder intent across ten native ticks")
	check(slot.writes == 0, "controls test never writes a checkpoint; any save would use MemorySlot")
	ui.free()
	runtime.dispose()

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	for enhanced in [false,true]:
		for kind in ["fuchuan","heavy"]: _queued_start(kind, enhanced)
	_waypoint_guards()
	_port_boundary()
	_runtime_slider()
	print("CASUAL_SAILING_RUNTIME_CONTROLS_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
