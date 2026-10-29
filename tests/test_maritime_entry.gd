extends SceneTree
const Menu = preload("res://game/ui/menu/main_menu.gd")
const Router = preload("res://game/runtime/game_router.gd")
const Main = preload("res://game/scenes/main/main_scene.gd")
const Settings = preload("res://game/persistence/user_settings.gd")
const Storage = preload("res://game/persistence/save_coordinator.gd")
var assertions := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ",detail)
func frames(count: int = 8) -> void:
	for i in count: await process_frame
func fixture_hashes(prefix: String) -> Dictionary:
	var result := {}
	for name: String in ["-settings.json","-v2.json","-v1.json"]:
		for suffix: String in ["",".backup",".rollback",".staged"]:
			var path := prefix+name+suffix
			result[path]=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
	return result
func _run() -> void:
	root.size=Vector2i(1280,720); root.content_scale_size=root.size
	var prefix := "user://tests/maritime-entry-"+str(OS.get_process_id())
	var settings := Settings.new(prefix+"-settings.json")
	var main := Main.new()
	main.router=Router.new({"mingqi_storage":Storage.new(prefix+"-v2.json"),"legacy_storage":Storage.new(prefix+"-v1.json"),"settings_storage":settings})
	root.add_child(main); await frames()
	var menu: Control=main.menu
	var viewport_rect:=Rect2(Vector2.ZERO,Vector2(root.size))
	for id in ["Settings","quit"]:
		var control:=menu.find_child(id,true,false) as Control
		check(viewport_rect.encloses(control.get_global_rect()),"1280 first screen exposes "+id)
	var button:=menu.find_child("world-atlas",true,false) as Button
	check(button!=null,"ordinary main menu exposes real world atlas")
	var profile_before:=fixture_hashes(prefix)
	if button:
		button.pressed.emit(); button.pressed.emit(); await frames(20)
		check(is_instance_valid(main.current_scene),"world atlas enters through normal staged router")
		if is_instance_valid(main.current_scene):
			var atlas: Control=main.current_scene
			check(atlas.get_script().resource_path=="res://game/ui/charts/world_atlas.gd","route constructs geographic atlas")
			check(atlas.is_visible_in_tree() and not menu.visible,"committed atlas replaces menu")
			check(atlas.size==Vector2(root.size),"staged Control receives complete viewport")
			check(atlas.select_port("hirado"),"real port can be selected after normal entry")
			check(atlas.zoom_at(2.0),"entered atlas supports zoom")
			atlas.main_menu_requested.emit(); await frames()
			check(main.current_scene==null and menu.visible,"atlas returns via owned scene lifecycle")
			check(not is_instance_valid(atlas),"returned atlas is released")
		check(fixture_hashes(prefix)==profile_before,"geographic browsing preserves all fixture settings, voyage, backup and staged bytes")
	check(not settings.snapshot().sound and not settings.snapshot().music,"fresh game keeps sound and music off")
	root.size=Vector2i(320,480); root.content_scale_size=root.size; await frames()
	var a:=menu.find_child("duel",true,false) as Button
	var b:=menu.find_child("fleet",true,false) as Button
	check(b.get_global_rect().position.y>=a.get_global_rect().end.y,"320 menu battle choices use distinct full-width rows")
	check(a.size.x>=200 and b.size.x>=200,"320 buttons keep practical hit widths")
	main.free(); await frames(2)
	print("MARITIME_ENTRY_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
