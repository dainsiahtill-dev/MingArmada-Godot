extends SceneTree
const Storage = preload("res://game/persistence/save_coordinator.gd")
const Runtime = preload("res://game/runtime/mingqi_runtime.gd")
const Settings = preload("res://game/persistence/user_settings.gd")
const Text = preload("res://game/domain/legacy/utf16_text.gd")
var failures := 0
var assertions := 0
class SpyStorage extends RefCounted:
	var raw := ""
	var backup := ""
	var writes := 0
	var write_ok := true
	func read_checkpoint() -> Dictionary: return {"ok":true,"json":raw} if not raw.is_empty() else {"ok":false,"reason":"save-not-found"}
	func read_backup() -> Dictionary: return {"ok":true,"json":backup} if not backup.is_empty() else {"ok":false,"reason":"backup-not-found"}
	func write_checkpoint(json: String) -> Dictionary:
		writes += 1
		if not write_ok: return {"ok":false,"reason":"save-write-failed"}
		backup = raw; raw = json; return {"ok":true}
class EntryScene extends Node:
	signal main_menu_requested
	var startup_receipt := {"ok":true}
	var startup_options: Dictionary = {}
	var settings_storage: RefCounted
	var activated := false
	func activate_entry() -> void: activated = true
class FixtureRouter extends "res://game/runtime/game_router.gd":
	var scene_ok := false
	func create_scene(_candidate: Dictionary) -> Dictionary:
		var scene := EntryScene.new(); scene.startup_receipt = {"ok":scene_ok,"reason":"fixture-native-preflight-failed"}
		return {"ok":true,"scene":scene}
