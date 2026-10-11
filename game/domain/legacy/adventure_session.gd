extends RefCounted
const Catalog=preload("res://game/domain/legacy/catalog.gd")
const C=Catalog.DATA
const Validator=preload("res://game/domain/legacy/save_validation.gd")
const Surrender=preload("res://game/domain/legacy/surrender.gd")
const JsonNumbers=preload("res://game/domain/legacy/json_numbers.gd")
const Text=preload("res://game/domain/legacy/utf16_text.gd")
var state={}
var meta={}
var paused=false
var latestNaval=null
var storage=null
var last_error=""
func _init(options={},encoded_options=false):
	if not options is Dictionary:last_error="无效航程选项";return
	var seed=options.get("seed");seed=1661 if seed==null else seed
	var name=options.get("name");name="沈沧海" if name==null else name
	if not integer(seed,0,0xffffffff):last_error="无效世界种子";return
	if not name is String:last_error="船长姓名须为1至24字";return
	name=Text.source_trim(name if encoded_options else Text.encode_native(name))
	if name.is_empty() or Text.source_length(name)>24:last_error="船长姓名须为1至24字";return
	storage=options.get("storage");var home=port("xiamen");var ship=initial_ship("player","fuchuan","定海号",48);ship.cargo.grain=30
	meta={"shipSequence":1,"logSequence":0,"questSequence":0,"battleEpoch":0,"lastNavalTick":0,"seenEvents":[],"settledTargets":[],"victories":[],"capturedTargets":[],"clues":[],"landWon":[],"treasures":[],"visitedSites":[],"rescuedTargets":[],"targets":{},"cooldowns":{}}
	var markets={};var stocks={}
	for p in C.PORTS:markets[p.id]=p.stock.duplicate(true);stocks[p.id]=C.AMMO_STOCKS.duplicate()
	state={"version":1,"seed":seed,"elapsedSeconds":0,"day":1,"player":{"name":name,"silver":650,"fame":0,"infamy":0,"age":22,"morale":100,"supplies":30},"fleet":[ship],"flagshipId":"player","position":{"x":home.x+25,"z":home.z},"speed":0,"heading":0,"currentPortId":null,"cargo":ship.cargo.duplicate(),"quests":C.MAIN_QUESTS.duplicate(true),"relations":{"zheng":0,"qing":0,"voc":0,"pirates":0},"log":[],"mainChapter":1,"weather":weather_for(seed,1),"career":{"surrenders":0,"battlesWon":0,"shipsCaptured":0,"portsVisited":[],"sitesVisited":[],"tradeProfit":0,"treasureFound":0,"injuries":0,"rank":"新任船长","totalPlunder":0,"retired":false,"score":0,"ending":""},"activeObjectives":[],"markets":markets,"battleActive":false,"officers":[],"ammoStocks":stocks,"supplyPerDay":2,"wagesPerDay":2}
	add_log("1661年。虚构船长初掌定海号，三十袋军粮随船。厦门锚地在近旁，金门等待补给。");add_repeatables();ensure_ambient()
func integer(n,lo=0,hi=1000000000):return bounded(n,lo,hi) and float(n)==floor(float(n))
func bounded(n,lo,hi):return typeof(n) in [TYPE_FLOAT,TYPE_INT] and is_finite(float(n)) and n>=lo and n<=hi
func amount(n):return integer(n,1,1000000)
func fail(reason):return {"ok":false,"reason":reason}
func empty_cargo():return {"grain":0,"wood":0,"iron":0,"silk":0,"porcelain":0,"spices":0}
func cargo_size(cargo):
	var total=0
	for g in C.GOODS:total+=cargo[g]
	return total
func port(id):
	for p in C.PORTS:
		if p.id==id:return p
	return null
func find_by(items,id):
	for item in items:
		if item.id==id:return item
	return null
func initial_ship(id,kind,name,crew=0):
	var p=C.SHIP_PROFILES[kind]
	return {"id":id,"name":name,"kind":kind,"hull":100,"sail":100,"crew":crew,"maxHull":100,"maxSail":100,"maxCrew":p.crew,"capacity":p.capacity,"cargo":empty_cargo(),"upgrades":{"hull":0,"cannons":0,"sails":0},"ammo":{"solid":40,"chain":24,"grape":24}}
func flagship():return find_by(state.fleet,state.flagshipId)
func snapshot():refresh();return state.duplicate(true)
func setPaused(value):paused=value
func set_paused(value):setPaused(value)
func commitFrom(candidate):
	if not Validator.validate(candidate.state,candidate.meta):last_error="存档字段、界限或舰队约束损坏，原存档未改动";return false
	state=candidate.state.duplicate(true);meta=candidate.meta.duplicate(true);latestNaval=candidate.latestNaval.duplicate(true) if candidate.latestNaval!=null else null;paused=candidate.paused;return true
func commit_from(candidate):return commitFrom(candidate)
func preview(c):
	var copy=get_script().new();copy.restore(serialize());copy.latestNaval=latestNaval.duplicate(true) if latestNaval!=null else null;return copy.command(c)
func command(c):
	if state.is_empty():return fail(last_error)
	if not c is Dictionary or not c.get("type") is String:return fail("无效操作")
	if state.has("pendingSurrenderReceipt") and c.type!="acknowledge-surrender":return fail("请先确认投降结果并返回厦门")
	if c.type in ["resolve-boarding","resolve-land","resolve-treasure"] and c.has("injury") and not bounded(c.injury,0,100):return fail("伤势须为0至100的有限百分比")
	if c.type=="resolve-boarding" and c.has("disposition") and c.disposition not in ["capture","plunder","release"]:return fail("无效俘获处置")
	if state.career.retired:return fail("此生涯已退休，请另开新航程")
	var result=apply(c)
	if result.ok:
		refresh()
		if storage!=null:result.save=save()
	return result
