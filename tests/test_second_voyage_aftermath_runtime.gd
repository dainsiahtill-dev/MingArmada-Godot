extends SceneTree
const Campaign=preload("res://game/domain/mingqi/campaign.gd")
const Runtime=preload("res://game/runtime/mingqi_runtime.gd")
const Story=preload("res://game/domain/mingqi/opening_story.gd")
const Codec=preload("res://game/domain/persistence/save_codec.gd")
var assertions:=0
var failures:=0
static func envelope(s: Dictionary) -> String:
	return JSON.stringify({"version":2,"campaignId":s.campaignId,"mode":"mingqi-1650","savedAtUtc":"2026-10-12T00:00:00.000Z","simulationSeconds":s.simulationSeconds,"state":s},"",false,true)
static func send(r: RefCounted,type: String,extra: Dictionary={},id: String="") -> Dictionary:
	var c={"type":type,"commandId":id if not id.is_empty() else "aftermath-"+str(r.campaign.snapshot().revision),"expectedRevision":r.campaign.snapshot().revision};c.merge(extra)
	return r.command(c)
# Legitimate domain arrival observations, followed by an actual native bridge.
# These fixtures do not claim an actual gameplay journey or acceptance return.
static func second_claim(port_id: String="forward-supply",crew_b: int=20,failed: bool=false) -> Dictionary:
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/mingqi-reference.json"))
	var c:=Campaign.new()
	if not c.restore(envelope(fixture.convoySteps[4].state)):return {"ok":false,"reason":"first-fixture"}
	var r:=Runtime.new()
	if not r.configure(func(_x: float,_z: float)->float:return -24.0,c).ok:return {"ok":false,"reason":"first-bridge"}
	if not send(r,"dock",{"portId":"kinmen"},"aftermath-first-dock").ok:r.dispose();return {"ok":false,"reason":"first-dock"}
	if not send(r,"accept-convoy",{"contractId":"convoy-002"},"aftermath-second-load").ok:r.dispose();return {"ok":false,"reason":"second-load"}
	if not send(r,"depart",{},"aftermath-second-depart").ok:r.dispose();return {"ok":false,"reason":"second-depart"}
	var observation: Dictionary=r.simulation.snapshot().duplicate(true);observation.tick+=1;observation.time+=1.0/60.0
	var target: Dictionary=c.snapshot().ports[port_id].position
	for ship in observation.ships:
		if ship.id==c.snapshot().flagshipId or ship.id.ends_with("-grain-a") or ship.id.ends_with("-grain-b"):
			ship.visual.position=target.duplicate() if ship.id==c.snapshot().flagshipId else c.snapshot().ports["forward-supply"].position.duplicate()
			ship.visual.velocity={"x":0,"z":0};ship.sailDeployment=0;ship.rudder=0
			if ship.id.ends_with("-grain-b"):ship.crew=crew_b
			if failed and ship.id.ends_with("-grain-a") or failed and ship.id.ends_with("-grain-b"):ship.hull=0;ship.crew=0
	var synced: Dictionary=c.sync_near(observation,[]);r.dispose()
	if not synced.ok:return {"ok":false,"reason":"second-arrival:"+str(synced)}
	var claimed: Dictionary=c.command({"type":"claim-convoy","contractId":"convoy-002","commandId":"aftermath-second-claim","expectedRevision":c.snapshot().revision})
	return {"ok":claimed.ok,"reason":str(claimed),"state":c.snapshot(),"claim":claimed.get("receipt",{})}
static func at_port(port_id: String="forward-supply",crew_b: int=20,failed: bool=false) -> Dictionary:
	var result=second_claim(port_id,crew_b,failed)
	if not result.ok:return result
	var c:=Campaign.new();c._state=result.state.duplicate(true);var r:=Runtime.new()
	if not r.configure(func(_x: float,_z: float)->float:return -24.0,c).ok:return {"ok":false,"reason":"second-bridge"}
	var docked=send(r,"dock",{"portId":port_id},"aftermath-second-dock")
	if not docked.ok:r.dispose();return {"ok":false,"reason":"second-dock:"+str(docked)}
	return {"ok":true,"runtime":r,"claim":result.claim}
