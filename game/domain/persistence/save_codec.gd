extends RefCounted
## Pure v2 codec. Disk/slot/rollback coordinator lives outside domain.
const Catalog = preload("res://game/domain/mingqi/catalog.gd")
const OpeningStory = preload("res://game/domain/mingqi/opening_story.gd")
const SecondVoyageAftermath = preload("res://game/domain/mingqi/second_voyage_aftermath.gd")
const MAX_SAFE = 9007199254740991
const MAX_SIGNED_BITS = 9223372036854775807
const MIN_SIGNED_BITS = -9223372036854775807 - 1
const GOODS = ["grain","water","wood","iron","powder","cloth","silk","porcelain","tea","sugar","salt","spices"]
const BUSINESS = ["accept-convoy","buy","sell","depart","choose-route","assign-order","claim-convoy","dock","repair","refit","start-boarding","board-action","allocate-prize","release-prisoners","treat-wounded","take-prize-cargo","resolve-prize","sell-prize","incorporate-prize","story-choice","repay-debt"]
const RECEIPTS = BUSINESS + ["background-load","shipment-arrived","shipment-lost","shipment-interrupted","shipment-late","person-died","cargo-loss","near-hit","near-fire","near-splash","near-sink","near-victory","near-defeat","near-surrender","near-battle-ended","boarding-won","boarding-lost","boarding-cut","work-completed","near-casualties","crew-transition"]
var error = ""
var _json = ""
var _at = 0
var _nodes = 0

static func encode(state: Dictionary,utc: String="2026-10-11T00:00:00.000Z") -> String:
	var json=JSON.stringify({"version":2,"campaignId":state.get("campaignId"),"mode":"mingqi-1650","savedAtUtc":utc,"simulationSeconds":state.get("simulationSeconds"),"state":state},"",false,true)
	return json if decode(json).get("ok",false) else ""
static func decode(json: String) -> Dictionary:
	var codec=new()
	var envelope=codec._parse(json)
	if not codec.error.is_empty():return {"ok":false,"code":codec.error}
	if not envelope is Dictionary:return {"ok":false,"code":"invalid-save: envelope"}
	if envelope.get("version")!=2:return {"ok":false,"code":"unsupported-save-version"}
	if envelope.get("state") is Dictionary:
		for field in ["prizes","casualtyOrdinals"]:
			if not envelope.state.has(field):envelope.state[field]={}
	var schema=codec._state_schema()
	if not codec._validate(envelope,{"version":["one",[2]],"campaignId":"commandId","mode":["one",["mingqi-1650"]],"savedAtUtc":"utc","simulationSeconds":"time","state":schema},"envelope"):return {"ok":false,"code":codec.error}
	if envelope.campaignId!=envelope.state.campaignId or envelope.simulationSeconds!=envelope.state.simulationSeconds:return {"ok":false,"code":"envelope-state-mismatch"}
	if not codec._relations(envelope.state):return {"ok":false,"code":codec.error}
	return {"ok":true,"kind":"mingqi","state":envelope.state.duplicate(true),"envelope":envelope.duplicate(true)}
static func command_data(value) -> bool:
	var codec=new()
	return codec._data(value,0,8,512,65)
func _fail(path: String,reason: String="invalid-save") -> bool:
	if error.is_empty():error=reason+": "+path
	return false
func _check(condition: bool,path: String,reason: String="invalid-save") -> bool:return true if condition else _fail(path,reason)
static func _finite(v) -> bool:return typeof(v) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(v))
static func _count(v) -> bool:return _finite(v) and v>=0 and v<=MAX_SAFE and v==floor(float(v))
static func _equal(a,b) -> bool:
	if _finite(a) and _finite(b):return a==b
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
	return a==b
static func _id(v,max_length: int=4096) -> bool:
	return _text(v,max_length) and not v in ["__proto__","prototype","constructor"]
static func _text(v,max_length: int=16384) -> bool:
	if not v is String or v.strip_edges().is_empty():return false
	var units=0
	for i in v.length():
		if v.unicode_at(i)<32 or v.unicode_at(i)==127:return false
		units+=2 if v.unicode_at(i)>65535 else 1
	return units<=max_length
func _data(v,depth: int,max_depth: int,max_nodes: int,max_keys: int) -> bool:
	_nodes+=1
	if depth>max_depth or _nodes>max_nodes:return false
	if v is Dictionary:
		if v.size()>max_keys:return false
		for k in v:
			if not k is String or not _data(v[k],depth+1,max_depth,max_nodes,max_keys):return false
		return true
	if v is Array:
		if v.size()>max_keys-1:return false
		for x in v:
			if not _data(x,depth+1,max_depth,max_nodes,max_keys):return false
		return true
	return v==null or v is bool or v is String or _finite(v)

func _parse(json: String):
	if not _check(json.length()<=16777216 and json.to_utf8_buffer().size()<=16777216,"json","save-limit"):return null
	_json=json;_at=0;_nodes=0
	var value=_value(0);_space()
	_check(_at==_json.length(),"json","invalid-json")
	return value
func _space():
	while _at<_json.length() and _json[_at] in [" ","\t","\n","\r"]:_at+=1
func _string():
	var start=_at;_at+=1
	while _at<_json.length():
		var c=_json[_at];_at+=1
		if c.unicode_at(0)<32:_fail("json","invalid-json");return null
		if c=='"':
			var parser=JSON.new()
			if parser.parse(_json.substr(start,_at-start))!=OK:_fail("json","invalid-json");return null
			return parser.data
		if c=="\\":
			if _at>=_json.length() or not _json[_at] in ['"',"\\","/","b","f","n","r","t","u"]:_fail("json","invalid-json");return null
			if _json[_at]=="u":
				if _at+4>=_json.length():_fail("json","invalid-json");return null
				for j in range(_at+1,_at+5):
					if not _json[j] in "0123456789abcdefABCDEF":_fail("json","invalid-json");return null
				_at+=4
			_at+=1
	_fail("json","invalid-json");return null
func _value(depth: int):
	_nodes+=1
	if not _check(depth<=32 and _nodes<=250000,"json","save-limit"):return null
	_space()
	if _at>=_json.length():_fail("json","invalid-json");return null
	var c=_json[_at]
	if c=='"':return _string()
	if c=="{":
		_at+=1;_space();var result={}
		if _at<_json.length() and _json[_at]=="}":_at+=1;return result
		while _at<_json.length() and error.is_empty():
			if not _check(_json[_at]=='"',"json","invalid-json"):return null
			var key=_string()
			if not _check(key is String and not key in ["__proto__","prototype","constructor"],"json.key","unsafe-key") or not _check(not result.has(key),str(key),"duplicate-key"):return null
			_space()
			if not _check(_at<_json.length() and _json[_at]==":","json","invalid-json"):return null
			_at+=1;result[key]=_value(depth+1);_space()
			if _at>=_json.length():break
			var end=_json[_at];_at+=1
			if end=="}":return result
			if not _check(end==",","json","invalid-json"):return null
			_space()
		_fail("json","invalid-json");return null
	if c=="[":
		_at+=1;_space();var result=[]
		if _at<_json.length() and _json[_at]=="]":_at+=1;return result
		while _at<_json.length() and error.is_empty():
			result.append(_value(depth+1));_space()
			if _at>=_json.length():break
			var end=_json[_at];_at+=1
			if end=="]":return result
			if not _check(end==",","json","invalid-json"):return null
		_fail("json","invalid-json");return null
	for pair in [["true",true],["false",false],["null",null]]:
		if _json.substr(_at,pair[0].length())==pair[0]:_at+=pair[0].length();return pair[1]
	var regex=RegEx.new();regex.compile("^-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?")
	var found=regex.search(_json.substr(_at))
	if not _check(found!=null,"json","invalid-json"):return null
	var token=found.get_string();_at+=token.length();var number=_saved_number(token)
	if not _check(is_finite(number),"json.number"):return null
	return number

static func _saved_number(token: String) -> float:
	var baseline=token.to_float()
	# Integer spellings keep the existing conversion and safe-count validation.
	if not is_finite(baseline) or not (token.contains(".") or token.contains("e") or token.contains("E")):
		return baseline
	if JSON.stringify(baseline,"",false,true)==token:return baseline
	# Godot's String parser can miss the own full-precision encoder's float by
	# a few ULPs. Restore only a unique nearby float that reproduces the raw
	# token exactly; alternate spellings and unmatched ranges keep the fallback.
	var raw_bits: int=PackedFloat64Array([baseline]).to_byte_array().decode_s64(0)
	var restored=baseline;var matches=0
	for offset in range(-8,9):
		if offset==0:continue
		if offset>0 and raw_bits>MAX_SIGNED_BITS-offset:continue
		if offset<0 and raw_bits<MIN_SIGNED_BITS-offset:continue
		var bytes=PackedByteArray();bytes.resize(8);bytes.encode_s64(0,raw_bits+offset)
		var neighbor=bytes.decode_double(0)
		if is_finite(neighbor) and JSON.stringify(neighbor,"",false,true)==token:
			restored=neighbor;matches+=1
			if matches>1:return baseline
	return restored if matches==1 else baseline

