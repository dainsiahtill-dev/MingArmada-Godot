extends RefCounted
## Standalone source sea practice; no career, reward, or save authority.
const Encounter = preload("res://modules/naval_simulation/encounter.gd")
const Simulation = preload("res://game/runtime/sailing_simulation.gd")
const Waves = preload("res://modules/physics_engine/ocean/coastal_wave_field.gd")
const Descriptors = preload("res://modules/contracts/wave_descriptor.gd")
const Fire = preload("res://modules/naval_simulation/combat/fire_control.gd")
const Launcher = preload("res://modules/naval_simulation/combat/fire_launcher.gd")
const PAUSES := ["player","menu","blur","hidden","loading","error","result","surrender","chart"]
var simulation: RefCounted
var _height: Callable
var _waves: RefCounted
var _options: Dictionary = {}
var _pauses: Dictionary = {}
var _handling := "assisted"
var _notice := ""
var _quote: Dictionary = {}
var _generation := 0
var _disposed := true
var _crew_changed := false
static func no(reason: String) -> Dictionary: return {"ok":false,"reason":reason}
func configure(height: Callable,options: Dictionary={}) -> Dictionary:
	if not height.is_valid() or options.get("mode","duel") not in ["duel","fleet","sail","fire"]: return no("invalid-practice-mode")
	_height=height; _options=options.duplicate(true); _waves=Waves.new(); _waves.configure(height)
	return _restart()
func _restart() -> Dictionary:
	var mode: String=_options.get("mode","duel")
	var config := {"referenceHandling":true,"referenceGunnery":true,"seed":1661,"enemyCount":1 if mode=="duel" else 2 if mode=="fleet" else 0,"mode":"terminal","wind":{"direction":{"x":-0.8,"y":-0.6},"speed":14.0},"sampleTerrainHeight":_height,"waveSampler":_waves,"oceanWaves":Descriptors.original_descriptors(),"battleId":"practice-%s-%s-%s" % [mode,OS.get_process_id(),_generation+1]}
	config.environmentRoute = "sailing" if mode=="sail" else "battle"
	if mode=="fire":
		# Finite skirmish equipment, restored only by restarting this unsaved battle.
		config.ships=[]
		for entry in [["player","镇海号","player",0.0],["enemy-1","海盗福船","hostile",60.0]]:
			config.ships.append({"id":entry[0],"name":entry[1],"kind":"fuchuan","team":entry[2],"position":{"x":0.0,"z":entry[3]},"heading":0.0,"sailDeployment":0.0,"fireControl":Fire.initial(24),"fireLauncher":Launcher.initial(2,2)})
	if mode=="sail":
		config.ships=[{"id":"player","name":"定海","kind":"fuchuan","team":"player","position":{"x":0,"z":0},"heading":0},{"id":"merchant","name":"泉州商船","kind":"merchant","team":"neutral","position":{"x":140,"z":100},"heading":0},{"id":"fisher","name":"金门渔舟","kind":"fisherman","team":"neutral","position":{"x":60,"z":-120},"heading":PI/3,"sailDeployment":0.65}]
	var native := Encounter.new(config)
	if not native.last_error.is_empty(): return no(native.last_error)
	if simulation: simulation.set_paused(true)
	simulation=Simulation.new(native); simulation.set_handling_mode(_handling)
	var retained: Dictionary={}
	for reason in ["hidden"]:
		if _pauses.has(reason): retained[reason]=true
	_pauses=retained; _quote.clear(); _notice=""; _crew_changed=false; _generation+=1; _disposed=false; _sync_pause()
	return {"ok":true}
func is_paused() -> bool: return not _pauses.is_empty()
func presentation_pause_reasons() -> Array: return _pauses.keys()
func _sync_pause() -> void:
	if simulation: simulation.set_paused(is_paused())
func set_pause(reason: String,value: bool) -> Dictionary:
	if _disposed or reason not in PAUSES: return no("invalid-practice-pause")
	if value: _pauses[reason]=true
	else: _pauses.erase(reason)
	_sync_pause(); return {"ok":true}
func set_handling_mode(mode: String) -> void:
	if mode not in ["assisted","realistic"]: return
	_handling=mode
	if simulation: simulation.set_handling_mode(mode)
func set_held(code: String,value: bool) -> void:
	if not _disposed and simulation: simulation.set_held(code,value)
func release_held_controls() -> void:
	if not _disposed and simulation: simulation.release_held_controls()
func command(intent: Dictionary) -> Dictionary:
	if _disposed or not simulation: return no("practice-disposed")
	match intent.get("type",""):
		"restart": return _restart()
		"pause": return set_pause("player",not _pauses.has("player"))
		"resume":
			for reason in ["player","menu","blur"]: _pauses.erase(reason)
			_sync_pause(); return {"ok":true}
		"menu": return set_pause("menu",bool(intent.get("value",false)))
		"cancel-surrender":
			_quote.clear(); return set_pause("surrender",false)
		"begin-surrender":
			if is_paused() or not _quote.is_empty(): return no("请先继续交战")
			var receipt: Dictionary=simulation.encounter.preview_surrender()
			if not receipt.ok: return receipt
			_quote=receipt.offer.duplicate(true); set_pause("surrender",true); return {"ok":true}
		"confirm-surrender":
			if _quote.is_empty() or intent.get("request") != _quote.request: return no("Surrender request is stale")
			var receipt: Dictionary=simulation.encounter.command({"type":"surrender","request":_quote.request})
			if receipt.ok:
				_quote.clear(); _pauses.erase("surrender"); _pauses.result=true
				simulation.refresh_snapshot(); _sync_pause()
			return receipt
	if is_paused() or simulation.current_status() in ["victory","defeat","surrendered"]: return no("请先继续航行")
	match intent.get("type",""):
		"mouse-course":
			if not intent.get("point") is Dictionary: return no("请选择有效的海面位置")
			return simulation.set_course(intent.point)
		"stop-sailing": return simulation.stop_course()
		"trim": simulation.toggle_trim()
		"sails":
			var value: Variant=intent.get("value")
			if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or value<0 or value>1: return no("invalid-sails")
			simulation.set_sails(value)
		"launch-fire","fire-control":
			if _options.get("mode","duel")!="fire": return no("本场未配火攻与损管装备")
			if intent.has("shipId") and intent.shipId!=simulation.encounter.player_id: return no("只能指挥本船")
			simulation.action(intent)
		"fire","select-ammo": simulation.action(intent)
		_: return no("unknown-practice-command")
	return {"ok":true}