func check(ok: bool,message: String) -> void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL: ",message)
func choice(r: RefCounted,id: String="aftermath-choice",pick: String="share-proceeds",extra: Dictionary={}) -> Dictionary:
	var fields={"sceneId":"second-return","choiceId":pick};fields.merge(extra)
	return send(r,"story-choice",fields,id)
func reject(r: RefCounted,command: Dictionary,context: Dictionary,label: String) -> void:
	var before: Dictionary=r.campaign.snapshot();var result: Dictionary=r.campaign.command(command,context)
	check(not result.ok and before==r.campaign.snapshot(),label+" rejects atomically")
func run_choices() -> void:
	check(Story.project(Campaign.new().snapshot()).scenes.size()==3,"unclaimed opening retains exactly old three scenes")
	for port in ["xiamen","kinmen","forward-supply"]:
		var made=at_port(port);check(made.ok,"legal second claim plus real native port fixture "+port+": "+made.get("reason",""))
		if not made.ok:continue
		var r: RefCounted=made.runtime;var before: Dictionary=r.campaign.snapshot();var packet: Dictionary=r.snapshot()
		check(made.claim.details.delivered==20 and made.claim.details.baseReward+made.claim.details.bonus==250,"formal second claim earns real250")
		check(packet.story.scenes.size()==4 and packet.story.scenes.back().id=="second-return","second claim appends one scene")
		check(packet.runtime.eligibility.story.get("second-return",{}).get("ok",false),"real native anchored port enables second scene")
		var result=choice(r);check(result.ok,"actual anchored second choice pays dividend "+port+": "+str(result))
		if result.ok:
			var after: Dictionary=r.campaign.snapshot();var d: Dictionary=result.receipt.details
			check(after.captain.silver==before.captain.silver-50 and after.reputations.crewSupport==min(100,before.reputations.crewSupport+4),"dividend debits real50 and clamps actual support")
			check(after.debt==before.debt and after.contracts==before.contracts and after.people==before.people,"dividend does not change principal contract or people")
			for id in before.vessels:check(after.vessels[id].crew==before.vessels[id].crew and after.vessels[id].cargo==before.vessels[id].cargo,"dividend leaves actual crew and cargo "+id)
			check(d.portId==port and d.aftermath.portWitness.anchored and d.aftermath.portWitness.position==before.vessels[before.flagshipId].pose.position,"receipt witnesses actual current port")
			var replay: Dictionary=r.command({"type":"story-choice","sceneId":"second-return","choiceId":"share-proceeds","commandId":"aftermath-choice","expectedRevision":0})
			check(replay.ok and replay.receipt==result.receipt and r.campaign.snapshot()==after,"exact command replay cannot pay twice")
			check(not choice(r,"other-command").ok and not choice(r,"other-pick","keep-capital").ok and r.campaign.snapshot()==after,"different command and alternate pick cannot choose twice")
			var decoded=Codec.decode(envelope(after));check(decoded.get("ok",false),"actual dividend save validates: "+str(decoded.get("code")))
		r.dispose()
func run_intents() -> void:
	for port in ["xiamen","kinmen","forward-supply"]:
		for pick in ["return-xiamen","keep-capital"]:
			var made=at_port(port);check(made.ok,"intent fixture "+port)
			if not made.ok:continue
			var r: RefCounted=made.runtime;var before: Dictionary=r.campaign.snapshot();var result=choice(r,"intent",pick)
			check(result.ok,"intent choice works "+port+" "+pick+": "+str(result))
			if result.ok:
				var after: Dictionary=r.campaign.snapshot()
				check(after.captain==before.captain and after.debt==before.debt and after.reputations==before.reputations,"intent has no economic or reputation effects")
				var repaid=send(r,"repay-debt",{"quantity":100},"aftermath-partial")
				check(repaid.ok==(port=="xiamen"),"real repayment only available in xiamen")
				if port=="xiamen" and repaid.ok:
					check(r.campaign.snapshot().debt.principal==300 and r.campaign.snapshot().reputations.merchantCredit==before.reputations.merchantCredit,"actual partial100 yields no payoff credit")
					var paid=send(r,"repay-debt",{"quantity":300},"aftermath-payoff")
					check(paid.ok and r.campaign.snapshot().debt.principal==0 and paid.receipt.details.creditAward==6,"real remaining300 gives one6 payoff")
			r.dispose()
