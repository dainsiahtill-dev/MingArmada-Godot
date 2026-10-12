extends SceneTree
const Cases=preload("res://tests/test_second_voyage_aftermath_runtime.gd")
const Campaign=preload("res://game/domain/mingqi/campaign.gd")
const Codec=preload("res://game/domain/persistence/save_codec.gd")
const Runtime=preload("res://game/runtime/mingqi_runtime.gd")
var assertions:=0
var failures:=0
func check(ok: bool,message: String) -> void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL: ",message)
func reject(s: Dictionary,label: String) -> void:check(not Codec.decode(Cases.envelope(s)).get("ok",false),"forged aftermath "+label+" rejected")
func same(a,b,path: String="state") -> bool:
	if typeof(a) in [TYPE_INT,TYPE_FLOAT] and typeof(b) in [TYPE_INT,TYPE_FLOAT]:
		# Godot's JSON reader rounds this simulation fraction by 6.94e-18.
		# Currency, receipt revisions and every crew/count field remain exact.
		if path=="state.macroRemainder" or path.begins_with("state.chronicle[") and path.ends_with(".simTime"):
			return abs(float(a)-float(b))<=1e-12
		# Actual later native enemy position differs by 1.82e-12 at z=10000.
		if path.begins_with("state.vessels.") and (path.ends_with(".pose.position.x") or path.ends_with(".pose.position.z") or path.ends_with(".pose.speed")):
			return abs(float(a)-float(b))<=1e-12*max(1.0,max(abs(float(a)),abs(float(b))))
		if a!=b:printerr("ROUNDTRIP_NUMERIC_DIFF ",path," before=",String.num_scientific(a)," after=",String.num_scientific(b)," error=",String.num_scientific(abs(float(a)-float(b))))
		return a==b
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		var equal=true
		for k in a:
			if not b.has(k) or not same(a[k],b[k],path+"."+k):equal=false
		return equal
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		var equal=true
		for i in a.size():
			if not same(a[i],b[i],path+"["+str(i)+"]"):equal=false
		return equal
	return a==b
func roundtrip(s: Dictionary,label: String) -> void:
	var encoded=Codec.encode(s);check(not encoded.is_empty(),label+" actual Codec.encode succeeds")
	var decoded=Codec.decode(encoded if not encoded.is_empty() else Cases.envelope(s));check(decoded.get("ok",false),label+": "+str(decoded.get("code")))
	if decoded.get("ok",false):check(same(s,decoded.state),label+" all JSON fields equal")
func historical_cut() -> void:
	var made=Cases.at_port("forward-supply",16);check(made.ok,"prepayment legitimate casualty fixture")
	if not made.ok:return
	var r: RefCounted=made.runtime;var ship_id: String=r.campaign.snapshot().campaignId+"-grain-b"
	var care=Cases.send(r,"treat-wounded",{"shipId":ship_id,"quantity":1},"aftermath-before-treatment")
	check(care.ok,"existing real treatment starts before choice")
	var result=Cases.send(r,"story-choice",{"sceneId":"second-return","choiceId":"share-proceeds"},"historical-share")
	check(result.ok,"unrelated transport treatment does not block actual flagship dividend")
	if not result.ok:r.dispose();return
	var receipt: Dictionary=result.receipt.duplicate(true)
	roundtrip(r.campaign.snapshot(),"save during treatment with dividend")
	for i in 1801:r.advance(1.0/60.0)
	var s: Dictionary=r.campaign.snapshot()
	check(s.settlements[receipt.id]==receipt,"later treatment never rewrites historical payout buckets")
	roundtrip(s,"actual treatment completion after payout")
	var casualty_observation: Dictionary=r.simulation.snapshot().duplicate(true);casualty_observation.tick+=1;casualty_observation.time+=1.0/60.0
	for ship in casualty_observation.ships:
		if ship.id==ship_id:ship.crew=s.vessels[ship_id].crew.able-2
	check(r.campaign.sync_near(casualty_observation,[]).ok,"real domain creates later casualty from current native epoch after payout")
	s=r.campaign.snapshot();r.dispose()
	check(s.settlements[receipt.id]==receipt,"later casualty never rewrites historical payout")
	roundtrip(s,"later real casualty after payout")
	var forged=s.duplicate(true);forged.settlements[receipt.id].details.aftermath.beneficiaries[1].able=forged.vessels[ship_id].crew.able
	forged.settlements[receipt.id].details.aftermath.beneficiaries[1].wounded=forged.vessels[ship_id].crew.wounded
	reject(forged,"current buckets substituted for historical recipients")
	# Constructed native observation at another port checks historical receipt,
	# without pretending this fixture traversed the real return navigation.
	var c:=Campaign.new();c._state=s.duplicate(true)
	r=Runtime.new();check(r.configure(func(_x: float,_z: float)->float:return -24.0,c).ok,"postpayout observation bridge")
	var observation: Dictionary=r.simulation.snapshot().duplicate(true);observation.tick+=1;observation.time+=1.0/60.0
	for ship in observation.ships:
		if ship.id==s.flagshipId:ship.visual.position=s.ports.xiamen.position.duplicate(true);ship.visual.velocity={"x":0,"z":0};ship.rudder=0;ship.sailDeployment=0
	check(c.sync_near(observation,[]).ok,"formal native boundary observation updates later flag position")
	s=c.snapshot();r.dispose();c=Campaign.new();c._state=s.duplicate(true);r=Runtime.new()
	check(r.configure(func(_x: float,_z: float)->float:return -24.0,c).ok,"real native bridge rebuilds later xiamen position")
	check(Cases.send(r,"dock",{"portId":"xiamen"},"later-xiamen").ok,"actual native dock at later port")
	check(Cases.send(r,"repay-debt",{"quantity":100},"later-repay").ok,"actual later repayment independent of historical choice")
	roundtrip(r.campaign.snapshot(),"historical supply witness survives later xiamen dock and actual repayment")
	r.dispose()
