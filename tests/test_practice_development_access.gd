extends SceneTree
var assertions := 0
var failures := 0
func check(value: bool,detail: String) -> void:
	assertions += 1
	if not value: failures += 1; printerr("FAIL: ",detail)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var scene = load("res://game/scenes/practice/practice.tscn").instantiate()
	scene.startup_options = {"dev":true,"qa":true,"debug":true,"editor":true,"kind":"duel"}
	var allowed := OS.is_debug_build() or OS.has_feature("editor")
	check(scene.has_method("development_access_allowed"),"direct practice scene owns actual environment authorization before startup")
	if scene.has_method("development_access_allowed"):
		check(scene.development_access_allowed() == allowed,"startup dictionaries cannot override actual practice host facts")
	root.add_child(scene); await process_frame
	if allowed:
		check(scene.startup_receipt.get("ok",false),"debug/editor direct practice preserves working startup")
		check(scene.encounter_ui != null and not scene.runtime.snapshot().is_empty(),"debug/editor practice creates real encounter UI/runtime")
	else:
		check(scene.startup_receipt == {"ok":false,"reason":"practice-development-only"},"release direct practice refuses manually supplied development flags")
		check(scene.encounter_ui == null and scene.get_child_count() == 0 and scene.runtime.snapshot().is_empty(),"release denial creates no practice UI or active runtime")
		check(not scene.is_processing(),"denied direct scene does not schedule practice ticks")
	scene.free()
	print("PRACTICE_DEVELOPMENT_ACCESS_TEST assertions=",assertions," failures=",failures," debug=",OS.is_debug_build()," editor=",OS.has_feature("editor"))
	quit(1 if failures else 0)
