extends SceneTree
var assertions:=0
var failures:=0
func check(value: bool,detail: String) -> void:
	assertions+=1
	if not value: failures+=1; printerr("FAIL: ",detail)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var started_ms:=Time.get_ticks_msec()
	var path:="res://game/scenes/visual_qa/visual_qa.tscn"
	check(ResourceLoader.exists(path),"native visual QA scene and inspector exist")
	if ResourceLoader.exists(path):
		root.size=Vector2i(1600,900)
		var settings_path:="user://migration-verification/visual-qa-settings-%d.json" % OS.get_process_id()
		var scene=load(path).instantiate(); scene.startup_options={"qa":true,"staged":true,"scenario":"impact-weak"}
		scene.settings_storage=load("res://game/persistence/user_settings.gd").new(settings_path)
		root.add_child(scene); await process_frame; scene.set_physics_process(false); scene.set_process(false)
		print("VISUAL_QA_LIFECYCLE_STAGE startup elapsed_ms=",Time.get_ticks_msec()-started_ms)
		check(scene.startup_receipt.ok and scene.runtime.is_paused(),"trusted QA gate and staged startup stay frozen")
		check(scene.sea.ships.size()==2 and scene.interface.find_child("scenario",true,false).item_count==15,"actual original ships and fifteen native scene choices")
		scene.activate_entry()
		check(not scene.runtime.is_paused(),"activation starts prepared native scene")
		# Long articulated-hit recovery has its own real-scene integration test.
		# This script keeps UI, settings, export, restart and scene ownership
		# orthogonal; one real interval still populates its diagnostic export.
		scene._physics_process(1.0/60.0)
		check(scene.inspection_snapshot().sailors.ships.size()==2,"inspector copies actual crews, roles, LOD and native facts")
		scene._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT); scene._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
		check(scene.runtime.is_paused(),"focus recovery waits for visible Continue")
		var paused: Dictionary=scene.runtime.snapshot().naval; scene._physics_process(0.1)
		check(paused==scene.runtime.snapshot().naval,"focused window cannot silently advance paused authority")
		scene.interface.find_child("resume",true,false).pressed.emit()
		check(not scene.runtime.is_paused(),"actual Continue clears focus pause")
		scene._command({"type":"handling","value":"realistic"})
		scene.runtime.set_held("KeyA",true)
		scene.services.change_settings({"quality":"low"})
		print("VISUAL_QA_LIFECYCLE_STAGE quality elapsed_ms=",Time.get_ticks_msec()-started_ms)
		check(scene.runtime.snapshot().runtime.handlingMode=="realistic","QA handling survives unrelated persisted quality settings")
		check(scene.runtime.simulation._held.has("KeyA"),"unrelated settings preserve QA held input instead of transient handling reset")
		scene.runtime.set_held("KeyA",false)
		check(scene.has_method("set_visibility_paused"),"hidden lifecycle has real native scene adapter")
		if scene.has_method("set_visibility_paused"):
			scene.set_visibility_paused(true); scene.set_visibility_paused(false)
			check(scene.runtime.is_paused(),"hidden recovery keeps explicit Continue pause")
		scene._command({"type":"resume"})
		var exported: Dictionary=scene.export_diagnostics("user://visual-qa-test.json")
		check(exported.ok and FileAccess.file_exists("user://visual-qa-test.json"),"native inspector exports real JSON diagnostic snapshot")
		if exported.ok:
			var data=JSON.parse_string(FileAccess.get_file_as_string("user://visual-qa-test.json"))
			check(data.schema=="ming-armada-native-frame-diagnostics-v1" and data.metadata.scenario=="impact-weak" and not data.samples.is_empty(),"JSON includes actual scenario, raw intervals and native diagnostics")
			DirAccess.remove_absolute("user://visual-qa-test.json")
		var old_pool=scene.sea.sailors["inspection-voc"].get_impact_pool()
		scene.interface.find_child("restart",true,false).pressed.emit()
		print("VISUAL_QA_LIFECYCLE_STAGE restart elapsed_ms=",Time.get_ticks_msec()-started_ms)
		check(scene.runtime.snapshot().naval.tick==0 and not is_instance_valid(old_pool),"same battle ID restart releases prior models and impact pools")
		root.size=Vector2i(320,480); root.content_scale_size=Vector2i(320,480)
		await process_frame; await process_frame; await process_frame
		check(scene.interface._panel.get_rect().end.x<=320 and scene.interface._panel.get_rect().end.y<=480,"native QA inspector remains inside narrow viewport")
		var count:=[0]; scene.main_menu_requested.connect(func(): count[0]+=1)
		scene.interface.find_child("main_menu",true,false).pressed.emit()
		check(count[0]==1,"native QA exit reaches owner menu signal")
		scene.queue_free(); await process_frame; await process_frame; await create_timer(0.08).timeout
		for suffix in ["",".backup",".rollback",".staged"]:
			if FileAccess.file_exists(settings_path+suffix): DirAccess.remove_absolute(settings_path+suffix)
	print("VISUAL_QA_SCENE_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