func old_support_and_attachment() -> void:
	for pick in ["return-xiamen","keep-capital"]:
		var made=Cases.at_port("xiamen");check(made.ok,"legacy support fixture")
		if not made.ok:continue
		var r: RefCounted=made.runtime;r.campaign._state.reputations.crewSupport+=10
		roundtrip(r.campaign.snapshot(),"old V2 unexplained support remains legal")
		var before: Dictionary=r.campaign.snapshot()
		check(not Cases.send(r,"story-choice",{"sceneId":"second-return","choiceId":"share-proceeds"},"legacy-share").ok and r.campaign.snapshot()==before,"unexplained old support explicitly refuses new share atomically")
		var result=Cases.send(r,"story-choice",{"sceneId":"second-return","choiceId":pick},"legacy-intent")
		check(result.ok,"unexplained old support still permits zeroeffect "+pick)
		if result.ok:roundtrip(r.campaign.snapshot(),"legacy support zeroeffect choice remains legal")
		r.dispose()
	var r:=Runtime.new();check(r.configure(func(_x: float,_z: float)->float:return -24.0).ok,"old scene attachment native fixture")
	var result=Cases.send(r,"story-choice",{"sceneId":"old-ledger","choiceId":"keep-reserve"},"old-choice")
	check(result.ok,"old scene receipt remains playable")
	if result.ok:
		var s: Dictionary=r.campaign.snapshot();s.settlements[result.receipt.id].details.aftermath={}
		reject(s,"old scene cannot carry new attachment")
	r.dispose()
func held_second_claim() -> RefCounted:
	# Existing canonical enemy and domain observations build legal crew lineage.
	# This is constructed automated coverage, never an actual capture journey.
	var result=Cases.second_claim();check(result.ok,"transfer formal second claim fixture")
	if not result.ok:return null
	var s: Dictionary=result.state;var c:=Campaign.new();c._state=s.duplicate(true)
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/mingqi-reference.json"))
	var observation: Dictionary=fixture.convoySteps[7].native.duplicate(true)
	observation.battleId=s.vessels[s.flagshipId].controlsObserved.battleId
	observation.tick=s.nearTicks[s.campaignId+":"+observation.battleId]+1
	for ship in observation.ships:
		var vessel: Dictionary=s.vessels[ship.id]
		ship.controlsSequence=100+s.revision;ship.visual.position=vessel.pose.position.duplicate(true);ship.visual.heading=vessel.pose.heading;ship.visual.velocity={"x":0,"z":0}
		ship.hull=vessel.damage.hull;ship.sail=vessel.damage.sail;ship.crew=vessel.crew.able
		ship.rudder=0;ship.sailDeployment=0;ship.sailAngle=vessel.controls.sailAngle;ship.autoTrim=vessel.controls.autoTrim
		ship.ammo=vessel.combat.ammo.duplicate(true);ship.ammoType=vessel.combat.ammoType;ship.cooldownSeconds=vessel.combat.cooldownSeconds.duplicate(true)
		if ship.id==s.campaignId+"-enemy":ship.visual.position={"x":s.ports["forward-supply"].position.x+25,"z":s.ports["forward-supply"].position.z};ship.crew=0
	var synced=c.sync_near(observation,[]);check(synced.ok,"existing enemy observed casualty creates actual conservation receipt: "+str(synced))
	if not synced.ok:return null
	roundtrip(c.snapshot(),"legal enemy casualty before actual boarding")
	var r:=Runtime.new();var configured=r.configure(func(_x: float,_z: float)->float:return -24.0,c)
	check(configured.ok,"actual native bridge creates carrier and weakened existing enemy")
	if not configured.ok:r.dispose();return null
	var started=Cases.send(r,"start-boarding",{"targetId":s.campaignId+"-enemy","fromShipId":s.flagshipId},"transfer-boarding")
	check(started.ok,"actual start-boarding native command: "+str(started))
	if not started.ok:r.dispose();return null
	var boarding_id: String=c.snapshot().boardings.keys()[0]
	for point in ["bow","deck","helm"]:
		var action=Cases.send(r,"board-action",{"encounterId":boarding_id,"point":point,"action":"advance"},"transfer-advance-"+point)
		check(action.ok,"actual boarding command "+point)
		if not action.ok:r.dispose();return null
	var advanced=c.advance(60,r.bridge.near_ids(),r.bridge.command_context())
	check(advanced.ok and c.snapshot().boardings[boarding_id].status=="won","real domain boarding progression earns held prize with native projection: "+str(advanced))
	if not advanced.ok or c.snapshot().boardings[boarding_id].status!="won":r.dispose();return null
	roundtrip(c.snapshot(),"legal captured prize before cross-ship transfer")
	return r