func apply(c):
	var s=state;var ship=flagship();var type=c.type
	if type=="acknowledge-surrender":
		if not s.has("pendingSurrenderReceipt") or c.get("battleId")!=s.pendingSurrenderReceipt.quote.token.battleId:return fail("投降结果不匹配")
		s.erase("pendingSurrenderReceipt");latestNaval=null;return {"ok":true,"navalChanged":true}
	if type=="surrender":return surrender(c.get("token"))
	if type=="rename":
		if not c.get("name") is String or Text.source_trim(c.name).is_empty() or Text.source_length(Text.source_trim(c.name))>24:return fail("船长姓名须为1至24字")
		s.player.name=Text.source_trim(c.name);return {"ok":true}
	if type=="dock":
		var p=port(c.get("portId"))
		if p==null:return fail("港口不存在")
		if s.battleActive:return fail("交战中无法靠港，请先脱离敌舰")
		if distance(s.position,p)>55:return fail("距锚地超过55米")
		if s.speed>1.5:return fail("船速过高，请减帆至1.5米/秒以下")
		if s.relations[p.faction]<=-50 and not (p.id=="luermen" and s.mainChapter==6):return fail("此势力拒绝你的舰队入港")
		s.currentPortId=p.id;s.speed=0
		if p.id not in s.career.portsVisited:s.career.portsVisited.append(p.id);s.player.fame+=2
		add_log("靠泊%s。港内暂停航海时间。"%p.name);progress_quests();return {"ok":true}
	if type=="depart":
		if s.currentPortId==null:return fail("当前未靠港")
		for f in s.fleet:
			if f.hull<=0 or f.crew<C.SHIP_PROFILES[f.kind].minCrew:return fail("请修复船只并为每艘船配足最低船员")
		var p=port(s.currentPortId);var dx=-p.islandX;var dz=-p.islandZ;var d=sqrt(dx*dx+dz*dz)
		s.position={"x":p.x+dx/d*30,"z":p.z+dz/d*30};s.heading=atan2(dz,dx);s.currentPortId=null;s.battleActive=false
		for i in s.fleet.size():var f=s.fleet[i];f.position={"x":s.position.x+dx/d*i*44,"z":s.position.z+dz/d*i*44};f.heading=s.heading;f.speed=0
		add_log("驶离%s。"%p.name);return {"ok":true,"navalChanged":true}
	if type=="resolve-boarding":return board(c)
	if s.currentPortId==null or s.battleActive:return fail("此操作须安全靠港后进行")
	var p=port(s.currentPortId)
	if type=="resupply-ammo":
		var ammo=c.get("ammo");var quantity=c.get("quantity")
		if not C.AMMO_PRICES.has(ammo) or not amount(quantity):return fail("弹种及数量无效，须为正整数")
		if "trade" not in p.services:return fail("此港没有军需供应")
		var iron=ceil(float(quantity)/C.AMMO_IRON_BATCH[ammo]);var cost=quantity*C.AMMO_PRICES[ammo]
		if ship.ammo[ammo]+quantity>200:return fail("每种弹药最多装载200组")
		if s.ammoStocks[p.id][ammo]<quantity:return fail("港口弹药库存不足")
		if ship.cargo.iron<iron:return fail("补充弹药需铁料%d，请先在市场购入"%iron)
		if s.player.silver<cost:return fail("补充弹药银两不足")
		s.player.silver-=cost;ship.cargo.iron-=iron;s.ammoStocks[p.id][ammo]-=quantity;ship.ammo[ammo]+=quantity;add_log("补充%s%d组，支付%d两及铁料%d。"%[{"solid":"实心弹","chain":"链弹","grape":"葡萄弹"}[ammo],quantity,cost,iron]);return {"ok":true,"cost":cost,"navalChanged":true}
	if type=="hire-officer":
		var role=c.get("role")
		if not C.OFFICERS.has(role):return fail("未知军官专长")
		if "recruit" not in p.services:return fail("此港没有募员服务")
		if role in s.officers:return fail("此专长军官已在舰队中")
		var officer=C.OFFICERS[role]
		if s.player.silver<officer.price:return fail("聘任军官银两不足")
		s.player.silver-=officer.price;s.officers.append(role);add_log("聘任%s，支付%d两，每日薪银%d两。%s"%[officer.name,officer.price,officer.dailyWage,officer.description]);return {"ok":true,"cost":officer.price,"navalChanged":true}
	if type in ["buy","sell"]:
		var good=c.get("good");var quantity=c.get("quantity")
		if good not in C.GOODS or not amount(quantity):return fail("货物及数量无效，须为正整数")
		var quote=trade_quote(type,good,quantity)
		if not quote.ok:return quote
		if type=="buy":s.player.silver-=quote.cost;ship.cargo[good]+=quantity;s.markets[p.id][good]-=quantity;s.career.tradeProfit-=quote.cost
		else:s.player.silver+=quote.reward;ship.cargo[good]-=quantity;s.markets[p.id][good]+=quantity;s.career.tradeProfit+=quote.reward
		add_log("%s%s%s%d，%s%d两。"%[p.name,"买入" if type=="buy" else "卖出",C.GOOD_NAMES[good],quantity,"支付" if type=="buy" else "收入",quote.get("cost",quote.get("reward"))]);progress_quests();return quote
	if type=="repair":
		if "repair" not in p.services:return fail("此港没有修船服务")
		var hull=ship.maxHull-ship.hull;var sail=ship.maxSail-ship.sail;var cost=ceil((hull+sail)*2);var wood=ceil(hull/10.0);var iron=ceil(hull/20.0)
		if cost==0:return fail("船体和帆装无需修复")
		if ship.cargo.wood<wood or ship.cargo.iron<iron:return fail("修船需木材%d、铁料%d"%[wood,iron])
		if s.player.silver<cost:return fail("修船银两不足")
		ship.cargo.wood-=wood;ship.cargo.iron-=iron;s.player.silver-=cost;ship.hull=ship.maxHull;ship.sail=ship.maxSail;add_log("%s修复完毕，花费%d两。"%[ship.name,cost]);return {"ok":true,"cost":cost,"navalChanged":true}
	if type=="recruit":
		if "recruit" not in p.services or not amount(c.get("count")):return fail("招募人数须为正整数")
		if ship.crew+c.count>ship.maxCrew:return fail("超过此船船员上限")
		var cost=c.count*6
		if s.player.silver<cost:return fail("招募银两不足")
		s.player.silver-=cost;ship.crew+=c.count;add_log("招募%d名船员，支付%d两。"%[c.count,cost]);return {"ok":true,"cost":cost,"navalChanged":true}
	if type=="buy-ship":
		if not C.SHIP_PROFILES.has(c.get("kind")):return fail("未知船型")
		if "shipyard" not in p.services:return fail("此港没有船坞")
		if s.fleet.size()>=6:return fail("舰队最多六艘船")
		var profile=C.SHIP_PROFILES[c.kind];var cost=profile.price
		if s.player.silver<cost:return fail("购船银两不足")
		s.player.silver-=cost;meta.shipSequence+=1;var acquired=initial_ship("fleet-%d"%meta.shipSequence,c.kind,"%s%d号"%[profile.name,meta.shipSequence]);s.fleet.append(acquired);add_log("购入%s。离港前须分配船员。"%acquired.name);return {"ok":true,"cost":cost,"navalChanged":true}
	if type=="select-flagship":
		var selected=find_by(s.fleet,c.get("shipId"))
		if selected==null:return fail("船只不在舰队中")
		if selected.hull<=0:return fail("沉没船只不能设为旗舰，请先处置损失")
		s.flagshipId=selected.id;add_log("%s升起旗舰旗号。"%selected.name);return {"ok":true,"navalChanged":true}
	if type=="sell-ship":
		var target=find_by(s.fleet,c.get("shipId"))
		if target==null:return fail("船只不在舰队中")
		if s.fleet.size()==1:return fail("无法卖掉最后一艘船")
		if target.id==s.flagshipId:return fail("请先指定另一艘旗舰")
		if target.crew>0 or cargo_size(target.cargo)>0:return fail("出售前请转移船员和货物")
		var reward=floor(C.SHIP_PROFILES[target.kind].price*.5*target.hull/target.maxHull);s.fleet=s.fleet.filter(func(f):return f.id!=target.id);s.player.silver+=reward;return {"ok":true,"reward":reward,"navalChanged":true}
	if type in ["transfer-crew","transfer-cargo"]:
		var from=find_by(s.fleet,c.get("fromShipId"));var to=find_by(s.fleet,c.get("toShipId"))
		if from==null or to==null or from.id==to.id:return fail("请选择两艘不同的舰队船只")
		if type=="transfer-crew":
			if not amount(c.get("count")) or from.crew<c.count or to.crew+c.count>to.maxCrew:return fail("船员分配超出人数或容量")
			from.crew-=c.count;to.crew+=c.count
		else:
			if c.get("good") not in C.GOODS or not amount(c.get("quantity")) or from.cargo[c.good]<c.quantity or cargo_size(to.cargo)+c.quantity>to.capacity:return fail("货物分配超出存货或货舱")
			from.cargo[c.good]-=c.quantity;to.cargo[c.good]+=c.quantity
		return {"ok":true,"navalChanged":true}
	if type=="upgrade":
		if c.get("system") not in ["hull","cannons","sails","equipment"]:return fail("未知升级系统")
		if "shipyard" not in p.services:return fail("此港没有船坞")
		var level=ship.upgrades.get(c.system,0)
		if level>=3:return fail("此系统已达三级上限")
		var cost=(level+1)*(250 if c.system=="cannons" else 180)
		if s.player.silver<cost:return fail("升级银两不足")
		s.player.silver-=cost;ship.upgrades[c.system]=level+1
		if c.system=="hull":var old=ship.maxHull;ship.maxHull=100*pow(1.2,ship.upgrades.hull);ship.hull+=ship.maxHull-old
		add_log("%s%s升至%d级。"%[ship.name,{"hull":"船体","cannons":"火炮","sails":"帆装","equipment":"操船装备"}[c.system],level+1]);return {"ok":true,"cost":cost,"navalChanged":true}
	if type=="accept-quest":return accept_quest(c.get("questId"))
	if type=="complete-quest":return complete_quest(c.get("questId"))
	if type in ["visit-land","resolve-land","resolve-treasure"]:return land(c)
	if type=="resolve-banquet":
		if c.get("portId")!=p.id or not integer(c.get("score"),0,100):return fail("宴会地点或得分无效")
		if meta.cooldowns.get("banquet:"+p.id,0)>s.day:return fail("此港宴会尚未散场，三日后再来")
		if s.player.silver<30:return fail("赴宴需三十两")
		s.player.silver-=30;s.player.morale=clamp(s.player.morale+floor(c.score/10.0),0,100);s.relations[p.faction]=clamp(s.relations[p.faction]+floor(c.score/20.0),-100,100);s.player.fame+=floor(c.score/25.0);meta.cooldowns["banquet:"+p.id]=s.day+3;add_log("%s宴会得分%d，声望与当地人缘随表现增长。"%[p.name,c.score]);return {"ok":true,"cost":30}
	if type=="divide-plunder":
		var cost=floor(s.player.silver*.2)
		if cost<10:return fail("至少五十两才能分赃")
		if meta.cooldowns.get("plunder",0)>s.day:return fail("船员本日已分得酬劳")
		s.player.silver-=cost;s.player.morale=clamp(s.player.morale+25,0,100);meta.cooldowns["plunder"]=s.day+1;add_log("分给船员%d两，士气提升。"%cost);return {"ok":true,"cost":cost,"navalChanged":true}
	if type=="retire":
		refresh();var career=s.career;career.score=max(0,floor(s.player.silver/10.0+s.player.fame*3+career.battlesWon*75+career.shipsCaptured*40+career.portsVisited.size()*25+career.sitesVisited.size()*20+career.treasureFound*50+(1000 if s.mainChapter==7 else 0)-career.injuries*30-20*career.get("surrenders",0)));career.retired=true
		var path="台湾功臣" if s.mainChapter==7 else "海上枭雄" if s.player.infamy>s.player.fame else "海商巨擘" if career.tradeProfit>500 else "逐浪名将" if career.battlesWon>=3 else "沿海船长"
		career.ending="%s以%d岁之龄归航，成为%s。留下%d两、%d名望、%d场胜仗与%d港见闻。生涯评定：%d分。"%[s.player.name,s.player.age,path,s.player.silver,s.player.fame,career.battlesWon,career.portsVisited.size(),career.score];add_log(career.ending);return {"ok":true}
	return fail("未知操作")