func _validate(v,schema,path: String) -> bool:
	if schema is Dictionary:
		if not _check(v is Dictionary,path):return false
		for key in v:
			if not _check(schema.has(key) or schema.has(key+"?"),path+"."+key,"unknown-key"):return false
		for field in schema:
			var optional=field.ends_with("?");var key=field.trim_suffix("?")
			if not v.has(key):
				if optional:continue
				return _fail(path+"."+key,"missing-field")
			if not _validate(v[key],schema[field],path+"."+key):return false
		return true
	if schema is Array:
		match schema[0]:
			"one":
				for allowed in schema[1]:
					if _equal(v,allowed):return true
				return _fail(path)
			"range":return _check(_finite(v) and v>=schema[1] and v<=schema[2],path)
			"null":return v==null or _validate(v,schema[1],path)
			"array":
				if not _check(v is Array and v.size()<=schema[2] and v.size()>=(schema[3] if schema.size()>3 else 0),path):return false
				for i in v.size():
					if not _validate(v[i],schema[1],path+"["+str(i)+"]"):return false
				return true
			"record":
				if not _check(v is Dictionary and v.size()<=schema[2],path,"save-limit"):return false
				for key in v:
					if not _check(_id(key),path+".key") or not _validate(v[key],schema[1],path+"."+key):return false
				return true
			"ids":
				if not _validate(v,["array","id",schema[1],schema[2] if schema.size()>2 else 0],path):return false
				var seen={}
				for id in v:
					if not _check(not seen.has(id),path,"duplicate-id"):return false
					seen[id]=true
				return true
	match schema:
		"finite":return _check(_finite(v),path)
		"count":return _check(_count(v),path)
		"debtPrincipal":return _check(_count(v) and v<=400,path)
		"positive":return _check(_count(v) and v>0,path)
		"time":return _check(_finite(v) and v>=0 and v<=MAX_SAFE,path)
		"positiveTime":return _check(_finite(v) and v>0 and v<=MAX_SAFE,path)
		"positiveRange":return _check(_finite(v) and v>0 and v<=10000,path)
		"id":return _check(_id(v),path)
		"commandId":return _check(_id(v,128),path)
		"text":return _check(_text(v,16384),path)
		"bool":return _check(v is bool,path)
		"name":return _check(_text(v,48) and v.length()<=24,path)
		"remainder":return _check(_finite(v) and v>=0 and v<1,path)
		"compensation":return _check(_finite(v) and abs(v)<=pow(2,-32),path)
		"sequence":return _check(_count(v) and v<MAX_SAFE,path)
		"utc":
			if not v is String:return _fail(path,"invalid-utc")
			var regex=RegEx.new();regex.compile("^(?:[0-9]{4}|[+-][0-9]{6})-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3}Z$")
			if regex.search(v)==null:return _fail(path,"invalid-utc")
			var offset=3 if v.length()==27 else 0
			var year=int(v.substr(0,4+offset));var month=int(v.substr(5+offset,2));var day=int(v.substr(8+offset,2))
			var lengths=[31,29 if year%4==0 and (year%100!=0 or year%400==0) else 28,31,30,31,30,31,31,30,31,30,31]
			var bounded=year>=-271821 and year<=275760
			if year==-271821:bounded=month>4 or month==4 and day>=20
			if year==275760:bounded=month<9 or month==9 and (day<13 or day==13 and v.substr(11+offset)=="00:00:00.000Z")
			return _check(bounded and month>=1 and month<=12 and day>=1 and day<=lengths[month-1] and int(v.substr(11+offset,2))<24 and int(v.substr(14+offset,2))<60 and int(v.substr(17+offset,2))<60 and (offset==0 or year<0 or year>9999),path,"invalid-utc")
		"cargo":
			if not _check(v is Dictionary,path):return false
			var total=0.0
			for good in v:
				if not _check(good in GOODS,path) or not _validate(v[good],"count",path+"."+good):return false
				total+=v[good]
			return _check(_count(total),path+".total")
		"order":
			if not _validate(v,{"id":"commandId","shipIds":["ids",64,1],"issuedAt":"time","intent":"intent"},path):return false
			return true
		"intent":
			if not v is Dictionary:return _fail(path)
			match v.get("kind"):
				"rally":return _validate(v,{"kind":["one",["rally"]],"point":{"x":"finite","z":"finite"}},path)
				"keep-distance":return _validate(v,{"kind":["one",["keep-distance"]],"targetId":"id","range":"positiveRange"},path)
				_:return _validate(v,{"kind":["one",["protect","intercept","focus","prepare-boarding"]],"targetId":"id"},path)
		"details":
			var all=_detail_schemas()
			if not v is Dictionary or not all.has(v.get("kind")):return _fail(path)
			if v.kind=="story-choice" and v.get("sceneId")==SecondVoyageAftermath.SCENE_ID:return _validate(v,_aftermath_schema(),path)
			return _validate(v,all[v.kind],path)
		"work":
			if not v is Dictionary:return _fail(path)
			var fields={"id":"id","shipId":"id","portId":"id","startAt":"time","completeAt":"time","cost":"positive","status":["one",["active","completed"]]}
			if v.get("kind")=="treatment":fields.merge({"kind":["one",["treatment"]],"quantity":"positive","hull":["one",[0]],"sail":["one",[0]],"targetProfileId":["one",[null]]})
			else:fields.merge({"kind":["one",["repair","refit"]],"hull":["range",0,100],"sail":["range",0,100],"targetProfileId":["null","id"]})
			return _validate(v,fields,path)
	return _fail(path,"unknown-validator")
func _calendar_schema() -> Dictionary:return {"year":"count","month":["range",1,12],"day":["range",1,31]}
func _state_schema() -> Dictionary:
	var position={"x":"finite","z":"finite"};var ordering={"battleId":"id","tick":"count","sequence":"sequence"};var projection=ordering.duplicate();projection.revision="count"
	var vessel={"id":"id","name":"text","ownerId":"id","profileId":"id","cargo":"cargo","pose":{"position":position,"heading":"finite","speed":["range",0,1.7976931348623157e308]},"controls":{"rudder":["range",-1,1],"sailAngle":["range",-PI/2,PI/2],"sailDeployment":["range",0,1],"autoTrim":"bool"},"controlsRevision":"count","controlsProjection":["null",projection],"controlsObserved":["null",ordering],"combat":{"ammo":{"solid":"count","chain":"count","grape":"count"},"ammoType":["one",["solid","chain","grape"]],"cooldownSeconds":{"port":["range",0,120],"starboard":["range",0,120]}},"crew":{"able":"count","wounded":"count","prisoners":"count","minimum":"count"},"damage":{"hull":["range",0,100],"sail":["range",0,100],"portGuns":["range",0,100],"starboardGuns":["range",0,100],"mast":["range",0,100],"fire":["range",0,100],"flooding":["range",0,100]},"voyageId":["null","id"],"representation":["one",["route","near"]],"revision":"count"}
	var voyage={"id":"id","vesselId":"id","originId":"id","destinationId":"id","routeId":"id","leg":"count","progress":["range",0,1],"departedAt":"time","eta":"time","escortIds":["ids",64],"status":["one",["loading","underway","arrived","lost","interrupted"]]}
	var point={"control":["range",0,100],"action":["one",["advance","hold"]]}
	var boarding={"id":"id","attackerId":"id","targetId":"id","points":{"bow":point,"deck":point,"helm":point},"morale":{"attacker":["range",0,100],"defender":["range",0,100]},"status":["one",["active","won","lost","cut"]],"participants":["ids",128],"elapsedSeconds":"count","remainder":"remainder","clockCompensation":"compensation"}
	return {"campaignId":"commandId","revision":"count","seed":["range",0,4294967295],"randomState":["range",0,4294967295],"nextId":"positive","simulationSeconds":"time","macroRemainder":"remainder","macroSeconds":"count","clockCompensation":"compensation","calendar":_calendar_schema(),"chapterId":["one",["opening-1650"]],"captain":{"name":"name","birthYear":["one",[1631]],"silver":"count"},"debt":{"principal":"debtPrincipal","creditorId":["one",["house-lin"]],"dueAt":["one",[18000]]},"flagshipId":"id","currentPortId":["null","id"],"vessels":["record",vessel,128],"voyages":["record",voyage,4096],"ports":["record",{"id":"id","name":"text","position":position,"stock":"cargo","production":"cargo","consumption":"cargo"},128],"orders":["array","order",4096],"contracts":["record",{"id":["one",["convoy-001","convoy-002"]],"voyageIds":["ids",64],"deadlineAt":"time","minimumDelivery":["one",[1]],"bonusQuantity":"count","criticalPersonIds":["ids",128],"secret":["one",[false]],"status":["one",["offered","active","delivered","failed","settled"]],"receiptId":["null","id"]},2],"boardings":["record",boarding,128],"works":["record","work",128],"prizes":["record",{"targetId":"id","boardingId":"id","originalOwnerId":"id","status":["one",["held","crewed","incorporated","released","abandoned","sold"]],"resolutionReceiptId":["null","id"]},128],"casualtyOrdinals":["record","count",128],"reputations":{"militaryTrust":["range",-100,100],"merchantCredit":["range",-100,100],"crewSupport":["range",-100,100],"intimidation":["range",-100,100]},"people":["record",{"id":"id","name":"text","shipId":["null","id"],"alive":"bool","role":["one",["steward","pilot","deputy"]]},128],"intelligence":["array",{"portId":"id","observedAt":"time","sourceId":"id","confidence":["range",0,1],"stock":"cargo"},4096],"chronicle":["array",{"id":"id","simTime":"time","date":_calendar_schema(),"causeIds":["array","id",128],"kind":["one",RECEIPTS],"message":"text"},4096],"settlements":["record",{"id":"id","commandId":"id","revision":"count","kind":["one",RECEIPTS],"message":"text","details?":"details"},4096],"nearTicks":["record","count",128]}
