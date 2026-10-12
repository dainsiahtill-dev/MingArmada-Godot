extends SceneTree
# Recorded geometry becomes a fresh real Encounter fixture, not a historical
# controller replay or evidence of a completed campaign voyage.
const Encounter = preload("res://modules/naval_simulation/encounter.gd")
const Height = preload("res://modules/scene_engine/terrain/height_field.gd")
const Layout = preload("res://game/scenes/common/reference_geography.gd")
const Catalog = preload("res://game/domain/mingqi/catalog.gd")
const Sailing = preload("res://game/runtime/sailing_simulation.gd")
const Campaign = preload("res://game/domain/mingqi/campaign.gd")
const Runtime = preload("res://game/runtime/mingqi_runtime.gd")
const ID = "mingqi-1650-grain-a"
const INPUT = "res://docs/migration/evidence/opening-story/journey-formal-manual-fire-return.json"
var assertions = 0
var failures = 0
var height_field = Height.new()
var actual: Dictionary
func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ", label)
func fixture(seconds: float = 750.0) -> RefCounted:
	var stage: Dictionary
	for value: Dictionary in actual.stages:
		if value.time == seconds: stage = value; break
	var setups: Array = []
	for frame: Dictionary in stage.ships:
		var metadata: Dictionary
		for saved: Dictionary in actual.final.naval.ships:
			if saved.id == frame.id: metadata = saved; break
		var profile: Dictionary = Catalog.DATA.profiles[actual.final.campaign.vessels[frame.id].profileId]
		var units = 20 if frame.id == ID else 0
		var stats: Dictionary = metadata.stats.duplicate(true)
		stats.draftMeters = profile.baseDraftMeters + units * profile.cargoDraftMetersPerUnit
		stats.cargoMass = units * 100.0
		setups.append({"id":frame.id,"kind":metadata.kind,"team":metadata.team,"position":frame.position,"heading":frame.heading,"hull":frame.hull,"sail":frame.sail,"crew":frame.crew,"sailDeployment":0.0,"stats":stats})
	var e = Encounter.new({"mode":"continuous","routePlanning":true,"referenceHandling":true,"playerId":ID,"controllableShipIds":[ID],"hostileTargets":{},"sampleTerrainHeight":Callable(height_field,"sample_height"),"oceanWaves":[],"wind":actual.final.naval.wind,"ships":setups})
	check(e.last_error.is_empty(), "recorded geometry builds real native Encounter")
	for frame: Dictionary in stage.ships:
		var ship: Dictionary = e._ship(frame.id)
		# Initial fixture velocity retains recorded lateral motion. Never used on
		# a running campaign, saved game, or authoritative journey.
		ship.core.correct_horizontal_motion(frame.position,frame.velocity)
		ship.previous = e._visual(ship)
	check(e.navigate(ID,{"x":282.1499288930165,"z":107.48568719733964}).ok,"real navigation accepts fixture destination")
	return e
func request(e: RefCounted) -> Dictionary: return e._autopilot(e._ship(ID))
func reconcile_goal(e: RefCounted, goal: Dictionary) -> void:
	var setups: Array = []
	for ship: Dictionary in e.ships:
		var s: Dictionary = ship.state
		var p: Dictionary = ship.core.get_snapshot()
		setups.append({"id":s.id,"kind":s.kind,"team":"player" if s.id==ID else s.team,"position":p.position,"heading":p.heading,"hull":s.hull,"sail":s.sail,"crew":s.crew,"rudder":s.rudder,"sailDeployment":s.sailDeployment,"stats":s.stats})
	var policy: Dictionary=e.policy.duplicate(true);policy.navigation={ID:goal}
	check(e.reconcileShips(setups,policy).ok,"actual atomic reconciliation installs authorized goal")
