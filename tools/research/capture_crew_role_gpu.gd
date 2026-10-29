extends SceneTree
## Actual menu -> laboratory -> registered crew experiment, with a fixed host clock.
## Never a claim of formal campaign play, manual input, frame rate or player enjoyment.
const Main = preload("res://game/scenes/main/main_scene.tscn")
const TOPIC := "crew-role-effects"
const STEP := 1.0 / 32.0
const LAST_TICK := 384
var failures: Array = []
var captures: Array = []
var sequence: Array = []
var checks: Array = []
var actions: Array = []
var output := ""
var own_output := false
var main: Node
var lab: Control
var candidate_eight: Dictionary = {}

func _initialize() -> void: run.call_deferred()

func check(value: bool, message: String) -> bool:
	if not value:
		failures.append(message)
		printerr("FAIL CREW GPU: ",message)
	return value

func frames(count: int) -> void:
	for _index in count: await process_frame

func normal(path: String) -> String:
	return path.replace("\\","/").simplify_path().trim_suffix("/").to_lower()

func inside(path: String, parent: String) -> bool:
	return not parent.is_empty() and normal(path).begins_with(normal(parent)+"/")

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output=") and output.is_empty(): output = arg.trim_prefix("--output=")
		else: check(false,"unknown or duplicate argument")
	var expected := OS.get_environment("CREW_CAPTURE_OUTPUT")
	var profile := OS.get_environment("CREW_PROFILE_ROOT")
	var original := OS.get_environment("CREW_ORIGINAL_APPDATA")
	var app := OS.get_environment("APPDATA")
	var local := OS.get_environment("LOCALAPPDATA")
	check(not expected.is_empty() and output.begins_with("res://docs/research/evidence/crew-role-effects/") and output.ends_with("/frames") and not output.contains("..") and not output.contains("\\") and normal(ProjectSettings.globalize_path(output)) == normal(expected) and not DirAccess.dir_exists_absolute(expected) and not FileAccess.file_exists(expected),"fresh confined output")
	check(not original.is_empty() and inside(app,profile) and inside(local,profile) and normal(app) != normal(local) and inside(ProjectSettings.globalize_path("user://"),app) and not inside(profile,original) and not inside(original,profile) and normal(profile) != normal(original),"isolated actual userdata")
	check(DisplayServer.get_name() != "headless","non-headless graphics required")
	if DisplayServer.get_name() != "headless":
		var adapter := RenderingServer.get_video_adapter_name().to_lower()
		check(not adapter.is_empty() and not "llvmpipe" in adapter and not "swiftshader" in adapter,"hardware graphics required")
	if not failures.is_empty():
		print("CREW_ROLE_GPU_GUARD_REJECTED failures=",failures.size())
		quit(2)
		return
	if not check(DirAccess.make_dir_recursive_absolute(expected) == OK,"create output"): quit(2); return
	own_output = true
	seed(0)
	AudioServer.set_bus_mute(0,true)
	await resize(Vector2i(1280,720))
	main = Main.instantiate()
	root.add_child(main)
	await frames(4)
	var button: Button = main.menu.find_child("laboratory",true,false)
	if not check(is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled,"real main menu laboratory button"): await finish(); return
	button.pressed.emit()
	for _index in 80:
		await process_frame
		if is_instance_valid(main.current_scene): break
	lab = main.current_scene
	if not check(is_instance_valid(lab) and lab.startup_receipt.get("ok",false),"laboratory opened by menu"): await finish(); return
	lab.set_process(false) # Only explicit host steps own this capture's timeline.
	if not check(lab.select_topic(TOPIC),"registered topic selectable"): await finish(); return
	if not start({"preset":"balanced","specialists":true}): await finish(); return
	await frames(5)
	if not await whole_page("wide-start"): await finish(); return
	if not await series("candidate",LAST_TICK,true,true): await finish(); return
	if not await whole_page("wide-detached"): await finish(); return
	var stopped: Dictionary = lab._demo.inspection_snapshot()
	await frames(8)
	check(lab._demo.inspection_snapshot() == stopped,"paused frames leave entire state unchanged")
	checks.append({"name":"pause","frames":8,"tick":stopped.tick,"unchanged":lab._demo.inspection_snapshot() == stopped})
	lab._reset_demo({"preset":"balanced","specialists":true,"repair_detachment":false})
	check(lab._demo.inspection_snapshot().tick == 0 and lab._demo.inspection_snapshot().state.hull == 54.0,"host reset restores initial resources and clock")
	if not start({"preset":"balanced","specialists":false}): await finish(); return
	if not await series("baseline",256,false,false): await finish(); return
	var baseline: Dictionary = lab._demo.inspection_snapshot().state
	check(candidate_eight.hull > baseline.hull and candidate_eight.ledger.meals_cooked > baseline.ledger.meals_cooked and baseline.hull > 54.0,"specialists outperform working ordinary crew at eight seconds")
	checks.append({"name":"specialist_comparison","candidate":candidate_eight,"baseline":baseline})
	if not start({"preset":"scarce","specialists":true}): await finish(); return
	if not await series("scarce",96,false,false): await finish(); return
	var scarce: Dictionary = lab._demo.inspection_snapshot().state
	check(is_zero_approx(scarce.grain) and is_zero_approx(scarce.wood) and is_equal_approx(scarce.hull,56.0) and scarce.ledger.meals_eaten == 0,"scarce materials stop work without free food")
	checks.append({"name":"scarce","state":scarce})
	if not start({"preset":"balanced","specialists":true}): await finish(); return
	await resize(Vector2i(960,640))
	await frames(5)
	if not await whole_page("narrow-top"): await finish(); return
	var roster: Button = lab._demo.find_child("CrewRosterButton",true,false)
	var scroll: ScrollContainer = lab._demo.find_child("CrewRoleScroll",true,false)
	var outer: ScrollContainer = lab.find_child("ExperimentScroll",true,false)
	if check(is_instance_valid(roster) and is_instance_valid(scroll) and is_instance_valid(outer),"nested experiment controls exist"):
		roster.pressed.emit()
		await frames(3)
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
		outer.scroll_vertical = int(outer.get_v_scroll_bar().max_value)
		await frames(3)
		check(scroll.scroll_vertical > 0 and lab._demo.inspection_snapshot().roster_open,"narrow crew roster scrolls to remaining workers")
		check(lab._demo.inspection_snapshot().tick == 0,"layout and roster do not advance time")
		if not await whole_page("narrow-roster-bottom"): await finish(); return
	check(captures.size() == 395,"385 consecutive candidate frames, six comparison frames and four pages")
	check(sequence.size() == 739,"all candidate baseline scarce ticks observed")
	await finish()

