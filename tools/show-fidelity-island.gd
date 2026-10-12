extends SceneTree
const Main = preload("res://game/scenes/main/main_scene.gd")
func _initialize() -> void: _open.call_deferred()
func _open() -> void:
	root.size=Vector2i(1600,900)
	var main:=Main.new(); root.add_child(main)
	await process_frame
	var button: Button=main.menu.find_child("fidelity-island",true,false)
	if button==null or button.disabled:
		printerr("FIDELITY_ISLAND_INTERACTIVE_OPEN failed=menu-entry-unavailable"); quit(1); return
	button.pressed.emit()
	for frame in 300:
		await process_frame
		if is_instance_valid(main.current_scene):
			if not main.current_scene.startup_receipt.get("ok",false):
				printerr("FIDELITY_ISLAND_INTERACTIVE_OPEN failed=scene-startup"); quit(1); return
			print("FIDELITY_ISLAND_INTERACTIVE_OPEN ready=true route=normal-menu gpu=",RenderingServer.get_video_adapter_name())
			return
	printerr("FIDELITY_ISLAND_INTERACTIVE_OPEN failed=entry-timeout"); quit(1)
