extends SceneTree
const Runtime=preload("res://game/runtime/naval_practice_runtime.gd")
var checks:int=0
var failures:int=0
func check(value:bool,detail:String)->void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: ",detail)
func _initialize()->void:
	var runtime:Runtime=Runtime.new()
	check(runtime.configure(func(_x,_z):return -50.0,{"mode":"fire"}).ok,"real fire runtime configured")
	check(runtime.command({"type":"fire-control","crew":4}).ok,"original team intent queued")
	runtime.advance(1.0/60.0)
	check(runtime.snapshot().runtime.notice.contains("赶往火场"),"outbound receipt describes outbound work")
	check(runtime.command({"type":"fire-control","crew":0}).ok,"original return intent queued")
	runtime.advance(1.0/60.0)
	var packet:Dictionary=runtime.snapshot()
	var player:Dictionary=packet.naval.ships.filter(func(ship):return ship.id==packet.naval.playerId)[0]
	check(player.fireControl.pendingFirefighters==0 and player.fireControl.transferTicks>0,"native return retains its real travel interval")
	check(packet.runtime.notice.contains("返回") and not packet.runtime.notice.contains("赶往火场"),"return receipt describes returning rather than approaching the fire")
	runtime.dispose()
	print("FIRE_SKIRMISH_RETURN_NOTICE_TEST_COMPLETE checks=",checks," failures=",failures)
	quit(1 if failures else 0)
