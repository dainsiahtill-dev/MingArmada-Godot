extends RefCounted
## Input/interpolation adapter. Encounter remains the authority for motion/combat.
const Assist = preload("res://game/runtime/manual_sailing_assist.gd")
const STEP := 1.0/60.0
var encounter: RefCounted
var _deployment := 1.0
var _auto_trim := true
var _sail_angle := PI/4
var _held: Dictionary = {}
var _queued: Array = []
var _events: Array = []
var _results: Array = []
var _accumulator := 0.0
var _paused := false
var _rudder := 0.0
var _rudder_intent := 0.0
var _previous: Dictionary = {}
var _current: Dictionary = {}
var _mode := "realistic"
var _manual_active := false
var _owned_helm := false
var _assist := Assist.new()
var _course: Dictionary = {}
var _sailing_allowed := true

func _init(native_encounter: RefCounted) -> void:
	encounter = native_encounter; _current = encounter.snapshot(); _previous = _current.duplicate(true); _restore_controls()
static func _ship(snap: Dictionary, id: String) -> Dictionary:
	for ship: Dictionary in snap.get("ships",[]):
		if ship.id == id: return ship
	return {}
func _restore_controls(preserve_sail_intent: bool = false) -> void:
	var player := _ship(_current,_current.get("playerId",""))
	if player.is_empty(): return
	if not preserve_sail_intent: _deployment = player.sailDeployment; _rudder = player.rudder; _rudder_intent = player.rudder
	_auto_trim = player.autoTrim; _sail_angle = player.sailAngle
func _clear_assistance(clear_held: bool = false, keep_course: bool = false) -> void:
	encounter.setManualHandling(_current.playerId,null); _assist.cancel(); _manual_active = false
	if not keep_course: _course.clear()
	if clear_held: _held.clear()
func set_sailing_allowed(value: bool) -> void:
	if value == _sailing_allowed: return
	_sailing_allowed = value
	if not value: _clear_assistance(true); _queued.clear(); _owned_helm = false
func _permission(replace_navigation: bool = false) -> Dictionary:
	if _paused: return {"ok":false,"reason":"请先继续航行"}
	if not _sailing_allowed: return {"ok":false,"reason":"请先离港，再选择航向"}
	return encounter.manual_control_permission(encounter.player_id, replace_navigation)
func set_course(point: Dictionary) -> Dictionary:
	if not _finite(point.get("x")) or not _finite(point.get("z")): return {"ok":false,"reason":"请选择有效的海面位置"}
	var authority: Dictionary = encounter.snapshot()
	var player: Dictionary = _ship(authority, authority.playerId)
	if player.is_empty(): return {"ok":false,"reason":"没有可操纵的船"}
	var direction := Vector2(float(point.x)-float(player.visual.position.x),float(point.z)-float(player.visual.position.z))
	if not is_finite(direction.x) or not is_finite(direction.y) or direction.length_squared() < 0.0001: return {"ok":false,"reason":"请在船身以外选择航向"}
	var permitted: Dictionary = _permission(true)
	if not permitted.ok: return permitted
	var terrain: Callable = encounter.config.get("sampleTerrainHeight",Callable())
	if terrain.is_valid():
		var height: Variant = terrain.call(point.x,point.z)
		if not _finite(height) or float(height) >= float(encounter.config.get("seaLevel",0)): return {"ok":false,"reason":"请点击海面选择航向"}
	var cancelled: Dictionary = encounter.navigate(authority.playerId,null)
	if not cancelled.ok: return cancelled
	refresh_snapshot()
	_held.clear(); _queued.clear(); _assist.cancel(); _owned_helm = true; _manual_active = true
	_rudder_intent = 0.0
	_deployment = maxf(_deployment,0.85); _auto_trim = true
	var heading: float = atan2(float(point.z)-float(player.visual.position.z),float(point.x)-float(player.visual.position.x))
	_course = {"heading":heading,"playerId":authority.playerId,"battleId":authority.battleId}
	return {"ok":true,"targetHeading":heading}
