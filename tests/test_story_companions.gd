extends SceneTree
## Companion specialties change real outcomes: navigator passages, purser
## upkeep, gunner batteries — reflected in live stats and the world ledger.

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
	_test_role_effects()
	_test_upkeep_discount()
	_test_live_stats_with_companions()
	_finish()

func _finish() -> void:
	print("STORY_COMPANIONS assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures > 0 else 0)

func _test_role_effects() -> void:
	check(absf(Rules.speed_multiplier(["navigator"]) - 1.1) < 0.000001, "navigator speeds passages")
	check(absf(Rules.reload_multiplier(["gunner"]) - 0.85) < 0.000001, "gunner crews batteries faster")
	check(absf(Rules.upkeep_multiplier(["purser"]) - 0.9) < 0.000001, "purser trims upkeep")
	check(absf(Rules.speed_multiplier([]) - 1.0) < 0.000001, "an empty roster changes nothing")
	check(Rules.reload_multiplier(["gunner", "gunner"]) < 0.85, "specialists stack multiplicatively")

func _test_upkeep_discount() -> void:
	var world: RefCounted = World.new()
	world.call("configure", Scenarios.opening(), 1661, "story-companions")
	world.call("command", {"type": "set-difficulty", "tier": 6})
	world.state.silver = 5000
	check(world.call("command", {"type": "sign-on", "personId": "keeper", "name": "账房", "role": "purser", "cost": 0, "wage": 0}).get("ok", false), "purser signs on")
	check(world.call("command", {"type": "sign-on", "personId": "cook", "name": "庖长", "role": "cook", "cost": 0, "wage": 0}).get("ok", false), "cook signs on")
	var before: int = int(world.state.silver)
	var day: Dictionary = world.call("command", {"type": "advance-day"})
	check(day.get("ok", false), "day advances with the roster aboard")
	var cost: int = before - int(world.state.silver)
	check(cost == 5, "specialists trim the daily upkeep to five taels, got %d" % cost)

func _test_live_stats_with_companions() -> void:
	var runtime: RefCounted = Support.setup("story-companions-stats")
	runtime.fixture_speed_multiplier = 1.0
	runtime.fixture_reload_multiplier = 1.0
	check(Support.advance_to(runtime, 4), "playthrough reaches CH-05")
	check(runtime.call("command", {"type": "begin-stage"}).get("ok", false), "CH-05 begins")
	check(runtime.call("command", {"type": "transition"}).get("ok", false), "CH-05 transitions")
	check(runtime.world.call("command", {"type": "sign-on", "personId": "ch05-willing-navigator", "name": "陈引水", "role": "navigator", "cost": 60, "wage": 6}).get("ok", false), "navigator signs on")
	var setup: Dictionary = runtime._fleet_setup(runtime.world.state.fleet[0])
	check(absf(float(setup.stats.speedMultiplier) - 1.1) < 0.000001, "navigator raises the live sailing speed (%s)" % str(setup.stats.speedMultiplier))
	check(runtime.world.call("command", {"type": "sign-on", "personId": "master-gunner", "name": "炮头", "role": "gunner", "cost": 80, "wage": 8}).get("ok", false), "gunner signs on")
	setup = runtime._fleet_setup(runtime.world.state.fleet[0])
	check(absf(float(setup.stats.reloadMultiplier) - 0.85) < 0.000001, "gunner raises the live rate of fire (%s)" % str(setup.stats.reloadMultiplier))
