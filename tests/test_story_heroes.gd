extends SceneTree
## Hero roster: twelve named heroes load strictly, only offer at their home
## ports (willingness), and sign on as real people in the world ledger.

const Heroes = preload("res://game/domain/story_campaign/heroes.gd")
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
	_test_registry()
	_test_home_port_willingness()
	_test_sign_on_ledger()
	_finish()

func _finish() -> void:
	print("STORY_HEROES assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures > 0 else 0)

func _test_registry() -> void:
	var loaded: Dictionary = Heroes.load_content()
	check(loaded.get("ok", false), "hero roster loads and validates: " + str(loaded.get("reason", "")))
	var roster: Array = Heroes.heroes()
	check(roster.size() == 12, "twelve named heroes on the roster")
	var names := {}
	for hero: Dictionary in roster:
		check(not names.has(hero.name), "hero name unique: " + str(hero.name))
		names[hero.name] = true
	check(names.has("林澈") and names.has("黎秋砚") and names.has("贺舫"), "roster matches the design names")

func _test_home_port_willingness() -> void:
	var xiamen: Array = Heroes.heroes_at("xiamen")
	var kinmen: Array = Heroes.heroes_at("kinmen")
	check(xiamen.size() == 5, "Xiamen offers five local heroes, got %d" % xiamen.size())
	check(kinmen.size() == 2, "Kinmen offers two local heroes, got %d" % kinmen.size())
	check(Heroes.heroes_at("xiamen", ["NPC-H01"]).size() == 4, "signed heroes stop being offered")
	check(Heroes.heroes_at("zeelandia").is_empty(), "distant ports offer no local heroes")

func _test_sign_on_ledger() -> void:
	var world: RefCounted = World.new()
	world.call("configure", Scenarios.opening(), 1661, "story-heroes")
	world.state.silver = 2000
	world.state.currentPortId = "kinmen"
	var silver_before: int = int(world.state.silver)
	check(world.call("command", {"type": "sign-on", "personId": "NPC-H08", "name": "石砚青", "role": "gunner", "cost": 280, "wage": 11}).get("ok", false), "hero signs on for real silver")
	check(silver_before - int(world.state.silver) == 280, "the signing fee leaves the ledger")
	check(world.state.people.size() == 1 and str(world.state.people[0].name) == "石砚青", "the hero is really aboard")
	check(not world.call("command", {"type": "sign-on", "personId": "NPC-H08", "name": "石砚青", "role": "gunner", "cost": 280, "wage": 11}).get("ok", true), "duplicate signing refused")
	check(World.validate_world(world.call("snapshot")).get("ok", false), "signed roster validates in the world")
