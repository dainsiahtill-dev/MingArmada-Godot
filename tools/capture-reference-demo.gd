extends SceneTree
const Router = preload("res://game/runtime/game_router.gd")
const Storage = preload("res://game/persistence/save_coordinator.gd")
const Settings = preload("res://game/persistence/user_settings.gd")
var main: Node
var scene: Control
var failures := 0
var captures := 0
var directory := "res://docs/migration/evidence/reference-demo-port"

func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	if not value: failures += 1; printerr("FAIL ",message)
func frames(count: int=6) -> void:
	for index in count: await process_frame
func capture(label: String) -> void:
	await frames(); await RenderingServer.frame_post_draw
	var image: Image = scene.view.get_texture().get_image()
	var ui := root.get_texture().get_image()
	check(image.save_png(directory+"/"+label+".png") == OK,"actual native viewport writes "+label)
	check(ui.save_png(directory+"/"+label+"-ui.png") == OK,"actual native controls write "+label)
	var data := {"route":"actual MainScene menu water-study button","engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"renderingMethod":RenderingServer.get_current_rendering_method(),"viewport":[image.get_width(),image.get_height()],"snapshot":scene.inspection_snapshot(),"sourceHeightSha256":FileAccess.get_sha256("res://assets/data/reference_cat_island_h.json"),"pngSha256":FileAccess.get_sha256(directory+"/"+label+".png"),"scope":"Actual Godot GPU scene. Fixed accepted time and source app state for visual comparison, no FPS claim."}
	var file := FileAccess.open(directory+"/"+label+".json",FileAccess.WRITE)
	check(file != null,"actual native metadata writes "+label)
	if file: file.store_string(JSON.stringify(data,"\t")); file.close()
	captures += 1

func run() -> void:
	root.size = Vector2i(1600,900); root.content_scale_size = root.size
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var prefix := "user://tests/reference-demo-%d" % OS.get_process_id()
	var packed: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	main = packed.instantiate()
	main.router = Router.new({"mingqi_storage":Storage.new(prefix+"-v2.json"),"legacy_storage":Storage.new(prefix+"-v1.json"),"settings_storage":Settings.new(prefix+"-settings.json")})
	root.add_child(main); await frames()
	var button: Button = main.menu.find_child("water-study",true,false)
	check(button != null and button.visible,"actual menu offers island-water scene")
	if button == null: quit(1); return
	main.menu._scroll.ensure_control_visible(button); button.pressed.emit()
	for frame in 180:
		if main.current_scene: break
		await process_frame
	check(main.current_scene != null,"actual menu routes direct port")
	if main.current_scene == null: quit(1); return
	scene = main.current_scene; scene.set_process(false)
	check(scene.startup_receipt.ok,"scene startup receipt")
	scene.seconds = 4.2; scene.set_state({"preset":"clear"})
	scene.find_child("WaterPause",true,false).pressed.emit()
	check(scene.state.paused,"actual pause control applies source state")
	await capture("clear")
	var original_time: float = scene.seconds
	await frames(20); await capture("paused")
	check(scene.seconds == original_time,"paused GPU scene preserves accepted time")
	scene.find_child("Water_reflection",true,false).button_pressed = false
	check(not scene.state.reflection,"actual reflection checkbox changes shader state")
	await capture("reflection-off")
	scene.find_child("Water_reflection",true,false).button_pressed = true
	scene.find_child("Water_foam",true,false).button_pressed = false
	check(not scene.state.foam,"actual foam checkbox changes shader state")
	await capture("foam-off")
	scene.set_state({"foam":true,"caustics":false}); await capture("caustics-off")
	scene.set_state({"caustics":true,"waves":false}); await capture("waves-off")
	scene.set_state({"waves":true}); scene.find_child("Water_tide",true,false).value = 3.5
	check(scene.state.tide == 3.5,"actual tide slider changes shoreline")
	await capture("high-tide")
	scene.set_state({"tide":-2.0}); await capture("low-tide")
	scene.set_state({"tide":0.0}); scene.find_child("WaterPreset",true,false).item_selected.emit(1)
	check(scene.state.preset == "sunset" and scene.state.strength == 0.65,"actual preset control changes source light and strength")
	await capture("sunset")
	scene.set_state({"preset":"storm"}); await capture("storm")
	scene.set_state({"preset":"clear"}); scene.seconds = 4.8; scene.advance_time(0.0,false); await capture("clear-4-8s")
	scene.orbit.elevation = 0.22; scene.orbit.distance = 140.0
	scene._update_camera(); scene.advance_time(0.0,false); await capture("low-angle")
	scene.set_state({"reflection":false}); await capture("low-angle-reflection-off")
	scene.set_state({"reflection":true}); scene.find_child("WaterReset",true,false).pressed.emit()
	root.size = Vector2i(960,680); root.content_scale_size = root.size
	await frames(12); scene.advance_time(0.0,false); await capture("resized")
	root.size = Vector2i(1717,1102); root.content_scale_size = root.size
	await frames(12)
	scene.set_state({"waves":false,"foam":false,"caustics":false,"preset":"clear"})
	await capture("static-source-state")
	var exported: Dictionary = await scene.save_frame(directory+"/native-saved-frame.png")
	check(exported.ok,"native PNG save control path")
	scene.main_menu_requested.emit(); await frames()
	check(main.current_scene == null and main.menu.visible,"actual scene exit returns to owner menu")
	main.queue_free(); await frames()
	print("REFERENCE_DEMO_CAPTURE_COMPLETE captures=",captures," failures=",failures)
	quit(1 if failures else 0)