func _detail_schemas() -> Dictionary:
	var bucket={"able":"count","wounded":"count","prisoners":"count"}
	return {
		"story-choice":{"kind":["one",["story-choice"]],"sceneId":["one",OpeningStory.SCENES],"choiceId":"id","portId":"id","silverCost":"count","reputationEffects":{"crewSupport":["range",-100,100],"militaryTrust":["range",-100,100],"merchantCredit":["range",-100,100]},"routeId":["null","id"],"convoyReceiptId":["null","id"],"intelligence":["null",{"portId":"id","observedAt":"time","sourceId":"id","confidence":["range",0,1],"stock":"cargo"}]},
		"repay-debt":{"kind":["one",["repay-debt"]],"portId":["one",["xiamen"]],"amount":"positive","beforePrincipal":"debtPrincipal","afterPrincipal":"debtPrincipal","creditAward":"count"},
		"crew-transition":{"kind":["one",["crew-transition"]],"reason":["one",["boarding-attrition","boarding-victory","allocation","release-prisoners","treatment","prize-release","prize-rescue","prize-sale"]],"causeId":"id","changes":["array",{"shipId":"id","before":bucket,"after":bucket},2,1]},
		"battle-ended":{"kind":["one",["battle-ended"]],"battleId":"id","episodeId":"id","outcome":["one",["victory","defeat","disengaged"]],"reason":"text"},
		"shipment-arrived":{"kind":["one",["shipment-arrived"]],"voyageId":"id","vesselId":"id","destinationId":"id","grain":"count","arrivedAt":"time"},
		"convoy-load":{"kind":["one",["convoy-load"]],"contractId":"id","loaded":"count","leasePaid":"count","ships":["array",{"shipId":"id","able":"count","wounded":"count"},128]},
		"convoy":{"kind":["one",["convoy"]],"contractId":"id","loaded":"count","delivered":"count","pending":"count","lost":"count","baseReward":"count","bonus":"count","leasePaid":"count","ships":["array",{"shipId":"id","wounded":"count","dead":"count","transferred":"count","hull":["range",0,100],"sail":["range",0,100]},128],"people":["array",{"personId":"id","alive":"bool"},128]},
		"prize":{"kind":["one",["prize"]],"targetId":"id","fromShipId":"id","crew":"positive","prisoners":"count"},
		"boarding":{"kind":["one",["boarding"]],"encounterId":"id","targetId":"id","attackerId":"id","outcome":["one",["won","lost","cut"]]},
		"work":{"kind":["one",["work"]],"workId":"id","shipId":"id","cost":"count","duration":"positiveTime","status":["one",["active","completed"]]},
		"treatment":{"kind":["one",["treatment"]],"workId":"id","shipId":"id","quantity":"positive","cost":"positive","duration":"positiveTime","status":["one",["active","completed"]]},
		"prize-cargo":{"kind":["one",["prize-cargo"]],"targetId":"id","toShipId":"id","cargo":"cargo"},
		"prize-resolution":{"kind":["one",["prize-resolution"]],"targetId":"id","boardingId":"id","choice":["one",["release","abandon"]],"toShipId":["null","id"],"movedWounded":"count","movedPrisoners":"count","restoredAble":"count"},
		"prize-port":{"kind":["one",["prize-port"]],"shipId":"id","portId":"id","action":["one",["sell","incorporate"]],"silver":"count","crewToShipId":["null","id"],"movedAble":"count","movedWounded":"count","movedPrisoners":"count"},
		"casualty":{"kind":["one",["casualty"]],"battleId":"id","tick":"count","controlsSequence":"sequence","shipId":"id","ableBefore":"count","ableAfter":"count","woundedBefore":"count","woundedAfter":"count","prisonersBefore":"count","prisonersAfter":"count","dead":"count","sunk":"bool","ordinalBefore":"count","ordinalAfter":"count"}
	}
func _aftermath_schema() -> Dictionary:
	var schema=_detail_schemas()["story-choice"].duplicate(true)
	schema.sceneId=["one",[SecondVoyageAftermath.SCENE_ID]]
	schema.choiceId=["one",SecondVoyageAftermath.CHOICES]
	schema.portId=["one",["xiamen","kinmen","forward-supply"]]
	schema.routeId=["one",[null]];schema.intelligence=["one",[null]]
	schema.aftermath={"contractId":["one",["convoy-002"]],"revenue":"count","silverBefore":"count","silverAfter":"count","supportBefore":["range",-100,100],"supportAfter":["range",-100,100],"beneficiaries":["array",{"shipId":"id","able":"count","wounded":"count"},128],"beneficiaryCount":"count","portWitness":{"flagshipId":"id","position":{"x":"finite","z":"finite"},"speed":["range",0,0.75],"hull":["range",0,100],"anchored":["one",[true]],"pendingAttacks":["one",[false]],"activeBoardings":["one",[0]],"hostileWithin600":["one",[false]]}}
	return schema