func stop_course() -> Dictionary:
	var permitted: Dictionary = _permission(true)
	if not permitted.ok: return permitted
	var cancelled: Dictionary = encounter.navigate(encounter.player_id,null)
	if not cancelled.ok: return cancelled
	refresh_snapshot(); _course.clear(); _held.clear(); _queued.clear(); _assist.cancel()
	_manual_active = true; _owned_helm = true; _deployment = 0.0; _rudder_intent = 0.0
	return {"ok":true}
func set_handling_mode(mode: String) -> void:
	if not mode in ["assisted","realistic"] or mode == _mode: return
	var clear_helm := _owned_helm; var restore_sails := _assist.active()
	_clear_assistance(true); _queued.clear(); _mode = mode
	if clear_helm or restore_sails:
		if clear_helm: _rudder = 0
		encounter.command({"type":"controls","rudder":_rudder,"sailDeployment":_deployment,"sailAngle":_sail_angle,"autoTrim":_auto_trim})
	_current = encounter.snapshot(); _previous = _current.duplicate(true); _owned_helm = false; _restore_controls()
func handling_status() -> Dictionary:
	var result: Dictionary = _assist.status()
	if not _course.is_empty(): result.targetHeading = _course.heading
	return result
func refresh_snapshot() -> void:
	var old_player := _ship(_current,_current.get("playerId",""))
	var next: Dictionary = encounter.snapshot()
	var player := _ship(next,next.playerId)
	var replaced: bool = next.playerId != _current.playerId or next.battleId != _current.get("battleId")
	var changed: bool = not old_player.is_empty() and not player.is_empty() and (old_player.rudder != player.rudder or old_player.sailDeployment != player.sailDeployment or old_player.autoTrim != player.autoTrim or old_player.sailAngle != player.sailAngle)
	var ordered: bool = player.has("navigation") or encounter.hasActiveOrder(next.playerId)
	var permitted: bool = encounter.manual_control_permission(next.playerId, true).ok and _sailing_allowed
	if replaced or ordered or not permitted or player.is_empty() or player.get("hull",0) <= 0 or player.get("crew",0) <= 0 or player.get("team") != "player" or changed:
		_clear_assistance(replaced or ordered); _owned_helm = false
		if replaced: _queued.clear()
	var preserve: bool = _mode == "assisted" and _manual_active and not changed and not replaced
	_current = next; _previous = _current.duplicate(true); _restore_controls(preserve); _events.append_array(encounter.drainEvents())
func _has(a: String, b: String) -> bool: return _held.has(a) or _held.has(b)
func _cancel_navigation() -> void:
	encounter.navigate(_current.playerId,null); refresh_snapshot()
static func _finite(value) -> bool: return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value))
static func _valid_controls(command: Dictionary) -> bool:
	return command.get("type") == "controls" and _finite(command.get("rudder")) and absf(command.rudder) <= 1 and _finite(command.get("sailDeployment")) and command.sailDeployment >= 0 and command.sailDeployment <= 1 and (not command.has("sailAngle") or _finite(command.sailAngle) and absf(command.sailAngle) <= PI/2) and (not command.has("autoTrim") or command.autoTrim is bool)
func pending_controls(ship_id: String) -> Dictionary:
	for index in range(_queued.size()-1,-1,-1):
		var command: Dictionary = _queued[index]
		if command.get("shipId",_current.playerId) == ship_id and _valid_controls(command): return command.duplicate(true)
	return {}
func set_held(code: String, down: bool) -> void:
	if not down:
		var was_held: bool = _held.has(code)
		_held.erase(code)
		if was_held and code in ["KeyA","KeyD","ArrowLeft","ArrowRight"]: _rudder_intent = 0.0
		if code in ["KeyW","ArrowUp"] and not _has("KeyW","ArrowUp"): _assist.release_forward(); encounter.setManualHandling(_current.playerId,null)
		return
	if _paused or not _sailing_allowed or _held.has(code): return
	if code in ["KeyW","ArrowUp"] and not _has("KeyW","ArrowUp"): _assist.release_forward()
	if code in ["KeyW","KeyS","KeyA","KeyD","ArrowUp","ArrowDown","ArrowLeft","ArrowRight","BracketLeft","BracketRight"]:
		_course.clear(); _cancel_navigation(); _manual_active = true; _rudder_intent = 0.0
	_held[code] = true
	if code in ["KeyA","KeyD","ArrowLeft","ArrowRight"]: _owned_helm = true
	if code in ["KeyA","KeyD","KeyS","ArrowLeft","ArrowRight","ArrowDown","BracketLeft","BracketRight"]:
		_assist.cancel(); encounter.setManualHandling(_current.playerId,null)
