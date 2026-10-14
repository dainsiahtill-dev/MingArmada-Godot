extends RefCounted
## Original opening dialogue. Receipts are the only persistent story authority.
const Catalog = preload("res://game/domain/mingqi/catalog.gd")
const SecondVoyageAftermath = preload("res://game/domain/mingqi/second_voyage_aftermath.gd")
const VoyageFlow = preload("res://game/domain/mingqi/voyage_flow.gd")
const SCENES = ["old-ledger","pilot-plan","first-return"]
const CHOICES = {"old-ledger":["settle-wages","keep-reserve"],"pilot-plan":["hire-pilot","stay-deep"],"first-return":["crew-dividend","buy-intelligence","keep-capital"]}

static func choice_definition(scene_id: String,choice_id: String) -> Dictionary:
	if scene_id==SecondVoyageAftermath.SCENE_ID:return SecondVoyageAftermath.choice_definition(choice_id)
	if not scene_id in SCENES or not choice_id in CHOICES[scene_id]: return {}
	var definition={"portId":"kinmen" if scene_id=="first-return" else "xiamen","silverCost":0,"reputationEffects":{"crewSupport":0,"militaryTrust":0,"merchantCredit":0},"routeId":null,"buyIntelligence":false}
	match choice_id:
		"settle-wages": definition.silverCost=80; definition.reputationEffects.crewSupport=10
		"keep-reserve": definition.reputationEffects.crewSupport=-4
		"hire-pilot": definition.silverCost=45; definition.reputationEffects.merchantCredit=1; definition.routeId="xiamen-kinmen-shallow"
		"stay-deep": definition.routeId="xiamen-kinmen-deep"
		"crew-dividend": definition.silverCost=80; definition.reputationEffects.crewSupport=8
		"buy-intelligence": definition.silverCost=60; definition.reputationEffects.militaryTrust=2; definition.reputationEffects.merchantCredit=3; definition.buyIntelligence=true
	return definition
static func receipt_id(state: Dictionary,scene_id: String) -> String:
	return state.campaignId+":story:"+scene_id
static func _receipt(state: Dictionary,scene_id: String) -> Dictionary:
	var receipt: Dictionary=state.get("settlements",{}).get(receipt_id(state,scene_id),{})
	return receipt if receipt.get("kind")=="story-choice" and receipt.get("details",{}).get("sceneId")==scene_id else {}
static func _claim(state: Dictionary) -> Dictionary:
	var claim: Dictionary=state.get("settlements",{}).get(state.campaignId+":convoy-001:claim",{})
	return claim if claim.get("kind")=="claim-convoy" and claim.get("details",{}).get("kind")=="convoy" and claim.details.contractId=="convoy-001" else {}
static func _original_loading(state: Dictionary) -> bool:
	var ct: Dictionary=state.get("contracts",{}).get("convoy-001",{})
	var ids=[state.campaignId+"-grain-a-voyage",state.campaignId+"-grain-b-voyage"]
	if ct.get("voyageIds",[]).size()!=2: return false
	for id in ids:
		var voyage: Dictionary=state.get("voyages",{}).get(id,{})
		if not id in ct.voyageIds or voyage.get("status")!="loading": return false
	return true
static func scene_reason(state: Dictionary,scene_id: String) -> String:
	if scene_id==SecondVoyageAftermath.SCENE_ID:return SecondVoyageAftermath.quote(state,"keep-capital").get("reason","")
	if not scene_id in SCENES: return "unknown-scene"
	if not _receipt(state,scene_id).is_empty(): return "story-completed"
	var ct: Dictionary=state.get("contracts",{}).get("convoy-001",{})
	if scene_id=="first-return":
		if not ct.get("status") in ["settled","failed"] or _claim(state).is_empty() or ct.get("receiptId")!=state.campaignId+":convoy-001:claim": return "first-convoy-unclaimed"
	elif scene_id=="pilot-plan":
		if ct.get("status")!="active": return "first-convoy-not-active"
		if not _original_loading(state): return "first-convoy-departed"
	else:
		if not ct.get("status") in ["offered","active"] or not _original_loading(state): return "first-convoy-departed"
	var port="kinmen" if scene_id=="first-return" else "xiamen"
	return "" if state.get("currentPortId")==port else "not-in-story-port"
