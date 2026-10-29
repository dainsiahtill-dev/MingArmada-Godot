extends SceneTree
## Real menu/laboratory, scripted 60 Hz steps, GPU image every four accepted ticks.
## Fifteen samples per accepted second; rendering/export wall time is not game FPS.
const Main = preload("res://game/scenes/main/main_scene.tscn")
const STEP := 1.0 / 60.0
const TICKS_PER_FRAME := 4
const MAX_FRAMES := 600
const SEED := 1661
const CASES := [
	{"id":"showcase-all", "stage":"showcase", "good":"all", "camera_mode":"deck"},
	{"id":"wood-combat", "stage":"combat", "good":"wood", "camera_mode":"water"},
	{"id":"porcelain-combat", "stage":"combat", "good":"porcelain", "camera_mode":"water"}
]

var failures: Array = []
var captures: Array = []
var sequences: Array = []
var checks: Array = []
var cases: Array = []
var output := ""
var own_output := false
var main: Node
var lab: Control
var baseline: Dictionary = {}
var accepted_steps := 0

func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> bool:
	if not value:
		failures.append(message)
		printerr("FAIL CARGO DECK GPU: ", message)
	return value
func frames(count: int) -> void:
	for _index in count: await process_frame
func normal(path: String) -> String: return path.replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
func inside(path: String, parent: String) -> bool: return not parent.is_empty() and normal(path).begins_with(normal(parent) + "/")
func near(a: float, b: float) -> bool: return absf(a - b) <= 0.000001
func digest(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
func state_digest(value: Dictionary) -> String: return digest(JSON.stringify(value,"",false,true).to_utf8_buffer())

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output=") and output.is_empty(): output = arg.trim_prefix("--output=")
		else: check(false, "unknown or duplicate argument")
	var expected := OS.get_environment("CARGO_DECK_CAPTURE_OUTPUT")
	var profile := OS.get_environment("CARGO_DECK_PROFILE_ROOT")
	var original := OS.get_environment("CARGO_DECK_ORIGINAL_APPDATA")
	var app := OS.get_environment("APPDATA")
	var local := OS.get_environment("LOCALAPPDATA")
	check(not expected.is_empty() and output.begins_with("res://docs/research/evidence/cargo-deck-drift/") and output.ends_with("/frames") and not output.contains("..") and not output.contains("\\") and normal(ProjectSettings.globalize_path(output)) == normal(expected) and not DirAccess.dir_exists_absolute(expected) and not FileAccess.file_exists(expected), "fresh confined output")
	check(not original.is_empty() and inside(app, profile) and inside(local, profile) and normal(app) != normal(local) and inside(ProjectSettings.globalize_path("user://"), app) and not inside(profile, original) and not inside(original, profile) and normal(profile) != normal(original), "isolated actual userdata")
	check(DisplayServer.get_name() != "headless", "non-headless graphics required")
	if DisplayServer.get_name() != "headless":
		var gpu := RenderingServer.get_video_adapter_name().to_lower()
		check(not gpu.is_empty() and not "llvmpipe" in gpu and not "swiftshader" in gpu and not "software" in gpu, "hardware graphics required")
	if not failures.is_empty():
		print("CARGO_DECK_GPU_GUARD_REJECTED failures=", failures.size())
		quit(2)
		return
	if not check(DirAccess.make_dir_recursive_absolute(expected) == OK, "create fresh output"): quit(2); return
	own_output = true
	seed(SEED)
	AudioServer.set_bus_mute(0, true)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	root.content_scale_size = Vector2i(1600, 900)
	root.size = Vector2i(1600, 900)
	await frames(4)
	main = Main.instantiate()
	root.add_child(main)
	await frames(4)
	await RenderingServer.frame_post_draw
	if not save_image(root.get_texture().get_image(), "menu-before.png", "menu", "", {}): await finish(); return
	var button: Button = main.menu.find_child("laboratory", true, false)
	if not check(is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled, "actual main menu laboratory button"): await finish(); return
	button.pressed.emit()
	for _index in 120:
		await process_frame
		if is_instance_valid(main.current_scene): break
	lab = main.current_scene
	if not check(is_instance_valid(lab) and lab.startup_receipt.get("ok", false), "laboratory opened from actual menu"): await finish(); return
	lab.set_process(false)
	if not check(lab.select_topic("cargo-deck-drift"), "registered cargo topic selectable"): await finish(); return
	checks.append({"name": "real_entry", "input": "ordinary menu button signal followed by registered topic selection", "ok": true})
	for fixture: Dictionary in CASES:
		if not await run_case(fixture): await finish(); return
	var owned_demo: WeakRef = weakref(lab._demo)
	main._return_from_scene(lab)
	lab = null
	await frames(4)
	check(owned_demo.get_ref() == null, "leaving actual laboratory releases the demo and owned world")
	checks.append({"name": "dispose", "released": owned_demo.get_ref() == null})
	await RenderingServer.frame_post_draw
	save_image(root.get_texture().get_image(), "menu-returned.png", "menu", "", {})
	await finish()

func run_case(fixture: Dictionary) -> bool:
	var id: String=fixture.id
	var options: Dictionary=fixture.duplicate(true); options.erase("id"); options.paused=true; options.seed=SEED
	if not check(lab.start_demo(options).get("ok",false),id+" registered demo starts"):return false
	await frames(3)
	if not await sample_frame(fixture,0,0): return false
	var state: Dictionary=lab._demo.inspection_snapshot()
	if fixture.stage=="showcase":
		check(state.cargo.decks.player.goods.size()==12,"all twelve actual cargo models visible")
		check(state.cargo.decks.player.overflow_goods.is_empty(),"all twelve fit without blocked deck")
		save_image(root.get_texture().get_image(),id+"-page.png","page",id,state)
		lab._demo.set_camera_mode("battle");await frames(2);await RenderingServer.frame_post_draw
		save_image(lab._viewport.get_texture().get_image(),id+"-wide.png","detail",id,lab._demo.inspection_snapshot())
		cases.append({"id":id,"frames":1,"models":12});return failures.is_empty()
	var airborne:=false;var floating:=false;var sinking:=false;var pause_checked:=false
	for sample in range(1,271):
		for _i in TICKS_PER_FRAME:
			if not check(lab.step_demo().get("ok",false),id+" actual host step"):return false
			accepted_steps+=1
		if not await sample_frame(fixture,sample,TICKS_PER_FRAME):return false
		state=lab._demo.inspection_snapshot()
		for lot: Dictionary in state.cargo.floating:
			airborne=airborne or lot.phase=="airborne"
			floating=floating or lot.phase=="floating"
			sinking=sinking or lot.phase=="sinking"
		if floating and not pause_checked:
			var before: Dictionary=state.duplicate(true);await frames(8);await RenderingServer.frame_post_draw
			check(lab._demo.inspection_snapshot()==before,id+" pause freezes all accepted state across rendered frames")
			save_image(lab._viewport.get_texture().get_image(),id+"-pause.png","pause",id,before)
			checks.append({"name":"pause","case":id,"unchanged":lab._demo.inspection_snapshot()==before});pause_checked=true
		if sample%60==0:print("CARGO_DECK_GPU_PROGRESS case=",id," sample=",sample," time=",state.time)
	check(airborne and floating and state.splash_count>0,id+" actual hit cargo completes flight splash and float")
	check(fixture.good!="porcelain" or sinking,id+" dense porcelain packaging eventually sinks")
	var lost:=0
	for drop: Dictionary in state.drops: lost+=int(drop.quantity)
	check(lost>0 and int(state.inventory.player.get(fixture.good,0))+lost==10,id+" actual cargo and losses conserve")
	cases.append({"id":id,"frames":271,"airborne":airborne,"floating":floating,"sinking":sinking,"pause":pause_checked,"lost":lost,"splash_count":state.splash_count})
	return failures.is_empty()

func sample_frame(fixture:Dictionary,index:int,steps:int)->bool:
	await frames(1);await RenderingServer.frame_post_draw
	var state: Dictionary=lab._demo.inspection_snapshot()
	if not check(state.ready and state.paused and state.cargo.errors.is_empty(),fixture.id+" ready cargo renderer"):return false
	var strip: Control=lab._demo.get("_strip")
	if not check(is_instance_valid(strip) and strip.size.y<=180.0 and strip.size.y<lab._viewport.size.y*.35,"cargo HUD leaves the sea and props visible"):return false
	var known: Dictionary={}
	for drop: Dictionary in state.drops: known[drop.dropId]=drop
	for lot: Dictionary in state.cargo.floating:
		if not check(known.has(lot.dropId) and known[lot.dropId].goodId==lot.goodId and known[lot.dropId].quantity==lot.quantity,"every prop is backed by real committed loss"):return false
	var file: String=fixture.id+"-%03d.png"%index
	sequences.append({"case":fixture.id,"sample":index,"file":file,"steps":steps,"tick":state.tick,"time":state.time})
	return save_image(lab._viewport.get_texture().get_image(),file,"experiment",fixture.id,state)

func save_image(image: Image, file: String, kind: String, case_id: String, state: Dictionary) -> bool:
	if not check(image != null and not image.is_empty(), "hardware framebuffer exists: " + file): return false
	image.convert(Image.FORMAT_RGBA8)
	var path := output + "/" + file
	if not check(not FileAccess.file_exists(path) and image.save_png(path) == OK, "fresh PNG write: " + file): return false
	captures.append({"file": file, "kind": kind, "case": case_id, "viewport": [image.get_width(), image.get_height()], "sha256": FileAccess.get_sha256(path), "framebuffer_sha256": digest(image.get_data()), "framebuffer_format": "RGBA8", "snapshot": state.duplicate(true)})
	return true

func finish() -> void:
	var report := {"valid": failures.is_empty(), "failures": failures, "engine": Engine.get_version_info(), "gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "displayServer": DisplayServer.get_name(), "fixedStep": STEP, "ticksPerFrame": TICKS_PER_FRAME, "nominalSamplesPerAcceptedSecond": 15, "maximumSamplesPerCase": MAX_FRAMES + 1, "seed": SEED, "audioMuted": AudioServer.is_bus_mute(0), "acceptedSteps": accepted_steps, "cases": cases, "sequences": sequences, "captures": captures, "checks": checks, "scope": "Scripted ordinary menu to registered isolated laboratory. Four accepted 60 Hz steps per GPU sample (15 samples per accepted second), with cargo quantity conservation and actual water-entry events. PNG and state proof require art review. No manual play, real-time FPS, per-physics-step imagery, volumetric renderer or production integration claim."}
	if own_output:
		var path := output + "/capture-result.json"
		if check(not FileAccess.file_exists(path), "fresh report"):
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file: file.store_string(JSON.stringify(report,"",false,true)); file.close()
			else: check(false, "report write")
	if is_instance_valid(main): main.free()
	await frames(2)
	print("CARGO_DECK_GPU captures=", captures.size(), " samples=", sequences.size(), " accepted_steps=", accepted_steps, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