func _relations(s: Dictionary) -> bool:
	if not _check(_count(s.seed) and _count(s.randomState),"seed") or not _check(s.simulationSeconds==s.macroSeconds+s.macroRemainder,"simulationSeconds") or not _check(floor(s.macroSeconds/1800.0)<=100116877,"calendar","calendar-overflow"):return false
	if not _check(_equal(s.calendar,_date_at(s.macroSeconds)),"calendar"):return false
	if not _check(s.flagshipId==s.campaignId+"-flagship" and s.vessels.has(s.flagshipId),"flagshipId"):return false
	for role in Catalog.DATA.roles:
		if not _check(s.vessels.has(s.campaignId+"-"+role.suffix),"original-vessel"):return false
	var entities={}
	for field in ["vessels","voyages","ports","contracts","boardings","works","people","settlements"]:
		for key in s[field]:
			if not _check(s[field][key].id==key,field+"."+key,"key-id-mismatch"):return false
			if field in ["vessels","voyages","boardings","works"]:
				if not _check(not entities.has(key),"entities","duplicate-id"):return false
				entities[key]=true
	if not _check(s.ports.size()==Catalog.DATA.ports.size(),"ports"):return false
	for key in Catalog.DATA.ports:
		if not _check(s.ports.has(key),"ports"):return false
		var p=s.ports[key].duplicate(true);p.stock=Catalog.DATA.ports[key].stock
		if not _check(_equal(p,Catalog.DATA.ports[key]),"ports."+key,"canonical-port-mismatch"):return false
	if s.currentPortId!=null and not _check(s.ports.has(s.currentPortId),"currentPortId"):return false
	for key in s.nearTicks:
		if not _check(key.begins_with(s.campaignId+":") and key.length()>s.campaignId.length()+1,"nearTicks"):return false
	for key in s.casualtyOrdinals:
		if not _check(s.vessels.has(key),"casualtyOrdinals"):return false
	for v in s.vessels.values():
		if not _check(Catalog.DATA.profiles.has(v.profileId),"profile:"+v.id):return false
		var p=Catalog.DATA.profiles[v.profileId];var total=0.0
		for q in v.cargo.values():total+=q
		if not _check(v.damage.hull<=p.maxHull and v.damage.sail<=p.maxSail and v.crew.able+v.crew.wounded+v.crew.prisoners<=p.maxCrew and v.crew.minimum<=p.maxCrew and total<=p.capacity and v.controlsRevision<=s.revision,"vessel:"+v.id):return false
		for fence in [v.controlsProjection,v.controlsObserved]:
			if fence!=null and not _check(s.nearTicks.has(s.campaignId+":"+fence.battleId) and fence.tick<=s.nearTicks[s.campaignId+":"+fence.battleId],"fence:"+v.id):return false
		if v.controlsProjection!=null:
			if not _check(v.controlsProjection.revision<=v.controlsRevision,"projection:"+v.id):return false
			if v.controlsObserved!=null and v.controlsObserved.battleId==v.controlsProjection.battleId and not _check(v.controlsObserved.sequence>=v.controlsProjection.sequence and v.controlsObserved.tick>=v.controlsProjection.tick,"observed:"+v.id):return false
		if v.voyageId!=null and not _check(s.voyages.has(v.voyageId) and s.voyages[v.voyageId].vesselId==v.id,"voyageId:"+v.id):return false
		for role in Catalog.DATA.roles:
			if v.id==s.campaignId+"-"+role.suffix:
				if not _check(v.profileId in [role.profileId,role.profileId+"-sails"] and v.crew.minimum==role.minimum,"role:"+v.id):return false
				if not _check(v.ownerId==role.ownerId or role.ownerId=="enemy" and v.ownerId in ["captain",_terminal_owner(s,v.id)],"owner:"+v.id):return false
		var original=false
		for role in Catalog.DATA.roles:original=original or v.id==s.campaignId+"-"+role.suffix
		if not original and not _check(v.ownerId in ["enemy","captain",_terminal_owner(s,v.id)],"owner:"+v.id):return false
		if v.ownerId=="captain" and v.id!=s.campaignId+"-heritage" and not _check(s.settlements.get(s.campaignId+":prize:"+v.id,{}).get("kind")=="allocate-prize","owner:"+v.id,"missing-prize-receipt"):return false
		if v.profileId.ends_with("-sails"):
			var proved=false
			for w in s.works.values():proved=proved or w.shipId==v.id and w.kind=="refit" and w.status=="completed" and w.targetProfileId==v.profileId
			if not _check(proved,"refit:"+v.id):return false
	for v in s.voyages.values():
		if not _check(s.vessels.has(v.vesselId) and s.ports.has(v.originId) and s.ports.has(v.destinationId) and Catalog.DATA.routes.has(v.routeId),"voyage:"+v.id):return false
		var r=Catalog.DATA.routes[v.routeId]
		if not _check(r.originId==v.originId and r.destinationId==v.destinationId and v.leg<r.points.size()-1 and v.departedAt<=s.simulationSeconds,"route:"+v.id):return false
		for id in v.escortIds:
			if not _check(s.vessels.has(id),"escortId"):return false
		if not v.status in ["arrived","lost"] and not _check(s.vessels[v.vesselId].voyageId==v.id,"current-voyage"):return false
		if v.status=="arrived":
			var d=s.settlements.get(s.campaignId+":"+v.id+":arrival",{}).get("details",{})
			if not _check(d.get("kind")=="shipment-arrived" and d.voyageId==v.id and d.vesselId==v.vesselId and d.destinationId==v.destinationId and d.arrivedAt==v.eta and v.progress==1,"arrival"):return false
		if v.status=="lost" and not _check(s.settlements.get(s.campaignId+":"+v.id+":lost",{}).get("kind")=="shipment-lost","loss"):return false
	var events={};var prior_time=-1.0
	for e in s.chronicle:
		if not _check(not events.has(e.id) and s.settlements.has(e.id) and e.simTime>=prior_time and e.simTime<=s.simulationSeconds and _equal(e.date,_date_at(e.simTime)),"chronicle"):return false
		events[e.id]=true;prior_time=e.simTime
		var r=s.settlements[e.id]
		if not _check(e.kind==r.kind and e.message==r.message,"chronicle-receipt"):return false
	if not _check(events.size()==s.settlements.size() and s.settlements.get("background-load-01",{}).get("kind")=="background-load","chronicle-receipts"):return false
	var commands={}
	for r in s.settlements.values():
		if not _check(r.revision<=s.revision,"receipt"):return false
		if r.kind in BUSINESS:
			if not _check(_id(r.commandId,128) and not commands.has(r.commandId),"commandId","duplicate-command"):return false
			commands[r.commandId]=true
			var prefixes={"buy":"trade","sell":"trade","depart":"depart","choose-route":"route","assign-order":"order"}
			if prefixes.has(r.kind) and not _check(r.id==s.campaignId+"-"+prefixes[r.kind]+"-"+r.commandId,"receipt-id"):return false
			if r.kind in ["dock","repair","refit","release-prisoners","start-boarding","board-action","treat-wounded","take-prize-cargo","repay-debt"] and not _check(r.id==s.campaignId+":"+r.kind+":"+r.commandId,"receipt-id"):return false
		elif not _check(r.commandId==r.id,"traffic-command"):return false
		if not _receipt_relations(s,r):return false
	if not _contract_relations(s):return false
	for p in s.people.values():
		if p.shipId!=null and not _check(s.vessels.has(p.shipId),"person-ship"):return false
		var death=s.settlements.get(s.campaignId+":person:"+p.id+":death",{})
		if not _check(p.alive==death.is_empty() and (death.is_empty() or death.get("kind")=="person-died"),"person-death"):return false
	for pair in [["steward-a","grain-a"],["steward-b","grain-b"]]:
		if not _check(s.people.get(pair[0],{}).get("role")=="steward" and s.people[pair[0]].shipId==s.campaignId+"-"+pair[1],"person"):return false
	for i in s.intelligence:
		if not _check(s.ports.has(i.portId) and i.observedAt<=s.simulationSeconds,"intelligence"):return false
	var order_ids={}
	for o in s.orders:
		if not _check(not order_ids.has(o.id) and o.issuedAt<=s.simulationSeconds,"order"):return false
		order_ids[o.id]=true
		for id in o.shipIds:
			if not _check(s.vessels.has(id),"order-ship"):return false
		if o.intent.has("targetId") and not _check(s.vessels.has(o.intent.targetId) and not o.intent.targetId in o.shipIds,"order-target"):return false
		if not _check(s.settlements.get(s.campaignId+"-order-"+o.id,{}).get("kind")=="assign-order","order-receipt"):return false
	return _business_relations(s) and _crew_history(s) and _opening_history(s)
static func _date_at(seconds: float) -> Dictionary:
	var days=int(floor(seconds/1800.0));var year=1650
	var cycles=int(floor(days/146097.0));days-=cycles*146097;year+=cycles*400
	while true:
		var length=366 if year%4==0 and (year%100!=0 or year%400==0) else 365
		if days<length:break
		days-=length;year+=1
	var months=[31,29 if year%4==0 and (year%100!=0 or year%400==0) else 28,31,30,31,30,31,31,30,31,30,31];var month=0
	while days>=months[month]:days-=months[month];month+=1
	return {"year":year,"month":month+1,"day":days+1}
func _terminal_owner(s: Dictionary,id: String):
	match s.prizes.get(id,{}).get("status"):
		"released":return "released-prize"
		"abandoned":return "abandoned-prize"
		"sold":return "port-prize"
	return null
