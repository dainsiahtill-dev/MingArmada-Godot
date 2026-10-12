extends "res://tools/capture-reference-events.gd"
## Private bounded capture using the existing QA menu and actual cannon input.
## This demonstrates shared presentation; it is not a career rescue acceptance.
func _initialize()->void:
	directory="res://Temp/detail-visual-audit-2026-10-13"
	run.call_deferred()
func run()->void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(directory)):
		printerr("Fresh visual audit directory required");quit(1);return
	create_timer(90.0).timeout.connect(func():printerr("Detail audit watchdog expired");quit(1))
	root.size=Vector2i(1600,900);root.content_scale_size=root.size
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var prefix:="user://verification/detail-audit-%d"%OS.get_process_id()
	var packed:PackedScene=load(ProjectSettings.get_setting("application/run/main_scene"))
	main=packed.instantiate();main.router=Router.new({"dev":true,"mingqi_storage":Storage.new(prefix+"-v2.json"),"legacy_storage":Storage.new(prefix+"-v1.json"),"settings_storage":Settings.new(prefix+"-settings.json")});root.add_child(main)
	root.grab_focus();await frames()
	var qa:Button=main.menu._buttons.qa
	main.menu._scroll.ensure_control_visible(qa);await frames();await click(qa)
	for unused in 180:
		if main.current_scene:break
		await process_frame
	check(main.current_scene!=null,"existing QA menu opens the shared production world")
	if main.current_scene==null:main.free();quit(1);return
	scene=main.current_scene;scene.set_process(false);scene.set_physics_process(false)
	await choose("damage")
	await capture_close("damaged-player","player")
	await capture_close("damaged-voc","inspection-voc")
	await choose("impact")
	await capture_close("crew-before-hit","inspection-voc")
	await click(scene.interface.find_child("fire_starboard",true,false))
	var hit:=false
	for unused in 150:
		await tick()
		if scene.inspection_snapshot().sailors.impacts.active>0:
			hit=true;await capture_close("crew-actual-hit","inspection-voc");break
	check(hit,"actual cannon creates physical crew rigs")
	if hit:
		await advance_ticks(18);await capture_close("crew-actual-hit-plus-0-3s","inspection-voc")
	await click(scene.interface.find_child("main_menu",true,false));await frames()
	check(main.current_scene==null and main.menu.visible,"audit exits back to its owning menu")
	main.queue_free();await frames()
	print("DETAIL_VISUAL_AUDIT captures=",captures," failures=",failures)
	quit(1 if failures else 0)
