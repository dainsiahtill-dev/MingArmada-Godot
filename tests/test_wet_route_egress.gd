extends SceneTree
## Frozen historical voyage regression. Its recorded unsafe-circle witnesses
## belong to the source-profile geography, not today's natural campaign map.
## Current natural egress is covered by test_natural_wet_route_egress.gd.
const Encounter=preload("res://modules/naval_simulation/encounter.gd")
const Height=preload("res://modules/scene_engine/terrain/height_field.gd")
const Layout=preload("res://game/scenes/common/reference_geography.gd")
const Planner=preload("res://modules/naval_simulation/navigation/wet_route_planner.gd")
const Egress=preload("res://modules/naval_simulation/navigation/wet_route_egress.gd")
# Frozen raw-profile layout recorded in INPUT.sourceHashes. Current source art
# grading and the natural campaign have both moved beyond this historical map.
const RECORDED_LAYOUT={"reference_islands":true,"reference_profiles":{"xiamen":"coastal2","kinmen":"cat_island","forward-supply":"virgin_islands"}}
const INPUT="res://docs/migration/evidence/opening-story/port-approach-and-voyage-clarity/journey-second-corrected.json"
const ID="mingqi-1650-grain-a"
var record: Dictionary
var heights=Height.new()
var assertions=0
var failures=0
func check(ok: bool,label: String) -> void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL: ",label)
func fixture(seconds: float=2999.8) -> RefCounted:
	var stage: Dictionary
	for frame: Dictionary in record.stages:
		if frame.simulationSeconds==seconds:stage=frame;break
	var setups: Array=[]
	for s: Dictionary in stage.ships:
		var native: Dictionary=s.nativeDiagnostics.duplicate(true)
		native.position=s.position;native.heading=s.heading;native.speed=0
		setups.append(native)
	var e=Encounter.new({"mode":"continuous","routePlanning":true,"referenceHandling":true,"ships":setups,"playerId":record.final.campaign.flagshipId,"controllableShipIds":stage.runtime.controllableShipIds,"hostileTargets":{},"sampleTerrainHeight":heights.sample_height,"wind":record.final.naval.wind,"oceanWaves":[]})
	check(e.last_error.is_empty(),"recorded scalar fixture builds real Encounter")
	for s: Dictionary in stage.ships:
		var ship: Dictionary=e._ship(s.id)
		ship.core.correct_horizontal_motion(s.position,s.velocity,s.heading)
		ship.core._yaw_rate=s.navigationDiagnostics.motion.yawRate
		ship.previous=e._visual(ship)
		if s.navigation!=null:ship.state.navigation=s.navigation.duplicate(true)
	return e
func safe_fixture() -> RefCounted:
	# Select an isolated fixture at construction, before any native step. The
	# original recorded moving-peer fixture remains intact in the first case.
	var recorded=fixture();var original: Dictionary=recorded._ship(ID);var motion: Dictionary=original.core.get_snapshot()
	var initial: Dictionary=recorded.config.duplicate(true)
	initial.ships=initial.ships.filter(func(s):return s.id==ID);initial.playerId=ID;initial.controllableShipIds=[ID]
	var e=Encounter.new(initial);var ship: Dictionary=e._ship(ID)
	check(e.last_error.is_empty(),"initial single-boat fixture uses real unchanged native physics")
	ship.state=original.state.duplicate(true)
	ship.core.correct_horizontal_motion(motion.position,motion.velocity,motion.heading);ship.core._yaw_rate=motion.yawRate;ship.previous=original.previous.duplicate(true)
	return e
