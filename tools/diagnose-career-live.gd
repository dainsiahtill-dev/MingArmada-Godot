extends "res://tools/capture-fidelity-island.gd"
## Short real-frame observation, not manual physics calls or a long benchmark.
func _run() -> void:
	create_timer(35.0).timeout.connect(func(): check(false,"live diagnostic watchdog expired"); _finish())
	output="res://Temp/career-live-v1"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	if not check(DisplayServer.get_name()!="headless","live observation needs native GPU"): _finish(); return
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output)): check(false,"fresh live output required"); _finish(); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output)); output_owned=true
	root.size=Vector2i(1600,900)
	var slot:=MemorySlot.new(); var legacy:=MemorySlot.new()
	settings=Settings.new("user://verification/career-live-no-write-%d.json"%OS.get_process_id())
	main=Main.new(); main.router=Router.new({"mingqi_storage":slot,"legacy_storage":legacy,"settings_storage":settings}); root.add_child(main)
	for frame in 5: await process_frame
	var entry_started:=Time.get_ticks_usec()
	main.menu.find_child("mingqi",true,false).pressed.emit()
	if not await _await_scene("mingqi"): _finish(); return
	var entry_ms:=float(Time.get_ticks_usec()-entry_started)/1000.0
	var game: Node=main.current_scene
	root.grab_focus()
	for frame in 3: await process_frame
	if not check(root.has_focus() and root.visible,"live game window is actually focused and visible"): _finish(); return
	game.interface.close_panel(); game.interface.close_menu()
	game.runtime.set_pause("player",false); game.runtime.set_pause("blur",false)
	var measured: Array=[]
	if "--render-metrics" in OS.get_cmdline_user_args():
		measured.append({"name":"main","rid":root.get_viewport_rid()})
		for viewport:SubViewport in root.find_children("*","SubViewport",true,false): measured.append({"name":String(viewport.get_path()),"rid":viewport.get_viewport_rid()})
		for viewport:Dictionary in measured: RenderingServer.viewport_set_measure_render_time(viewport.rid,true)
	var start:=Time.get_ticks_usec(); var previous:=start
	var prior_physics:=Engine.get_physics_frames()
	var rows: Array=[]
	var native_start: float=game.runtime.simulation.encounter.tick*(1.0/60.0)
	while float(Time.get_ticks_usec()-start)/1000000.0<12.0:
		await process_frame
		var now:=Time.get_ticks_usec(); var physics:=Engine.get_physics_frames()
		rows.append({"wallSeconds":float(now-start)/1000000.0,"intervalMs":float(now-previous)/1000.0,"physicsSteps":physics-prior_physics,"focused":root.has_focus(),"visible":root.visible,"paused":game.runtime.is_paused(),"nativeTime":game.runtime.simulation.encounter.tick*(1.0/60.0)})
		if not measured.is_empty():
			var render_times:Array=[]
			for viewport:Dictionary in measured: render_times.append({"name":viewport.name,"cpuMs":RenderingServer.viewport_get_measured_render_time_cpu(viewport.rid),"gpuMs":RenderingServer.viewport_get_measured_render_time_gpu(viewport.rid)})
			rows[-1].renderTimes=render_times
			rows[-1].renderSetupCpuMs=RenderingServer.get_frame_setup_time_cpu()
			rows[-1].engineProcessMonitorMs=Performance.get_monitor(Performance.TIME_PROCESS)*1000.0
			rows[-1].enginePhysicsMonitorMs=Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0
		previous=now; prior_physics=physics
	var valid:=true
	for row: Dictionary in rows:
		if not row.focused or not row.visible or row.paused: valid=false
	var visible_crew:=0
	for crew:Node3D in game.sailors.values(): visible_crew+=crew.get_visible_count()
	var observed: Dictionary={"scope":"12 second actual engine frames, including 2 second warmup; no manual _physics_process/advance calls, FPS cap or GPU readback while timing; not long-duration acceptance.","valid":valid,"entryWallMs":entry_ms,"shipCount":game.ships.size(),"visibleCrew":visible_crew,"nativeStart":native_start,"nativeEnd":game.runtime.simulation.encounter.tick*(1.0/60.0),"gpu":RenderingServer.get_video_adapter_name(),"physicsHz":Engine.physics_ticks_per_second,"maxPhysicsStepsPerFrame":Engine.max_physics_steps_per_frame,"settings":settings.snapshot(),"rows":rows}
	var file:=FileAccess.open(output+"/live-observation.json",FileAccess.WRITE)
	if check(file!=null,"real frame observation receipt opens"): file.store_string(JSON.stringify(observed,"\t")); file.close()
	game.set_physics_process(false); game.set_process(false); game.runtime.set_pause("player",true); game._present(0.0)
	await _capture("career-after-live-observation",game)
	check(slot.writes==0 and legacy.writes==0,"real observation preserves user save slots")
	print("CAREER_LIVE_OBSERVATION frames=",rows.size()," valid=",valid," nativeSeconds=",observed.nativeEnd-native_start)
	_finish()
