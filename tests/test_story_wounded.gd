extends SceneTree
## Wounds and medicine: failures cost hands to the sick berth (not the sea),
## paid treatment returns them ashore, doctors recover one a day.

const Support = preload("res://tests/story_walkthrough_support.gd")
const Rules = preload("res://game/domain/story_world/story_rules.gd")
const World = preload("res://game/domain/story_world/story_world_session.gd")
const Scenarios = preload("res://game/domain/story_campaign/scenarios.gd")
var assertions: int = 0
var failures: int = 0

func _init() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> bool:
	assertions += 1
	if not value:
		failures += 1
		print("FAIL: ", label)
	return value

func _run() -> void:
	_test_failure_wounds()
	_test_paid_treatment()
	_test_doctor_recovery()
	_finish()

func _finish() -> void:
	print("STORY_WOUNDED assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures > 0 else 0)

func _world() -> RefCounted:
	var world: RefCounted = World.new()
	world.call("configure", Scenarios.opening(), 1661, "story-wounded")
	world.state.silver = 5000
	return world

func _test_failure_wounds() -> void:
	var world := _world()
	world.state.currentPortId = ""
	world.state.fleet[0].position = {"x": 0.0, "z": 0.0}
	var target := {"id": "hard-prize", "team": "hostile", "kind": "fuchuan", "hull": 65, "maxHull": 100, "crew": 28, "maxCrew": 100, "sail": 50, "maxSail": 100, "ammo": {"solid": 0, "chain": 0, "grape": 0}, "visual": {"position": {"x": 20.0, "z": 0.0}, "velocity": {"x": 0.0, "z": 0.0}, "heading": 0.0}}
	world.call("attach_native", {"ships": [{"id": "player", "team": "player", "kind": "fuchuan", "hull": 100, "maxHull": 100, "crew": 48, "maxCrew": 100, "sail": 100, "maxSail": 100, "ammo": {"solid": 0, "chain": 0, "grape": 0}, "visual": {"position": {"x": 0.0, "z": 0.0}, "velocity": {"x": 0.0, "z": 0.0}, "heading": 0.0}}, target]})
	var crew_before: int = int(world.state.fleet[0].crew)
	world.call("command", {"type": "resolve-boarding", "targetId": "hard-prize", "captured": false, "battleId": "w1"})
	var ship: Dictionary = world.state.fleet[0]
	check(int(ship.wounded) == 4 and crew_before - int(ship.crew) == 4, "a failed boarding sends four hands to the sick berth")
	check(int(ship.crew) + int(ship.wounded) == crew_before, "no hands vanish: the ledger balances")
	world.state.landPositions.erase("x")
	var land_crew_before: int = int(ship.crew)
	world.call("command", {"type": "resolve-land", "siteId": "hard-shore", "victory": false})
	check(int(world.state.fleet[0].wounded) == 10 and land_crew_before - int(world.state.fleet[0].crew) == 6, "a lost landing costs six more wounded")

func _test_paid_treatment() -> void:
	var world := _world()
	var ship: Dictionary = world.state.fleet[0]
	ship.wounded = 8
	ship.crew = 40
	world.state.currentPortId = "kinmen"
	check(not world.call("command", {"type": "treat-wounded", "count": 5}).get("ok", true), "ports without medicine refuse treatment")
	world.state.currentPortId = "xiamen"
	var silver_before: int = int(world.state.silver)
	check(world.call("command", {"type": "treat-wounded", "count": 5}).get("ok", false), "the yard treats five hands")
	check(silver_before - int(world.state.silver) == 10, "treatment costs two taels a head")
	var treated: Dictionary = world.state.fleet[0]
	check(int(treated.wounded) == 3 and int(treated.crew) == 45, "five hands return to duty")
	check(not world.call("command", {"type": "treat-wounded", "count": 9}).get("ok", true), "treating more than the sick berth holds is refused")
	check(World.validate_world(world.call("snapshot")).get("ok", false), "wounded counts validate in the world")

func _test_doctor_recovery() -> void:
	var world := _world()
	world.call("command", {"type": "sign-on", "personId": "medic", "name": "罗医者", "role": "doctor", "cost": 0, "wage": 0})
	var ship: Dictionary = world.state.fleet[0]
	ship.wounded = 3
	ship.crew = 40
	var crew_before: int = int(ship.crew)
	world.call("command", {"type": "advance-day"})
	var after: Dictionary = world.state.fleet[0]
	check(int(after.wounded) == 2 and int(after.crew) == crew_before + 1, "a doctor returns one hand a day")