static func _route_reason(state: Dictionary,route_id: String) -> String:
	var route: Dictionary=Catalog.DATA.routes[route_id]
	for suffix in ["grain-a","grain-b"]:
		var vessel: Dictionary=state.vessels.get(state.campaignId+"-"+suffix,{})
		var profile: Dictionary=Catalog.DATA.profiles.get(vessel.get("profileId"),{})
		if profile.is_empty(): return "unknown-profile"
		var quantity=0.0
		for q in vessel.cargo.values():
			if not typeof(q) in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(q)) or q<0 or q!=floor(float(q)): return "invalid-cargo"
			quantity+=q
		if quantity>profile.capacity: return "invalid-cargo"
		if profile.baseDraftMeters+quantity*profile.cargoDraftMetersPerUnit>=route.minimumDepth: return "route-too-shallow"
	return ""
static func choice_reason(state: Dictionary,scene_id: String,choice_id: String) -> String:
	if scene_id==SecondVoyageAftermath.SCENE_ID:return SecondVoyageAftermath.quote(state,choice_id).get("reason","")
	var definition=choice_definition(scene_id,choice_id)
	if definition.is_empty(): return "unknown-choice"
	var reason=scene_reason(state,scene_id)
	if not reason.is_empty(): return reason
	if state.captain.silver<definition.silverCost: return "insufficient-silver"
	if definition.buyIntelligence and state.intelligence.size()>=4096: return "intelligence-buffer-full"
	return _route_reason(state,definition.routeId) if definition.routeId!=null else ""
static func apply(state: Dictionary,scene_id: String,choice_id: String) -> Dictionary:
	if scene_id==SecondVoyageAftermath.SCENE_ID:return {"ok":false,"reason":"native-context-required"}
	var reason=choice_reason(state,scene_id,choice_id)
	if not reason.is_empty(): return {"ok":false,"reason":reason}
	var definition=choice_definition(scene_id,choice_id)
	var id=receipt_id(state,scene_id); var intel=null
	if definition.buyIntelligence:
		intel={"portId":"forward-supply","observedAt":state.simulationSeconds,"sourceId":id,"confidence":0.65,"stock":{"grain":state.ports["forward-supply"].stock.get("grain",0)}}
	var details={"kind":"story-choice","sceneId":scene_id,"choiceId":choice_id,"portId":definition.portId,"silverCost":definition.silverCost,"reputationEffects":definition.reputationEffects.duplicate(true),"routeId":definition.routeId,"convoyReceiptId":state.campaignId+":convoy-001:claim" if scene_id=="first-return" else null,"intelligence":intel}
	state.captain.silver-=definition.silverCost
	for key in definition.reputationEffects: state.reputations[key]=clamp(state.reputations[key]+definition.reputationEffects[key],-100,100)
	if definition.routeId!=null:
		for suffix in ["grain-a","grain-b"]: state.voyages[state.campaignId+"-"+suffix+"-voyage"].routeId=definition.routeId
	if intel!=null: state.intelligence.append(intel.duplicate(true))
	var message=_reply(choice_id)
	if intel!=null: message+=" 实际粮食库存%d，采集于航程时间%.2f秒，可信度65%%。"%[intel.stock.grain,intel.observedAt]
	return {"ok":true,"message":message,"details":details}
static func _reply(choice_id: String) -> String:
	match choice_id:
		"settle-wages": return "许福收下80两工钱：船长没忘了弟兄，我们也会守住这条船。"
		"keep-reserve": return "许福把账册合上：银子留着救急可以，欠下的工钱，弟兄们都记着。"
		"hire-pilot": return "陈阿海收下45两规划费，为两艘粮船安排了验过吃水的浅水航道；你也可以自行免费逐船选路。"
		"stay-deep": return "陈阿海点头：两艘粮船仍走深水外线。航道宽敞，遇敌时要守住船队。"
		"crew-dividend": return "你拿出80两分给船员。许福说，生意有赚有险，肯和弟兄们分担才走得长远。"
		"buy-intelligence": return "你用60两取得近岸补给点的粮食库存情报。林账房提醒：这是此刻的消息，出航后还会变化。"
		_: return "你把银两留作下一次出航的本钱。林账房将交差结果如实记入账册。"
