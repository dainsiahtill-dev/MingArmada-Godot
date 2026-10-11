extends SceneTree
var assertions := 0
var failures := 0
func check(value: bool,detail: String) -> void:
	assertions += 1
	if not value: failures += 1; printerr("FAIL: ",detail)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var path := "res://game/runtime/naval_practice_runtime.gd"
	check(ResourceLoader.exists(path),"standalone naval practice has an actual native runtime")
	if ResourceLoader.exists(path):
		var script = load(path)
		for mode in ["duel","fleet","sail"]:
			var runtime = script.new()
			check(runtime.configure(func(_x,_z): return -50.0,{"mode":mode}).ok,"native mode starts: "+mode)
			var first: Dictionary = runtime.snapshot(); var native: Dictionary = first.naval
			check(native.ships.size() == (2 if mode=="duel" else 3),"exact source fleet count: "+mode)
			check(native.wind == {"direction":{"x":-0.8,"y":-0.6},"speed":14.0},"source wind retained")
			if mode=="sail": check(native.ships.filter(func(s): return s.team=="hostile").is_empty(),"free sailing has real neutral traffic and no enemies")
			runtime.set_held("KeyW",true); runtime.set_held("KeyD",true)
			for tick in 90: runtime.advance(1.0/60)
			check(runtime.snapshot().naval.tick == 90,"one accepted 60Hz authority clock")
			check(runtime.snapshot().naval.ships[0].visual.position != native.ships[0].visual.position,"actual ship dynamics moves under held inputs")
			runtime.set_pause("player",true); var paused: Dictionary=runtime.snapshot()
			check(runtime.advance(60)==0 and runtime.snapshot().naval==paused.naval,"pause freezes authoritative ships, waves and projectiles")
			check(not runtime.command({"type":"fire","side":"port"}).ok,"paused UI cannot queue cannon attacks")
			runtime.set_pause("player",false)
			check(not runtime.simulation.has_pending_input(),"pause clears held controls and deferred attacks")
			check(runtime.command({"type":"select-ammo","ammo":"grape"}).ok,"ammunition UI goes through real simulation")
			runtime.advance(1.0/60)
			check(runtime.snapshot().naval.ships[0].ammoType=="grape","selected ammunition changes actual cannon state")
			if mode!="sail":
				check(runtime.command({"type":"begin-surrender"}).ok,"active encounter produces actual surrender quote")
				var quote: Dictionary=runtime.snapshot().runtime.surrenderQuote
				check(not quote.is_empty() and runtime.is_paused(),"quote pauses actual sea without advancing its token")
				check(not runtime.command({"type":"confirm-surrender","request":{"battleId":"stale"}}).ok,"stale confirmation cannot surrender")
				check(runtime.command({"type":"cancel-surrender"}).ok and not runtime.is_paused(),"cancel resumes encounter")
				runtime.command({"type":"begin-surrender"}); quote=runtime.snapshot().runtime.surrenderQuote
				check(runtime.command({"type":"confirm-surrender","request":quote.request}).ok,"token-fenced surrender reaches canonical authority")
				check(runtime.snapshot().naval.status=="surrendered","surrender has actual terminal outcome")
			else: check(not runtime.command({"type":"begin-surrender"}).ok,"free sailing cannot surrender to neutral traffic")
			var old_id: String=runtime.snapshot().naval.battleId
			runtime.set_pause("blur",true)
			check(runtime.command({"type":"restart"}).ok,"practice restarts without career rewards or disk saves")
			check(runtime.snapshot().naval.tick==0 and runtime.snapshot().naval.battleId!=old_id and not runtime.is_paused(),"restart replaces authority and invalidates old battle identity")
			var detached: Dictionary=runtime.snapshot(); detached.naval.ships.clear()
			check(not runtime.snapshot().naval.ships.is_empty(),"HUD snapshots detached from rules")
			runtime.dispose(); check(runtime.advance(1)==0,"disposed practice cannot advance")
		var invalid = script.new()
		check(not invalid.configure(func(_x,_z): return -50.0,{"mode":"career"}).ok,"practice refuses career mode")
	print("NAVAL_PRACTICE_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