func small_turn() -> RefCounted:
	var e=fixture();request(e)
	check(e.update_ship_stats(ID,{"crew":30,"stats":{"cargoMass":0.0}}).ok,"full-power native small-error fixture")
	var ship: Dictionary=e._ship(ID);var p: Dictionary=e._visual(ship)
	var course=atan2(ship.state.navigation.z-p.position.z,ship.state.navigation.x-p.position.x)
	ship.core.correct_horizontal_motion(p.position,{"x":0.0,"z":0.0},course-10*PI/180)
	ship.previous=e._visual(ship)
	return e
func review_regressions() -> void:
	var e=fixture();e.navigate(ID,null)
	var simulation=Sailing.new(e);simulation.advance(1.0/60.0)
	var target={"x":282.1499288930165,"z":107.48568719733964}
	reconcile_goal(e,target)
	check(not request(e).is_empty(),"P2 idle Sailing controls followed by actual reconcile can acquire recovery")
	e=fixture();request(e);var state: Dictionary=e._ship(ID).state
	e.command({"type":"controls","shipId":ID,"rudder":state.rudder,"sailDeployment":state.sailDeployment,"sailAngle":state.sailAngle,"autoTrim":state.autoTrim})
	check(not request(e).is_empty(),"P2 no-op controls do not cancel navigation ownership")
	e.command({"type":"controls","shipId":ID,"rudder":-1.0,"sailDeployment":0.0});reconcile_goal(e,target)
	check(request(e).is_empty(),"P2 deliberate same-goal override survives routine reconciliation")
	var next_target=target.duplicate();next_target.x+=0.1;reconcile_goal(e,next_target)
	check(not request(e).is_empty(),"P2 authorized new goal clears only obsolete manual fence")
	# Full Runtime startup/select/idle/depart/Bridge path. This never supplies a
	# native navigation command, so the idle-fence regression cannot be hidden.
	var campaign=Campaign.new(1650,"regression","approach-runtime")
	check(campaign.command({"type":"accept-convoy","commandId":"accept","expectedRevision":0}).ok,"runtime fixture loads actual contract")
	var runtime=Runtime.new();check(runtime.configure(func(_x: float,_z: float)->float:return -24.0,campaign).ok,"actual Runtime configured for idle departure")
	var flag="approach-runtime-flagship"
	check(runtime.simulation.encounter.set_player_id(flag).ok,"actual idle flagship selected")
	runtime.simulation.refresh_snapshot();runtime.advance(1.0/60.0)
	check(runtime.command({"type":"depart","commandId":"depart","expectedRevision":runtime.campaign.snapshot().revision}).ok,"actual Runtime departs after idle input tick")
	check(runtime.bridge.sync().ok,"actual Bridge reconciles departed goals")
	check(not runtime.simulation.encounter._ship(flag).get("approachManualOverride",false),"P2 idle selected runtime vessel does not carry poisoned manual fence after departure")
	runtime.dispose()
	e=small_turn();request(e)
	var horizon: float=e._ship(ID).approachClearance.get("horizon",0.0)
	var elapsed=0.0
	for index in 1800:
		e.step(1.0/60.0);elapsed+=1.0/60.0
		var p: Dictionary=e._visual(e._ship(ID));var goal: Dictionary=e._ship(ID).state.navigation
		if absf(wrapf(atan2(goal.z-p.position.z,goal.x-p.position.x)-p.heading,-PI,PI))<=PI/36:break
	check(horizon>=elapsed,"P2 predicted horizon covers actual native PD ten-to-five degree turn")
	print("REVIEW_SMALL_TURN horizon=",horizon," actualSeconds=",elapsed)
	e=fixture();check(e.update_ship_stats(ID,{"crew":10,"stats":{"cargoMass":100000.0}}).ok,"reduced crew and loaded native timeout fixture")
	var owned=request(e)
	check(not owned.is_empty(),"reduced-power loaded turn can acquire bounded owner")
	for index in 2401:e.step(1.0/60.0)
	var timed_out=request(e)
	check(e._ship(ID).state.sailDeployment==0 and timed_out.get("targetYawRateRad",1)==0 and timed_out.get("brakeDeceleration",0)>0,"P2 forty actual seconds force neutral furled braking when slow turn remains unaligned")
	print("REVIEW_TIMEOUT actualSeconds=",e.tick/60.0," owner=",e._ship(ID).get("approachRecovery",{})," yaw=",e._ship(ID).core.get_snapshot().yawRate)
	var timeout_owner: Dictionary=e._ship(ID).get("approachRecovery",{}).duplicate(true)
	request(e)
	check(e._ship(ID).get("approachRecovery",{})==timeout_owner,"P2 timeout cannot reset ownership clock while yaw is still settling")
	e=small_turn();var own_ship: Dictionary=e._ship(ID)
	for index in 60:own_ship.core.step(1.0/60.0,{"manualAssist":{"targetYawRateRad":-4*PI/180,"maxYawAccelerationRad":8*PI/180,"powerFraction":1.0,"neutralYawDamping":0.0,"brakeDeceleration":0.2,"coastInNoGo":true,"responseRate":6.0}})
	own_ship.previous=e._visual(own_ship)
	check(own_ship.core.get_snapshot().yawRate<0,"opposing-yaw fixture uses actual solver acceleration")
	request(e)
	check(own_ship.approachClearance.get("horizon",0)==60.0,"P2 opposing-yaw actual state receives full bounded prediction interval")
	e=small_turn();var peer: Dictionary=e._ship("mingqi-1650-flagship");var position: Dictionary=e._visual(e._ship(ID)).position
	peer.core.correct_horizontal_motion({"x":position.x-110,"z":position.z},{"x":7.0,"z":0.0},0.0)
	var late_request=request(e)
	check(e._ship(ID).approachClearance.get("reason")=="predicted-peer" and e._ship(ID).state.sailDeployment==0 and late_request.get("brakeDeceleration",0)>0,"P2 late crossing within true turn interval rejects and brakes owned turn")
	for hazard in ["peer","depth"]:
		e=fixture();request(e)
		for index in 1200:e.step(1.0/60.0)
		var ship: Dictionary=e._ship(ID);var p: Dictionary=e._visual(ship)
		# Geometry fixture: the old blocker has departed, then a new hazard is
		# observed outside the current cone. This is not voyage replay evidence.
		e._ship("mingqi-1650-background-grain-01").core.correct_horizontal_motion({"x":1000.0,"z":1000.0},{"x":0.0,"z":0.0})
		var error=absf(wrapf(atan2(target.z-p.position.z,target.x-p.position.x)-p.heading,-PI,PI))
		check(error>PI/36 and error<40*PI/180 and not e._ship_ahead(ship,p,p.heading),"mid-turn hazard fixture has old cone clear and remaining5-40degrees")
		if hazard=="peer":
			peer=e._ship("mingqi-1650-flagship");peer.core.correct_horizontal_motion({"x":p.position.x-80,"z":p.position.z},{"x":5.0,"z":0.0},0.0)
		else:e.config.sampleTerrainHeight=func(_x: float,_z: float)->float:return -1.5
		var rejected=request(e)
		check(ship.state.sailDeployment==0 and rejected.get("brakeDeceleration",0)>0 and rejected.get("targetYawRateRad",1)==0,"P2 owned "+hazard+" clearance rejection stays furled with neutral bounded braking")
		if hazard=="peer":
			check(e.command({"type":"controls","shipId":ID,"rudder":-1.0,"sailDeployment":0.2}).ok,"manual helm can supersede safety holding")
			var manual_request=request(e)
			check(not ship.has("approachRecovery") and manual_request.get("brakeDeceleration",0)==0,"safety hold yields to actual manual control authority")
