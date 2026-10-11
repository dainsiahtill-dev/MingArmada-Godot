extends RefCounted
const Text=preload("res://game/domain/legacy/utf16_text.gd")
const C=preload("res://game/domain/legacy/catalog.gd").DATA
static func num(n,lo,hi):return typeof(n) in [TYPE_FLOAT,TYPE_INT] and is_finite(float(n)) and n>=lo and n<=hi
static func integer(n,lo=0,hi=1000000000):return num(n,lo,hi) and n==floor(n)
static func text(v,maximum=128):return v is String and v.length()>0 and Text.source_length(v)<=maximum
static func strings(v):
	if not v is Array or v.size()>100000:return false
	var seen={}
	for item in v:
		if not text(item,256) or seen.has(item):return false
		seen[item]=true
	return true
static func cargo(v):
	if not v is Dictionary or v.size()!=6:return false
	for g in C.GOODS:
		if not integer(v.get(g),0,100000):return false
	return true
static func cargo_size(v):
	var n=0
	for g in C.GOODS:n+=v[g]
	return n
static func find(items,id):
	for item in items:
		if item is Dictionary and item.get("id")==id:return item
	return null
static func port(id):return find(C.PORTS,id)
static func position(p):return p is Dictionary and num(p.get("x"),-100000,100000) and num(p.get("z"),-100000,100000)
static func distance(a,b):return sqrt(pow(a.x-b.x,2)+pow(a.z-b.z,2))
static func naval_controls(n):
	if not n is Dictionary:return false
	if n.get("cooldownSeconds")!=null:
		if not n.cooldownSeconds is Dictionary or not num(n.cooldownSeconds.get("port"),0,120) or not num(n.cooldownSeconds.get("starboard"),0,120):return false
	if n.has("ammoType") and n.ammoType not in ["solid","chain","grape"]:return false
	for key in {"rudder":[-1,1],"sailAngle":[-PI/2,PI/2],"sailDeployment":[0,1]}:
		var range_value={"rudder":[-1,1],"sailAngle":[-PI/2,PI/2],"sailDeployment":[0,1]}[key]
		if n.has(key) and not num(n[key],range_value[0],range_value[1]):return false
	if n.has("autoTrim") and not n.autoTrim is bool:return false
	return true
