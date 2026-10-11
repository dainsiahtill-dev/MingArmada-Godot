extends SceneTree
## Actual main-menu QA route, original scenarios, canonical fire and live Jolt bodies.
const Router = preload("res://game/runtime/game_router.gd")
const Storage = preload("res://game/persistence/save_coordinator.gd")
const Settings = preload("res://game/persistence/user_settings.gd")
const Runtime = preload("res://game/runtime/visual_qa_runtime.gd")
var main: Node
var scene: Node
var failures := 0
var captures := 0
var directory := "res://docs/migration/evidence/visual-qa"
func _initialize() -> void: run.call_deferred()
func check(value: bool, detail: String) -> void:
	if not value: failures += 1; printerr("FAIL: ",detail)
func frames(count: int = 4) -> void:
	for frame in count: await process_frame
func tick() -> void:
	# Other desktop windows may steal focus during unattended capture. Use the
	# same visible Continue control as the player; never erase pause authority.
	var reasons: Array=scene.runtime.snapshot().runtime.pauseReasons
	if reasons == ["blur"]: await click(scene.interface.find_child("resume",true,false))
	scene._physics_process(1.0/60.0)
	await physics_frame; await process_frame
func click(control: Control) -> void:
	var event := InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=true; event.position=control.get_global_rect().get_center()
	Input.parse_input_event(event); await process_frame
	event=event.duplicate(); event.pressed=false; Input.parse_input_event(event); await process_frame
func capture(label: String) -> void:
	for frame in 4: await tick()
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image.save_png(directory+"/"+label+".png") == OK,"native PNG writes "+label)
	var metadata := {"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"viewport":[image.get_width(),image.get_height()],"route":"actual project MainScene menu QA button","runtime":scene.runtime.snapshot(),"inspection":scene.inspection_snapshot(),"quality":scene.services.settings_storage.snapshot().quality,"camera":{"position":str(scene.sea.camera.position),"tactical":scene.sea.tactical},"scope":"Native visual and real cannon/Jolt input evidence. Fixed capture ticks are not a wall-time FPS benchmark."}
	var file := FileAccess.open(directory+"/"+label+".json",FileAccess.WRITE)
	check(file != null,"native metadata writes "+label)
	if file: file.store_string(JSON.stringify(metadata,"\t")); file.close()
	captures += 1
func choose(id: String) -> void:
	var option: OptionButton = scene.interface.find_child("scenario",true,false)
	var index := Runtime.SCENARIOS.find(id)
	option.select(index); option.item_selected.emit(index)
	await frames()
	check(scene.runtime.snapshot().runtime.scenario == id,"actual scenario selector "+id)
func run() -> void:
	root.size=Vector2i(1600,900); root.content_scale_size=root.size
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var prefix := "user://tests/native-qa-capture-%d" % OS.get_process_id()
	var packed: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	main=packed.instantiate(); main.router=Router.new({"dev":true,"mingqi_storage":Storage.new(prefix+"-v2.json"),"legacy_storage":Storage.new(prefix+"-v1.json"),"settings_storage":Settings.new(prefix+"-settings.json")}); root.add_child(main)
	await frames()
	var qa: Button=main.menu._buttons.qa
	main.menu._scroll.ensure_control_visible(qa); await frames(); await click(qa)
	for frame in 180:
		if main.current_scene: break
		await process_frame
	check(main.current_scene != null,"actual native menu routes QA scene")
	if not main.current_scene: quit(1); return
	scene=main.current_scene; scene.set_process(false); scene.set_physics_process(false)
	for id: String in Runtime.SCENARIOS:
		await choose(id)
		if id.begins_with("wave-"):
			for frame in 278: await tick()
			check(scene.runtime.snapshot().runtime.pauseReasons.has("wave"),"real source 4.6s hold "+id)
		await capture(id)
		if id in ["impact","impact-weak","sink"]:
			await click(scene.interface.find_child("fire_starboard",true,false))
			var actual_hit := false
			for frame in 150:
				await tick()
				var detail: Dictionary=scene.inspection_snapshot()
				if detail.sailors.impacts.active > 0:
					actual_hit=true; await capture(id+"-real-hit"); break
			check(actual_hit,"actual player cannon produces real Jolt bodies "+id)
			if actual_hit and id == "impact-weak":
				for frame in 130: await tick()
				await capture("impact-weak-recovered")
	await choose("fleet")
	root.size=Vector2i(320,480); root.content_scale_size=root.size; await frames(); await capture("fleet-narrow")
	root.size=Vector2i(1600,900); root.content_scale_size=root.size; await frames()
	await click(scene.interface.find_child("main_menu",true,false)); await frames()
	check(main.current_scene == null and main.menu.visible,"actual QA exit returns to owner menu")
	main.queue_free(); await frames()
	print("NATIVE_VISUAL_QA_CAPTURE_COMPLETE captures=",captures," failures=",failures)
	quit(1 if failures else 0)
