extends SceneTree
## Actual Mingqi callbacks with a validated lethal-health fixture. This is
## terminal-state diagnosis, not a real cannon flight or a wall-time benchmark.
const Scene=preload("res://game/scenes/mingqi/mingqi_scene.gd")
const Settings=preload("res://game/persistence/user_settings.gd")
const AudioCleanup=preload("res://tests/fixtures/audio_cleanup.gd")
func _initialize()->void:_run.call_deferred()
func _run()->void:
	var output:="res://Temp/terminal-sink-audit.json"
	if FileAccess.file_exists(output):printerr("Fresh diagnostic output required");quit(1);return
	var scene:=Scene.new()
	scene.settings_storage=Settings.new("user://verification/terminal-sink-audit-no-write-%d.json"%OS.get_process_id())
	root.add_child(scene);scene.set_physics_process(false);scene.set_process(false)
	if not scene.startup_receipt.get("ok",false):printerr("Actual scene startup rejected");scene.free();quit(1);return
	scene.interface.close_panel();scene.interface.close_menu()
	for reason in ["player","blur","loading"]:scene.runtime.set_pause(reason,false)
	var packet:Dictionary=scene.runtime.snapshot()
	var id:String=packet.naval.playerId
	var view:Node3D=scene.ships[id]
	var before:Dictionary=view.damage_diagnostics()
	var fixture:Dictionary=scene.runtime.simulation.encounter.update_ship_stats(id,{"hull":0.0})
	if not fixture.get("ok",false):printerr("Validated lethal fixture rejected");scene.free();quit(1);return
	scene._physics_process(1.0/60.0);scene._process(1.0/60.0)
	var lethal:Dictionary=scene.runtime.snapshot()
	var started:Dictionary=view.damage_diagnostics()
	var y_before:float=view.get_model().position.y
	for unused in 50:
		scene._physics_process(0.1);scene._process(0.1)
	var after:Dictionary=scene.runtime.snapshot()
	var final:Dictionary=view.damage_diagnostics()
	var report:Dictionary={"scope":"Actual Mingqi scene and production callbacks; public validated hull=0 fixture; 50 requested 0.1s intervals, no real projectile or FPS claim", "fixture":fixture,"before":before,"lethalNativeTime":lethal.naval.time,"lethalPauseReasons":lethal.runtime.pauseReasons,"started":started,"finalNativeTime":after.naval.time,"finalPauseReasons":after.runtime.pauseReasons,"final":final,"modelYBefore":y_before,"modelYAfter":view.get_model().position.y,"modelVisible":view.get_model().visible,"foundFreeze":after.runtime.pauseReasons.has("result") and absf(after.naval.time-lethal.naval.time)<1e-8 and final.sinking_age==started.sinking_age and not final.ended}
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file==null:printerr("Diagnostic receipt could not open");scene.free();quit(1);return
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("TERMINAL_SINK_AUDIT found_freeze=",report.foundFreeze," age=",final.sinking_age," ended=",final.ended)
	var playbacks:=AudioCleanup.stop_players(scene);scene.free()
	var clean:bool=await AudioCleanup.wait_for_release(self,playbacks)
	quit(0 if report.foundFreeze and clean else 1)