static func validate(s,m):
	if not s is Dictionary or not m is Dictionary:return false
	if s.get("version")!=1 or not integer(s.get("seed"),0,0xffffffff) or not num(s.get("elapsedSeconds"),0,1e9) or not integer(s.get("day"),1,3333335):return false
	if s.day!=1+floor((s.elapsedSeconds+1e-7)/300.0) or not s.get("player") is Dictionary or not text(s.player.get("name"),24):return false
	var w=s.get("weather")
	if not w is Dictionary or w.get("kind") not in ["clear","windy","fog","storm"] or not text(w.get("label")) or not num(w.get("windFactor"),.1,3) or not num(w.get("visibility"),.1,1):return false
	if not w.get("wind") is Dictionary or not w.wind.get("direction") is Dictionary or not num(w.wind.direction.get("x"),-1,1) or not num(w.wind.direction.get("y"),-1,1) or not num(w.wind.get("speed"),0,100):return false
	for key in ["silver","fame","infamy"]:
		if not integer(s.player.get(key)):return false
	if not integer(s.player.get("age"),22,10000) or s.player.age!=22+floor((s.day-1)/365.0) or not num(s.player.get("morale"),0,100):return false
	if not s.get("fleet") is Array or s.fleet.size()<1 or s.fleet.size()>6:return false
	var ids={}
	for f in s.fleet:
		if not f is Dictionary or not text(f.get("id"),64) or ids.has(f.id) or find(C.AMBIENT_VESSELS,f.id)!=null or not text(f.get("name"),80) or not C.SHIP_PROFILES.has(f.get("kind")):return false
		ids[f.id]=true;var p=C.SHIP_PROFILES[f.kind]
		if f.get("capacity")!=p.capacity or f.get("maxCrew")!=p.crew or f.get("maxSail")!=100 or not f.get("upgrades") is Dictionary:return false
		for key in ["hull","cannons","sails"]:
			if not integer(f.upgrades.get(key),0,3):return false
		if f.upgrades.has("equipment") and not integer(f.upgrades.equipment,0,3):return false
		if not num(f.get("maxHull"),1,10000) or abs(f.maxHull-100*pow(1.2,f.upgrades.hull))>=1e-7 or not num(f.get("hull"),0,f.maxHull) or not num(f.get("sail"),0,100) or not integer(f.get("crew"),0,f.maxCrew) or not cargo(f.get("cargo")) or cargo_size(f.cargo)>f.capacity:return false
		if not f.get("ammo") is Dictionary:return false
		for ammo in ["solid","chain","grape"]:
			if not integer(f.ammo.get(ammo),0,100000):return false
		if f.get("position")!=null and not position(f.position):return false
		if f.has("heading") and not num(f.heading,-100000,100000):return false
		if f.has("speed") and not num(f.speed,0,1000):return false
		if f.get("navalState")!=null:
			if not naval_controls(f.navalState):return false
			for key in ["cooldownSeconds","ammoType","rudder","sailAngle","autoTrim","sailDeployment"]:
				if not f.navalState.has(key):return false
	if not ids.has(s.get("flagshipId")) or not position(s.get("position")) or not num(s.get("speed"),0,1000) or not num(s.get("heading"),-100000,100000):return false
	if not s.has("currentPortId") or (s.get("currentPortId")!=null and port(s.currentPortId)==null):return false
	if not s.get("battleActive") is bool or (s.currentPortId!=null and s.battleActive) or not integer(s.get("mainChapter"),1,7):return false
	if s.currentPortId!=null and (distance(s.position,port(s.currentPortId))>55 or s.speed!=0):return false
	if not cargo(s.get("cargo")):return false
	for g in C.GOODS:
		var total=0
		for f in s.fleet:total+=f.cargo[g]
		if s.cargo[g]!=total:return false
	if s.player.get("supplies")!=s.cargo.grain or not s.get("relations") is Dictionary:return false
	for faction in ["zheng","qing","voc","pirates"]:
		if not integer(s.relations.get(faction),-100,100):return false
	if not s.get("markets") is Dictionary or s.markets.size()!=6:return false
	for p in C.PORTS:
		if not cargo(s.markets.get(p.id)):return false
	if not strings(s.get("officers")) or s.officers.size()>3:return false
	for role in s.officers:
		if not C.OFFICERS.has(role):return false
	if not s.get("ammoStocks") is Dictionary or s.ammoStocks.size()!=6:return false
	for p in C.PORTS:
		var stock=s.ammoStocks.get(p.id)
		if not stock is Dictionary or stock.size()!=3:return false
		for ammo in ["solid","chain","grape"]:
			if not integer(stock.get(ammo),0,C.AMMO_STOCKS[ammo]*2):return false
	for key in ["supplyPerDay","wagesPerDay"]:
		if s.has(key) and not integer(s[key],1,1000):return false
	if not s.get("quests") is Array or s.quests.size()<6 or s.quests.size()>10000:return false
	var quest_ids={};var active_count=0
	for q in s.quests:
		if not q is Dictionary or not text(q.get("id"),64) or quest_ids.has(q.id) or not text(q.get("title")) or not text(q.get("description"),400):return false
		quest_ids[q.id]=true
		if q.get("kind") not in ["delivery","escort","bounty","clues","boarding","finale","explore","rescue"] or q.get("status") not in ["available","active","ready","completed","failed"]:return false
		if q.status in ["active","ready"]:active_count+=1
		if port(q.get("issuerPortId"))==null or (q.has("destinationPortId") and port(q.destinationPortId)==null):return false
		for key in {"reward":[0,10000],"fame":[0,1000],"required":[1,10000],"deadlineDays":[1,365]}:
			var limits={"reward":[0,10000],"fame":[0,1000],"required":[1,10000],"deadlineDays":[1,365]}[key]
			if not integer(q.get(key),limits[0],limits[1]):return false
		if not integer(q.get("progress"),0,q.required) or q.get("faction") not in ["zheng","qing","voc","pirates"]:return false
		if q.has("good") and q.good not in C.GOODS:return false
		if q.has("quantity") and not integer(q.quantity,1,1000):return false
		if q.has("siteId") and find(C.LAND_SITES,q.siteId)==null:return false
		if q.has("targetId") and (not text(q.targetId,64) or find(C.AMBIENT_VESSELS,q.targetId)!=null):return false
		if q.kind=="delivery":
			if port(q.get("destinationPortId"))==null or q.get("good") not in C.GOODS or not integer(q.get("quantity"),1,1000) or q.required!=q.quantity or q.has("targetId") or q.has("siteId"):return false
		if q.kind in ["escort","rescue","bounty","boarding","finale"] and (not text(q.get("targetId"),64) or port(q.get("destinationPortId"))==null):return false
		if q.kind in ["explore","finale"] and find(C.LAND_SITES,q.get("siteId"))==null:return false
		if q.kind=="finale":
			var site=find(C.LAND_SITES,q.siteId)
			if site.kind!="fort" or site.portId!=q.destinationPortId or q.required!=2:return false
		if q.kind!="delivery" and (q.has("good") or q.has("quantity")):return false
		if q.has("acceptedDay") and not integer(q.acceptedDay,1,s.day):return false
		if q.has("expiresDay") and not integer(q.expiresDay,1,s.day+365):return false
		if q.status in ["active","ready"] and (not q.has("acceptedDay") or q.get("expiresDay")!=q.acceptedDay+q.deadlineDays):return false
		if q.status=="completed" and q.progress!=q.required:return false
		if q.get("mainStep",0)!=0:
			var d=find(C.MAIN_QUESTS,q.id)
			if d==null or d.mainStep!=q.mainStep:return false
			for key in ["title","description","kind","issuerPortId","destinationPortId","targetId","siteId","good","quantity","reward","fame","faction","deadlineDays","required"]:
				if q.get(key)!=d.get(key):return false
			if q.mainStep<s.mainChapter and q.status!="completed":return false
			if q.status=="completed" and q.mainStep>=s.mainChapter:return false
		elif not q.id.begins_with("side-"):return false
	if active_count>4:return false
	for q in C.MAIN_QUESTS:
		if not quest_ids.has(q.id):return false
	var c=s.get("career")
	if not c is Dictionary or not c.get("retired") is bool:return false
	for key in ["battlesWon","shipsCaptured","treasureFound","injuries","totalPlunder","score"]:
		if not integer(c.get(key)):return false
	if not integer(c.get("tradeProfit"),-1e9,1e9) or not strings(c.get("portsVisited")) or not strings(c.get("sitesVisited")):return false
	for id in c.portsVisited:
		if port(id)==null:return false
	for id in c.sitesVisited:
		if find(C.LAND_SITES,id)==null:return false
	if not c.get("ending") is String or Text.source_length(c.ending)>1000 or (c.retired and (c.ending.is_empty() or s.currentPortId==null)):return false
	if c.has("surrenders") and not integer(c.surrenders):return false
	if c.has("lastInjurySeverity") and not num(c.lastInjurySeverity,0,100):return false
	if not s.get("log") is Array or s.log.size()>120:return false
	var log_ids={}
	for l in s.log:
		if not l is Dictionary or not integer(l.get("id"),1) or not integer(l.get("day"),1,s.day) or not text(l.get("message"),1000) or log_ids.has(l.id):return false
		log_ids[l.id]=true
	for key in ["shipSequence","logSequence","questSequence","battleEpoch","lastNavalTick"]:
		if not integer(m.get(key)):return false
	if m.shipSequence<1:return false
	for f in s.fleet:
		if f.id.begins_with("fleet-") or f.id.begins_with("prize-"):
			var suffix=f.id.get_slice("-",1)
			if suffix.is_valid_int() and int(suffix)>m.shipSequence:return false
	for l in s.log:
		if l.id>m.logSequence:return false
	for key in ["seenEvents","settledTargets","victories","capturedTargets","clues","landWon","treasures","visitedSites","rescuedTargets"]:
		if not strings(m.get(key)):return false
	if m.clues.size()>3:return false
	for id in m.clues:
		var site=find(C.LAND_SITES,id)
		if site==null or site.kind!="clue":return false
	for id in m.landWon+m.treasures+m.visitedSites:
		if find(C.LAND_SITES,id)==null:return false
	if not m.get("targets") is Dictionary or m.targets.size()>10000:return false
	for id in m.targets:
		var t=m.targets[id]
		if not t is Dictionary or not t.get("setup") is Dictionary:return false
		var setup=t.setup
		if not text(id,64) or setup.get("id")!=id or not C.SHIP_PROFILES.has(setup.get("kind")) or setup.get("team") not in ["player","neutral","hostile"] or not position(setup.get("position")):return false
		if not num(t.get("maxHull"),1,10000) or not num(t.get("maxCrew"),1,1000) or not num(setup.get("hull"),0,t.maxHull) or not num(setup.get("sail"),0,100) or not num(setup.get("crew"),0,t.maxCrew) or not num(t.get("speed"),0,1000):return false
		var ambient=find(C.AMBIENT_VESSELS,id)
		if ambient!=null and (setup.kind!=ambient.kind or setup.team=="player" or not integer(t.get("routeLeg"),0,ambient.routePortIds.size()-1) or t.maxCrew!=C.SHIP_PROFILES[ambient.kind].crew):return false
		if setup.get("stats")!=null:
			if not setup.stats is Dictionary:return false
			var limits={"hullMultiplier":100,"cannonMultiplier":10,"speedMultiplier":2,"reloadMultiplier":10,"maxHull":10000,"maxCrew":1000,"steeringMultiplier":2}
			for key in limits:
				if setup.stats.has(key) and not num(setup.stats[key],.001,limits[key]):return false
			if setup.stats.has("maxCrew") and (not integer(setup.stats.maxCrew,1,1000) or setup.stats.maxCrew!=t.maxCrew):return false
			if setup.stats.has("maxHull") and setup.stats.maxHull!=t.maxHull:return false
			if setup.stats.has("cargoMass") and not num(setup.stats.cargoMass,0,10000000):return false
		if not naval_controls(setup):return false
		if setup.get("ammo")!=null:
			if not setup.ammo is Dictionary:return false
			for ammo in ["solid","chain","grape"]:
				if setup.ammo.has(ammo) and not integer(setup.ammo[ammo],0,100000):return false
	if not m.get("cooldowns") is Dictionary:return false
	for key in m.cooldowns:
		if not text(key) or not num(m.cooldowns[key],0,1e9):return false
	var surrender_count=0
	for id in m.seenEvents:
		if id.begins_with("surrender:"):surrender_count+=1
	if c.get("surrenders",0)!=surrender_count:return false
	if s.has("pendingSurrenderReceipt") and not validate_surrender(s,m,ids):return false
	return true