func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ",detail)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	if not ResourceLoader.exists("res://game/runtime/game_router.gd"):
		check(false,"native router exists with fenced continuation and recovery"); _finish(); return
	var Router = load("res://game/runtime/game_router.gd")
	var runtime := Runtime.new(); runtime.configure(func(_x: float,_z: float) -> float: return -24.0)
	var good: String = runtime.export_save("2026-10-11T00:00:00.000Z").json; runtime.dispose()
	var storage := SpyStorage.new(); storage.raw = good
	var router = Router.new({"mingqi_storage":storage})
	var request := {"type":"start","mode":"mingqi-continue","generation":router.generation,"nonce":1,"name":"船长"}
	var prepared: Dictionary = router.prepare_entry(request)
	check(prepared.ok and prepared.initial_save == good and storage.writes == 0,"ordinary continue validates actual Native projection and preserves original bytes with zero writes")
	check(not router.prepare_entry(request).ok,"double intent cannot prepare another authority")
	router.cancel(router.generation+1)
	check(not router.is_current(prepared) and not router.commit_import(prepared).ok and storage.writes == 0,"cancel fences late prepared candidate and disk transaction")
	storage.raw = "{invalid}\r\n"
	request.generation = router.generation; request.nonce = 2
	prepared = router.prepare_entry(request)
	check(not prepared.ok and prepared.get("recovery",false) and router.recovery_snapshot().raw == storage.raw,"invalid current slot opens recovery preserving exact raw bytes")
	check(router.export_recovery().json == storage.raw,"recovery export returns raw invalid bytes without claiming verified checkpoint")
	var invalid: Dictionary = router.prepare_recovery({"type":"import-json","json":"{bad}"})
	check(not invalid.ok and storage.writes == 0 and storage.raw == "{invalid}\r\n","invalid import leaves existing slot and raw recovery bytes untouched")
	storage.backup = good
	var candidate: Dictionary = router.prepare_recovery({"type":"read-backup"})
	check(candidate.ok and candidate.initial_save == good and storage.writes == 0,"backup validation prepares paused continue without rotating disk slot")
	storage.write_ok = false
	candidate = router.prepare_recovery({"type":"import-json","json":good})
	check(candidate.ok and candidate.get("explicit_import",false),"explicit import fully validates detached candidate before commit")
	check(not router.commit_import(candidate).ok and storage.raw == "{invalid}\r\n" and router.recovery_snapshot().raw == storage.raw,"failed write cannot replace slot or recovery evidence")
	storage.write_ok = true
	check(router.commit_import(candidate).ok and storage.raw == good and storage.backup == "{invalid}\r\n","successful import uses actual transaction boundary and retains previous raw bytes")
	request.generation = router.generation; request.nonce = 3; request.mode = "qa"
	check(not router.prepare_entry(request).ok,"release owner independently enforces QA gate")
	router.cancel(router.generation+1); storage.raw = ""
	request.generation = router.generation; request.nonce = 4; request.mode = "mingqi-continue"
	check(router.prepare_entry(request).get("recovery",false),"missing v2 remains recovery entry")
	check(not router.prepare_recovery({"type":"read-backup"}).get("explicit_import",false),"reading backup does not implicitly import")
	storage.raw = "{raw-evidence}\n"; router.cancel(); request.generation = router.generation; request.nonce = 5
	router.prepare_entry(request); storage.raw = ""; router.prepare_recovery({"type":"retry"})
	check(router.export_recovery().get("json") == "{raw-evidence}\n","failed missing retry retains earlier raw recovery evidence")
	var encoded: String = Text.from_units([0xe000])+"林".repeat(18)+Text.from_units([0xd83d])
	router.cancel(); request.generation = router.generation; request.nonce = 6; request.mode = "mingqi"; request.name = encoded
	var named: Dictionary = router.prepare_entry(request); var named_scene: Dictionary = router.create_scene(named)
	check(named_scene.ok and named_scene.scene.startup_options.captainName == String.chr(0xe000)+"林".repeat(18)+String.chr(0xfffd) and named.options.captainName == encoded,"1650 scene native adaptation preserves literal marker and substitutes lone surrogate without altering source settings name")
	if named_scene.ok: named_scene.scene.free()
	router.cancel(); request.generation = router.generation; request.nonce = 7; request.name = "明"+String.chr(127)+"旗"
	var del_entry: Dictionary = router.prepare_entry(request); var del_scene: Dictionary = router.create_scene(del_entry)
	check(del_scene.ok and del_scene.scene.startup_options.captainName == "明"+String.chr(0xfffd)+"旗" and del_scene.scene._validate_startup_options().ok,"source menu DEL name adapts to an accepted native1650 captain without rejecting startup")
	if del_scene.ok: del_scene.scene.free()
	var disk_path := "user://migration-verification/router-%d.json" % OS.get_process_id()
	var disk := Storage.new(disk_path); disk.write_checkpoint(good)
	var actual = Router.new({"mingqi_storage":disk})
	request.generation = actual.generation; request.nonce = 1
	check(actual.prepare_entry(request).ok and not FileAccess.file_exists(disk_path+".backup"),"actual file continue leaves backup rotation absent")
	for mode in ["duel","fleet","sail","ships","practice","qa","water-study"]:
		actual.dev = true; actual.cancel()
		var entry: Dictionary = actual.prepare_entry({"type":"start" if mode in ["duel","fleet","sail"] else mode,"mode":mode,"name":" \t林  明\n","qaSeed":1661,"dev":false,"qa":true,"generation":actual.generation,"nonce":actual.generation})
		var made: Dictionary = actual.create_scene(entry)
		check(made.ok and made.get("scene") is Node,"default factory constructs actual extra entry "+mode)
		if made.ok:
			var scene: Node = made.scene
			check(scene.get("startup_options").get("captainName") == "林 明" and scene.get("startup_options").get("seed") == 1661,"real scene receives normalized captain and seeded detached options "+mode)
			check(scene.get("startup_options").get("staged",false),"router constructs actual extra entry with staging boundary "+mode)
			if mode in ["ships","qa"]: check(scene.get("startup_options").get("dev") == true and scene.get("startup_options").get("qa") == false,"actual developer entry receives trusted owner flags while ignoring request flag spoofing "+mode)
			scene.free()
	for suffix in ["",".backup",".rollback",".staged"]:
		if FileAccess.file_exists(disk_path+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(disk_path+suffix))
	if not ResourceLoader.exists("res://game/scenes/main/main_scene.gd"):
		check(false,"native entry owner keeps failed or canceled candidates detached"); _finish(); return
	var Main = load("res://game/scenes/main/main_scene.gd")
	var main = Main.new()
	var settings_path := disk_path+".settings"
	var created: Array = []
	main.router = Router.new({"mingqi_storage":storage,"settings_storage":Settings.new(settings_path),"dev":true,"entry_factory":func(_mode: String,_options: Dictionary):
		var scene := EntryScene.new(); created.append(weakref(scene)); return scene})
	root.add_child(main); await process_frame
	main.menu.find_child("Settings",true,false).pressed.emit()
	check(main.settings_panel.visible and main.menu.visible,"actual menu opens settings while retaining menu authority")
	var escape := InputEventKey.new(); escape.physical_keycode = KEY_ESCAPE; escape.pressed = true
	Input.parse_input_event(escape); await process_frame
	check(not main.settings_panel.visible and main.current_scene == null and main.menu.visible,"physical Esc closes focused native menu settings without starting an entry")
	main.menu.find_child("ships",true,false).pressed.emit()
	main.menu.find_child("Back",true,false).pressed.emit()
	for frame in 5: await process_frame
	check(main.current_scene == null and main.menu.visible and (created.is_empty() or created[-1].get_ref() == null),"back before deferred readiness prevents late scene adoption and releases candidate")
	main.menu.find_child("ships",true,false).pressed.emit()
	await process_frame; await process_frame
	main.menu.find_child("Back",true,false).pressed.emit()
	for frame in 4: await process_frame
	check(main.current_scene == null and main.menu.visible and created[-1].get_ref() == null,"cancel after candidate enters tree releases node before readiness completion")
	main.menu.find_child("ships",true,false).pressed.emit()
	for frame in 5: await process_frame
	check(main.current_scene is EntryScene and not main.menu.visible,"actual menu intent creates and swaps ready injected entry")
	check(main.current_scene.activated,"successful swap activates the ready scene explicitly")
	check(not FileAccess.file_exists(settings_path),"ship book entry does not persist captain name through non-start source intent")
	var first_scene = main.current_scene
	first_scene.main_menu_requested.emit()
	await process_frame
	check(main.current_scene == null and main.menu.visible and not is_instance_valid(first_scene),"return to menu disposes previous authority and presents fresh owner generation")
	main.router.entry_factory = func(_mode: String,_options: Dictionary):
		var scene := EntryScene.new(); scene.startup_receipt = {"ok":false,"reason":"entry-fixture-failed"}; return scene
	main.menu.find_child("ships",true,false).pressed.emit()
	for frame in 5: await process_frame
	check(main.current_scene == null and main.menu.find_child("Retry",true,false).visible,"scene startup failure remains visible with retry/back without swapping authority")
	main.menu.find_child("Back",true,false).pressed.emit()
	main.menu.find_child("mingqi-continue",true,false).pressed.emit()
	for frame in 3: await process_frame
	check(main.recovery.visible and not main.menu.visible,"missing v2 opens actual recovery controls through native menu")
	main.recovery.find_child("Back",true,false).pressed.emit()
	check(main.menu.visible and not main.recovery.visible,"recovery back resets native entry lifecycle")
	storage.raw = "{broken-original}\n"; storage.write_ok = true
	var imported = FixtureRouter.new({"mingqi_storage":storage,"settings_storage":Settings.new(settings_path)})
	imported.generation = main.router.generation+1; main.router = imported; main._refresh_menu()
	main.menu.find_child("mingqi-continue",true,false).pressed.emit()
	var writes_before: int = storage.writes
	main._handle_recovery({"type":"import-json","json":good})
	for frame in 5: await process_frame
	check(main.current_scene == null and storage.writes == writes_before and storage.raw == "{broken-original}\n" and main.recovery.visible,"actual scene readiness failure prevents import disk commit and retains recovery")
	imported.scene_ok = true; storage.write_ok = false
	main._handle_recovery({"type":"import-json","json":good})
	for frame in 5: await process_frame
	check(main.current_scene == null and storage.raw == "{broken-original}\n" and main.recovery.visible,"actual scene preflight success followed by transaction failure retains old slot and releases candidate")
	storage.write_ok = true
	main._handle_recovery({"type":"import-json","json":good})
	for frame in 5: await process_frame
	check(main.current_scene is EntryScene and storage.raw == good and not main.recovery.visible,"successful explicit import commits then swaps fully ready candidate")
	var recovery_ui = load("res://game/ui/menu/save_recovery.gd").new(); root.add_child(recovery_ui)
	var emitted: Array = []; recovery_ui.intent_requested.connect(func(intent: Dictionary): emitted.append(intent))
	recovery_ui.open({"has_raw":false}); recovery_ui._button_pressed("import-file-dialog")
	var old_callback: Callable = recovery_ui._load.file_selected.get_connections()[0].callable
	recovery_ui.close(); recovery_ui.open({"has_raw":false})
	old_callback.call("res://tests/fixtures/web-save-v2.json")
	check(emitted.is_empty(),"canceled file dialog callback cannot import into a reopened recovery session")
	recovery_ui.queue_free(); await process_frame
	main.queue_free(); await process_frame
	for suffix in ["",".backup",".rollback",".staged"]:
		if FileAccess.file_exists(settings_path+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path+suffix))
	_finish()
func _finish() -> void:
	print("GAME_ROUTER_TESTS complete assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
