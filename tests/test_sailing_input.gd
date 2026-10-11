extends SceneTree
const Runtime = preload("res://game/runtime/mingqi_runtime.gd")
const Interface = preload("res://game/ui/mingqi/mingqi_interface.gd")
var assertions := 0
var failures := 0
func check(ok: bool,detail: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ",detail)
func make_runtime() -> RefCounted:
	var r := Runtime.new(); r.configure(func(_x: float,_z: float)->float: return -24.0)
	r.command({"type":"accept-convoy","commandId":"input-accept","expectedRevision":r.snapshot().campaign.revision})
	return r
func player(r: RefCounted) -> Dictionary: return Runtime._ship(r.simulation.encounter.snapshot(),r.simulation.snapshot().playerId)
func navigate(r: RefCounted) -> void:
	r.simulation.encounter.command({"type":"controls","rudder":0.0,"sailDeployment":0.4,"autoTrim":true})
	r.simulation.refresh_snapshot()
	r.simulation.encounter.navigate(r.simulation.snapshot().playerId,{"x":300.0,"z":0.0})
	r.simulation.refresh_snapshot()
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var r := make_runtime(); navigate(r)
	r.simulation.action({"type":"controls","rudder":NAN,"sailDeployment":0.4})
	check(player(r).has("navigation"),"invalid controls do not cancel current navigation before validation")
	r.simulation.set_paused(true); r.simulation.set_paused(false); navigate(r)
	r.simulation.action({"type":"controls","rudder":0.0,"sailDeployment":0.4,"autoTrim":true})
	check(player(r).has("navigation"),"unchanged valid controls retain waypoint")
	r.simulation.set_paused(true); r.simulation.set_paused(false); navigate(r)
	r.simulation.action({"type":"controls","shipId":r.snapshot().campaign.campaignId+"-fast","rudder":0.2,"sailDeployment":0.5})
	check(player(r).has("navigation"),"another ship's controls retain player's waypoint")
	r.simulation.set_paused(true); r.simulation.set_paused(false); navigate(r)
	r.simulation.set_sails(0.8); r.simulation.advance(1.0/60)
	check(absf(player(r).sailDeployment-0.8)<1e-12,"sail change reaches first tick after navigation cancellation")
	navigate(r); r.simulation.toggle_trim(); r.simulation.advance(1.0/60)
	check(not player(r).autoTrim,"manual trim reaches first tick after navigation cancellation")
	r.dispose()
	r = Runtime.new(); r.configure(func(_x: float,_z: float)->float: return -24.0)
	r.set_held("KeyW",true)
	check(r.simulation.has_pending_input() and not r.check_safety().ok,"held unconsumed input blocks save safety")
	r.set_held("KeyW",false)
	check(not r.simulation.has_pending_input(),"released input clears pending fence without consumption")
	r.set_pause("player",true); check(not r.simulation.has_pending_input(),"pause clears input fence")
	r.dispose()
	for reason in ["loading","error","result"]:
		r = Runtime.new(); r.configure(func(_x: float,_z: float)->float: return -24.0); r.set_pause(reason,true)
		var before: Dictionary = r.snapshot().campaign
		check(not r.command({"type":"accept-convoy","commandId":"blocked-accept","expectedRevision":before.revision}).ok and r.snapshot().campaign == before,"hard stage rejects business: "+reason)
		if reason != "result": check(not r.draft_order({"type":"assign-order","commandId":"blocked-draft","expectedRevision":before.revision}).ok,"hard stage rejects draft: "+reason)
		r.dispose()
	r = make_runtime(); r._fail("input-test-error")
	check(not r.export_save("2026-10-11T00:00:00.000Z").ok,"error runtime rejects export")
	r.dispose(); check(not r.export_save("2026-10-11T00:00:00.000Z").ok,"disposed runtime rejects export explicitly")
	for button_name in ["ship_auto_trim","ammo_chain","ship_fire_port"]:
		r = make_runtime()
		var ui := Interface.new(); root.add_child(ui); ui.apply_snapshot(r.snapshot()); ui.open_panel("ship")
		var responses: Array = []
		ui.command_requested.connect(func(command: Dictionary): responses.append(r.command(command)))
		ui.find_child(button_name,true,false).emit_signal("pressed")
		check(responses.size() == 1 and responses[0].ok,"actual HUD intent is adapted: "+button_name)
		check(r.simulation.has_pending_input(),"HUD intent queues until native tick: "+button_name)
		r.advance(1.0/60)
		var ship := player(r)
		check(not ship.autoTrim if button_name == "ship_auto_trim" else ship.ammoType == "chain" if button_name == "ammo_chain" else ship.ammo.solid == 39,"HUD intent changes actual engine: "+button_name)
		ui.queue_free(); r.dispose(); await process_frame
	for second in ["ship_auto_trim","ship_rudder"]:
		r = make_runtime()
		var ui := Interface.new(); root.add_child(ui); ui.apply_snapshot(r.snapshot()); ui.open_panel("ship")
		ui.command_requested.connect(func(command: Dictionary): r.command(command))
		ui.find_child("ship_sail",true,false).value = 0.8
		if second == "ship_auto_trim": ui.find_child(second,true,false).emit_signal("pressed")
		else: ui.find_child(second,true,false).value = 0.6
		r.advance(1.0/60)
		check(absf(player(r).sailDeployment-0.8)<1e-12,"same tick partial controls preserve sails: "+second)
		check(not player(r).autoTrim if second == "ship_auto_trim" else absf(player(r).rudder-0.6)<1e-12,"same tick partial controls preserve second intent: "+second)
		ui.queue_free(); r.dispose(); await process_frame
	r = make_runtime()
	r.command({"type":"controls","sailDeployment":0.8})
	r.set_pause("player",true); r.set_pause("player",false)
	r.command({"type":"controls","autoTrim":false}); r.advance(1.0/60)
	check(player(r).sailDeployment == 0 and not player(r).autoTrim,"pause discards unconsumed partial controls without stale merge")
	r.dispose()
	print("SAILING_INPUT_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
