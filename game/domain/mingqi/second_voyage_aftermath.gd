extends RefCounted
## One payment from the actual second claim; receipts own persistence and history.
const Catalog=preload("res://game/domain/mingqi/catalog.gd")
const SCENE_ID="second-return"
const CHOICES=["return-xiamen","share-proceeds","keep-capital"]
const PORTS=["xiamen","kinmen","forward-supply"]
const MAX_COUNT=9007199254740991

static func choice_definition(choice_id: String) -> Dictionary:
	if not choice_id in CHOICES:return {}
	return {"portId":null,"silverCost":0,"reputationEffects":{"crewSupport":0,"militaryTrust":0,"merchantCredit":0},"routeId":null,"buyIntelligence":false}
static func _id(state: Dictionary) -> String:return state.get("campaignId","")+":story:"+SCENE_ID
static func _count(n: Variant) -> bool:return typeof(n) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(n)) and n>=0 and n<=MAX_COUNT and n==floor(float(n))
static func _support(n: Variant) -> bool:return typeof(n) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(n)) and n>=-100 and n<=100
static func _equal(a: Variant,b: Variant) -> bool:
	if typeof(a) in [TYPE_INT,TYPE_FLOAT] and typeof(b) in [TYPE_INT,TYPE_FLOAT]:return is_finite(float(a)) and is_finite(float(b)) and a==b
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key in a:
			if not b.has(key) or not _equal(a[key],b[key]):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for i in a.size():
			if not _equal(a[i],b[i]):return false
		return true
	return typeof(a)==typeof(b) and a==b
static func _index(state: Dictionary,id: String) -> int:
	var found=-1
	for i in state.get("chronicle",[]).size():
		if state.chronicle[i].get("id")==id:
			if found!=-1:return -1
			found=i
	return found
static func _receipt(state: Dictionary) -> Dictionary:
	var r: Dictionary=state.get("settlements",{}).get(_id(state),{})
	return r if r.get("kind")=="story-choice" and r.get("details",{}).get("sceneId")==SCENE_ID else {}
static func _load(state: Dictionary) -> Dictionary:
	var r: Dictionary=state.get("settlements",{}).get(state.get("campaignId","")+"-convoy-002-accept",{})
	var d: Dictionary=r.get("details",{})
	return r if r.get("kind")=="accept-convoy" and d.get("kind")=="convoy-load" and d.get("contractId")=="convoy-002" and d.get("loaded")==20 and _index(state,r.get("id",""))>=0 else {}
static func _claim(state: Dictionary) -> Dictionary:
	var id: String=state.get("campaignId","")+":convoy-002:claim"
	var r: Dictionary=state.get("settlements",{}).get(id,{})
	var d: Dictionary=r.get("details",{});var ct: Dictionary=state.get("contracts",{}).get("convoy-002",{});var load=_load(state)
	if r.get("id")!=id or r.get("kind")!="claim-convoy" or d.get("kind")!="convoy" or d.get("contractId")!="convoy-002" or not ct.get("status") in ["settled","failed"] or ct.get("receiptId")!=id or load.is_empty():return {}
	if _index(state,id)<=_index(state,load.id) or not _count(r.get("revision")) or r.revision<=load.revision:return {}
	for field in ["loaded","delivered","pending","lost","baseReward","bonus"]:
		if not _count(d.get(field)):return {}
	if d.loaded!=20 or d.pending!=0 or d.delivered+d.lost!=20 or d.baseReward!=d.delivered*10 or d.bonus!=0 and d.bonus!=50 or d.bonus>0 and d.delivered!=20:return {}
	var delivered=0;var latest=0.0;var ids=[]
	for vid in ct.get("voyageIds",[]):
		var v: Dictionary=state.get("voyages",{}).get(vid,{})
		if v.is_empty() or not v.get("status") in ["arrived","lost"] or v.get("vesselId") in ids:return {}
		ids.append(v.vesselId)
		var arrival: Dictionary=state.settlements.get(state.campaignId+":"+vid+":arrival",{})
		if v.status=="arrived":
			var a: Dictionary=arrival.get("details",{})
			if arrival.get("kind")!="shipment-arrived" or a.get("voyageId")!=vid or a.get("vesselId")!=v.vesselId or a.get("destinationId")!="forward-supply" or not _count(a.get("grain")) or _index(state,arrival.get("id",""))<=_index(state,load.id) or _index(state,arrival.id)>=_index(state,id):return {}
			delivered+=a.grain;latest=maxf(latest,a.get("arrivedAt",INF))
	if delivered!=d.delivered or ids.size()!=load.details.ships.size():return {}
	var loaded_ids=[]
	for ship in load.details.ships:
		if not ship.get("shipId") in ids or ship.shipId in loaded_ids or not ship.shipId in [state.campaignId+"-grain-a",state.campaignId+"-grain-b"]:return {}
		loaded_ids.append(ship.shipId)
	var bonus=delivered==20 and latest<=ct.get("deadlineAt",-1)
	for pid in ct.get("criticalPersonIds",[]):
		var person_alive=false
		for person in d.get("people",[]):
			if person.get("personId")==pid:person_alive=person.get("alive",false)
		bonus=bonus and person_alive
	if d.bonus!=(50 if bonus else 0):return {}
	return r
