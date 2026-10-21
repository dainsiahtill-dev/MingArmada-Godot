extends SceneTree
## Real menu -> existing laboratory host -> registered paired production demo.
## Captures and state contracts; visual review and whole-game FPS remain separate.
const Main = preload("res://game/scenes/main/main_scene.tscn")
const TOPIC := "architecture-convergence-2026-10-21"
const STEP := 1.0 / 60.0
const TICKS := 120
const KINDS := ["fuchuan","fisherman","patrol","merchant","voc","heavy"]
const SOURCES := ["game/research/demos/architecture_convergence_experiment.gd","game/research/laboratory.gd","game/research/catalog.gd","assets/research/catalog.json","modules/physics_engine/ships/ship_dynamics.gd","modules/physics_engine/ocean/ocean_adapter.gd","modules/physics_engine/ocean/coastal_wave_field.gd","modules/physics_engine/ocean/wave_field.gd","modules/naval_simulation/ocean_adapter.gd","modules/naval_simulation/encounter.gd","game/runtime/sailing_simulation.gd","game/presentation/ships/ship_view.gd","modules/scene_engine/ocean/projected_ocean.gd","modules/scene_engine/ocean/reference_game_water.gdshader","tools/verify-architecture-lab-gpu.gd"]
const PERSISTED := ["user://saves/mingqi-v2.json","user://saves/legacy-v1.json","user://settings.json"]
var output := ""
var assertions := 0
var failures: Array[String] = []
var captures: Array = []
var comparisons: Array = []
var source_hashes: Dictionary = {}
var persisted_before: Dictionary = {}
var _main: Node
var _lab: Control
var _created_output := false
var _started_utc := ""

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok: failures.append(message); printerr("FAIL: ",message)

func _frames(count: int) -> void:
	for _frame in count: await process_frame

func _hashes() -> Dictionary:
	var result: Dictionary = {}
	for path: String in SOURCES: result[path] = FileAccess.get_sha256("res://" + path)
	return result

