extends SceneTree
## Deterministic test-only voyage fixtures; never evidence of the player's voyage.
const Campaign = preload("res://game/domain/mingqi/campaign.gd")
const Encounter = preload("res://modules/naval_simulation/encounter.gd")
const Simulation = preload("res://game/runtime/sailing_simulation.gd")
const Bridge = preload("res://game/runtime/near_field_bridge.gd")
const Runtime = preload("res://game/runtime/mingqi_runtime.gd")
var assertions := 0
var failures := 0
func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ", detail)
func ship(f: Dictionary, id: String) -> Dictionary:
	for row: Dictionary in f.encounter.snapshot().ships:
		if row.id == id: return row
	return {}
func fixture(speed: float = 0.2, distance: float = 22.0, heading: float = 0.0) -> Dictionary:
	var c := Campaign.new(1650,"泊船测试船长","berth-unit")
	check(c.command({"type":"accept-convoy","commandId":"accept","expectedRevision":0}).ok,"real lease loads the two original transports")
	check(c.command({"type":"depart","commandId":"depart","expectedRevision":c.snapshot().revision}).ok,"real leased voyage departs")
	var port: Dictionary = c._state.ports.kinmen.position
	for suffix in ["grain-a","grain-b"]:
		var v: Dictionary = c._state.vessels["berth-unit-"+suffix]
		v.pose.position = {"x":port.x+(-distance if suffix=="grain-a" else distance),"z":port.z}
		v.pose.heading = heading; v.pose.speed = speed; v.controls.sailDeployment = 0.3
	# Native fixture pose is established before startup, never teleported live.
	var epoch: String = c.allocate_native_epoch()
	var state: Dictionary = c.snapshot()
	var ids: Array = state.vessels.keys().filter(func(id): return state.vessels[id].ownerId != "enemy")
	var setups: Array = ids.map(func(id): return c.near_field_setup(state.vessels[id],"player" if state.vessels[id].profileId in ["flagship","fast"] or state.vessels[id].ownerId=="captain" else "neutral"))
	var policy: Dictionary = c.native_policy(ids)
	var e := Encounter.new({"mode":"continuous","routePlanning":true,"battleId":epoch,"playerId":state.flagshipId,"ships":setups,"controllableShipIds":policy.controllableShipIds,"hostileTargets":policy.hostileTargets,"sampleTerrainHeight":func(_x: float,_z: float)->float:return -24.0,"oceanWaves":[],"wind":{"direction":{"x":1.0,"y":0.0},"speed":12.0}})
	check(e.last_error.is_empty(),"test voyage builds the real continuous encounter")
	var s := Simulation.new(e)
	var b := Bridge.new(c,s)
	check(c.project_native(b.command_context().native).ok,"fresh native authority projects transactionally")
	for suffix in ["grain-a","grain-b"]:
		check(e.navigate("berth-unit-"+suffix,port).ok,"actual native final-port navigation is active before arrival")
	return {"campaign":c,"encounter":e,"simulation":s,"bridge":b,"id":"berth-unit-grain-a","other":"berth-unit-grain-b"}
func arrive(f: Dictionary) -> void:
	var before: Dictionary = f.campaign.snapshot()
	check(f.bridge.sync().ok,"first real native observation completes unloading")
	var after: Dictionary = f.campaign.snapshot()
	for id: String in [f.id,f.other]:
		check(after.voyages[id+"-voyage"].status=="arrived" and after.vessels[id].cargo.grain==0,"authoritative voyage arrived with actual unloaded cargo")
		check(not ship(f,id).has("navigation") and not f.encounter.isAnchored(id),"arrival clears old port navigation before later berthing")
	check(after.ports.kinmen.stock.grain==before.ports.kinmen.stock.grain+40,"actual unloading conserves all 40 grain")
func close(f: Dictionary) -> void: f.bridge.dispose()
func position(f: Dictionary, id: String) -> Vector2:
	var p: Dictionary = ship(f,id).visual.position
	return Vector2(p.x,p.z)
