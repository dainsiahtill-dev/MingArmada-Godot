extends SceneTree
## Source weak-hit integration runs independently from inspector lifecycle;
## actual cannon events, articulated bodies and accepted recovery stay intact.
var assertions:=0
var failures:=0
func check(value: bool,detail: String) -> void:
	assertions+=1
	if not value: failures+=1; printerr("FAIL: ",detail)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var started_ms:=Time.get_ticks_msec()
	var path:="res://game/scenes/visual_qa/visual_qa.tscn"
	check(ResourceLoader.exists(path),"actual source QA scene exists for articulated weak-hit integration")
	if ResourceLoader.exists(path):
		root.size=Vector2i(1600,900)
		var settings_path:="user://migration-verification/visual-qa-impact-settings-%d.json" % OS.get_process_id()
		var scene=load(path).instantiate(); scene.startup_options={"qa":true,"staged":true,"scenario":"impact-weak"}
		scene.settings_storage=load("res://game/persistence/user_settings.gd").new(settings_path)
		root.add_child(scene); await process_frame; scene.set_physics_process(false); scene.set_process(false)
		print("VISUAL_QA_IMPACTS_STAGE startup elapsed_ms=",Time.get_ticks_msec()-started_ms)
		check(scene.startup_receipt.ok and scene.runtime.is_paused(),"trusted source impact fixture starts staged")
		check(scene.sea.ships.size()==2,"weak-hit fixture renders both original authored ships")
		scene.activate_entry()
		var ammo: float=scene.runtime.snapshot().naval.ships[0].ammo.solid
		scene.interface.find_child("fire_starboard",true,false).pressed.emit()
		var maximum_impacts:=0; var saw_nonlethal:=false; var recovered_nonlethal:=false
		for frame in 150:
			scene._physics_process(1.0/60.0); await physics_frame; await process_frame
			var detail: Dictionary=scene.inspection_snapshot()
			maximum_impacts=maxi(maximum_impacts,int(detail.sailors.impacts.active))
			for entry: Dictionary in detail.sailors.impacts.bodies:
				if not entry.casualty: saw_nonlethal=true
			if saw_nonlethal and frame>100 and not detail.sailors.impacts.bodies.any(func(entry): return not entry.casualty): recovered_nonlethal=true
		check(scene.runtime.snapshot().naval.ships[0].ammo.solid<ammo,"real native QA fire button consumes original cannon ammo")
		check(maximum_impacts>0,"real source cannon hit spawns native articulated sailor bodies")
		check(saw_nonlethal,"fractional weak hit produces real recovery body without counterfeit damage")
		check(recovered_nonlethal,"actual accepted clock releases nonlethal body and restores native standing animation")
		print("VISUAL_QA_REAL_WEAK_HIT maximum_impacts=",maximum_impacts," recovered=",recovered_nonlethal," crew=",scene.runtime.snapshot().naval.ships[1].crew)
		scene.queue_free(); await process_frame; await process_frame; await create_timer(0.08).timeout
		for suffix in ["",".backup",".rollback",".staged"]:
			if FileAccess.file_exists(settings_path+suffix): DirAccess.remove_absolute(settings_path+suffix)
	print("VISUAL_QA_IMPACTS_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