static func _buckets(value: Variant) -> bool:
	if not value is Dictionary:return false
	for key in ["able","wounded","prisoners"]:
		if not _count(value.get(key)):return false
	return true
static func _bucket(value: Dictionary) -> Dictionary:return {"able":int(value.able),"wounded":int(value.wounded),"prisoners":int(value.prisoners)}
static func _edges(state: Dictionary,ship_id: String) -> Array:
	var result=[]
	for i in state.get("chronicle",[]).size():
		var event: Dictionary=state.chronicle[i];var r: Dictionary=state.get("settlements",{}).get(event.get("id"),{});var d: Dictionary=r.get("details",{})
		if d.get("kind")=="casualty" and d.get("shipId")==ship_id:
			result.append({"index":i,"before":{"able":d.get("ableBefore"),"wounded":d.get("woundedBefore"),"prisoners":d.get("prisonersBefore")},"after":{"able":d.get("ableAfter"),"wounded":d.get("woundedAfter"),"prisoners":d.get("prisonersAfter")},"valid":r.get("kind")=="near-casualties"})
		elif d.get("kind")=="crew-transition":
			for change in d.get("changes",[]):
				if change.get("shipId")==ship_id:result.append({"index":i,"before":change.get("before",{}),"after":change.get("after",{}),"valid":r.get("kind")=="crew-transition"})
	return result
static func crew_at_event(state: Dictionary,ship_id: String,before_event_id: String) -> Dictionary:
	var fail={"ok":false,"reason":"unverified-crew-history","able":0,"wounded":0,"prisoners":0}
	var vessel: Dictionary=state.get("vessels",{}).get(ship_id,{})
	if not _buckets(vessel.get("crew")):return fail
	var cut=state.get("chronicle",[]).size() if before_event_id.is_empty() else _index(state,before_event_id)
	if cut<0:return fail
	var current=_bucket(vessel.crew);var at_cut=current.duplicate();var edges=_edges(state,ship_id)
	var capacity=Catalog.DATA.profiles.get(vessel.get("profileId"),{}).get("maxCrew",-1)
	for i in range(edges.size()-1,-1,-1):
		var edge: Dictionary=edges[i]
		if not edge.valid or not _buckets(edge.before) or not _buckets(edge.after) or current!=_bucket(edge.after) or edge.before.able+edge.before.wounded+edge.before.prisoners>capacity or edge.after.able+edge.after.wounded+edge.after.prisoners>capacity:return fail
		current=_bucket(edge.before)
		if edge.index>=cut:at_cut=current.duplicate()
	var anchored=false
	for role in Catalog.DATA.roles:
		if ship_id==state.get("campaignId","")+"-"+role.suffix:anchored=current=={"able":int(role.able),"wounded":0,"prisoners":0}
	# Old legitimate loads can supply an otherwise absent historical bucket baseline.
	if not anchored:
		var first=edges[0].index if not edges.is_empty() else cut
		for i in first:
			var d: Dictionary=state.settlements.get(state.chronicle[i].id,{}).get("details",{})
			if d.get("kind")=="convoy-load":
				for ship in d.get("ships",[]):
					if ship.get("shipId")==ship_id and _count(ship.get("able")) and _count(ship.get("wounded")):anchored=anchored or current=={"able":int(ship.able),"wounded":int(ship.wounded),"prisoners":0}
	if not anchored or at_cut.able+at_cut.wounded+at_cut.prisoners>capacity:return fail
	return {"ok":true,"reason":"","able":at_cut.able,"wounded":at_cut.wounded,"prisoners":at_cut.prisoners}