func _receipt_relations(s: Dictionary,r: Dictionary) -> bool:
	var required={"story-choice":"story-choice","repay-debt":"repay-debt","accept-convoy":"convoy-load","claim-convoy":"convoy","allocate-prize":"prize","repair":"work","refit":"work","treat-wounded":"treatment","take-prize-cargo":"prize-cargo","resolve-prize":"prize-resolution","sell-prize":"prize-port","incorporate-prize":"prize-port","near-casualties":"casualty","shipment-arrived":"shipment-arrived","boarding-won":"boarding","boarding-lost":"boarding","boarding-cut":"boarding","near-battle-ended":"battle-ended","crew-transition":"crew-transition"}
	var d=r.get("details",{})
	if required.has(r.kind) and not _check(d.get("kind")==required[r.kind],"receipt-details"):return false
	if r.kind=="work-completed" and not _check(d.get("kind") in ["work","treatment"],"receipt-details"):return false
	if d.is_empty():return true
	var allowed={"story-choice":["story-choice"],"repay-debt":["repay-debt"],"crew-transition":["crew-transition"],"battle-ended":["near-battle-ended"],"shipment-arrived":["shipment-arrived"],"convoy-load":["accept-convoy"],"convoy":["claim-convoy"],"prize":["allocate-prize"],"boarding":["board-action","boarding-won","boarding-lost","boarding-cut"],"work":["repair","refit","work-completed"],"treatment":["treat-wounded","work-completed"],"prize-cargo":["take-prize-cargo"],"prize-resolution":["resolve-prize"],"prize-port":["sell-prize","incorporate-prize"],"casualty":["near-casualties"]}
	if not _check(r.kind in allowed[d.kind],"receipt-detail-kind-mismatch"):return false
	match d.kind:
		"story-choice":return _story_receipt(s,r,d)
		"repay-debt":return _check(d.beforePrincipal>0 and d.amount<=d.beforePrincipal and d.afterPrincipal==d.beforePrincipal-d.amount and d.creditAward==(6 if d.afterPrincipal==0 else 0),"debt-payment-definition")
		"shipment-arrived":
			if not _check(s.voyages.has(d.voyageId) and s.vessels.has(d.vesselId),"shipment-arrived"):return false
			var v=s.voyages[d.voyageId]
			return _check(v.status=="arrived" and v.vesselId==d.vesselId and v.destinationId==d.destinationId and r.id==s.campaignId+":"+v.id+":arrival" and d.arrivedAt<=s.simulationSeconds and d.grain<=Catalog.DATA.profiles[s.vessels[d.vesselId].profileId].capacity,"shipment-arrived")
		"battle-ended":return _check(s.nearTicks.has(s.campaignId+":"+d.battleId) and d.episodeId.length()<=512 and d.reason.length()<=512,"battle-ended")
		"convoy-load","convoy":
			if not _check(s.contracts.has(d.contractId),"convoy-detail"):return false
			var quantity=40 if d.contractId=="convoy-001" else 20;var lease=50 if d.contractId=="convoy-001" else 0;var bonus=100 if d.contractId=="convoy-001" else 50
			if not _check(d.loaded==quantity and d.leasePaid==lease,"convoy-rule"):return false
			var seen={}
			for ship in d.ships:
				if not _check(s.vessels.has(ship.shipId) and not seen.has(ship.shipId),"convoy-ship"):return false
				seen[ship.shipId]=true
			if d.kind=="convoy-load":
				for ship in d.ships:
					if not _check(ship.able+ship.wounded<=Catalog.DATA.profiles[s.vessels[ship.shipId].profileId].maxCrew,"convoy-load-crew"):return false
				return _check(r.id==s.campaignId+"-"+d.contractId+"-accept","convoy-load-id")
			if not _check(r.id==s.campaignId+":"+d.contractId+":claim" and d.loaded==d.delivered+d.pending+d.lost and d.pending==0 and d.baseReward==d.delivered*10 and (d.bonus==0 or d.bonus==bonus),"convoy-claim"):return false
			var loaded=s.settlements.get(s.campaignId+"-"+d.contractId+"-accept",{}).get("details",{})
			if not _check(loaded.get("kind")=="convoy-load" and loaded.ships.size()==d.ships.size(),"convoy-history"):return false
			for ship in d.ships:
				var before={}
				for item in loaded.ships:
					if item.shipId==ship.shipId:before=item;break
				var transfers=_convoy_transfers(s,ship.shipId,s.settlements[s.campaignId+"-"+d.contractId+"-accept"].revision,r.revision)
				if not _check(not before.is_empty() and ship.dead+ship.wounded+ship.transferred<=before.able+before.wounded+transfers.incoming and ship.transferred==transfers.outgoing,"convoy-crew-history"):return false
			var delivered=0;var last=0
			for vid in s.contracts[d.contractId].voyageIds:
				var arrival=s.settlements.get(s.campaignId+":"+vid+":arrival",{}).get("details",{})
				if arrival.get("kind")=="shipment-arrived":delivered+=arrival.grain;last=max(last,arrival.arrivedAt)
			if not _check(d.delivered==delivered,"convoy-delivery"):return false
			if d.bonus>0 and not _check(delivered==quantity and last<=s.contracts[d.contractId].deadlineAt,"convoy-bonus"):return false
			var people={}
			if not _check(d.people.size()==s.contracts[d.contractId].criticalPersonIds.size(),"convoy-people"):return false
			for person in d.people:
				var death=s.settlements.get(s.campaignId+":person:"+person.personId+":death",{})
				if not _check(s.people.has(person.personId) and person.personId in s.contracts[d.contractId].criticalPersonIds and not people.has(person.personId) and person.alive==not(not death.is_empty() and _event_index(s,death.id)>=0 and _event_index(s,death.id)<_event_index(s,r.id)) and (d.bonus==0 or person.alive),"convoy-person"):return false
				people[person.personId]=true
		"boarding":
			var b=s.boardings.get(d.encounterId,{})
			return _check(not b.is_empty() and b.status==d.outcome and b.targetId==d.targetId and b.attackerId==d.attackerId,"boarding-details")
		"work","treatment":
			var w=s.works.get(d.workId,{})
			if not _check(not w.is_empty() and w.shipId==d.shipId and w.cost==d.cost and (w.kind=="treatment" and w.quantity==d.quantity if d.kind=="treatment" else w.kind!="treatment"),"work-detail"):return false
			return _check(d.status=="completed" and w.status=="completed" and r.id==w.id+":completed" and d.duration==w.completeAt-w.startAt if r.kind=="work-completed" else d.status=="active" and r.kind==("treat-wounded" if w.kind=="treatment" else w.kind) and d.duration==_duration(w),"work-detail-duration")
		"prize","prize-cargo","prize-resolution","prize-port":return _prize_detail_relations(s,r,d)
		"casualty":
			if not _check(s.vessels.has(d.shipId) and s.nearTicks.has(s.campaignId+":"+d.battleId) and d.tick<=s.nearTicks[s.campaignId+":"+d.battleId] and r.id==s.campaignId+":"+d.battleId+":casualty:%d:%d:%s"%[d.tick,d.controlsSequence,d.shipId],"casualty-identity"):return false
			var event=_event(s,r.id);var capacity=Catalog.DATA.profiles[s.vessels[d.shipId].profileId].maxCrew;var before=d.ableBefore+d.woundedBefore+d.prisonersBefore;var after=d.ableAfter+d.woundedAfter+d.prisonersAfter
			if not _check(_equal(event.get("causeIds"),[d.shipId,d.battleId]) and before<=capacity and after<=capacity and before==after+d.dead,"casualty-conservation"):return false
			if d.sunk:return _check(before>0 and after==0 and d.dead==before and d.ordinalAfter==d.ordinalBefore,"casualty-sunk")
			var loss=d.ableBefore-d.ableAfter;var wounded=ceil(d.ordinalAfter/2.0)-ceil(d.ordinalBefore/2.0)
			return _check(loss>0 and d.ordinalAfter==d.ordinalBefore+loss and d.woundedAfter==d.woundedBefore+wounded and d.dead==loss-wounded and d.prisonersAfter==d.prisonersBefore,"casualty-loss")
		"crew-transition":
			return _crew_detail_relations(s,r,d)
	return true

func _story_receipt(s: Dictionary,r: Dictionary,d: Dictionary) -> bool:
	if d.sceneId==SecondVoyageAftermath.SCENE_ID:
		var reason=SecondVoyageAftermath.receipt_error(s,r)
		return _check(reason.is_empty(),"second-voyage-aftermath."+reason)
	var definition=OpeningStory.choice_definition(d.sceneId,d.choiceId)
	if not _check(not definition.is_empty(),"story-choice-definition"):return false
	if not _check(r.id==OpeningStory.receipt_id(s,d.sceneId) and d.portId==definition.portId and d.silverCost==definition.silverCost and _equal(d.reputationEffects,definition.reputationEffects) and d.routeId==definition.routeId and _equal(_event(s,r.id).causeIds,[r.commandId,r.id]),"story-choice-definition"):return false
	var claim_id=s.campaignId+":convoy-001:claim"
	if d.sceneId=="first-return":
		var claim=s.settlements.get(claim_id,{})
		if not _check(d.convoyReceiptId==claim_id and claim.get("kind")=="claim-convoy" and claim.get("details",{}).get("kind")=="convoy" and _precedes(s,claim_id,r.id) and claim.revision<r.revision,"story-return-history"):return false
	elif not _check(d.convoyReceiptId==null,"story-unclaimed-history"):return false
	if d.sceneId in ["old-ledger","pilot-plan"]:
		var accepted=s.settlements.get(s.campaignId+"-convoy-001-accept",{})
		if d.sceneId=="pilot-plan" and not _check(accepted.get("kind")=="accept-convoy" and _precedes(s,accepted.id,r.id) and accepted.revision<r.revision,"story-pilot-history"):return false
		for event in s.chronicle:
			var receipt=s.settlements[event.id]
			if receipt.kind=="depart" or receipt.kind=="claim-convoy" and receipt.get("details",{}).get("contractId")=="convoy-001":
				if not _check(_precedes(s,r.id,event.id),"story-before-first-voyage"):return false
		for suffix in ["grain-a","grain-b"]:
			var vid=s.campaignId+"-"+suffix+"-voyage"
			for terminal in ["arrival","lost"]:
				var id=s.campaignId+":"+vid+":"+terminal
				if s.settlements.has(id) and not _check(_precedes(s,r.id,id),"story-before-first-voyage"):return false
	if not definition.buyIntelligence:return _check(d.intelligence==null,"story-intelligence-definition")
	var intel=d.intelligence;var matching=0
	if not _check(intel is Dictionary and intel.portId=="forward-supply" and intel.sourceId==r.id and intel.observedAt==_event(s,r.id).simTime and intel.confidence==0.65 and intel.stock.size()==1 and intel.stock.has("grain"),"story-intelligence-definition"):return false
	for entry in s.intelligence:
		if entry.sourceId==r.id:
			matching+=1
			if not _check(_equal(entry,intel),"story-intelligence-receipt"):return false
	return _check(matching==1,"story-intelligence-receipt")