func start(options: Dictionary) -> bool:
	options = options.duplicate(true)
	options.merge({"paused":true,"repair_detachment":false,"camera_mode":"fixed"},true)
	return check(lab.start_demo(options).get("ok",false),"start isolated fixture")

func resize(size: Vector2i) -> void:
	DisplayServer.window_set_size(size)
	root.content_scale_size = size
	root.size = size
	await frames(4)

func series(variant: String, last_tick: int, detach: bool, every_image: bool) -> bool:
	for tick in last_tick+1:
		if tick > 0 and not check(lab.step_demo().get("ok",false),"host single step"): return false
		if detach and tick == 256:
			candidate_eight = lab._demo.inspection_snapshot().state.duplicate(true)
			lab._change_parameter("repair_detachment",true)
			var after: Dictionary = lab._demo.inspection_snapshot()
			if not check(after.parameters.repair_detachment and after.state.gun_efficiency < candidate_eight.gun_efficiency and after.state.rates.repair > candidate_eight.rates.repair and after.state.ledger == candidate_eight.ledger,"host detachment changes capacity without awarding work"): return false
			actions.append({"variant":variant,"tick":tick,"action":"repair_detachment","value":true,"before":candidate_eight,"after":after.state})
		await process_frame
		await RenderingServer.frame_post_draw
		var snap: Dictionary = lab._demo.inspection_snapshot()
		if not check(snap.tick == tick and snap.time == tick*STEP and snap.fixed_step == STEP and snap.paused and snap.ready,"same-frame fixed host clock"): return false
		var state: Dictionary = snap.state
		if not conserved(state,0.5 if variant == "scarce" else 24.0,1.0 if variant == "scarce" else 16.0): return false
		sequence.append({"variant":variant,"tick":tick,"time":snap.time,"hull":state.hull,"wood":state.wood,"grain":state.grain,"cooked":state.cooked_rations,"morale":state.morale,"gun_efficiency":state.gun_efficiency,"ledger":state.ledger.duplicate(true)})
		if every_image or tick in [0,last_tick/2,last_tick]:
			var viewport: SubViewport = lab.find_child("ExperimentViewport",true,false)
			if not check(is_instance_valid(viewport),"experiment viewport exists"): return false
			if not save_image(viewport.get_texture().get_image(),"%s-%03d.png" % [variant,tick],"experiment",snap): return false
	return true

