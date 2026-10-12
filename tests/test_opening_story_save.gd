extends SceneTree
const Campaign=preload("res://game/domain/mingqi/campaign.gd")
const Codec=preload("res://game/domain/persistence/save_codec.gd")
const Runtime=preload("res://game/runtime/mingqi_runtime.gd")
var assertions:=0
var failures:=0
func check(ok: bool,message: String) -> void:
	assertions+=1
	if not ok: failures+=1; printerr("FAIL: ",message)
func envelope(s: Dictionary) -> String:
	return JSON.stringify({"version":2,"campaignId":s.campaignId,"mode":"mingqi-1650","savedAtUtc":"2026-10-11T00:00:00.000Z","simulationSeconds":s.simulationSeconds,"state":s},"",false,true)
func make_runtime(state: Dictionary={}) -> RefCounted:
	var c:=Campaign.new(); if not state.is_empty(): c._state=state.duplicate(true)
	var r:=Runtime.new(); check(r.configure(func(_x: float,_z: float)->float:return -24.0,c).ok,"actual native repayment bridge")
	return r
func send(r: RefCounted,type: String,extra: Dictionary,id: String) -> Dictionary:
	var c: Dictionary={"type":type,"commandId":id,"expectedRevision":r.campaign.snapshot().revision}; c.merge(extra)
	return r.campaign.command(c,r.bridge.command_context())
func reject_save(s: Dictionary,label: String) -> void:
	check(not Codec.decode(envelope(s)).get("ok",false),label)
func roundtrip(r: RefCounted,label: String) -> void:
	var state: Dictionary=r.campaign.snapshot(); var decoded: Dictionary=Codec.decode(r.campaign.serialize())
	check(decoded.get("ok",false),label+" validates: "+str(decoded.get("code")))
	if decoded.get("ok",false): check(equivalent(decoded.state,state),label+" preserves all JSON state")
func equivalent(a,b) -> bool:
	if typeof(a) in [TYPE_INT,TYPE_FLOAT] and typeof(b) in [TYPE_INT,TYPE_FLOAT]: return abs(float(a)-float(b))<=1e-12*max(1.0,abs(float(a)))
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key in a:
			if not b.has(key) or not equivalent(a[key],b[key]):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for i in a.size():
			if not equivalent(a[i],b[i]):return false
		return true
	return a==b
