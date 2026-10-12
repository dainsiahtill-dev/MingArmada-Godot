extends SceneTree
# Recorded scalars initialize fresh real physics fixtures. No campaign, storage,
# journey replay, or post-step correction is used to manufacture an arrival.
const Encounter=preload("res://modules/naval_simulation/encounter.gd")
const Height=preload("res://modules/scene_engine/terrain/height_field.gd")
const Layout=preload("res://game/scenes/common/reference_geography.gd")
const Sailing=preload("res://game/runtime/sailing_simulation.gd")
const Manual=preload("res://modules/physics_engine/ships/manual_handling.gd")
const Runtime=preload("res://game/runtime/mingqi_runtime.gd")
const INPUT="res://docs/migration/evidence/opening-story/second-voyage-aftermath/journey-second.json"
const INPUT_SHA256="191170ccf22ab26dfd00521c3ea2ff6933e30c2c24b98d575e7ea856b2a3c037"
const FAST="mingqi-1650-fast"
const GRAIN_A="mingqi-1650-grain-a"
const GRAIN_B="mingqi-1650-grain-b"
var assertions=0
var failures=0
var record: Dictionary
var heights=Height.new()
var diagnostics: Array=[]
func check(ok: bool,label: String) -> void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL: ",label)
func motion(e: RefCounted) -> Array:
	return e.ships.map(func(s):return s.core.get_snapshot())
func kinematics(e: RefCounted) -> Array:
	return e.ships.map(func(s):
		var p: Dictionary=s.core.get_snapshot()
		return {"position":p.position,"velocity":p.velocity,"heading":p.heading,"yawRate":p.yawRate,"time":p.time})
func recorded(seconds: float) -> RefCounted:
	var stage: Dictionary
	for s: Dictionary in record.stages:
		if s.simulationSeconds==seconds:stage=s;break
	var setups: Array=[]
	for s: Dictionary in stage.ships:
		var setup: Dictionary=s.nativeDiagnostics.duplicate(true)
		setup.position=s.position;setup.heading=s.heading;setup.speed=0;setups.append(setup)
	var e=Encounter.new({"mode":"continuous","routePlanning":true,"referenceHandling":true,"ships":setups,"playerId":record.final.campaign.flagshipId,"controllableShipIds":stage.runtime.controllableShipIds,"hostileTargets":{},"sampleTerrainHeight":heights.sample_height,"wind":record.final.naval.wind,"oceanWaves":[]})
	check(e.last_error.is_empty(),"recorded "+str(seconds)+" initializes actual Encounter")
	for s: Dictionary in stage.ships:
		var ship: Dictionary=e._ship(s.id);var p: Dictionary=s.navigationDiagnostics.motion
		# Initial fixture restoration only, before any control decision or tick.
		ship.core.correct_horizontal_motion(p.position,p.velocity,p.heading)
		ship.core._yaw_rate=p.yawRate
		ship.core._time=p.time;ship.core._base_y=p.baseY
		ship.core._heave=p.heave;ship.core._heave_rate=p.heaveRate
		ship.core._pitch=p.pitch;ship.core._pitch_rate=p.pitchRate
		ship.core._heel=p.heel;ship.core._heel_rate=p.heelRate
		ship.core._buoyancy_offset=p.buoyancyOffsetY
		ship.previous=e._visual(ship)
		# Historical previous/tack were not recorded. This explicitly linearizes
		# previous heading from measured yaw; it is not a historical tick replay.
		ship.previous.heading=p.heading-p.yawRate/60.0
		if s.navigation!=null:ship.state.navigation=s.navigation.duplicate(true)
		if s.navigationDiagnostics.route!=null:ship.route=s.navigationDiagnostics.route.duplicate(true)
		ship.lowSpeedTurn=s.navigationDiagnostics.lowSpeedTurn
		ship.sailRecovery=s.navigationDiagnostics.sailRecovery
		e.tick=int(p.time*60.0)
	return e
func simple(position: Dictionary={"x":0.0,"z":0.0},heading: float=PI/2,extra: Array=[]) -> RefCounted:
	var setups=[{"id":"own","kind":"merchant","team":"player","position":position,"heading":heading,"speed":0.2,"rudder":0.7,"sailDeployment":0.4,"crew":20,"stats":{"maxCrew":30}}]
	setups.append_array(extra)
	var e=Encounter.new({"mode":"continuous","routePlanning":true,"referenceHandling":true,"ships":setups,"playerId":"own","controllableShipIds":["own"],"hostileTargets":{},"sampleTerrainHeight":func(_x: float,_z: float)->float:return -24.0,"wind":{"direction":{"x":-1.0,"y":0.0},"speed":12.0},"oceanWaves":[]})
	check(e.last_error.is_empty(),"isolated real native fixture initializes")
	return e