func legitimate_transfers() -> void:
	for before_payment in [true,false]:
		var r=held_second_claim()
		if r==null:continue
		var s: Dictionary=r.campaign.snapshot();var carrier: String=s.campaignId+"-grain-a";var receipt={}
		if not before_payment:
			check(Cases.send(r,"dock",{"portId":"forward-supply"},"transfer-beforepay-dock").ok,"actual native safe dock before payment")
			var paid=Cases.send(r,"story-choice",{"sceneId":"second-return","choiceId":"share-proceeds"},"transfer-before-share")
			check(paid.ok,"actual payment before later cross-ship transfer: "+str(paid))
			if not paid.ok:r.dispose();continue
			receipt=paid.receipt.duplicate(true);roundtrip(r.campaign.snapshot(),"valid payout before later transfer")
		var allocated=Cases.send(r,"allocate-prize",{"targetId":s.campaignId+"-enemy","fromShipId":carrier,"crew":12},"real-carrier-transfer")
		check(allocated.ok,"actual native carrier-to-prize crew transfer12: "+str(allocated))
		if not allocated.ok:r.dispose();continue
		s=r.campaign.snapshot();check(s.vessels[carrier].crew.able==8,"actual transfer decreases original carrier20 to8")
		roundtrip(s,"strict V2 valid actual carrier transfer lineage")
		if before_payment:
			check(Cases.send(r,"dock",{"portId":"forward-supply"},"transfer-after-dock").ok,"actual safe dock after carrier transfer")
			var paid=Cases.send(r,"story-choice",{"sceneId":"second-return","choiceId":"share-proceeds"},"transfer-after-share")
			check(paid.ok,"actual payment after mixed carrier transfer: "+str(paid))
			if paid.ok:
				receipt=paid.receipt.duplicate(true)
				check(receipt.details.aftermath.beneficiaries.size()==1 and receipt.details.aftermath.beneficiaries[0].shipId==s.campaignId+"-grain-b" and receipt.details.aftermath.beneficiaryCount==20,"only unaffected actual carrier remains eligible after transfer")
				roundtrip(r.campaign.snapshot(),"strict V2 payout excludes transferred carrier")
		else:
			check(s.settlements[receipt.id]==receipt and receipt.details.aftermath.beneficiaryCount==40,"later real crew transfer preserves original40-person payout")
			var forged=s.duplicate(true);var a: Dictionary=forged.settlements[receipt.id].details.aftermath
			for ship in a.beneficiaries:
				if ship.shipId==carrier:ship.able=8
			a.beneficiaryCount=28;reject(forged,"posttransfer current28 replaces historical40")
		r.dispose()
