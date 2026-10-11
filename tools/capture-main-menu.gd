extends SceneTree
## Captures actual native Controls. This does not exercise the game router.
const Menu = preload("res://game/ui/menu/main_menu.gd")
const Settings = preload("res://game/persistence/user_settings.gd")
const Storage = preload("res://game/persistence/save_coordinator.gd")
var failed := false
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var settings := Settings.new(); settings.load_settings()
	var checkpoint: Dictionary = Storage.new().read_checkpoint()
	var model := {"settings":settings.snapshot(),"hasLegacySave":FileAccess.file_exists("user://saves/legacy-v1.json"),"mingqiSlot":"present" if checkpoint.ok else "missing" if checkpoint.get("reason") == "save-not-found" else "unreadable","dev":true,"qa":false}
	var menu := Menu.new(); root.add_child(menu); menu.apply_view_model(model,1)
	DisplayServer.window_set_title("海上明旗 · 原生主菜单画面验收")
	for item in [{"label":"main-menu-wide","size":Vector2i(1600,900)},{"label":"main-menu-narrow","size":Vector2i(320,480)}]:
		root.size = item.size
		root.content_scale_size = item.size
		for frame in 8: await process_frame
		await RenderingServer.frame_post_draw
		var directory := "res://docs/migration/evidence/menu"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
		var pixels := root.get_texture().get_image()
		var saved := pixels.save_png(directory+"/"+item.label+".png")
		if saved != OK: failed = true; push_error("Native menu capture failed: "+str(saved))
		var metadata := {"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"viewport":[pixels.get_width(),pixels.get_height()],"confirmedModel":model,"scope":"native menu Controls only; game router not exercised"}
		var file := FileAccess.open(directory+"/"+item.label+".json",FileAccess.WRITE)
		if file: file.store_string(JSON.stringify(metadata,"\t")); file.close()
		else: failed = true; push_error("Native menu metadata write failed")
	menu.queue_free(); await process_frame; await process_frame
	print("NATIVE_MAIN_MENU_CAPTURE_COMPLETE failures=",int(failed))
	quit(1 if failed else 0)