static func _mixed(state: Dictionary,ship_id: String,load_index: int,cut: int) -> bool:
	for i in range(load_index+1,cut):
		var d: Dictionary=state.settlements.get(state.chronicle[i].id,{}).get("details",{})
		if d.get("kind")=="crew-transition" and d.get("reason") in ["allocation","prize-rescue","prize-sale"]:
			for change in d.get("changes",[]):
				if change.get("shipId")==ship_id and not _equal(change.get("before"),change.get("after")):return true
		if d.get("kind")=="prize" and d.get("crew",0)>0 and ship_id in [d.get("fromShipId"),d.get("targetId")]:return true
		if d.get("kind")=="prize-resolution" and d.get("choice")=="abandon" and d.get("movedWounded",0)+d.get("movedPrisoners",0)>0 and ship_id in [d.get("targetId"),d.get("toShipId")]:return true
		if d.get("kind")=="prize-port" and d.get("action")=="sell" and d.get("movedAble",0)+d.get("movedWounded",0)+d.get("movedPrisoners",0)>0 and ship_id in [d.get("shipId"),d.get("crewToShipId")]:return true
	return false
static func _sunk(state: Dictionary,ship_id: String,cut: int) -> bool:
	var later_loss=false
	for i in state.get("chronicle",[]).size():
		var r: Dictionary=state.settlements.get(state.chronicle[i].id,{});var d: Dictionary=r.get("details",{})
		if d.get("kind")=="casualty" and d.get("shipId")==ship_id and d.get("sunk",false):
			if i<cut:return true
			later_loss=true
		if r.get("kind")=="shipment-lost" and ship_id in state.chronicle[i].get("causeIds",[]) and i<cut:return true
	return state.vessels.get(ship_id,{}).get("damage",{}).get("hull",0)<=0 and not later_loss
static func _beneficiaries(state: Dictionary,before_event_id: String="") -> Dictionary:
	var load=_load(state);var recipients=[];var exclusions=[];var total=0
	if load.is_empty():return {"beneficiaries":recipients,"beneficiaryCount":0,"exclusions":exclusions}
	var cut=state.chronicle.size() if before_event_id.is_empty() else _index(state,before_event_id)
	if cut<0:return {"beneficiaries":recipients,"beneficiaryCount":0,"exclusions":exclusions}
	var ids=[]
	for ship in load.details.ships:ids.append(ship.shipId)
	ids.sort()
	for ship_id in ids:
		var crew=crew_at_event(state,ship_id,before_event_id)
		if _mixed(state,ship_id,_index(state,load.id),cut):exclusions.append(state.vessels[ship_id].name+"人员曾跨船调动，本航受益人数暂不能核清。");continue
		if not crew.ok:exclusions.append(state.vessels[ship_id].name+"人员来源暂不能核验。");continue
		if _sunk(state,ship_id,cut) or crew.able+crew.wounded==0:continue
		recipients.append({"shipId":ship_id,"able":crew.able,"wounded":crew.wounded});total+=crew.able+crew.wounded
	return {"beneficiaries":recipients,"beneficiaryCount":total,"exclusions":exclusions}
static func _support_history(state: Dictionary) -> Dictionary:
	var value=50
	var before_values={};var after_values={}
	for event in state.get("chronicle",[]):
		var r: Dictionary=state.settlements.get(event.id,{});var d: Dictionary=r.get("details",{})
		if r.get("kind")!="story-choice":continue
		var award=0
		match d.get("sceneId"):
			"old-ledger":award=10 if d.get("choiceId")=="settle-wages" else -4 if d.get("choiceId")=="keep-reserve" else 0
			"first-return":award=8 if d.get("choiceId")=="crew-dividend" else 0
			SCENE_ID:
				if d.get("choiceId")=="share-proceeds":
					var revenue=d.get("aftermath",{}).get("revenue",-1)
					if not _count(revenue) or revenue<5:return {"ok":false}
					award=_award(int(floor(float(revenue)/5.0)))
		before_values[event.id]=value;value=clamp(value+award,-100,100);after_values[event.id]=value
	return {"ok":_support(state.get("reputations",{}).get("crewSupport")) and state.reputations.crewSupport==value,"before":before_values,"after":after_values}