func conserved(state: Dictionary, grain: float, wood: float) -> bool:
	var ledger: Dictionary = state.ledger
	return check(absf(grain-state.grain-ledger.grain_used)<0.000001 and absf(ledger.grain_used-ledger.meals_cooked)<0.000001 and absf(ledger.meals_cooked-ledger.meals_eaten-state.cooked_rations)<0.000001 and absf(wood-state.wood-ledger.wood_used)<0.000001 and absf(ledger.wood_used-ledger.hull_repaired*0.5)<0.000001 and absf(state.hull-54.0-ledger.hull_repaired)<0.000001 and state.hull<=80.0 and state.grain>=0.0 and state.wood>=0.0 and state.cooked_rations>=0.0,"frame resource conservation and caps")

func whole_page(name: String) -> bool:
	await process_frame
	await RenderingServer.frame_post_draw
	var snap: Dictionary = lab._demo.inspection_snapshot()
	var viewport: SubViewport = lab.find_child("ExperimentViewport",true,false)
	var panel: PanelContainer = lab._demo.find_child("CrewRolePanel",true,false)
	if not check(is_instance_valid(viewport) and is_instance_valid(panel),"painted panel exists"): return false
	var bounds := Rect2(Vector2.ZERO,Vector2(viewport.size))
	if not check(bounds.encloses(panel.get_rect()),"panel fits experiment viewport"): return false
	var style: StyleBox = panel.get_theme_stylebox("panel")
	if style.has_method("_get_draw_rect"):
		var painted: Rect2 = style.call("_get_draw_rect",Rect2(Vector2.ZERO,panel.size))
		painted.position += panel.position
		if not check(bounds.encloses(painted),"painted frame shadow fits viewport: bounds=%s panel=%s painted=%s" % [bounds,panel.get_rect(),painted]): return false
	return save_image(root.get_texture().get_image(),name+".png","page",snap)

func save_image(im: Image, name: String, kind: String, snap: Dictionary) -> bool:
	if not check(im != null and not im.is_empty(),"GPU image exists"): return false
	var path := output+"/"+name
	if not check(not FileAccess.file_exists(path),"never overwrite capture"): return false
	if not check(im.save_png(path) == OK,"PNG write"): return false
	captures.append({"file":name,"kind":kind,"viewport":[im.get_width(),im.get_height()],"sha256":FileAccess.get_sha256(path),"snapshot":snap.duplicate(true)})
	return true

func finish() -> void:
	var report := {"valid":failures.is_empty(),"failures":failures,"scope":"Actual main menu and registered laboratory, scripted fixed-step GPU sequence. Not formal campaign, manual interaction, full-game FPS or player experience.","engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"displayServer":DisplayServer.get_name(),"fixedStep":STEP,"seed":0,"lastTick":LAST_TICK,"captures":captures,"sequence":sequence,"checks":checks,"actions":actions,"audioMuted":AudioServer.is_bus_mute(0)}
	if own_output:
		var path := output+"/capture-result.json"
		if check(not FileAccess.file_exists(path),"fresh report path"):
			var file := FileAccess.open(path,FileAccess.WRITE)
			if file: file.store_string(JSON.stringify(report)); file.close()
			else: check(false,"report write")
	if is_instance_valid(main): main.free()
	await frames(2)
	print("CREW_ROLE_GPU captures=",captures.size()," ticks=",sequence.size()," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
