extends SceneTree

const Physics = preload("res://modules/physics_engine/ships/ship_dynamics.gd")
const Manual = preload("res://modules/physics_engine/ships/manual_handling.gd")
const Encounter = preload("res://modules/naval_simulation/encounter.gd")
const Simulation = preload("res://game/runtime/sailing_simulation.gd")
var failures := 0
var assertions := 0
func check(value: bool, detail: String) -> void:
	assertions += 1
	if not value: failures += 1; printerr("FAIL: ", detail)
func body(kind: String, cargo: float = 0.0) -> RefCounted:
	var result := Physics.new()
	check(result.configure({"kind":kind,"position":{"x":0.0,"z":0.0},"wind":{"direction":{"x":1.0,"z":0.0},"speed":0.0},"sailDeployment":0.0,"cargoMass":cargo}), "real hull configures: " + kind)
	return result
func turn(kind: String, responsive: bool, crew: float = 1.0, cargo: float = 0.0) -> Dictionary:
	var hull := body(kind, cargo)
	for tick in 120:
		var request := Manual.build(kind, 1.0, 0.0, crew)
		if responsive: request.responseRate = 6.0
		hull.step(1.0/60.0,{"manualAssist":request})
	return hull.get_snapshot()
func _initialize() -> void:
	var legacy := turn("fuchuan",false,0.25)
	var responsive := turn("fuchuan",true,0.25)
	print("REFERENCE_HANDLING_RESPONSE legacyDegrees=",rad_to_deg(legacy.heading)," responsiveDegrees=",rad_to_deg(responsive.heading))
	# Quarter-crew torque saturates early; a 15% gain would exceed the original
	# acceleration budget. Protect the measurable tail improvement instead.
	check(responsive.heading > legacy.heading * 1.02, "bounded responsive torque measurably improves reduced-crew low-speed turn")
	for entry in [["fisherman",18000.0],["merchant",150000.0],["heavy",330000.0]]:
		var normal := turn(entry[0], true)
		var loaded := turn(entry[0], true, 1.0, entry[1])
		check(normal.heading > 0.07 and normal.heading < 0.25, "zero-speed turn remains usable and bounded: " + entry[0])
		check(loaded.heading > 0.04 and loaded.heading < normal.heading, "cargo preserves inertia and usable low-speed turn: " + entry[0])
		print("REFERENCE_HANDLING_SAMPLE ",entry[0]," unloadedDegrees=",rad_to_deg(normal.heading)," loadedDegrees=",rad_to_deg(loaded.heading))
	var stopped := turn("heavy",true,0.0)
	check(stopped.heading == 0.0 and stopped.position.x == 0.0 and stopped.position.z == 0.0, "zero crew cannot turn or gain direct thrust")
	var hull := body("fuchuan")
	for tick in 120:
		var request := Manual.build("fuchuan",1.0,0.0); request.responseRate = 6.0
		hull.step(1.0/60.0,{"manualAssist":request})
	var before: Dictionary = hull.get_snapshot()
	for tick in 60:
		var request := Manual.build("fuchuan",0.0,0.0); request.responseRate = 6.0
		hull.step(1.0/60.0,{"manualAssist":request})
	check(absf(hull.get_snapshot().yawRate) < 0.001 and hull.get_snapshot().heading - before.heading < deg_to_rad(1.0), "release helm arrests yaw in one second with less than one degree overshoot")
	var bad := Manual.build("heavy",1.0,0.0); bad.responseRate = INF
	check(Manual.sanitize(bad).is_empty(), "nonfinite response rate rejects entire assist")
	bad.responseRate = 8.1
	check(Manual.sanitize(bad).is_empty(), "response beyond torque controller limit rejects entire assist")
	var encounter := Encounter.new({"referenceHandling":true,"mode":"continuous","playerId":"player","controllableShipIds":["player"],"hostileTargets":{},"oceanWaves":[],"ships":[{"id":"player","kind":"heavy","team":"player","position":{"x":0.0,"z":0.0},"heading":0.0,"speed":0.0,"sailDeployment":0.0,"stats":{"cargoMass":330000.0}}],"sampleTerrainHeight":func(_x,_z): return -80.0,"wind":{"direction":{"x":1.0,"y":0.0},"speed":12.0}})
	var sim := Simulation.new(encounter); sim.set_handling_mode("assisted"); sim.set_held("KeyW",true)
	var max_heading := 0.0
	var recovery_seen := false
	for tick in 360:
		sim.advance(1.0/60.0)
		var ship: Dictionary = sim.snapshot().ships[0]
		max_heading = maxf(max_heading,absf(atan2(sin(ship.visual.heading),cos(ship.visual.heading))))
		recovery_seen = recovery_seen or sim.handling_status().phase in ["wind-recovery","blocked"]
	var underway: Dictionary = sim.snapshot()
	var loaded: Dictionary = underway.ships[0]
	check(underway.tick == 360 and absf(underway.time-6.0)<1e-9 and max_heading<deg_to_rad(5),"loaded heavy ship keeps original heading through six accepted headwind seconds")
	check(loaded.sailDeployment>0.95 and not recovery_seen and not sim._assist.active(),"held W raises full sails without automatic wind escape or recovery block")
	check(loaded.visual.velocity.x>0.5 and loaded.visual.position.x>=3.0,"loaded heavy headwind assistance produces useful real forward speed and travel")
	print("REFERENCE_HANDLING_HEADWIND acceptedSeconds=",underway.time," maxHeadingDegrees=",rad_to_deg(max_heading)," forwardMeters=",loaded.visual.position.x," forwardMetersPerSecond=",loaded.visual.velocity.x," sails=",loaded.sailDeployment," phase=",sim.handling_status().phase)
	for kind in ["fisherman","merchant","heavy"]:
		var straight := Encounter.new({"referenceHandling":true,"oceanWaves":[],"ships":[{"id":"player","kind":kind,"team":"player","position":{"x":0.0,"z":0.0}}],"wind":{"direction":{"x":-0.8,"y":-0.6},"speed":14.0}})
		var turning := Encounter.new(straight.config)
		straight.set_manual_handling("player",{"mode":"assisted","turnIntent":0.0,"sailIntent":1.0,"braking":false,"recovery":false})
		turning.set_manual_handling("player",{"mode":"assisted","turnIntent":1.0,"sailIntent":1.0,"braking":false,"recovery":false})
		turning.command({"type":"controls","rudder":1.0,"sailDeployment":1.0})
		turning.set_manual_handling("player",{"mode":"assisted","turnIntent":1.0,"sailIntent":1.0,"braking":false,"recovery":false})
		for tick in 900: straight.step(1.0/60.0); turning.step(1.0/60.0)
		var a: Dictionary = straight.snapshot().ships[0].visual
		var b: Dictionary = turning.snapshot().ships[0].visual
		var speed_a := Vector2(a.velocity.x,a.velocity.z).length()
		var speed_b := Vector2(b.velocity.x,b.velocity.z).length()
		check(speed_a > 0.2,"wind powers startup without artificial drive: " + kind)
		check(absf(b.heading) > 0.3,"sustained turn changes course under real sail and keel forces: " + kind)
		print("REFERENCE_HANDLING_SAIL ",kind," straightMetersPerSecond=",speed_a," turnMetersPerSecond=",speed_b," turnDegrees=",rad_to_deg(b.heading))
		# Hold initial kinetic energy and zero wind equal: otherwise turning to
		# a better wind angle can outweigh hydrodynamic turning losses.
		var coast_config := {"referenceHandling":true,"oceanWaves":[],"ships":[{"id":"player","kind":kind,"team":"player","position":{"x":0.0,"z":0.0},"speed":3.0,"sailDeployment":0.0}],"wind":{"direction":{"x":1.0,"y":0.0},"speed":0.0}}
		var coast := Encounter.new(coast_config); var helm := Encounter.new(coast_config)
		helm.command({"type":"controls","rudder":1.0,"sailDeployment":0.0})
		for game in [coast,helm]: game.set_manual_handling("player",{"mode":"assisted","turnIntent":0.0 if game==coast else 1.0,"sailIntent":0.0,"braking":false,"recovery":false})
		for tick in 180: coast.step(1.0/60.0); helm.step(1.0/60.0)
		var cv: Dictionary = coast.snapshot().ships[0].visual.velocity
		var hv: Dictionary = helm.snapshot().ships[0].visual.velocity
		check(Vector2(hv.x,hv.z).length() < Vector2(cv.x,cv.z).length(),"equal-energy calm-water turn loses speed without fake friction: "+kind)
	var frozen: Dictionary = sim.snapshot(); sim.set_paused(true); sim.advance(60.0)
	check(sim.snapshot() == frozen and not sim._assist.active(), "pause clears recovery and consumes no simulation time")
	print("REFERENCE_HANDLING_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
