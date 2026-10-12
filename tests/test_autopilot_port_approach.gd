extends SceneTree
const Encounter=preload("res://modules/naval_simulation/encounter.gd")
const Manual=preload("res://modules/physics_engine/ships/manual_handling.gd")
var assertions:=0
var failures:=0
func check(ok: bool,label: String) -> void:
	assertions+=1
	if not ok: failures+=1;printerr("FAIL: ",label)
func case_for(heading: float,reference: bool=true,position: Dictionary={"x":347.597,"z":126.349}) -> RefCounted:
	return Encounter.new({"mode":"continuous","routePlanning":true,"referenceHandling":reference,"battleId":"isolated-port-approach","playerId":"merchant","controllableShipIds":["merchant"],"hostileTargets":{},"sampleTerrainHeight":func(_x: float,_z: float)->float:return -24.0,"oceanWaves":[],"wind":{"direction":{"x":-1.0,"y":0.0},"speed":12.0},"ships":[{"id":"merchant","kind":"merchant","team":"player","position":position,"heading":heading,"speed":0.2,"crew":20,"sail":100,"hull":100,"sailDeployment":0.1987,"autoTrim":true,"stats":{"maxHull":100,"maxCrew":30,"draftMeters":1.6,"cargoMass":2000}}]})
func run_approach(heading: float) -> Dictionary:
	var e:=case_for(heading);check(e.last_error.is_empty(),"healthy single-merchant actual physics fixture is valid")
	var target:={"x":282.1499288930165,"z":107.48568719733964}
	check(e.navigate("merchant",target).ok,"actual native navigation accepts unobstructed port")
	var samples=[];var arrived=false;var nearest=INF;var low_turn_ticks=0;var minimum_sails=1.0
	for i in 36000:
		e.step(1.0/60.0)
		var s: Dictionary=e.snapshot().ships[0];var p: Dictionary=s.visual.position;var v: Dictionary=s.visual.velocity
		var distance:=Vector2(p.x-target.x,p.z-target.z).length();var speed:=Vector2(v.x,v.z).length()
		nearest=minf(nearest,distance);minimum_sails=minf(minimum_sails,s.sailDeployment)
		if e.ships[0].lowSpeedTurn:low_turn_ticks+=1
		if i%600==0:samples.append({"time":e.snapshot().time,"position":p,"distance":distance,"speed":speed,"heading":s.visual.heading,"rudder":s.rudder,"sails":s.sailDeployment,"lowSpeedTurn":e.ships[0].lowSpeedTurn,"tack":e.ships[0].get("tack")})
		if distance<=25.0 and speed<=0.75:arrived=true;break
	var final: Dictionary=e.snapshot().ships[0]
	return {"initialHeading":heading,"arrived":arrived,"seconds":e.snapshot().time,"nearest":nearest,"lowTurnTicks":low_turn_ticks,"minimumSails":minimum_sails,"final":final,"samples":samples}
func _initialize() -> void:
	for heading in [-1.4386,0.0,PI]:
		var result:=run_approach(heading)
		print("AUTOPILOT_PORT_DIAGNOSTICS ",JSON.stringify(result,"",false,true))
		check(result.arrived,"actual single healthy merchant recovers and reaches port at business arrival speed from heading "+str(heading))
		check(result.final.hull==100 and result.final.sail==100 and result.final.crew==20,"isolated controller test changes no health crew or sails")
	var target:={"x":282.1499288930165,"z":107.48568719733964}
	var e:=case_for(0.0);check(e.navigate("merchant",target).ok,"bounded steering request fixture has real navigation")
	var request: Dictionary=e._autopilot(e.ships[0])
	check(not request.is_empty() and not Manual.sanitize(request).is_empty(),"actual autopilot delegates a valid existing steering request")
	check(absf(request.targetYawRateRad)<=6*PI/180 and request.maxYawAccelerationRad<=8*PI/180 and request.powerFraction<=20.0/30.0 and request.brakeDeceleration==0,"merchant recovery respects existing hull crew yaw budgets and adds no brake or drive")
	var original:=case_for(0.0,false);original.navigate("merchant",target)
	check(original._autopilot(original.ships[0]).is_empty(),"original default-false navigation receives no recovery assist")
	var visual: Dictionary=e.snapshot().ships[0].visual
	check(e._navigation_steerage(e.ships[0],visual,2*PI/3,2*PI/3,true,68.0,false).is_empty(),"collision-blocked course cannot use recovery assist")
	check(e._navigation_steerage(e.ships[0],visual,2*PI/3,2*PI/3,false,18.0,false).is_empty(),"final target braking radius cannot acquire turn recovery")
	var unplanned:=case_for(0.0,true,{"x":target.x+25,"z":target.z});unplanned.config.routePlanning=false;unplanned.navigate("merchant",target)
	check(unplanned._autopilot(unplanned.ships[0]).is_empty(),"non-planning native 30m braking range also suppresses recovery")
	check(e._navigation_steerage(e.ships[0],visual,visual.heading,0.0,false,68.0,false).is_empty(),"aligned low speed does not receive artificial steering")
	var locked:=case_for(0.0);locked.navigate("merchant",target);locked.policy.lockedShipIds=["merchant"];locked.step(1.0/60.0)
	check(locked.snapshot().ships[0].rudder==0 and locked.snapshot().ships[0].sailDeployment==0,"service-locked ship stays stopped instead of receiving autonomous recovery")
	var disabled:=case_for(0.0);disabled.navigate("merchant",target);disabled.policy.disabledMotionShipIds=["merchant"];disabled.step(1.0/60.0)
	check(disabled.snapshot().ships[0].rudder==0 and disabled.snapshot().ships[0].sailDeployment==0 and not disabled.snapshot().ships[0].has("navigation"),"disabled-motion authority cancels navigation and recovery")
	var captured:=case_for(0.0);captured.navigate("merchant",target);captured.policy.capturedShipIds=["merchant"]
	check(captured._autopilot(captured.ships[0]).is_empty(),"captured ship does not get crew recovery")
	var dry:=case_for(0.0);dry.navigate("merchant",target)
	dry.config.sampleTerrainHeight=func(x: float,z: float)->float:return 4.0 if x>335 and x<360 and z>137 else -24.0
	var dry_visual: Dictionary=dry.snapshot().ships[0].visual
	check(dry._navigation_steerage(dry.ships[0],dry_visual,2*PI/3,2*PI/3,false,68.0,false).is_empty(),"recovery turn rejects dry swept hull orientations even when initial footprint is wet")
	print("AUTOPILOT_PORT_APPROACH_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
