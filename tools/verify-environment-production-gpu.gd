extends SceneTree
## Actual production scenes, isolated runtime only; no user saves or menu entries.
const Practice=preload("res://game/scenes/naval_practice/naval_practice.gd")
const AudioCleanup=preload("res://tests/fixtures/audio_cleanup.gd")
const Settings=preload("res://game/persistence/user_settings.gd")
var scene:Node3D
var failures:=0
var records:Array=[]
var output:="res://docs/migration/evidence/weather-cloud-shadow-wake-integration-2026-10-13/gpu"
func _initialize()->void:run.call_deferred()
func check(ok:bool,message:String)->void:
	if not ok:failures+=1;printerr("FAIL production environment GPU: ",message)
func frames(count:int)->void:
	for i in count:await process_frame
func enter(mode:String)->bool:
	scene=Practice.new();scene.startup_options={"mode":mode,"staged":true}
	scene.settings_storage=Settings.new("user://tests/environment-gpu-%s-settings.json"%OS.get_process_id())
	root.add_child(scene)
	await frames(2);scene.set_physics_process(false);scene.set_process(false)
	check(scene.startup_receipt.get("ok",false),mode+" actual scene startup")
	if not scene.startup_receipt.get("ok",false):return false
	scene.activate_entry()
	scene.sea.apply_settings({"quality":"balanced"})
	# Background verification deliberately consumes the isolated accepted
	# runtime; actual player focus/blur policy is tested separately through UI.
	scene.runtime.set_pause("blur",false)
	await frames(8)
	return true
func ticks(count:int)->void:
	for i in count:
		scene.runtime.set_pause("blur",false)
		scene._physics_process(1.0/60.0);scene._present(0.0)
		await process_frame
func capture(label:String,extra:Dictionary={})->void:
	await frames(3);await RenderingServer.frame_post_draw
	var pixels:=root.get_texture().get_image()
	check(pixels.save_png(output+"/"+label+".png")==OK,label+" screenshot")
	var native:Dictionary=scene.runtime.snapshot().naval
	var packet:Dictionary={"label":label,"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"acceptedTime":native.time,"environmentTime":native.environment.acceptedTime,"environmentRoute":native.environment.route,"sourceCallIndex":native.environment.sourceCallIndex,"ships":native.ships,"wake":scene.sea.wakes.diagnostics(),"atmosphere":scene.sea.world.atmosphere.diagnostics(),"shadow":scene.sea.source_shadow_status(),"viewport":[pixels.get_width(),pixels.get_height()],"scope":"actual production scene with deterministic accepted runtime, not interactive FPS"}
	packet.merge(extra,true);records.append(packet)
	var file:=FileAccess.open(output+"/"+label+".json",FileAccess.WRITE);file.store_string(JSON.stringify(packet,"\t"));file.close()
	check(packet.wake.get("source_errors",{}).is_empty(),label+" source wake diagnostics")
	check(packet.shadow.get("errors",[]).is_empty(),label+" source shadow diagnostics")
func leave()->void:
	var playbacks:Array[WeakRef]=AudioCleanup.stop_players(scene)
	scene.free();scene=null;await frames(4)
	check(await AudioCleanup.wait_for_release(self,playbacks),"actual scene audio cleanup")
func run()->void:
	root.size=Vector2i(1600,900);root.content_scale_size=Vector2i(1600,900)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	check(RenderingServer.get_current_rendering_method()=="forward_plus","actual Forward+ renderer")
	if await enter("sail"):
		await capture("sailing-start")
		var before:Dictionary=scene.runtime.snapshot().naval.ships[0].visual.position.duplicate(true)
		var receipt:Dictionary=scene.runtime.command({"type":"mouse-course","point":{"x":before.x+300.0,"z":before.z+180.0}})
		check(receipt.ok,"production mouse course accepted on sea")
		await ticks(240);await capture("sailing-moving")
		var after:Dictionary=scene.runtime.snapshot().naval.ships[0].visual.position
		var travelled:=Vector2(after.x-before.x,after.z-before.z).length()
		check(travelled>1.0,"actual open-water displacement, not coast-blocked HUD speed")
		scene.runtime.set_pause("player",true);scene.sea.zoom=0.65
		var down:=InputEventMouseButton.new();down.button_index=MOUSE_BUTTON_RIGHT;down.pressed=true
		scene.sea.handle_camera_input(down)
		var drag:=InputEventMouseMotion.new();drag.relative=Vector2(150.0,-20.0)
		scene.sea.handle_camera_input(drag);scene.sea.cancel_camera_drag();scene._present(0.0)
		await capture("sailing-paused-orbit",{"actualDisplacementMetres":travelled})
		scene.sea.apply_settings({"quality":"low"});await capture("sailing-low")
		scene.sea.apply_settings({"quality":"high"});await capture("sailing-high")
		await leave()
	if await enter("duel"):
		await ticks(60);await capture("battle-start")
		var fire:Dictionary=scene.runtime.command({"type":"fire","side":scene.runtime.nearest_side()})
		check(fire.ok,"production cannon command accepted")
		await ticks(30);await capture("battle-cannon-smoke")
		await ticks(120);await capture("battle-tail")
		await leave()
	var report:Dictionary={"failures":failures,"captures":records.size(),"records":records,"scope":"production renderer/effect and lifecycle verification; original DX9 pixel parity and full-session FPS not claimed"}
	var file:=FileAccess.open(output+"/VERIFICATION.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("PRODUCTION_ENVIRONMENT_GPU failures=",failures," captures=",records.size())
	quit(1 if failures else 0)
