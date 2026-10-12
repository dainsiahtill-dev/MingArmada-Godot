extends SceneTree
## The oracle is an actual ShipView presented every accepted tick; the deferred
## path must retain its fire poses without touching any displayed node/animation.
const Ship=preload("res://game/presentation/ships/ship_view.gd")
const Sea=preload("res://game/presentation/world/naval_world_view.gd")
const Encounter=preload("res://modules/naval_simulation/encounter.gd")
const Library=preload("res://modules/scene_engine/assets/asset_library.gd")
class ObservedShip extends Ship:
	var full_calls:=0
	func apply_snapshot(ship:Dictionary,wind:Dictionary={},consumed:float=0.0)->void:
		full_calls+=1;super.apply_snapshot(ship,wind,consumed)
class Probe extends Node3D:
	var calls:=0
	var impact_steps:=0
	var last_frame:=Transform3D.IDENTITY
	func advance_impacts(_phase:float,_consumed:float,frame:Transform3D)->void:impact_steps+=1;last_frame=frame
	func apply_snapshot(_snapshot:Dictionary,_wind_or_consumed:Variant=null,_consumed:float=0.0)->void:calls+=1
	func apply_events(_events:Array)->void:calls+=1
	func presentation_events(events:Array)->Array:return events.duplicate(true)
	func set_ship_model(_model:Node3D)->void:calls+=1
	func set_lod_distance(_distance:float)->void:calls+=1
	func set_allocation(_allocation:int)->void:calls+=1
	func dispose()->void:pass
class ObservedSea extends Sea:
	# Only replace expensive effects reset in this narrow CPU contract. The real
		# Sea apply_snapshot still owns epoch reset, view creation and fire bridge.
	func _reset_fleet()->void:
		for id:String in ships.keys():_release_ship(id)
var assertions:=0
var failures:=0
func check(value:bool,reason:String)->void:
	assertions+=1
	if not value:failures+=1;printerr("FAIL deferred ship birth pose: ",reason)
