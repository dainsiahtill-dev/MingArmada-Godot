extends SceneTree
## Production clock and actual Effects, with a terminal packet unit fixture.
## Do not simulate combat outcomes or claim this as a real cannon impact.
const Clock = preload("res://game/scenes/common/terminal_presentation_clock.gd")
const Effects = preload("res://game/presentation/combat/combat_effects.gd")
var assertions := 0
var failures := 0
func check(value: bool, detail: String) -> void:
	assertions += 1
	if not value: failures += 1; printerr("FAIL: ",detail)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var effects := Effects.new(); root.add_child(effects)
	effects.set_water_sampler(func(_x,_z,_time): return 0.0)
	var native := {"battleId":"residual-a","time":10.0,"status":"active","ships":[{"id":"player","hull":0.0}],"projectiles":[{"id":"remaining-shot","position":{"x":1.0,"y":2.0,"z":3.0},"velocity":{"x":5.0,"y":2.0,"z":0.0}}]}
	effects.apply_snapshot(native,0.0)
	check(effects.diagnostics().projectiles==1,"active snapshot draws the actual projectile mesh")
	native.status="defeat"
	var authority := native.duplicate(true)
	var clock := Clock.new(); clock.advance(native,["result"],0.05,0.05)
	effects.apply_snapshot(clock.snapshot(native),0.0)
	check(effects.diagnostics().projectiles==0,"settled result retires projectile meshes while frozen native shots remain authoritative")
	for unused in 138:
		var accepted := clock.advance(native,["result"],0.05)
		effects.apply_snapshot(clock.snapshot(native),accepted)
	var birth: float = clock.snapshot(native).time
	effects.apply_events([{"type":"splash","id":"late-crew-entry","time":birth,"position":{"x":0.0,"y":0.0,"z":0.0},"scale":0.45}])
	check(effects.diagnostics().splashes==1,"late crew entry at 6.9 seconds builds real water geometry")
	for unused in 23:
		var accepted := clock.advance(native,["result"],0.05)
		effects.apply_snapshot(clock.snapshot(native),accepted)
	check(clock.is_playing() and effects.diagnostics().splashes==1,"tail remains active after eight seconds so a late water splash can fade naturally")
	for unused in 50:
		var accepted := clock.advance(native,["result"],0.05)
		effects.apply_snapshot(clock.snapshot(native),accepted)
	check(not clock.is_playing() and effects.diagnostics().splashes==0,"finite presentation ends after the seven-second body plus its 2.8-second water effect")
	effects.apply_snapshot(clock.snapshot(native),0.0)
	check(effects.diagnostics().projectiles==0 and effects.diagnostics().splashes==0,"completed result does not recreate frozen shots or late water geometry")
	check(native==authority,"residual cleanup preserves every native projectile and terminal authority field")
	effects.free()
	print("TERMINAL_RESIDUAL_EFFECTS_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
