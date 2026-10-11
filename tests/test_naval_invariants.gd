extends SceneTree
const Encounter = preload("res://modules/naval_simulation/encounter.gd")
const Waves = preload("res://modules/physics_engine/ocean/wave_field.gd")
const Coastal = preload("res://modules/physics_engine/ocean/coastal_wave_field.gd")
const Descriptor = preload("res://modules/contracts/wave_descriptor.gd")
const ComparatorTest = preload("res://tests/test_naval_simulation.gd")
var failures: Array[String] = []
var assertions = 0
class ClockSampler extends RefCounted:
	var seen: Array = []
	func sample(x: float, z: float, time: float) -> Dictionary:
		seen.append({"x": x, "z": z, "time": time})
		return {"height": sin(time) * 0.2}
class FaultSampler extends RefCounted:
	func sample(_x: float, _z: float, _time: float) -> Dictionary: return {"height": NAN}
func _initialize() -> void:
	for pair in [[NAN, 1.0], [1.0, NAN], [NAN, NAN], [INF, INF], [-INF, 1.0]]: check(not ComparatorTest.numeric_equal(pair[0], pair[1]), "numeric comparator rejects nonfinite " + str(pair))
	check(ComparatorTest.numeric_equal(1.00000001, 1.0), "numeric comparator retains finite tolerance")
	var ship = {"id": "player", "kind": "fuchuan", "team": "player", "position": {"x": 10, "z": 20}, "sailDeployment": 0.0}
	var probe = ClockSampler.new()
	var e = Encounter.new({"mode": "continuous", "playerId": "player", "controllableShipIds": ["player"], "ships": [ship], "waveSampler": probe, "oceanWaves": [], "wind": {"direction": {"x": 1, "y": 0}, "speed": 0}})
	check(e.last_error.is_empty(), "trusted injected sampler configured")
	probe.seen.clear()
	e.step(1.0 / 60)
	check(not probe.seen.is_empty(), "injected sampler used by actual physics")
	check(probe.seen.all(func(v): return absf(v.time - 1.0 / 60) < 1e-12), "all sub-samples use accepted encounter clock")
	var before = e.snapshot()
	var detached = e.snapshot()
	detached.ships[0].hull = 0
	detached.ships[0].visual.position.x = -999
	detached.wind.speed = 99
	check(e.snapshot() == before, "snapshot mutation cannot alter authority")
	check(not e.update_ship_stats("player", {"stats": {"hullMultiplier": "bad"}}).ok, "malformed numeric stats rejected")
	check(e.snapshot() == before, "malformed stats atomic")
	check(not e.reconcile_ships([ship, {"id": 99, "kind": "fuchuan", "team": "neutral", "position": {"x": 0, "z": 0}}], {"controllableShipIds": ["player"], "hostileTargets": {}}).ok, "malformed batch identity rejected")
	check(e.snapshot() == before and e.drain_events().is_empty(), "malformed batch preserves pose and event buffer")
	check(e.command({"type": "controls", "rudder": 0.4, "sailDeployment": 0.6}).ok, "same tick controls accepted")
	check(e.snapshot().ships[0].controlsSequence == before.ships[0].controlsSequence + 1 and e.snapshot().tick == before.tick, "same tick authority sequence increments independently of physics")
	check(e.update_ship_stats("player", {"stats": {"speedMultiplier": 1.3, "cargoMass": 5000, "draftMeters": 2.4}}).ok, "live stats accepted")
	check(e.snapshot().ships[0].visual == before.ships[0].visual, "equipment mutation preserves full current motion")
	var captured_events = Encounter.new({"ships": [ship], "oceanWaves": []})
	captured_events.command({"type": "fire", "side": "port"})
	var event_before = captured_events.events.duplicate(true)
	captured_events.reconcile_ships([ship, ship])
	check(captured_events.events == event_before, "rejected batch preserves already emitted events")
	var coast = Coastal.new()
	var coast_game = Encounter.new({"ships": [ship], "oceanWaves": Descriptor.original_descriptors(), "waveSampler": coast})
	check(coast_game.last_error.is_empty(), "real CoastalWaveField accepted")
	coast_game.step(0.1)
	check(coast_game.snapshot().tick == 6 and coast_game.snapshot().time == 0.1, "max caller step consumes source six naval ticks")
	coast_game.step(-1); coast_game.step(NAN); coast_game.step(0)
	check(coast_game.snapshot().tick == 6, "invalid elapsed times consume no time")
	var enormous_wave = {"direction": {"x": 1.0, "y": 0.0}, "amplitude": 8.8e307, "wavelength": 100.0, "speed": 0.0}
	var overflow_ship = ship.duplicate(true); overflow_ship.position = {"x": 0.0, "z": 0.0}; overflow_ship.stats = {"draftMeters": 1e307}
	var prior = e.snapshot(); var event_prior = e.events.duplicate(true)
	check(not e.reset({"ships": [overflow_ship], "oceanWaves": [enormous_wave]}), "combined heave overflow rejects reset")
	check(e.last_error == "Ship heave travel limit must be finite", "reset overflow source reason")
	check(e.snapshot() == prior and e.events == event_prior, "rejected reset fully atomic")
	var small_ship = ship.duplicate(true); small_ship.position = {"x": 0.0, "z": 0.0}
	var huge_ocean = Encounter.new({"ships": [small_ship], "oceanWaves": [enormous_wave]})
	check(huge_ocean.last_error.is_empty(), "individual enormous wave envelope remains finite")
	var huge_before = huge_ocean.snapshot()
	check(not huge_ocean.update_ship_stats("player", {"stats": {"draftMeters": 1e307}}).ok, "combined heave overflow rejects live update")
	check(huge_ocean.snapshot() == huge_before, "rejected overflow update preserves authority")
	check(not huge_ocean.reconcile_ships([overflow_ship]).ok, "combined heave overflow rejects batch")
	check(huge_ocean.snapshot() == huge_before, "rejected overflow batch preserves authority")
	var core_identity = e.ships[0].core.get_instance_id()
	check(e.update_ship_stats("player", {"stats": {"cargoMass": 1000}}).ok and e.ships[0].core.get_instance_id() == core_identity, "validated physics clone commits to original live core identity")
	var stable_before = e.snapshot()
	check(not e.reset({"ships": [ship], "waveSampler": FaultSampler.new()}), "physics configure false propagates out of reset")
	check(e.snapshot() == stable_before and e.ships[0].core.get_instance_id() == core_identity, "physics configure failure leaves original authority/core intact")
	var raw_config = e.ships[0].core.get_config()
	e.ships[0].core._config.waterAreaFactor = -1.0
	var invalid_physics_before = e.snapshot()
	var failed_physics = e.update_ship_stats("player", {"stats": {"draftMeters": 2.5}})
	check(not failed_physics.ok and failed_physics.reason == "Invalid ship physics update", "physics setter failure propagated before live update")
	check(e.snapshot() == invalid_physics_before and e.ships[0].core._config.waterAreaFactor == -1.0, "failed physics staging leaves live authority/config unchanged")
	e.ships[0].core._config = raw_config
	var injected_compare_game = Encounter.new({"ships": [ship], "oceanWaves": [], "idComparer": func(a: String, b: String): return -a.casecmp_to(b)})
	check(injected_compare_game._compare_ids("a", "b") > 0, "trusted comparator seam accepts alternate host collator")
	for expected_method in ["reset", "command", "step", "snapshot", "drainEvents", "drain_events", "reconcileShips", "reconcile_ships", "reconcile", "setPlayerId", "set_player_id", "updateShipStats", "update_ship_stats", "isAnchored", "is_anchored", "hasPendingAttacks", "has_pending_attacks", "hasPendingCombat", "has_pending_combat", "issueOrder", "issue_order", "orderStatus", "order_status", "navigate", "navigationStatus", "navigation_status", "anchorFleet", "anchor_fleet", "previewSurrender", "preview_surrender", "setWind", "set_wind", "setManualHandling", "set_manual_handling", "findManualRecoveryHeading", "find_manual_recovery_heading"]:
		check(e.has_method(expected_method), "public API " + expected_method)
	if failures.is_empty(): print("NAVAL_INVARIANTS_PASS assertions=", assertions); quit(0)
	else:
		for failure in failures: print("NAVAL_INVARIANT_FAIL ", failure)
		quit(1)
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)