static func _award(payment: int) -> int:return mini(4,maxi(1,int(floor(float(payment)/10.0)))) if payment>0 else 0
static func quote(state: Dictionary,choice_id: String) -> Dictionary:
	var claim=_claim(state);var revenue=claim.get("details",{}).get("baseReward",0)+claim.get("details",{}).get("bonus",0)
	var payment=int(floor(float(revenue)/5.0)) if choice_id=="share-proceeds" else 0
	var before=state.get("reputations",{}).get("crewSupport",0);var award=_award(payment);var after=clamp(before+award,-100,100)
	var crew=_beneficiaries(state) if choice_id=="share-proceeds" else {"beneficiaries":[],"beneficiaryCount":0,"exclusions":[]}
	var result={"ok":false,"reason":"","portId":state.get("currentPortId"),"claimId":claim.get("id",""),"revenue":revenue,"silverCost":payment,"supportAward":award,"supportBefore":before,"supportAfter":after,"supportDelta":after-before,"beneficiaries":crew.beneficiaries,"beneficiaryCount":crew.beneficiaryCount,"exclusions":crew.exclusions}
	if not choice_id in CHOICES:result.reason="unknown-choice"
	elif not _receipt(state).is_empty():result.reason="story-completed"
	elif claim.is_empty():result.reason="second-convoy-unclaimed"
	elif not state.get("currentPortId") in PORTS:result.reason="not-in-story-port"
	elif choice_id=="return-xiamen" and state.get("debt",{}).get("principal",0)==0:result.reason="debt-paid"
	elif choice_id=="share-proceeds" and payment==0:result.reason="no-dividend-proceeds"
	elif choice_id=="share-proceeds" and crew.beneficiaryCount<=0:result.reason="no-verified-beneficiaries"
	elif choice_id=="share-proceeds" and not _support_history(state).ok:result.reason="unexplained-crew-support"
	elif not _count(state.get("captain",{}).get("silver")) or state.captain.silver<payment:result.reason="insufficient-silver"
	result.ok=result.reason.is_empty();return result
static func _witness_error(state: Dictionary,port_id: String,witness: Dictionary) -> String:
	if not port_id in PORTS or witness.size()!=8 or witness.get("flagshipId")!=state.get("flagshipId"):return "invalid-port-witness"
	var position=witness.get("position")
	if not position is Dictionary or position.size()!=2:return "invalid-port-witness"
	for n in [position.get("x"),position.get("z"),witness.get("speed"),witness.get("hull")]:
		if not typeof(n) in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(n)):return "invalid-port-witness"
	var port: Dictionary=Catalog.DATA.ports[port_id].position
	if Vector2(position.x,position.z).distance_to(Vector2(port.x,port.z))>55 or witness.speed<0 or witness.speed>0.75 or witness.hull<=0 or witness.hull>100 or witness.get("anchored")!=true or witness.get("pendingAttacks")!=false or witness.get("activeBoardings")!=0 or witness.get("hostileWithin600")!=false:return "invalid-port-witness"
	return ""
static func apply(state: Dictionary,choice_id: String,port_witness: Dictionary) -> Dictionary:
	var q=quote(state,choice_id)
	if not q.ok:return {"ok":false,"reason":q.reason}
	var reason=_witness_error(state,q.portId,port_witness)
	if not reason.is_empty():return {"ok":false,"reason":reason}
	var before=state.captain.silver;var after=before-q.silverCost
	var details={"kind":"story-choice","sceneId":SCENE_ID,"choiceId":choice_id,"portId":q.portId,"silverCost":q.silverCost,"reputationEffects":{"crewSupport":q.supportAward,"militaryTrust":0,"merchantCredit":0},"routeId":null,"convoyReceiptId":q.claimId,"intelligence":null,"aftermath":{"contractId":"convoy-002","revenue":q.revenue,"silverBefore":before,"silverAfter":after,"supportBefore":q.supportBefore,"supportAfter":q.supportAfter,"beneficiaries":q.beneficiaries.duplicate(true),"beneficiaryCount":q.beneficiaryCount,"portWitness":port_witness.duplicate(true)}}
	state.captain.silver=after;state.reputations.crewSupport=q.supportAfter
	var message="第二趟实付%d两，受益%d人，拥护实际+%d。"%[q.silverCost,q.beneficiaryCount,q.supportDelta] if choice_id=="share-proceeds" else "已记下偿债去向；实际偿债仍使用厦门港务的独立支付。" if choice_id=="return-xiamen" else "现银仍%d两，未偿本金仍%d两；下一笔支出由你决定。"%[after,state.debt.principal]
	return {"ok":true,"message":message,"details":details}