func _opening_history(s: Dictionary) -> bool:
	var remaining=400;var paid=0;var prior_revision=-1;var payoff=false
	for event in s.chronicle:
		var receipt=s.settlements[event.id]
		if receipt.kind!="repay-debt":continue
		var d=receipt.details
		if not _check(d.beforePrincipal==remaining and d.amount<=remaining and receipt.revision>prior_revision and _equal(event.causeIds,[receipt.commandId,receipt.id]),"debt-payment-history"):return false
		remaining-=d.amount;paid+=d.amount;prior_revision=receipt.revision
		if not _check(d.afterPrincipal==remaining and d.creditAward==(6 if remaining==0 else 0) and not payoff,"debt-payoff-history"):return false
		payoff=remaining==0
	if not _check(paid<=400 and s.debt.principal==400-paid and s.debt.principal==remaining,"debt-current-principal"):return false
	for entry in s.intelligence:
		if entry.sourceId.begins_with(s.campaignId+":story:"):
			var receipt=s.settlements.get(entry.sourceId,{})
			if not _check(receipt.get("kind")=="story-choice" and receipt.get("details",{}).get("choiceId")=="buy-intelligence" and _equal(receipt.details.intelligence,entry),"story-intelligence-source"):return false
	return true
func _contract_relations(s: Dictionary) -> bool:
	if not _check(s.contracts.has("convoy-001"),"convoy-001"):return false
	for c in s.contracts.values():
		if not _check(c.bonusQuantity==(40 if c.id=="convoy-001" else 20),"contract-canonical"):return false
		var load=s.settlements.get(s.campaignId+"-"+c.id+"-accept",{})
		var critical=["steward-a","steward-b"]
		if c.id=="convoy-002" and load.get("details",{}).get("ships",[]).size()==1:
			critical=[]
			for pid in ["steward-a","steward-b"]:
				var person=s.people.get(pid,{});var death=s.settlements.get(s.campaignId+":person:"+pid+":death",{})
				if person.get("shipId")==load.details.ships[0].shipId and (death.is_empty() or not _precedes(s,death.id,load.id)):critical.append(pid)
		if not _check(c.criticalPersonIds==critical,"contract-critical-persons"):return false
		var vessel_ids={}
		for vid in c.voyageIds:
			if not _check(s.voyages.has(vid) and not vessel_ids.has(s.voyages[vid].vesselId),"contract-voyage"):return false
			vessel_ids[s.voyages[vid].vesselId]=true
		if c.status=="delivered":
			if not _check(not c.voyageIds.is_empty(),"delivered"):return false
			for vid in c.voyageIds:
				if not _check(s.voyages[vid].status=="arrived","delivered"):return false
		if c.status=="offered":
			if not _check(load.is_empty() and c.receiptId==null and (c.voyageIds.size()==2 and c.deadlineAt==1800 if c.id=="convoy-001" else c.voyageIds.is_empty() and c.deadlineAt==0),"offered-contract"):return false
			if c.id=="convoy-002" and not _check(s.contracts["convoy-001"].status=="settled","convoy-002-unlock"):return false
			continue
		if not _check(load.get("kind")=="accept-convoy" and (c.voyageIds.size()==2 if c.id=="convoy-001" else c.voyageIds.size() in [1,2]),"contract-load"):return false
		var expected=[]
		for suffix in ["grain-a","grain-b","flagship","fast"] if c.id=="convoy-001" else ["grain-a","grain-b"]:expected.append(s.campaignId+"-"+suffix)
		var actual=[]
		for v in load.details.ships:actual.append(v.shipId)
		if c.id=="convoy-002" and c.voyageIds.size()==1:
			if not _check(actual.size()==1 and actual[0] in expected,"contract-single-carrier"):return false
			var missing=expected[1] if actual[0]==expected[0] else expected[0]
			if not _sunk_before_load(s,missing,load.id):return false
			expected=[actual[0]]
		if not _check(_equal(actual,expected) and c.deadlineAt==(1800 if c.id=="convoy-001" else _event(s,load.id).simTime+1200),"contract-load-ships-deadline"):return false
		for index in c.voyageIds.size():
			var vid=c.voyageIds[index]
			if not _check(s.voyages.has(vid),"contract-voyage"):return false
			var v=s.voyages[vid]
			if not _check(v.vesselId==expected[index],"contract-vessel-load"):return false
			if c.id=="convoy-002" and not _check(v.id==s.campaignId+"-convoy-002-"+str(index)+"-voyage" and v.routeId=="kinmen-supply-deep","contract-second-voyage"):return false
			if not _check(v.originId==("xiamen" if c.id=="convoy-001" else "kinmen") and v.destinationId==("kinmen" if c.id=="convoy-001" else "forward-supply"),"contract-route"):return false
		if c.status in ["settled","failed"]:
			var claim=s.settlements.get(s.campaignId+":"+c.id+":claim",{})
			if not _check(claim.get("kind")=="claim-convoy" and c.receiptId==claim.id and (claim.details.delivered>0 if c.status=="settled" else claim.details.delivered==0),"contract-claim"):return false
			for vid in c.voyageIds:
				if not _check(s.voyages[vid].status in ["arrived","lost"],"contract-claim-terminal"):return false
		else:
			if not _check(c.receiptId==load.id,"contract-receipt"):return false
		if c.id=="convoy-002" and not _check(s.contracts["convoy-001"].status=="settled","convoy-002-unlock"):return false
	return true
func _sunk_before_load(s: Dictionary,id: String,load_id: String) -> bool:
	if not _check(s.vessels[id].damage.hull==0,"contract-single-sunk-hull"):return false
	var loss=s.campaignId+":"+id+"-voyage:lost"
	for event in s.chronicle:
		if not _precedes(s,event.id,load_id):continue
		var r=s.settlements[event.id];var d=r.get("details",{})
		if r.kind=="shipment-lost" and r.id==loss:return true
		if r.kind=="near-casualties" and d.get("kind")=="casualty" and d.get("shipId")==id and d.get("sunk")==true:return true
		if r.kind=="near-sink" and id in event.causeIds:return true
	return _fail("contract-single-loss-history")