func install_route(e: RefCounted,points: Array) -> void:
	var ship: Dictionary=e._ship("own")
	ship.route={"target":ship.state.navigation.duplicate(true),"points":points.duplicate(true),"checked":e.tick,"distance":e._distance(points[0],e._visual(ship).position),"draft":ship.state.dimensions.draft,"retryAt":e.tick,"failures":0}
func rally_completion() -> void:
	var e=recorded(2156.6);var ship: Dictionary=e._ship(GRAIN_B)
	check(e.issue_order({"id":"completion","shipIds":[GRAIN_B],"intent":{"kind":"rally","point":record.routes.returnPoints[-1]}}).ok,"actual Rally accepts recorded B arrival")
	ship.tack={"side":1};ship.lowSpeedTurn=true;ship.sailRecovery=0.8
	ship.approachRecovery={"goal":record.routes.returnPoints[-1],"startedTick":e.tick,"holding":true}
	ship.wetRouteEgress={"goal":record.routes.returnPoints[-1],"draft":ship.state.dimensions.draft,"node":record.routes.returnPoints[-1],"startedTick":e.tick,"holding":true}
	var before=motion(e);var peer_controls=e._ship(FAST).state.duplicate(true)
	e._tactical_tick()
	check(e.orders.completion.status.state=="completed" and e.orders.completion.status.reason=="rally-arrived","real Rally completes at unchanged25m/1mps contract")
	check(ship.state.rudder==0 and ship.state.sailDeployment==0,"completed Rally releases its old autonomous helm and sail")
	check(ship.state.get("navigation")==record.routes.returnPoints[-1] and ship.has("terminalStop") and not ship.has("route") and not ship.has("tack"),"completed Rally hands exact stopping navigation to wrapper owner and clears obsolete route and tack")
	check(not ship.has("approachRecovery") and not ship.has("wetRouteEgress") and not ship.lowSpeedTurn and ship.sailRecovery==0,"completed Rally releases old recovery output states")
	check(before==motion(e),"Rally cleanup does not mutate any native pose velocity yaw or clock")
	check(peer_controls==e._ship(FAST).state,"Rally completion does not erase nonparticipant controls")
	for i in 60:e.step(1.0/60.0)
	check(ship.state.rudder==0 and ship.state.sailDeployment==0,"later real native ticks do not reapply completed Rally helm")
	check(e._speed(e._visual(ship))>0,"Rally control cleanup preserves physical coast instead of instantaneous anchoring")
func stationary_protect() -> void:
	for seconds in [1496.6,1511.6]:
		var e=recorded(seconds);var ship: Dictionary=e._ship(FAST)
		check(e.issue_order({"id":"stationary-protect","shipIds":[FAST],"intent":{"kind":"protect","targetId":GRAIN_A}}).ok,"actual protect accepts recorded early station")
		e._tactical_tick();var goal: Dictionary=ship.state.navigation.duplicate(true)
		check(e.is_anchored(GRAIN_A) and e._distance(goal,e._visual(ship).position)<18,"recorded target anchored and protect station already reached")
		var before=motion(e);var request: Dictionary=e._autopilot(ship)
		check(request.get("brakeDeceleration",0)==0.2 and request.get("targetYawRateRad",1)==0 and ship.state.rudder==0 and ship.state.sailDeployment==0,"reached stationary protect station requests existing neutral physical brake without old helm")
		check(not ship.lowSpeedTurn and ship.sailRecovery==0 and not ship.has("tack"),"station hold releases obsolete turning output")
		check(e.hasActiveOrder(FAST) and ship.state.navigation==goal,"station hold retains live protect ownership and its exact goal")
		check(before==motion(e),"station decision preserves every native pose velocity yaw and clock")
		if seconds==1496.6:
			var initial: Dictionary=ship.core.get_snapshot();var wet=true;var neutral=true
			for i in 600:
				e.step(1.0/60.0);var p: Dictionary=e._visual(ship)
				wet=wet and e._wet_hull(ship,p.position.x,p.position.z,p.heading)
				neutral=neutral and ship.state.rudder==0 and ship.state.sailDeployment==0
			var final: Dictionary=ship.core.get_snapshot()
			check(wet and neutral,"ten actual native seconds retain wet hull and neutral station controls")
			check(e._speed(e._visual(ship))<e._speed(initial) and absf(final.yawRate)<absf(initial.yawRate),"neutral station coast physically reduces recorded speed and yaw")
			check(final.position!=initial.position and final.velocity!=initial.velocity,"station slowing comes from native integration with nonzero residual motion")
			diagnostics.append({"case":"recorded1496-station-coast","seconds":10,"initial":initial,"final":final,"goal":goal,"allWet":wet,"allNeutral":neutral})
