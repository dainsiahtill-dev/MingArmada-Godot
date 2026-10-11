extends SceneTree

const Campaign = preload("res://game/domain/mingqi/campaign.gd")
const SaveCodec = preload("res://game/domain/persistence/save_codec.gd")
var failures = 0
func check(value: bool, message: String):
	if not value:
		failures += 1
		push_error(message)
func equal(a, b) -> bool:
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
		return abs(float(a)-float(b)) <= 1e-8 * max(1.0, abs(float(a)))
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not equal(a[key], b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for i in a.size():
			if not equal(a[i],b[i]): return false
		return true
	return a == b
func context_for(observation: Dictionary) -> Dictionary:
	return {"applyOrder":func(_order):return {"ok":true},"native":{"snapshot":observation.duplicate(true),"events":[],"pendingAttacks":false,"supportsPrizeRetirement":true,"validateCurrent":func():return {"ok":true},"isAnchored":func(_id):return true,"hasActiveOrder":func(_id):return false,"project":func(state,_anchors,_phase):return project_fixture(state,observation)}}
func project_fixture(state: Dictionary,observation: Dictionary) -> Dictionary:
	var ships=[]
	for v in state.vessels.values():
		var previous={}
		for s in observation.ships:
			if s.id==v.id:previous=s;break
		var ship={"id":v.id,"controlsSequence":previous.get("controlsSequence",-1)+1,"visual":{"position":v.pose.position.duplicate(),"velocity":{"x":0,"z":0},"heading":v.pose.heading},"hull":v.damage.hull,"sail":v.damage.sail,"crew":v.crew.able,"ammo":v.combat.ammo.duplicate(),"ammoType":v.combat.ammoType,"cooldownSeconds":v.combat.cooldownSeconds.duplicate()}
		ship.merge(v.controls.duplicate());ships.append(ship)
	return {"ok":true,"snapshot":{"battleId":observation.battleId,"tick":observation.tick,"time":observation.time,"ships":ships}}
func run_native_steps(c,steps: Array):
	for step in steps:
		var result={}
		if step.kind=="sync":result=c.sync_near(step.native,[])
		elif step.kind=="command":result=c.command(step.command,{} if step.native==null else context_for(step.native))
		elif step.kind=="advance":
			var ids=[]
			for ship in step.native.ships:ids.append(ship.id)
			result=c.advance(step.seconds,ids,context_for(step.native))
		if step.has("result"):check(equal(result,step.result),"business result "+str(step.get("command",{}).get("type",step.kind)))
		check(equal(c.snapshot(),step.state),"business full state "+str(step.get("command",{}).get("type",step.kind)))
func _initialize():
	var fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/mingqi-reference.json"))
	var c = Campaign.new(4294967295, "林船长", "fixture-1650")
	check(equal(c.snapshot(),fixture.initial),"initial exact source state")
	for step in fixture.steps:
		check(equal(c.command(step.command),step.result),"source result: "+step.command.type)
		check(equal(c.snapshot(),step.state),"source state: "+step.command.type)
	check(equal(c.advance(1000),fixture.advance.result),"accepted clock")
	check(equal(c.snapshot(),fixture.advance.state),"background traffic full source state")
	var before = c.snapshot()
	var detached = c.snapshot()
	detached.captain.silver = 999999
	check(equal(c.snapshot(),before),"snapshot detached")
	check(not c.command({"type":"depart","commandId":"bad","expectedRevision":c.snapshot().revision,"extra":true}).ok,"unknown command key")
	check(equal(c.snapshot(),before),"invalid command atomic")
	check(not c.advance(-1).ok,"negative clock rejected")
	var business=Campaign.new(1650,"林船长","business")
	run_native_steps(business,fixture.businessSteps)
	var business_decoded=SaveCodec.decode(fixture.businessSave)
	check(business_decoded.get("ok",false),"native decode original boarding/allocation save: "+str(business_decoded.get("code")))
	check(not business.serialize().is_empty(),"native boarding/allocation serialize")
	var care=Campaign.new()
	var care_json=JSON.stringify({"version":2,"campaignId":"care","mode":"mingqi-1650","savedAtUtc":"2026-10-11T00:00:00.000Z","simulationSeconds":0,"state":fixture.careInitial},"",false,true)
	check(care.restore(care_json),"old baseline crew fixture valid")
	run_native_steps(care,fixture.careSteps)
	check(SaveCodec.decode(fixture.careSave).get("ok",false),"native decode original completed care save")
	check(not care.serialize().is_empty(),"native completed care serialize")
	var convoy=Campaign.new(1650,"林船长","convoy")
	run_native_steps(convoy,fixture.convoySteps)
	check(SaveCodec.decode(fixture.convoySave).get("ok",false),"source two completed contracts decode")
	check(not convoy.serialize().is_empty(),"native two completed contracts serialize")
	for name in ["port","held","sale","rescue"]:
		var instance=Campaign.new()
		var state=fixture[name+"Initial"]
		check(instance.restore(JSON.stringify({"version":2,"campaignId":state.campaignId,"mode":"mingqi-1650","savedAtUtc":"2026-10-11T00:00:00.000Z","simulationSeconds":state.simulationSeconds,"state":state},"",false,true)),name+" baseline restore")
		run_native_steps(instance,fixture[name+"Steps"])
		var decoded=SaveCodec.decode(fixture[name+"Save"])
		check(decoded.get("ok",false),name+" source save decode: "+str(decoded.get("code")))
		check(not instance.serialize().is_empty(),name+" native save encode")
	var handoff=Campaign.new()
	var hs=fixture.handoff.before
	check(handoff.restore(JSON.stringify({"version":2,"campaignId":hs.campaignId,"mode":"mingqi-1650","savedAtUtc":"2026-10-11T00:00:00.000Z","simulationSeconds":hs.simulationSeconds,"state":hs},"",false,true)),"handoff baseline")
	var rejected=handoff.reconcile_near(fixture.handoff.native,[],fixture.handoff.nearIds,func(_v,_s):return {"ok":false,"reason":"test-refusal"})
	check(not rejected.ok and equal(handoff.snapshot(),hs),"handoff failure atomic")
	var hr=handoff.reconcile_near(fixture.handoff.native,[],fixture.handoff.nearIds,func(_v,_s):return {"ok":true})
	check(equal(hr,fixture.handoff.result) and equal(handoff.snapshot(),fixture.handoff.state),"source near/route handoff exact")
	check(equal(handoff.advance(fixture.handoffAdvance.seconds,fixture.handoff.nearIds),fixture.handoffAdvance.result),"route clock acceptance")
	check(equal(handoff.snapshot(),fixture.handoffAdvance.state),"actual route cargo unload source exact")
	var rejection=Campaign.new()
	check(rejection.restore(fixture.businessSave),"projection refusal baseline")
	var last=fixture.portSteps[1]
	var reject_context=context_for(last.native)
	reject_context.native.project=func(_s,_a,_p):return {"ok":false,"reason":"test-refusal"}
	var reject_state=rejection.snapshot()
	var refused=rejection.command({"type":"dock","portId":"xiamen","commandId":"refused","expectedRevision":reject_state.revision},reject_context)
	check(not refused.ok and equal(rejection.snapshot(),reject_state),"native projection refusal atomic")
	var orders=Campaign.new(1650,"林船长","orders")
	run_native_steps(orders,fixture.ordersSteps)
	check(not orders.serialize().is_empty() and SaveCodec.decode(fixture.ordersSave).get("ok",false),"all six order receipts serialize")
	for item in fixture.navigationCases:
		check(equal(c.route_for_vessel(item.route,item.vessel),item.admission),"source draft admission math")
		if item.setup!=null:check(equal(c.near_field_setup(item.vessel),item.setup),"native setup cargo100kg draft source exact")
	print("mingqi source golden: ", "PASS" if failures == 0 else "FAIL", " (",failures,")")
	quit(0 if failures == 0 else 1)
