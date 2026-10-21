extends "res://tests/test_wet_route_egress.gd"
# Recorded horizontal scalars plus an explicitly hypothetical in-progress tack.
# Historical tack/previous-controller internals are not present in the record.
func prepared(expired: bool=true) -> RefCounted:
	var e=fixture(989.8);var ship: Dictionary=e._ship(ID);var p: Dictionary=e._visual(ship);var motion: Dictionary=ship.core.get_snapshot()
	e.tick=6000
	ship.previous={"position":{"x":p.position.x-p.velocity.x/60.0,"z":p.position.z-p.velocity.z/60.0},"heading":p.heading-motion.yawRate/60.0}
	ship.tack={"side":1,"windFrom":PI,"settledTicks":0,"legTicks":0}
	ship.route={"target":ship.state.navigation.duplicate(true),"points":[ship.state.navigation.duplicate(true)],"checked":e.tick-1801 if expired else e.tick,"distance":e._distance(ship.state.navigation,p.position),"draft":ship.state.dimensions.draft,"retryAt":0,"failures":0}
	return e
func _initialize() -> void:
	record=JSON.parse_string(FileAccess.get_file_as_string(INPUT))
	check(heights.configure_ports(JSON.parse_string(FileAccess.get_file_as_string("res://game/data/mingqi_geography.json")),true,RECORDED_LAYOUT),"historical recorded terrain configured")
	var fresh=prepared(false);var expired=prepared(true)
	fresh._autopilot(fresh._ship(ID));expired._autopilot(expired._ship(ID))
	check(fresh._ship(ID).tack.side==1,"fresh route keeps explicitly hypothetical+1 unfinished tack")
	check(expired._ship(ID).tack.side==fresh._ship(ID).tack.side,"same safe goal/leg/draft replan keeps unfinished tack side")
	check(expired._ship(ID).state.rudder==fresh._ship(ID).state.rudder,"only checked expiry cannot reverse helm on equivalent leg")
	for cause in ["goal","leg","draft","failure","empty","manual","tactical"]:
		var e=prepared();var ship: Dictionary=e._ship(ID)
		ship.tack.legTicks=123;ship.tack.settledTicks=30
		match cause:
			"goal":ship.route.target={"x":-61.0,"z":320.0}
			"leg":ship.route.points=[{"x":0.0,"z":350.0}]
			"draft":ship.route.draft+=0.1
			"failure":e.config.sampleTerrainHeight=func(_x,_z):return -0.1
			"empty":ship.route.points=[]
			"manual":ship.approachManualOverride=ship.state.navigation.duplicate(true)
			"tactical":check(e.issue_order({"id":"tack-rally","shipIds":[ID],"intent":{"kind":"rally","point":ship.state.navigation.duplicate(true)}}).ok,"actual tactical owner accepts replacement")
		if not ship.route.points.is_empty():ship.route.distance=e._distance(ship.route.points[0],e._visual(ship).position)
		e._autopilot(ship)
		check(not ship.has("tack") or ship.tack.legTicks==0,cause+" does not retain unfinished old leg counters")
	var e=prepared();var ship: Dictionary=e._ship(ID);var p: Dictionary=e._visual(ship)
	ship.tack.legTicks=123;ship.tack.settledTicks=30
	e._autopilot(ship)
	check(ship.tack.side==1 and ship.tack.legTicks==123,"same refresh preserves unfinished leg counter")
	check(ship.tack.settledTicks==0,"original controller still resets unaligned settling counter normally")
	var goal: Dictionary=ship.state.navigation.duplicate(true)
	var node={"x":p.position.x+cos(4*PI/3)*100,"z":p.position.z+sin(4*PI/3)*100}
	var original=e.config.sampleTerrainHeight
	e.config.sampleTerrainHeight=func(x,z):return -0.1 if absf(x-node.x)<1 and absf(z-node.z)<1 else original.call(x,z)
	check(not e._keep_tack_after_replan(ship,ship.route,{"ok":true,"points":[goal]},goal,p),"newly dry retained-side150m corridor invalidates preservation")
	e=prepared();ship=e._ship(ID)
	check(e.set_wind({"direction":{"x":cos(PI+PI/6),"y":sin(PI+PI/6)},"speed":12.0}).ok,"real wind API accepts changed direction")
	e._autopilot(ship)
	check(not ship.has("tack") or absf(wrapf(ship.tack.windFrom-PI,-PI,PI))>PI/18,"existing wind-change gate discards old tack wind identity")
	e=prepared(false);ship=e._ship(ID);p=e._visual(ship)
	ship.tack.legTicks=123;ship.route.points=[{"x":p.position.x,"z":p.position.z},ship.state.navigation.duplicate(true)]
	e._autopilot(ship)
	check(ship.route.points.size()==1 and (not ship.has("tack") or ship.tack.legTicks==0),"ordinary45m waypoint pop still clears old tack")
	e=prepared(true);ship=e._ship(ID);p=e._visual(ship)
	ship.tack.legTicks=123;ship.route.points=[{"x":p.position.x,"z":p.position.z},ship.state.navigation.duplicate(true)];ship.route.distance=0.0
	e._autopilot(ship)
	check(ship.route.points.size()==1 and (not ship.has("tack") or ship.tack.legTicks==0),"expired replan cannot hide an old45m waypoint advancement")
	# Real native short segment checks that preserve does not disable advancing
	# physics or replace controls with an invented assist/controller.
	e=prepared();ship=e._ship(ID)
	var start: Dictionary=e._visual(ship).position.duplicate(true)
	for index in 60:e.step(1.0/60.0)
	check(e._distance(start,e._visual(ship).position)>0.5,"actual native sailing continues after equivalent replan")
	check(ship.tack.side==1,"unfinished hypothesis+1 survives actual short segment")
	var report={"assertions":assertions,"failures":failures,"scope":"recorded scalars plus hypothetical unfinished+1 tack; historical side/previous state unknown; no campaign replay","baselineSha256":FileAccess.get_sha256("res://build/port-approach-work/tack-route-replan/encounter.preedit.gd"),"encounterSha256":FileAccess.get_sha256("res://modules/naval_simulation/encounter.gd"),"fixtureSha256":FileAccess.get_sha256(INPUT)}
	var output=FileAccess.open("res://build/port-approach-work/tack-route-replan/unit.json",FileAccess.WRITE);output.store_string(JSON.stringify(report,"\t"));output.close()
	print("TACK_ROUTE_REPLAN assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