func final_navigation() -> void:
	for planned in [true,false]:
		var e=simple();e.config.routePlanning=planned
		var goal={"x":18.0 if planned else 30.0,"z":0.0}
		check(e.navigate("own",goal).ok,"ordinary final navigation accepts goal")
		var ship: Dictionary=e._ship("own");var before=motion(e)
		var request: Dictionary=e._autopilot(ship)
		check((request.get("brakeDeceleration",0)==0.2 if planned else request.is_empty()) and ship.state.rudder==0 and ship.state.sailDeployment==0,"ordinary final reach uses planned physical brake or unplanned neutral coast "+str(planned))
		check(ship.state.navigation==goal and before==motion(e),"ordinary final hold retains goal and exact native motion")
	var opted_out=simple();opted_out.config.referenceHandling=false;opted_out.navigate("own",{"x":10.0,"z":0.0})
	check(opted_out._autopilot(opted_out._ship("own")).is_empty(),"reference handling opt-out cannot acquire final physical brake")
	var e=simple();check(e.navigate("own",{"x":100.0,"z":0.0}).ok,"intermediate route accepts farther destination")
	install_route(e,[{"x":5.0,"z":0.0},{"x":100.0,"z":0.0}]);e._autopilot(e._ship("own"))
	check(e._ship("own").state.rudder!=0 and e._ship("own").route.points.size()==1,"reached intermediate waypoint pops and continues steering to farther final")
	e=simple();e.navigate("own",{"x":10.0,"z":0.0});install_route(e,[{"x":0.0,"z":80.0},{"x":10.0,"z":0.0}]);e._autopilot(e._ship("own"))
	check(e._ship("own").route.points.size()==2 and e._ship("own").state.sailDeployment>0,"near final coordinates do not bypass a remaining intermediate route")
func protect_boundary() -> void:
	var target={"id":"target","kind":"merchant","team":"neutral","position":{"x":0.0,"z":0.0},"heading":0.0,"speed":4.0,"sailDeployment":0.0}
	var e=simple({"x":0.0,"z":65.0},0.0,[target]);e.issue_order({"id":"moving-protect","shipIds":["own"],"intent":{"kind":"protect","targetId":"target"}});e._tactical_tick()
	var ship: Dictionary=e._ship("own");var initial_goal: Dictionary=ship.state.navigation.duplicate(true)
	check(e._distance(initial_goal,e._visual(ship).position)<18 and not e.is_anchored("target"),"moving protected target starts inside near station radius")
	e._autopilot(ship)
	check(ship.state.rudder!=0 and e.hasActiveOrder("own"),"moving protect goal keeps ordinary steering instead of stationary hold")
	for i in 600:e.step(1.0/60.0)
	check(ship.state.navigation!=initial_goal and e.hasActiveOrder("own") and ship.state.rudder!=0,"native target movement updates live goal and keeps navigation following")
	target.speed=0.0
	e=simple({"x":0.0,"z":65.0},0.0,[target]);e.policy.controllableShipIds.append("target")
	e.issue_order({"id":"departing-protect","shipIds":["own"],"intent":{"kind":"protect","targetId":"target"}});e._tactical_tick();ship=e._ship("own")
	e._autopilot(ship);check(ship.state.rudder==0,"stationary target begins with arrival hold")
	check(e.command({"type":"controls","shipId":"target","rudder":0.0,"sailDeployment":1.0}).ok,"protected target legitimately departs with new controls")
	e._tactical_tick();e._autopilot(ship)
	check(ship.state.rudder!=0 and e.hasActiveOrder("own"),"target departure immediately re-evaluates stationary hold and resumes steering")
	# Threat changes the formation point and fire decision; arrival must not
	# suppress normal tactical steering or combat even for an anchored target.
	target.speed=0.0
	var threat={"id":"threat","kind":"merchant","team":"hostile","position":{"x":100.0,"z":0.0},"sailDeployment":0.0}
	e=simple({"x":65.0,"z":0.0},PI/2,[target,threat]);e.policy.hostileTargets={"own":["threat"]}
	e.issue_order({"id":"threat-protect","shipIds":["own"],"intent":{"kind":"protect","targetId":"target"}});e._tactical_tick();ship=e._ship("own")
	check(e.decisions.own.fire and e._distance(ship.state.navigation,e._visual(ship).position)<18,"threat protect uses a reached but live combat decision")
	e._autopilot(ship);check(ship.state.rudder!=0,"threat fire decision preserves existing tactical steering")
