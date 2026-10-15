extends SceneTree
const Body=preload("res://modules/physics_engine/ships/ship_dynamics.gd")
const Coastal=preload("res://modules/physics_engine/ocean/coastal_wave_field.gd")
const Types=preload("res://modules/contracts/physics_types.gd")
var assertions:=0
var failures:=0
class MovingWater:
	extends RefCounted
	func sample(_x:float,_z:float,t:float)->Dictionary:return {"height":t*.4}
func check(ok:bool,message:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL: ",message)
func solver()->RefCounted:
	return Body.new()
func _initialize()->void:run.call_deferred()
func run()->void:
	var rising:=solver()
	check(rising.configure({"kind":"fuchuan","sailDeployment":0},Callable(),MovingWater.new()),"moving plane configured")
	for tick in 600:rising.step_buoyancy(1.0/60.0)
	var end:Dictionary=rising.get_snapshot()
	check(absf(end.position.y-end.time*.4)<.05,"co-moving water has no sustained world-frame damping offset")
	rising.step_buoyancy(1.0/60.0,end.time)
	check(rising.get_snapshot()==end,"positive delta with repeated accepted time cannot reintegrate buoyancy")
	rising.step_buoyancy(1.0/60.0,end.time-1.0)
	check(rising.get_snapshot()==end,"rewind requires reset rather than integrating stale water samples")
	rising.step(1.0/60.0,{"time":end.time,"sailDeployment":1.0,"rudderAngleDeg":25.0})
	check(rising.get_snapshot()==end,"full motion entry rejects repeated time before controls or physics mutate")
	var rows:Array=[]
	for kind:String in Types.SHIP_SPECS:
		for depth:float in [3.0,20.0]:
			var ground:=func(_x:float,_z:float)->float:return -depth
			var waves:=Coastal.new();waves.configure(ground)
			var body:=solver();check(body.configure({"kind":kind,"position":{"x":-160.0,"z":-60.0},"heading":.45,"sailDeployment":0.0},ground,waves),"configure "+kind)
			var peak:=0.0;var finite:=true;var squares:=0.0
			for tick in 7200:
				var s:Dictionary=body.step_buoyancy(1.0/60.0)
				var avg:float=body.get_wave_debug().averageHeight
				var difference:float=s.position.y-avg-float(s.buoyancyOffsetY)
				peak=maxf(peak,absf(difference));squares+=difference*difference
				finite=finite and is_finite(s.position.y) and is_finite(s.pitch) and is_finite(s.heel)
			var draft:float=Types.ship_spec(kind).draft
			check(finite,"finite "+kind)
			check(peak<=draft*.25+.000001,"water-relative immersion envelope "+kind+" depth "+str(depth)+" peak "+str(peak))
			check(sqrt(squares/7200)<draft*.1,"tracks moving water without spending the cycle on an artificial clamp "+kind)
			rows.append({"kind":kind,"depth":depth,"peak":peak,"rms":sqrt(squares/7200)})
			var before:Dictionary=body.get_snapshot()
			body.step_buoyancy(0.0);body.step_buoyancy(NAN)
			check(body.get_snapshot()==before,"invalid steps preserve pose "+kind)
	# Reset at the same phase must not retain a previous ship's surface velocity.
	var fresh:=solver();var restarted:=solver()
	var ground:=func(_x:float,_z:float)->float:return -20.0
	var wave:=Coastal.new();wave.configure(ground)
	var spec:={"kind":"fisherman","time":7.0,"sailDeployment":0.0,"position":{"x":25.0,"z":-14.0}}
	restarted.configure({"kind":"heavy"},ground,wave)
	for tick in 120:restarted.step_buoyancy(1.0/60.0)
	restarted.configure(spec,ground,wave);fresh.configure(spec,ground,wave)
	for tick in 120:
		restarted.step_buoyancy(1.0/60.0);fresh.step_buoyancy(1.0/60.0)
	check(restarted.get_snapshot()==fresh.get_snapshot(),"reset clears old ship and water-motion history")
	check(restarted.set_draft_meters(.5),"live draft changes accepted")
	var changed:Dictionary=restarted.step_buoyancy(1.0/60.0)
	check(absf(changed.position.y-float(restarted.get_wave_debug().averageHeight)-float(changed.buoyancyOffsetY))<=.125001,"new draft immediately controls its own water-relative envelope")
	print("BUOYANCY_CONTACT_METRICS ",JSON.stringify(rows))
	print("BUOYANCY_CONTACT_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
