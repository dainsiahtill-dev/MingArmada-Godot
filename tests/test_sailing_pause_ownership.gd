extends SceneTree
## Regression: pause must release held keys without dropping accepted casual sail ownership.
const Encounter = preload("res://modules/naval_simulation/encounter.gd")
const Simulation = preload("res://game/runtime/sailing_simulation.gd")
const Practice = preload("res://game/runtime/naval_practice_runtime.gd")
const STEP := 1.0 / 60.0
var assertions := 0
var failures := 0

func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL sailing pause: ", detail)

func fixture() -> RefCounted:
	var native := Encounter.new({"mode":"continuous", "referenceHandling":true,
		"seed":1661, "playerId":"player", "controllableShipIds":["player"],
		"hostileTargets":{}, "oceanWaves":[], "wind":{"direction":{"x":1.0,"y":0.0},"speed":12.0},
		"sampleTerrainHeight":func(_x: float, _z: float) -> float: return -80.0,
		"ships":[{"id":"player","kind":"fuchuan","team":"player","heading":0.0,
			"speed":0.0,"sailDeployment":0.0,"autoTrim":true,"position":{"x":0.0,"z":0.0}}]})
	check(native.last_error.is_empty(), "real native fixture configures")
	var sim := Simulation.new(native)
	sim.set_handling_mode("assisted")
	return sim

func player(sim: RefCounted) -> Dictionary:
	return Simulation._ship(sim.snapshot(), "player")

func advance(sim: RefCounted, ticks: int) -> void:
	for tick in ticks: sim.advance(STEP)

func start(sim: RefCounted, input: String) -> void:
	match input:
		"sails": sim.set_sails(0.8)
		"controls": sim.action({"type":"controls","rudder":0.0,"sailDeployment":0.8,"autoTrim":true})
		"keys": sim.set_held("KeyW",true)
		"course": check(sim.set_course({"x":1000.0,"z":0.0}).ok, "course accepted")
	advance(sim,120)
	if input == "keys": sim.set_held("KeyW",false)

func retains_sailing(input: String) -> void:
	var uninterrupted := fixture()
	var resumed := fixture()
	start(uninterrupted,input); start(resumed,input)
	resumed.set_paused(true)
	var frozen: Dictionary = resumed.snapshot()
	resumed.set_held("KeyA",true)
	advance(resumed,120)
	check(resumed.snapshot() == frozen, "pause freezes all accepted authority: " + input)
	resumed.set_paused(false)
	advance(uninterrupted,240); advance(resumed,240)
	var continuous := player(uninterrupted)
	var actual := player(resumed)
	check(actual.visual == continuous.visual and actual.sailDeployment == continuous.sailDeployment,
		"resume matches uninterrupted native motion at equal accepted time: " + input)
	check(actual.visual.velocity.x >= 1.5 and absf(actual.visual.heading) < deg_to_rad(5),
		"resumed accepted sails retain headwind propulsion and chosen heading: " + input)
	print("SAILING_PAUSE_SAMPLE ",JSON.stringify({"input":input,"acceptedSeconds":resumed.snapshot().time,
		"resumedSpeed":actual.visual.velocity.x,"continuousSpeed":continuous.visual.velocity.x,
		"resumedX":actual.visual.position.x,"continuousX":continuous.visual.position.x}))

func clears_held_keys() -> void:
	var sim := fixture()
	sim.set_held("KeyW",true); sim.set_held("KeyD",true)
	advance(sim,30)
	var deployment: float = player(sim).sailDeployment
	sim.set_paused(true); sim.set_paused(false)
	advance(sim,60)
	check(player(sim).sailDeployment == deployment and absf(player(sim).rudder) < 0.001,
		"resume retains accepted sail amount but releases the old held sail and steering keys")

func permission_invalidation() -> void:
	var sim := fixture()
	start(sim,"sails")
	sim.set_paused(true)
	sim.set_sailing_allowed(false)
	sim.set_paused(false)
	advance(sim,120)
	check(player(sim).visual.velocity.x < 1.0, "revoked sailing permission cannot resume casual propulsion")

func runtime_pause_reasons() -> void:
	var continuous := Practice.new()
	var resumed := Practice.new()
	for runtime: RefCounted in [continuous,resumed]:
		check(runtime.configure(func(_x: float,_z: float) -> float: return -80.0,{"mode":"sail"}).ok,"actual free-sail runtime configures")
		check(runtime.simulation.encounter.set_wind({"direction":{"x":1.0,"y":0.0},"speed":12.0}).ok,"public native wind fixture is accepted")
		runtime.simulation.refresh_snapshot()
		check(runtime.command({"type":"sails","value":0.8}).ok,"actual free-sail sail command is accepted")
		for tick in 120: runtime.advance(STEP)
	for reason: String in ["player","menu","blur","loading","chart"]:
		check(resumed.set_pause(reason,true).ok,"real runtime pause enters: "+reason)
		var frozen: Dictionary = resumed.snapshot().naval
		resumed.advance(0.1)
		check(resumed.snapshot().naval == frozen,"real runtime pause freezes native authority: "+reason)
		check(resumed.set_pause(reason,false).ok,"real runtime pause leaves: "+reason)
	for tick in 240:
		continuous.advance(STEP); resumed.advance(STEP)
	check(player(resumed.simulation).visual == player(continuous.simulation).visual,
		"actual free-sail pause gates preserve sail propulsion at equal accepted time")
	continuous.dispose(); resumed.dispose()

func _initialize() -> void:
	for input: String in ["sails","controls","keys","course"]: retains_sailing(input)
	clears_held_keys()
	permission_invalidation()
	runtime_pause_reasons()
	print("SAILING_PAUSE_OWNERSHIP_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