func manual_precedence() -> void:
	for selected in ["own","peer"]:
		for helm in [-0.6,0.7]:
			var peer={"id":"peer","kind":"merchant","team":"neutral","position":{"x":200.0,"z":200.0},"sailDeployment":0.0}
			var e=simple({"x":0.0,"z":0.0},PI/2,[peer]);e.policy.controllableShipIds.append("peer");e.set_player_id(selected)
			e.issue_order({"id":"old-rally","shipIds":["own"],"intent":{"kind":"rally","point":{"x":10.0,"z":0.0}}})
			var simulation=Sailing.new(e)
			simulation.action({"type":"controls","shipId":"own","rudder":helm,"sailDeployment":0.35,"sailAngle":0.2,"autoTrim":false})
			check(simulation.has_pending_input(),"real Sailing queues newer helm or sail-only controls with selected "+selected)
			simulation.advance(1.0/60.0);var state: Dictionary=e._ship("own").state
			check(state.rudder==helm and state.sailDeployment==0.35 and state.sailAngle==0.2 and not state.autoTrim,"old Rally cancellation and tick preserve newest queued controls with selected "+selected)
			check(not e.hasActiveOrder("own") and not state.has("navigation"),"manual takeover revokes old arrival owner")
	var e=simple();e.issue_order({"id":"old","shipIds":["own"],"intent":{"kind":"rally","point":{"x":10.0,"z":0.0}}})
	check(not e.command({"type":"controls","shipId":"own","rudder":2.0,"sailDeployment":0.3}).ok and e.hasActiveOrder("own"),"invalid new controls cannot cancel current tactical owner")
	check(e.command({"type":"controls","shipId":"own","rudder":0.7,"sailDeployment":0.4}).ok and e.hasActiveOrder("own"),"unchanged controls retain current Rally ownership")
	e.issue_order({"id":"new","shipIds":["own"],"intent":{"kind":"rally","point":{"x":100.0,"z":0.0}}});e._tactical_tick()
	check(e.orders.old.status.state=="blocked" and e.orders.new.status.state=="active" and e._ship("own").state.navigation.x==100,"superseding order cannot be cleaned by the old near Rally")
func partial_rally() -> void:
	var peer={"id":"peer","kind":"merchant","team":"neutral","position":{"x":100.0,"z":100.0},"heading":0.0,"speed":0.2,"sailDeployment":0.4,"rudder":0.7}
	var e=simple({"x":20.0,"z":0.0},PI/2,[peer]);e.policy.controllableShipIds.append("peer")
	check(e.issue_order({"id":"fleet-rally","shipIds":["own","peer"],"intent":{"kind":"rally","point":{"x":0.0,"z":0.0}}}).ok,"real multi-participant Rally accepted")
	e._tactical_tick();var ship: Dictionary=e._ship("own");var before=motion(e)
	check(e.orders["fleet-rally"].status.state=="active" and e.decisions.own.completed and not e.decisions.peer.completed,"one Rally participant reaches20m while the other remains in transit")
	var request: Dictionary=e._autopilot(ship)
	check(ship.state.rudder==0 and ship.state.sailDeployment==0 and e.hasActiveOrder("own") and ship.state.has("navigation"),"completed Rally participant holds neutral while shared current order remains active")
	check(request.get("brakeDeceleration",0)==0.2 and request.get("targetYawRateRad",1)==0,"arrived partial Rally participant gets existing neutral physical brake")
	e._autopilot(e._ship("peer"))
	check(e._ship("peer").state.rudder!=0,"unreached Rally participant keeps normal autonomous steering")
	check(before==motion(e),"partial Rally control decisions preserve all native motion")
