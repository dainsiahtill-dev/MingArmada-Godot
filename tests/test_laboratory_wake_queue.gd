extends SceneTree
## Actual Demo + producer + field facade queue, held at the asynchronous
## scheduling boundary. No RD exists, no fake pixels or GPU success claimed.
var assertions := 0
var failures := 0
func check(ok: bool,detail: String) -> void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL wake queue: ",detail)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var viewport:=SubViewport.new();viewport.size=Vector2i(1200,760);viewport.own_world_3d=true;root.add_child(viewport)
	var demo=load("res://game/research/demos/wake_flow_experiment.gd").new()
	demo.configure({"field_enabled":true});viewport.add_child(demo)
	for boundary: String in ["in_flight","awaiting_ack"]:
		if boundary=="awaiting_ack":demo.reset_experiment({"field_enabled":true,"paused":false})
		var field: RefCounted=demo.get("_field")
		field.set("_backend",load("res://modules/scene_engine/water/interactive_wake_field_rd.gd").new())
		field.set("_in_flight",boundary=="in_flight")
		field.set("_awaiting_ack",boundary=="awaiting_ack")
		for tick in 64:demo.advance(1.0/32.0)
		var before: Dictionary=field.get("_queued").duplicate(true)
		var inputs: Dictionary=demo.inspection_snapshot().interaction
		var force_proxy:=0.0
		for emitter: Dictionary in before.get("emitters",[]):force_proxy+=emitter.velocity.length()*emitter.weight*emitter.wetness
		check(before.get("emitters",[]).size()==5 and before.get("wakes",[]).size()==1 and force_proxy>0.0,boundary+": real moving ship queued nonzero interaction")
		var coalesced: int=field.diagnostics().queue_coalesced
		var skips: int=int(demo.inspection_snapshot().get("interaction_duplicate_skips",0))
		demo.set_paused(true);demo.orbit_camera(.1,0.0)
		check(field.get("_queued")==before,boundary+": same-time camera redraw preserves the actual queued force packet")
		check(field.diagnostics().queue_coalesced==coalesced,boundary+": observer redraw makes no new field submission")
		check(demo.inspection_snapshot().interaction==inputs,boundary+": last accepted input receipt survives duplicate observer sampling")
		check(demo.inspection_snapshot().get("interaction_duplicate_skips",-1)==skips+1,boundary+": duplicate skip is explicitly counted")
		demo.set_paused(false);demo.advance(1.0/32.0)
		check(float(field.get("_queued").seconds)>float(before.seconds) and field.get("_queued").emitters.size()==5,boundary+": next accepted pose still replaces queue normally")
		# Restore the unconfigured headless owner before normal dispose; no
		# rendering-thread methods are invoked by this queue-boundary fixture.
		field.set("_backend",null)
	demo.dispose();viewport.free()
	print("LABORATORY_WAKE_QUEUE_PASS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