func same(a: Variant, b: Variant) -> bool:
	if typeof(a) in [TYPE_INT,TYPE_FLOAT] and typeof(b) in [TYPE_INT,TYPE_FLOAT]: return absf(float(a)-float(b))<0.000001
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return false
		for key in a:
			if not b.has(key) or not same(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size(): return false
		for i in a.size():
			if not same(a[i],b[i]): return false
		return true
	return a==b
func preserve_business(before: Dictionary, after: Dictionary, detail: String) -> void:
	for key in ["ports","settlements","people","captain","debt","reputations","contracts","prizes","casualtyOrdinals","chronicle"]:
		check(before[key]==after[key],detail+": "+key)
	for id in before.vessels:
		for key in ["ownerId","profileId","cargo","crew","damage"]:
			check(same(before.vessels[id][key],after.vessels[id][key]),detail+": "+id+" "+key)
func blocked_case(name: String, change: Callable) -> void:
	var f := fixture(); arrive(f); change.call(f)
	var before: Dictionary = f.campaign.snapshot(); var start := position(f,f.id)
	check(f.bridge.sync().ok,name+" allows ordinary synchronization")
	check(not f.encounter.isAnchored(f.id),name+" prevents automatic berthing")
	check(position(f,f.id)==start,name+" preserves actual position")
	check(f.campaign.snapshot().vessels[f.id].cargo==before.vessels[f.id].cargo,name+" preserves cargo")
	close(f)
func automatic_arrival() -> Dictionary:
	var f := fixture(0.2,25.01,0.4)
	check(f.bridge.sync().ok and f.campaign.snapshot().voyages[f.id+"-voyage"].status=="underway","actual bridge projects automatic voyage before reaching arrival range")
	var port: Dictionary=f.campaign.snapshot().ports.kinmen.position
	var reached := false
	for tick in 120:
		f.encounter.step(1.0/60.0)
		var row: Dictionary=ship(f,f.id)
		if Vector2(row.visual.position.x-port.x,row.visual.position.z-port.z).length()<=25.0 and Vector2(row.visual.velocity.x,row.visual.velocity.z).length()<=0.75:
			reached=true; break
	var residual: Dictionary=ship(f,f.id)
	check(reached and f.encounter.snapshot().tick>0 and absf(residual.rudder)>0.01,"real automatic navigation enters genuine arrival range with nonzero residual rudder")
	return f
func _initialize() -> void:
	# Real voyage projection and native ticks leave autopilot rudder at arrival.
	for method in ["sync","reconcile"]:
		var automatic := automatic_arrival()
		check(automatic.bridge.call(method).ok,"real autopilot arrival transaction is accepted")
		check(automatic.campaign.snapshot().voyages[automatic.id+"-voyage"].status=="arrived" and automatic.campaign.snapshot().vessels[automatic.id].cargo.grain==0,"real autopilot observation actually unloads the authoritative voyage")
		check(ship(automatic,automatic.id).rudder==0 and automatic.campaign.snapshot().vessels[automatic.id].controls.rudder==0,"completed autonomous arrival neutralizes its native and business rudder")
		var berth_position := position(automatic,automatic.id)
		check(automatic.bridge.call(method).ok and automatic.encounter.isAnchored(automatic.id) and position(automatic,automatic.id)==berth_position,"next safe observation actually berths after real residual autopilot control")
		close(automatic)
	var controlled := automatic_arrival()
	check(controlled.encounter.command({"type":"controls","shipId":controlled.id,"rudder":0.25,"sailDeployment":0.0}).ok,"actual helm command supersedes residual autopilot control before unloading")
	check(controlled.bridge.sync().ok and ship(controlled,controlled.id).rudder==0.25 and controlled.campaign.snapshot().vessels[controlled.id].controls.rudder==0.25,"genuine arrival retains newly commanded native and business rudder")
	check(controlled.bridge.sync().ok and not controlled.encounter.isAnchored(controlled.id),"new helm command remains protected after arrival")
	close(controlled)
	controlled=automatic_arrival()
	check(controlled.encounter.command({"type":"controls","shipId":controlled.id,"rudder":0.0,"sailDeployment":0.4}).ok,"actual sail-only command supersedes autopilot before unloading")
	check(controlled.bridge.sync().ok and ship(controlled,controlled.id).sailDeployment==0.4 and controlled.campaign.snapshot().vessels[controlled.id].controls.sailDeployment==0.4,"first genuine arrival retains new native and business sail-only command")
	check(controlled.bridge.sync().ok and not controlled.encounter.isAnchored(controlled.id),"new sail-only command cannot become an automatic berth on later sync")
	close(controlled)
	controlled=automatic_arrival()
	var port: Dictionary=controlled.campaign.snapshot().ports.kinmen.position
	var first_target := {"x":port.x+150,"z":port.z+120}
	check(controlled.encounter.navigate(controlled.id,first_target).ok,"native navigation changes destination just before genuine arrival")
	check(controlled.bridge.sync().ok and ship(controlled,controlled.id).get("navigation")==first_target,"first genuine arrival preserves an explicit different destination")
	check(controlled.bridge.sync().ok and not controlled.encounter.isAnchored(controlled.id),"new destination remains protected on later arrival sync")
	close(controlled)
	controlled=automatic_arrival()
	port=controlled.campaign.snapshot().ports.kinmen.position
	var rally := {"id":"first-arrival-order","shipIds":[controlled.id],"intent":{"kind":"rally","point":{"x":port.x,"z":port.z}}}
	var issued: Dictionary=controlled.encounter.issueOrder(rally)
	check(issued.ok and controlled.encounter.hasActiveOrder(controlled.id),"real active order owns controls at genuine arrival: "+JSON.stringify(issued))
	var rudder: float=ship(controlled,controlled.id).rudder
	check(controlled.bridge.sync().ok and controlled.encounter.hasActiveOrder(controlled.id) and ship(controlled,controlled.id).rudder==rudder,"genuine arrival leaves active order and its actual rudder intact")
	close(controlled)
	for invalid in ["not-an-array",["unknown"],["berth-unit-flagship"],["berth-unit-grain-a","berth-unit-grain-a"]]:
		controlled=automatic_arrival()
		var original_business: Dictionary=controlled.campaign.snapshot()
		var original_native: Dictionary=controlled.encounter.snapshot()
		var handoff: Dictionary=controlled.campaign.reconcile_near(original_native,[],controlled.bridge.near_ids(),func(vessels: Array,candidate: Dictionary):return controlled.bridge._apply(vessels,candidate),invalid)
		check(not handoff.ok and controlled.campaign.snapshot()==original_business and controlled.encounter.snapshot()==original_native,"malformed or unauthorized arrival-control identities reject atomically")
		close(controlled)
	controlled=automatic_arrival()
	check(controlled.encounter.command({"type":"controls","shipId":controlled.id,"rudder":0.25,"sailDeployment":0.0}).ok,"real explicit control advances native controls sequence")
	var original_business: Dictionary=controlled.campaign.snapshot()
	var original_native: Dictionary=controlled.encounter.snapshot()
	var handoff: Dictionary=controlled.campaign.reconcile_near(original_native,[],controlled.bridge.near_ids(),func(vessels: Array,candidate: Dictionary):return controlled.bridge._apply(vessels,candidate),[controlled.id])
	check(not handoff.ok and controlled.campaign.snapshot()==original_business and controlled.encounter.snapshot()==original_native,"domain rechecks native sequence and rejects falsely owned controls atomically")
	close(controlled)
	for fault in ["crew","navigation","tick"]:
		controlled=automatic_arrival()
		original_business=controlled.campaign.snapshot(); original_native=controlled.encounter.snapshot()
		var malformed: Dictionary=original_native.duplicate(true)
		if fault=="tick": malformed.tick="invalid"
		else:
			for row: Dictionary in malformed.ships:
				if row.id==controlled.id:
					if fault=="crew": row.crew="invalid"
					else: row.navigation={"z":0}
		handoff=controlled.campaign.reconcile_near(malformed,[],controlled.bridge.near_ids(),func(vessels: Array,candidate: Dictionary):return controlled.bridge._apply(vessels,candidate),[controlled.id])
		check(not handoff.ok and controlled.campaign.snapshot()==original_business and controlled.encounter.snapshot()==original_native,"malformed ownership observation rejects without an exception or partial handoff")
		close(controlled)
	for explicit in [false,true]:
		for bad_rows in [7,[null],[{}]]:
			controlled=automatic_arrival()
			if explicit: check(controlled.encounter.command({"type":"controls","shipId":controlled.id,"rudder":0.25,"sailDeployment":0.4}).ok,"explicit malformed-row fixture has a real newer native control sequence")
			original_business=controlled.campaign.snapshot(); original_native=controlled.encounter.snapshot()
			var observation: Dictionary=original_native.duplicate(true); observation.ships=bad_rows
			var rejected: Variant=controlled.campaign.reconcile_near(observation,[],controlled.bridge.near_ids(),func(vessels: Array,candidate: Dictionary):return controlled.bridge._apply(vessels,candidate),[] if explicit else [controlled.id],[controlled.id] if explicit else [])
			check(rejected is Dictionary and rejected.get("ok")==false,"malformed ships container or row returns ordinary ownership rejection")
			check(rejected is Dictionary and rejected.get("reason")==("unknown-or-duplicate-near-vessel" if bad_rows is Array else "invalid-near-snapshot"),"new ownership context retains normal native snapshot shape rejection")
			check(controlled.campaign.snapshot()==original_business and controlled.encounter.snapshot()==original_native,"malformed ships container or row leaves both authorities unchanged")
			close(controlled)
	for fault in ["unobserved","duplicate","epoch"]:
		controlled=automatic_arrival()
		if fault!="unobserved": check(controlled.encounter.command({"type":"controls","shipId":controlled.id,"rudder":0.0,"sailDeployment":0.4}).ok,"explicit ownership fixture observes a real new native control sequence")
		original_business=controlled.campaign.snapshot(); original_native=controlled.encounter.snapshot()
		var observation: Dictionary=original_native.duplicate(true)
		if fault=="epoch": observation.battleId="unrelated-epoch"
		var explicit_ids: Array=[controlled.id,controlled.id] if fault=="duplicate" else [controlled.id]
		handoff=controlled.campaign.reconcile_near(observation,[],controlled.bridge.near_ids(),func(vessels: Array,candidate: Dictionary):return controlled.bridge._apply(vessels,candidate),[],explicit_ids)
		check(not handoff.ok and controlled.campaign.snapshot()==original_business and controlled.encounter.snapshot()==original_native,"invalid explicit arrival ownership rejects atomically: "+fault)
		close(controlled)
	controlled=automatic_arrival()
	check(controlled.encounter.command({"type":"controls","shipId":controlled.id,"rudder":0.0,"sailDeployment":0.4}).ok,"legacy caller fixture has a real sail control")
	handoff=controlled.campaign.reconcile_near(controlled.encounter.snapshot(),[],controlled.bridge.near_ids(),func(vessels: Array,candidate: Dictionary):return controlled.bridge._apply(vessels,candidate))
	check(handoff.ok and ship(controlled,controlled.id).sailDeployment==0,"default empty ownership context retains legacy unloading sail semantics")
	close(controlled)
	controlled=automatic_arrival()
	controlled.campaign._state.vessels[controlled.other].profileId="flagship"
	original_business=controlled.campaign.snapshot(); original_native=controlled.encounter.snapshot()
	check(not controlled.bridge.sync().ok and controlled.campaign.snapshot()==original_business and controlled.encounter.snapshot()==original_native,"native rejection rolls back a newly arrived cargo and owned neutral-rudder transaction")
	close(controlled)
	# Removing the actual anchor side effect must fail these native observations.
	for method in ["sync","reconcile"]:
		var f := fixture(); arrive(f)
		var before: Dictionary = f.campaign.snapshot()
		var starts := {f.id:position(f,f.id),f.other:position(f,f.other)}
		check(f.bridge.call(method).ok,method+" applies safe merchant arrival transaction")
		for id: String in [f.id,f.other]:
			check(f.encounter.isAnchored(id),method+" actually berths original arrived leased transport")
			check(position(f,id)==starts[id],method+" anchors at actual position without teleportation")
		preserve_business(before,f.campaign.snapshot(),method+" berthing creates no business side effect")
		for tick in 600:
			f.encounter.step(1.0/60.0)
			if not f.bridge.call(method).ok: check(false,"repeated "+method+" remains valid"); break
		for id: String in [f.id,f.other]:
			check(f.encounter.isAnchored(id) and position(f,id).distance_to(starts[id])<0.01,"repeated "+method+" retains stable native berth through 10s wind")
		preserve_business(before,f.campaign.snapshot(),method+" repeated berthing does not duplicate payment reward loss or personnel")
		check(not f.encounter.isAnchored("berth-unit-background-grain-01"),"random background merchant remains in motion")
		close(f)
	# Removing a gate must stop a legitimately commanded or unauthorized vessel.
	blocked_case("live explicit navigation",func(f):
		var p: Dictionary = f.campaign.snapshot().ports.kinmen.position
		var target := {"x":p.x+150,"z":p.z+120}
		check(f.encounter.navigate(f.id,target).ok,"native manual navigation accepts explicit new destination")
		check(f.bridge.sync().ok and ship(f,f.id).get("navigation")==target,"sync preserves the player's real explicit navigation")
	)
	blocked_case("active explicit rally",func(f):
		var p: Dictionary = f.campaign.snapshot().ports.kinmen.position
		var order := {"id":"leave-port","shipIds":[f.id],"intent":{"kind":"rally","point":{"x":p.x+150,"z":p.z+120}},"issuedAt":0}
		check(f.campaign.command({"type":"assign-order","commandId":"leave-port","expectedRevision":f.campaign.snapshot().revision,"order":order},f.bridge.command_context()).ok,"real campaign command issues native rally")
		check(f.encounter.hasActiveOrder(f.id),"explicit rally remains active before sync")
	)
	blocked_case("unleased transport",func(f): f.campaign._state.settlements.erase("berth-unit-convoy-001-accept"))
	blocked_case("wrong transport owner",func(f): f.campaign._state.vessels[f.id].ownerId="independent")
	blocked_case("wrong original grain profile",func(f): f.campaign._state.vessels[f.id].profileId="grain-sails")
	blocked_case("missing voyage",func(f): f.campaign._state.vessels[f.id].voyageId=null)
	blocked_case("voyage vessel mismatch",func(f): f.campaign._state.voyages[f.id+"-voyage"].vesselId=f.other)
	blocked_case("loading voyage",func(f): f.campaign._state.voyages[f.id+"-voyage"].status="loading")
	blocked_case("underway voyage",func(f):
		f.campaign._state.voyages[f.id+"-voyage"].status="underway"
		var v: Dictionary=f.campaign._state.vessels[f.id]
		v.pose.position.x+=100
	)
	blocked_case("remaining cargo",func(f): f.campaign._state.vessels[f.id].cargo.water=1)
	blocked_case("current native authorization absent",func(f): f.encounter.policy.controllableShipIds.erase(f.id))
	blocked_case("insufficient actual able crew",func(f): check(f.encounter.updateShipStats(f.id,{"crew":7}).ok,"real native crew loss remains below original minimum of 8"))
	blocked_case("active boarding",func(f): f.campaign._state.boardings["busy"]={"status":"active","attackerId":f.id,"targetId":f.other,"participants":[]})
	blocked_case("actual rudder command",func(f): check(f.encounter.command({"type":"controls","shipId":f.id,"rudder":0.25,"sailDeployment":0.0}).ok,"real native rudder control is accepted"))
	blocked_case("actual sail command",func(f): check(f.encounter.command({"type":"controls","shipId":f.id,"rudder":0.0,"sailDeployment":0.4}).ok,"real native sail control is accepted"))
	for key in ["capturedShipIds","disabledMotionShipIds","lockedShipIds"]:
		blocked_case("current native "+key,func(f): f.encounter.policy[key]=[f.id])
	# Real native pose/speed, including the inclusive safety boundaries.
	for distance in [55.0,55.01]:
		var f := fixture(); arrive(f)
		var p: Dictionary = f.campaign.snapshot().ports.kinmen.position
		# Test-only fixture changes a native numeric state; business pose stays stale.
		f.encounter._ship(f.id).core.correct_horizontal_motion({"x":p.x-distance,"z":p.z},{"x":0.2,"z":0.0})
		check(f.bridge.sync().ok,"actual harbor distance boundary synchronizes")
		check(f.encounter.isAnchored(f.id)==(distance==55.0),"55m inclusive gate uses actual native location")
		close(f)
	for speed in [0.75,0.7501]:
		var f := fixture(speed)
		if speed>0.75:
			check(f.bridge.sync().ok,"too-fast native observation cannot unload")
			check(f.campaign.snapshot().voyages[f.id+"-voyage"].status=="underway","actual speed above 0.75 retains underway voyage")
			# Pre-existing arrival fixture still cannot substitute business speed for native.
			f.campaign._state.voyages[f.id+"-voyage"].status="arrived"; f.campaign._state.vessels[f.id].cargo.grain=0
			f.campaign._state.vessels[f.id].pose.speed=0
			check(f.encounter.navigate(f.id,null).ok,"test removes navigation without stopping native motion")
		else: arrive(f)
		check(f.bridge.sync().ok,"actual speed boundary synchronizes")
		check(f.encounter.isAnchored(f.id)==(speed==0.75),"0.75 inclusive gate uses horizontal native speed")
		close(f)
	# These policies are native fixtures, not fabricated captured prize receipts.
	for separation in [600.0,600.01]:
		var f := fixture(); arrive(f)
		var c: RefCounted = f.campaign; var live: Dictionary = ship(f,f.id)
		var enemy: Dictionary = c._state.vessels["berth-unit-enemy"]
		enemy.pose.position={"x":live.visual.position.x+separation,"z":live.visual.position.z}
		var state: Dictionary=c.snapshot(); var ids: Array=f.bridge.near_ids(); ids.append(enemy.id)
		var setups: Array=ids.map(func(id):return c.near_field_setup(state.vessels[id],"hostile" if id==enemy.id else "player" if state.vessels[id].profileId in ["flagship","fast"] or state.vessels[id].ownerId=="captain" else "neutral"))
		check(f.encounter.reconcileShips(setups,c.native_policy(ids)).ok,"live hostile enters actual native policy")
		f.bridge._near_ids=ids
		check(f.bridge.sync().ok,"hostile proximity observation synchronizes")
		check(f.encounter.isAnchored(f.id)==(separation>600.0),"live uncaptured hostile inside inclusive 600m prevents automatic berth")
		close(f)
	var f := fixture(); arrive(f)
	check(f.encounter.command({"type":"fire","side":"port","shipId":"berth-unit-flagship"}).ok and f.encounter.hasPendingAttacks(),"real flagship volley establishes pending attacks")
	check(f.bridge.sync().ok and not f.encounter.isAnchored(f.id),"pending attack blocks merchant berth without blocking ordinary sync")
	close(f)
	f=fixture(); arrive(f)
	check(f.bridge.sync().ok,"merchant fleet really berths before checking captain control")
	for id in ["berth-unit-flagship","berth-unit-fast","berth-unit-heritage"]:
		check(f.encounter.command({"type":"controls","shipId":id,"rudder":0.0,"sailDeployment":0.4}).ok,"real captain or escort helm accepts sail command")
	check(f.bridge.sync().ok,"captain and escorts synchronize beside berthed merchants")
	for id in ["berth-unit-flagship","berth-unit-fast","berth-unit-heritage"]:
		check(not f.encounter.isAnchored(id) and ship(f,id).sailDeployment==0.4,"arrival automation preserves non-merchant sail command")
	var before: Dictionary=f.campaign.snapshot()
	check(not f.campaign.command({"type":"dock","portId":"kinmen","commandId":"unsafe-dock","expectedRevision":before.revision},f.bridge.command_context()).ok and f.campaign.snapshot()==before,"berthed merchants do not substitute for actual captain docking safety")
	var runtime := Runtime.new()
	runtime.campaign=f.campaign; runtime.simulation=f.simulation; runtime.bridge=f.bridge
	var exported: Dictionary=runtime.export_save("2026-10-12T00:00:00.000Z")
	check(not exported.ok and exported.reason=="save-fleet-not-anchored:berth-unit-flagship" and not exported.has("json"),"real export_save retains full fleet safety gate beside berthed merchants")
	close(f)
	f=fixture(); arrive(f)
	check(f.encounter.updateShipStats(f.id,{"hull":0}).ok,"native test battle actually sinks the original merchant")
	check(f.bridge.sync().ok,"real native sink reaches authoritative business state")
	before=f.campaign.snapshot()
	check(before.vessels[f.id].damage.hull==0 and not before.people["steward-a"].alive and before.vessels[f.id].crew.able==0,"actual sinking retains ship crew and steward death")
	check(f.bridge.sync().ok and not f.encounter.isAnchored(f.id),"dead merchant never becomes an arrival berth")
	preserve_business(before,f.campaign.snapshot(),"repeated sync never revives actual merchant casualties")
	close(f)
	f=fixture(); arrive(f)
	f.campaign._state.works["busy"]={"status":"active","shipId":f.id}
	check(f.bridge.sync().ok and f.encounter.isAnchored(f.id),"existing active port-work service lock still controls its native ship")
	check(f.encounter.policy.lockedShipIds.has(f.id),"active port work retains its ordinary native lock authority")
	close(f)
	f=fixture(); arrive(f)
	var state: Dictionary=f.campaign.snapshot(); var native: Dictionary=f.encounter.snapshot()
	f.campaign._state.vessels[f.other].profileId="flagship"
	state=f.campaign.snapshot()
	check(not f.bridge.sync().ok,"invalid companion setup rejects whole native arrival transaction")
	check(f.campaign.snapshot()==state and f.encounter.snapshot()==native,"failed handoff leaves business and native authorities unchanged")
	close(f)
	print("ARRIVAL_BERTHING_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