func distance(a,b):return sqrt(pow(a.x-b.x,2)+pow(a.z-b.z,2))
func total_cargo():
	var total=empty_cargo()
	for f in state.fleet:
		for g in C.GOODS:total[g]+=f.cargo[g]
	return total
func reserved(good):
	var n=0
	for q in state.quests:
		if q.kind=="delivery" and q.status in ["active","ready"] and q.get("good")==good:n+=q.get("quantity",0)
	return n
func take_cargo(good,quantity):
	for f in state.fleet:
		var take=min(quantity,f.cargo[good]);f.cargo[good]-=take;quantity-=take
		if quantity==0:break
func trade_quote(type,good,quantity):
	var s=state;var p=port(s.currentPortId);var ship=flagship();var stock=s.markets[p.id][good]
	if type=="buy":
		if stock<quantity:return fail("港口库存不足")
		if cargo_size(ship.cargo)+quantity>ship.capacity:return fail("旗舰货舱不足")
	else:
		if ship.cargo[good]<quantity or total_cargo()[good]-quantity<reserved(good):return fail("货物不足或已留作任务货物")
		if stock+quantity>100000:return fail("港口库存容量不足，无法收购这批货物")
	var relation_factor=max(1-clamp(s.relations[p.faction],-100,100)*.002,sqrt((1-p.tax)/(1+p.tax)));var ask=relation_factor*(1+p.tax);var bid=min((1-p.tax)/relation_factor,ask);var value=0.0
	for i in int(quantity):
		var level=stock-i if type=="buy" else stock+i+1;value+=p.prices[good]*(1.15 if level<p.stock[good]*.25 else .9 if level>p.stock[good]*1.5 else 1)
	if type=="buy":
		var cost=ceil(value*ask)
		if s.player.silver<cost:return fail("银两不足")
		return {"ok":true,"cost":cost}
	return {"ok":true,"reward":floor(value*bid)}
func accept_quest(id):
	var s=state;var q=find_by(s.quests,id)
	if q==null or q.status not in ["available","failed"]:return fail("委托不存在或已接取/结算")
	if q.get("mainStep",0)!=0 and q.mainStep!=s.mainChapter:return fail("请先完成前一章主线")
	if s.currentPortId!=q.issuerPortId:return fail("请到委托发布港接取")
	if q.kind=="delivery" and total_cargo()[q.good]-reserved(q.good)<q.get("quantity",0):return fail("请先购足委托要求的货物")
	if s.quests.filter(func(x):return x.status in ["active","ready"]).size()>=4:return fail("同时最多承接四项委托")
	q.status="active";q.acceptedDay=s.day;q.expiresDay=s.day+q.deadlineDays;q.progress=0
	if q.has("targetId"):
		meta.targets.erase(q.targetId);meta.settledTargets=meta.settledTargets.filter(func(x):return not x.ends_with(":"+q.targetId));meta.capturedTargets.erase(q.targetId);meta.rescuedTargets.erase(q.targetId)
	add_log("接取「%s」，限%d日。"%[q.title,q.deadlineDays]);progress_quests();return {"ok":true,"navalChanged":q.has("targetId")}
func complete_quest(id):
	progress_quests();var s=state;var q=find_by(s.quests,id)
	if q==null or q.status!="ready":return fail("委托目标尚未完成")
	var destination=q.get("destinationPortId") if q.kind in ["delivery","escort","rescue"] else q.issuerPortId
	if s.currentPortId!=destination:return fail("请到任务交付港结算")
	if q.kind=="delivery":
		if total_cargo()[q.good]<q.quantity:return fail("交付货物不足")
		take_cargo(q.good,q.quantity)
	q.status="completed";s.player.silver+=q.reward;s.player.fame+=q.fame;s.relations[q.faction]=clamp(s.relations[q.faction]+8,-100,100)
	if q.has("mainStep"):s.mainChapter=q.mainStep+1
	add_log("完成「%s」，获%d两、%d名望。%s"%[q.title,q.reward,q.fame,"郑氏收复台湾的航程告一段落；你仍可自由贸易探索，或在港口退休。" if q.get("mainStep")==6 else ""])
	if not q.has("mainStep"):add_repeatables(q.kind,q.issuerPortId)
	return {"ok":true,"reward":q.reward,"navalChanged":q.has("targetId")}
