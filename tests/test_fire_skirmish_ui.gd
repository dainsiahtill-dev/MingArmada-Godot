extends SceneTree
const Interface=preload("res://game/ui/naval_practice.gd")
const Runtime=preload("res://game/runtime/naval_practice_runtime.gd")
var assertions:=0
var failures:=0
func check(value:bool,detail:String)->void:
	assertions+=1
	if not value:failures+=1;printerr("FAIL: ",detail)
func _initialize()->void:run.call_deferred()
func run()->void:
	root.size=Vector2i(1600,900)
	var ui:Interface=Interface.new();root.add_child(ui);await process_frame
	var toggle:Button=ui.find_child("toggle_fire",true,false)
	check(toggle!=null,"actual HUD exposes fire and damage-control folio")
	if toggle==null:ui.free();finish();return
	var runtime:Runtime=Runtime.new()
	check(runtime.configure(func(_x,_z):return -50.0,{"mode":"fire"}).ok,"fire HUD consumes an actual practice runtime")
	var events:Array=[];ui.command_requested.connect(func(command):events.append(command.duplicate(true)))
	ui.apply_snapshot(runtime.snapshot());toggle.pressed.emit();await process_frame
	var target:OptionButton=ui.find_child("FireTarget",true,false)
	var fire_ball:Button=ui.find_child("fire_ball",true,false)
	check(target!=null and target.item_count==1 and target.get_item_metadata(0)=="enemy-1","target selector holds a live enemy stable ID")
	check(not fire_ball.disabled,"in-range supplied launcher is available")
	fire_ball.pressed.emit()
	check(events.back()=={"type":"launch-fire","payload":"fire-ball","targetId":"enemy-1"},"button reads actual selected target on press")
	var fight_fire:Button=ui.find_child("fight_fire",true,false)
	check(fight_fire!=null,"fire folio exposes one firefighting action")
	if fight_fire==null:ui.free();runtime.dispose();finish();return
	for old_id:String in ["fire_team_0","fire_team_2","fire_team_4","fire_team_8"]:
		check(ui.find_child(old_id,true,false)==null,"manual team choice is absent: "+old_id)
	var fire_state:Label=ui.find_child("FireState",true,false)
	var fire_stores:Label=ui.find_child("FireStores",true,false)
	check(fight_fire.text=="扑救火灾" and fight_fire.disabled and fire_state.text.contains("未起火"),"cold ship presents the single action as unavailable")
	check(fire_stores.text.contains("扑救储备") and fire_stores.text.contains("24"),"finite preparation remains visible without a resource control")
	var hot:Dictionary=hot_packet(runtime)
	ui.apply_snapshot(hot)
	check(not fight_fire.disabled,"burning ship with four available crew can request firefighting")
	var event_count:int=events.size()
	fight_fire.pressed.emit()
	check(events.size()==event_count+1 and events.back()=={"type":"fire-control","crew":4},"one firefighting press emits the fixed four-person native command")
	var packet:Dictionary=hot.duplicate(true)
	packet.naval.ships[0].availableCrew=3
	ui.apply_snapshot(packet)
	check(fight_fire.disabled,"three available crew cannot start an ineffective smaller team")
	packet=hot.duplicate(true)
	packet.naval.ships[0].fireControl.pendingFirefighters=4;packet.naval.ships[0].fireControl.transferTicks=120
	ui.apply_snapshot(packet)
	check(fight_fire.disabled and fire_state.text.contains("赶往火场"),"outbound team blocks duplicate assignment and reports travel")
	packet=hot.duplicate(true)
	packet.naval.ships[0].fireControl.assignedFirefighters=4;packet.naval.ships[0].fireControl.pendingFirefighters=4
	ui.apply_snapshot(packet)
	check(fight_fire.disabled and fire_state.text.contains("扑救中"),"working team cannot be reassigned from the simple action")
	packet=runtime.snapshot()
	packet.naval.ships[0].fireControl.assignedFirefighters=4;packet.naval.ships[0].fireControl.transferTicks=120
	ui.apply_snapshot(packet)
	check(fight_fire.disabled and fire_state.text.contains("正在归位"),"extinguished team reports automatic return without a withdrawal control")
	packet=hot.duplicate(true)
	packet.naval.ships[0].fireControl.supplies=0
	ui.apply_snapshot(packet)
	check(fight_fire.disabled and fight_fire.tooltip_text.contains("储备") and fight_fire.tooltip_text.contains("耗尽"),"exhausted preparation blocks ineffective work with a visible reason")
	packet=hot.duplicate(true)
	packet.naval.ships[0].fireControl.supplies=0
	packet.naval.ships[0].fireControl.assignedFirefighters=4;packet.naval.ships[0].fireControl.pendingFirefighters=4
	ui.apply_snapshot(packet)
	check(not fight_fire.disabled and fight_fire.text=="返回岗位","exhausted active team can return through the same single action")
	event_count=events.size();fight_fire.pressed.emit()
	check(events.size()==event_count+1 and events.back()=={"type":"fire-control","crew":0},"context return releases exhausted duty through the original authoritative seam")
	packet=hot.duplicate(true);packet.naval.status="victory"
	ui.apply_snapshot(packet)
	check(fight_fire.disabled,"terminal combat cannot offer a new team")
	runtime.set_pause("player",true);packet=hot_packet(runtime);ui.apply_snapshot(packet)
	check(fire_ball.disabled and fight_fire.disabled,"paused controls cannot suggest active combat")
	runtime.set_pause("player",false)
	packet=runtime.snapshot();packet.naval.ships[1].hull=0.0
	ui.apply_snapshot(packet)
	check(target.item_count==0 and fire_ball.disabled,"sunk target is removed and cannot receive a stale launch")
	for size in [Vector2i(800,600),Vector2i(320,480)]:
		root.size=size;root.content_scale_size=size;ui.apply_snapshot(runtime.snapshot())
		await process_frame;await process_frame
		var panel:Control=ui.find_child("FirePanel",true,false)
		check(panel.get_global_rect().position.x>=0 and panel.get_global_rect().end.x<=float(size.x)+1.0 and panel.get_global_rect().end.y<=float(size.y)+1.0,"fire panel stays inside narrow viewport "+str(size))
		check(ui.find_child("FireScroll",true,false) is ScrollContainer,"long tactical controls retain native scrolling")
	ui.free();runtime.dispose();finish()
func hot_packet(runtime:Runtime)->Dictionary:
	var packet:Dictionary=runtime.snapshot()
	packet.naval.ships[0].fireControl.heat=28.0;packet.naval.ships[0].fireControl.fuelSeconds=18.0
	return packet
func finish()->void:
	print("FIRE_SKIRMISH_UI_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
