extends SceneTree
const Main = preload("res://game/scenes/main/main_scene.tscn")
const Contract = preload("res://tools/research/broadside_capture_contract.gd")
var assertions := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL broadside capture entry: ",message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var main = Main.instantiate(); root.add_child(main)
	for i in 4: await process_frame
	var button: Button = main.menu.find_child("laboratory",true,false)
	check(is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled,"actual main menu offers laboratory")
	if failures: main.free(); finish(); return
	button.pressed.emit()
	for i in 80:
		await process_frame
		if is_instance_valid(main.current_scene): break
	var lab = main.current_scene
	check(is_instance_valid(lab) and lab.startup_receipt.get("ok",false),"main menu opens actual laboratory")
	if failures: main.free(); finish(); return
	lab.set_process(false)
	check(lab.select_topic("broadside-receipt-readability"),"registered subject selectable")
	for size: Vector2i in [Vector2i(1600,900),Vector2i(1280,720)]:
		root.content_scale_size = size; root.size = size
		var baseline := []
		for enabled in [false,true]:
			var started: Dictionary = lab.start_demo({"paused":true,"candidate_enabled":enabled})
			check(started.ok,"registered demo starts at viewport size")
			if not started.ok: continue
			for tick in Contract.LAST_TICK+1:
				if tick: check(lab.step_demo().ok,"host single step accepted")
				var snap: Dictionary = lab._demo.inspection_snapshot()
				check(snap.tick == tick and absf(float(snap.time)-tick*Contract.STEP)<1.0e-12,"host clock matches fixed input")
				if enabled: check(Contract.pair_ok(baseline[tick],snap),"baseline candidate internal state matches")
				else: baseline.append(snap.duplicate(true))
	main.free(); finish()
func finish() -> void:
	print("BROADSIDE_CAPTURE_ENTRY assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
