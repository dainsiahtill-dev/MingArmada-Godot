extends Node
## External acceptance harness: actual exported release, actual Controls and GPU.
## Never ships in the production PCK; APPDATA/LOCALAPPDATA isolated by launcher.
var main: Node
var root: Window
var failures: Array[String] = []
var assertions := 0
var directory := ""
var captures: Array = []
var states: Array = []
var checkpoint := ""

func _ready() -> void:
	root = get_tree().root
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--proofdir="): directory = argument.trim_prefix("--proofdir=")
	run.call_deferred()

func check(value: bool, detail: String) -> void:
	assertions += 1
	if not value: failures.append(detail); printerr("FAIL: ", detail)

func frames(count: int = 8) -> void:
	for frame in count: await get_tree().process_frame

func quit(code: int) -> void: get_tree().quit(code)

func click(control: Control) -> void:
	check(control != null and control.is_visible_in_tree(), "actual click target visible")
	if not control: return
	var scroll: Node = control.get_parent()
	while scroll:
		if scroll is ScrollContainer: scroll.ensure_control_visible(control)
		scroll = scroll.get_parent()
	await frames(4)
	var point := control.get_global_rect().get_center()
	check(root.get_visible_rect().has_point(point), "actual click target within viewport")
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT; event.pressed = true; event.position = point
	Input.parse_input_event(event); await get_tree().process_frame
	event = event.duplicate(); event.pressed = false; Input.parse_input_event(event)
	await frames(8)

func key(code: int) -> void:
	var event := InputEventKey.new(); event.keycode = code; event.physical_keycode = code; event.pressed = true
	Input.parse_input_event(event); await get_tree().process_frame
	event = event.duplicate(); event.pressed = false; Input.parse_input_event(event)
	await frames(5)

func capture(label: String) -> void:
	await frames(6); await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := directory.path_join(label + ".png")
	check(image.save_png(path) == OK, "actual release viewport saved: " + label)
	captures.append({"label":label,"path":path,"sha256":FileAccess.get_sha256(path),"viewport":[image.get_width(),image.get_height()]})
	if main and main.current_scene:
		var scene: Node = main.current_scene
		var state: Dictionary = {"label":label,"scene":scene.get_script().resource_path}
		if scene.has_method("snapshot"): state.snapshot = scene.snapshot()
		elif "runtime" in scene: state.snapshot = scene.runtime.snapshot()
		states.append(state)

func enter(mode: String) -> Node:
	check(main.current_scene == null and main.menu.visible,"entry begins at visible menu: " + mode)
	if main.current_scene != null or not main.menu.visible: return null
	await click(main.menu._buttons[mode])
	for frame in 240:
		if main.current_scene or main.menu._phase == "error": break
		await get_tree().process_frame
	check(main.current_scene != null, "release menu entered actual scene: " + mode)
	if not main.current_scene: return null
	check(main.current_scene.startup_receipt.get("ok",false), "release scene startup confirmed: " + mode)
	var expected: String = {"mingqi":"mingqi","mingqi-continue":"mingqi","career":"legacy","duel":"naval_practice","fleet":"naval_practice","sail":"naval_practice","ships":"ship_book"}.get(mode,"")
	check(main.current_scene.get_script().resource_path.contains("/" + expected + "/"),"entry actually changed to requested scene: " + mode)
	if mode in ["duel","fleet","sail"]:
		var actual: String = main.current_scene.runtime.snapshot().runtime.mode
		check(actual == mode,"shared naval scene entered requested mode: %s (actual %s)" % [mode,actual])
	return main.current_scene

func leave_with_control(button_name: String) -> void:
	var scene: Node = main.current_scene
	if not scene: return
	if not scene.interface.is_menu_open(): await key(KEY_ESCAPE)
	var button := scene.find_child(button_name,true,false) as Button
	check(button != null and not button.disabled, "actual return control available: " + button_name)
	if button: await click(button)
	await frames(12)
	check(main.current_scene == null and main.menu.visible, "actual return control releases scene and restores menu")

