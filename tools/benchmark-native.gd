extends SceneTree
## Real idle-render/physics benchmark. Never manually advances the product.
const QA = preload("res://game/scenes/visual_qa/visual_qa.tscn")
const Settings = preload("res://game/persistence/user_settings.gd")
var scenario := "benchmark"
var quality := "balanced"
var output := "res://docs/migration/evidence/native-performance"
var cycles := 3
var samples: Array = []
var actors: Array = []
var invalid: Array = []
var scene: Node
var started := 0.0
var previous := 0.0
var prefix := ""
var setup_only := false
var setup_audit: Array=[]
func _initialize() -> void: run.call_deferred()
func stats(values: Array) -> Dictionary:
	if values.is_empty(): return {"count":0,"meanMs":null,"p95Ms":null,"p99Ms":null,"worstMs":null,"fps":null}
	var sorted := values.duplicate(); sorted.sort(); var total := 0.0
	for value in values: total += float(value)
	return {"count":values.size(),"meanMs":total/values.size(),"p95Ms":sorted[ceili(values.size()*0.95)-1],"p99Ms":sorted[ceili(values.size()*0.99)-1],"worstMs":sorted.back(),"fps":values.size()*1000/total if total>0 else null}
func mark(reason: String) -> void:
	if reason not in invalid: invalid.append(reason)
func load_changes(expected: Dictionary,actual: Dictionary) -> Array:
	var changed: Array=[]
	for key in expected:
		if not actual.has(key) or actual[key]!=expected[key]: changed.append(key)
	for key in actual:
		if not expected.has(key): changed.append(key)
	return changed
func fixed_load() -> Dictionary:
	var viewport_size:=root.get_visible_rect().size
	var render_size:=root.get_texture().get_size()
	return {"window":[root.size.x,root.size.y],"viewport":[viewport_size.x,viewport_size.y],"renderTextureSize":[render_size.x,render_size.y],"contentScaleSize":[root.content_scale_size.x,root.content_scale_size.y],"contentScaleFactor":root.content_scale_factor,"quality":scene.services.settings_storage.snapshot().quality,"settings":scene.services.settings_storage.snapshot(),"handling":scene.runtime._handling,"playback":scene.runtime._playback,"scenario":scene.runtime._scenario,"generation":scene.runtime._generation,"tactical":scene.sea.tactical,"msaa3d":root.msaa_3d,"scaling3dScale":root.scaling_3d_scale,"scaling3dMode":root.scaling_3d_mode,"physicsTicksPerSecond":Engine.physics_ticks_per_second,"maxFps":Engine.max_fps,"timeScale":Engine.time_scale,"vsyncMode":DisplayServer.window_get_vsync_mode()}
func audit_regression() -> bool:
	var expected:={"window":[1600,900],"viewport":[1600,900],"quality":"balanced","handling":"realistic","playback":1.0}
	var ok:=load_changes(expected,expected.duplicate(true)).is_empty()
	for key in expected:
		var changed:=expected.duplicate(true)
		changed[key]=[800,450] if key in ["window","viewport"] else "low" if key=="quality" else "assisted" if key=="handling" else 0.25
		if key not in load_changes(expected,changed): printerr("FAIL fixed-load audit: ",key); ok=false
	var retained: Array=[]
	var reasons: Array=[]
	for width in [1600,800,1600]:
		var actual:=expected.duplicate(true); actual.window=[width,900]
		var changed:=load_changes(expected,actual)
		retained.append({"load":actual,"changes":changed})
		for key in changed:
			if key not in reasons: reasons.append(key)
	if retained.size()!=3 or retained[1].load.window[0]!=800 or reasons!=["window"]: printerr("FAIL audit loses restored invalid interval"); ok=false
	var nested:={"settings":{"quality":"balanced","sound":true},"generation":1,"scenario":"benchmark"}
	var altered:=nested.duplicate(true); altered.settings.sound=false
	if load_changes(nested,altered)!=["settings"]: printerr("FAIL nested load setting"); ok=false
	altered=nested.duplicate(true); altered.generation=2
	if load_changes(nested,altered)!=["generation"]: printerr("FAIL restart detection"); ok=false
	altered=nested.duplicate(true); altered.erase("scenario")
	if load_changes(nested,altered)!=["scenario"]: printerr("FAIL missing fixed setting"); ok=false
	return ok