func _initialize() -> void:
	var r:=make_runtime()
	var partial:=send(r,"repay-debt",{"quantity":150},"part")
	check(partial.ok,"first real debt repayment supported")
	if not partial.ok: r.dispose(); finish(); return
	var after: Dictionary=r.campaign.snapshot()
	check(after.debt.principal==250 and after.captain.silver==500 and after.reputations.merchantCredit==0,"partial payment subtracts actual principal and silver without payoff award")
	check(partial.receipt.id==after.campaignId+":repay-debt:part" and partial.receipt.details.amount==150 and partial.receipt.details.beforePrincipal==400 and partial.receipt.details.afterPrincipal==250 and partial.receipt.details.creditAward==0,"repayment receipt preserves exact continuity")
	roundtrip(r,"partial payment roundtrip")
	var final:=send(r,"repay-debt",{"quantity":250},"final")
	check(final.ok,"remaining principal can be paid")
	after=r.campaign.snapshot()
	check(after.debt.principal==0 and after.captain.silver==250 and after.reputations.merchantCredit==6,"full payoff gives one credit award")
	check(final.receipt.details.creditAward==6,"payoff receipt has one credit award"); roundtrip(r,"payoff save")
	var replay: Dictionary=r.campaign.command({"type":"repay-debt","commandId":"part","expectedRevision":0,"quantity":150})
	check(replay.ok and replay.receipt==partial.receipt and r.campaign.snapshot()==after,"duplicate repayment cannot debit or award twice")
	var before: Dictionary=r.campaign.snapshot()
	check(not send(r,"repay-debt",{"quantity":1},"overpaid").ok and before==r.campaign.snapshot(),"paid debt cannot be overpaid to farm credit")
	for mutation in ["amount","beforePrincipal","afterPrincipal","creditAward","principal","duplicate-award","forged-id","order","fractional-principal"]:
		var forged: Dictionary=after.duplicate(true); var a: Dictionary=forged.settlements[partial.receipt.id].details
		match mutation:
			"amount":a.amount=149
			"beforePrincipal":a.beforePrincipal=399
			"afterPrincipal":a.afterPrincipal=249
			"creditAward":a.creditAward=6
			"principal":forged.debt.principal=1
			"duplicate-award":forged.settlements[final.receipt.id].details.creditAward=12
			"forged-id":a.portId="kinmen"
			"order":forged.chronicle.reverse()
			"fractional-principal":forged.debt.principal=0.5
		reject_save(forged,"forged repayment "+mutation+" rejected")
	r.dispose()
	r=make_runtime(); before=r.campaign.snapshot()
	check(not r.campaign.command({"type":"repay-debt","commandId":"missing-native","expectedRevision":before.revision,"quantity":10}).ok and before==r.campaign.snapshot(),"repayment requires native context")
	var context: Dictionary=r.bridge.command_context(); context.native.isAnchored=func(_id):return false
	check(not r.campaign.command({"type":"repay-debt","commandId":"not-anchored","expectedRevision":before.revision,"quantity":10},context).ok and before==r.campaign.snapshot(),"repayment requires native actual anchor")
	context=r.bridge.command_context(); context.native.project=func(_s,_a,_p):return {"ok":false,"reason":"test-refusal"}
	check(not r.campaign.command({"type":"repay-debt","commandId":"refuse","expectedRevision":before.revision,"quantity":10},context).ok and before==r.campaign.snapshot(),"repayment projection failure rolls silver and debt back")
	check(not r.campaign.command({"type":"repay-debt","commandId":"stale","expectedRevision":before.revision+1,"quantity":10},r.bridge.command_context()).ok and before==r.campaign.snapshot(),"stale repayment atomic")
	r.campaign._state.currentPortId=null; before=r.campaign.snapshot()
	check(not send(r,"repay-debt",{"quantity":10},"no-port").ok and before==r.campaign.snapshot(),"near dock without current port does not authorize repayment")
	r.dispose()
	for quantity in [0,-1,401,1.5,"10"]:
		r=make_runtime(); before=r.campaign.snapshot(); check(not send(r,"repay-debt",{"quantity":quantity},"bad").ok and r.campaign.snapshot()==before,"invalid repayment amount atomic"); r.dispose()
	r=make_runtime(); r.campaign._state.captain.silver=20; before=r.campaign.snapshot()
	check(not send(r,"repay-debt",{"quantity":21},"poor").ok and r.campaign.snapshot()==before,"insufficient money repayment atomic")
	check(not send(r,"repay-debt",{"quantity":10,"extra":true},"extra").ok and r.campaign.snapshot()==before,"repayment extra fields rejected")
	r.dispose()
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/mingqi-reference.json"))
	var states: Array=[Campaign.new().snapshot(),fixture.convoySteps[4].state]
	for choice in [[0,"old-ledger","settle-wages"],[0,"old-ledger","keep-reserve"],[1,"first-return","crew-dividend"],[1,"first-return","buy-intelligence"],[1,"first-return","keep-capital"]]:
		r=make_runtime(states[choice[0]])
		var result:=send(r,"story-choice",{"sceneId":choice[1],"choiceId":choice[2]},"choice")
		check(result.ok,"story choice save setup "+choice[2]); after=r.campaign.snapshot()
		roundtrip(r,"story receipt save roundtrip "+choice[2])
		if result.ok:
			for mutation in ["cost","choice","scene","port","effect","claim"]:
				var forged: Dictionary=after.duplicate(true); var d: Dictionary=forged.settlements[result.receipt.id].details
				match mutation:
					"cost":d.silverCost+=1
					"choice":d.choiceId="forged"
					"scene":d.sceneId="forged"
					"port":d.portId="forward-supply"
					"effect":d.reputationEffects.crewSupport+=1
					"claim":d.convoyReceiptId="forged"
				reject_save(forged,"forged story "+mutation+" rejected")
			if choice[2]=="buy-intelligence":
				var forged: Dictionary=after.duplicate(true); forged.intelligence.back().sourceId="forged"; reject_save(forged,"intelligence source must be story receipt")
				forged=after.duplicate(true); forged.settlements[result.receipt.id].details.intelligence.confidence=1; reject_save(forged,"intelligence confidence must be defined value")
		r.dispose()
	for choice in ["hire-pilot","stay-deep"]:
		r=make_runtime(); send(r,"accept-convoy",{},"accept"); check(send(r,"story-choice",{"sceneId":"pilot-plan","choiceId":choice},"pilot").ok,"pilot saved choice setup")
		roundtrip(r,"both actual pilot routes and choice receipt save roundtrip"); r.dispose()
	for lost_ships in [1,2]:
		var c:=Campaign.new(); var underway: Dictionary=fixture.convoySteps[1].state
		check(c.restore(envelope(underway)),"source departing convoy fixture is valid")
		var observation: Dictionary=fixture.convoySteps[2].native.duplicate(true)
		for ship in observation.ships:
			if ship.id==underway.campaignId+"-grain-b" or lost_ships==2 and ship.id==underway.campaignId+"-grain-a": ship.hull=0; ship.crew=0
		check(c.sync_near(observation,[]).ok,"actual domain loss and arrival transitions consume native observation")
		var claim: Dictionary=c.command({"type":"claim-convoy","contractId":"convoy-001","commandId":"loss-claim","expectedRevision":c.snapshot().revision})
		check(claim.ok and claim.receipt.details.delivered==(20 if lost_ships==1 else 0) and claim.receipt.details.lost==20*lost_ships,"partial or failed return has actual generated claim receipt")
		r=make_runtime(c.snapshot()); check(send(r,"dock",{"portId":"kinmen"},"loss-dock").ok,"surviving flagship safely docks at real kinmen native position")
		check(send(r,"story-choice",{"sceneId":"first-return","choiceId":"keep-capital"},"loss-return").ok,"actual partial or failed claim permits return dialogue")
		roundtrip(r,"actual partial or failed story and casualties save")
		var Story=load("res://game/domain/mingqi/opening_story.gd");var model: Dictionary=Story.project(r.campaign.snapshot())
		check(model.scenes[2].text[0].contains(str(20*lost_ships)) and model.scenes[2].npc.id=="lin-clerk","return reports generated losses without reviving dead steward")
		r.dispose()
	check(Codec.decode(FileAccess.get_file_as_string("res://tests/fixtures/web-save-v2.json")).get("ok",false),"old web v2 fixture remains valid")
	check(Codec.decode(fixture.convoySave).get("ok",false),"old full contract fixture remains valid")
	var malformed: Dictionary=Campaign.new().snapshot(); malformed.debt.principal=399; reject_save(malformed,"principal cannot drop without payment receipt")
	finish()
func finish() -> void:
	print("OPENING_STORY_SAVE_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
