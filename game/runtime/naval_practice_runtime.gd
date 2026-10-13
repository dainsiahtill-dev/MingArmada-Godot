extends RefCounted
## Standalone source sea practice; no career, reward, or save authority.
const Encounter = preload("res://modules/naval_simulation/encounter.gd")
const Simulation = preload("res://game/runtime/sailing_simulation.gd")
const Waves = preload("res://modules/physics_engine/ocean/coastal_wave_field.gd")
const Descriptors = preload("res://modules/contracts/wave_descriptor.gd")
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
static func no(reason: String) -> Dictionary: return {"ok":false,"reason":reason}
func configure(height: Callable,options: Dictionary={}) -> Dictionary:
	if not height.is_valid() or options.get("mode","duel") not in ["duel","fleet","sail"]: return no("invalid-practice-mode")
	_height=height; _options=options.duplicate(true); _waves=Waves.new(); _waves.configure(height)
	return _restart()
func _restart() -> Dictionary:
	var mode: String=_options.get("mode","duel")
	var config := {"referenceHandling":true,"referenceGunnery":true,"seed":1661,"enemyCount":1 if mode=="duel" else 2 if mode=="fleet" else 0,"mode":"terminal","wind":{"direction":{"x":-0.8,"y":-0.6},"speed":14.0},"sampleTerrainHeight":_height,"waveSampler":_waves,"oceanWaves":Descriptors.original_descriptors(),"battleId":"practice-%s-%s-%s" % [mode,OS.get_process_id(),_generation+1]}
	if mode=="sail":
		config.ships=[{"id":"player","name":"定海","kind":"fuchuan","team":"player","position":{"x":0,"z":0},"heading":0},{"id":"merchant","name":"泉州商船","kind":"merchant","team":"neutral","position":{"x":140,"z":100},"heading":0},{"id":"fisher","name":"金门渔舟","kind":"fisherman","team":"neutral","position":{"x":60,"z":-120},"heading":PI/3,"sailDeployment":0.65}]
	var native := Encounter.new(config)
	if not native.last_error.is_empty(): return no(native.last_error)
	if simulation: simulation.set_paused(true)
	simulation=Simulation.new(native); simulation.set_handling_mode(_handling)
	var retained: Dictionary={}
	for reason in ["hidden"]:
		if _pauses.has(reason): retained[reason]=true
	_pauses=retained; _quote.clear(); _notice=""; _generation+=1; _disposed=false; _sync_pause()
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
	if is_paused() or simulation.snapshot().status in ["victory","defeat","surrendered"]: return no("请先继续航行")
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
	if _disposed or not simulation or is_paused(): return 0
	var before: float=simulation.snapshot().time
	simulation.advance(seconds)
	for receipt: Dictionary in simulation.drain_results():
		if not receipt.result.ok: _notice=receipt.result.get("reason","command-rejected")
	var native: Dictionary=simulation.snapshot()
	if native.status in ["victory","defeat","surrendered"]: set_pause("result",true)
	return native.time-before
func snapshot() -> Dictionary:
	if _disposed or not simulation: return {}
	var phase: String = simulation.handling_status().get("phase","idle")
	var assistance_notice: String = {"wind-recovery":"迎风起步辅助：先转出迎风区，再逐渐升帆。A/D 转舵可立即接管。","blocked":"起步辅助已停止；调整航向后重新按 W。"}.get(phase, "")
	return {"naval":simulation.snapshot(),"runtime":{"generation":_generation,"mode":_options.get("mode","duel"),"paused":is_paused(),"pauseReasons":_pauses.keys(),"handlingMode":_handling,"notice":_notice if not _notice.is_empty() else assistance_notice,"surrenderQuote":_quote.duplicate(true)}}
func render_snapshot() -> Dictionary: return simulation.render_snapshot() if not _disposed and simulation else {}
func requires_immediate_actor_presentation() -> bool:
	if _disposed or not simulation: return false
	# Observe without draining: the scene presents original ordered events once.
	for event: Dictionary in simulation._events:
		if event.get("type") == "fire": return true
		if event.get("type") == "hit" and float(event.get("damage",{}).get("crew",0.0)) > 0.0: return true
	return false
func drain_events() -> Array: return simulation.drain_events() if not _disposed and simulation else []
func sample_water_height(x: float,z: float,seconds: float) -> float: return _waves.sample_height(x,z,seconds) if _waves else 0
func dispose() -> void:
	if simulation: simulation.set_paused(true)
	simulation=null; _disposed=true; _quote.clear(); _pauses.clear()