func progress_quests():
	for q in state.quests:
		if q.status not in ["active","ready"]:continue
		if state.day>q.get("expiresDay",INF):q.status="failed";add_log("「%s」逾期，可回发布港重新接取。"%q.title);continue
		var target=meta.targets.get(q.get("targetId"))
		if q.kind=="boarding" and target!=null and target.setup.get("hull",100)<=0 and q.targetId not in meta.capturedTargets:q.status="failed";add_log("「%s」目标沉没，密令未得，可回港重新接取。"%q.title);continue
		if q.kind=="delivery":q.progress=q.required if state.currentPortId==q.destinationPortId and total_cargo()[q.good]>=q.quantity else 0
		if q.kind in ["escort","rescue"]:
			if target!=null and target.setup.get("hull",100)<=0:q.status="failed";add_log("「%s」目标沉没，可回港重试。"%q.title);continue
			var p=port(q.destinationPortId)
			if target!=null and target.setup.get("hull",100)>0 and distance(target.setup.position,p)<=90 and (q.kind!="rescue" or q.targetId in meta.rescuedTargets):q.progress=1
		if q.kind=="bounty":q.progress=1 if target_settled(q.targetId) else 0
		if q.kind=="boarding":q.progress=1 if q.targetId in meta.capturedTargets else 0
		if q.kind=="clues":q.progress=meta.clues.size()
		if q.kind=="finale":q.progress=(1 if target_settled(q.targetId) else 0)+(1 if q.siteId in meta.landWon else 0)
		q.status="ready" if q.progress>=q.required else "active"
func target_settled(id):
	if id in meta.capturedTargets:return true
	for key in meta.settledTargets:
		if key.ends_with(":"+id):return true
	return false
func add_repeatables(kind=null,issuer=null):
	var definitions=[{"kind":"delivery","port":"quanzhou","destination":"penghu","title":"海商运瓷","reward":350,"good":"porcelain","quantity":8},{"kind":"escort","port":"xiamen","destination":"kinmen","title":"民船护航","reward":200},{"kind":"bounty","port":"kinmen","destination":"dongshan","title":"清剿劫船者","reward":260},{"kind":"explore","port":"penghu","site":"dongshan-cave","title":"访查古海洞","reward":160},{"kind":"rescue","port":"xiamen","destination":"xiamen","title":"救援遇险渔民","reward":180}]
	for d in definitions:
		if kind!=null and (d.kind!=kind or d.port!=issuer):continue
		meta.questSequence+=1;var id="side-%s-%d"%[d.kind,meta.questSequence];var description="备齐%d%s，运抵%s。"%[d.quantity,C.GOOD_NAMES[d.good],port(d.destination).name] if d.kind=="delivery" else "登岸踏查指定海洞，并返回报告。" if d.kind=="explore" else "护送遇险渔船回到厦门锚地。" if d.kind=="rescue" else "护航须抵达真实锚地；讨伐须击败指定敌船。"
		var q={"id":id,"title":d.title,"description":description,"kind":d.kind,"status":"available","issuerPortId":d.port,"reward":d.reward,"fame":8,"faction":port(d.port).faction,"deadlineDays":18,"progress":0,"required":d.get("quantity",1)}
		for key in ["good","quantity"]:
			if d.has(key):q[key]=d[key]
		if d.has("destination"):q.destinationPortId=d.destination
		if d.has("site"):q.siteId=d.site
		if d.kind in ["escort","bounty","rescue"]:q.targetId="target-"+id
		state.quests.append(q)
func land(c):
	var site=find_by(C.LAND_SITES,c.get("siteId"));var s=state
	if site==null or site.portId!=s.currentPortId:return fail("须在此遗迹所属港口登岸")
	if c.type=="visit-land":
		if site.id not in meta.visitedSites:meta.visitedSites.append(site.id);s.career.sitesVisited.append(site.id);s.player.fame+=3;add_log("登岸探索%s。"%site.name)
		if site.kind=="clue" and site.id not in meta.clues:meta.clues.append(site.id);add_log("从%s取得藏宝图线索（%d/3）。"%[site.name,meta.clues.size()])
		for q in s.quests:
			if q.kind=="explore" and q.status=="active" and q.get("siteId")==site.id:q.progress=1
		progress_quests();return {"ok":true}
	if site.id not in meta.visitedSites:return fail("请先登岸勘察地点")
	if c.type=="resolve-treasure":
		if not c.get("found") is bool or site.kind!="treasure":return fail("无效寻宝结果")
		if meta.clues.size()<3:return fail("尚缺三岛藏宝线索")
		if site.id in meta.treasures:return fail("此处宝藏已取走")
		if meta.cooldowns.get("treasure:"+site.id,0)>s.day:return fail("今日已搜寻此处，请明日再来")
		meta.cooldowns["treasure:"+site.id]=s.day+1
		if not c.found:
			s.player.morale=clamp(s.player.morale-3,0,100);var injured=record_injury(c.get("injury"));add_log("挖掘未中，线索仍在，下次可重试。");return {"ok":true,"navalChanged":injured}
		meta.treasures.append(site.id);s.player.silver+=site.reward;s.career.treasureFound+=1;s.player.fame+=12;var injured=record_injury(c.get("injury"));add_log("藏银湾寻得%d两宝藏。"%site.reward);return {"ok":true,"reward":site.reward,"navalChanged":injured}
	if not c.get("victory") is bool or site.kind!="fort":return fail("此地没有陆战目标")
	if site.id in meta.landWon:return fail("炮台已攻占")
	var finale=find_by(s.quests,"main-6")
	if finale==null or finale.status not in ["active","ready"] or not target_settled(finale.targetId):return fail("须先完成海上守舰战斗")
	if meta.cooldowns.get("land:"+site.id,0)>s.day:return fail("此战刚刚结束，请明日再战")
	meta.cooldowns["land:"+site.id]=s.day+1
	if not c.victory:
		var f=flagship();f.crew=max(1,f.crew-6);s.player.morale=clamp(s.player.morale-10,0,100);record_injury(c.get("injury"),true,false);add_log("陆战撤退，伤兵归船。");return {"ok":true,"navalChanged":true}
	meta.landWon.append(site.id);s.player.silver+=site.reward;s.player.fame+=20;s.relations.voc=clamp(s.relations.voc-20,-100,100);var injured=record_injury(c.get("injury"));add_log("鹿耳门炮台告捷。");progress_quests();return {"ok":true,"reward":site.reward,"navalChanged":injured}
func record_injury(severity=null,legacy_failure=false,consequences=true):
	if severity==null and not legacy_failure:return false
	var injury=severity if severity!=null else 50;state.career.lastInjurySeverity=injury
	if injury>=50:state.career.injuries+=1
	if consequences and injury>0:var f=flagship();f.crew=max(1,f.crew-ceil(injury/20.0));state.player.morale=clamp(state.player.morale-ceil(injury/10.0),0,100)
	add_log("伤势记录%s%%；%s"%[js_number(injury),"留下生涯旧伤。" if injury>=50 else "已处置轻伤。"]);return injury>0
func js_number(n):return str(int(n)) if float(n)==floor(float(n)) else str(n)
func record_victory(battle_id):
	if battle_id in meta.victories:return
	meta.victories.append(battle_id);state.career.battlesWon+=1;state.player.fame+=10;add_log("海战胜利，战果录入生涯。")
func naval_battle_id(n):
	if n.has("battleId"):return n.battleId
	var ids=[]
	for s in n.ships:
		if s.team=="hostile":ids.append(s.id)
	ids.sort();return "%d-%s"%[meta.battleEpoch,"|".join(ids)]
