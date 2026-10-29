extends SceneTree
const Scene=preload("res://game/scenes/naval_practice/naval_practice.gd")
var assertions:=0
var failures:=0
func check(value:bool,detail:String)->void:
	assertions+=1
	if not value:failures+=1;printerr("FAIL: ",detail)
func _initialize()->void:run.call_deferred()
func run()->void:
	root.size=Vector2i(1600,900)
	var scene:Scene=Scene.new();scene.startup_options={"mode":"fire"};root.add_child(scene);await process_frame
	scene.set_physics_process(false);scene.set_process(false)
	check(scene.startup_receipt.ok,"actual fire scene starts")
	scene.interface.find_child("toggle_fire",true,false).pressed.emit();await process_frame
	var target:OptionButton=scene.interface.find_child("FireTarget",true,false)
	target.grab_focus();target.select(0);target.item_selected.emit(0);await process_frame
	check(root.gui_get_focus_owner()!=target,"selecting a target returns keyboard ownership to the ship")
	var forward:InputEventKey=InputEventKey.new();forward.keycode=KEY_W;forward.physical_keycode=KEY_W;forward.pressed=true
	root.push_input(forward,true)
	check(scene.runtime.simulation._held.has("KeyW"),"real W input reaches the helm after target selection")
	forward.pressed=false;root.push_input(forward,true)
	check(scene._camera_input_ready(),"closed target selector no longer blocks camera control")
	forward.pressed=true;root.push_input(forward,true)
	scene.runtime.command({"type":"fire-control","crew":2})
	var pending:Array=scene.runtime.simulation._queued.duplicate(true)
	target.get_popup().about_to_popup.emit()
	check(not scene.runtime.simulation._held.has("KeyW"),"opening the modal target list releases helm keys whose key-up may be consumed by its Window")
	check(scene.runtime.simulation._queued==pending and not pending.is_empty(),"popup key release retains already queued combat orders")
	target.get_popup().popup_hide.emit()
	var packet:Dictionary=scene.runtime.snapshot();var player:Dictionary=packet.naval.ships[0]
	player.crew=3;player.availableCrew=0;player.fireLauncher.operationSeconds=1.0;player.fireControl.heat=28.0;player.fireControl.fuelSeconds=18.0
	scene.interface.apply_snapshot(packet)
	var fight_fire:Button=scene.interface.find_child("fight_fire",true,false)
	check(fight_fire!=null,"real scene owns the single firefighting action")
	if fight_fire!=null:
		check(fight_fire.disabled,"three surviving operators cannot also start firefighting")
		player.crew=7;player.availableCrew=3
		scene.interface.apply_snapshot(packet)
		check(fight_fire.disabled,"active launcher operators stay unavailable even when total crew exceeds four")
		player.crew=8;player.availableCrew=4
		scene.interface.apply_snapshot(packet)
		check(not fight_fire.disabled,"four crew beyond active launcher operators can form the fixed team")
	scene.free();await process_frame
	print("FIRE_SKIRMISH_INPUT_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
