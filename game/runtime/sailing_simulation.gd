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
var _previous: Dictionary = {}
var _current: Dictionary = {}
var _mode := "realistic"
var _manual_active := false
var _owned_helm := false
var _assist := Assist.new()

func _init(native_encounter: RefCounted) -> void:
	encounter = native_encounter; _current = encounter.snapshot(); _previous = _current.duplicate(true); _restore_controls()
static func _ship(snap: Dictionary, id: String) -> Dictionary:
	for ship: Dictionary in snap.get("ships",[]):
		if ship.id == id: return ship
	return {}
func _restore_controls(preserve_sail_intent: bool = false) -> void:
	var player := _ship(_current,_current.get("playerId",""))
	if player.is_empty(): return
	if not preserve_sail_intent: _deployment = player.sailDeployment; _rudder = player.rudder
	_auto_trim = player.autoTrim; _sail_angle = player.sailAngle
func _clear_assistance(clear_held: bool = false) -> void:
	encounter.setManualHandling(_current.playerId,null); _assist.cancel(); _manual_active = false
	if clear_held: _held.clear()
func set_handling_mode(mode: String) -> void:
	if not mode in ["assisted","realistic"] or mode == _mode: return
	var clear_helm := _owned_helm; var restore_sails := _assist.active()
	_clear_assistance(true); _queued.clear(); _mode = mode
	if clear_helm or restore_sails:
		if clear_helm: _rudder = 0
		encounter.command({"type":"controls","rudder":_rudder,"sailDeployment":_deployment,"sailAngle":_sail_angle,"autoTrim":_auto_trim})
	_current = encounter.snapshot(); _previous = _current.duplicate(true); _owned_helm = false; _restore_controls()
func handling_status() -> Dictionary: return _assist.status()
func refresh_snapshot() -> void:
	var old_player := _ship(_current,_current.get("playerId",""))
	var next: Dictionary = encounter.snapshot()
	var player := _ship(next,next.playerId)
	var replaced: bool = next.playerId != _current.playerId
	var changed: bool = not old_player.is_empty() and not player.is_empty() and (old_player.rudder != player.rudder or old_player.sailDeployment != player.sailDeployment or old_player.autoTrim != player.autoTrim or old_player.sailAngle != player.sailAngle)
	var ordered: bool = player.has("navigation") or encounter.hasActiveOrder(next.playerId)
	if replaced or ordered or player.is_empty() or player.get("hull",0) <= 0 or player.get("crew",0) <= 0 or player.get("team") != "player" or changed:
		_clear_assistance(replaced or ordered); _owned_helm = false
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
		_held.erase(code)
		if code in ["KeyW","ArrowUp"] and not _has("KeyW","ArrowUp"): _assist.release_forward(); encounter.setManualHandling(_current.playerId,null)
		return
	if _paused or _held.has(code): return
	if code in ["KeyW","ArrowUp"] and not _has("KeyW","ArrowUp"): _assist.release_forward()
	if code in ["KeyW","KeyS","KeyA","KeyD","ArrowUp","ArrowDown","ArrowLeft","ArrowRight","BracketLeft","BracketRight"]:
		_cancel_navigation(); _manual_active = true
	_held[code] = true
	if code in ["KeyA","KeyD","ArrowLeft","ArrowRight"]: _owned_helm = true
	if code in ["KeyA","KeyD","KeyS","ArrowLeft","ArrowRight","ArrowDown","BracketLeft","BracketRight"]:
		_assist.cancel(); encounter.setManualHandling(_current.playerId,null)
func action(command: Dictionary) -> void:
	if _paused: return
	var current_controls: bool = _valid_controls(command) and (not command.get("shipId") or command.shipId == _current.playerId)
	if current_controls:
		_clear_assistance(); _owned_helm = false
		if command.rudder != _rudder or command.sailDeployment != _deployment or command.has("sailAngle") and command.sailAngle != _sail_angle or command.has("autoTrim") and command.autoTrim != _auto_trim: _cancel_navigation()
	_queued.append(command.duplicate(true))