static func _duration(w: Dictionary) -> float:return 30*w.quantity if w.kind=="treatment" else 120 if w.kind=="refit" else max(1,ceil((w.hull+w.sail)/2.0))
func _business_relations(s: Dictionary) -> bool:
	var active={}
	for w in s.works.values():
		if not _check(s.vessels.has(w.shipId) and s.ports.has(w.portId) and w.startAt<=s.simulationSeconds and w.completeAt==w.startAt+_duration(w),"work"):return false
		var payments=0
		var payment={}
		for r in s.settlements.values():
			if r.kind==("treat-wounded" if w.kind=="treatment" else w.kind) and r.get("details",{}).get("workId")==w.id and r.details.status=="active":payments+=1;payment=r
		if not _check(payments==1,"work-payment"):return false
		if w.kind=="treatment" and s.vessels[w.shipId].ownerId=="house-lin":
			var lease=s.settlements.get(s.campaignId+"-convoy-001-accept",{});var leased=[]
			for ship in lease.get("details",{}).get("ships",[]):leased.append(ship.shipId)
			if not _check(lease.get("kind")=="accept-convoy" and w.shipId in leased and _precedes(s,lease.id,payment.id) and lease.revision<payment.revision,"treatment-lease-history"):return false
		if w.kind=="treatment" and not _check(w.cost==4*w.quantity and (w.status!="active" or w.quantity<=s.vessels[w.shipId].crew.wounded),"treatment"):return false
		if w.kind=="treatment" and not _check(_event(s,payment.id).simTime==w.startAt and (w.status!="completed" or _event(s,w.id+":completed").get("simTime",-1)>=w.completeAt),"treatment-time"):return false
		var vessel=s.vessels[w.shipId];var prize=s.prizes.get(vessel.id,{})
		var sold_after=prize.get("status")=="sold" and prize.resolutionReceiptId!=null and w.status=="completed" and _precedes(s,w.id+":completed",prize.resolutionReceiptId)
		if w.kind=="refit" and not _check(w.cost==150 and w.hull==0 and w.sail==0 and w.portId=="xiamen" and (vessel.ownerId=="captain" or sold_after) and w.targetProfileId!=null and Catalog.DATA.profiles.has(w.targetProfileId) and w.targetProfileId==vessel.profileId.trim_suffix("-sails")+"-sails","refit"):return false
		if w.kind=="repair" and not _check(w.targetProfileId==null and w.cost==ceil((w.hull+w.sail)*2) and (w.portId!="forward-supply" or w.hull<=20 and w.sail<=20),"repair"):return false
		var completion=s.settlements.get(w.id+":completed",{})
		if w.status=="active":
			if not _check(completion.is_empty() and not active.has(w.shipId),"work-active"):return false
			active[w.shipId]=true
		elif not _check(w.completeAt<=s.simulationSeconds and completion.get("kind")=="work-completed" and completion.details.get("kind")==("treatment" if w.kind=="treatment" else "work") and completion.details.workId==w.id and completion.details.status=="completed" and _precedes(s,payment.id,completion.id) and (w.kind!="refit" or vessel.profileId==w.targetProfileId),"work-completed"):return false
	for b in s.boardings.values():
		if not _check(s.vessels.has(b.attackerId) and s.vessels.has(b.targetId) and b.attackerId!=b.targetId and not b.targetId in b.participants and b.elapsedSeconds<=s.macroSeconds,"boarding"):return false
		for id in b.participants:
			if not _check(s.vessels.has(id),"boarding-participant"):return false
		var started=false
		for r in s.settlements.values():started=started or r.kind=="start-boarding" and _event_index(s,r.id)>=0 and r.id==s.campaignId+":start-boarding:"+r.commandId
		if not _check(started,"boarding-start"):return false
		if b.status!="active":
			var d=s.settlements.get(s.campaignId+":"+b.id+":"+b.status,{}).get("details",{})
			if not _check(d.get("kind")=="boarding" and d.encounterId==b.id and d.outcome==b.status,"boarding-terminal"):return false
			if b.status=="won" and not _check(b.elapsedSeconds>=20 and b.points.bow.control==100 and b.points.deck.control==100 and b.points.helm.control==100 and b.morale.defender<=20,"boarding-won"):return false
	for kind in ["boarding","work"]:
		for key in s.boardings if kind=="boarding" else s.works:
			var prefix=s.campaignId+":"+kind+":";var ordinal=int(key.trim_prefix(prefix))
			if not _check(ordinal>0 and ordinal<s.nextId and key==prefix+str(ordinal),"allocated"):return false
	for id in s.prizes:
		var p=s.prizes[id];var b=s.boardings.get(p.boardingId,{})
		if not _check(s.vessels.has(id) and p.targetId==id and p.originalOwnerId=="enemy" and b.get("status")=="won" and b.targetId==id,"prize-origin"):return false
		var victory=_winning_receipt(s,id,p.boardingId)
		if victory.is_empty():return false
		var allocation=s.settlements.get(s.campaignId+":prize:"+id,{});var transitions=[];var target=s.vessels[id]
		if not allocation.is_empty() and not _check(allocation.get("kind")=="allocate-prize" and allocation.get("details",{}).get("kind")=="prize" and allocation.details.targetId==id and _precedes(s,victory.id,allocation.id),"prize-allocation"):return false
		for r in s.settlements.values():
			var d=r.get("details",{})
			if d.get("kind")=="prize-resolution" and d.targetId==id or d.get("kind")=="prize-port" and d.shipId==id:transitions.append(r)
		if p.status in ["held","crewed"]:
			if not _check(p.resolutionReceiptId==null and transitions.is_empty() and (allocation.is_empty() and target.ownerId==p.originalOwnerId if p.status=="held" else not allocation.is_empty() and target.ownerId=="captain"),"prize-active"):return false
		else:
			var terminal=s.settlements.get(p.resolutionReceiptId,{}) if p.resolutionReceiptId!=null else {}
			if not _check(not terminal.is_empty() and transitions.size()==1 and transitions[0].id==terminal.id and _precedes(s,victory.id,terminal.id) and target.ownerId==("captain" if p.status=="incorporated" else _terminal_owner(s,id)),"prize-terminal"):return false
			if p.status in ["released","abandoned"]:
				if not _check(allocation.is_empty() and terminal.details.get("kind")=="prize-resolution" and terminal.details.choice==("release" if p.status=="released" else "abandon"),"prize-terminal"):return false
			elif not _check(not allocation.is_empty() and terminal.details.get("kind")=="prize-port" and terminal.details.action==("sell" if p.status=="sold" else "incorporate"),"prize-terminal"):return false
	return true

static func _event_index(s: Dictionary,id: String) -> int:
	for i in s.chronicle.size():
		if s.chronicle[i].id==id:return i
	return -1
static func _event(s: Dictionary,id: String) -> Dictionary:
	var index=_event_index(s,id)
	return s.chronicle[index] if index>=0 else {}
static func _precedes(s: Dictionary,before: String,after: String) -> bool:
	var bi=_event_index(s,before);var ai=_event_index(s,after)
	return bi>=0 and bi<ai and s.settlements[before].revision<=s.settlements[after].revision
static func _buckets_total(d: Dictionary) -> float:return d.able+d.wounded+d.prisoners
func _winning_receipt(s: Dictionary,target: String,boarding: String) -> Dictionary:
	for role in Catalog.DATA.roles:
		if target==s.campaignId+"-"+role.suffix and not _check(role.ownerId=="enemy","prize-origin"):return {}
	var b=s.boardings.get(boarding,{});var r=s.settlements.get(s.campaignId+":"+boarding+":won",{});var d=r.get("details",{})
	if not _check(not b.is_empty() and b.status=="won" and b.targetId==target and r.get("kind")=="boarding-won" and d.get("kind")=="boarding" and d.encounterId==boarding and d.targetId==target and d.attackerId==b.attackerId and d.outcome=="won","prize-victory"):return {}
	return r
func _prize_detail_relations(s: Dictionary,r: Dictionary,d: Dictionary) -> bool:
	var target_id=d.get("targetId",d.get("shipId",""))
	if not _check(s.vessels.has(target_id),"prize-target"):return false
	var target=s.vessels[target_id];var p=s.prizes.get(target_id,{});var capacity=Catalog.DATA.profiles[target.profileId].maxCrew
	var allocation=s.settlements.get(s.campaignId+":prize:"+target_id,{})
	if d.kind=="prize":
		for role in Catalog.DATA.roles:
			if target_id==s.campaignId+"-"+role.suffix and not _check(role.ownerId=="enemy","prize-origin"):return false
		var sold=p.get("status")=="sold" and p.resolutionReceiptId!=null and target.ownerId=="port-prize" and _precedes(s,r.id,p.resolutionReceiptId)
		var won=false
		for b in s.boardings.values():won=won or b.targetId==target_id and b.status=="won"
		return _check(s.vessels.has(d.fromShipId) and d.targetId!=d.fromShipId and (target.ownerId=="captain" or sold) and d.crew>=max(12,target.crew.minimum) and d.crew<=Catalog.DATA.profiles[s.vessels[d.fromShipId].profileId].maxCrew and d.prisoners<=capacity and r.id==s.campaignId+":prize:"+d.targetId and won,"prize-detail")
	if not _check(not p.is_empty(),"prize-record"):return false
	var victory=_winning_receipt(s,target_id,p.boardingId)
	if victory.is_empty():return false
	if d.kind=="prize-cargo":
		if not _check(s.vessels.has(d.toShipId) and d.targetId!=d.toShipId,"prize-receiver"):return false
		var quantity=0.0
		for q in d.cargo.values():quantity+=q
		return _check(quantity>0 and quantity<=Catalog.DATA.profiles[target.profileId].capacity and quantity<=Catalog.DATA.profiles[s.vessels[d.toShipId].profileId].capacity and _precedes(s,victory.id,r.id) and (allocation.is_empty() or _precedes(s,r.id,allocation.id)) and (p.resolutionReceiptId==null or _precedes(s,r.id,p.resolutionReceiptId)),"prize-cargo-history")
	if not _check(r.id==s.campaignId+":prize-disposition:"+target_id and p.resolutionReceiptId==r.id,"prize-disposition-id"):return false
	if d.kind=="prize-resolution":
		if not _check(p.boardingId==d.boardingId and p.status==("released" if d.choice=="release" else "abandoned") and allocation.is_empty() and _precedes(s,victory.id,r.id) and _count(d.movedWounded+d.movedPrisoners+d.restoredAble) and d.movedWounded+d.movedPrisoners+d.restoredAble<=capacity,"prize-resolution-history"):return false
		if d.choice=="release":return _check(d.toShipId==null and d.movedWounded==0 and d.movedPrisoners==0 and target.crew.prisoners==0,"prize-release")
		return _check(d.toShipId!=null and s.vessels.has(d.toShipId) and d.toShipId!=d.targetId and d.restoredAble==0 and _buckets_total(target.crew)==0 and d.movedWounded+d.movedPrisoners<=Catalog.DATA.profiles[s.vessels[d.toShipId].profileId].maxCrew,"prize-abandon")
	if not _check(d.portId in ["xiamen","kinmen"] and allocation.get("details",{}).get("kind")=="prize" and _precedes(s,allocation.id,r.id) and p.status==("sold" if d.action=="sell" else "incorporated") and r.kind==("sell-prize" if d.action=="sell" else "incorporate-prize") and _count(d.movedAble+d.movedWounded+d.movedPrisoners) and d.movedAble+d.movedWounded+d.movedPrisoners<=capacity,"prize-port-history"):return false
	if d.action=="sell":
		var price=max(1,floor(200*target.damage.hull/100.0+100*target.damage.sail/100.0));var empty=true
		for q in target.cargo.values():empty=empty and q==0
		return _check(d.silver==price and d.crewToShipId!=null and s.vessels.has(d.crewToShipId) and d.crewToShipId!=d.shipId and _buckets_total(target.crew)==0 and empty and d.movedAble+d.movedWounded+d.movedPrisoners<=Catalog.DATA.profiles[s.vessels[d.crewToShipId].profileId].maxCrew,"prize-sale")
	return _check(d.silver==0 and d.crewToShipId==null and d.movedAble+d.movedWounded+d.movedPrisoners==0,"prize-incorporate")