func run() -> void:
	check(not directory.is_empty(), "explicit external evidence directory")
	if directory.is_empty(): quit(1); return
	DirAccess.make_dir_recursive_absolute(directory)
	check(not OS.is_debug_build() and not OS.has_feature("editor"), "actual release host flags debug=false editor=false")
	check(DisplayServer.get_name() != "headless", "actual GPU window; no headless visual substitution")
	check(FileAccess.file_exists("res://project.binary") and not FileAccess.file_exists("res://project.godot"), "exported project resource root")
	for path in ["res://build","res://tools","res://tests","res://docs","res://assets/provenance"]:
		check(not DirAccess.dir_exists_absolute(path), "production pack excludes " + path)
	root.size = Vector2i(1600,900); root.content_scale_size = Vector2i(1600,900)
	get_tree().create_timer(180,true,false,true).timeout.connect(func(): printerr("FAIL release acceptance wall timeout"); quit(70))
	# Verification-copy override selects only this driver. Game scene comes from the
	# unchanged production PCK, with actual release environment and no injected router.
	var packed = load("res://game/scenes/main/main_scene.tscn")
	main = packed.instantiate(); root.add_child(main); await frames(12)
	check(not main.router.dev and not main.router.qa, "--dev --qa cannot elevate actual release router")
	check(not main.menu._buttons.qa.visible and not main.menu._buttons.practice.visible and not main.menu._seed_row.visible, "release hides developer entries and seed")
	await capture("release-menu")
	# Caller dictionaries and direct scene loads also use actual engine facts.
	for pair in [["visual_qa","visual-qa-development-only"],["practice","practice-development-only"]]:
		var scene = load("res://game/scenes/%s/%s.tscn" % [pair[0],pair[0]]).instantiate()
		scene.startup_options = {"dev":true,"qa":true,"debug":true,"editor":true}
		root.add_child(scene); await frames(2)
		check(scene.startup_receipt == {"ok":false,"reason":pair[1]}, "direct release scene denies forged flags: " + pair[0])
		check(scene.get_child_count() == 0, "denied scene constructed no runtime/visual children")
		scene.free()
	var mingqi: Node = await enter("mingqi")
	if mingqi:
		await capture("release-mingqi-1650")
		if not mingqi.interface.is_menu_open(): await key(KEY_ESCAPE)
		check(mingqi.runtime.snapshot().runtime.paused, "Esc pauses actual Mingqi runtime")
		var save := mingqi.find_child("save",true,false) as Button
		check(save != null and not save.disabled, "initial safe port can save through real control")
		if save: await click(save)
		var read: Dictionary = main.router.mingqi_storage.read_checkpoint()
		check(read.get("ok",false), "release real UI wrote validated disk checkpoint")
		checkpoint = read.get("json", "")
		check(mingqi._verified_checkpoint == checkpoint and not checkpoint.is_empty(), "scene caches exact verified disk bytes")
		var status := mingqi.find_child("save_status",true,false) as Label
		check(status != null and status.text.contains("已验证"), "release save status visible")
		await capture("release-mingqi-checkpoint")
		var backup := mingqi.find_child("export_backup",true,false) as Button
		check(backup != null and not backup.disabled, "verified checkpoint enables real recovery export")
		# Avoid clipboard writes in the user's OS; export enablement is inspected here.
		await click(mingqi.find_child("save_and_menu",true,false))
		await frames(12); check(main.current_scene == null, "actual save-and-menu returns to menu")
	var restored: Node = await enter("mingqi-continue")
	if restored:
		var before: Dictionary = restored.runtime.snapshot()
		await frames(30)
		var after: Dictionary = restored.runtime.snapshot()
		check(after.runtime.paused and before.campaign == after.campaign and before.naval == after.naval, "continue stays frozen without offline/idle advancement")
		check(restored.initial_save == main.router.mingqi_storage.read_checkpoint().get("json",""), "continue receives original disk bytes")
		if not restored.interface.is_menu_open(): await key(KEY_ESCAPE)
		await capture("release-mingqi-continued")
		await click(restored.find_child("save_and_menu",true,false)); await frames(12)
	for mode in ["career","duel","fleet","sail"]:
		var scene: Node = await enter(mode)
		if not scene: continue
		await capture("release-" + mode)
		await leave_with_control("menu_save_exit" if mode == "career" else "main_menu")
	var book: Node = await enter("ships")
	if book:
		var controls := book.find_child("LODControls",true,false) as Control
		check(controls != null and not controls.visible, "public ship book hides release LOD developer controls")
		await capture("release-shipbook")
		await key(KEY_ESCAPE); await frames(10)
		check(main.current_scene == null, "shipbook real Esc returns to menu")
	root.size = Vector2i(320,480); root.content_scale_size = Vector2i(320,480)
	await capture("release-menu-narrow")
	var cwd := DirAccess.open(".").get_current_dir()
	var report := {"status":"PASS" if failures.is_empty() else "FAIL","assertions":assertions,"failures":failures,"engine":Engine.get_version_info(),"executable":OS.get_executable_path(),"debug":OS.is_debug_build(),"editor":OS.has_feature("editor"),"display":DisplayServer.get_name(),"gpu":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_driver_name(),"renderer":RenderingServer.get_current_rendering_method(),"physics":ProjectSettings.get_setting("physics/3d/physics_engine"),"arguments":OS.get_cmdline_args(),"cwd":cwd,"userDataDirectory":OS.get_user_data_dir(),"captures":captures,"states":states,"verificationDriver":true,"gameScene":"res://game/scenes/main/main_scene.tscn","scope":"Actual release EXE and byte-identical production PCK in verification copy; external override.cfg selects this driver. Production game scene and router loaded unchanged from PCK. Empty cwd, isolated child profile; actual Input events, Controls, entries, initial port checkpoint and frozen Continue. Not uninstrumented launch, continuous voyage/performance/audio/network acceptance."}
	var file := FileAccess.open(directory.path_join("release-proof.json"),FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report,"\t")); file.close()
	else: check(false,"release proof writable")
	main.queue_free(); await frames(8)
	print("WINDOWS_RELEASE_ACCEPTANCE assertions=",assertions," failures=",failures.size()," captures=",captures.size())
	quit(0 if failures.is_empty() else 1)
