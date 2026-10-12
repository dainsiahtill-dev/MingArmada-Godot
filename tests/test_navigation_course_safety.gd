extends SceneTree
const Encounter=preload("res://modules/naval_simulation/encounter.gd")
const Physics=preload("res://modules/physics_engine/ships/ship_dynamics.gd")
const Height=preload("res://modules/scene_engine/terrain/height_field.gd")
const Layout=preload("res://game/scenes/common/reference_geography.gd")
const INPUT="res://docs/migration/evidence/opening-story/wet-route-egress/journey-second.json"
const FLAG="mingqi-1650-flagship"
const GRAIN="mingqi-1650-grain-b"
var record: Dictionary
var heights=Height.new()
var assertions=0
var failures=0
func check(ok: bool,label: String) -> void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL: ",label)
func fixture() -> RefCounted:
	var stage: Dictionary=record.stages.back()
	var setups: Array=[]
	for s: Dictionary in stage.ships:
		var native: Dictionary=s.nativeDiagnostics.duplicate(true)
		native.position=s.position;native.heading=s.heading;native.speed=0
		setups.append(native)
	var e=Encounter.new({"mode":"continuous","routePlanning":true,"referenceHandling":true,"ships":setups,"playerId":record.final.campaign.flagshipId,"controllableShipIds":stage.runtime.controllableShipIds,"hostileTargets":{},"sampleTerrainHeight":heights.sample_height,"wind":record.final.naval.wind,"oceanWaves":[]})
	check(e.last_error.is_empty(),"real recorded return scalars construct native Encounter")
	for command: Dictionary in record.commands:
		if command.input.type!="assign-order":continue
		for status: Dictionary in stage.runtime.orderStatuses:
			if status.id==command.input.order.id and status.state=="active":
				var order: Dictionary=command.input.order.duplicate(true)
				e.orders[order.id]={"order":order,"participants":order.shipIds.duplicate(),"status":status.duplicate(true)}
	for s: Dictionary in stage.ships:
		var ship: Dictionary=e._ship(s.id)
		ship.core.correct_horizontal_motion(s.position,s.velocity,s.heading);ship.core._yaw_rate=s.navigationDiagnostics.motion.yawRate
		ship.previous={"position":{"x":s.position.x-s.velocity.x/60.0,"z":s.position.z-s.velocity.z/60.0},"heading":s.heading-s.navigationDiagnostics.motion.yawRate/60.0}
		if s.navigation!=null:ship.state.navigation=s.navigation.duplicate(true)
		if s.navigationDiagnostics.route!=null:
			ship.route=s.navigationDiagnostics.route.duplicate(true);ship.route.checked=0
		ship.sailRecovery=s.navigationDiagnostics.sailRecovery;ship.lowSpeedTurn=s.navigationDiagnostics.lowSpeedTurn
	return e
func force(e: RefCounted,ship: Dictionary,heading: float) -> float:
	var s: Dictionary=ship.state;var p: Dictionary=e._visual(ship)
	var core=Physics.new()
	check(core.configure({"kind":s.kind,"position":p.position,"heading":heading,"cargoMass":s.stats.cargoMass,"draft":s.dimensions.draft,"wind":e.wind,"sailCondition":s.sail/s.maxSail,"sailPowerScale":pow(s.stats.speedMultiplier,2),"config":ship.core.get_config()}),"isolated native sail probe uses unchanged real physics")
	core.correct_horizontal_motion(p.position,p.velocity,heading)
	core.set_sail_angle(e._wrap(atan2(e.wind.direction.y*e.wind.speed+p.velocity.z,e.wind.direction.x*e.wind.speed+p.velocity.x)-heading)/2)
	core.set_sail_deployment(1)
	core._step_sail(cos(heading),sin(heading),-sin(heading),cos(heading),0.0)
	return core.get_snapshot().sailDebug.forwardForce