static func _convoy_transfers(s: Dictionary,id: String,after,through) -> Dictionary:
	var outgoing=0;var incoming=0
	for r in s.settlements.values():
		if r.revision<=after or r.revision>through:continue
		var d=r.get("details",{})
		if d.get("kind")=="prize" and d.fromShipId==id:outgoing+=d.crew
		if d.get("kind")=="prize-resolution" and d.choice=="abandon":
			if d.targetId==id:outgoing+=d.movedWounded
			if d.toShipId==id:incoming+=d.movedWounded
		if d.get("kind")=="prize-port" and d.action=="sell":
			if d.shipId==id:outgoing+=d.movedAble+d.movedWounded
			if d.crewToShipId==id:incoming+=d.movedAble+d.movedWounded
	return {"outgoing":outgoing,"incoming":incoming}
func _crew_detail_relations(s: Dictionary,r: Dictionary,d: Dictionary) -> bool:
	if not _check(r.id==d.causeId+":crew","crew-cause"):return false
	var ids={};var causes=[d.causeId]
	for change in d.changes:
		if not _check(s.vessels.has(change.shipId) and not ids.has(change.shipId),"crew-transition-ship"):return false
		ids[change.shipId]=true;causes.append(change.shipId)
		var capacity=Catalog.DATA.profiles[s.vessels[change.shipId].profileId].maxCrew
		if not _check(_buckets_total(change.before)<=capacity and _buckets_total(change.after)<=capacity,"crew-capacity"):return false
	var event=_event(s,r.id)
	if not _check(_equal(event.get("causeIds"),causes),"crew-cause-ids"):return false
	if d.reason=="boarding-attrition":
		var prefix=s.campaignId+":";var separator=d.causeId.rfind(":attrition:");var boarding_id=d.causeId.substr(prefix.length(),separator-prefix.length());var elapsed=int(d.causeId.substr(separator+11));var b=s.boardings.get(boarding_id,{})
		if not _check(separator>prefix.length() and not b.is_empty() and elapsed>0 and elapsed%10==0 and elapsed<=b.elapsedSeconds and d.causeId==prefix+b.id+":attrition:"+str(elapsed) and d.changes.size()==2 and d.changes[1].shipId==b.targetId and d.changes[0].shipId!=b.targetId,"crew-attrition"):return false
		for c in d.changes:
			if not _check(c.before.able>0 and c.after.able==c.before.able-1 and c.after.wounded==c.before.wounded+1 and c.after.prisoners==c.before.prisoners,"crew-attrition-change"):return false
		return true
	var action=s.settlements.get(d.causeId,{});var detail=action.get("details",{})
	if not _check(not action.is_empty() and _event_index(s,d.causeId)>=0 and _event(s,d.causeId).simTime==event.simTime,"crew-action"):return false
	var c=d.changes[0]
	match d.reason:
		"boarding-victory":return _check(action.kind=="boarding-won" and detail.get("kind")=="boarding" and d.changes.size()==1 and c.shipId==detail.targetId and c.after.able==0 and c.after.wounded==c.before.wounded and c.after.prisoners==c.before.prisoners+c.before.able,"crew-victory")
		"allocation":
			if not _check(action.kind=="allocate-prize" and detail.get("kind")=="prize" and d.changes.size()==2 and d.changes[0].shipId==detail.fromShipId and d.changes[1].shipId==detail.targetId,"crew-allocation"):return false
			for i in d.changes.size():
				var item=d.changes[i]
				if not _check(item.after.able==item.before.able+(-detail.crew if i==0 else detail.crew) and item.after.wounded==item.before.wounded and item.after.prisoners==item.before.prisoners,"crew-allocation-change"):return false
		"release-prisoners":return _check(action.kind=="release-prisoners" and d.changes.size()==1 and c.shipId in _event(s,d.causeId).causeIds and c.before.prisoners>0 and c.after.prisoners==0 and c.after.able==c.before.able and c.after.wounded==c.before.wounded,"crew-prisoner-release")
		"prize-release":return _check(action.kind=="resolve-prize" and detail.get("kind")=="prize-resolution" and detail.choice=="release" and d.changes.size()==1 and c.shipId==detail.targetId and c.before.able==0 and c.after.able==c.before.prisoners and c.after.wounded==c.before.wounded and c.after.prisoners==0 and detail.restoredAble==c.before.prisoners,"crew-prize-release")
		"prize-rescue","prize-sale":
			var rescue=d.reason=="prize-rescue"
			if not _check(action.kind=="resolve-prize" and detail.get("kind")=="prize-resolution" and detail.choice=="abandon" if rescue else action.kind=="sell-prize" and detail.get("kind")=="prize-port" and detail.action=="sell","crew-transfer-action") or not _check(d.changes.size()==2,"crew-transfer-count"):return false
			var to=d.changes[1]
			if rescue:
				if not _check(c.shipId==detail.targetId and to.shipId==detail.toShipId and c.before.able==0 and detail.movedWounded==c.before.wounded and detail.movedPrisoners==c.before.prisoners,"crew-rescue"):return false
			elif not _check(c.shipId==detail.shipId and to.shipId==detail.crewToShipId and detail.movedAble==c.before.able and detail.movedWounded==c.before.wounded and detail.movedPrisoners==c.before.prisoners,"crew-sale"):return false
			return _check(_buckets_total(c.after)==0 and to.after.able==to.before.able+c.before.able and to.after.wounded==to.before.wounded+c.before.wounded and to.after.prisoners==to.before.prisoners+c.before.prisoners and to.after.able>=ceil(to.after.prisoners/5.0),"crew-transfer")
		_:return _check(action.kind=="work-completed" and detail.get("kind")=="treatment" and d.changes.size()==1 and c.shipId==detail.shipId and c.after.able==c.before.able+detail.quantity and c.after.wounded==c.before.wounded-detail.quantity and c.after.prisoners==c.before.prisoners,"crew-treatment")
	return true
func _crew_history(s: Dictionary) -> bool:
	var ordinals={};var history={};var fences={}
	for event in s.chronicle:
		var r=s.settlements[event.id];var d=r.get("details",{})
		if d.get("kind")=="crew-transition":
			for c in d.changes:
				if history.has(c.shipId) and not _check(_equal(history[c.shipId],c.before),"crew-chain"):return false
				history[c.shipId]=c.after
			continue
		var changed=[]
		match d.get("kind"):
			"prize-resolution":changed=[d.targetId]+([d.toShipId] if d.toShipId!=null else [])
			"prize-port":
				if d.action=="sell":changed=[d.shipId,d.crewToShipId]
			"prize":changed=[d.fromShipId,d.targetId]
			"boarding":
				if r.kind=="boarding-won":changed=[d.targetId]
			"treatment":
				if d.status=="completed":changed=[d.shipId]
		if r.kind=="release-prisoners":
			for id in event.causeIds:
				if s.vessels.has(id):changed.append(id)
		var witnessed=r.kind=="release-prisoners" and not history.is_empty()
		for id in changed:witnessed=witnessed or history.has(id)
		if witnessed and not _check(s.settlements.get(event.id+":crew",{}).get("details",{}).get("kind")=="crew-transition","crew-witness"):return false
		if d.get("kind")!="casualty":continue
		var before={"able":d.ableBefore,"wounded":d.woundedBefore,"prisoners":d.prisonersBefore}
		if history.has(d.shipId) and not _check(_equal(history[d.shipId],before),"crew-chain"):return false
		history[d.shipId]={"able":d.ableAfter,"wounded":d.woundedAfter,"prisoners":d.prisonersAfter}
		var fence=fences.get(d.shipId,{})
		if fence.get("battleId")==d.battleId and not _check(d.tick>fence.tick or d.tick==fence.tick and d.controlsSequence>fence.sequence,"casualty-order"):return false
		fences[d.shipId]={"battleId":d.battleId,"tick":d.tick,"sequence":d.controlsSequence}
		if not _check(d.ordinalBefore==ordinals.get(d.shipId,0),"casualty-chain"):return false
		ordinals[d.shipId]=d.ordinalAfter
	for id in history:
		var c=s.vessels[id].crew
		if not _check(_equal(history[id],{"able":c.able,"wounded":c.wounded,"prisoners":c.prisoners}),"crew-current"):return false
	for id in ordinals:
		if not _check(s.casualtyOrdinals.get(id,0)==ordinals[id],"casualty-ordinal"):return false
	for id in s.casualtyOrdinals:
		if not _check(s.casualtyOrdinals[id]==ordinals.get(id,0),"casualty-ordinal"):return false
	return true
