extends RefCounted
## Source VisualScenarios + GameScene QA coordinator; Encounter owns every result.
const Encounter=preload("res://modules/naval_simulation/encounter.gd")
const Simulation=preload("res://game/runtime/sailing_simulation.gd")
const Waves=preload("res://modules/physics_engine/ocean/coastal_wave_field.gd")
const Descriptors=preload("res://modules/contracts/wave_descriptor.gd")
const SCENARIOS:=["fleet","damage","sink","impact","impact-weak","benchmark","shore-escape","wave-fisherman","wave-patrol","crew-fuchuan","crew-fisherman","crew-merchant","crew-voc","crew-patrol","crew-heavy"]
const LABELS:=["六船航行与尾浪","受损船帆与三种弹药","真实炮击沉船","近距炮击与船员物理冲击","低伤害炮击与受击恢复（QA火力2%）","三船炮战性能","岸线脱困与自动收帆","原海浪 · 渔船波谷浮态","原海浪 · 巡哨船波谷浮态","船员实测 · fuchuan","船员实测 · fisherman","船员实测 · merchant","船员实测 · voc","船员实测 · patrol","船员实测 · heavy"]
const PAUSES:=["player","menu","blur","hidden","loading","error","wave","benchmark"]
const WAYPOINT:={"x":-178,"z":475}
var simulation: RefCounted
var diagnostics:=FrameDiagnostics.new()
var _height: Callable
var _waves: RefCounted
var _scenario:="fleet"
var _pauses: Dictionary={}
var _handling:="realistic"
var _playback:=1.0
var _benchmark:=0.0
var _frames: Array=[]
var _generation:=0
var _disposed:=true
var _notice:=""

class FrameDiagnostics extends RefCounted:
	var _samples: Array=[]
	var _events: Array=[]
	var _previous: Variant=null
	func record_interval(interval: Dictionary) -> void:
		var start: float=interval.callbackTimestampMs-interval.elapsedMs
		var overlaps: bool=interval.elapsedMs>0 and _previous!=null and _previous.cpuCompletedAtMs>_previous.cpuStartedAtMs and _previous.cpuStartedAtMs<interval.callbackTimestampMs and _previous.cpuCompletedAtMs>start
		var copy:=interval.duplicate(true)
		copy.index=_samples.size()+1; copy.previousCompletedFrame=_previous.duplicate(true) if overlaps else null
		_samples.append(copy)
	func complete_frame(frame: Dictionary) -> void: _previous=frame.duplicate(true)
	func note_event(event: Dictionary) -> void: _events.append(event.duplicate(true))
	func reset() -> void: _samples.clear(); _events.clear(); _previous=null
	func snapshot() -> Dictionary: return {"samples":_samples.duplicate(true),"events":_events.duplicate(true)}
	func summary() -> Dictionary:
		var total:=0.0; var maximum:=0.0; var included:=0; var sorted: Array=[]
		var over:={25:0,50:0,100:0,500:0,1000:0}
		for sample: Dictionary in _samples:
			total+=sample.elapsedMs; maximum=maxf(maximum,sample.elapsedMs); sorted.append(sample.elapsedMs)
			if sample.includedInMetrics: included+=1
			for threshold: int in over:
				if sample.elapsedMs>threshold: over[threshold]+=1
		sorted.sort()
		var top:=_samples.duplicate(true)
		top.sort_custom(func(a,b): return a.elapsedMs>b.elapsedMs if a.elapsedMs!=b.elapsedMs else a.index<b.index)
		var counts:={"blur":0,"visibility-hidden":0,"visibility-visible":0,"pause":0,"resume":0,"export":0}
		for event: Dictionary in _events:
			if counts.has(event.type): counts[event.type]+=1
		return {"sampleCount":_samples.size(),"includedInMetrics":included,"totalMs":total,"meanMs":total/_samples.size() if not _samples.is_empty() else 0.0,"maxMs":maximum,"p99Ms":sorted[maxi(0,ceili(sorted.size()*0.99)-1)] if not sorted.is_empty() else 0.0,"overMs":over,"topIntervals":top.slice(0,10),"eventCounts":counts}