func action(command: Dictionary) -> void:
	if _paused: return
	var owned: Dictionary = command.duplicate(true)
	if owned.get("type") in ["controls","fire","select-ammo"] and not owned.has("shipId"): owned.shipId = _current.playerId
	_queued.append(owned)
func _consume_actions() -> bool:
	var adopted_rudder := false
	for queued: Dictionary in _queued:
		var before: Dictionary = encounter.snapshot()
		var player: Dictionary = _ship(before,before.playerId)
		var receipt: Dictionary = encounter.command(queued)
		_results.append({"command":queued,"result":receipt})
		if not receipt.ok or not _valid_controls(queued) or queued.get("shipId",before.playerId) != before.playerId or player.is_empty(): continue
		var changed: bool = queued.rudder != player.rudder or queued.sailDeployment != player.sailDeployment or queued.has("sailAngle") and queued.sailAngle != player.sailAngle or queued.has("autoTrim") and queued.autoTrim != player.autoTrim
		if not changed: continue
		if not _course.is_empty() and (queued.rudder != player.rudder or queued.sailDeployment <= 0.05): _course.clear()
		encounter.navigate(before.playerId,null)
		_rudder = queued.rudder; _rudder_intent = queued.rudder; _deployment = queued.sailDeployment
		_auto_trim = queued.get("autoTrim",player.autoTrim); _sail_angle = queued.get("sailAngle",player.sailAngle)
		_manual_active = _sailing_allowed and encounter.manual_control_permission(before.playerId).ok
		_owned_helm = true; _assist.cancel(); adopted_rudder = true
	_queued.clear()
	return adopted_rudder
func set_sails(value: float) -> void:
	if _paused or not _sailing_allowed or not is_finite(value) or clampf(value,0,1) == _deployment: return
	_cancel_navigation(); _assist.cancel(); _manual_active = true; encounter.setManualHandling(_current.playerId,null); _deployment = clampf(value,0,1)
func toggle_trim() -> void:
	if _paused or not _sailing_allowed: return
	_cancel_navigation(); _assist.cancel(); _manual_active = true; encounter.setManualHandling(_current.playerId,null); _auto_trim = not _auto_trim
func set_paused(value: bool) -> void:
	if value == _paused: return
	# Pausing clears transient keys/actions and native assistance, not an already
	# accepted sail setting's owner. Without this, non-course input silently
	# resumes realistic forces and stalls in headwind despite retaining its sails.
	var retain_manual: bool = _manual_active and _mode == "assisted"
	_paused = value; _accumulator = 0; _previous = _current.duplicate(true); _clear_assistance(true,true); _queued.clear()
	_manual_active = retain_manual and _sailing_allowed and encounter.player_id == _current.playerId and encounter.battle_id == _current.battleId and encounter.manual_control_permission(encounter.player_id).ok
	if not value and not _course.is_empty():
		if _permission(true).ok and _course.playerId == encounter.player_id and _course.battleId == encounter.battle_id: _manual_active = true
		else: _course.clear()
