extends SceneTree
## Mouse sail intent must start a casual ship on its chosen course, including headwind.
## Real Encounter motion and accepted SailingSimulation ticks; no scene/GPU or copied force formula.

const Encounter = preload("res://modules/naval_simulation/encounter.gd")
const Simulation = preload("res://game/runtime/sailing_simulation.gd")
const Career = preload("res://game/runtime/mingqi_runtime.gd")
const Practice = preload("res://game/runtime/naval_practice_runtime.gd")
const STEP := 1.0 / 60.0
const KINDS := ["fisherman", "patrol", "fuchuan", "merchant", "voc", "heavy"]
const HEADWIND := {"direction":{"x":1.0,"y":0.0},"speed":12.0}
var assertions := 0
var failures := 0

func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", detail)

func _player(native: Dictionary) -> Dictionary:
	return Simulation._ship(native, native.get("playerId", "player"))

func _fixture(kind: String, wind: Dictionary, enhanced: bool, mode: String = "assisted", speed: float = 0.0) -> Dictionary:
	# Same continuous native ownership as career; no solo-ship victory stops the clock.
	var native := Encounter.new({
		"mode":"continuous", "routePlanning":true, "referenceHandling":enhanced,
		"seed":1661, "playerId":"player", "controllableShipIds":["player"],
		"hostileTargets":{}, "oceanWaves":[], "wind":wind.duplicate(true),
		"sampleTerrainHeight":func(_x: float, _z: float) -> float: return -80.0,
		"ships":[{"id":"player", "kind":kind, "team":"player", "heading":0.0,
			"speed":speed, "sailDeployment":0.0, "autoTrim":true,
			"position":{"x":0.0,"z":0.0}, "stats":{"cargoMass":0.0}}],
	})
	check(native.last_error.is_empty(), "healthy empty native fixture configures: " + kind)
	if not native.last_error.is_empty(): return {}
	var sim := Simulation.new(native)
	sim.set_handling_mode(mode)
	var initial := _player(sim.snapshot())
	check(initial.hull == initial.maxHull and initial.sail == initial.maxSail and initial.crew == initial.maxCrew and initial.stats.cargoMass == 0.0,
		"fixture has full hull, sails and crew without cargo: " + kind)
	check(initial.sailDeployment == 0.0 and sim.snapshot().status == "sailing", "fixture starts furled and continuous: " + kind)
	return {"native":native, "simulation":sim}

func _measure(sim: RefCounted, kind: String, label: String) -> Dictionary:
	var before: Dictionary = sim.snapshot()
	var start := _player(before)
	var origin := Vector2(start.visual.position.x, start.visual.position.z)
	var original_forward := Vector2(cos(start.visual.heading), sin(start.visual.heading))
	var at_two: Dictionary = {}
	var max_heading := 0.0
	var recovery_seen := false
	for tick in 360:
		sim.advance(STEP)
		var accepted: Dictionary = sim.snapshot()
		var ship := _player(accepted)
		var angle := absf(atan2(sin(ship.visual.heading - start.visual.heading), cos(ship.visual.heading - start.visual.heading)))
		max_heading = maxf(max_heading, angle)
		recovery_seen = recovery_seen or sim.handling_status().get("phase", "idle") == "wind-recovery"
		if tick == 119: at_two = accepted
	var after: Dictionary = sim.snapshot()
	var two := _player(at_two)
	var six := _player(after)
	var report := {
		"kind":kind, "profile":label, "acceptedSeconds":after.time-before.time,
		"acceptedTicks":after.tick-before.tick,
		"forward2":Vector2(two.visual.velocity.x,two.visual.velocity.z).dot(original_forward),
		"forward6":Vector2(six.visual.velocity.x,six.visual.velocity.z).dot(original_forward),
		"forwardMeters6":(Vector2(six.visual.position.x,six.visual.position.z)-origin).dot(original_forward),
		"maxHeadingDegrees":rad_to_deg(max_heading), "recoverySeen":recovery_seen,
		"sails":six.sailDeployment,
	}
	check(report.acceptedTicks == 360 and absf(report.acceptedSeconds - 6.0) < 1e-9,
		"six real accepted seconds are measured: " + kind + " " + label)
	print("CASUAL_SAILING_HEADWIND_SAMPLE ", JSON.stringify(report))
	return report

func _assert_start(report: Dictionary, label: String) -> void:
	check(report.forward2 > 0.5, "mouse sails alone start above 0.5m/s by 2s: " + label)
	check(report.forward6 >= 1.5, "mouse sails alone sustain at least 1.5m/s by 6s: " + label)
	check(report.forwardMeters6 >= 6.0, "real native position travels at least 6m on original course: " + label)

func _headwind_profile(enhanced: bool, label: String) -> Dictionary:
	var samples := {}
	for kind: String in KINDS:
		var fixture := _fixture(kind, HEADWIND, enhanced)
		if fixture.is_empty(): continue
		var sim: RefCounted = fixture.simulation
		# The only forward input is the same existing method called by a mouse slider.
		# No W, navigation target, fake initial velocity, or direct physics force.
		sim.set_sails(0.8)
		var sample := _measure(sim, kind, label)
		_assert_start(sample, kind + " " + label)
		check(sample.maxHeadingDegrees < 5.0 and not sample.recoverySeen,
			"headwind motion keeps chosen heading without automatic wind escape: " + kind + " " + label)
		check(absf(sample.sails - 0.8) < 1e-9, "mouse sail setting remains authoritative: " + kind + " " + label)
		samples[kind] = sample
	return samples