func wire(value:Vector3)->Dictionary:return {"x":value.x,"y":value.y,"z":value.z}
func point(value:Dictionary)->Vector3:return Vector3(value.x,value.y,value.z)
func _initialize()->void:_run.call_deferred()
func _finish()->void:
	print("DEFERRED_SHIP_BIRTH_POSE_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
func _sample(base:Dictionary,time:float,index:int)->Dictionary:
	var ship:=base.duplicate(true);ship.time=time
	ship.visual.position={"x":float(index*index)+3.0,"y":float(index)*.2,"z":-float(index)*2.1}
	ship.visual.heading=float(index)*.11;ship.visual.pitch=float(index)*.017;ship.visual.heel=-float(index)*.023
	ship.sailAngle=float(index)*.02;ship.sailDeployment=.5
	return ship
func _event(view:Node3D,time:float,id:String)->Dictionary:
	var socket:Node3D=view.get("_models")[0].find_children("socket_smoke_starboard_*","Node3D",true,false)[0]
	return {"type":"fire","id":id,"time":time,"shipId":"player","side":"starboard","position":wire(socket.global_position),"velocity":{"x":0.0,"y":0.0,"z":20.0}}
func _run()->void:
	var eager:=ObservedShip.new();var delayed:=ObservedShip.new();var sea:=ObservedSea.new()
	check(delayed.has_method("remember_authoritative_pose"),"ShipView provides the pure accepted-pose recorder")
	check(sea.has_method("remember_authoritative_poses"),"Sea forwards accepted physics poses without presenting")
	if not delayed.has_method("remember_authoritative_pose") or not sea.has_method("remember_authoritative_poses"):
		eager.free();delayed.free();sea.free();_finish();return
	var native:=Encounter.new({"referenceHandling":true,"referenceGunnery":true,"ships":[{"id":"player","kind":"fuchuan","team":"player","position":{"x":0.0,"z":0.0},"sailDeployment":0.0}],"wind":{"direction":{"x":1.0,"y":0.0},"speed":0.0},"oceanWaves":[],"sampleTerrainHeight":func(_x:float,_z:float)->float:return -80.0}).snapshot()
	native.battleId="deferred-A";native.ships[0].crew=0
	var library:=Library.new();var host:=Node3D.new();root.add_child(host);root.add_child(sea)
	var parent_pose:=Transform3D(Basis.from_euler(Vector3(.17,-.31,.23)).scaled_local(Vector3(1.2,.9,1.1)),Vector3(12,4,-9))
	host.transform=parent_pose;sea.transform=parent_pose
	host.add_child(eager);sea.add_child(delayed)
	check(eager.configure("fuchuan",library) and delayed.configure("fuchuan",library),"actual original model loads in both presentation paths")
	if eager.get_model()==null or delayed.get_model()==null:
		eager.dispose();host.free();sea.free();library.dispose();_finish();return
	var authored_root:Transform3D=eager.get("_models")[0].transform
	for view:Node3D in [eager,delayed]:
		view.scale=Vector3(.9,1.2,1.05)
		var model:Node3D=view.get("_models")[0]
		model.transform=Transform3D(Basis.from_euler(Vector3(.04,.13,-.08)).scaled_local(Vector3(.96,1.04,.98)),Vector3(.3,.7,-.2))
		view.get("_damage").configure(view.get("_models"))
		var initial:Dictionary=native.ships[0].duplicate(true);initial.time=0.0;view.apply_snapshot(initial,native.wind,0.0)
	sea.set("_disposed",false);sea.set("_battle_id","deferred-A")
	sea.library=library;sea.ships.player=delayed;sea.get("_kinds").player="fuchuan"
	var crew:=Probe.new();delayed.add_child(crew);sea.sailors.player=crew
	var world:=Probe.new();var effects:=Probe.new();var wakes:=Probe.new()
	sea.add_child(world);sea.add_child(effects);sea.add_child(wakes);sea.world=world;sea.effects=effects;sea.wakes=wakes
	var camera:=Camera3D.new();sea.add_child(camera);sea.camera=camera
	var displayed:=delayed.global_transform;var model_displayed:Transform3D=delayed.get_model().transform
	var damage_before:Dictionary=delayed.damage_diagnostics();var calls_before:=delayed.full_calls
	var shots:Array=[];var expected:Array=[];var last:Dictionary={}
	for i in range(1,9):
		var time:=float(i)/60.0;var ship:=_sample(native.ships[0],time,i)
		eager.apply_snapshot(ship,native.wind,1.0/60.0)
		var event:=_event(eager,time,"deferred-shot-"+str(i));shots.append(event);expected.append(eager.source_fire_position(event))
		last=native.duplicate(true);last.time=time;last.ships=[ship]
		var input:=last.duplicate(true);sea.remember_authoritative_poses(last,1.0/60.0)
		var pose:Variant=delayed.call("_source_pose_at",time)
		check(pose is Transform3D and pose.is_equal_approx(eager.get("_models")[0].global_transform),"accepted tick "+str(i)+" matches actual Node3D Euler/scale/parent/model-root pose")
		check(crew.last_frame.is_equal_approx(eager.get("_models")[0].global_transform),"crew Jolt step gets this tick's authoritative model frame")
		check(last==input,"pose capture leaves authoritative input immutable")
	check(delayed.full_calls==calls_before and delayed.global_transform==displayed and delayed.get_model().transform==model_displayed,"eight accepted ticks do not move nodes or run full ShipView presentation")
	check(delayed.damage_diagnostics()==damage_before and world.calls==0 and effects.calls==0 and wakes.calls==0 and crew.calls==0,"pose-only ticks do not touch damage/crew/world/effects/wakes")
	check(crew.impact_steps==8,"accepted physics retains eight individual crew impact steps")
	var presented:Array=sea.apply_snapshot(last,shots,8.0/60.0)
	check(presented.size()==shots.size(),"one deferred render presents every accumulated fire")
	for i in mini(presented.size(),shots.size()):
		check(presented[i].has("source_muzzle_position") and point(presented[i].source_muzzle_position).distance_to(expected[i])<.001,"deferred fire "+str(i)+" stays at its original per-tick source mouth")
		check(not shots[i].has("source_muzzle_position"),"fire bridge never edits the native event")
	var replacement:=_sample(native.ships[0],float(last.time),12);eager.apply_snapshot(replacement,native.wind,0.0)
	var current:=_event(eager,float(last.time),"same-time-replacement")
	sea.remember_authoritative_poses({"battleId":"deferred-A","time":last.time,"ships":[replacement]})
	check(delayed.source_fire_position(current).distance_to(eager.source_fire_position(current))<.001,"same accepted time replaces the remembered pose")
	var history_count:int=delayed.get("_source_poses").size()
	sea.remember_authoritative_poses({"battleId":"deferred-A","time":NAN,"ships":[replacement]})
	check(delayed.get("_source_poses").size()==history_count,"invalid time cannot poison accepted history")
	var rewind:=_sample(native.ships[0],.01,-2)
	sea.remember_authoritative_poses({"battleId":"deferred-A","time":.01,"ships":[rewind]})
	check(delayed.source_fire_position(current)==null and delayed.source_fire_position(shots[0])==null,"remembered rewind clears future history before the next render")
	# Actual old-epoch sinking changes the root. A new healthy epoch must not
	# sample those damaged actors before reset; earlier shots use native fallback.
	var sinking:Dictionary=native.ships[0].duplicate(true);sinking.hull=0.0;sinking.time=1.0
	delayed.apply_snapshot(sinking,native.wind,0.0)
	sinking.time=2.0;delayed.apply_snapshot(sinking,native.wind,0.0)
	check(delayed.get("_models")[0].position.y<model_displayed.origin.y-.01,"actual original sinking animation supplies a displaced old model root")
	eager.scale=Vector3.ONE;eager.get("_models")[0].transform=authored_root;eager.get("_damage").configure(eager.get("_models"))
	var fresh_shots:Array=[];var fresh_expected:Array=[];var fresh:Dictionary={}
	for i in range(1,4):
		var ship:=_sample(native.ships[0],float(i)/60.0,20+i);eager.apply_snapshot(ship,native.wind,0.0)
		var event:=_event(eager,float(i)/60.0,"fresh-shot-"+str(i))
		fresh_shots.append(event);fresh_expected.append(eager.source_fire_position(event))
		fresh=native.duplicate(true);fresh.battleId="deferred-B";fresh.time=float(i)/60.0;fresh.ships=[ship]
		sea.remember_authoritative_poses(fresh)
	check(delayed.get("_source_poses").is_empty(),"new epoch clears old sinking history and never records unready old actors")
	presented=sea.apply_snapshot(fresh,fresh_shots,3.0/60.0)
	for i in mini(presented.size(),fresh_shots.size()):
		if i<fresh_shots.size()-1:check(not presented[i].has("source_muzzle_position") and presented[i].position==fresh_shots[i].position,"unobserved earlier new-epoch fire honestly uses its native mouth")
		else:check(presented[i].has("source_muzzle_position") and point(presented[i].source_muzzle_position).distance_to(fresh_expected[i])<.001,"current new-epoch fire uses the recreated healthy original source mouth")
	var active:Node3D=sea.ships.player
	var count:int=active.get("_source_poses").size()
	sea.remember_authoritative_poses({"battleId":"deferred-B","time":.2,"ships":[{"id":"unknown","kind":"fuchuan","visual":replacement.visual}]})
	check(sea.ships.size()==1 and active.get("_source_poses").size()==count,"unknown ship IDs cannot instantiate actors or write another ship's history")
	active.dispose();check(active.call("_source_pose_at",fresh.time)==null,"dispose releases accepted pose history")
	eager.dispose();host.free();sea.dispose();sea.free();library.dispose();_finish()