func _initialize() -> void:
	actual = JSON.parse_string(FileAccess.get_file_as_string(INPUT))
	check(actual.assertions == 29 and actual.failures == 0,"fixture uses immutable actual successful29/0 journey")
	check(height_field.configure_ports(JSON.parse_string(FileAccess.get_file_as_string("res://game/data/mingqi_geography.json")),true,Layout.options()),"formal depth field configured")
	review_regressions()
	var e = fixture()
	var ship: Dictionary = e._ship(ID)
	var visual: Dictionary = e._visual(ship)
	var bearing = atan2(ship.state.navigation.z-visual.position.z,ship.state.navigation.x-visual.position.x)
	check(e._ship_ahead(ship,visual,visual.heading),"750s current heading is blocked")
	check(e._feasible(ship,visual,bearing,50*PI/180),"750s destination passes existing instantaneous feasibility")
	check(not e._feasible(ship,visual,bearing+PI/3,50*PI/180) and not e._feasible(ship,visual,bearing-PI/3,50*PI/180),"750s old alternatives both fail")
	check(not request(e).is_empty() and ship.state.rudder > 0,"750s safe final destination acquires bounded turn recovery instead of permanent stop")
	print("APPROACH_INITIAL ",ship.get("approachClearance",{}))
	var moving = fixture()
	var start_heading: float = moving._visual(moving._ship(ID)).heading
	for index in 600: moving.step(1.0/60.0)
	check(moving._visual(moving._ship(ID)).heading > start_heading + 0.2,"real physics rotates recovering hull over ten seconds without pose correction")
	print("APPROACH_MOTION seconds=10 heading=",moving._visual(moving._ship(ID)).heading," speed=",moving._speed(moving._visual(moving._ship(ID))))
	var reached = false
	for index in 6600:
		moving.step(1.0/60.0)
		var current: Dictionary = moving._visual(moving._ship(ID))
		if moving._distance(current.position,moving._ship(ID).state.navigation)<=25.0 and moving._speed(current)<=0.75: reached=true;break
	check(reached,"isolated recorded750 geometry reaches unchanged25m/.75mps threshold through actual physics")
	check(moving._ship(ID).state.hull==100 and moving._ship(ID).state.crew==20,"recovery changes no hull or crew")
	print("APPROACH_FIXTURE_ARRIVAL seconds=",moving.tick/60.0," reached=",reached)
	e=fixture();request(e);check(e._ship(ID).has("approachRecovery"),"successful clearance owns a transient turn")
	check(e.command({"type":"controls","shipId":ID,"rudder":-1.0,"sailDeployment":0.0}).ok,"actual explicit controls accepted")
	check(request(e).is_empty() and not e._ship(ID).has("approachRecovery"),"explicit controls revoke recovery until new navigation")
	e=fixture();request(e);e.navigate(ID,null);e.step(1.0/60.0)
	check(not e._ship(ID).has("approachRecovery"),"cancelled navigation discards transient owner")
	e=fixture();request(e);e.policy.lockedShipIds=[ID];e.step(1.0/60.0)
	check(not e._ship(ID).has("approachRecovery"),"service lock discards transient owner before skipped autopilot")
	e=fixture();request(e);ship=e._ship(ID)
	check(not e._final_approach_clear(ship,e._visual(ship),ship.state.navigation,25.0),"actual unloading radius cannot acquire recovery")
	check(not e._final_approach_clear(ship,e._visual(ship),ship.state.navigation,55.001),"outside final55m zone cannot acquire recovery")
	e=fixture();e.policy.hostileTargets={ID:["mingqi-1650-background-grain-01"]}
	check(request(e).is_empty(),"active hostile relation cannot use arrival recovery as combat shortcut")
	e = fixture(450.0)
	check(request(e).is_empty() and e._ship(ID).state.sailDeployment == 0,"450s swept turning overlap still stops")
	for flag in ["referenceHandling","routePlanning"]:
		e = fixture();e.config[flag] = false
		check(request(e).is_empty(),"opted-out path retains blocked stop: "+flag)
	for gate in ["capturedShipIds","lockedShipIds","disabledMotionShipIds"]:
		e = fixture();e.policy[gate] = [ID]
		check(request(e).is_empty(),"recovery cannot bypass "+gate)
	for stat in ["crew","hull","sail"]:
		e = fixture();e._ship(ID).state[stat] = 0
		check(request(e).is_empty(),"recovery requires operational "+stat)
	e = fixture();e._ship(ID).manualHandling = {"mode":"assisted","turnIntent":-1.0,"braking":false}
	check(request(e).is_empty(),"manual handling retains ownership")
	e = fixture();check(e.issue_order({"id":"test-rally","shipIds":[ID],"intent":{"kind":"rally","point":e._ship(ID).state.navigation}}).ok,"real tactical order accepted")
	check(request(e).is_empty(),"active tactical order retains ownership")
	e = fixture();ship = e._ship(ID);visual=e._visual(ship);ship.core.correct_horizontal_motion(visual.position,{"x":1.3,"z":0.0})
	check(request(e).is_empty(),"fast navigation cannot enter final recovery")
	e = fixture();e._ship(ID).state.navigation={"x":285.0,"z":250.0}
	check(request(e).is_empty(),"remote target cannot enter final recovery")
	e = fixture();ship=e._ship(ID);ship.route={"target":ship.state.navigation.duplicate(),"points":[ship.state.navigation.duplicate(),{"x":500.0,"z":500.0}],"draft":1.6,"checked":0,"distance":27.4,"retryAt":0}
	# route pops near intermediate points by design; use a remote first point.
	ship.route.points[0]={"x":285.0,"z":150.0}
	check(request(e).is_empty(),"intermediate route cannot enter final recovery")
	e = fixture();e.wind.direction={"x":0.0,"y":1.0}
	var wind_assist=request(e);ship=e._ship(ID);visual=e._visual(ship)
	var goal_course=atan2(ship.state.navigation.z-visual.position.z,ship.state.navigation.x-visual.position.x)
	var wind_from=atan2(e.wind.direction.y,e.wind.direction.x);var physics: Dictionary=ship.core.get_config()
	var goal_angle=absf(e._wrap(goal_course-wind_from))
	check(absf(goal_angle*180/PI-10.8354658776414)<1e-6 and goal_angle<physics.noGoZoneDeg*PI/180,"unchanged destination remains inside wind no-go")
	check(not e._final_approach_clear(ship,visual,ship.state.navigation,e._distance(ship.state.navigation,visual.position)),"wind no-go still rejects final approach clearance")
	check(not ship.has("approachRecovery") and not ship.has("wetRouteEgress"),"wind no-go cannot acquire approach or egress owner")
	var ordinary_course=wind_from+ship.tack.side*PI/3
	check(absf(e._wrap(ordinary_course-5*PI/6))<1e-9 and absf(e._wrap(ordinary_course-wind_from))>=(physics.noGoZoneDeg+physics.noGoFadeDeg)*PI/180 and e._wet_ahead(ship,ship.tack.side,wind_from,visual),"ordinary150degree tack remains wet and outside no-go")
	var ordinary_budget=e.Manual.build(ship.state.kind,ship.state.rudder,e._speed(visual),ship.state.crew/ship.state.maxCrew,ship.state.hull/ship.state.maxHull,ship.state.sail/ship.state.maxSail,false,ship.state.sailDeployment,true)
	check(wind_assist.is_empty() or wind_assist==ordinary_budget,"ordinary tack steerage retains existing bounded Manual budget")
	for depth in [2.0,-1.5]:
		e=fixture();e.config.sampleTerrainHeight=func(x: float,z: float)->float:return depth if x>277 and x<280 and z>89 and z<92 else -24.0
		check(request(e).is_empty(),"swept hull rejects dry or insufficient loaded depth "+str(depth))
	e=fixture();var peer: Dictionary=e._ship("mingqi-1650-flagship");peer.core.correct_horizontal_motion({"x":260.0,"z":40.0},{"x":0.0,"z":3.0},PI/2)
	check(request(e).is_empty(),"currently clear peer crossing during turn rejects recovery")
	print("PORT_APPROACH_RECOVERY_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