func board(c):
	var target_id=c.get("targetId");var success=c.get("success");var disposition=c.get("disposition","capture");var s=state
	var target=find_by(latestNaval.ships,target_id) if latestNaval!=null else null;var own=find_by(latestNaval.ships,s.flagshipId) if latestNaval!=null else null
	if s.currentPortId!=null or target==null or own==null or target.team!="hostile" or target.hull<=0 or not success is bool:return fail("接舷目标无效或不在海上")
	if target_settled(target_id):return fail("此船战利品已结算")
	var p=target.visual.position;var o=own.visual.position;var tv=target.visual.velocity;var ov=own.visual.velocity
	if distance(p,o)>36 or distance(tv,ov)>3:return fail("接舷需要36米内且相对速度不超过3米/秒")
	if float(target.hull)/target.maxHull>.65 and float(target.crew)/target.maxCrew>.6:return fail("先削弱敌船船体或船员再接舷")
	if meta.cooldowns.get("boarding:"+target_id,0)>s.elapsedSeconds:return fail("接舷尚在冷却")
	if success and disposition=="capture" and s.fleet.size()>=6:return fail("舰队已满，请先处理船位")
	var profile=C.SHIP_PROFILES[target.kind];var f=flagship();var volunteers=max(0,profile.minCrew-floor(target.crew/2.0))
	if success and disposition=="capture" and f.crew-volunteers<C.SHIP_PROFILES[f.kind].minCrew:return fail("没有足够船员操纵缴获船只")
	meta.cooldowns["boarding:"+target_id]=s.elapsedSeconds+30
	if not success:f.crew=max(1,f.crew-4);s.player.morale=clamp(s.player.morale-8,0,100);record_injury(c.get("injury"),true,false);add_log("接舷失利，撤回本船。");return {"ok":true,"navalChanged":true}
	var battle_id=naval_battle_id(latestNaval);meta.settledTargets.append(battle_id+":"+target_id);meta.capturedTargets.append(target_id)
	if disposition=="capture":
		f.crew-=volunteers;meta.shipSequence+=1;var acquired=initial_ship("prize-%d"%meta.shipSequence,target.kind,"缴获·"+target.name,profile.minCrew);acquired.hull=max(15,min(acquired.maxHull,target.hull));acquired.sail=max(10,min(acquired.maxSail,target.sail));acquired.ammo=target.ammo.duplicate();acquired.position=p.duplicate();acquired.heading=target.visual.heading;acquired.speed=distance(tv,{"x":0,"z":0});s.fleet.append(acquired);s.career.shipsCaptured+=1;loot(target_id,120);change_combat_relations(target_id,true);add_log("接舷胜利，将%s编入舰队。"%target.name)
	elif disposition=="plunder":loot(target_id,120);change_combat_relations(target_id,true);add_log("缴械%s，只取战利品，不编入舰队。"%target.name)
	else:s.player.fame+=4;s.player.infamy=max(0,s.player.infamy-1);s.player.morale=clamp(s.player.morale+3,0,100);var faction=combat_faction(target_id);s.relations[faction]=clamp(s.relations[faction]+2,-100,100);add_log("放行%s，宽待降者，声望提升、恶名降低。"%target.name)
	record_injury(c.get("injury"));var hostiles=latestNaval.ships.filter(func(x):return x.team=="hostile")
	if not hostiles.is_empty() and hostiles.all(func(x):return x.hull<=0 or target_settled(x.id)):record_victory(battle_id)
	progress_quests();return {"ok":true,"navalChanged":true,"reward":0 if disposition=="release" else 120}
func advance(seconds):
	if state.is_empty():return false
	if not bounded(seconds,0,8640000):last_error="无效模拟时间";return false
	if seconds==0 or paused or state.currentPortId!=null or state.career.retired or state.has("pendingSurrenderReceipt"):return true
	var s=state;var new_time=s.elapsedSeconds+seconds;var next_day=1+floor((new_time+1e-7)/300.0);s.elapsedSeconds=new_time
	while s.day<next_day:
		s.day+=1;var costs=daily_costs();var available=max(0,total_cargo().grain-reserved("grain"));take_cargo("grain",min(costs.grain,available))
		if s.player.silver>=costs.silver:s.player.silver-=costs.silver
		else:s.player.silver=0;s.player.morale=clamp(s.player.morale-6,0,100)
		if available<costs.grain:
			for f in s.fleet:f.crew=max(1,f.crew-1)
			s.player.morale=clamp(s.player.morale-8,0,100);add_log("缺粮：船员减员、士气下滑，请尽快靠港补给。")
		else:s.player.morale=clamp(s.player.morale-1,0,100)
		s.player.age=22+floor((s.day-1)/365.0)
		if int(s.day)%365==0:s.career.injuries+=1;add_log("长年航海留下旧伤，航速受到影响。")
		for p in C.PORTS:
			for g in C.GOODS:s.markets[p.id][g]=min(p.stock[g]*2,s.markets[p.id][g]+5)
			for ammo in ["solid","chain","grape"]:s.ammoStocks[p.id][ammo]=min(C.AMMO_STOCKS[ammo]*2,s.ammoStocks[p.id][ammo]+5)
		s.weather=weather_for(s.seed,s.day);progress_quests()
	refresh();return true
func naval_state(ship):return {"cooldownSeconds":ship.cooldownSeconds.duplicate(),"ammoType":ship.ammoType,"rudder":ship.rudder,"sailAngle":ship.sailAngle,"autoTrim":ship.autoTrim,"sailDeployment":ship.sailDeployment}
func syncDockedFleet(n):
	if state.currentPortId==null:return true
	var owned=find_by(n.ships,state.flagshipId)
	if owned==null or distance(owned.visual.velocity,{"x":0,"z":0})>1e-7:last_error="靠港舰队尚未完成锚定";return false
	state.position=owned.visual.position.duplicate();state.heading=owned.visual.heading;state.speed=0
	for fleet in state.fleet:
		var ship=find_by(n.ships,fleet.id)
		if ship==null:continue
		fleet.position=ship.visual.position.duplicate();fleet.heading=ship.visual.heading;fleet.speed=0;fleet.navalState=naval_state(ship)
	latestNaval=n.duplicate(true);refresh();return true
