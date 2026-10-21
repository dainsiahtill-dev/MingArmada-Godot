extends SceneTree
const Encounter=preload("res://modules/naval_simulation/encounter.gd")
const Simulation=preload("res://game/runtime/sailing_simulation.gd")
var assertions:=0
var failures:=0
func check(ok:bool,message:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL fixed tick: ",message)
func _initialize()->void:
	var first:=Encounter.new({"seed":1661,"enemyCount":1})
	check(first.has_method("step_fixed"),"naval authority exposes accumulator-free fixed tick")
	var a:=Simulation.new(first)
	check(a.has_method("advance_fixed"),"input adapter accepts an already budgeted fixed tick")
	check(a.has_method("current_tick") and a.has_method("current_time") and a.has_method("current_status"),"primitive reads avoid detached world snapshots")
	if failures:finish();return
	var b:=Simulation.new(Encounter.new({"seed":1661,"enemyCount":1}))
	a.set_handling_mode("assisted");b.set_handling_mode("assisted")
	a.set_held("KeyW",true);b.set_held("KeyW",true)
	for tick in 180:
		if tick==60:a.set_held("KeyD",true);b.set_held("KeyD",true)
		if tick==100:a.set_held("KeyD",false);b.set_held("KeyD",false)
		if tick==120:
			var fire:={"type":"fire","side":"starboard","ammo":"round"}
			a.action(fire);b.action(fire)
		a.advance_fixed();b.advance(1.0/60.0)
		check(a.snapshot()==b.snapshot(),"single tick and frame adapter states match %d"%tick)
		check(a.drain_events()==b.drain_events() and a.drain_results()==b.drain_results(),"single tick retains input/event order %d"%tick)
		check(a.current_tick()==tick+1 and a.current_time()==(tick+1)*Simulation.STEP and a.current_status()==a.snapshot().status,"primitive reads reflect authority %d"%tick)
	check(first.accumulator==0.0 and a._accumulator==0.0,"budgeted tick chain never accumulates frame time")
	var detached:Dictionary=a.snapshot();detached.ships[0].visual.position.x=100000.0
	check(a.snapshot()!=detached,"public snapshots remain detached")
	var before:=a.snapshot();a.set_paused(true);a.advance_fixed()
	check(a.snapshot()==before,"paused single tick cannot advance")
	a.set_paused(false);a.advance(1.0/120.0)
	check(a.current_tick()==180,"frame adapter retains half tick")
	a.advance(1.0/120.0);check(a.current_tick()==181,"second half tick advances exactly once")
	finish()
func finish()->void:
	print("FIXED_TICK_CONTRACT_TESTS assertions=",assertions," failures=",failures);quit(1 if failures else 0)