static func _locked_prompt(state: Dictionary,scene_id: String,reason: String) -> String:
	if reason=="not-in-story-port": return "请先在金门安全靠港后交谈。" if scene_id=="first-return" else "请先回厦门安全靠港后交谈。"
	if reason=="first-convoy-not-active": return "先接下第一份护粮委托，再与领航员商量两艘粮船的航路。"
	if reason=="first-convoy-departed": return "这段出航前的谈话已错过；继续处理当前航程，现有委托照常进行。"
	if reason=="first-convoy-unclaimed":
		var ct: Dictionary=state.contracts.get("convoy-001",{})
		return "先完成第一趟护粮航程并领取实际交差结果，再到金门谈下一步。" if ct.get("status")!="offered" else "先接下护粮委托，完成航行并交差，再到金门会面。"
	return "请先满足当前航程的实际条件。"
static func _scene_text(state: Dictionary,scene_id: String) -> Array:
	if scene_id=="old-ledger": return ["厦门，1650年。父亲留下的承家号和旧账册还在；林家商行原有400两本金，现在未偿%d两。如今明旗号和快船都是借用，得先做成一趟生意。"%state.debt.principal,"承家号的老水手许福翻到欠薪那页：船要修，人也要吃饭。你打算先拿80两安下弟兄的心，还是留住银子防备海上的变故？"]
	if scene_id=="pilot-plan": return ["陈阿海用指头沿着海图划出两条路：两艘粮船已经装货，深水外线宽敞，浅水线能绕过部分火力，但必须逐船核对吃水。","45两是代规划两艘粮船及建立委托人情的费用；你仍可自行免费逐船选路。这个选择只改粮船路线，旗舰仍由你操纵，浅滩仍会挡住吃水更深的船。"]
	var d: Dictionary=_claim(state).get("details",{}); var dead=0; var wounded=0
	for ship in d.get("ships",[]): dead+=ship.get("dead",0); wounded+=ship.get("wounded",0)
	var delivered=d.get("delivered",0); var lost=d.get("lost",0)
	var outcome="这一趟完整交付了粮食。" if delivered==40 and lost==0 else "这一趟只交付了部分粮食，损失必须留在账上。" if delivered>0 else "这一趟护粮失败，不能把没有送到的粮食记作功劳。"
	return ["留守金门的林账房核过交差账：实交%d粮，损失%d粮；船员死亡%d人、伤员%d人。%s"%[delivered,lost,dead,wounded,outcome],"许福关心弟兄的伤亡，账房关心下一趟的本钱。你可以给船员分红、购买补给点情报，或把银子留在船上。下一份委托按真实交差结果开放。",_supply_plan(state) if delivered>0 else "本次护粮没有交付，尚未开放第二委托；先保住船和人员，再作打算。"]
static func _supply_plan(state: Dictionary) -> String:
	var sunk=0;var stock=state.ports.kinmen.stock.get("grain",0)
	for suffix in ["grain-a","grain-b"]:
		if state.vessels[state.campaignId+"-"+suffix].damage.hull<=0:sunk+=1
	if sunk==0:return "近岸据点需要20粮，金门现有%d粮；两艘原租粮船各运10，先核对人数、空舱与安全锚定。"%stock
	if sunk==1:return "近岸据点需要20粮，金门现有%d粮；一艘原租粮船已沉没，合格幸存船可独运20，全部补给集中在一船，风险更高。"%stock
	return "两艘原租粮船均已沉没，当前没有替换租船来源，无法承运近岸据点的20粮。"