func set_sails(value: float) -> void:
	if _paused or not is_finite(value) or clampf(value,0,1) == _deployment: return
	_cancel_navigation(); _assist.cancel(); _manual_active = true; encounter.setManualHandling(_current.playerId,null); _deployment = clampf(value,0,1)
func toggle_trim() -> void:
	if _paused: return
	_cancel_navigation(); _assist.cancel(); _manual_active = true; encounter.setManualHandling(_current.playerId,null); _auto_trim = not _auto_trim
func set_paused(value: bool) -> void:
	_paused = value; _accumulator = 0; _previous = _current.duplicate(true); _clear_assistance(true); _queued.clear()
func has_pending_input() -> bool: return not _queued.is_empty() or not _held.is_empty()
func advance(frame_seconds: float) -> void:
	if _paused or not is_finite(frame_seconds) or frame_seconds <= 0: return
	_accumulator = minf(0.1,_accumulator+minf(frame_seconds,0.1))
	while _accumulator+1e-10 >= STEP:
		if _mode == "assisted" and _manual_active:
			var fresh: Dictionary = encounter.snapshot(); var fresh_player := _ship(fresh,fresh.playerId)
			if fresh.playerId != _current.playerId or fresh_player.is_empty() or fresh_player.has("navigation") or encounter.hasActiveOrder(fresh.playerId) or fresh_player.hull <= 0 or fresh_player.crew <= 0 or fresh_player.team != "player": refresh_snapshot()
		var turn := float(int(_has("KeyD","ArrowRight"))-int(_has("KeyA","ArrowLeft")))
		_rudder += (turn-_rudder)*(1-exp(-(10 if _mode == "assisted" else 8)*STEP))
		if absf(_rudder) < 1e-10: _rudder = 0
		var sails := int(_has("KeyW","ArrowUp"))-int(_has("KeyS","ArrowDown"))
		_deployment = clampf(_deployment+sails*STEP*((0.75 if sails > 0 else 0.9) if _mode == "assisted" else 0.35),0,1)
		var trim := int(_held.has("BracketRight"))-int(_held.has("BracketLeft"))
		if trim: _auto_trim = false; _sail_angle = clampf(_sail_angle+trim*STEP*0.7,-PI/2,PI/2)
		var input := {"forward":_has("KeyW","ArrowUp"),"backward":_has("KeyS","ArrowDown"),"turn":turn,"turnIntent":_rudder if turn else 0.0,"sailIntent":_deployment,"autoTrim":_auto_trim,"manualTrim":trim != 0}
		var player := _ship(_current,_current.playerId)
		if not player.is_empty() and not player.has("navigation") and not encounter.hasActiveOrder(_current.playerId):
			var assisted := _mode == "assisted" and _manual_active
			var control := _assist.controls(player,input) if assisted else {"turnIntent":input.turnIntent,"sailDeployment":_deployment,"recovery":false,"braking":false}
			var result: Dictionary = encounter.command({"type":"controls","rudder":control.turnIntent if control.recovery else _rudder,"sailDeployment":control.sailDeployment,"sailAngle":_sail_angle,"autoTrim":_auto_trim})
			if result.ok and assisted:
				var applied: Dictionary = encounter.setManualHandling(_current.playerId,{"mode":"assisted","turnIntent":control.turnIntent,"sailIntent":_deployment,"braking":control.braking,"recovery":control.recovery})
				if not applied.ok: _clear_assistance(true); _assist.block(applied.get("reason","Ship not authorized"))
			elif not result.ok: _clear_assistance(true); _restore_controls()
		for queued: Dictionary in _queued: _results.append({"command":queued,"result":encounter.command(queued)})
		_queued.clear(); _previous = _current.duplicate(true); encounter.step(STEP); _current = encounter.snapshot()
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