static func scenario_config(id: String) -> Dictionary:
	if id not in SCENARIOS: return {}
	if id=="impact-weak":
		var config:=scenario_config("impact"); config.battleId="visual-impact-weak"; config.ships[0].stats={"cannonMultiplier":0.02}; return config
	if id=="impact": return {"seed":1661,"playerId":"player","battleId":"visual-impact","wind":{"direction":{"x":1,"y":0},"speed":0},"ships":[{"id":"player","kind":"fuchuan","team":"player","position":{"x":0,"z":0},"heading":0,"crew":100,"sailDeployment":0},{"id":"inspection-voc","kind":"voc","team":"hostile","position":{"x":0,"z":35},"heading":0,"crew":30,"sailDeployment":0,"cooldownSeconds":{"port":60,"starboard":60}}]}
	var player:={"id":"player","name":"验收·定海号","kind":"fuchuan","team":"player","position":{"x":0,"z":0},"heading":0}
	if id.begins_with("crew-") or id.begins_with("wave-"):
		player.merge({"name":"验收·真实船员" if id.begins_with("crew-") else "验收·波谷浮态","kind":id.substr(5),"position":{"x":-530.4088827004637,"z":-723.2650164094327},"heading":2.356194490192344,"speed":0,"sailDeployment":0},true)
		return {"seed":1661,"playerId":"player","battleId":"visual-"+id,"wind":{"direction":{"x":1,"y":0},"speed":0},"ships":[player]}
	if id=="shore-escape":
		player.merge({"name":"验收·岸线操纵","position":{"x":-333,"z":639},"heading":131*PI/180,"speed":0.2,"hull":81.6,"sail":80,"crew":37,"sailDeployment":1,"autoTrim":true,"stats":{"maxHull":120,"maxCrew":100,"cargoMass":3000}},true)
		return {"seed":1661,"playerId":"player","battleId":"visual-shore-escape","wind":{"direction":{"x":-1,"y":0},"speed":9},"ships":[player]}
	var ships: Array=[]
	if id=="fleet":
		var kinds:=["fuchuan","fisherman","merchant","voc","patrol","heavy"]
		var names:=["定海福船","金门渔舟","泉州商船","荷兰商舰","巡哨快船","远洋重舰"]
		for index in kinds.size():
			var ship:=player.duplicate(true)
			ship.merge({"id":"player" if index==0 else "inspection-"+kinds[index],"kind":kinds[index],"name":names[index],"team":"player" if index==0 else "neutral","position":{"x":(index%3-1)*70,"z":(floori(index/3.0)-0.5)*85},"speed":3,"sailDeployment":0.8},true); ships.append(ship)
	else:
		var sinking:=id=="sink"; var benchmark:=id=="benchmark"
		if not sinking and not benchmark: player.merge({"hull":58,"sail":35,"crew":45},true)
		if benchmark: player.merge({"stats":{"maxHull":1000},"hull":1000},true)
		ships=[player,{"id":"inspection-voc","name":"低耐久沉船靶舰" if sinking else "弹药与船帆靶舰","kind":"voc","team":"hostile","position":{"x":0,"z":70},"heading":0,"sailDeployment":0,"hull":8 if sinking else 100,"crew":30,"sail":100 if sinking else 40,"stats":{"cannonMultiplier":0.1},"cooldownSeconds":{"port":60,"starboard":60}}]
		if benchmark:
			ships[1].merge({"crew":120,"stats":{"maxCrew":120,"cannonMultiplier":0.1},"sail":100,"sailDeployment":1,"cooldownSeconds":{"port":0,"starboard":0}},true)
			ships.append({"id":"inspection-fuchuan","name":"性能验收第二敌舰","kind":"fuchuan","team":"hostile","position":{"x":0,"z":-85},"heading":0,"stats":{"cannonMultiplier":0.1}})
	return {"seed":1661,"playerId":"player","wind":{"direction":{"x":-0.8,"y":-0.6},"speed":14},"ships":ships,"battleId":"visual-"+id}

static func no(reason: String) -> Dictionary: return {"ok":false,"reason":reason}
func configure(height: Callable,options: Dictionary={}) -> Dictionary:
	if not height.is_valid() or options.get("scenario","fleet") not in SCENARIOS: return no("invalid-visual-scenario")
	_height=height; _waves=Waves.new(); _waves.configure(height); _scenario=options.get("scenario","fleet")
	return _restart()
func _restart() -> Dictionary:
	var config:=scenario_config(_scenario)
	config.merge({"sampleTerrainHeight":_height,"waveSampler":_waves,"oceanWaves":Descriptors.original_descriptors()},true)
	var native:=Encounter.new(config)
	if not native.last_error.is_empty(): return no(native.last_error)
	if _scenario=="shore-escape":
		var receipt: Dictionary=native.navigate("player",WAYPOINT)
		if not receipt.ok: return receipt
	if simulation: simulation.set_paused(true)
	simulation=Simulation.new(native); _handling="realistic"; _playback=1.0; _benchmark=0; _frames.clear(); diagnostics.reset()
	var retained: Dictionary={}
	for reason in ["hidden","loading"]:
		if _pauses.has(reason): retained[reason]=true
	_pauses=retained; _generation+=1; _disposed=false; _notice=""; _sync_pause(); return {"ok":true}
func is_paused() -> bool: return not _pauses.is_empty()
func _sync_pause() -> void:
	if simulation: simulation.set_paused(is_paused())
func set_pause(reason: String,value: bool) -> Dictionary:
	if _disposed or reason not in PAUSES: return no("invalid-visual-pause")
	var changed:=_pauses.has(reason)!=value
	if value: _pauses[reason]=true
	else: _pauses.erase(reason)
	if changed: note_event("pause" if value else "resume")
	_sync_pause(); return {"ok":true}
