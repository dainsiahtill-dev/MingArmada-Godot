extends SceneTree
const Menu = preload("res://game/ui/menu/main_menu.gd")
const Router = preload("res://game/runtime/game_router.gd")
const Main = preload("res://game/scenes/main/main_scene.gd")
const Settings = preload("res://game/persistence/user_settings.gd")
const Storage = preload("res://game/persistence/save_coordinator.gd")
var assertions := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, reason: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ",reason)

func _write_fixture(path: String, bytes: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path,FileAccess.WRITE)
	check(file != null,"fixture file opens "+path)
	if file: file.store_string(bytes); file.close()

func _unchanged(paths: Array, before: Array) -> bool:
	for index in paths.size():
		if FileAccess.get_file_as_string(paths[index]) != before[index]: return false
		for suffix: String in [".backup",".staged",".rollback"]:
			if FileAccess.file_exists(paths[index]+suffix): return false
	return true

func _run() -> void:
	var menu := Menu.new(); root.add_child(menu)
	menu.apply_view_model({"dev":false,"qa":false},7)
	await process_frame
	var button: Button = menu.find_child("laboratory",true,false)
	check(button != null and button.is_visible_in_tree() and not button.disabled,"ordinary homepage exposes enabled laboratory without developer access")
	var intents: Array = []
	menu.intent_requested.connect(func(request: Dictionary): intents.append(request.duplicate(true)))
	var captain: LineEdit = menu.find_child("Captain",true,false)
	captain.text = "  草稿船长  "; captain.text_changed.emit(captain.text)
	if button:
		button.pressed.emit()
		check(intents.size() == 1 and intents[0].type == "laboratory" and not intents[0].has("mode"),"laboratory button emits public non-start intent")
		if not intents.is_empty():
			check(intents[0].generation == 7 and intents[0].nonce > 0,"laboratory intent carries current menu generation and nonce")
			check(menu.draft_name() == "  草稿船长  ","laboratory entry preserves unconfirmed captain draft without start normalization")
			button.pressed.emit()
			check(intents.size() == 1,"pending laboratory request suppresses repeated clicks")
			menu.apply_status({"phase":"error","message":"实验室暂未就绪"},7,intents[0].nonce)
			menu.find_child("Retry",true,false).pressed.emit()
			check(intents.size() == 2 and intents[-1].type == "retry" and intents[-1].entryType == "laboratory" and not intents[-1].has("mode"),"laboratory retry preserves non-start target")
			var cancelled_nonce: int = intents[-1].nonce
			menu.find_child("Back",true,false).pressed.emit()
			check(intents[-1].type == "back" and intents[-1].cancelledNonce == cancelled_nonce and intents[-1].nextGeneration == 8,"laboratory loading cancellation advances authority generation")
			check(not menu.apply_status({"phase":"complete"},7,cancelled_nonce),"late laboratory status cannot hide recovered menu")
	menu.free()
	var prefix := "user://tests/laboratory-entry-%d" % OS.get_process_id()
	var paths: Array = [prefix+"-v2.json",prefix+"-v1.json",prefix+"-settings.json"]
	var confirmed := Settings.defaults(); confirmed.captainName = "已确认船长"
	var before: Array = ["[]\n","[]\r\n",JSON.stringify({"version":1,"settings":confirmed})+"\n"]
	for index in paths.size(): _write_fixture(paths[index],before[index])
	var settings := Settings.new(paths[2]); settings.load_settings()
	var router := Router.new({"mingqi_storage":Storage.new(paths[0]),"legacy_storage":Storage.new(paths[1]),"settings_storage":settings})
	var request := {"type":"laboratory","generation":router.generation,"nonce":1,"name":"草稿船长"}
	var prepared: Dictionary = router.prepare_entry(request)
	check(prepared.get("ok",false) and prepared.get("mode") == "laboratory","ordinary router accepts public laboratory intent")
	if prepared.get("ok",false):
		check(not prepared.get("persist_name",false) and not prepared.get("explicit_import",false) and prepared.initial_save.is_empty(),"laboratory candidate never requests captain persistence or save import")
		check(router.commit_import(prepared).ok and _unchanged(paths,before) and settings.snapshot().captainName == "已确认船长","laboratory commit leaves actual save and settings bytes unchanged")
		check(router.prepare_entry(request).get("reason") == "entry-stale","repeated laboratory nonce cannot prepare another candidate")
		router.cancel()
		check(not router.is_current(prepared) and router.create_scene(prepared).get("reason") == "entry-stale" and router.commit_import(prepared).get("reason") == "entry-stale","cancelled laboratory candidate cannot construct or commit")
		var forged: Dictionary = router.prepare_entry({"type":"start","mode":"laboratory","name":"伪造船长","generation":router.generation,"nonce":2})
		check(not forged.get("persist_name",false),"laboratory cannot persist a captain name through a forged start intent")
		check(_unchanged(paths,before),"router cancellation preserves save and settings transaction files")
	var lab_resource = load("res://game/research/laboratory.gd") if ResourceLoader.exists("res://game/research/laboratory.gd") else null
	check(lab_resource is GDScript,"real laboratory resource is available through normal router")
	if lab_resource is GDScript:
		var main := Main.new()
		main.router = Router.new({"mingqi_storage":Storage.new(paths[0]),"legacy_storage":Storage.new(paths[1]),"settings_storage":Settings.new(paths[2])})
		root.add_child(main); await process_frame
		var entry_button: Button = main.menu.find_child("laboratory",true,false)
		if entry_button:
			var entry_captain: LineEdit = main.menu.find_child("Captain",true,false)
			entry_captain.text = "临时草稿"; entry_captain.text_changed.emit(entry_captain.text)
			entry_button.pressed.emit()
			for frame in 12: await process_frame
			var laboratory: Node = main.current_scene
			check(is_instance_valid(laboratory) and laboratory.get_script() == lab_resource,"visible homepage button activates actual laboratory through Main owner")
			if is_instance_valid(laboratory):
				check(laboratory.startup_options.get("staged",false) and laboratory.startup_receipt.get("ok",false) and not main.menu.visible,"laboratory passes real staged receipt before menu hides")
				check(_unchanged(paths,before) and main.router.settings_storage.snapshot().captainName == "已确认船长","successful laboratory activation never adopts captain draft or rotates saves")
				var old_generation: int = main.router.generation
				laboratory.main_menu_requested.emit()
				for frame in 4: await process_frame
				check(main.current_scene == null and main.menu.is_visible_in_tree() and not is_instance_valid(laboratory) and main.router.generation > old_generation,"laboratory return restores menu and releases scene through existing owner")
				main.menu.find_child("laboratory",true,false).pressed.emit()
				for frame in 12: await process_frame
				var reopened: Node = main.current_scene
				check(is_instance_valid(reopened) and reopened.get_script() == lab_resource,"laboratory can reenter after native scene disposal")
				if is_instance_valid(reopened): reopened.main_menu_requested.emit()
				for frame in 4: await process_frame
				main.menu.find_child("laboratory",true,false).pressed.emit()
				main.menu.find_child("Back",true,false).pressed.emit()
				for frame in 8: await process_frame
				check(main.current_scene == null and main._candidate == null and main.menu.is_visible_in_tree(),"cancel before deferred laboratory load fences late candidate")
				main.menu.find_child("laboratory",true,false).pressed.emit()
				for frame in 6:
					await process_frame
					if is_instance_valid(main._candidate): break
				var staged: Node = main._candidate
				check(is_instance_valid(staged) and staged.get_script() == lab_resource and not staged.visible,"real laboratory candidate stays hidden before owner acceptance")
				main.menu.find_child("Back",true,false).pressed.emit()
				for frame in 8: await process_frame
				check(main.current_scene == null and main._candidate == null and not is_instance_valid(staged) and main.menu.is_visible_in_tree(),"cancel while laboratory is staged disposes candidate and fences late receipt")
				check(_unchanged(paths,before),"repeated entry return and cancellation leave all persisted bytes unchanged")
		else: check(false,"actual Main menu has laboratory button")
		main.free(); await process_frame
	for path: String in paths:
		for suffix: String in ["",".backup",".staged",".rollback"]:
			if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	print("LABORATORY_ENTRY_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
