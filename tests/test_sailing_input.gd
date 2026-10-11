extends SceneTree
const Runtime = preload("res://game/runtime/mingqi_runtime.gd")
const Interface = preload("res://game/ui/mingqi/mingqi_interface.gd")
const Trial = preload("res://game/scenes/sailing_trial/sailing_trial.gd")
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
func trial_key(code: Key, physical: bool = true) -> void:
	var event := InputEventKey.new(); event.pressed = true
	if physical: event.physical_keycode = code
	else: event.keycode = code
	root.push_input(event,true)
func trial_click(control: Control, local: Vector2) -> void:
	var event := InputEventMouseButton.new(); event.button_index = MOUSE_BUTTON_LEFT; event.pressed = true
	event.position = control.get_global_transform_with_canvas() * local; root.push_input(event,true)
	event = event.duplicate(); event.pressed = false; root.push_input(event,true)
func trial_chart_tests() -> void:
	# Resize the logical viewport, without the project's 1600px canvas scaling.
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1280,720)
	var trial := Trial.new(); root.add_child(trial); trial.set_physics_process(false)
	await process_frame
	var compact := trial.find_child("minimap",true,false) as Control
	check(compact != null,"default trial has actual compact chart")
	if compact == null: trial.queue_free(); await process_frame; return
	check(compact.visible and compact.position.x>700,"trial compact chart stays clear of left HUD")
	var initial: Dictionary = trial.runtime.snapshot()
	var marks: Array = compact.ship_marks()
	check(marks.size()==1 and marks[0].flagship and marks[0].position==Vector2(initial.ship.position.x,initial.ship.position.z),"trial chart shows only real runtime player position")
	check(marks[0].direction.is_equal_approx(Vector2(cos(initial.ship.heading),sin(initial.ship.heading))),"trial chart heading comes from real runtime")
	compact._native.ships[0].visual.position.x=9999.0
	check(trial.runtime.snapshot().ship.position.x==initial.ship.position.x,"chart owns detached position and cannot mutate native runtime")
	trial._apply_snapshot(0.0)
	var retained: Dictionary = compact._native
	for tick in 240: trial.runtime.advance(1.0/120)
	trial._apply_snapshot(2.0)
	var moved: Dictionary = trial.runtime.snapshot()
	check(compact.ship_marks()[0].position==Vector2(moved.ship.position.x,moved.ship.position.z) and moved.ship.position!=initial.ship.position,"trial compact position follows real physics movement")
	check(retained.ships[0].visual.position==initial.ship.position,"chart snapshot does not mutate previously supplied ship positions")
	trial_click(compact,compact.map_rect().get_center()); await process_frame
	var expanded := trial.find_child("trial_chart",true,false) as Control
	var close := trial.find_child("trial_chart_close",true,false) as Button
	check(expanded != null and expanded.is_visible_in_tree() and close != null,"actual compact Control click opens expanded trial chart")
	if expanded == null or close == null: trial.queue_free(); await process_frame; return
	check(trial.runtime.snapshot().paused and not compact.visible,"expanded chart owns pause and hides compact chart")
	check(expanded.mouse_filter==Control.MOUSE_FILTER_IGNORE and expanded.ship_marks().size()==1,"expanded trial chart is read-only with only native player mark")
	var waypoints: Array = []
	expanded.waypoint_requested.connect(func(point: Dictionary): waypoints.append(point))
	trial_click(expanded,expanded.map_rect().get_center()); await process_frame
	check(waypoints.is_empty() and not trial.runtime.snapshot().ship.has("navigation"),"actual full-chart click cannot create a trial waypoint")
	var frozen: Dictionary = trial.runtime.snapshot()
	trial_key(KEY_SPACE); trial.runtime.advance(0.1)
	check(trial.runtime.snapshot().time==frozen.time and trial.runtime.snapshot().paused,"Space cannot release chart modal pause")
	trial_click(close,close.size/2); await process_frame
	check(not expanded.is_visible_in_tree() and not trial.runtime.snapshot().paused and compact.visible,"actual close Button restores running state")
	trial.runtime.command({"type":"pause","value":true})
	trial_key(KEY_M,false); await process_frame
	check(expanded.is_visible_in_tree(),"M keycode fallback opens chart")
	close.grab_focus(); trial_key(KEY_ESCAPE,false); await process_frame
	check(not expanded.is_visible_in_tree() and trial.runtime.snapshot().paused,"focused modal Escape closes before quit and retains prior pause")
	trial_key(KEY_M); await process_frame
	trial_key(KEY_M); await process_frame
	check(not expanded.is_visible_in_tree() and trial.runtime.snapshot().paused,"physical M toggles chart and restores prior pause")
	root.size=Vector2i(800,600); await process_frame
	check(not compact.visible,"narrow trial viewport hides compact chart")
	trial_key(KEY_M); await process_frame
	check(expanded.is_visible_in_tree() and Rect2(Vector2.ZERO,Vector2(root.size)).encloses(expanded.get_global_rect()) and Rect2(Vector2.ZERO,Vector2(root.size)).encloses(close.get_global_rect()),"narrow viewport retains expanded chart and close control inside viewport")
	root.size=Vector2i(800,480); await process_frame
	check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(expanded.get_global_rect()) and Rect2(Vector2.ZERO,Vector2(root.size)).encloses(close.get_global_rect()),"short viewport keeps expanded chart and close control reachable")
	trial_key(KEY_ESCAPE); root.size=Vector2i(1280,720); await process_frame
	trial.hud.visible=false; trial._apply_snapshot(0.0)
	check(not compact.visible,"hidden HUD also hides trial compact chart")
	trial.queue_free(); await process_frame
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
	await trial_chart_tests()
	print("SAILING_INPUT_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