func sync_docked_fleet(n):return syncDockedFleet(n)
func syncNaval(n,events=[]):
	if state.currentPortId!=null or state.career.retired:return
	var s=state;var owned=find_by(n.ships,s.flagshipId)
	if owned==null:return
	latestNaval=n.duplicate(true)
	if n.tick<meta.lastNavalTick:meta.battleEpoch+=1
	meta.lastNavalTick=n.tick;var battle_id=naval_battle_id(n);s.position=owned.visual.position.duplicate();s.speed=distance(owned.visual.velocity,{"x":0,"z":0});s.heading=owned.visual.heading;s.battleActive=n.status=="active"
	for ship in n.ships:
		var f=find_by(s.fleet,ship.id)
		if f!=null:f.hull=clamp(ship.hull,0,f.maxHull);f.sail=clamp(ship.sail,0,f.maxSail);f.crew=clamp(floor(ship.crew+1e-7),0,f.maxCrew);f.ammo=ship.ammo.duplicate();f.position=ship.visual.position.duplicate();f.heading=ship.visual.heading;f.speed=distance(ship.visual.velocity,{"x":0,"z":0});f.navalState=naval_state(ship)
		else:
			var ambient=find_by(C.AMBIENT_VESSELS,ship.id);var route_leg=meta.targets.get(ship.id,{}).get("routeLeg",1)
			if ambient!=null:
				var p=port(ambient.routePortIds[int(route_leg)])
				if ship.hull>0 and distance(ship.visual.position,p)<=70:route_leg=(int(route_leg)+1)%ambient.routePortIds.size()
			var setup={"id":ship.id,"name":ship.name,"kind":ship.kind,"team":ship.team,"position":ship.visual.position.duplicate(),"heading":ship.visual.heading,"speed":distance(ship.visual.velocity,{"x":0,"z":0}),"hull":ship.hull,"sail":ship.sail,"crew":ship.crew,"ammo":ship.ammo.duplicate(),"stats":ship.stats.duplicate()};setup.merge(naval_state(ship));meta.targets[ship.id]={"setup":setup,"maxHull":ship.maxHull,"maxCrew":ship.maxCrew,"speed":setup.speed}
			if ambient!=null:meta.targets[ship.id].routeLeg=route_leg
			for q in s.quests:
				if q.kind=="rescue" and q.status=="active" and q.get("targetId")==ship.id and ship.hull>0 and ship.id not in meta.rescuedTargets and distance(ship.visual.position,owned.visual.position)<=45:meta.rescuedTargets.append(ship.id);add_log("抵近遇险渔船，船员已经救援；请护送渔船返港。");break
	for event in events:
		if event.type in ["fire","splash"]:continue
		var key=battle_id+":"+(js_number(event.id) if typeof(event.id) in [TYPE_INT,TYPE_FLOAT] else str(event.id))
		if key in meta.seenEvents:continue
		meta.seenEvents.append(key)
		if event.type=="hit" and find_by(s.fleet,event.get("shipId"))!=null:
			var target=find_by(n.ships,event.get("targetId"))
			if target!=null and target.team!="player" and (event.damage.hull>0 or event.damage.sail>0 or event.damage.crew>0):change_combat_relations(target.id,false)
		if event.type=="sink":
			var target=find_by(n.ships,event.shipId);var settlement=battle_id+":"+event.shipId
			if target!=null and target.team=="hostile" and target.hull<=0 and settlement not in meta.settledTargets and target.id not in meta.capturedTargets:meta.settledTargets.append(settlement);loot(target.id,90);change_combat_relations(target.id,true)
		if event.type=="victory" and n.status=="victory":
			var hostiles=n.ships.filter(func(f):return f.team=="hostile")
			if not hostiles.is_empty() and hostiles.all(func(f):return f.hull<=0 or target_settled(f.id)):record_victory(battle_id)
		if event.type=="defeat" and n.status=="defeat" and owned.hull<=0:recover()
	progress_quests();refresh()
func sync_naval(n,events=[]):syncNaval(n,events)
func loot(id,silver):
	state.player.silver+=silver;state.career.totalPlunder+=silver;state.player.morale=clamp(state.player.morale+4,0,100);var f=flagship();var quantity=min(4,f.capacity-cargo_size(f.cargo));f.cargo.grain+=quantity;add_log("取得%s战利品：%d两、粮食%d袋。"%[id,silver,quantity])
func combat_faction(id):
	var ambient=find_by(C.AMBIENT_VESSELS,id)
	if ambient!=null:return ambient.faction
	var q=null
	for item in state.quests:
		if item.get("targetId")==id:q=item;break
	if q!=null and q.kind in ["escort","rescue"]:return q.faction
	var target=meta.targets.get(id)
	return "pirates" if "pirate" in id or (q!=null and q.kind=="bounty") else "voc" if "voc" in id or "taiwan" in id or (target!=null and target.setup.kind=="voc") else "qing" if "qing" in id else "zheng" if "zheng" in id else "pirates"
func change_combat_relations(id,decisive):
	var faction=combat_faction(id);var key="relations:%s:%s"%[id,"decisive" if decisive else "attack"]
	if key in meta.seenEvents:return
	meta.seenEvents.append(key);state.relations[faction]=clamp(state.relations[faction]-(12 if decisive else 3),-100,100)
	if faction=="pirates":state.relations.zheng=clamp(state.relations.zheng+(3 if decisive else 1),-100,100)
	else:state.player.infamy+=4 if decisive else 1;state.relations.zheng=clamp(state.relations.zheng+((3 if decisive else 1) if faction=="voc" else 0),-100,100)
func ensure_ambient():
	for vessel in C.AMBIENT_VESSELS:
		if meta.targets.has(vessel.id) or target_settled(vessel.id):continue
		var p=port(vessel.homePortId);var destination=port(vessel.routePortIds[1]);var hash_value=int(state.seed)
		for character in vessel.id:hash_value=((hash_value^character.unicode_at(0))*16777619)&0xffffffff
		var outward=vessel.spawn.outward+(hash_value&1023)/1023.0*20-10;var lateral=vessel.spawn.lateral+((hash_value>>10)&1023)/1023.0*20-10;var length=sqrt(p.islandX*p.islandX+p.islandZ*p.islandZ);var nx=-p.islandX/length;var nz=-p.islandZ/length;var position={"x":p.x+nx*outward-nz*lateral,"z":p.z+nz*outward+nx*lateral};var max_crew=C.SHIP_PROFILES[vessel.kind].crew
		meta.targets[vessel.id]={"setup":{"id":vessel.id,"name":vessel.name,"kind":vessel.kind,"team":vessel.team,"position":position,"heading":atan2(destination.z-position.z,destination.x-position.x),"speed":0,"hull":vessel.hull,"sail":100,"crew":vessel.crew,"sailDeployment":.7,"autoTrim":true,"sailAngle":0,"rudder":0,"ammo":{"solid":40 if vessel.team=="hostile" else 0,"chain":0,"grape":0},"stats":{"maxHull":100,"maxCrew":max_crew,"cargoMass":vessel.cargoMass,"speedMultiplier":vessel.speedMultiplier,"cannonMultiplier":.75 if vessel.team=="hostile" else 1}},"maxHull":100,"maxCrew":max_crew,"speed":0,"routeLeg":1}
func ambientNavalSetup():
	var result=[]
	for v in C.AMBIENT_VESSELS:
		if not target_settled(v.id) and meta.targets.get(v.id,{}).get("setup",{}).get("hull",0)>0:result.append(meta.targets[v.id].setup.duplicate(true))
	return result
func ambient_naval_setup():return ambientNavalSetup()
func ambientWaypoints():
	var routes={}
	for v in C.AMBIENT_VESSELS:
		var target=meta.targets.get(v.id)
		if target==null or target_settled(v.id) or target.setup.get("hull",0)<=0 or (v.team=="neutral" and target.setup.team=="hostile"):continue
		var p=port(v.routePortIds[int(target.get("routeLeg",1))]);routes[v.id]={"x":p.x,"z":p.z}
	return routes
func ambient_waypoints():return ambientWaypoints()
func recover():
	var s=state;var home=port("xiamen");var f=flagship();s.player.silver=floor(s.player.silver*.65);s.player.morale=40;s.career.injuries+=1
	for ship in s.fleet:ship.hull=max(ship.hull,ship.maxHull*.5);ship.sail=max(ship.sail,50);ship.crew=max(ship.crew,C.SHIP_PROFILES[ship.kind].minCrew)
	for g in C.GOODS:f.cargo[g]=floor(f.cargo[g]*.5)
	f.cargo.grain=max(f.cargo.grain,8);s.position={"x":home.x,"z":home.z};s.speed=0;s.currentPortId=home.id;s.battleActive=false
	for q in s.quests:
		if q.status in ["active","ready"]:q.status="failed"
	for ship in s.fleet:ship.position=s.position.duplicate();ship.speed=0
	add_log("水师渔民将你救回厦门。损失部分银两与货物，添一处旧伤；船只经最低修复，可整备再起。")