func recovery_priority() -> void:
	for owner in ["approachRecovery","wetRouteEgress"]:
		var e=simple();e.navigate("own",{"x":10.0,"z":0.0});var ship: Dictionary=e._ship("own")
		ship.core._yaw_rate=0.02;ship[owner]={"goal":ship.state.navigation.duplicate(true),"startedTick":e.tick,"holding":true,"draft":ship.state.dimensions.draft,"node":{"x":40.0,"z":0.0}}
		var before=motion(e);var request: Dictionary=e._autopilot(ship)
		check(ship.has(owner) and ship[owner].holding and request.get("brakeDeceleration",0)>0,"reached final point cannot short-circuit owned "+owner+" physical hold")
		check(before==motion(e),"owned recovery decision keeps native motion exact")
	var e=simple();e.navigate("own",{"x":10.0,"z":0.0});var ship: Dictionary=e._ship("own")
	e.config.sampleTerrainHeight=func(_x: float,_z: float)->float:return 4.0
	var request: Dictionary=e._autopilot(ship)
	check(ship.route.points.is_empty() and ship.route.reason=="unsafe-endpoint" and request.is_empty() and not ship.has("wetRouteEgress"),"near final goal cannot bypass invalid wet route or acquire unsafe egress")
func terminal_case(arm: bool=true) -> RefCounted:
	var e=simple()
	check(e.issue_order({"id":"stop-rally","shipIds":["own"],"intent":{"kind":"rally","point":{"x":0.0,"z":0.0}}}).ok,"genuine current stopping Rally accepted")
	if arm:e._tactical_tick()
	return e
func terminal_physics(accepted_seconds: float=10.0) -> void:
	var e=recorded(2156.6);var ship: Dictionary=e._ship(GRAIN_B)
	# Restore the two genuinely active peer owners using accepted order scalars.
	for input: Dictionary in record.commands:
		if input.input.type!="assign-order" or not input.input.order.id in ["continued-voyage-5","continued-voyage-7"]:continue
		var old: Dictionary=input.input.order
		check(e.issue_order({"id":old.id,"shipIds":old.shipIds,"intent":old.intent}).ok,"recorded native peer keeps its current Rally authority")
	check(e.issue_order({"id":"native-stop","shipIds":[GRAIN_B],"intent":{"kind":"rally","point":record.routes.returnPoints[-1]}}).ok,"recorded B accepts genuine stopping Rally")
	var before=motion(e);var peer_controls=[]
	for peer: Dictionary in e.ships:
		if peer.state.id!=GRAIN_B:peer_controls.append([peer.state.rudder,peer.state.sailDeployment])
	e._tactical_tick()
	check(ship.has("terminalStop") and not ship.state.has("terminalStop") and not e.snapshot().ships.any(func(s):return s.has("terminalStop")),"terminal stop is ephemeral wrapper authority outside snapshots and codec")
	check(before==motion(e),"terminal stop creation preserves every native pose velocity yaw and clock")
	var after_controls=[]
	for peer: Dictionary in e.ships:
		if peer.state.id!=GRAIN_B:after_controls.append([peer.state.rudder,peer.state.sailDeployment])
	check(peer_controls==after_controls,"B terminal creation does not neutralize its peers")
	check(not e.is_anchored(GRAIN_B),"Save anchor predicate rejects active physical settling owner")
	var initial: Dictionary=ship.core.get_snapshot();var stopped_at=-1.0;var wet=true;var max_distance=0.0
	e.step(1.0/60.0)
	var expected=Manual.sanitize(Manual.build("merchant",0.0,e._speed(initial),20.0/30.0,1.0,1.0,true,0.0,true))
	check(ship.core._controls.manualAssist==expected,"terminal stop applies exact existing neutral crew-scaled Manual budget")
	for i in range(1,int(accepted_seconds*60)):
		e.step(1.0/60.0);var p: Dictionary=ship.core.get_snapshot()
		wet=wet and e._wet_hull(ship,p.position.x,p.position.z,p.heading)
		max_distance=maxf(max_distance,e._distance(p.position,record.routes.returnPoints[-1]))
		if stopped_at<0 and not ship.has("terminalStop") and e.is_anchored(GRAIN_B):stopped_at=(i+1)/60.0
	check(stopped_at>0 and stopped_at<=60,"recorded B reaches real physical anchored thresholds within60 accepted seconds")
	check(wet and max_distance<=55 and e.is_anchored(GRAIN_B) and not ship.has("terminalStop"),"recorded B remains safely anchored within55m through"+str(accepted_seconds)+" native seconds")
	check(ship.state.hull==100 and ship.state.crew==20 and ship.state.sail==100,"native stopping preserves B health and crew")
	diagnostics.append({"case":"recorded2156-terminal-stop","seconds":accepted_seconds,"stoppedAt":stopped_at,"allWet":wet,"maximumGoalDistance":max_distance,"initial":initial,"final":ship.core.get_snapshot()})
func projected_setups(e: RefCounted) -> Array:
	var setups=[]
	for saved: Dictionary in e.snapshot().ships:
		var setup: Dictionary=saved.duplicate(true);setup.position=saved.visual.position;setup.heading=saved.visual.heading;setup.speed=0.0;setups.append(setup)
	return setups