func has_pending_input() -> bool: return not _queued.is_empty() or not _held.is_empty() or not _course.is_empty()
func advance(frame_seconds: float) -> void:
	if _paused or not is_finite(frame_seconds) or frame_seconds <= 0: return
	_accumulator = minf(0.1,_accumulator+minf(frame_seconds,0.1))
	while _accumulator+1e-10 >= STEP:
		var adopted_rudder: bool = _consume_actions()
		if _mode == "assisted" and _manual_active:
			var fresh: Dictionary = encounter.snapshot(); var fresh_player := _ship(fresh,fresh.playerId)
			if fresh.playerId != _current.playerId or fresh.battleId != _current.battleId or fresh_player.is_empty() or fresh_player.has("navigation") or encounter.hasActiveOrder(fresh.playerId) or fresh_player.hull <= 0 or fresh_player.crew <= 0 or fresh_player.team != "player" or not encounter.manual_control_permission(fresh.playerId).ok: refresh_snapshot()
		var turn := float(int(_has("KeyD","ArrowRight"))-int(_has("KeyA","ArrowLeft"))) if _has("KeyD","ArrowRight") or _has("KeyA","ArrowLeft") else _rudder_intent
		if not _course.is_empty():
			var authority: Dictionary = encounter.snapshot()
			var controlled: Dictionary = _ship(authority,authority.playerId)
			if not controlled.is_empty():
				var heading_error: float = atan2(sin(_course.heading-controlled.visual.heading),cos(_course.heading-controlled.visual.heading))
				turn = clampf(heading_error*2.5,-1.0,1.0)
		if not adopted_rudder: _rudder += (turn-_rudder)*(1-exp(-(10 if _mode == "assisted" else 8)*STEP))
		if absf(_rudder) < 1e-10: _rudder = 0
		var sails := int(_has("KeyW","ArrowUp"))-int(_has("KeyS","ArrowDown"))
		_deployment = clampf(_deployment+sails*STEP*((0.75 if sails > 0 else 0.9) if _mode == "assisted" else 0.35),0,1)
		var trim := int(_held.has("BracketRight"))-int(_held.has("BracketLeft"))
		if trim: _auto_trim = false; _sail_angle = clampf(_sail_angle+trim*STEP*0.7,-PI/2,PI/2)
		var input := {"forward":_has("KeyW","ArrowUp"),"backward":_has("KeyS","ArrowDown"),"turn":turn,"turnIntent":_rudder if turn or adopted_rudder else 0.0,"sailIntent":_deployment,"autoTrim":_auto_trim,"manualTrim":trim != 0,"casual":_mode == "assisted"}
		var player := _ship(_current,_current.playerId)
		if not player.is_empty() and not player.has("navigation") and not encounter.hasActiveOrder(_current.playerId):
			var assisted := _mode == "assisted" and _manual_active
			var control := _assist.controls(player,input) if assisted else {"turnIntent":input.turnIntent,"sailDeployment":_deployment,"recovery":false,"braking":false}
			var result: Dictionary = encounter.command({"type":"controls","rudder":control.turnIntent if control.recovery else _rudder,"sailDeployment":control.sailDeployment,"sailAngle":_sail_angle,"autoTrim":_auto_trim})
			if result.ok and assisted:
				var applied: Dictionary = encounter.setManualHandling(_current.playerId,{"mode":"assisted","turnIntent":control.turnIntent,"sailIntent":_deployment,"braking":control.braking,"recovery":control.recovery,"casual":true})
				if not applied.ok: _clear_assistance(true); _assist.block(applied.get("reason","Ship not authorized"))
			elif not result.ok: _clear_assistance(true); _restore_controls()
		_previous = _current.duplicate(true); encounter.step(STEP); _current = encounter.snapshot()
		var consumed: float = (_current.tick-_previous.tick)*STEP
		var actual := _ship(_current,_current.playerId)
		if _mode == "assisted" and _manual_active and not actual.is_empty() and consumed > 0: _assist.advance(consumed,actual,_current.wind,input,func() -> Dictionary: return encounter.findManualRecoveryHeading(_current.playerId))
		if actual.has("navigation") or encounter.hasActiveOrder(_current.playerId): _restore_controls()
		_events.append_array(encounter.drainEvents()); _accumulator = maxf(0,_accumulator-STEP)
func snapshot() -> Dictionary: return _current.duplicate(true)
func render_snapshot() -> Dictionary:
	var alpha := _accumulator/STEP; var next := _current.duplicate(true)
	next.time = _previous.time+(next.time-_previous.time)*alpha
	for ship: Dictionary in next.ships:
		var before := _ship(_previous,ship.id)
		if before.is_empty(): continue
		var a: Dictionary = before.visual; var b: Dictionary = ship.visual
		b.heading = a.heading+atan2(sin(b.heading-a.heading),cos(b.heading-a.heading))*alpha
		for axis in ["x","y","z"]: b.position[axis] = a.position[axis]+(b.position[axis]-a.position[axis])*alpha
		b.pitch = a.pitch+(b.pitch-a.pitch)*alpha; b.heel = a.heel+(b.heel-a.heel)*alpha
	return next
func drain_events() -> Array:
	var events := _events; _events = []; return events
func drain_results() -> Array:
	var results := _results; _results = []; return results