func quoteSurrender():
	var s=state;var n=latestNaval
	if s.currentPortId!=null or s.career.retired or s.has("pendingSurrenderReceipt"):return fail("当前航程无法投降")
	if n==null or n.status!="active" or n.playerId!=s.flagshipId or flagship().hull<=0:return fail("须在旗舰存活的真实交战中投降")
	if "surrender:"+n.battleId in meta.seenEvents:return fail("此战投降已结算")
	var player=find_by(n.ships,s.flagshipId)
	if player==null or player.hull<=0:return fail("旗舰已沉没")
	var captors=n.ships.filter(func(x):return x.team=="hostile" and x.hull>0 and not target_settled(x.id))
	captors.sort_custom(func(a,b):return distance(a.visual.position,player.visual.position)<distance(b.visual.position,player.visual.position) if distance(a.visual.position,player.visual.position)!=distance(b.visual.position,player.visual.position) else Text.less(a.id,b.id))
	if captors.is_empty():return fail("没有可受降的未结算敌舰")
	var captor=captors[0];return {"ok":true,"quote":create_surrender_quote({"id":captor.id,"name":captor.name,"faction":combat_faction(captor.id)})}
func quote_surrender():return quoteSurrender()
func create_surrender_quote(captor):
	var s=state;var loss=ceil(s.player.silver/4.0);var terms={"captor":captor.duplicate(),"returnPortId":"xiamen","silver":{"before":s.player.silver,"loss":loss,"after":s.player.silver-loss},"morale":{"before":s.player.morale,"after":max(0,s.player.morale-20)},"fame":{"before":s.player.fame,"after":max(0,s.player.fame-5)},"relation":{"before":s.relations[captor.faction],"after":max(-100,s.relations[captor.faction]-5)},"shipLosses":[],"lostShips":[],"failedQuests":[],"completedQuestIds":[],"mainChapter":s.mainChapter,"surrenders":{"before":s.career.get("surrenders",0),"after":s.career.get("surrenders",0)+1}}
	var ships=s.fleet.duplicate();ships.sort_custom(func(a,b):return Text.less(a.id,b.id))
	for ship in ships:
		if ship.hull<=0:terms.lostShips.append({"id":ship.id,"name":ship.name,"kind":ship.kind});continue
		var cargo_loss=empty_cargo();var after=empty_cargo()
		for g in C.GOODS:cargo_loss[g]=ceil(ship.cargo[g]/4.0);after[g]=ship.cargo[g]-cargo_loss[g]
		terms.shipLosses.append({"shipId":ship.id,"name":ship.name,"before":ship.cargo.duplicate(),"loss":cargo_loss,"after":after,"hull":ship.hull,"maxHull":ship.maxHull,"sail":ship.sail,"crew":ship.crew,"ammo":ship.ammo.duplicate()})
	var quests=s.quests.duplicate();quests.sort_custom(func(a,b):return Text.less(a.id,b.id))
	for q in quests:
		if q.status in ["active","ready"]:terms.failedQuests.append({"id":q.id,"title":q.title,"before":q.status})
		if q.status=="completed":terms.completedQuestIds.append(q.id)
	return {"token":{"battleId":latestNaval.battleId,"tick":latestNaval.tick,"lossDigest":canonical_surrender_terms(terms)},"terms":terms}
static func canonical_surrender_terms(terms):
	return Surrender.canonical_terms(terms)
func surrender(token):
	var preview_result=quoteSurrender()
	if not preview_result.ok:return fail(preview_result.reason)
	var quote=preview_result.quote
	if not token is Dictionary or token.get("battleId")!=quote.token.battleId or token.get("tick")!=quote.token.tick or token.get("lossDigest")!=quote.token.lossDigest:return fail("投降条件已变化，请重新确认")
	var s=state;var t=quote.terms;var home=port(t.returnPortId);s.player.silver=t.silver.after;s.player.morale=t.morale.after;s.player.fame=t.fame.after;s.relations[t.captor.faction]=t.relation.after;s.career.surrenders=t.surrenders.after;s.fleet=s.fleet.filter(func(f):return f.hull>0)
	for f in s.fleet:
		for item in t.shipLosses:
			if item.shipId==f.id:f.cargo=item.after.duplicate();break
		f.position={"x":home.x,"z":home.z};f.speed=0
		if f.get("navalState")!=null:f.navalState.rudder=0;f.navalState.sailDeployment=0
	for q in s.quests:
		if q.status in ["active","ready"]:q.status="failed"
	s.position={"x":home.x,"z":home.z};s.speed=0;s.currentPortId=home.id;s.battleActive=false;var id="surrender:"+quote.token.battleId;meta.seenEvents.append(id);s.pendingSurrenderReceipt={"version":1,"id":id,"acceptedDay":s.day,"quote":quote.duplicate(true)};add_log("向%s降旗投降，损失%d两；幸存船按原状返回厦门，等待结果确认。"%[t.captor.name,t.silver.loss]);return {"ok":true,"navalChanged":true}
func navalSetup():
	var s=state;var all=[];var ordered=[flagship()]+s.fleet.filter(func(f):return f.id!=s.flagshipId);var reload_multiplier=1.0;var sailing_multiplier=1.0
	for role in s.officers:reload_multiplier*=C.OFFICERS[role].reloadMultiplier;sailing_multiplier*=C.OFFICERS[role].speedMultiplier
	for i in ordered.size():
		var f=ordered[i];var saved_controls=f.get("navalState")
		saved_controls={} if saved_controls==null else saved_controls
		var setup={"id":f.id,"name":f.name,"kind":f.kind,"team":"player","position":f.position.duplicate() if i!=0 and f.get("position")!=null else s.position.duplicate(),"heading":f.get("heading",s.heading),"speed":f.get("speed",0) if i!=0 else s.speed,"hull":f.hull,"sail":f.sail,"crew":f.crew,"ammo":f.ammo.duplicate()}
		setup.merge(saved_controls.duplicate());setup.sailDeployment=0 if s.currentPortId!=null else saved_controls.get("sailDeployment",1)
		setup.stats={"hullMultiplier":pow(1.2,f.upgrades.hull),"maxHull":f.maxHull,"maxCrew":f.maxCrew,"cannonMultiplier":pow(1.15,f.upgrades.cannons),"reloadMultiplier":reload_multiplier,"steeringMultiplier":1+.15*f.upgrades.get("equipment",0),"speedMultiplier":pow(1.08,f.upgrades.sails)*sailing_multiplier*(.6+s.player.morale*.004)*max(.65,1-s.career.injuries*.025)};all.append(setup)
	for q in s.quests:
		if q.status not in ["active","ready"] or not q.has("targetId") or target_settled(q.targetId):continue
		if meta.targets.has(q.targetId):all.append(meta.targets[q.targetId].setup.duplicate(true));continue
		var destination=port(q.get("destinationPortId"));destination=destination if destination!=null else port(q.issuerPortId);var start=port(q.issuerPortId);var neutral=q.kind in ["escort","rescue"];var kind="fisherman" if neutral else "voc" if q.kind=="boarding" else "fuchuan" if q.kind=="finale" else "patrol";var origin=start if neutral else destination;var d=sqrt(origin.islandX*origin.islandX+origin.islandZ*origin.islandZ);var reach=230 if q.kind=="rescue" else 65 if neutral else 140
		all.append({"id":q.targetId,"name":"VOC船长·范德伦" if q.kind=="boarding" else q.title,"kind":kind,"team":"neutral" if neutral else "hostile","position":{"x":origin.x-origin.islandX/d*reach,"z":origin.z-origin.islandZ/d*reach},"hull":85 if q.kind=="finale" else 70,"sail":75,"crew":12 if neutral else 38 if q.kind=="boarding" else 28,"sailDeployment":.7 if neutral else 1,"stats":{"maxHull":100,"maxCrew":C.SHIP_PROFILES[kind].crew,"cannonMultiplier":.8}})
	return all