static func receipt_error(state: Dictionary,receipt: Dictionary) -> String:
	var d: Dictionary=receipt.get("details",{});var a: Dictionary=d.get("aftermath",{});var claim=_claim(state);var load=_load(state)
	if d.get("sceneId")!=SCENE_ID or receipt.get("kind")!="story-choice" or receipt.get("id")!=_id(state) or state.get("settlements",{}).get(_id(state),{})!=receipt or not d.get("choiceId") in CHOICES:return "aftermath-identity"
	var cut=_index(state,receipt.id);var claim_cut=_index(state,claim.get("id",""))
	if claim.is_empty() or load.is_empty() or cut<=claim_cut or receipt.get("revision",-1)<=claim.revision or d.get("convoyReceiptId")!=claim.id or state.chronicle[cut].get("causeIds")!=[receipt.get("commandId"),receipt.id]:return "aftermath-history"
	if d.size()!=10 or a.size()!=9 or a.get("contractId")!="convoy-002" or d.get("routeId")!=null or d.get("intelligence")!=null:return "aftermath-schema"
	for r in state.settlements.values():
		if r.get("id")!=receipt.id and (r.get("commandId")==receipt.get("commandId") or r.get("details",{}).get("sceneId")==SCENE_ID):return "aftermath-duplicate"
	var revenue=claim.details.baseReward+claim.details.bonus;var share=d.choiceId=="share-proceeds";var payment=int(floor(float(revenue)/5.0)) if share else 0;var award=_award(payment)
	if a.get("revenue")!=revenue or d.get("silverCost")!=payment or not _equal(d.get("reputationEffects"),{"crewSupport":award,"militaryTrust":0,"merchantCredit":0}):return "aftermath-payment-definition"
	if not _count(a.get("silverBefore")) or not _count(a.get("silverAfter")) or a.silverBefore<payment or a.silverAfter!=a.silverBefore-payment or not _support(a.get("supportBefore")) or not _support(a.get("supportAfter")) or a.supportAfter!=clamp(a.supportBefore+award,-100,100):return "aftermath-payment-effects"
	if not a.get("portWitness") is Dictionary:return "invalid-port-witness"
	var witness_reason=_witness_error(state,d.get("portId",""),a.portWitness)
	if not witness_reason.is_empty():return witness_reason
	var crew=_beneficiaries(state,receipt.id) if share else {"beneficiaries":[],"beneficiaryCount":0}
	if not _equal(a.get("beneficiaries"),crew.beneficiaries) or a.get("beneficiaryCount")!=crew.beneficiaryCount or share and (payment<=0 or crew.beneficiaryCount<=0):return "aftermath-beneficiaries"
	if share:
		var history=_support_history(state)
		if not history.ok or history.before.get(receipt.id)!=a.supportBefore or history.after.get(receipt.id)!=a.supportAfter:return "aftermath-support-history"
	return ""
static func _reason_text(reason: String,payment: int=0) -> String:
	match reason:
		"second-convoy-unclaimed":return "先完成第二趟并领取实际报酬"
		"not-in-story-port":return "在厦门、金门或近岸补给点安全锚泊后，再打开船上账册"
		"no-dividend-proceeds":return "本航没有可分报酬"
		"no-verified-beneficiaries":return "暂无可核验的存活随航船员，不能发放"
		"insufficient-silver":return "当前银两不足支付%d两"%payment
		"unexplained-crew-support":return "现有拥护来源无法由历史核清，本次暂不能分红；仍可留本或立偿债目标"
		"debt-paid":return "本金已还清，无需再立偿债目标"
		"story-completed":return "本次安排已记账，仍可自行港务或偿债"
	return reason