func nearest_side() -> String:
	var native: Dictionary=simulation.snapshot(); var player: Dictionary=Simulation._ship(native,native.playerId)
	var nearest: Dictionary={}; var distance:=INF
	for ship: Dictionary in native.ships:
		if ship.team!="hostile" or ship.hull<=0: continue
		var delta:=Vector2(ship.visual.position.x-player.visual.position.x,ship.visual.position.z-player.visual.position.z)
		if delta.length_squared()<distance: nearest=ship; distance=delta.length_squared()
	if nearest.is_empty(): return "starboard"
	var dx: float=nearest.visual.position.x-player.visual.position.x; var dz: float=nearest.visual.position.z-player.visual.position.z
	return "starboard" if -sin(player.visual.heading)*dx+cos(player.visual.heading)*dz>=0 else "port"
func advance(seconds: float) -> float:
	_crew_changed=false
	if _disposed or not simulation or is_paused(): return 0
	var before: float=simulation.current_time()
	var previous_crew: Dictionary={}
	for ship:Dictionary in simulation.snapshot().ships: previous_crew[ship.id]=ship.crew
	simulation.advance(seconds)
	for ship:Dictionary in simulation.snapshot().ships:
		if previous_crew.has(ship.id) and ship.crew<previous_crew[ship.id]: _crew_changed=true
	for receipt: Dictionary in simulation.drain_results():
		if not receipt.result.ok: _notice=fire_reason(receipt.result.get("reason","command-rejected"))
		elif receipt.command.get("type")=="launch-fire": _notice="载荷已投出；能否命中取决于航迹与敌舰移动。"
		elif receipt.command.get("type")=="fire-control": _notice="水手正返回原岗位。" if receipt.command.get("crew",0)==0 else "水手正赶往火场；火灭后会自动归位。"
	if simulation.current_status() in ["victory","defeat","surrendered"]: set_pause("result",true)
	return simulation.current_time()-before
func snapshot() -> Dictionary:
	if _disposed or not simulation: return {}
	var phase: String = simulation.handling_status().get("phase","idle")
	var assistance_notice: String = {"wind-recovery":"迎风起步辅助：先转出迎风区，再逐渐升帆。A/D 转舵可立即接管。","blocked":"起步辅助已停止；调整航向后重新按 W。"}.get(phase, "")
	var native: Dictionary=simulation.snapshot()
	var state: Dictionary={"generation":_generation,"mode":_options.get("mode","duel"),"paused":is_paused(),"pauseReasons":_pauses.keys(),"handlingMode":_handling,"notice":_notice if not _notice.is_empty() else assistance_notice,"surrenderQuote":_quote.duplicate(true)}
	if state.mode=="fire":
		state.fireQuotes={}
		for target:Dictionary in native.ships:
			if target.team!="hostile" or target.hull<=0.0: continue
			state.fireQuotes[target.id]={}
			for payload:String in Launcher.PAYLOADS:
				state.fireQuotes[target.id][payload]=simulation.encounter.preview_fire_launch(native.playerId,target.id,payload)
	return {"naval":native,"runtime":state}
static func fire_reason(reason:String)->String:
	return {"fire-launch-out-of-range":"靠近敌舰至70米内再投送。","Fire launcher reloading":"投送器正在准备下一枚载荷。","Insufficient fire launcher crew":"至少需要4名空闲水手操作投送器。","Out of fire payloads":"该载荷已用尽。","friendly-fire-blocked":"友船挡在弹道上，请调整位置。","target-unavailable":"目标已离场或不能攻击。","No fire launcher":"本船未配火攻投送器。","invalid-fire-assignment":"调派人数超过当前可用水手。"}.get(reason,reason)
func render_snapshot() -> Dictionary: return simulation.render_snapshot() if not _disposed and simulation else {}
func requires_immediate_actor_presentation() -> bool:
	if _disposed or not simulation: return false
	if requires_full_actor_presentation(): return true
	# Observe without draining: the scene presents original ordered events once.
	for event: Dictionary in simulation._events:
		if event.get("type") == "fire": return true
		if event.get("type") == "hit" and float(event.get("damage",{}).get("crew",0.0)) > 0.0: return true
	return false
func requires_full_actor_presentation() -> bool:
	if _disposed or not simulation: return false
	if _crew_changed: return true
	return simulation._events.any(func(event):return event.get("type")=="fire-payload-hit")
func drain_events() -> Array: return simulation.drain_events() if not _disposed and simulation else []
func sample_water_height(x: float,z: float,seconds: float) -> float: return _waves.sample_height(x,z,seconds) if _waves else 0
func dispose() -> void:
	if simulation: simulation.set_paused(true)
	simulation=null; _disposed=true; _quote.clear(); _pauses.clear()