func _other_wind(enhanced: bool, headwind: Dictionary, label: String) -> void:
	if headwind.is_empty(): return
	var winds := {
		"calm":{"direction":{"x":1.0,"y":0.0},"speed":0.0},
		"tailwind":{"direction":{"x":-1.0,"y":0.0},"speed":12.0},
		"crosswind":{"direction":{"x":0.0,"y":1.0},"speed":12.0},
	}
	var reports := {}
	for name: String in winds:
		var fixture := _fixture("fuchuan", winds[name], enhanced)
		if fixture.is_empty(): continue
		fixture.simulation.set_sails(0.8)
		var sample := _measure(fixture.simulation, "fuchuan", label + " " + name)
		_assert_start(sample, label + " " + name)
		reports[name] = sample
	for name in ["tailwind", "crosswind"]:
		if not reports.has(name): continue
		check(reports[name].forward6 >= headwind.forward6 + 0.25,
			"wind efficiency remains a visible speed difference of at least 0.25m/s: " + label + " " + name)

func _stop_and_pause(enhanced: bool, label: String) -> void:
	# Independent moving fixture ensures a headwind startup failure cannot mask this contract.
	var fixture := _fixture("fuchuan", {"direction":{"x":1.0,"y":0.0},"speed":0.0}, enhanced, "assisted", 3.0)
	if fixture.is_empty(): return
	var sim: RefCounted = fixture.simulation
	sim.set_sails(0.8)
	sim.advance(STEP)
	var moving := _player(sim.snapshot())
	var moving_speed: float = moving.visual.velocity.x
	sim.set_sails(0.0)
	sim.advance(STEP)
	var first := _player(sim.snapshot())
	check(first.sailDeployment == 0.0, "zero mouse sails cancels deployment on next accepted tick: " + label)
	check(first.visual.velocity.x > 0.0 and first.visual.velocity.x <= moving_speed and moving_speed - first.visual.velocity.x < 0.2,
		"zero sails begins smooth deceleration without snapping or reversing: " + label)
	var last_speed: float = first.visual.velocity.x
	var increasing := false
	var reversed := false
	for tick in 59:
		sim.advance(STEP)
		var speed: float = _player(sim.snapshot()).visual.velocity.x
		increasing = increasing or speed > last_speed + 1e-7
		reversed = reversed or speed < -1e-7
		last_speed = speed
	check(not increasing and not reversed and last_speed < moving_speed - 0.01,
		"furled calm-water ship loses speed across accepted time without residual propulsion: " + label)
	sim.set_paused(true)
	var frozen: Dictionary = sim.snapshot()
	for tick in 360: sim.advance(STEP)
	check(sim.snapshot() == frozen and fixture.native.snapshot() == frozen,
		"paused accepted state has no time, velocity or position change: " + label)
	sim.set_paused(false)
	sim.advance(STEP)
	check(_player(sim.snapshot()).sailDeployment == 0.0,
		"resume retains zero sail intent: " + label)

func _realistic_boundary(enhanced: bool, label: String) -> void:
	var fixture := _fixture("fuchuan", HEADWIND, enhanced, "realistic")
	if fixture.is_empty(): return
	fixture.simulation.set_sails(0.8)
	var sample := _measure(fixture.simulation, "fuchuan", label + " realistic")
	check(absf(sample.forward6) < 1e-6 and absf(sample.forwardMeters6) < 1e-6 and sample.maxHeadingDegrees < 1e-6,
		"explicit realistic mode retains legacy straight-headwind no-go: " + label)

func _initialize() -> void:
	# Derive both source profiles from the actual runtime configuration, not a copied assumption.
	var career := Career.new()
	var career_ready: Dictionary = career.configure(func(_x: float, _z: float) -> float: return -80.0)
	check(career_ready.ok, "actual career runtime constructs native source")
	var practice := Practice.new()
	var practice_ready: Dictionary = practice.configure(func(_x: float, _z: float) -> float: return -80.0, {"mode":"sail"})
	check(practice_ready.ok, "actual practice runtime constructs native source")
	if career_ready.ok and practice_ready.ok:
		check(career.snapshot().runtime.handlingMode == "assisted" and practice.snapshot().runtime.handlingMode == "assisted",
			"actual career and practice default to assisted handling")
		var profiles := {
			"career":bool(career.simulation.encounter.config.get("referenceHandling", false)),
			"practice":bool(practice.simulation.encounter.config.get("referenceHandling", false)),
		}
		for label: String in profiles:
			var samples := _headwind_profile(profiles[label], label)
			_other_wind(profiles[label], samples.get("fuchuan", {}), label)
			_stop_and_pause(profiles[label], label)
			_realistic_boundary(profiles[label], label)
	career.dispose()
	practice.dispose()
	print("CASUAL_SAILING_HEADWIND_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
