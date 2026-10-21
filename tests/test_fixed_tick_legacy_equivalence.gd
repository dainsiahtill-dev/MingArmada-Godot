extends SceneTree
## Frozen pre-refactor input/accumulator oracle, not a second copy of the new adapter.
const Simulation=preload("res://game/runtime/sailing_simulation.gd")
const Encounter=preload("res://modules/naval_simulation/encounter.gd")
const BASE="res://docs/research/evidence/architecture-convergence-2026-10-21/baseline/"
var assertions:=0
var failures:=0
func check(ok:bool,message:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL tick oracle: ",message)
func _initialize()->void:
	var file:=BASE+"source/game/runtime/sailing_simulation.gd.txt"
	var hashes:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(BASE+"SOURCE_HASHES.json"))
	check(FileAccess.get_sha256(file)==hashes["game/runtime/sailing_simulation.gd"],"frozen legacy source matches pre-edit receipt")
	var legacy:=GDScript.new();legacy.source_code=FileAccess.get_file_as_string(file)
	check(legacy.reload()==OK,"frozen legacy adapter compiles independently")
	if failures:finish();return
	for mode in ["realistic","assisted"]:
		var options:={"seed":1661,"enemyCount":2,"referenceHandling":true,"referenceGunnery":true}
		var a:=Simulation.new(Encounter.new(options))
		var b:RefCounted=legacy.new(Encounter.new(options))
		a.set_handling_mode(mode);b.set_handling_mode(mode)
		for frame in 360:
			if frame%60==0:
				for adapter:RefCounted in [a,b]:
					adapter.set_held("KeyW",true)
					adapter.set_held("KeyD",frame%120==0)
			if frame==120:
				for adapter:RefCounted in [a,b]:adapter.action({"type":"fire","side":"starboard","ammo":"round"})
			if frame==180:
				for adapter:RefCounted in [a,b]:adapter.set_paused(true)
			if frame==192:
				for adapter:RefCounted in [a,b]:adapter.set_paused(false)
			var dt:float=[0.0,1.0/120.0,1.0/30.0,0.3,1.0/60.0][frame%5]
			a.advance(dt);b.advance(dt)
			check(a.snapshot()==b.snapshot(),"full native states preserve original variable-frame semantics %s/%d"%[mode,frame])
			check(a.render_snapshot()==b.render_snapshot(),"interpolation preserves original residual budget %s/%d"%[mode,frame])
			check(a.drain_events()==b.drain_events() and a.drain_results()==b.drain_results(),"input/results/events preserve original order %s/%d"%[mode,frame])
	finish()
func finish()->void:
	print("FIXED_TICK_LEGACY_EQUIVALENCE_TESTS assertions=",assertions," failures=",failures);quit(1 if failures else 0)
