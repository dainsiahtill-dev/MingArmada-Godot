extends SceneTree
## Observes the real main menu/router/game entry. No replacement sea scene.
var failures:Array=[]
func _initialize()->void:run.call_deferred()
func statistics(values:Array)->Dictionary:
	var ordered:=values.duplicate();ordered.sort()
	return {"count":ordered.size(),"p50":ordered[int((ordered.size()-1)*.50)],"p95":ordered[int((ordered.size()-1)*.95)],"p99":ordered[int((ordered.size()-1)*.99)]}
func run()->void:
	root.size=Vector2i(1200,900);root.content_scale_size=root.size
	var main:Node=load("res://game/scenes/main/main_scene.tscn").instantiate();root.add_child(main)
	for frame in 400:
		await process_frame
		if is_instance_valid(main.current_scene) and main.current_scene.get("startup_receipt").get("ok",false):break
	if not is_instance_valid(main.current_scene):printerr("REAL_ENTRY failures=1 missing game");quit(1);return
	var game:Node=main.current_scene
	if game.runtime.snapshot().runtime.mode!="sail":printerr("REAL_ENTRY failures=1 wrong mode");quit(1);return
	for frame in 90:await process_frame
	var times:Array=[];var cpu:Array=[];var active:=0;var previous:=Time.get_ticks_usec();var first:Dictionary=game.runtime.snapshot()
	for frame in 240:
		await process_frame
		var now:=Time.get_ticks_usec();times.append(float(now-previous)/1000.0);previous=now
		cpu.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
		if root.has_focus() and not game.runtime.is_paused():active+=1
	var last:Dictionary=game.runtime.snapshot()
	if active!=240:failures.append("Some measured frames lacked focus or were paused")
	if float(last.naval.time)<=float(first.naval.time):failures.append("Native simulation did not advance")
	var directory:="res://docs/migration/evidence/hull-dynamics-2026-10-14/actual-entry"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(directory+"/main-free-trial.png")
	var report:={"scope":"Actual main menu/router Freedom Trial with unchanged world/ocean/3D crew and runtime; idle wall frame intervals, not isolated GPU timing. Includes all scene work; no inference of root cause from frame timing alone.","failures":failures,"activeFrames":active,"frameIntervalsMs":statistics(times),"processCPUms":statistics(cpu),"rawIntervalsMs":times,"initialTime":first.naval.time,"finalTime":last.naval.time,"native":last.naval,"gpu":RenderingServer.get_video_adapter_name(),"engine":Engine.get_version_info(),"renderingMethod":RenderingServer.get_current_rendering_method(),"viewport":[root.size.x,root.size.y],"source":"real main_scene.tscn --start-game=sail"}
	var file:=FileAccess.open(directory+"/VERIFICATION.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("REAL_ENTRY failures=",failures.size()," activeFrames=",active," times=",report.frameIntervalsMs)
	main.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