func _initialize() -> void:
	record=JSON.parse_string(FileAccess.get_file_as_string(INPUT))
	check(heights.configure_ports(JSON.parse_string(FileAccess.get_file_as_string("res://game/data/mingqi_geography.json")),true,Layout.options()),"formal terrain configured")
	for id in [FLAG,GRAIN]:
		var e=fixture();var ship: Dictionary=e._ship(id);var p: Dictionary=e._visual(ship)
		check(not e._wet_ahead(ship,-1,PI,p) and e._wet_ahead(ship,1,PI,p),id+" real120dry240wet reproduced")
		check(force(e,ship,7*PI/6)==0.0 and force(e,ship,4*PI/3)>40000,id+" native210 has0force and240 positive force without physics change")
		e._autopilot(ship)
		check(ship.has("tack") and ship.tack.side==1,id+" real one-wet-side selects240")
		check(ship.state.rudder>0.1,id+" real autopilot leaves210 no-go hold toward wet240")
	check(fixture().hasActiveOrder(GRAIN),"grainB return fixture retains legitimate activeRally")
	var e=fixture();var ship: Dictionary=e._ship(FLAG)
	ship.tack={"side":-1,"windFrom":PI,"settledTicks":0,"legTicks":0}
	e._autopilot(ship)
	check(ship.state.rudder>0.1,"existing dry120 tack cannot use blind+90 to settle at no-go210")
	e=fixture();ship=e._ship(FLAG);var p: Dictionary=e._visual(ship)
	e.config.sampleTerrainHeight=func(x,z):return -24.0 if sqrt(pow(x-p.position.x,2)+pow(z-p.position.z,2))<30 else -0.1
	e._autopilot(ship)
	check(ship.state.rudder==0 and ship.state.sailDeployment==0,"wet current hull with every outgoing course blocked holds neutral and furled immediately")
	for dry_side in [-1,1]:
		for closer_side in [-1,1]:
			e=fixture();ship=e._ship(FLAG);p=e._visual(ship);p.heading=PI+closer_side*0.3
			e.config.sampleTerrainHeight=func(x,z):return -0.1 if dry_side*(z-p.position.z)<-25 else -24.0
			# side+1 points south; side-1 points north. The dry half-plane is
			# chosen explicitly while the current actual footprint stays wet.
			ship.erase("tack");e._tack_course(ship,PI,p)
			check(ship.tack.side==-dry_side,"wet side wins over closer dry side permutation "+str(dry_side)+"/"+str(closer_side))
	for closer_side in [-1,1]:
		e=fixture();ship=e._ship(FLAG);p=e._visual(ship);p.heading=PI+closer_side*0.3
		e.config.sampleTerrainHeight=func(_x,_z):return -24.0
		e._tack_course(ship,PI,p)
		check(ship.tack.side==closer_side,"both wet keeps original nearest-heading tie-break "+str(closer_side))
	e=fixture();ship=e._ship(FLAG);p=e._visual(ship)
	var course: Dictionary=e._shore_course(ship,p,7*PI/6)
	var safe_wind: float=(ship.core.get_config().noGoZoneDeg+ship.core.get_config().noGoFadeDeg)*PI/180
	check(course.ok and absf(e._wrap(course.heading-PI))>=safe_wind,"unsafe210 candidate is rechecked outside unchanged no-go/fade")
	check(course.ok and force(e,ship,course.heading)>0,"checked shore choice has native positive sail force")
	var peer: Dictionary=e._ship(GRAIN)
	peer.core.correct_horizontal_motion({"x":p.position.x+cos(4*PI/3)*30,"z":p.position.z+sin(4*PI/3)*30},{"x":0.0,"z":0.0},4*PI/3)
	course=e._shore_course(ship,p,2*PI/3)
	check(not course.ok or not e._ship_ahead(ship,p,course.heading),"shore alternative cannot enter existing peer exclusion")
	e=fixture();ship=e._ship(FLAG);p=e._visual(ship)
	e.config.sampleTerrainHeight=func(_x,_z):return -24.0
	ship.tack={"side":1,"windFrom":PI,"settledTicks":0,"legTicks":123}
	e._tack_course(ship,PI,p)
	check(ship.tack.side==1 and ship.tack.legTicks==123,"valid in-progress tack and leg counter remain stable")
	check(e.set_wind({"direction":{"x":cos(PI+PI/6),"y":sin(PI+PI/6)},"speed":12.0}).ok,"changed wind uses real existing API")
	e._tack_course(ship,PI,p)
	check(absf(e._wrap(ship.tack.windFrom-PI))>PI/18,"original changed-wind tack gate still discards stale wind")
	e=fixture();ship=e._ship(FLAG);p=e._visual(ship);e.config.sampleTerrainHeight=func(_x,_z):return -24.0
	p.heading=4*PI/3;ship.previous={"position":{"x":p.position.x-cos(p.heading)*0.01,"z":p.position.z-sin(p.heading)*0.01},"heading":p.heading}
	p.velocity={"x":cos(p.heading)*1.5,"z":sin(p.heading)*1.5}
	ship.tack={"side":1,"windFrom":PI,"settledTicks":120,"legTicks":2700}
	e._tack_course(ship,PI,p)
	check(ship.tack.side==-1 and ship.tack.legTicks==0,"original completed wet tack can still switch sides")
	e=fixture();ship=e._ship(FLAG)
	check(e.navigate(FLAG,null).ok and e.command({"type":"controls","shipId":FLAG,"rudder":-0.4,"sailDeployment":0.2}).ok,"real manual takeover cancels direct navigation then supplies controls")
	e.step(1.0/60.0)
	check(not ship.state.has("navigation") and ship.state.rudder==-0.4 and ship.state.sailDeployment==0.2,"course safety does not override explicitly transferred manual controls")
	# Actual short native return segment, with reconstructed legitimate Rally
	# and unchanged recorded scalar physics. No complete campaign replay.
	e=fixture();var initial_heading: Dictionary={};var actual_wet=true
	for id in [FLAG,GRAIN]:initial_heading[id]=e._visual(e._ship(id)).heading
	for index in 1200:
		e.step(1.0/60.0)
		for id in [FLAG,GRAIN]:
			ship=e._ship(id);p=e._visual(ship)
			actual_wet=actual_wet and e._wet_hull(ship,p.position.x,p.position.z,p.heading)
	check(actual_wet,"actual twenty-second native return segment keeps both tested hulls wet")
	check(e.hasActiveOrder(GRAIN) and not e._ship(GRAIN).has("wetRouteEgress"),"legitimate activeRally retains authority without widening Egress")
	for id in [FLAG,GRAIN]:
		ship=e._ship(id);p=e._visual(ship)
		check(absf(e._wrap(p.heading-initial_heading[id]))>PI/36,id+" actual native yaw leaves old no-go heading")
		check(ship.core.get_snapshot().sailDebug.forwardForce>0,id+" actual native twenty-second sailing produces positive unmodified force")
	print("COURSE_NATIVE_SECONDS=20 flagship=",e._visual(e._ship(FLAG))," grainB=",e._visual(e._ship(GRAIN)))
	var report={"assertions":assertions,"failures":failures,"baselineSha256":FileAccess.get_sha256("res://build/port-approach-work/navigation-course-safety/encounter.preedit.gd"),"encounterSha256":FileAccess.get_sha256("res://modules/naval_simulation/encounter.gd"),"fixtureSha256":FileAccess.get_sha256(INPUT),"scope":"recorded return scalars, explicit no-tack/previous reconstruction, native20sec; no complete campaign/GPU claim"}
	var output=FileAccess.open("res://build/port-approach-work/navigation-course-safety/unit.json",FileAccess.WRITE);output.store_string(JSON.stringify(report,"\t"));output.close()
	print("NAVIGATION_COURSE_SAFETY assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
