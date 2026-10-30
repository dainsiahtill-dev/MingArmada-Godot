extends SceneTree
## Difficulty four-axis wiring: pressure tier scales hostile composition at
## bind and voyage upkeep per day (doc 38 difficulty axes).

const Support = preload("res://tests/story_walkthrough_support.gd")
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
	_test_upkeep_scales_with_tier()
	_test_hostile_composition_scales_at_bind()
	_finish()

func _finish() -> void:
	print("STORY_DIFFICULTY assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures > 0 else 0)

func _test_upkeep_scales_with_tier() -> void:
	var world: RefCounted = World.new()
	world.call("configure", Scenarios.opening(), 1661, "story-difficulty")
	var silver_before: int = int(world.state.silver)
	world.call("command", {"type": "advance-day"})
	var tier_one_cost: int = silver_before - int(world.state.silver)
	check(tier_one_cost == 2, "tier 1 upkeep is the baseline two taels, got %d" % tier_one_cost)
	check(world.call("command", {"type": "set-difficulty", "tier": 5}).get("ok", false), "difficulty tier records")
	check(int(world.state.meta.difficultyTier) == 5, "tier five stored in the world ledger")
	silver_before = int(world.state.silver)
	world.call("command", {"type": "advance-day"})
	var tier_five_cost: int = silver_before - int(world.state.silver)
	check(tier_five_cost == 3, "tier 5 upkeep rises to three taels, got %d" % tier_five_cost)
	check(not world.call("command", {"type": "set-difficulty", "tier": 9}).get("ok", true), "out-of-range tiers refused")
	check(World.validate_world(world.call("snapshot")).get("ok", false), "difficulty state validates")

func _test_hostile_composition_scales_at_bind() -> void:
	var runtime: RefCounted = Support.setup("story-difficulty-bind")
	check(Support.advance_to(runtime, 18), "playthrough reaches CH-19 (tier 5)")
	check(runtime.call("command", {"type": "begin-stage"}).get("ok", false), "CH-19 begins")
	var tier: int = int(runtime.world.state.meta.difficultyTier)
	check(tier == 5, "CH-19 bind applies the fifth-tier pressure")
	var pursuer: Dictionary = runtime._entity_setups.get("ch19-pursuer", {})
	check(int(pursuer.get("hull", 0)) == 70 + tier * 3, "pursuer hull scales with the tier (%d)" % int(pursuer.get("hull", 0)))
	check(int(pursuer.get("crew", 0)) == 28 + tier * 2, "pursuer crew scales with the tier (%d)" % int(pursuer.get("crew", 0)))
	var wounded: Dictionary = runtime._entity_setups.get("ch19-wounded-column", {})
	check(wounded.is_empty(), "neutral groups are not scaled by enemy composition")
