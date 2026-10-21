extends SceneTree
const Services = preload("res://game/scenes/common/sea_services.gd")
const AudioCleanup = preload("res://tests/fixtures/audio_cleanup.gd")
class CountingSettings:
	extends "res://game/persistence/user_settings.gd"
	var loads := 0
	var quality := "low"
	func _init() -> void:
		super("user://tests/app-settings-no-write-%d.json" % OS.get_process_id())
	func load_settings() -> Dictionary:
		loads += 1
		var receipt := super.load_settings()
		_settings.quality = quality
		return receipt
class RuntimeStub:
	extends RefCounted
	var handling := ""
	func set_handling_mode(value: String) -> void: handling = value
class SeaStub:
	extends Node3D
	var confirmed: Dictionary = {}
	func apply_settings(value: Dictionary) -> void: confirmed = value.duplicate(true)
var failures := 0
var assertions := 0
func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ", detail)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var settings := CountingSettings.new(); settings.load_settings()
	var runtime := RuntimeStub.new()
	var sea := SeaStub.new(); root.add_child(sea)
	var services := Services.new(); root.add_child(services)
	services.configure(runtime, sea, settings)
	print("APP_SETTINGS_SERVICE loads=", settings.loads)
	check(settings.loads == 1, "scene service consumes the app-confirmed settings without a second disk read")
	check(services.settings_storage == settings and sea.confirmed.quality == "low", "scene service retains the injected settings authority")
	var stopped := AudioCleanup.stop_players(services)
	services.dispose(); services.free(); sea.free()
	check(await AudioCleanup.wait_for_release(self, stopped), "scene service releases native audio playback")
	# Exercise actual production entry-owner source. Only its renderer dependency
	# is replaced by a subclass which calls super and counts real world builds.
	for fixture: Dictionary in [{"path":"res://game/scenes/mingqi/mingqi_scene.gd", "quality":"low"}, {"path":"res://game/scenes/naval_practice/naval_practice.gd", "quality":"high"}]:
		var source := FileAccess.get_file_as_string(fixture.path)
		check(source.contains('preload("res://game/presentation/world/naval_world_view.gd")'), "entry instrumentation locates the actual renderer dependency")
		var script := GDScript.new()
		script.source_code = source.replace('preload("res://game/presentation/world/naval_world_view.gd")', 'preload("res://tests/fixtures/counting_naval_world_view.gd")')
		if not check_script(script): continue
		var owner: Node = script.new()
		settings = CountingSettings.new(); settings.quality = fixture.quality; settings.load_settings()
		owner.set("settings_storage", settings)
		owner.set("startup_options", {"staged":true, "mode":"sail", "seed":1650})
		root.add_child(owner); owner.set_process(false); owner.set_physics_process(false)
		var receipt: Dictionary = owner.get("startup_receipt")
		check(receipt.get("ok",false), "actual entry owner initializes: " + fixture.path)
		var actual_sea: Node3D = owner.get("sea")
		if actual_sea != null:
			print("APP_SETTINGS_ENTRY path=", fixture.path, " quality=", fixture.quality, " loads=", settings.loads, " worldBuilds=", actual_sea.get("world_configurations"))
			check(settings.loads == 1, "actual entry owner does not reload the app settings: " + fixture.quality)
			check(actual_sea.get("world_configurations") == 1, "actual entry builds the world once at confirmed quality: " + fixture.quality)
			check(actual_sea.get("_settings").quality == fixture.quality, "actual entry adopts the confirmed quality")
		stopped = AudioCleanup.stop_players(owner)
		owner.free()
		check(await AudioCleanup.wait_for_release(self, stopped), "actual entry releases audio playback")
	# The same ordering also protects the gated historical and QA owner paths.
	for path: String in ["res://game/scenes/legacy/legacy_scene.gd", "res://game/scenes/visual_qa/visual_qa.gd"]:
		var source := FileAccess.get_file_as_string(path)
		var preconfigure := source.find("sea.apply_settings(settings_storage.snapshot())")
		check(preconfigure >= 0 and preconfigure < source.find("sea.configure("), "entry confirms settings before its first world construction: " + path)
	print("APP_SETTINGS_CONVERGENCE_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
func check_script(script: GDScript) -> bool:
	var ok := script.reload() == OK
	check(ok, "actual entry owner instrumentation compiles")
	return ok