func note_event(type: String) -> void: diagnostics.note_event({"type":type,"timestampMs":Time.get_ticks_usec()/1000.0,"benchmarkSeconds":_benchmark,"phase":phase()})
func set_handling_mode(mode: String) -> void:
	if mode not in ["assisted","realistic"]: return
	_handling=mode
	if simulation: simulation.set_handling_mode(mode)
func set_held(code: String,value: bool) -> void:
	if not _disposed and simulation: simulation.set_held(code,value)
func command(intent: Dictionary) -> Dictionary:
	if _disposed or not simulation: return no("visual-qa-disposed")
	match intent.get("type",""):
		"restart": return _restart()
		"scenario":
			if intent.get("value") not in SCENARIOS: return no("invalid-visual-scenario")
			_scenario=intent.value; return _restart()
		"pause": return set_pause("player",not _pauses.has("player"))
		"resume":
			for reason in ["player","menu","blur"]: _pauses.erase(reason)
			note_event("resume"); _sync_pause(); return {"ok":true}
		"menu": return set_pause("menu",bool(intent.get("value",false)))
		"playback":
			if _scenario=="benchmark" or intent.get("value") not in ([1.0,0.25,0.1,4.0] if _scenario=="shore-escape" else [1.0,0.25,0.1]): return no("invalid-visual-playback")
			_playback=float(intent.value); return {"ok":true}
		"handling":
			if intent.get("value") not in ["realistic","assisted"]: return no("invalid-visual-handling")
			set_handling_mode(intent.value); return {"ok":true}
	if is_paused(): return no("visual-qa-paused")
	match intent.get("type",""):
		"trim": simulation.toggle_trim()
		"sails":
			var value: Variant=intent.get("value")
			if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or value<0 or value>1: return no("invalid-sails")
			simulation.set_sails(value)
		"fire","select-ammo": simulation.action(intent)
		_: return no("unknown-visual-command")
	return {"ok":true}
func phase() -> String:
	if _scenario=="benchmark" and _benchmark>=80: return "complete"
	if is_paused(): return "paused"
	if _scenario=="benchmark": return "warmup" if _benchmark<20 else "sampling"
	return "running"
func advance(seconds: float,callback_ms: float=-1.0) -> float:
	if _disposed or not simulation or is_paused() or not is_finite(seconds) or seconds<=0: return 0.0
	var before: float=simulation.snapshot().time
	if _scenario=="benchmark": _benchmark+=seconds
	var included:=_scenario!="benchmark" or _benchmark>=20 and _benchmark<80
	diagnostics.record_interval({"elapsedMs":seconds*1000,"callbackTimestampMs":callback_ms if callback_ms>=0 else Time.get_ticks_usec()/1000.0,"benchmarkSeconds":_benchmark,"phase":phase(),"includedInMetrics":included})
	if included:
		_frames.append(seconds*1000)
		if _frames.size()>7200: _frames.pop_front()
	var amount:=minf(0.1,seconds*_playback)
	if _scenario.begins_with("wave-"): amount=maxf(0,minf(amount,4.6-before))
	simulation.advance(amount)
	for receipt: Dictionary in simulation.drain_results():
		if not receipt.result.ok: _notice=receipt.result.get("reason","command-rejected")
	var after: float=simulation.snapshot().time
	if _scenario.begins_with("wave-") and after>=4.6-1e-9: set_pause("wave",true)
	if _scenario=="benchmark" and _benchmark>=80: set_pause("benchmark",true)
	return after-before
func original_metrics() -> Dictionary:
	var total:=0.0; var sorted:=_frames.duplicate(); sorted.sort()
	for interval: float in _frames: total+=interval
	return {"frames":_frames.size(),"seconds":total/1000,"fps":_frames.size()*1000/total if total>0 else 0.0,"p95Ms":sorted[maxi(0,ceili(sorted.size()*0.95)-1)] if not sorted.is_empty() else 0.0}
func snapshot() -> Dictionary:
	if _disposed or not simulation: return {}
	return {"naval":simulation.snapshot(),"runtime":{"scenario":_scenario,"generation":_generation,"paused":is_paused(),"pauseReasons":_pauses.keys(),"handlingMode":_handling,"playback":_playback,"benchmarkSeconds":_benchmark,"phase":phase(),"notice":_notice,"waypoint":WAYPOINT.duplicate() if _scenario=="shore-escape" else null}}
func render_snapshot() -> Dictionary: return simulation.render_snapshot() if not _disposed and simulation else {}
func drain_events() -> Array: return simulation.drain_events() if not _disposed and simulation else []
func sample_water_height(x: float,z: float,seconds: float) -> float: return _waves.sample(x,z,seconds).height if _waves else 0.0
func dispose() -> void:
	if simulation: simulation.set_paused(true)
	simulation=null; _waves=null; _height=Callable(); _disposed=true; _pauses.clear(); _frames.clear(); diagnostics.reset()