static func _choice_label(choice_id: String) -> Array:
	match choice_id:
		"settle-wages": return ["先结工钱 · 80两","支付80两；船员拥护+10，影响接舷初始士气。"]
		"keep-reserve": return ["留作应急","保留银两；船员拥护-4。"]
		"hire-pilot": return ["请陈阿海规划 · 45两","支付45两代规划两艘粮船并建立人情，商人信用+1；逐船核对吃水后改走浅水线，原有免费选路仍可用。"]
		"stay-deep": return ["沿深水外线走","无需花费；两艘粮船走深水线。"]
		"crew-dividend": return ["与船员分红 · 80两","支付80两；船员拥护+8，影响接舷初始士气。"]
		"buy-intelligence": return ["购买补给情报 · 60两","支付60两；军方信任+2、商人信用+3，记录当前补给点粮食库存。"]
		_: return ["留下下趟本钱","保留银两，声望不变。"]
static func _objective(state: Dictionary) -> Dictionary:
	var first_claim=_claim(state);var second: Dictionary=state.contracts.get("convoy-002",{})
	if not first_claim.is_empty() and first_claim.details.delivered>0 and _receipt(state,"first-return").is_empty() and second.get("status")=="offered":
		if state.currentPortId!="kinmen":return {"id":"return-to-kinmen","title":"前往金门安全靠港","detail":"首航交差已记录，回金门安全锚定后可与林账房商量下一步；会面可跳过，补给委托仍可直接承接。","panel":"port"}
		return {"id":"first-return-meeting","title":"与林账房核对下一步","detail":"先确认港口安全并锚定，再谈分红、情报或保留本金。会面可跳过，近岸据点的20粮补给委托无需等待对白。","panel":"story"}
	for cid in ["convoy-001","convoy-002"]:
		var ct: Dictionary=state.contracts.get(cid,{})
		if ct.is_empty(): continue
		if ct.status=="offered":
			var detail="在厦门核对粮船与租费，接受第一趟护航。"
			if cid=="convoy-002":
				detail=_supply_plan(state)
			return {"id":"accept-"+cid,"title":"接下护粮委托" if cid=="convoy-001" else "承接军需补给","detail":detail,"panel":"convoy"}
		if ct.status=="active" or ct.status=="delivered":
			var finished=not ct.voyageIds.is_empty(); var loading=false
			for id in ct.voyageIds:
				var status=state.voyages.get(id,{}).get("status"); finished=finished and status in ["arrived","lost"]; loading=loading or status=="loading"
			if finished: return {"id":"claim-"+cid,"title":"核对交差结果","detail":"按实际送达粮食、损失与人员情况领取报酬。","panel":"convoy"}
			if loading: return {"id":"depart-"+cid,"title":"整备后出航","detail":"核对航线和吃水，确保港口安全，再带粮船离港。","panel":"convoy"}
			return {"id":"deliver-"+cid,"title":"护住粮船" if cid=="convoy-001" else "送达近岸补给点","detail":"操纵旗舰保护运输船，观察真实航程、损伤与伤亡。","panel":"convoy"}
	if not _claim(state).is_empty() and state.contracts.get("convoy-001",{}).get("status")=="failed": return {"id":"recover-from-loss","title":"保船保人，再作打算","detail":"回港修理并处理伤员；失败的交差结果已经记入账册。","panel":"port"}
	return {"id":"fleet-next-voyage","title":"整备下一次出航","detail":"两趟交差结果已记录，检查船只、人员与剩余本金。","panel":"ship"}