func _initialize() -> void:
	record=JSON.parse_string(FileAccess.get_file_as_string(INPUT))
	check(heights.configure_ports(JSON.parse_string(FileAccess.get_file_as_string("res://game/data/mingqi_geography.json")),true,RECORDED_LAYOUT),"historical recorded raw source-profile terrain configured")
	var e=fixture();var ship: Dictionary=e._ship(ID);var p: Dictionary=e._visual(ship)
	check(e._wet_hull(ship,p.position.x,p.position.z,p.heading),"real stuck hull is wet")
	check(not Planner.new().plan(p.position,ship.state.navigation,ship.state.dimensions,heights.sample_height).ok,"unchanged original Planner rejects circle-unsafe start")
	e._autopilot(ship)
	check(ship.has("wetRouteEgress"),"wet low-speed unsafe-start gets independently owned directed connector")
	check(ship.route.points.is_empty() and ship.wetRouteEgress.node.z<p.position.z,"short connector remains separate from ordinary45m waypoint pop")
	check(ship.state.sailDeployment==0,"turn starts with furled sails")
	var original_goal: Dictionary=ship.state.navigation.duplicate(true)
	var safe_steps=true
	var no_actual_flagship_overlap=true
	var max_speed=0.0
	for i in 300:
		e.step(1.0/60.0)
		var motion: Dictionary=e._visual(ship)
		safe_steps=safe_steps and e._wet_hull(ship,motion.position.x,motion.position.z,motion.heading)
		max_speed=maxf(max_speed,e._speed(motion))
		var physical_input: Dictionary=e._egress_input(ship,motion)
		for peer_snapshot: Dictionary in physical_input.peers:
			if peer_snapshot.id=="mingqi-1650-flagship":
				no_actual_flagship_overlap=no_actual_flagship_overlap and not Egress.Clearance._moving_overlap(ship.state.dimensions,{"x":motion.position.x,"z":motion.position.z,"heading":motion.heading,"padding":0.0},peer_snapshot,0.0)
		if not ship.has("wetRouteEgress"):break
	check(safe_steps,"continuous native Encounter steps retain wet actual hull")
	check(ship.has("wetRouteEgress") and ship.wetRouteEgress.holding and ship.egressClearance.get("reason")=="predicted-peer" and ship.egressClearance.get("peerId")=="mingqi-1650-flagship","recorded moving-peer fixture triggers fresh conservative peer hold")
	check(ship.state.sailDeployment==0 and ship.state.rudder==0,"fresh predicted-peer rejection keeps furled neutral control")
	check(no_actual_flagship_overlap,"predicted259second peer envelope is not a claimed actual five-second collision")
	check(ship.state.navigation==original_goal,"actual connector does not rewrite authorized final goal")
	print("EGRESS_NATIVE ticks=",e.tick," motion=",e._visual(ship)," owner=",ship.get("wetRouteEgress")," clearance=",ship.get("egressClearance")," maxSpeed=",max_speed)
	var isolated=safe_fixture();var isolated_ship: Dictionary=isolated._ship(ID);var isolated_goal: Dictionary=isolated_ship.state.navigation.duplicate(true)
	isolated._autopilot(isolated_ship)
	check(isolated_ship.has("wetRouteEgress") and not isolated_ship.wetRouteEgress.holding and isolated._egress_input(isolated_ship,isolated._visual(isolated_ship)).peers.is_empty(),"independently constructed safe fixture starts with checked egress and no peers")
	var isolated_wet=true
	for index in 300:
		isolated.step(1.0/60.0)
		var isolated_motion: Dictionary=isolated._visual(isolated_ship)
		isolated_wet=isolated_wet and isolated._wet_hull(isolated_ship,isolated_motion.position.x,isolated_motion.position.z,isolated_motion.heading)
	check(isolated_wet and isolated_ship.has("wetRouteEgress") and not isolated_ship.wetRouteEgress.holding and isolated_ship.egressClearance.ok,"actual safe single-boat300tick turn retains fresh checked egress ownership")
	check(isolated_ship.state.navigation==isolated_goal,"independent safe turn retains original recorded authorized goal")
	for seconds in [1049.8,1064.8]:
		e=fixture(seconds);ship=e._ship(ID);p=e._visual(ship)
		e._autopilot(ship)
		check(not ship.has("wetRouteEgress"),"exact recorded "+str(seconds)+" rejects unsafe motion or turn")
	e=fixture();ship=e._ship(ID);p=e._visual(ship)
	var input: Dictionary=e._egress_input(ship,p)
	var node={"x":p.position.x,"z":p.position.z-32.0}
	var peer={"id":"crossing","position":{"x":p.position.x-80.0,"z":p.position.z-16.0},"velocity":{"x":1.0,"z":0.0},"heading":0.0,"yawRate":0.0,"dimensions":ship.state.dimensions}
	check(Egress.assess(input.own,node,[peer],heights.sample_height).get("reason")=="predicted-peer","continuous moving peer crossing rejects full connector")
	var wet_target=ship.state.navigation.duplicate(true)
	check(not Egress.plan(input.own,{"x":500.0,"z":500.0},[],func(_x,_z):return -0.1).ok,"dry target retains blocked endpoint")
	input.own.yawRate=1.0
	check(not Egress.assess(input.own,node,[],heights.sample_height).ok,"large current yaw cannot acquire connector")
	var corner_x: float=p.position.x+cos(p.heading)*18.0-sin(p.heading)*5.0
	var corner_z: float=p.position.z+sin(p.heading)*18.0+cos(p.heading)*5.0
	var patch=func(x,z):return -0.1 if absf(x-corner_x)<0.03 and absf(z-corner_z)<0.03 else -24.0
	check(not Egress._wet_envelope(ship.state.dimensions,{"x":p.position.x,"z":p.position.z,"heading":p.heading,"padding":1.0},patch,0.0),"thin shallow patch at real corner cannot hide between expanded corners")
	input.own.yawRate=0.012
	check(Egress.assess(input.own,node,[],patch).get("reason")=="current-depth","nonzero yaw cannot shift turn grid past a dry actual current corner")
	for cause in ["manual","tactical","crew","sunk","service","disabled","captured","navigation","draft"]:
		e=fixture();ship=e._ship(ID);e._autopilot(ship)
		check(ship.has("wetRouteEgress"),cause+" fixture acquired owner before revocation")
		match cause:
			"manual":e.command({"type":"controls","shipId":ID,"rudder":-1.0,"sailDeployment":0.0})
			"tactical":check(e.issue_order({"id":"egress-rally","shipIds":[ID],"intent":{"kind":"rally","point":{"x":-60.0,"z":250.0}}}).ok,"actual tactical order supersedes navigation")
			"crew":ship.state.crew=1
			"sunk":ship.sunk=true
			"service":e.policy.lockedShipIds=[ID]
			"disabled":e.policy.disabledMotionShipIds=[ID]
			"captured":e.policy.capturedShipIds=[ID]
			"navigation":e.navigate(ID,null)
			"draft":ship.state.dimensions.draft+=0.1
		e.step(1.0/60.0)
		check(not ship.has("wetRouteEgress") and ship.state.sailDeployment==0,cause+" revokes connector without reopening sails")
	for cause in ["cancel","manual","reconcile"]:
		e=fixture();ship=e._ship(ID);e._autopilot(ship)
		# Exercise an owned travel output, rather than only the initial furled turn.
		ship.state.sailDeployment=Egress.MAX_SAIL;ship.state.rudder=0.2
		if cause=="cancel":e.navigate(ID,null)
		elif cause=="manual":e.command({"type":"controls","shipId":ID,"rudder":-0.7,"sailDeployment":0.3})
		else:
			var setups: Array=[]
			for body: Dictionary in e.ships:
				var state: Dictionary=body.state;var visual: Dictionary=e._visual(body)
				setups.append({"id":state.id,"kind":state.kind,"team":state.team,"position":visual.position,"heading":visual.heading,"hull":state.hull,"sail":state.sail,"crew":state.crew,"sailDeployment":state.sailDeployment,"rudder":state.rudder,"stats":state.stats})
			var policy: Dictionary=e.policy.duplicate(true);policy.navigation={ID:null}
			check(e.reconcileShips(setups,policy).ok,"actual reconciliation removes travel goal")
		e.step(1.0/60.0)
		check(not ship.has("wetRouteEgress"),cause+" removes travel owner")
		check(ship.state.rudder==-0.7 and ship.state.sailDeployment==0.3 if cause=="manual" else ship.state.rudder==0 and ship.state.sailDeployment==0,cause+" clears old output or retains explicit new manual controls")
	e=fixture();ship=e._ship(ID);e._autopilot(ship)
	e.config.sampleTerrainHeight=func(_x,_z):return -0.1
	var held: Dictionary=e._autopilot(ship)
	check(ship.has("wetRouteEgress") and ship.wetRouteEgress.holding and ship.state.sailDeployment==0 and held.get("targetYawRateRad",1)==0 and held.get("brakeDeceleration",0)>0,"fresh depth hazard latches neutral furled braking")
	e.config.sampleTerrainHeight=heights.sample_height;e._autopilot(ship)
	check(ship.has("wetRouteEgress") and ship.wetRouteEgress.holding and ship.state.sailDeployment==0,"removed hazard does not automatically reopen sails")
	var report={"assertions":assertions,"failures":failures,"scope":"historical source-profile recorded scalar fixtures and isolated native short continuous turn; current natural campaign covered separately","encounterSha256":FileAccess.get_file_as_string("res://modules/naval_simulation/encounter.gd").sha256_text(),"moduleSha256":FileAccess.get_file_as_string("res://modules/naval_simulation/navigation/wet_route_egress.gd").sha256_text(),"fixtureSha256":FileAccess.get_file_as_string(INPUT).sha256_text()}
	var output=FileAccess.open("res://build/port-approach-work/wet-route-egress/unit.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"\t"));output.close()
	print("WET_ROUTE_EGRESS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
