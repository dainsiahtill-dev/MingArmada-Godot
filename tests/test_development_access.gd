extends SceneTree
var failures := 0
var assertions := 0
func check(value: bool, detail: String) -> void:
	assertions += 1
	if not value: failures += 1; printerr("FAIL: ",detail)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var path := "res://game/runtime/development_access.gd"
	check(ResourceLoader.exists(path),"release authorization must have a shared engine environment boundary")
	if not ResourceLoader.exists(path): finish(); return
	var Access = load(path)
	for debug in [false,true]:
		for editor in [false,true]:
			check(Access.environment_allows(debug,editor) == (debug or editor),"environment truth table debug=%s editor=%s" %[debug,editor])
	var allowed: bool = OS.is_debug_build() or OS.has_feature("editor")
	check(Access.host_allows() == allowed,"host gate reads actual Godot debug/editor features")
	var Main = load("res://game/scenes/main/main_scene.gd")
	check(Main.startup_flags(PackedStringArray(["--dev","--qa"])) == {"dev":allowed,"qa":allowed},"main raw arguments are fenced by actual host")
	check(Main.startup_flags(PackedStringArray(["--dev=false","--qa=false"])) == {"dev":false,"qa":false},"only exact entry arguments request development access")
	var Settings = load("res://game/persistence/user_settings.gd")
	var Router = load("res://game/runtime/game_router.gd")
	var settings_path := "user://migration-verification/development-access-%d.json" % OS.get_process_id()
	var settings = Settings.new(settings_path)
	var router = Router.new({"dev":true,"qa":true,"debug":true,"editor":true,"settings_storage":settings})
	check(router.dev == allowed and router.qa == allowed,"injected dependencies cannot override actual release environment")
	var nonce := 0
	for mode in ["qa","practice","ships"]:
		nonce += 1
		var prepared: Dictionary = router.prepare_entry({"type":"start","mode":mode,"generation":router.generation,"nonce":nonce,"dev":true,"qa":true,"qaSeed":1661})
		check(prepared.ok == (allowed or mode == "ships"),"router fences developer mode and preserves public ships: "+mode)
		router.cancel()
	var closed = Router.new({"settings_storage":settings})
	check(not closed.prepare_entry({"type":"start","mode":"qa","generation":closed.generation,"nonce":1,"dev":true,"qa":true}).ok,"request flags cannot elevate router ownership")
	var public_candidate: Dictionary = closed.prepare_entry({"type":"start","mode":"ships","generation":closed.generation,"nonce":2})
	public_candidate.mode = "practice"
	var forged: Dictionary = closed.create_scene(public_candidate)
	check(forged.get("reason") == "entry-developer-only","manually changed candidate cannot bypass create-scene development gate")
	if forged.get("scene") is Node: forged.scene.free()
	if FileAccess.file_exists(settings_path): DirAccess.remove_absolute(settings_path)
	finish()
func finish() -> void:
	print("DEVELOPMENT_ACCESS_TEST assertions=",assertions," failures=",failures," debug=",OS.is_debug_build()," editor=",OS.has_feature("editor"))
	quit(1 if failures else 0)
