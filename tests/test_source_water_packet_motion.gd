extends SceneTree
## Real ship model -> production packet -> native history, with target pose changes.
const Ship=preload("res://game/presentation/ships/ship_view.gd")
const Packet=preload("res://game/presentation/world/source_water_packet.gd")
const History=preload("res://modules/scene_engine/water/source_wake_history.gd")
var assertions:=0
var failures:=0
func check(ok:bool,message:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL: ",message)
func _initialize()->void:_run.call_deferred()
func _ship(time:float,x:float,y:float,z:float,pitch:float,heel:float,heading:float=0.0)->Dictionary:
	return {"id":"player","kind":"fuchuan","time":time,"hull":100.0,"sailDeployment":0.0,"visual":{"position":{"x":x,"y":y,"z":z},"velocity":{"x":0.0,"z":0.0},"heading":heading,"pitch":pitch,"heel":heel}}
func _packet(view:Node3D,ship:Dictionary,call_index:int)->Dictionary:
	view.apply_snapshot(ship,{},0.0)
	return Packet.compose({"time":ship.time,"environment":{"route":"sailing","acceptedTime":ship.time,"sourceCallIndex":call_index},"ships":[ship]},{"player":view},null).ships[0].sourceWake
func _run()->void:
	var actor:=Ship.new();root.add_child(actor);check(actor.configure("fuchuan"),"actual source ship configures")
	var first:=_packet(actor,_ship(0.0,20.0,0.0,10.0,0.0,0.0),0)
	var history:=History.new({},first.modelScale,first.markerId,first.sourcePosition)
	check(history.update(first.sourcePosition,first.sourceClock,first.markerId),"first actual marker sample is accepted")
	var reference:Vector3=Vector3(first.sourcePosition[0],first.sourcePosition[1],first.sourcePosition[2])
	var raw_motion:=false
	for i in range(1,25):
		var time:=float(i)*0.1
		var packet:=_packet(actor,_ship(time,20.0,sin(time*2.0)*2.0,10.0,sin(time)*0.25,cos(time)*0.4),i)
		var p:=Vector3(packet.sourcePosition[0],packet.sourcePosition[1],packet.sourcePosition[2])
		check(p.distance_to(reference)<0.00001,"stationary planar travel marker ignores displayed heave/pitch/heel")
		history.update(packet.sourcePosition,packet.sourceClock,packet.markerId)
		check(history.updates==1,"displayed floating does not create sailing history samples")
		check(packet.froth.has("sourcePosition"),"froth retains explicit full-pose raw wake marker")
		if packet.froth.has("sourcePosition"):
			var raw:Vector3=Vector3(packet.froth.sourcePosition[0],packet.froth.sourcePosition[1],packet.froth.sourcePosition[2])
			raw_motion=raw_motion or raw.distance_to(reference)>1.0
	check(raw_motion,"froth raw marker still moves with the actual displayed model")
	var moving:=_packet(actor,_ship(2.5,21.0,1.0,10.0,0.2,0.3),25)
	check(history.update(moving.sourcePosition,moving.sourceClock,moving.markerId),"real horizontal movement still crosses original sampling distance gate")
	check(history.updates==2,"real movement adds exactly one sailing sample")
	var turning:=_packet(actor,_ship(2.6,21.0,1.0,10.0,0.2,0.3,PI/2.0),26)
	check(history.update(turning.sourcePosition,turning.sourceClock,turning.markerId),"actual source marker retains yaw turning around the ship")
	check(history.updates==3,"yaw movement remains a native distance-gated sample")
	var battle_ship:=_ship(2.7,21.0,2.0,10.0,0.25,0.3,PI/2.0)
	actor.apply_snapshot(battle_ship,{},0.0)
	var attachment:Dictionary=actor.source_water_attachment()
	var battle:Dictionary=Packet.compose({"time":2.7,"environment":{"route":"battle","acceptedTime":2.7,"sourceCallIndex":27},"ships":[battle_ship]},{"player":actor},null).ships[0].sourceWake
	var raw:Array=Packet.native_vector(attachment.wake/attachment.sourceToWorld)
	check(battle.sourcePosition==raw,"battle 90 route keeps original raw marker input")
	check(battle.froth.sourcePosition==raw,"local froth keeps raw full-pose marker independently of trail")
	check(battle.froth.sourceBowPosition==Packet.native_vector(attachment.bow/attachment.sourceToWorld),"authored bow attachment still follows actual heave and hull rotation")
	check(battle.sourceRotation==Packet.native_rotation(attachment.rotation),"froth source rotation retains full displayed model pose")
	actor.dispose();actor.free()
	print("SOURCE_WATER_PACKET_MOTION_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
