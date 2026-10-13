extends SceneTree
## Authority owns source weather; display reads must never add source calls.
const Encounter=preload("res://modules/naval_simulation/encounter.gd")
const Sailing=preload("res://game/runtime/sailing_runtime.gd")
const Practice=preload("res://game/runtime/naval_practice_runtime.gd")
var assertions:=0
var failures:=0
func check(ok:bool,detail:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL source environment integration: ",detail)
func _initialize()->void:_run.call_deferred()
func _run()->void:
	var encounter:=Encounter.new({"mode":"continuous","enemyCount":0,"environmentRoute":"sailing"})
	var initial:Dictionary=encounter.snapshot()
	check(initial.has("environment"),"formal encounter exposes engine environment")
	if initial.has("environment"):
		var original:Dictionary=initial.environment.duplicate(true)
		check(original.route=="sailing" and original.acceptedTime==0.0,"explicit sailing route begins at accepted zero")
		for i in 6:encounter.snapshot()
		check(encounter.snapshot().environment==original,"snapshot reads do not consume weather RNG or calls")
		initial.environment.worldClouds[0].worldPosition[0]=123456.0
		check(encounter.snapshot().environment==original,"environment packet is detached from caller edits")
		var wind:Dictionary=encounter.wind.duplicate(true)
		encounter.step(0.1)
		var advanced:Dictionary=encounter.snapshot()
		check(is_equal_approx(advanced.environment.acceptedTime,advanced.time) and advanced.environment.sourceCallIndex==3,"source cadence follows accepted fixed ticks")
		check(encounter.wind==wind,"independent source weather never changes handling wind")
		var retained:Dictionary=advanced.environment.duplicate(true)
		encounter.command({"type":"fire","side":"port"})
		check(encounter.snapshot().environment==retained,"instant cannon command does not advance weather")
		check(not encounter.reset({"environmentRoute":"bad"}) and encounter.snapshot().environment==retained,"invalid route preserves running weather atomically")
		check(not encounter.reset({"environmentOptions":{"source_calls_per_second":0}}) and encounter.snapshot().environment==retained,"invalid weather options preserve running encounter")
		check(encounter.reset({"mode":"terminal","environmentRoute":"battle","enemyCount":1}),"battle restart succeeds")
		var reset:Dictionary=encounter.snapshot().environment
		check(reset.route=="battle" and reset.epoch>retained.epoch and reset.acceptedTime==0.0 and reset.sourceCallIndex==0,"restart replaces epoch and source journal")
	var trial:=Sailing.new()
	check(trial.configure(func(_x:float,_z:float):return -100.0),"standalone trial configures")
	var startup:Dictionary=trial.snapshot()
	check(startup.has("environment"),"ordinary sailing trial exposes the same engine packet")
	if startup.has("environment"):
		check(startup.environment.route=="sailing","trial selects source sailing route")
		var consumed:=trial.advance(0.25)
		var active:Dictionary=trial.snapshot()
		check(is_equal_approx(active.environment.acceptedTime,active.time) and is_equal_approx(consumed,0.25),"trial environment consumes authoritative physics time")
		trial.command({"type":"pause","value":true})
		var paused:Dictionary=trial.snapshot().environment
		check(trial.advance(0.25)==0.0 and trial.snapshot().environment==paused,"pause preserves complete weather state")
	var practice:=Practice.new()
	check(practice.configure(func(_x:float,_z:float):return -100.0,{"mode":"sail"}).ok,"free sailing entrance configures")
	var free:Dictionary=practice.snapshot().naval
	check(free.has("environment") and free.get("environment",{}).get("route")=="sailing","free sailing chooses sea navigation despite terminal encounter policy")
	check(practice.configure(func(_x:float,_z:float):return -100.0,{"mode":"duel"}).ok,"cannon duel entrance configures")
	var duel:Dictionary=practice.snapshot().naval
	check(duel.has("environment") and duel.get("environment",{}).get("route")=="battle","duel chooses battle source route")
	practice.dispose()
	print("SOURCE_ENVIRONMENT_INTEGRATION_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