func _initialize() -> void:
	check(Codec.decode(FileAccess.get_file_as_string("res://tests/fixtures/web-save-v2.json")).get("ok",false),"old web v2 remains legal")
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/mingqi-reference.json"))
	for row in [[4,"old first claim without story"],[5,"old second loading"],[8,"old second claim without aftermath"]]:
		check(Codec.decode(Cases.envelope(fixture.convoySteps[row[0]].state)).get("ok",false),row[1]+" remains legal")
	for port in ["xiamen","kinmen","forward-supply"]:
		for pick in ["share-proceeds","return-xiamen","keep-capital"]:
			var made=Cases.at_port(port);check(made.ok,"legal save fixture "+port)
			if not made.ok:continue
			var r: RefCounted=made.runtime;check(Codec.decode(r.campaign.serialize()).get("ok",false),"old second claim remains legal")
			var result=Cases.send(r,"story-choice",{"sceneId":"second-return","choiceId":pick},"save-choice")
			check(result.ok,"actual new save choice "+port+" "+pick)
			if result.ok:
				var s: Dictionary=r.campaign.snapshot();var encoded: String=r.campaign.serialize()
				check(not encoded.is_empty(),"actual campaign serialize succeeds "+port+" "+pick)
				var decoded=Codec.decode(encoded if not encoded.is_empty() else Cases.envelope(s))
				check(decoded.get("ok",false),"new choice roundtrips "+port+" "+pick+": "+str(decoded.get("code")))
				if decoded.get("ok",false):check(same(s,decoded.state),"all JSON fields preserved")
				for mutation in ["missing","unknown","unknown-details","claim","cost","revenue","port","unknown-port","position","nonfinite-position","speed","hull","anchor","attacks","boardings","hostile","flagship","silver","support-pair","support-current","award","foreign","order","revision","recipient","recipient-count","dead","duplicate-beneficiary","beneficiary-order","zero-beneficiary","prisoner-field","duplicate-command","non-share-effect"]:
					var forged=s.duplicate(true);var d: Dictionary=forged.settlements[result.receipt.id].details;var a: Dictionary=d.aftermath
					match mutation:
						"missing":d.erase("aftermath")
						"unknown":a.plannedRepayment=100
						"unknown-details":d.portWitness=a.portWitness
						"claim":d.convoyReceiptId=forged.campaignId+":convoy-001:claim"
						"cost":d.silverCost+=1
						"revenue":a.revenue+=1
						"port":d.portId="kinmen" if port!="kinmen" else "xiamen"
						"unknown-port":d.portId="unknown"
						"position":a.portWitness.position.x+=1000
						"nonfinite-position":a.portWitness.position.x=null
						"speed":a.portWitness.speed=0.76
						"hull":a.portWitness.hull=0
						"anchor":a.portWitness.anchored=false
						"attacks":a.portWitness.pendingAttacks=true
						"boardings":a.portWitness.activeBoardings=1
						"hostile":a.portWitness.hostileWithin600=true
						"flagship":a.portWitness.flagshipId=forged.campaignId+"-fast"
						"silver":a.silverAfter+=1
						"support-pair":
							if pick!="share-proceeds":continue
							a.supportBefore+=10;a.supportAfter+=10;forged.reputations.crewSupport+=10
						"support-current":
							if pick!="share-proceeds":continue
							forged.reputations.crewSupport+=1
						"award":d.reputationEffects.crewSupport+=1
						"foreign":forged.settlements[result.receipt.id].id="other:story:second-return"
						"order":forged.chronicle.reverse()
						"revision":forged.settlements[result.receipt.id].revision=forged.settlements[d.convoyReceiptId].revision
						"recipient":
							if pick!="share-proceeds":continue
							a.beneficiaries[0].shipId=forged.campaignId+"-fast"
						"recipient-count":a.beneficiaryCount+=1
						"dead":
							if pick!="share-proceeds":continue
							a.beneficiaries[0].able+=1;a.beneficiaryCount+=1
						"duplicate-beneficiary":
							if pick!="share-proceeds":continue
							a.beneficiaries.append(a.beneficiaries[0].duplicate(true));a.beneficiaryCount+=a.beneficiaries[0].able+a.beneficiaries[0].wounded
						"beneficiary-order":
							if pick!="share-proceeds":continue
							a.beneficiaries.reverse()
						"zero-beneficiary":
							if pick!="share-proceeds":continue
							a.beneficiaries=[];a.beneficiaryCount=0
						"prisoner-field":
							if pick!="share-proceeds":continue
							a.beneficiaries[0].prisoners=1
						"duplicate-command":forged.settlements[result.receipt.id].commandId=forged.settlements[d.convoyReceiptId].commandId
						"non-share-effect":
							if pick=="share-proceeds":continue
							d.silverCost=50;a.silverAfter-=50
					reject(forged,mutation+" "+pick)
			r.dispose()
	historical_cut();old_support_and_attachment();legitimate_transfers()
	print("SECOND_VOYAGE_AFTERMATH_SAVE_TESTS assertions=",assertions," failures=",failures)
	quit(0 if failures==0 else 1)
