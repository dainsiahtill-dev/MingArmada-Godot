extends SceneTree
## Public combat events must drive imported source particles, using accepted time.
const Effects = preload("res://game/presentation/combat/combat_effects.gd")
var assertions := 0
var failures := 0
func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ", detail)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var effects := Effects.new(); root.add_child(effects)
	effects.position = Vector3(90, 0, 120)
	effects.set_water_sampler(func(_x, _z, _t): return 0.0)
	effects.apply_snapshot({"time":10.06,"projectiles":[]},0.0)
	var event := {"type":"fire","id":"native-fire","projectileId":"shot","time":10.0,"position":{"x":3.0,"y":2.0,"z":4.0},"velocity":{"x":25.0,"y":0.0,"z":0.0}}
	effects.apply_events([event, event])
	var first: Dictionary = effects.diagnostics()
	check(first.get("source_fire",0) == 1,"one actual fire event creates one imported source replay, duplicates ignored")
	check(first.get("source_particles",0) > 0,"authored eleven-layer cannon flash and smoke are present at accepted age 0.06")
	check(first.get("puffs",-1) == 0,"normal cannon fire uses textured source particles")
	effects.apply_snapshot({"time":10.06,"projectiles":[]},1.0)
	check(effects.diagnostics().get("source_particles",0) == first.get("source_particles",-1),"wall delta cannot advance paused source particles")
	effects.apply_snapshot({"time":20.0,"projectiles":[]},0.0)
	check(effects.diagnostics().get("source_fire",-1) == 0,"finite cannon effect releases all owned mesh nodes")
	effects.apply_events([event])
	check(effects.diagnostics().get("source_fire",-1) == 0,"expired late event cannot resurrect cannon smoke")
	effects.apply_snapshot({"time":9.0,"projectiles":[]},0.0)
	check(effects.diagnostics().events == 0,"rewind clears native effect and event history together")
	effects.dispose(); effects.dispose(); effects.free()
	print("FIDELITY_FX_PRESENTATION_TESTS assertions=%d failures=%d" % [assertions,failures])
	quit(1 if failures else 0)