static func project(state: Dictionary) -> Dictionary:
	var claim=_claim(state)
	if claim.is_empty():return {}
	var receipt=_receipt(state);var shared=quote(state,"share-proceeds");var candidates=_beneficiaries(state);var revenue=claim.details.baseReward+claim.details.bonus;var dividend=int(floor(float(revenue)/5.0));var award=_award(dividend);var support=state.reputations.crewSupport;var after=clamp(support+award,-100,100)
	var deaths=0;var wounded=0
	for ship in _load(state).details.ships:
		wounded+=state.vessels[ship.shipId].crew.wounded
		for loss in claim.details.get("ships",[]):
			if loss.get("shipId")==ship.shipId:deaths+=loss.get("dead",0)
	var bill={"delivered":claim.details.delivered,"lost":claim.details.lost,"baseReward":claim.details.baseReward,"bonus":claim.details.bonus,"revenue":revenue,"silver":state.captain.silver,"principal":state.debt.principal,"dividend":dividend,"remainingSilver":state.captain.silver-dividend,"supportBefore":support,"supportAward":award,"supportAfter":after,"supportDelta":after-support,"beneficiaryCount":candidates.beneficiaryCount,"beneficiaries":candidates.beneficiaries,"verifiedDeaths":deaths,"currentWounded":wounded,"scopeNote":"本次仅含承运船；护卫伤亡未列入本账。旧伤列为当前伤员，不称本航新增。","exclusions":candidates.exclusions}
	var choices=[]
	for choice in CHOICES:
		var q=quote(state,choice);var label="在厦门偿债" if state.currentPortId=="xiamen" else "回厦门偿债"
		var consequence="只记录目标，不扣银；当前可还%d两，实际金额在厦门港务支付时选择。"%min(state.captain.silver,state.debt.principal)
		if choice=="share-proceeds":
			label="分给已核验随航船员 · %d两"%dividend
			consequence="支付%d两；受益%d人，拥护实际+%d（名义+%d，上限100）。不治疗伤员。"%[dividend,candidates.beneficiaryCount,after-support,award]
			if support==100:consequence+=" 拥护已满，本次不会再加；支付仍会记账。"
		elif choice=="keep-capital":label="留作船本";consequence="零支出，声望不变；核对真实船况与港务费用。"
		choices.append({"id":choice,"label":label,"consequence":consequence,"silverCost":q.silverCost,"enabled":q.ok,"reason":q.reason,"reasonText":_reason_text(q.reason,q.silverCost)})
	var reason=quote(state,"keep-capital").reason
	var text=["这趟实交%d粮，实收%d两；现银%d两，旧债%d两。"%[claim.details.delivered,revenue,state.captain.silver,state.debt.principal],"%s、给本航已核验船员分两成，或先留船本，这笔钱由你安排。"%("在厦门偿债" if state.currentPortId=="xiamen" else "回厦门偿债")]
	var scene={"id":SCENE_ID,"title":"第二趟交差之后","npc":{"id":"aftermath-ledger","name":"交差账单","role":"船上账册"},"text":text,"status":"completed" if not receipt.is_empty() else "available" if reason.is_empty() else "locked","selectedChoiceId":receipt.get("details",{}).get("choiceId",""),"reply":receipt.get("message",""),"choices":choices,"bill":bill}
	var objective={"id":"second-aftermath-ledger","title":"核对第二趟的船上账册","detail":"在厦门、金门或近岸补给点安全锚泊后，比较实际报酬、船员与旧债。","panel":"story"}
	var relation=receipt.get("message","")
	if not state.currentPortId in PORTS and receipt.is_empty():objective.panel="port";objective.title="驶往安全港核账"
	if not receipt.is_empty():
		if receipt.details.choiceId=="return-xiamen":
			var paid=0;var start=_index(state,receipt.id)
			for i in range(start+1,state.chronicle.size()):
				var d: Dictionary=state.settlements.get(state.chronicle[i].id,{}).get("details",{})
				if d.get("kind")=="repay-debt" and _count(d.get("amount")):paid+=d.amount
			objective={"id":"second-debt-cleared" if state.debt.principal==0 else "second-repay-xiamen" if state.currentPortId=="xiamen" else "second-return-xiamen","title":"旧账已清" if state.debt.principal==0 else "向林家商行偿还本金" if state.currentPortId=="xiamen" else "驶回厦门偿债","detail":"本次安排后实际已还%d两，当前未偿本金%d两。"%[paid,state.debt.principal],"panel":"port"}
			if state.debt.principal>0 and state.currentPortId!="xiamen":objective.detail+=" 驶回厦门，安全锚定后偿债。"
		elif receipt.details.choiceId=="keep-capital":objective={"id":"second-keep-capital","title":"核对船况与本钱","detail":"现银%d两，未偿本金%d两；检查真实船只，港务与交易仍可自行办理。"%[state.captain.silver,state.debt.principal],"panel":"ship"}
		else:objective={"id":"second-share-recorded","title":"分红已记账，继续整备","detail":receipt.message+" 检查船况与现有港务费用。","panel":"ship"}
	return {"scene":scene,"objective":objective,"relationNote":relation,"bill":bill}
