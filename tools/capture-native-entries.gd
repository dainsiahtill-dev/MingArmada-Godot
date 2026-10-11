extends SceneTree
## Actual menu Controls, routes, source models and GPU viewport; isolated test slots.
const Router=preload("res://game/runtime/game_router.gd")
const Storage=preload("res://game/persistence/save_coordinator.gd")
const Settings=preload("res://game/persistence/user_settings.gd")
const Legacy=preload("res://game/runtime/legacy_runtime.gd")
const Campaign=preload("res://game/domain/mingqi/campaign.gd")
var main: Node
var failures:=0
var captures:=0
var directory:="res://docs/migration/evidence/entries"
func _initialize() -> void: run.call_deferred()
func frames(count: int=5) -> void:
	for frame in count: await process_frame
func click(control: Control) -> void:
	var point:=control.get_global_rect().get_center()
	var event:=InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=true; event.position=point
	Input.parse_input_event(event); await process_frame
	event=event.duplicate(); event.pressed=false; Input.parse_input_event(event); await process_frame
func capture(label: String,extra: Dictionary={}) -> void:
	await frames(); await RenderingServer.frame_post_draw
	var pixels:=root.get_texture().get_image()
	if pixels.save_png(directory+"/"+label+".png")!=OK: failures+=1; printerr("FAIL capture ",label); return
	var metadata: Dictionary={"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"viewport":[pixels.get_width(),pixels.get_height()],"generation":main.router.generation,"mode":"menu","scope":"actual native menu route and GPU viewport"}
	if main.current_scene:
		var scene: Node=main.current_scene
		metadata.mode="native-entry"
		metadata.scene=scene.get_script().resource_path
		if scene.has_method("snapshot"): metadata.state=scene.snapshot()
		else:
			for property in scene.get_property_list():
				if property.name=="runtime": metadata.state=scene.runtime.snapshot()
	metadata.merge(extra,true)
	var file:=FileAccess.open(directory+"/"+label+".json",FileAccess.WRITE); file.store_string(JSON.stringify(metadata,"\t")); file.close(); captures+=1
func enter(mode: String) -> Node:
	var button: Button=main.menu._buttons[mode]
	main.menu._scroll.ensure_control_visible(button); await frames(3); await click(button)
	for frame in 180:
		if main.current_scene: break
		await process_frame
	if not main.current_scene:
		await capture("entry-failed-"+mode,{"buttonRect":str(button.get_global_rect()),"scroll":main.menu._scroll.scroll_vertical})
		failures+=1; printerr("FAIL entry ",mode," phase=",main.menu._phase); return null
	var scene: Node=main.current_scene; scene.set_physics_process(false); scene.set_process(false)
	return scene
func leave() -> void:
	if main.current_scene: main.current_scene.main_menu_requested.emit()
	await frames(4)
	if main.current_scene or not main.menu.visible: failures+=1; printerr("FAIL return-menu")
func run() -> void:
	root.size=Vector2i(1600,900); root.content_scale_size=Vector2i(1600,900)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var prefix:="user://tests/native-entry-capture-%s" % OS.get_process_id()
	var slot:=Storage.new(prefix+"-v2.json"); var old:=Storage.new(prefix+"-v1.json",Legacy.validate_save)
	var main_path: String=ProjectSettings.get_setting("application/run/main_scene")
	var packed:=load(main_path) as PackedScene
	if not packed: printerr("FAIL default main scene"); quit(1); return
	main=packed.instantiate(); main.router=Router.new({"dev":true,"mingqi_storage":slot,"legacy_storage":old,"settings_storage":Settings.new(prefix+"-settings.json")}); root.add_child(main)
	await capture("menu-wide")
	main.menu._scroll.ensure_control_visible(main.menu._settings); await frames(3); await click(main.menu._settings)
	await capture("menu-settings")
	var escape:=InputEventKey.new(); escape.physical_keycode=KEY_ESCAPE; escape.pressed=true
	Input.parse_input_event(escape); await frames()
	if main.settings_panel.visible: failures+=1; printerr("FAIL physical-Esc menu settings")
	main.menu._scroll.scroll_vertical=0; await frames()
	var raw_file:=FileAccess.open(slot.path,FileAccess.WRITE); raw_file.store_string("{damaged-original"); raw_file.close()
	await click(main.menu._buttons["mingqi-continue"]); await capture("recovery-invalid")
	main.recovery._json.text=Campaign.new(1661,"郑海帆").serialize()
	main.recovery._scroll.ensure_control_visible(main.recovery._buttons.ImportJSONButton); await frames(3); await click(main.recovery._buttons.ImportJSONButton)
	for frame in 180:
		if main.current_scene: break
		await process_frame
	if main.current_scene:
		main.current_scene.set_physics_process(false)
		await capture("recovered-1650-menu",{"checkpointValid":slot.read_checkpoint().ok,"backupRaw":slot.read_backup().get("json","")})
	else: failures+=1; printerr("FAIL recovery import")
	await leave()
	for mode in ["mingqi","career","duel","fleet","sail"]:
		var scene: Node=await enter(mode)
		if not scene: continue
		if mode in ["duel","fleet","sail"]:
			for tick in 60: scene._physics_process(1.0/60)
		if mode=="sail": scene._command({"type":"chart","value":true})
		await capture(mode+"-native")
		if mode=="duel":
			root.size=Vector2i(320,480); root.content_scale_size=Vector2i(320,480); await capture("duel-narrow")
			root.size=Vector2i(1600,900); root.content_scale_size=Vector2i(1600,900); await frames()
		await leave()
	var book: Node=await enter("ships")
	if book:
		for kind in ["fuchuan","fisherman","merchant","voc","patrol","heavy"]:
			book.select_ship(kind,0); await capture("shipbook-"+kind)
		await leave()
	var practice: Node=await enter("practice")
	if practice:
		for kind in ["duel","landBattle","treasure","banquet"]:
			var choice: OptionButton=practice.find_child("PracticeKind",true,false)
			choice.select(practice.KINDS.find(kind)); choice.item_selected.emit(practice.KINDS.find(kind))
			await capture("practice-"+kind)
		await leave()
	main.queue_free(); await frames(3); await create_timer(.1).timeout
	print("NATIVE_ENTRY_CAPTURE_COMPLETE captures=",captures," failures=",failures)
	quit(1 if failures else 0)
