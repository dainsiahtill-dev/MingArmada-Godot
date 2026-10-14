extends SceneTree
var assertions := 0
var failures := 0
var readback_result: Dictionary = {}
func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL interactive wake lab: ",detail)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var demo = load("res://game/research/demos/wake_flow_experiment.gd").new()
	var defaults: Dictionary = demo.get_default_options()
	check(defaults.has("field_enabled") and defaults.get("field_enabled") == false,"new field is opt-in; existing source remains default")
	check(defaults.get("field_debug") == "none","normal ocean view is default")
	check(not demo.configure({"field_enabled":1}).ok,"nonboolean field selection rejected")
	check(not demo.configure({"field_enabled":true,"flow_enabled":true}).ok,"historical center trail and field cannot silently mix")
	check(not demo.configure({"field_debug":"made-up"}).ok,"unsupported field debug rejected")
	check(demo.configure({}).ok,"default configuration remains accepted")
	var viewport := SubViewport.new(); viewport.size=Vector2i(960,640); viewport.own_world_3d=true
	root.add_child(viewport); viewport.add_child(demo)
	var initial: Dictionary=demo.inspection_snapshot()
	check(initial.get("field_status")=="disabled" and initial.get("field",{}).is_empty(),"baseline owns no field resources")
	var controls: Array=demo.control_spec();var ids: Array=[]
	for control: Dictionary in controls: ids.append(control.id)
	check(ids.has("field_enabled") and ids.has("field_debug") and ids.has("contact_enabled"),"field and local contact have independent visible factors")
	check(ids.has("carrier_extent") and demo.set_parameter("carrier_extent",384.0).get("reset_required",false),"field carrier density is a declared reset factor for reproducible displacement comparisons")
	var change: Dictionary=demo.set_parameter("field_enabled",true)
	check(change.get("ok",false) and change.get("reset_required",false),"field selection resets asynchronous ownership")
	check(not demo.inspection_snapshot().parameters.get("field_enabled",false),"selection receipt leaves current history unchanged")
	var before: Dictionary=demo.inspection_snapshot()
	check(demo.set_parameter("contact_enabled",false).get("ok",false),"local contact can be hidden independently")
	check(not demo.inspection_snapshot().contact_visible and demo.inspection_snapshot().time==before.time,"contact visibility changes no accepted time")
	check(demo.set_parameter("field_debug","foam").get("ok",false),"field debug accepts foam")
	check(demo.inspection_snapshot().parameters.get("field_debug")=="foam" and demo.inspection_snapshot().time==before.time,"debug changes no accepted time")
	# This machine runs the contract suite headless. A missing RD must be an
	# explicit candidate error with the real source fallback, never fake ready.
	var configured: Dictionary=demo.reset_experiment({"field_enabled":true,"field_debug":"none","contact_enabled":false})
	check(configured.get("ok",false),"field experiment keeps a valid scene while asynchronous backend reports separately")
	if configured.get("ok",false):
		demo.advance(1.0/32.0)
		var first: Dictionary=demo.inspection_snapshot()
		var inputs: Dictionary=first.get("interaction",{})
		check(inputs.get("diagnostics",{}).get("accepted",false) and inputs.get("emitters",[]).size()==5,"candidate consumes actual five hull probes through shared producer")
		check(is_equal_approx(float(inputs.get("diagnostics",{}).get("time",-1)),first.time) and first.time>0.0,"first probe uses accepted native time, not observation tick")
		check(is_equal_approx(float(first.get("field_requested_time",-1)),.025) and is_equal_approx(first.presentation_time,.03125),"field submits native .025 seconds while observer first tick is .03125")
		check(float(inputs.get("diagnostics",{}).get("beam_m",0))>2.0 and float(inputs.get("diagnostics",{}).get("beam_m",0))<8.0,"fuchuan inputs use measured waterline scale, not nominal nine metre beam")
		var has_vertical_motion := false
		for emitter: Dictionary in inputs.get("emitters",[]):
			has_vertical_motion=has_vertical_motion or absf(emitter.velocity.y)>0.00001
		check(has_vertical_motion,"native heave reaches interaction as full 3D probe velocity")
		for i in 127: demo.advance(1.0/32.0)
		var active: Dictionary=demo.inspection_snapshot()
		check(active.native_ship!=initial.native_ship and active.time>3.9,"field factor uses actual SailingRuntime motion")
		check(active.get("field_status") in ["pending","ready","error"],"candidate accurately declares asynchronous lifecycle")
		if active.get("field_status") != "ready":
			check(not active.get("field_bound",true) and active.tail_visible,"unavailable field preserves visible source tail")
			check(active.get("field_status") != "error" or not str(active.get("field_error","")).is_empty(),"error gives an actionable reason")
		demo.set_paused(true)
		var frozen: Dictionary=demo.inspection_snapshot();demo.advance(1.0);demo.orbit_camera(.1,0.0)
		check(demo.inspection_snapshot().time==frozen.time and demo.inspection_snapshot().field.get("tick",0)==frozen.field.get("tick",0),"pause and camera update cannot age field")
		demo.request_field_readback(func(receipt: Dictionary):readback_result=receipt)
		check(demo.reset_experiment({"field_enabled":false,"paused":false}).ok,"field reset can return to source baseline")
		await process_frame
		check(readback_result.get("error")=="stale-field-readback","queued old-generation readback cannot be accepted after reset")
		check(demo.inspection_snapshot().get("field_status")=="disabled" and demo.inspection_snapshot().native_ship==initial.native_ship,"reset drops field history and restores actual initial state")
	demo.dispose();demo.dispose()
	check(not demo.inspection_snapshot().ready and demo.get_child_count()==0 and demo.inspection_snapshot().get("field_status")=="disposed","idempotent dispose releases asynchronous owner before world")
	viewport.free()
	print("LABORATORY_INTERACTIVE_WAKE_FIELD_PASS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
