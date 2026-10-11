extends SceneTree
## Scene boundary checks: a bad startup never replaces a live game or writes disk.
const Scene = preload("res://game/scenes/mingqi/mingqi_scene.gd")
const Runtime = preload("res://game/runtime/mingqi_runtime.gd")
const Campaign = preload("res://game/domain/mingqi/campaign.gd")
const Storage = preload("res://game/persistence/save_coordinator.gd")
const Settings = preload("res://game/persistence/user_settings.gd")
const PATH := "user://tests/career-startup-v2.json"
const UTC := "2026-10-11T00:00:00.000Z"
var failures := 0
var assertions := 0

class FailedStorage extends Storage:
	func write_checkpoint(_json: String) -> Dictionary:
		return {"ok":false,"reason":"injected-write-failure"}

func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ",detail)

func _initialize() -> void: _run.call_deferred()

func _mount(options: Dictionary = {}, save: String = "", disk: RefCounted = null) -> Node3D:
	var scene := Scene.new()
	scene.set("startup_options",options); scene.set("initial_save",save)
	scene.settings_storage = Settings.new("user://tests/career-startup-settings.json")
	if disk: scene.storage = disk
	scene.set_physics_process(false)
	root.add_child(scene)
	await process_frame
	return scene

func _dispose(scene: Node) -> void:
	scene.queue_free(); await process_frame; await process_frame

func _receipt(scene: Node) -> Dictionary:
	var value: Variant = scene.get("startup_receipt")
	return value if value is Dictionary else {}