func run_fences() -> void:
	var made=at_port();check(made.ok,"guard fixture valid")
	if not made.ok:return
	var r: RefCounted=made.runtime;var before: Dictionary=r.campaign.snapshot()
	var command={"type":"story-choice","sceneId":"second-return","choiceId":"share-proceeds","commandId":"guard","expectedRevision":before.revision}
	reject(r,command,{},"missing native")
	var context: Dictionary=r.bridge.command_context();context.native.isAnchored=func(_id):return false
	reject(r,command,context,"actual unanchored")
	context=r.bridge.command_context();context.native.pendingAttacks=true;reject(r,command,context,"pending real combat")
	context=r.bridge.command_context();context.native.project=func(_s,_anchors,_phase):return {"ok":false,"reason":"aftermath-test-projection-refusal"}
	reject(r,command,context,"native projection refused")
	var stale=command.duplicate(true);stale.expectedRevision-=1;reject(r,stale,r.bridge.command_context(),"stale revision")
	for field in ["portId","portWitness","native"]:
		var forged=command.duplicate(true);forged[field]="xiamen";reject(r,forged,r.bridge.command_context(),"caller supplied "+field)
	var old=command.duplicate(true);old.sceneId="first-return";old.choiceId="keep-capital";reject(r,old,r.bridge.command_context(),"old fixed kinmen scene cannot broaden to supply")
	r.campaign._state.currentPortId="xiamen";command.expectedRevision=r.campaign.snapshot().revision
	reject(r,command,r.bridge.command_context(),"fake currentPort disagrees with actual native location")
	r.campaign._state.currentPortId="unknown";reject(r,command,r.bridge.command_context(),"unknown port")
	r.campaign._state.currentPortId=null;reject(r,command,r.bridge.command_context(),"at sea")
	r.campaign._state.currentPortId="forward-supply";r.campaign._state.captain.silver=49;reject(r,command,r.bridge.command_context(),"insufficient50 silver")
	r.campaign._state.captain.silver=before.captain.silver
	while r.campaign._state.chronicle.size()<4096:r.campaign._state.chronicle.append(before.chronicle[0].duplicate(true))
	reject(r,command,r.bridge.command_context(),"event buffer full")
	r.dispose()
	made=at_port();check(made.ok,"live unanchored guard fixture")
	if made.ok:
		r=made.runtime
		check(not r.command({"type":"controls","rudder":0.3,"sailDeployment":0.0}).ok,"aftermath helm input respects docked authority")
		check(send(r,"depart",{},"aftermath-unanchor-depart").ok,"public departure enables legal aftermath helm fixture")
		check(r.command({"type":"controls","rudder":0.3,"sailDeployment":0.0}).ok,"actual rudder command releases native anchor")
		r.advance(1.0/60.0);before=r.campaign.snapshot()
		check(not r.simulation.encounter.isAnchored(before.flagshipId) and not r.snapshot().runtime.eligibility.story.get("second-return",{}).get("ok",false),"actual unanchored vessel rejects projected scene eligibility")
		check(not choice(r,"live-unanchored").ok and r.campaign.snapshot()==before,"actual unanchored native bridge rejects payment atomically")
		r.dispose()
	made=at_port("forward-supply",20,true);check(made.ok,"formal zero delivery claim fixture")
	if made.ok:
		r=made.runtime;before=r.campaign.snapshot();check(not choice(r).ok and before==r.campaign.snapshot(),"zero reward cannot pay dividend");check(choice(r,"zero-intent","keep-capital").ok,"failed second claim retains keep choice");r.dispose()
func _initialize() -> void:
	run_choices();run_intents();run_fences()
	print("SECOND_VOYAGE_AFTERMATH_RUNTIME_TESTS assertions=",assertions," failures=",failures)
	quit(0 if failures==0 else 1)
