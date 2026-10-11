extends "res://tools/capture-native-qa.gd"
## Real menu/scenario/fire controls; close cameras only change presentation.
const SeaView = preload("res://game/presentation/world/naval_world_view.gd")

func _initialize() -> void:
	directory = "res://docs/migration/evidence/reference-implementation-events"
	run.call_deferred()

func capture_close(label: String, target_id: String) -> void:
	var native: Dictionary = scene.runtime.snapshot().naval
	var ship: Dictionary = SeaView.find_ship(native,target_id)
	check(not ship.is_empty(),"canonical target retained for "+label)
	if ship.is_empty(): return
	var p: Dictionary = ship.visual.position
	var point := Vector3(p.x,p.y+3.0,p.z)
	scene.sea.camera.position = point + Vector3(-24,17,29)
	scene.sea.camera.look_at(point)
	scene.sea.world.get_ocean().update_projection()
	scene.interface.visible = false
	await frames(3); await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image.save_png(directory+"/"+label+".png") == OK,"native close PNG writes "+label)
	var damage: Dictionary = scene.sea.ships[target_id].damage_diagnostics() if scene.sea.ships.has(target_id) else {}
	var data := {"route":"actual MainScene QA menu, scenario selector and fire buttons","engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"viewport":[image.get_width(),image.get_height()],"runtime":scene.runtime.snapshot(),"inspection":scene.inspection_snapshot(),"damage":damage,"effects":scene.sea.effects.diagnostics(),"scope":"Fixed accepted ticks and close camera, no synthesized damage or FPS claim."}
	var file := FileAccess.open(directory+"/"+label+".json",FileAccess.WRITE)
	check(file != null,"native close metadata writes "+label)
	if file: file.store_string(JSON.stringify(data,"\t")); file.close()
	captures += 1
	scene.interface.visible = true

func advance_ticks(count: int) -> void:
	for frame in count: await tick()

func run() -> void:
	root.size=Vector2i(1600,900); root.content_scale_size=root.size
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var prefix := "user://tests/reference-events-%d" % OS.get_process_id()
	var packed: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	main=packed.instantiate(); main.router=Router.new({"dev":true,"mingqi_storage":Storage.new(prefix+"-v2.json"),"legacy_storage":Storage.new(prefix+"-v1.json"),"settings_storage":Settings.new(prefix+"-settings.json")}); root.add_child(main)
	await frames()
	var qa: Button=main.menu._buttons.qa
	main.menu._scroll.ensure_control_visible(qa); await frames(); await click(qa)
	for frame in 180:
		if main.current_scene: break
		await process_frame
	check(main.current_scene != null,"actual native menu routes close event acceptance")
	if not main.current_scene: quit(1); return
	scene=main.current_scene; scene.set_process(false); scene.set_physics_process(false)
	await choose("impact")
	await capture_close("crew-standing","inspection-voc")
	await click(scene.interface.find_child("fire_starboard",true,false))
	var hit := false
	for frame in 180:
		await tick()
		if scene.inspection_snapshot().sailors.impacts.active > 0:
			hit=true; await capture_close("crew-real-impact","inspection-voc"); break
	check(hit,"real cannon hit creates close Jolt evidence")
	await advance_ticks(18); await capture_close("crew-impact-0-3s","inspection-voc")
	await advance_ticks(72); await capture_close("crew-impact-1-5s","inspection-voc")
	await advance_ticks(420); await capture_close("crew-impact-recycled","inspection-voc")
	check(scene.inspection_snapshot().sailors.impacts.active == 0,"all impact bodies recycled after accepted lifetime")
	await choose("damage")
	await capture_close("damaged-fuchuan","player")
	await capture_close("damaged-voc","inspection-voc")
	await click(scene.interface.find_child("chain",true,false))
	var broken := false
	for salvo in 3:
		await click(scene.interface.find_child("fire_starboard",true,false))
		for frame in 480:
			await tick()
			if SeaView.find_ship(scene.runtime.snapshot().naval,"inspection-voc").sail <= 0:
				broken=true; break
		if broken: break
	check(broken,"real chain salvos reduce sail to zero")
	if broken:
		await capture_close("mast-break-start","inspection-voc")
		await advance_ticks(80); await capture_close("mast-break-mid","inspection-voc")
		await advance_ticks(95); await capture_close("mast-break-end","inspection-voc")
	await choose("sink")
	await capture_close("sink-before","inspection-voc")
	await click(scene.interface.find_child("fire_starboard",true,false))
	var sunk := false
	for frame in 180:
		await tick()
		if SeaView.find_ship(scene.runtime.snapshot().naval,"inspection-voc").hull <= 0:
			sunk=true; await capture_close("sink-start","inspection-voc"); break
	check(sunk,"real solid cannon reduces target hull to zero")
	if sunk:
		await advance_ticks(90); await capture_close("sink-froth-1-5s","inspection-voc")
		await advance_ticks(180); await capture_close("sink-ended","inspection-voc")
		check(scene.sea.ships["inspection-voc"].damage_diagnostics().ended,"accepted sinking timeline reaches finite end")
	await click(scene.interface.find_child("main_menu",true,false)); await frames()
	check(main.current_scene == null and main.menu.visible,"actual event QA exit returns to owner menu")
	main.queue_free(); await frames()
	print("REFERENCE_EVENT_CAPTURE_COMPLETE captures=",captures," failures=",failures)
	quit(1 if failures else 0)