func terminal_inputs() -> void:
	var e=terminal_case(false);var simulation=Sailing.new(e)
	simulation.advance(1.0/60.0);var ship: Dictionary=e._ship("own")
	check(ship.has("terminalStop"),"selected Sailing initialized before Rally completion acquires stopping owner")
	var owner: Dictionary=ship.get("terminalStop",{}).duplicate(true)
	for i in 20:simulation.advance(1.0/60.0)
	check(ship.has("terminalStop") and ship.get("terminalStop")==owner and ship.state.rudder==0 and ship.state.sailDeployment==0,"selected idle ticks restore completed autonomous controls without discarding stop owner")
	e=terminal_case(false);ship=e._ship("own")
	# Set the already-slow initial scalar fixture before any accepted step.
	ship.core.correct_horizontal_motion(e._visual(ship).position,{"x":0.0,"z":0.04})
	simulation=Sailing.new(e);simulation.advance(0.1)
	check(not ship.has("terminalStop") and not ship.state.has("navigation") and e.is_anchored("own") and ship.state.rudder==0 and ship.state.sailDeployment==0,"already-slow Rally completion survives multiple Sailing substeps without stale cached helm resurrection")
	e=terminal_case();ship=e._ship("own");owner=ship.get("terminalStop",{}).duplicate(true);var before=kinematics(e);var sequence=ship.state.controlsSequence
	check(e.reconcile_ships(projected_setups(e)).ok and ship.state.controlsSequence>sequence,"ordinary native projection legitimately increments controls sequence")
	check(ship.has("terminalStop") and ship.get("terminalStop")==owner and before==kinematics(e),"unchanged projection preserves terminal start deadline and physical state")
	var invalid=projected_setups(e);invalid[0].kind="fuchuan"
	var atomic_before=motion(e)
	check(not e.reconcile_ships(invalid).ok and ship.get("terminalStop")==owner and atomic_before==motion(e),"rejected projection atomically preserves previous stop owner and physical state")
	check(not e.command({"type":"controls","shipId":"own","rudder":2.0,"sailDeployment":0.0}).ok and ship.get("terminalStop")==owner,"invalid controls cannot revoke legitimate physical stop")
	check(e.command({"type":"controls","shipId":"own","rudder":0.0,"sailDeployment":0.0}).ok and ship.get("terminalStop")==owner,"unchanged idle controls preserve stop despite sequence increment")
	for takeover in ["helm","sail","trim","manual","cancel","same-navigation","new-navigation","same-order","new-order","projection-controls","projection-navigation","projection-orders","projection-permission","projection-capture","anchor"]:
		e=terminal_case();ship=e._ship("own");before=kinematics(e)
		check(ship.has("terminalStop"),"takeover fixture has genuine stop owner: "+takeover)
		var receipt={"ok":true}
		if takeover=="helm":receipt=e.command({"type":"controls","shipId":"own","rudder":-0.6,"sailDeployment":0.0})
		elif takeover=="sail":receipt=e.command({"type":"controls","shipId":"own","rudder":0.0,"sailDeployment":0.3})
		elif takeover=="trim":receipt=e.command({"type":"controls","shipId":"own","rudder":0.0,"sailDeployment":0.0,"sailAngle":0.2,"autoTrim":false})
		elif takeover=="manual":
			e.navigate("own",null);receipt=e.set_manual_handling("own",{"mode":"assisted","turnIntent":-0.5,"sailIntent":0.0,"braking":false,"recovery":false})
		elif takeover=="cancel":receipt=e.navigate("own",null)
		elif takeover in ["same-navigation","new-navigation"]:receipt=e.navigate("own",{"x":0.0 if takeover=="same-navigation" else 100.0,"z":0.0})
		elif takeover in ["same-order","new-order"]:receipt=e.issue_order({"id":"new-stop-order","shipIds":["own"],"intent":{"kind":"rally","point":{"x":0.0 if takeover=="same-order" else 100.0,"z":0.0}}})
		elif takeover=="projection-controls":
			var setups=projected_setups(e);setups[0].rudder=-0.4;receipt=e.reconcile_ships(setups)
		elif takeover in ["projection-navigation","projection-orders","projection-permission","projection-capture"]:
			var policy: Dictionary=e.policy.duplicate(true)
			if takeover=="projection-navigation":policy.navigation={"own":{"x":100.0,"z":0.0}}
			elif takeover=="projection-orders":policy.orders=[]
			elif takeover=="projection-permission":policy.controllableShipIds=[]
			else:policy.capturedShipIds=["own"]
			receipt=e.reconcile_ships(projected_setups(e),policy)
		elif takeover=="anchor":receipt=e.anchor_fleet(["own"])
		check(receipt.ok and not ship.has("terminalStop"),"successful newer authority revokes old physical stop: "+takeover)
		if takeover!="anchor":check(before==kinematics(e),"stop revocation does not overwrite native motion: "+takeover)
		if takeover=="helm":check(ship.state.rudder==-0.6,"new helm survives old-stop revocation")
		if takeover=="sail":check(ship.state.sailDeployment==0.3,"new sails survive old-stop revocation")