func spawn_scene() -> Node:
	var node := QA.instantiate()
	node.startup_options={"dev":true,"scenario":scenario}
	node.settings_storage=Settings.new(prefix+"-settings.json")
	var receipt: Dictionary=node.settings_storage.update_settings({"quality":quality})
	if not receipt.ok: mark("isolated-settings-write-failed")
	root.add_child(node)
	return node
func resources() -> Dictionary:
	return {"nodes":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),"objects":int(Performance.get_monitor(Performance.OBJECT_COUNT)),"resources":int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),"orphanNodes":int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),"staticMemoryBytes":int(Performance.get_monitor(Performance.MEMORY_STATIC)),"renderVideoMemoryBytes":int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),"physicsActiveObjects":int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))}
func frames(count: int=5) -> void:
	for index in count: await process_frame
func calibrate_window() -> bool:
	# Win32 style transitions must settle before requesting final client dimensions.
	root.unresizable=true
	await frames(3)
	for attempt in 4:
		root.size=Vector2i(1600,900)
		root.content_scale_size=Vector2i(1600,900)
		for frame in 3: await RenderingServer.frame_post_draw
		var load_state:=fixed_load()
		setup_audit.append({"attempt":attempt+1,"fixedLoad":load_state})
		if load_state.window==[1600,900] and load_state.viewport==[1600.0,900.0] and load_state.renderTextureSize==[1600.0,900.0]:
			return true
	return false
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="): scenario=arg.trim_prefix("--scenario=")
		elif arg.begins_with("--quality="): quality=arg.trim_prefix("--quality=")
		elif arg.begins_with("--output="): output=arg.trim_prefix("--output=")
		elif arg.begins_with("--cycles="): cycles=int(arg.trim_prefix("--cycles="))
		elif arg=="--setup-only": setup_only=true
		elif arg=="--dry-run":
			var result:=stats([10.0,20.0,30.0,40.0])
			var ok: bool=result.meanMs==25 and result.p95Ms==40 and result.p99Ms==40 and result.worstMs==40 and stats([]).fps==null and audit_regression()
			print("NATIVE_BENCHMARK_DRY_RUN parser/statistics only; no performance evidence; failures=",0 if ok else 1)
			quit(0 if ok else 1); return
	if scenario not in ["benchmark","fleet"] or quality not in ["low","balanced","high"] or cycles<0 or cycles>10:
		printerr("Invalid --scenario=benchmark|fleet --quality=low|balanced|high --cycles=0..10"); quit(2); return
	if DisplayServer.get_name()=="headless": printerr("Real benchmark requires visible GPU window; use --dry-run for headless validation"); quit(2); return
	root.unresizable=true
	prefix="user://tests/native-performance-%d-%s" % [OS.get_process_id(),scenario]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(prefix.get_base_dir()))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var baseline:=resources()
	scene=spawn_scene(); await frames()
	if not scene.startup_receipt.get("ok",false): printerr("Native QA startup failed"); quit(1); return
	scene.set_process(false)
	var calibrated: bool=await calibrate_window()
	if setup_only:
		print("NATIVE_BENCHMARK_SETUP_ONLY ",JSON.stringify({"validDimensions":calibrated,"actualFixedLoad":fixed_load(),"setupAudit":setup_audit,"snapshot":scene.runtime.snapshot(),"scope":"Actual visible GPU setup only; no timed performance sample"}))
		scene.queue_free(); await frames(); quit(0 if calibrated else 1); return
	if not calibrated:
		printerr("NATIVE_BENCHMARK_SETUP_FAILED ",JSON.stringify(setup_audit))
		scene.queue_free(); await frames(); quit(1); return
	# Restart establishes the unchanged source benchmark clock after startup/import.
	scene._command({"type":"restart"})
	scene.set_process(true)
	var initial_native: Dictionary=scene.runtime.snapshot().naval
	var expected_load:=fixed_load()
	if expected_load.window!=[1600,900] or expected_load.viewport!=[1600.0,900.0] or expected_load.renderTextureSize!=[1600.0,900.0]: mark("initial-viewport-not-1600x900")
	started=Time.get_ticks_usec()/1000.0; previous=started
	var next_actor:=0.0
	while true:
		await process_frame
		var now:=Time.get_ticks_usec()/1000.0; var elapsed: float=(now-started)/1000.0
		var reasons: Array=scene.runtime._pauses.keys()
		var external:=reasons.duplicate(); external.erase("benchmark")
		var visible:=root.visible; var focused:=root.has_focus()
		var actual_load:=fixed_load(); var changes:=load_changes(expected_load,actual_load)
		for changed in changes: mark("fixed-load-changed-"+str(changed))
		if not external.is_empty(): mark("external-pause")
		if not visible: mark("hidden-window")
		if not focused: mark("window-unfocused")
		var included: bool=elapsed>=20 and elapsed<80
		samples.append({"callbackTimestampMs":now,"elapsedMs":now-previous,"wallSeconds":elapsed,"includedInMetrics":included,"valid":external.is_empty() and visible and focused and changes.is_empty(),"pauseReasons":reasons,"visible":visible,"focused":focused,"fixedLoad":actual_load,"fixedLoadChanges":changes,"processMonitorMs":Performance.get_monitor(Performance.TIME_PROCESS)*1000,"physicsMonitorMs":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000})
		previous=now
		if elapsed>=next_actor:
			actors.append({"wallSeconds":elapsed,"inspection":scene.inspection_snapshot(),"resources":resources()}); next_actor=elapsed+1
		if scenario=="benchmark" and scene.runtime.phase()=="complete": break
		if scenario=="fleet" and elapsed>=80: break
		if elapsed>=110: mark("source-benchmark-did-not-complete-before-110s"); break
	# No resumes/restarts erase an interrupted interval. Retain the whole failed run.
	# Sampling has stopped. Synchronize/read GPU pixels only now, never in the loop.
	scene.set_process(false) # Freeze QA idle diagnostics after final timed interval.
	await RenderingServer.frame_post_draw
	var capture_path:=output+"/"+scenario+"-viewport.png"
	var capture_image:=root.get_texture().get_image()
	var capture_error:=capture_image.save_png(capture_path)
	if capture_error!=OK: mark("post-measurement-viewport-capture-failed")
	var capture_sha256: Variant=null
	if capture_error==OK:
		var hash:=HashingContext.new()
		if hash.start(HashingContext.HASH_SHA256)==OK:
			var png_bytes:=FileAccess.get_file_as_bytes(capture_path)
			if png_bytes.is_empty() or hash.update(png_bytes)!=OK: mark("post-measurement-viewport-hash-failed")
			else: capture_sha256=hash.finish().hex_encode()
		else: mark("post-measurement-viewport-hash-failed")
	var viewport_capture:={"path":ProjectSettings.globalize_path(capture_path),"sha256":capture_sha256,"width":capture_image.get_width(),"height":capture_image.get_height(),"saved":capture_error==OK,"capturedAfterMeasurement":true,"measurementStoppedAtMs":previous,"captureCompletedAtMs":Time.get_ticks_usec()/1000.0}
	var packet: Dictionary=scene.runtime.snapshot()
	if packet.naval.ships.size()!=(3 if scenario=="benchmark" else 6): mark("unexpected-source-ship-count")
	if scenario=="benchmark" and (packet.runtime.phase!="complete" or "benchmark" not in packet.runtime.pauseReasons): mark("source-auto-pause-missing")
	var diagnostics: Dictionary=scene.export_diagnostics(output+"/"+scenario+"-frame-diagnostics.json")
	if not diagnostics.ok: mark("diagnostics-export-failed")
	var intervals: Array=[]; var process_values: Array=[]; var physics_values: Array=[]
	var source_intervals: Array=[]
	for source_sample in scene.runtime.diagnostics.snapshot().samples:
		if source_sample.includedInMetrics: source_intervals.append(source_sample.elapsedMs)
	for sample in samples:
		if sample.includedInMetrics:
			intervals.append(sample.elapsedMs); process_values.append(sample.processMonitorMs); physics_values.append(sample.physicsMonitorMs)
	var report:={"schema":"ming-armada-native-performance-acceptance-v1","valid":invalid.is_empty(),"invalidReasons":invalid,"scenario":scenario,"warmupWallSeconds":20,"samplingWallSeconds":60,"actualWallSeconds":(previous-started)/1000,"metadata":{"engine":Engine.get_version_info(),"platform":OS.get_name(),"processor":OS.get_processor_name(),"processId":OS.get_process_id(),"gpu":RenderingServer.get_video_adapter_name(),"renderingMethod":RenderingServer.get_current_rendering_method(),"viewport":[root.size.x,root.size.y],"settings":scene.services.settings_storage.snapshot(),"actualHandling":packet.runtime.handlingMode,"playback":packet.runtime.playback,"physicsEngine":ProjectSettings.get_setting("physics/3d/physics_engine"),"isolatedPaths":{"settings":prefix+"-settings.json","career":"not opened; direct source QA scene"}},"intervalMetrics":stats(intervals),"processMonitorMetrics":stats(process_values),"physicsMonitorMetrics":stats(physics_values),"gpuCompletionMs":null,"renderSubmitMs":null,"nativeFinal":packet,"rawObservedIntervals":samples,"actorTimeline":actors,"frameDiagnosticsExport":diagnostics,"scope":"Actual Godot scene _process wall clock, rendering and native physics. Monitor CPU times are engine monitors, not GPU completion or per-scene exclusive times. Invalid runs retain every interval and are not acceptance results."}
	# Real scene entry/dispose proof after measurement; queue_free and engine frames.
	var release: Array=[]
	report.sourceFrameDiagnosticsMetrics=stats(source_intervals)
	report.viewportCapture=viewport_capture
	report.expectedFixedLoad=expected_load
	report.setupAudit=setup_audit
	report.nativeProgress={"initialTick":initial_native.tick,"finalTick":packet.naval.tick,"advancedTicks":packet.naval.tick-initial_native.tick,"initialTime":initial_native.time,"finalTime":packet.naval.time,"consumedSimulationSeconds":packet.naval.time-initial_native.time}
	scene.queue_free(); await frames(12); release.append({"stage":"measured-scene-disposed","resources":resources(),"baseline":baseline})
	for index in cycles:
		var before:=resources(); scene=spawn_scene(); await frames(12)
		var during:=resources(); var count: int=scene.runtime.snapshot().naval.ships.size()
		scene.queue_free(); await frames(12)
		release.append({"cycle":index+1,"before":before,"during":during,"after":resources(),"actualShipCount":count,"sceneStillValid":is_instance_valid(scene)})
	report.resourceRelease=release
	var file:=FileAccess.open(output+"/"+scenario+"-acceptance.json",FileAccess.WRITE)
	if not file: printerr("Cannot write acceptance JSON"); quit(1); return
	file.store_string(JSON.stringify(report,"  ")); file.close()
	print("NATIVE_BENCHMARK_COMPLETE scenario=",scenario," valid=",invalid.is_empty()," wallSeconds=",report.actualWallSeconds," failures=",0 if invalid.is_empty() else 1)
	quit(0 if invalid.is_empty() else 1)