static func project(state: Dictionary) -> Dictionary:
	var scenes=[]; var history=[]
	var aftermath=SecondVoyageAftermath.project(state)
	var names={"old-ledger":{"id":"xu-fu","name":"许福","role":"老水手"},"pilot-plan":{"id":"chen-ahai","name":"陈阿海","role":"领航员"},"first-return":{"id":"lin-clerk","name":"林账房","role":"林家商行账房"}}
	var titles={"old-ledger":"旧账与工钱","pilot-plan":"粮船走哪条路","first-return":"第一趟交差之后"}
	for id in SCENES:
		var receipt=_receipt(state,id); var reason=scene_reason(state,id); var completed=not receipt.is_empty(); var choices=[]
		for choice_id in CHOICES[id]:
			var label=_choice_label(choice_id); var unavailable=choice_reason(state,id,choice_id)
			choices.append({"id":choice_id,"label":label[0],"consequence":label[1],"silverCost":choice_definition(id,choice_id).silverCost,"enabled":unavailable.is_empty(),"reason":unavailable})
		var text=_scene_text(state,id) if completed or reason.is_empty() else [_locked_prompt(state,id,reason)]
		scenes.append({"id":id,"title":titles[id],"npc":names[id],"text":text,"status":"completed" if completed else "available" if reason.is_empty() else "locked","selectedChoiceId":receipt.get("details",{}).get("choiceId",""),"reply":receipt.get("message",""),"choices":choices})
	if not aftermath.is_empty():scenes.append(aftermath.scene)
	for event in state.get("chronicle",[]):
		var receipt: Dictionary=state.settlements.get(event.id,{})
		if receipt.get("kind")=="story-choice":
			var d: Dictionary=receipt.get("details",{})
			history.append({"id":receipt.id,"sceneId":d.sceneId,"choiceId":d.choiceId,"message":receipt.message,"simTime":event.simTime})
	var ledger_choice=_receipt(state,"old-ledger").get("details",{}).get("choiceId",""); var pilot_choice=_receipt(state,"pilot-plan").get("details",{}).get("choiceId",""); var return_choice=_receipt(state,"first-return").get("details",{}).get("choiceId","")
	var dead=0; var wounded=0
	for ship in _claim(state).get("details",{}).get("ships",[]): dead+=ship.dead; wounded+=ship.wounded
	var xu_stance="等你对旧账表态。" if ledger_choice.is_empty() else "工钱结清，愿意与你共担风险。" if ledger_choice=="settle-wages" else "接受应急留银，但仍记着欠薪。"
	if return_choice=="crew-dividend": xu_stance+=" 你给船员分了红。"
	if dead>0 or wounded>0: xu_stance+=" 此趟死亡%d人、受伤%d人，他希望先安置伤员。"%[dead,wounded]
	var ahai_stance="等待护粮委托与路线决定。" if pilot_choice.is_empty() else "已受规划费，认可你的委托；两艘粮船按浅水航路安排。" if pilot_choice=="hire-pilot" else "尊重深水路线的决定，仍提醒你守住船队。"
	var lin_alive=state.people.get("steward-a",{}).get("alive",false)
	var lin_stance="等你把粮船安全送达。" if _claim(state).is_empty() else "已按实际送达与损失结账。"
	if not lin_alive: lin_stance="林管事已在本次航程中阵亡，交差由留守账房接手。"
	if return_choice=="buy-intelligence": lin_stance+=" 留守账房给了你当时的补给库存情报。"
	if state.debt.principal==0: lin_stance+=" 400两本金已清偿。"
	var principal=state.debt.principal; var repay_reason="" if state.currentPortId=="xiamen" and principal>0 and state.captain.silver>0 else "debt-paid" if principal==0 else "not-in-port" if state.currentPortId!="xiamen" else "insufficient-silver"
	var relations=[{"id":"xu-fu","name":"许福","role":"老水手","stance":xu_stance},{"id":"chen-ahai","name":"陈阿海","role":"领航员","stance":ahai_stance},{"id":"lin-steward","name":"林管事","role":"商行管事","stance":lin_stance}]
	if not aftermath.get("relationNote","").is_empty():relations.append({"id":"verified-convoy-crew","name":"已核验随航船员","role":"本航承运船","stance":aftermath.relationNote})
	var projection={"chapter":{"id":"opening-1650","title":"旧账新帆","summary":"从厦门的一册旧账出发：护粮、交差、分担损失，再决定怎样养活自己的船。"},"objective":aftermath.objective if not aftermath.is_empty() else _objective(state),"scenes":scenes,"relations":relations,"history":history,"debt":{"principal":principal,"creditorName":"林家商行","canRepay":repay_reason.is_empty(),"reason":repay_reason}}
	if not aftermath.is_empty():projection.bill=aftermath.bill
	projection.flow=VoyageFlow.project(state)
	return projection.duplicate(true)
