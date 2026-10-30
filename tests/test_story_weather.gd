extends SceneTree
## Sea weather: three states with deterministic wind that reaches the native
## physics, reefs sails in storms, and rides along stage content and saves.

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
	_test_weather_plumbing()
	_test_weather_reaches_physics()
	_test_stage_weather_content()
	_finish()

func _finish() -> void:
	print("STORY_WEATHER assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures > 0 else 0)

func _test_weather_plumbing() -> void:
	check(absf(float(Rules.weather_wind("storm").speed) - 13.0) < 0.000001, "storm wind blows at thirteen")
	check(absf(Rules.weather_sail_cap("storm") - 0.55) < 0.000001, "storms reef sails to 0.55")
	check(absf(Rules.weather_sail_cap("calm") - 1.0) < 0.000001, "calm water keeps full sail")
	var world: RefCounted = World.new()
	world.call("configure", Scenarios.opening(), 1661, "story-weather")
	check(str(world.state.weather.sea) == "breeze", "the world opens on a breeze")
	check(world.call("command", {"type": "set-weather", "sea": "storm"}).get("ok", false), "the storm sets in")
	check(str(world.state.weather.sea) == "storm" and absf(float(world.state.weather.wind.speed) - 13.0) < 0.000001, "the storm is on the books")
	check(not world.call("command", {"type": "set-weather", "sea": "hurricane"}).get("ok", true), "unknown weather refused")
	check(World.validate_world(world.call("snapshot")).get("ok", false), "weather validates in the world")
	var twin: RefCounted = World.new()
	check(twin.call("restore", world.call("serialize")).get("ok", false), "weather survives save/restore")
	check(str(twin.state.weather.sea) == "storm", "restored world keeps the storm")

func _test_weather_reaches_physics() -> void:
	var storm: RefCounted = Support.setup("story-weather-storm")
	storm.fixture_calm_sea = false
	check(storm.call("command", {"type": "set-weather", "sea": "storm"}).get("ok", false), "storm sets on the runtime world")
	check(Support.advance_to(storm, 0), "storm runtime reaches CH-01")
	check(storm.call("command", {"type": "begin-stage"}).get("ok", false), "CH-01 begins")
	check(storm.call("command", {"type": "transition"}).get("ok", false), "CH-01 transitions")
	var native: Dictionary = storm.call("native_snapshot")
	check(absf(float(native.get("wind", {}).get("speed", 0.0)) - 13.0) < 0.000001, "the native physics feels the storm wind (%s)" % str(native.get("wind", {}).get("speed", 0.0)))
	check(storm.call("command", {"type": "depart"}).get("ok", false), "the fleet deploys under the storm")
	var setup: Dictionary = storm._fleet_setup(storm.world.state.fleet[0])
	check(absf(float(setup.sailDeployment) - 0.55) < 0.000001, "storm rigs are reefed (%s)" % str(setup.sailDeployment))
	var calm: RefCounted = Support.setup("story-weather-calm")
	calm.fixture_calm_sea = false
	check(calm.call("command", {"type": "set-weather", "sea": "calm"}).get("ok", false), "calm sets on the runtime world")
	check(Support.advance_to(calm, 0), "calm runtime reaches CH-01")
	check(calm.call("command", {"type": "begin-stage"}).get("ok", false), "CH-01 begins")
	check(calm.call("command", {"type": "transition"}).get("ok", false), "CH-01 transitions")
	var calm_native: Dictionary = calm.call("native_snapshot")
	check(absf(float(calm_native.get("wind", {}).get("speed", 0.0)) - 4.0) < 0.000001, "the native physics feels the calm wind")

func _test_stage_weather_content() -> void:
	# Stage weather is content + bind behavior: the walk verifies the CH-18
	# bind really brings the storm (play_ch_18 refuses without it).
	var scenarios: GDScript = load("res://game/domain/story_campaign/scenarios.gd")
	var entry: Dictionary = scenarios.call("scenario", "CH-18-S1")
	check(str(entry.get("weather", "")) == "storm", "the storm chapter carries weather in content")
	var storm_entry: Dictionary = scenarios.call("scenario", "CH-19-S1")
	check(str(storm_entry.get("weather", "")) == "storm", "the retreat chapter carries weather in content")