func _run() -> void:
	root.size = Vector2i(1600,900)
	for options: Dictionary in [{"seed":-1},{"seed":4294967296},{"seed":1.5},{"seed":true},{"seed":"2"},{"seed":NAN},{"captainName":null},{"captainName":" "},{"captainName":"海".repeat(25)},{"captainName":"海\n军"},{"campaignId":"constructor"},{"campaignId":2}]:
		var rejected := await _mount(options)
		check(_receipt(rejected).get("ok") == false and not _receipt(rejected).get("reason","").is_empty(),"invalid startup returns useful rejection: "+str(options))
		check(rejected.sea == null and rejected.interface == null,"invalid startup creates no sea or interface")
		await _dispose(rejected)
	var invalid := await _mount({},"{broken")
	check(_receipt(invalid).get("ok") == false and _receipt(invalid).get("reason") == "save-invalid","invalid initial save has truthful nonfatal rejection")
	check(invalid.sea == null and invalid.interface == null,"invalid save creates no world or UI")
	await _dispose(invalid)
	var fresh := await _mount({"seed":4294967295,"captainName":"  郑 海  ","campaignId":"career-custom"})
	check(_receipt(fresh).get("ok") == true,"valid bounded startup succeeds")
	var state: Dictionary = fresh.runtime.snapshot().campaign
	check(state.seed == 4294967295 and state.captain.name == "郑 海" and state.campaignId == "career-custom","real campaign receives seed, trimmed native captain and identity")
	check(fresh.runtime.snapshot().naval.playerId == "career-custom-flagship","custom identity reaches real native authority")
	check(not fresh.interface.is_menu_open() and not fresh.runtime.is_paused(),"fresh startup runs without restore pause")
	await _dispose(fresh)
	var title_before := "Career staged sentinel"
	root.title = title_before; Engine.physics_ticks_per_second = 48; root.msaa_3d = Viewport.MSAA_DISABLED
	var staged := await _mount({"staged":true,"seed":0,"captainName":"候选船长"})
	check(_receipt(staged).get("ok") == true and staged.runtime.snapshot().campaign.seed == 0,"staged new game prepares real zero seed")
	check(root.title == title_before and Engine.physics_ticks_per_second == 48 and root.msaa_3d == Viewport.MSAA_DISABLED,"staged readiness preserves window, physics and viewport globals")
	check(staged.runtime.snapshot().runtime.pauseReasons.has("loading") and staged.services.audio.diagnostics().state == "paused" and staged.runtime.advance(1.0) == 0,"staged new authority and audio pause before first presented frame")
	if staged.has_method("activate_entry"): staged.call("activate_entry")
	check(root.title == "海上明旗 · 1650 厦金护粮" and Engine.physics_ticks_per_second == 60 and root.msaa_3d == Viewport.MSAA_4X,"activation applies actual window, physics and viewport settings")
	check(not staged.runtime.snapshot().runtime.pauseReasons.has("loading") and staged.runtime.advance(1.0/60.0) > 0,"new game activation releases staging pause")
	await _dispose(staged)
	var source := Runtime.new()
	check(source.configure(func(_x: float,_z: float)->float: return -24.0,Campaign.new(98765,"存档船长","restored-career")).ok,"real source builds save fixture")
	var acceptance: Dictionary = source.command({"type":"accept-convoy","commandId":"startup-fixture-accept","expectedRevision":source.snapshot().campaign.revision})
	check(acceptance.ok,"saved convoy acceptance grants real native flagship authority: "+str(acceptance))
	var exported: Dictionary = source.export_save(UTC)
	check(exported.ok,"real v2 export succeeds in safe port")
	var disk := Storage.new(PATH)
	check(disk.write_checkpoint(exported.json).ok,"real checkpoint fixture is committed")
	var prior: String = FileAccess.get_file_as_string(PATH)
	var backup := "preexisting backup bytes"
	var file := FileAccess.open(PATH+".backup",FileAccess.WRITE); file.store_string(backup); file.close()
	var restored := await _mount({"seed":1,"captainName":"New Captain"},exported.json,disk)
	check(_receipt(restored).get("ok") == true,"continue restores actual v2 checkpoint")
	state = restored.runtime.snapshot().campaign
	check(state.seed == 98765 and state.captain.name == "存档船长" and state.campaignId == "restored-career","restore keeps saved identity rather than new-game options")
	check(restored.runtime.snapshot().naval.playerId == "restored-career-flagship" and restored.runtime.snapshot().runtime.controllableShipIds.has("restored-career-flagship"),"restored identity has native control policy")
	check(FileAccess.get_file_as_string(PATH) == prior and FileAccess.get_file_as_string(PATH+".backup") == backup and not FileAccess.file_exists(PATH+".rollback"),"ordinary continue preserves checkpoint and backup bytes")
	check(restored.interface.is_menu_open() and restored.runtime.snapshot().runtime.pauseReasons.has("loading") and restored.runtime.snapshot().runtime.pauseReasons.has("menu"),"restore opens actual menu with loading and menu pause")
	var before: Dictionary = restored.runtime.snapshot()
	check(restored.runtime.advance(1.0) == 0 and restored.runtime.snapshot().naval == before.naval,"restored native state remains frozen before real menu close")
	restored.runtime.set_pause("player",true); restored.interface.close_menu()
	check(not restored.interface.is_menu_open() and not restored.runtime.snapshot().runtime.pauseReasons.has("loading") and not restored.runtime.snapshot().runtime.pauseReasons.has("menu") and restored.runtime.snapshot().runtime.pauseReasons.has("player"),"actual menu close releases loading and menu, retains independent player pause")
	restored.runtime.set_pause("player",false)
	check(restored.runtime.advance(1.0/60.0) > 0,"real restored game resumes after menu close")
	await _dispose(restored)
	root.title = title_before; Engine.physics_ticks_per_second = 48; root.msaa_3d = Viewport.MSAA_DISABLED
	var staged_restore := await _mount({"staged":true},exported.json,disk)
	check(_receipt(staged_restore).get("ok") == true and root.title == title_before and Engine.physics_ticks_per_second == 48,"staged restore remains ready without global activation")
	if staged_restore.has_method("activate_entry"): staged_restore.call("activate_entry")
	check(staged_restore.interface.is_menu_open() and staged_restore.runtime.snapshot().runtime.pauseReasons.has("loading") and staged_restore.runtime.snapshot().runtime.pauseReasons.has("menu") and staged_restore.runtime.advance(1.0) == 0,"restore activation retains actual menu/loading review pause")
	staged_restore.interface.close_menu()
	check(not staged_restore.runtime.is_paused() and staged_restore.runtime.advance(1.0/60.0) > 0,"activated restore still resumes through actual menu close")
	await _dispose(staged_restore)
	var failing := await _mount({},exported.json,FailedStorage.new(PATH))
	check(_receipt(failing).get("ok") == true and failing.interface != null,"ordinary continue succeeds even with injected write-failure storage")
	var active: Dictionary = failing.runtime.snapshot()
	failing._command({"type":"import-save","json":exported.json})
	check(failing.runtime.snapshot().campaign == active.campaign and failing.runtime.snapshot().naval == active.naval and failing.runtime.snapshot().runtime.notice == "injected-write-failure","explicit import remains transactional with injected storage")
	check(FileAccess.get_file_as_string(PATH) == prior and FileAccess.get_file_as_string(PATH+".backup") == backup,"failed import preserves disk bytes")
	await _dispose(failing)
	source.dispose()
	for suffix in ["",".backup",".rollback",".staged"]:
		if FileAccess.file_exists(PATH+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH+suffix))
	await create_timer(0.08).timeout
	print("CAREER_STARTUP_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