func terminal_gates() -> void:
	for gate in ["crew","hull","sail","captured","locked","disabled","permission","combat","terminal","planning","reference","draft","depth","battle","record","participant"]:
		var e=terminal_case();var ship: Dictionary=e._ship("own")
		check(ship.has("terminalStop"),"revocation fixture has genuine stopping owner: "+gate)
		if gate in ["crew","hull","sail"]:ship.state[gate]=0.0
		elif gate=="captured":e.policy.capturedShipIds=["own"]
		elif gate=="locked":e.policy.lockedShipIds=["own"]
		elif gate=="disabled":e.policy.disabledMotionShipIds=["own"]
		elif gate=="permission":e.policy.controllableShipIds=[]
		elif gate=="combat":e.volleys.append({"due":e.tick+100000,"shipId":"own"})
		elif gate=="terminal":e.status="surrendered"
		elif gate=="planning":e.config.routePlanning=false
		elif gate=="reference":e.config.referenceHandling=false
		elif gate=="draft":ship.state.dimensions.draft+=0.1
		elif gate=="depth":e.config.sampleTerrainHeight=func(_x: float,_z: float)->float:return 4.0
		elif gate=="battle":e.battle_id="new-incarnation"
		elif gate=="record":e.orders.clear()
		elif gate=="participant":e.orders["stop-rally"].participants.clear()
		e.step(1.0/60.0)
		check(not ship.has("terminalStop") and ship.core._controls.manualAssist.is_empty(),"lost current guard removes stop and its request: "+gate)
	var e=terminal_case(false);var ship: Dictionary=e._ship("own");ship.state.crew=0.001;e._tactical_tick()
	check(ship.has("terminalStop"),"low positive crew can acquire only its tiny existing physical budget")
	var owner: Dictionary=ship.get("terminalStop",{}).duplicate(true)
	check(owner.get("deadlineTick",-1)-owner.get("startedTick",-1)==3600,"terminal stop deadline uses exactly60 accepted native seconds")
	for i in 3601:e.step(1.0/60.0)
	check(not ship.has("terminalStop") and not e.is_anchored("own") and ship.core._controls.manualAssist.is_empty(),"insufficient native stopping power times out without forced anchoring")
	var before=motion(e);e._tactical_tick()
	check(not ship.has("terminalStop") and before==motion(e),"old completed Rally cannot rearm timed-out physical stop")
func terminal_capability_updates() -> void:
	for gate in ["lockedShipIds","disabledMotionShipIds"]:
		var e=terminal_case();var ship: Dictionary=e._ship("own");var before=kinematics(e)
		e.policy[gate]=["own"]
		check(e._terminal_stop_request(ship).is_empty() and not ship.has("terminalStop") and not ship.state.has("navigation"),"central controlled guard rejects stop request before service or disabled tick: "+gate)
		check(before==kinematics(e) and ship.state.rudder==0 and ship.state.sailDeployment==0,"request revocation only erases owned metadata: "+gate)
		e=terminal_case();ship=e._ship("own");e.command({"type":"controls","shipId":"own","rudder":-0.4,"sailDeployment":0.3});e.policy[gate]=["own"]
		check(e._terminal_stop_request(ship).is_empty() and ship.state.rudder==-0.4 and ship.state.sailDeployment==0.3,"lost stop permission does not overwrite already accepted newer controls: "+gate)
	var e=terminal_case();var ship: Dictionary=e._ship("own");var owner: Dictionary=ship.get("terminalStop",{}).duplicate(true)
	check(e.set_manual_handling("own",null).ok and ship.get("terminalStop")==owner,"clearing absent manual handling is not an autonomous stop takeover")
	var cases=[{"crew":10.0},{"hull":99.0},{"sail":99.0},{"stats":{"maxCrew":40}},{"stats":{"maxHull":120}},{"stats":{"cargoMass":1000}},{"stats":{"speedMultiplier":0.9}},{"stats":{"steeringMultiplier":0.9}},{"stats":{"draftMeters":1.5}}]
	for update: Dictionary in cases:
		e=terminal_case();ship=e._ship("own");var before=kinematics(e)
		check(e.update_ship_stats("own",update).ok,"actual healthy capability update validates: "+JSON.stringify(update))
		check(not ship.has("terminalStop") and not ship.state.has("navigation"),"committed health or physical capability change revokes previous stop: "+JSON.stringify(update))
		check(before==kinematics(e),"capability revocation preserves physical kinematics: "+JSON.stringify(update))
	e=terminal_case();ship=e._ship("own");owner=ship.get("terminalStop",{}).duplicate(true);var before=motion(e)
	check(not e.update_ship_stats("own",{"stats":{"cargoMass":-1}}).ok and ship.get("terminalStop")==owner and before==motion(e),"invalid physical update preserves existing stop atomically")