func _persisted() -> Dictionary:
	var result: Dictionary = {}
	for path: String in PERSISTED: result[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
	return result

func _physical(state: Dictionary) -> PackedByteArray:
	return var_to_bytes([state.tick,state.time,state.seed,state.baseline,state.candidate,state.counts])

func _capture(label: String) -> void:
	if is_instance_valid(_lab): _lab._update_telemetry()
	await _frames(2); await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	check(image != null and not image.is_empty(),"actual framebuffer " + label)
	if image == null or image.is_empty(): return
	var path := output + "/" + label + ".png"
	check(image.save_png(path) == OK,"PNG saved " + label)
	captures.append({"image":label + ".png","sha256":FileAccess.get_sha256(path),"size":[image.get_width(),image.get_height()],"laboratory":_lab.inspection_snapshot() if is_instance_valid(_lab) else {}})

func _run() -> void:
	_started_utc = Time.get_datetime_string_from_system(true)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	check(DisplayServer.get_name() != "headless","real graphics backend required")
	check(not output.is_empty() and output.begins_with("res://") and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output)),"fresh res:// output directory required")
	if not failures.is_empty(): _finish(); return
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output)) == OK,"output directory created")
	if not failures.is_empty(): _finish(); return
	_created_output = true; source_hashes = _hashes(); persisted_before = _persisted()
	root.size = Vector2i(1600,1000); root.content_scale_size = root.size; root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.unresizable = true; root.unfocusable = true; root.gui_disable_input = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_main = Main.instantiate(); root.add_child(_main); await _frames(4)
	var button: Button = _main.menu.find_child("laboratory",true,false)
	check(button != null and button.is_visible_in_tree() and not button.disabled,"ordinary homepage laboratory route enabled")
	await _capture("00-home")
	if button == null: _finish(); return
	button.pressed.emit()
	for _frame in 120:
		await process_frame
		if is_instance_valid(_main.current_scene): break
	_lab = _main.current_scene
	check(is_instance_valid(_lab) and _lab.startup_receipt.get("ok",false),"actual homepage activates existing laboratory host")
	if not is_instance_valid(_lab): _finish(); return
	_lab.set_process(false)
	check(_lab.select_topic(TOPIC),"registered architecture paper selected")
	await _capture("01-architecture-paper")
	for kind: String in KINDS:
		for depth: float in [4.0,24.0]:
			var options := {"kind":kind,"depth":depth,"paused":false,"variant":"scalar","interpolation":true,"camera_mode":"side"}
			check(_lab.start_demo(options).get("ok",false),"host constructs declared paired demo " + kind + " depth " + str(depth))
			if not is_instance_valid(_lab._demo): continue
			var demo: Node3D = _lab._demo
			var initial: Dictionary = demo.inspection_snapshot()
			check(initial.ready and initial.seed == 1661 and initial.tick == 0,"declared seed and initial state " + kind)
			var timeline: Array = []
			for tick in TICKS:
				demo.advance(STEP)
				var state: Dictionary = demo.inspection_snapshot()
				check(state.tick == tick + 1 and state.baseline == state.candidate and state.telemetry.exact,"paired numerical state " + kind + " tick " + str(tick + 1))
				timeline.append({"tick":state.tick,"time":state.time,"exact":state.telemetry.exact,"counts":state.counts})
			demo.advance(STEP * 0.5)
			var partial: Dictionary = demo.inspection_snapshot()
			check(partial.tick == TICKS and absf(partial.render_time - (TICKS - 0.5) * STEP) < 1.0e-10,"production fractional-frame interpolation " + kind)
			var full_expected := TICKS * (25 if depth == 4.0 else 5)
			check(partial.counts.full_terrain == full_expected and partial.counts.scalar_terrain == TICKS * 5 and partial.counts.candidate_full_samples == 0,"real full/scalar sampler workload " + kind)
			var accepted := _physical(partial)
			for view: String in ["side","high"]:
				_lab._change_parameter("camera_mode",view)
				var observer: Array = demo.inspection_snapshot().camera_transform
				for variant: String in ["full","scalar"]:
					_lab._change_parameter("variant",variant)
					var state: Dictionary = demo.inspection_snapshot()
					check(_physical(state) == accepted and state.camera_transform == observer and state.render_time == partial.render_time,"same-time same-camera path switch " + kind + " " + view + " " + variant)
					check(absf(float(state.surface.simulation_time) - state.render_time) < 1.0e-5 and absf(float(state.surface.u_time) - state.render_time) < 1.0e-5,"water display uniforms follow selected render time")
					await _capture("%s-depth%02d-%s-%s" % [kind,int(depth),view,variant])
			_lab._change_parameter("interpolation",false)
			check(demo.inspection_snapshot().render_time == partial.time and _physical(demo.inspection_snapshot()) == accepted,"fixed-pose toggle changes display only " + kind)
			_lab._change_parameter("interpolation",true)
			_lab._pause_demo()
			var paused: Dictionary = demo.inspection_snapshot(); var paused_state := _physical(paused)
			demo.advance(1.0); demo.orbit_camera(0.1,0.02); demo.zoom_camera(-0.1); await _frames(2)
			check(_physical(demo.inspection_snapshot()) == paused_state,"paused GPU observation spends no authority time or sampling calls " + kind)
			var observer_before: Dictionary = demo.inspection_snapshot().camera_controls
			_lab._reset_demo()
			var reset: Dictionary = demo.inspection_snapshot()
			check(reset.tick == 0 and reset.seed == initial.seed and reset.counts.full_terrain == 0 and reset.counts.scalar_terrain == 0 and reset.camera_controls == observer_before,"same-condition reset restores origin and retains observer " + kind)
			_lab._pause_demo()
			for tick in TICKS: demo.advance(STEP)
			demo.advance(STEP * 0.5)
			check(_physical(demo.inspection_snapshot()) == accepted,"same-condition deterministic replay " + kind)
			_lab._pause_demo()
			comparisons.append({"kind":kind,"depth_m":depth,"initial":initial,"fractional_frame":partial,"timeline":timeline,"reset":reset,"replay":demo.inspection_snapshot()})
			var demo_id := demo.get_instance_id()
			_lab._show_paper()
			check(_lab.inspection_snapshot().demo.is_empty() and _lab.find_child("ExperimentViewport",true,false).get_child_count() == 0 and not is_instance_id_valid(demo_id),"host releases isolated demo resources " + kind)
			await process_frame
	check(comparisons.size() == 12 and captures.size() == 50,"six hulls by two depths by two views and two paths captured")
	_lab.main_menu_requested.emit(); await _frames(6)
	check(_main.current_scene == null and _main.menu.is_visible_in_tree(),"laboratory returns through existing homepage lifecycle")
	_lab = null
	check(_persisted() == persisted_before,"lab leaves save and settings bytes untouched")
	check(_hashes() == source_hashes,"capture sources remained frozen")
	_finish()

func _finish() -> void:
	if _created_output:
		var evidence := {"schemaVersion":1,"recordType":"gpu-capture","valid":failures.is_empty(),"assertions":assertions,"failures":failures,"startedAtUtc":_started_utc,"finishedAtUtc":Time.get_datetime_string_from_system(true),"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"displayServer":DisplayServer.get_name(),"sources":source_hashes,"persistedBefore":persisted_before,"persistedAfter":_persisted(),"controls":{"seed":1661,"step_seconds":STEP,"ticks":TICKS,"fractional_frame_seconds":STEP * 0.5,"root_viewport":[1600,1000],"quality":"independent demo balanced","hulls":KINDS,"depths_m":[4,24],"views":["side","high"],"variants":["full","scalar"]},"captures":captures,"comparisons":comparisons,"scope":"Actual ordinary homepage -> existing laboratory host -> registered architecture demo. Six selectable real hulls, shallow/deep Coastal profiles, paired production Encounter/Simulation, same-time full/scalar snapshots, fixed/interpolated display, pause/reset/replay/resource contracts. PNGs are raw frames at controlled times; artistic acceptance requires visual review. No continuous full-game scene, FPS result, crew/Jolt budget measurement or original-engine pixel equivalence."}
		var file := FileAccess.open(output + "/GPU_VERIFY.json",FileAccess.WRITE)
		if file == null: check(false,"GPU manifest writable")
		else: file.store_string(JSON.stringify(evidence,"\t") + "\n"); file.close()
	print("ARCHITECTURE_LAB_GPU assertions=",assertions," captures=",captures.size()," failures=",failures.size())
	quit(1 if not failures.is_empty() else 0)