func naval_setup():return navalSetup()
func naval_target_position(q,p):
	var target=meta.targets.get(q.get("targetId"))
	if target!=null:return target.setup.position.duplicate()
	var origin=port(q.issuerPortId) if q.kind=="rescue" else p;var reach=230 if q.kind=="rescue" else 140;var d=sqrt(origin.islandX*origin.islandX+origin.islandZ*origin.islandZ);return {"x":origin.x-origin.islandX/d*reach,"z":origin.z-origin.islandZ/d*reach}
func objectives():
	var result=[]
	for q in state.quests:
		if q.status not in ["active","ready"]:continue
		if q.kind=="rescue" and q.has("targetId") and meta.targets.get(q.targetId,{}).get("setup",{}).get("hull",100)<=0:continue
		var p=port(q.get("destinationPortId",q.issuerPortId));var enemy=q.kind not in ["escort","rescue"];var spawn=naval_target_position(q,p);var approaching_rescue=q.kind=="rescue" and q.targetId not in meta.rescuedTargets
		if q.has("targetId") and not target_settled(q.targetId):
			var objective={"id":q.targetId,"questId":q.id,"kind":"escort" if q.kind=="escort" else "rescue" if q.kind=="rescue" else "enemy","targetId":q.targetId,"position":spawn if enemy or approaching_rescue else {"x":p.x,"z":p.z},"shipKind":"voc" if q.kind=="boarding" else "fisherman" if q.kind in ["escort","rescue"] else "fuchuan" if q.kind=="finale" else "patrol","faction":"pirates" if q.kind=="bounty" else "voc","required":1,"progress":.5 if q.kind=="rescue" and q.progress==0 and q.targetId in meta.rescuedTargets else q.progress,"label":q.title}
			if enemy:objective.enemyId=q.targetId
			result.append(objective)
		if q.kind=="delivery":result.append({"id":"delivery-"+q.id,"questId":q.id,"kind":"delivery","position":{"x":p.x,"z":p.z},"required":q.required,"progress":q.progress,"label":q.title})
		if q.kind=="clues":
			for site in C.LAND_SITES:
				if site.kind=="clue" and site.id not in meta.clues:result.append({"id":site.id,"questId":q.id,"kind":"treasure","position":{"x":site.x,"z":site.z},"required":1,"progress":0,"label":site.name})
		if q.has("siteId"):var site=find_by(C.LAND_SITES,q.siteId);result.append({"id":site.id,"questId":q.id,"kind":"land" if q.kind=="finale" else "treasure","position":{"x":site.x,"z":site.z},"required":1,"progress":q.progress if q.kind=="explore" else 1 if site.id in meta.visitedSites else 0,"label":site.name})
	return result
func refresh():
	if state.is_empty():return
	state.cargo=total_cargo();state.player.supplies=state.cargo.grain;var fame=state.player.fame;state.career.rank="水师都督" if fame>=180 else "参将" if fame>=80 else "游击船长" if fame>=30 else "新任船长";state.activeObjectives=objectives();var costs=daily_costs();state.supplyPerDay=costs.grain;state.wagesPerDay=costs.silver
func daily_costs():
	var crew=0.0;var factor=1.0;var wages=0
	for f in state.fleet:crew+=f.crew
	for role in state.officers:factor*=C.OFFICERS[role].supplyFactor;wages+=C.OFFICERS[role].dailyWage
	var base=max(1,ceil(crew/24));return {"grain":max(1,floor(base*factor)),"silver":base+wages}
func add_log(message):
	meta.logSequence+=1;state.log.append({"id":meta.logSequence,"day":state.day,"message":message})
	if state.log.size()>120:state.log.pop_front()
func imul32(a,b):return ((int(a)&0xffff)*(int(b)&0xffff)+((((int(a)>>16)&0xffff)*(int(b)&0xffff)+(int(a)&0xffff)*((int(b)>>16)&0xffff))<<16))&0xffffffff
func weather_for(seed,day):
	var n=(int(seed)^imul32(day,0x9e3779b9))&0xffffffff;n=imul32(n^(n>>16),0x85ebca6b);n=imul32(n^(n>>13),0xc2b2ae35);n=(n^(n>>16))&0xffffffff
	var roll=n%100;var kind="clear" if roll<55 else "windy" if roll<78 else "fog" if roll<92 else "storm";var factor={"clear":1,"windy":1.3,"fog":.75,"storm":1.6}[kind];var angle=(n%6283)/1000.0;return {"kind":kind,"label":{"clear":"晴朗","windy":"劲风","fog":"海雾","storm":"风暴"}[kind],"windFactor":factor,"visibility":{"clear":1,"windy":.9,"fog":.42,"storm":.55}[kind],"wind":{"direction":{"x":cos(angle),"y":sin(angle)},"speed":9*factor}}
func serialize():refresh();return Surrender.js_json({"version":1,"state":state,"meta":meta})
func save():
	if storage==null:return fail("未配置存档存储")
	var json=serialize();var written=storage.write(json)
	if written is Dictionary and not written.get("ok",false):return written
	if storage.read()!=json:return fail("存档写入后校验失败，存储未保存完整航程")
	return {"ok":true,"bytes":json.to_utf8_buffer().size()}
func restore(json,new_storage=null,encoded_json=false):
	var parsed=JsonNumbers.new().decode(json,encoded_json)
	if not parsed.ok:last_error="存档JSON损坏，原存档未改动";return false
	var data=parsed.value
	if not data is Dictionary or data.get("version")!=1:last_error="不支持的存档版本";return false
	if data.get("state") is Dictionary:
		var s=data.state
		if not s.has("officers"):s.officers=[]
		if not s.has("ammoStocks"):
			s.ammoStocks={}
			for p in C.PORTS:s.ammoStocks[p.id]=C.AMMO_STOCKS.duplicate()
		if s.get("career") is Dictionary and not s.career.has("surrenders"):s.career.surrenders=0
		if s.get("quests") is Array:
			for q in s.quests:
				if q is Dictionary and q.get("id")=="main-3" and q.get("description")=="击沉或俘获盘踞东山外海的海盗首船。":q.description=find_by(C.MAIN_QUESTS,"main-3").description
	if data.get("meta") is Dictionary and data.meta.get("targets") is Dictionary:
		for vessel in C.AMBIENT_VESSELS:
			var target=data.meta.targets.get(vessel.id)
			if target is Dictionary and not target.has("routeLeg"):target.routeLeg=1
	if not Validator.validate(data.get("state"),data.get("meta")):last_error="存档字段、界限或舰队约束损坏，原存档未改动";return false
	if Text.source_trim(data.state.player.name).is_empty():last_error="船长姓名须为1至24字";return false
	state=data.state.duplicate(true);meta=data.meta.duplicate(true);latestNaval=null;paused=false
	if new_storage!=null:storage=new_storage
	ensure_ambient();refresh();last_error="";return true
static func from_json(json,new_storage=null):
	var instance=load("res://game/domain/legacy/adventure_session.gd").new()
	return instance if instance.restore(json,new_storage) else null
static func load_storage(adapter):
	var json=adapter.read()
	return from_json(json,adapter) if json!=null else null
