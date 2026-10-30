extends SceneTree
## All twelve hero specialties map to live mechanics: pure role math plus real
## world integrations (rescue hands, boarding volunteers, repair economics,
## charter credit, upkeep, lookout reach, escort coordination).

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
	_test_role_math()
	_test_world_specialties()
	_test_signaler_escort_bonus()
	_finish()

func _finish() -> void:
	print("STORY_ROLE_EFFECTS assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures > 0 else 0)

func _world() -> RefCounted:
	var world: RefCounted = World.new()
	world.call("configure", Scenarios.opening(), 1661, "story-roles")
	world.state.silver = 5000
	return world

func _sign(world: RefCounted, id: String, role: String) -> void:
	world.state.currentPortId = "xiamen"
	world.call("command", {"type": "sign-on", "personId": id, "name": id, "role": role, "cost": 0, "wage": 0})

func _test_role_math() -> void:
	check(absf(Rules.identify_radius(["lookout"]) - 180.0) < 0.000001, "lookout widens recognition reach")
	check(absf(Rules.boarding_volunteer_multiplier(["boarder"]) - 0.75) < 0.000001, "boarder needs fewer prize hands")
	check(absf(Rules.repair_cost_multiplier(["shipwright"]) - 0.5) < 0.000001, "shipwright halves repair bills")
	check(absf(Rules.charter_cost_multiplier(["diplomat"]) - 0.8) < 0.000001, "diplomat earns charter credit")
	check(Rules.rescue_crew_bonus(["rescuer"]) == 2, "rescuer recovers hands from the sea")
	check(Rules.repair_crew_bonus(["doctor"]) == 10, "doctor returns hands to duty after repairs")
	check(absf(Rules.escort_speed_bonus(["signaler"]) - 0.15) < 0.000001, "signaler keeps escorts moving")
	check(absf(Rules.upkeep_multiplier(["musician"]) - 0.95) < 0.000001, "musician sustains the crew")

func _test_world_specialties() -> void:
	var world := _world()
	_sign(world, "h-rescuer", "rescuer")
	var crew_before: int = int(world.state.fleet[0].crew)
	world.call("command", {"type": "rescue", "targetId": "swimmers", "name": "落水者"})
	check(int(world.state.fleet[0].crew) == crew_before + 2, "rescuer brings two hands aboard")
	_sign(world, "h-boarder", "boarder")
	world.state.currentPortId = ""
	world.state.fleet[0].position = {"x": 0.0, "z": 0.0}
	# Base volunteers: fuchuan minimum 24 minus half of 28 hands = 10.
	var target := {"id": "practice-prize", "team": "hostile", "kind": "fuchuan", "hull": 65, "maxHull": 100, "crew": 28, "maxCrew": 100, "sail": 50, "maxSail": 100, "ammo": {"solid": 0, "chain": 0, "grape": 0}, "visual": {"position": {"x": 20.0, "z": 0.0}, "velocity": {"x": 0.0, "z": 0.0}, "heading": 0.0}}
	world.call("attach_native", {"ships": [{"id": "player", "team": "player", "kind": "fuchuan", "hull": 100, "maxHull": 100, "crew": 48, "maxCrew": 100, "sail": 100, "maxSail": 100, "ammo": {"solid": 0, "chain": 0, "grape": 0}, "visual": {"position": {"x": 0.0, "z": 0.0}, "velocity": {"x": 0.0, "z": 0.0}, "heading": 0.0}}, target]})
	var crew_before_board: int = int(world.state.fleet[0].crew)
	world.call("command", {"type": "resolve-boarding", "targetId": "practice-prize", "captured": true, "disposition": "capture", "battleId": "roles-b"})
	var volunteers: int = crew_before_board - int(world.state.fleet[0].crew)
	check(volunteers == 8, "boarder trims prize volunteers from ten to eight, got %d" % volunteers)
	_sign(world, "h-shipwright", "shipwright")
	world.state.fleet[0].hull = 60
	var silver_before: int = int(world.state.silver)
	world.call("command", {"type": "repair"})
	check(silver_before - int(world.state.silver) == 40, "shipwright halves the eighty-tael repair")
	_sign(world, "h-doctor", "doctor")
	var crew_before_repair: int = int(world.state.fleet[0].crew)
	world.state.fleet[0].hull = 60
	world.call("command", {"type": "repair"})
	check(int(world.state.fleet[0].crew) == crew_before_repair + 10, "doctor returns ten hands after repairs")
	_sign(world, "h-diplomat", "diplomat")
	silver_before = int(world.state.silver)
	world.call("command", {"type": "sign-charter", "permitId": "credit-charter", "scope": "trade", "issuer": "court", "cost": 100, "conditions": ["按线经营"]})
	check(silver_before - int(world.state.silver) == 80, "diplomat earns twenty taels of charter credit")
	var roles: Array = world.call("_roles")
	check(roles.size() == 5, "the roster carries five active specialties, got %d" % roles.size())

func _test_signaler_escort_bonus() -> void:
	var runtime: RefCounted = Support.setup("story-roles-escort")
	runtime.fixture_speed_multiplier = 1.0
	check(Support.advance_to(runtime, 3), "playthrough reaches CH-04")
	check(runtime.world.call("command", {"type": "sign-on", "personId": "h-signaler", "name": "顾望川", "role": "signaler", "cost": 0, "wage": 0}).get("ok", false), "signaler signs on")
	check(runtime.call("command", {"type": "begin-stage"}).get("ok", false), "CH-04 begins")
	var convoy: Dictionary = runtime._entity_setups.get("ch04-client-convoy", {})
	check(absf(float(convoy.get("stats", {}).get("speedMultiplier", 0.0)) - 1.15) < 0.000001, "signaler lifts escort speed (%s)" % str(convoy.get("stats", {}).get("speedMultiplier", 0.0)))