static func validate_surrender(s,m,ids):
	var r=s.pendingSurrenderReceipt
	if not r is Dictionary or r.get("version")!=1 or not text(r.get("id"),256) or not integer(r.get("acceptedDay"),1,s.day) or r.acceptedDay!=s.day or not r.get("quote") is Dictionary:return false
	var q=r.quote;var token=q.get("token");var t=q.get("terms")
	if not token is Dictionary or not t is Dictionary or not text(token.get("battleId")) or not integer(token.get("tick")) or token.tick!=m.lastNavalTick or not token.get("lossDigest") is String or r.id!="surrender:"+token.battleId or r.id not in m.seenEvents:return false
	var f=find(s.fleet,s.flagshipId);var c=s.career
	if t.get("returnPortId")!="xiamen" or s.currentPortId!="xiamen" or s.battleActive or c.retired or f.hull<=0:return false
	var home=port("xiamen")
	if s.position.x!=home.x or s.position.z!=home.z or s.speed!=0:return false
	var captor=t.get("captor")
	if not captor is Dictionary or not text(captor.get("id"),64) or not text(captor.get("name"),80) or captor.get("faction") not in ["zheng","qing","voc","pirates"] or ids.has(captor.id):return false
	var target=m.targets.get(captor.id)
	if target==null or target.setup.team!="hostile" or target.setup.hull<=0 or target.setup.name!=captor.name or captor.id in m.capturedTargets:return false
	for key in m.settledTargets:
		if key.ends_with(":"+captor.id):return false
	var faction="pirates"
	var ambient=find(C.AMBIENT_VESSELS,captor.id);var quest=null
	for item in s.quests:
		if item.get("targetId")==captor.id:quest=item;break
	if ambient!=null:faction=ambient.faction
	elif quest!=null and quest.kind in ["escort","rescue"]:faction=quest.faction
	else:faction="pirates" if "pirate" in captor.id or (quest!=null and quest.kind=="bounty") else "voc" if "voc" in captor.id or "taiwan" in captor.id or target.setup.kind=="voc" else "qing" if "qing" in captor.id else "zheng" if "zheng" in captor.id else "pirates"
	if captor.faction!=faction:return false
	for key in ["silver","morale","fame","relation","surrenders"]:
		if not t.get(key) is Dictionary:return false
	if not integer(t.silver.get("before")) or not integer(t.silver.get("loss")) or not integer(t.silver.get("after")) or t.silver.loss!=ceil(t.silver.before/4.0) or t.silver.after!=t.silver.before-t.silver.loss or s.player.silver!=t.silver.after:return false
	if not num(t.morale.get("before"),0,100) or t.morale.get("after")!=max(0,t.morale.before-20) or s.player.morale!=t.morale.after:return false
	if not integer(t.fame.get("before")) or t.fame.get("after")!=max(0,t.fame.before-5) or s.player.fame!=t.fame.after:return false
	if not integer(t.relation.get("before"),-100,100) or t.relation.get("after")!=max(-100,t.relation.before-5) or s.relations[faction]!=t.relation.after:return false
	if not integer(t.surrenders.get("before")) or t.surrenders.get("after")!=t.surrenders.before+1 or c.surrenders!=t.surrenders.after:return false
	if t.get("mainChapter")!=s.mainChapter or not t.get("shipLosses") is Array or t.shipLosses.size()!=s.fleet.size():return false
	var seen={}
	for loss in t.shipLosses:
		if not loss is Dictionary or seen.has(loss.get("shipId")):return false
		seen[loss.get("shipId")]=true;var ship=find(s.fleet,loss.get("shipId"))
		if ship==null or loss.get("name")!=ship.name or loss.get("hull")!=ship.hull or ship.hull<=0 or loss.get("maxHull")!=ship.maxHull or loss.get("sail")!=ship.sail or loss.get("crew")!=ship.crew or not cargo(loss.get("before")) or not cargo(loss.get("loss")) or not cargo(loss.get("after")) or cargo_size(loss.before)>ship.capacity:return false
		for g in C.GOODS:
			if loss.loss[g]!=ceil(loss.before[g]/4.0) or loss.after[g]!=loss.before[g]-loss.loss[g] or ship.cargo[g]!=loss.after[g]:return false
		if not loss.get("ammo") is Dictionary:return false
		for ammo in ["solid","chain","grape"]:
			if not integer(loss.ammo.get(ammo),0,100000) or loss.ammo[ammo]!=ship.ammo[ammo]:return false
		if ship.get("position")==null or ship.position.x!=s.position.x or ship.position.z!=s.position.z or ship.get("speed")!=0 or (ship.get("navalState")!=null and (ship.navalState.rudder!=0 or ship.navalState.sailDeployment!=0)):return false
	if not t.get("lostShips") is Array or t.lostShips.size()>5:return false
	seen={}
	for lost in t.lostShips:
		if not lost is Dictionary or not text(lost.get("id"),64) or seen.has(lost.id) or not text(lost.get("name"),80) or not C.SHIP_PROFILES.has(lost.get("kind")) or ids.has(lost.id) or lost.id==captor.id:return false
		seen[lost.id]=true
	if t.shipLosses.size()+t.lostShips.size()>6 or not t.get("failedQuests") is Array or t.failedQuests.size()>4:return false
	seen={}
	for failed in t.failedQuests:
		if not failed is Dictionary or seen.has(failed.get("id")):return false
		seen[failed.get("id")]=true;var quest_item=find(s.quests,failed.get("id"))
		if quest_item==null or quest_item.title!=failed.get("title") or quest_item.status!="failed" or failed.get("before") not in ["active","ready"]:return false
	var completed=[]
	for quest_item in s.quests:
		if quest_item.status in ["active","ready"]:return false
		if quest_item.status=="completed":completed.append(quest_item.id)
	if not strings(t.get("completedQuestIds")):return false
	completed.sort();var supplied=t.completedQuestIds.duplicate();supplied.sort()
	if supplied!=completed:return false
	return token.lossDigest==preload("res://game/domain/legacy/surrender.gd").canonical_terms(t)
