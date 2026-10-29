extends SceneTree
const Main = preload("res://game/scenes/main/main_scene.tscn")
const Maritime = preload("res://game/ui/shared/maritime_art_theme.gd")
var assertions := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL broadside layout: ",message)
func _initialize() -> void: run.call_deferred()
func settle() -> void:
	for i in 5: await process_frame
func run() -> void:
	var main = Main.instantiate(); root.add_child(main); await settle()
	var button: Button = main.menu.find_child("laboratory",true,false)
	check(is_instance_valid(button) and button.is_visible_in_tree(),"actual laboratory entry available")
	if failures: main.free(); finish(); return
	button.pressed.emit()
	for i in 80:
		await process_frame
		if is_instance_valid(main.current_scene): break
	var lab = main.current_scene
	check(is_instance_valid(lab) and lab.startup_receipt.get("ok",false),"main scene opens laboratory")
	if failures: main.free(); finish(); return
	lab.set_process(false)
	check(lab.select_topic("broadside-receipt-readability"),"correct research topic selected")
	for size: Vector2i in [Vector2i(1280,720),Vector2i(1600,900)]:
		root.content_scale_size = size; root.size = size; await settle()
		var initial_rect := Rect2()
		for enabled: bool in [false,true]:
			check(lab.start_demo({"paused":true,"candidate_enabled":enabled}).ok,"fixture starts")
			await settle()
			var viewport: SubViewport = lab.find_child("ExperimentViewport",true,false)
			var panel: PanelContainer = lab._demo.find_child("BroadsideReceiptPaper",true,false)
			var label: Label = lab._demo.find_child("BroadsideReceiptFixture",true,false)
			check(is_instance_valid(viewport) and is_instance_valid(panel) and is_instance_valid(label),"real experiment controls exist")
			if not is_instance_valid(viewport) or not is_instance_valid(panel) or not is_instance_valid(label): continue
			for tick: int in [0,16,20,112]:
				while lab._demo.inspection_snapshot().tick < tick: lab.step_demo()
				await settle()
				var style: StyleBox = panel.get_theme_stylebox("panel")
				var draw: Rect2 = style.call("_get_draw_rect",Rect2(Vector2.ZERO,panel.size)) if style.has_method("_get_draw_rect") else Rect2(Vector2.ZERO,panel.size)
				draw.position += panel.position
				var bounds := Rect2(Vector2.ZERO,Vector2(viewport.size))
				print("BROADSIDE_LAYOUT window=",size," enabled=",enabled," tick=",tick," viewport=",viewport.size," panel=",panel.get_rect()," draw=",draw," label=",label.get_global_rect())
				if not enabled and tick == 0: initial_rect = panel.get_rect()
				check(panel.get_rect() == initial_rect,"frame geometry remains fixed across time and A/B")
				check(bounds.encloses(draw),"entire panel and shadow fit viewport")
				check(bounds.encloses(label.get_global_rect()),"live receipt text fits viewport")
				check(label.size.x + 0.1 >= label.get_combined_minimum_size().x and label.size.y + 0.1 >= label.get_combined_minimum_size().y,"text is not clipped by its own control")
				for text: Label in panel.find_children("*","Label",true,false):
					check(bounds.encloses(text.get_global_rect()),"each caption fits the viewport")
					check(text.size.x + 0.1 >= text.get_combined_minimum_size().x and text.size.y + 0.1 >= text.get_combined_minimum_size().y,"each caption fits its control")
				check(label.get_theme_color("font_color") == Maritime.INK,"text uses the current light maritime ink")
				check(style.has_method("get_body_style") and style.call("get_body_style").texture.resource_path.contains("/quiet/"),"panel uses existing quiet maritime painted material")
	main.free(); finish()
func finish() -> void:
	print("BROADSIDE_RECEIPT_LAYOUT assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
