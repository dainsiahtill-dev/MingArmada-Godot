extends SceneTree
## External script, launched in an empty directory with --main-pack.
var failures: Array = []
var assertions := 0
var output := ""
var subjects: Array = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, reason: String) -> void:
	assertions += 1
	if not ok: failures.append(reason); printerr("FAIL: ",reason)
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--proof="): output = arg.trim_prefix("--proof=")
	check(FileAccess.file_exists("res://project.binary") and not FileAccess.file_exists("res://project.godot"),"packed project only, no loose project resources")
	var script: Variant = load("res://game/research/catalog.gd")
	check(script is GDScript,"packed research registry loads")
	var catalog: RefCounted = script.new()
	check(catalog.load_catalog().ok,"packed JSON catalog loads")
	for item: Dictionary in catalog.topics():
		var paper: Dictionary = catalog.read_paper(item.id)
		check(paper.ok and paper.text.contains("## 实验设计") and paper.text.contains("## 局限与失败"),"packed paper text exists: "+item.id)
		subjects.append({"id":item.id,"paper":item.paper,"sha256":FileAccess.get_sha256(item.paper)})
	var scene: Variant = load(ProjectSettings.get_setting("application/run/main_scene"))
	check(scene is PackedScene,"packed actual main scene loads")
	var main: Node = scene.instantiate(); root.add_child(main); await process_frame
	var button: Button = main.menu.find_child("laboratory",true,false)
	check(button != null and button.is_visible_in_tree(),"packed ordinary menu exposes laboratory")
	button.pressed.emit()
	for _i in 20:
		await process_frame
		if is_instance_valid(main.current_scene): break
	var lab: Control = main.current_scene
	check(is_instance_valid(lab) and lab.startup_receipt.ok,"packed route activates real laboratory")
	if is_instance_valid(lab):
		check(lab.select_topic("hull-contact"),"packed paper selection works")
		var launched: Dictionary = lab.start_demo({"paused":true})
		check(launched.ok,"packed registered experiment constructs production resources")
		var info: Dictionary = lab.inspection_snapshot()
		check(info.demo.get("ready",false) and info.demo.get("kind") == "fuchuan","packed experiment receipt ready")
		check(not FileAccess.file_exists("res://docs/research/README.md"),"documents excluded; runtime reports do not depend on docs")
		lab.main_menu_requested.emit()
		for _i in 3: await process_frame
		check(main.current_scene == null and main.menu.is_visible_in_tree(),"packed native lifecycle returns to menu")
	main.free(); await process_frame
	var result := {"valid":failures.is_empty(),"assertions":assertions,"failures":failures,"engine":Engine.get_version_info(),"subjects":subjects,"scope":"Exported PCK only from an empty working directory: bundled papers, JSON registry, real menu/router laboratory entry, production-resource demo construction and disposal. Headless package contract; not Windows EXE launch or packaged GPU pixel acceptance."}
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(result,"\t")); file.close()
	else: check(false,"pack evidence file opens")
	print("LABORATORY_PACK_TESTS assertions=",assertions," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
