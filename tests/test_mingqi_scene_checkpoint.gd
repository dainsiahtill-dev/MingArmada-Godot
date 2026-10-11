extends SceneTree
const Scene = preload("res://game/scenes/mingqi/mingqi_scene.gd")
const Storage = preload("res://game/persistence/save_coordinator.gd")
const Settings = preload("res://game/persistence/user_settings.gd")
var failures := 0
var assertions := 0
var base := "user://tests/checkpoint-ui-%d" % OS.get_process_id()
var exits := 0
var exports := 0
func check(value: bool, detail: String) -> void:
	assertions += 1
	if not value: failures += 1; printerr("FAIL: ",detail)
func _initialize() -> void: _run.call_deferred()
func _mount(path: String, saved: String = "") -> Node3D:
	var scene := Scene.new()
	scene.storage = Storage.new(path)
	scene.settings_storage = Settings.new(base+"/settings.json")
	scene.initial_save = saved
	scene.set_physics_process(false)
	root.add_child(scene)
	await process_frame
	scene.set_physics_process(false); scene.runtime.set_pause("checkpoint-test",true)
	check(scene.startup_receipt.get("ok",false),"real scene starts")
	return scene
func _status(scene: Node) -> String: return str(scene.interface._packet.runtime.get("saveStatus",""))
func _backup_button(scene: Node) -> Button: return scene.interface.find_child("export_backup",true,false)
func _run() -> void:
	root.size = Vector2i(1600,900)
	var path := base+"/checkpoint.json"
	var scene := await _mount(path)
	scene.main_menu_requested.connect(func(): exits += 1)
	scene.interface.open_menu()
	check(not scene.interface._packet.runtime.get("hasCheckpoint",true) and _backup_button(scene).disabled,"fresh scene has no verified recovery")
	var raw: FileAccess
	# A raw disk backup must not turn into a source-verified recovery checkpoint.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base))
	raw = FileAccess.open(path+".backup",FileAccess.WRITE); raw.store_string("unvalidated recovery bytes"); raw.close()
	scene._present(0)
	check(_backup_button(scene).disabled,"raw disk backup never enables verified recovery")
	var save_button: Button = scene.interface.find_child("save",true,false)
	save_button.pressed.emit()
	var prior: String = scene.storage.read_checkpoint().json
	check(scene.interface._packet.runtime.get("hasCheckpoint",false) and not _backup_button(scene).disabled,"first confirmed save enables latest verified checkpoint")
	check(_status(scene).contains("已验证") and _status(scene).contains("保存"),"successful save gives persistent actual status")
	scene._command({"type":"pause"})
	check(_status(scene).contains("已验证"),"unrelated command preserves save result")
	var live: Dictionary = scene.runtime.snapshot()
	var blocked := base+"/blocked"
	raw = FileAccess.open(blocked,FileAccess.WRITE); raw.store_string("file blocks directory"); raw.close()
	scene.storage.path = blocked+"/checkpoint.json"
	scene._command({"type":"save-and-menu"})
	check(_status(scene).contains("未能保存") and _status(scene).contains("写入失败") and exits == 0,"real blocked-path write failure gives truthful status and prevents leave: "+_status(scene))
	check(scene.interface._packet.runtime.get("hasCheckpoint",false),"write failure preserves confirmed recovery")
	scene._command({"type":"export-save","kind":"backup"})
	check(_status(scene).contains("已导出"),"recovery export uses latest confirmed bytes despite disk failure")
	check(scene._checkpoint_export().json == prior,"recovery returns latest exact verified bytes, not older raw backup")
	scene.interface.command_requested.connect(func(intent: Dictionary):
		if intent.type == "export-save": exports += 1)
	_backup_button(scene).pressed.emit(); _backup_button(scene).pressed.emit()
	check(exports == 2,"actual recovery export button remains usable after successful export")
	check(scene.runtime.snapshot().campaign.captain == live.campaign.captain and scene.runtime.snapshot().campaign.simulationSeconds == live.campaign.simulationSeconds,"failed save and recovery export preserve captain and simulation clock")
	scene._command({"type":"import-save","json":"{broken"})
	check(_status(scene).contains("导入未成功"),"invalid restore replaces stale export status")
	check(scene.runtime.snapshot().runtime.generation == live.runtime.generation and scene._checkpoint_export().json == prior,"failed restore preserves live generation and verified recovery")
	scene._command({"type":"import-save","json":prior})
	check(_status(scene).contains("导入未成功") and _status(scene).contains("写入失败") and scene.runtime.snapshot().runtime.generation == live.runtime.generation and scene._checkpoint_export().json == prior,"real failed import write preserves generation and checkpoint")
	scene.storage.path = path
	# UI debounce uses wall ticks; SceneTreeTimer uses frame delta and can expire
	# early in wall time after a long headless startup frame.
	var save_key := JSON.stringify({"type":"save"})
	var retry_after := int(scene.interface._recent.get(save_key,Time.get_ticks_msec()))+250
	while Time.get_ticks_msec() < retry_after: await process_frame
	scene.interface.find_child("save",true,false).pressed.emit()
	check(_status(scene).contains("已验证") and not _status(scene).contains("未能"),"real retry clears previous failure")
	prior = scene.storage.read_checkpoint().json
	scene._command({"type":"import-save","json":prior})
	check(_status(scene).contains("载入") and scene._checkpoint_export().json == scene.storage.read_checkpoint().json and scene.interface.is_menu_open(),"successful import records actual newly confirmed bytes and opens paused review")
	prior = scene.storage.read_checkpoint().json
	scene.queue_free(); await process_frame; await process_frame
	var continued := await _mount(path,prior)
	continued.interface.open_menu()
	check(continued.interface._packet.runtime.get("hasCheckpoint",false) and not _backup_button(continued).disabled,"continue verifies exact disk bytes and enables source recovery")
	check(FileAccess.get_file_as_string(path) == prior,"continue never rewrites checkpoint")
	continued.queue_free(); await process_frame; await process_frame
	var other := prior.replace(".000Z",".001Z")
	check(Storage.new(path).write_checkpoint(other).ok,"valid changed disk checkpoint fixture")
	var mismatch := await _mount(path,prior)
	check(not mismatch.interface._packet.runtime.get("hasCheckpoint",true),"valid mismatched disk bytes cannot fabricate injected continue checkpoint")
	mismatch.queue_free(); await process_frame; await process_frame
	raw = FileAccess.open(path,FileAccess.WRITE); raw.store_string("{broken"); raw.close()
	var corrupt := await _mount(path,prior)
	check(not corrupt.interface._packet.runtime.get("hasCheckpoint",true) and not corrupt._checkpoint_export().ok,"corrupt disk cannot establish checkpoint from valid injected continue bytes")
	corrupt.queue_free(); await process_frame; await process_frame
	await create_timer(0.1).timeout
	for file in [path,path+".backup",blocked,base+"/settings.json"]:
		if FileAccess.file_exists(file): DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(base))
	print("MINGQI_SCENE_CHECKPOINT_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