func runtime_stop_save() -> void:
	var campaign=Runtime.Campaign.new()
	check(campaign.restore(record.confirmedSourceCheckpointJson),"real Campaign restores genuine confirmed first checkpoint for Save lifecycle")
	var runtime=Runtime.new();runtime.enable_reference_enhancements(true)
	check(runtime.configure(heights.sample_height,campaign).ok,"real Runtime and Bridge configure checkpoint fixture")
	var e=runtime.simulation.encounter;var ship: Dictionary=e._ship(GRAIN_B)
	check(e.issue_order({"id":"save-stop","shipIds":[GRAIN_B],"intent":{"kind":"rally","point":{"x":e._visual(ship).position.x,"z":e._visual(ship).position.z}}}).ok,"current at-rest native Rally arms settling before Save")
	e._tactical_tick()
	check(ship.has("terminalStop") and not e.is_anchored(GRAIN_B),"numerically stationary ship remains unanchored until stopping owner retires")
	var result: Dictionary=runtime.export_save("2026-10-12T00:00:00.000Z")
	check(not result.ok and result.reason=="save-fleet-not-anchored:"+GRAIN_B,"ordinary Runtime export rejects active stop through unchanged full-fleet gate")
	var owner: Dictionary=ship.get("terminalStop",{}).duplicate(true)
	check(runtime.bridge.sync().ok and ship.get("terminalStop")==owner,"real unchanged Bridge projection preserves native stop identity and deadline")
	e.step(1.0/60.0)
	check(not ship.has("terminalStop") and e.is_anchored(GRAIN_B),"post-physics observation retires stationary stop without direct anchor call")
	result=runtime.export_save("2026-10-12T00:00:00.000Z")
	check(result.ok and not result.get("json","").contains("terminalStop"),"normal export succeeds after physical retirement without serializing stop metadata")
	if result.ok:
		var restored=Runtime.Campaign.new();check(restored.restore(result.json),"unchanged SaveCodec accepts legitimately exported checkpoint")
	runtime.dispose()
func _initialize() -> void:
	var exists=FileAccess.file_exists(INPUT)
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(INPUT)) if exists else null
	check(exists and FileAccess.get_sha256(INPUT)==INPUT_SHA256 and parsed is Dictionary,"immutable actual second-voyage scalar fixture has pinned SHA and readable record")
	if failures:quit(1);return
	record=parsed
	check(record.assertions==82 and record.failures==1,"uses immutable genuine82/1 second voyage only as scalar fixture")
	check(heights.configure_ports(JSON.parse_string(FileAccess.get_file_as_string("res://game/data/mingqi_geography.json")),true,Layout.options()),"formal native terrain configured")
	rally_completion();stationary_protect();final_navigation();protect_boundary();manual_precedence();partial_rally();recovery_priority()
	terminal_physics();terminal_inputs();terminal_gates();terminal_capability_updates();runtime_stop_save()
	var out={"assertions":assertions,"failures":failures,"encounterSha256":FileAccess.get_sha256("res://modules/naval_simulation/encounter.gd"),"inputSha256":FileAccess.get_sha256(INPUT),"mode":"Focused real Encounter control lifecycle tests; short native fixtures only, no full-voyage acceptance","diagnostics":diagnostics}
	var destination="res://build/second-aftermath-work/fleet-arrival-controls/"
	DirAccess.make_dir_recursive_absolute(destination)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):destination+=argument.trim_prefix("--report=")
	if destination.ends_with("/"):destination+="unit.json"
	var file=FileAccess.open(destination,FileAccess.WRITE);file.store_string(JSON.stringify(out,"\t",false,true));file.close()
	print("FLEET_ARRIVAL_CONTROLS_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
