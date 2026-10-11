extends RefCounted
## Input policy from ManualSailingAssist.ts. Only accepted simulation time counts.
var _stalled := 0.0
var _fresh_forward_required := false
var _recovery: Dictionary = {}
var _status := {"phase":"idle"}

func status() -> Dictionary: return _status.duplicate(true)
func active() -> bool: return not _recovery.is_empty()
func cancel() -> void:
	_recovery.clear(); _stalled = 0.0; _fresh_forward_required = true; _status = {"phase":"idle"}
func release_forward() -> void:
	cancel(); _fresh_forward_required = false
func block(reason: String) -> void:
	cancel(); _status = {"phase":"blocked","reason":reason}
static func _wrap(value: float) -> float: return atan2(sin(value),cos(value))

func advance(seconds: float, ship: Dictionary, wind: Dictionary, input: Dictionary, find_heading: Callable) -> void:
	if not is_finite(seconds) or seconds <= 0: return
	if not input.forward: release_forward()
	if input.turn or input.backward or input.manualTrim or not input.autoTrim: cancel()
	if input.turn: _status = {"phase":"turning"}; return
	if input.backward: _status = {"phase":"braking" if input.sailIntent <= 0.05 else "idle"}; return
	var angle := absf(_wrap(ship.visual.heading-atan2(wind.direction.y,wind.direction.x)))
	if not _recovery.is_empty():
		_recovery.seconds += seconds
		if _recovery.seconds+1e-10 >= (24 if ship.kind == "heavy" else 18): block("recovery-timeout"); return
		if angle > deg_to_rad(50): _recovery.restoring = true
		if _recovery.restoring: _recovery.restoringSeconds += seconds
		if _recovery.restoringSeconds+1e-10 >= 2: cancel(); return
		_status = {"phase":"wind-recovery"}; return
	if _fresh_forward_required: return
	_status = {"phase":"idle"}
	var speed := Vector2(ship.visual.velocity.x,ship.visual.velocity.z).length()
	if input.forward and input.autoTrim and wind.speed > 0 and Vector2(wind.direction.x,wind.direction.y).length() > 0 and speed < 0.5 and angle <= deg_to_rad(50):
		_stalled += seconds
		if _stalled+1e-10 >= 1:
			var result: Dictionary = find_heading.call()
			_stalled = 0; _fresh_forward_required = true
			if not result.get("ok",false): block(result.get("reason","recovery-unavailable")); return
			_recovery = {"heading":result.heading,"seconds":0.0,"restoringSeconds":0.0,"restoring":false}
			_status = {"phase":"wind-recovery"}
	else: _stalled = 0

func controls(ship: Dictionary, input: Dictionary) -> Dictionary:
	if _recovery.is_empty(): return {"turnIntent":input.turnIntent,"sailDeployment":input.sailIntent,"braking":input.backward and input.sailIntent <= 0.05,"recovery":false}
	return {"turnIntent":clampf(_wrap(_recovery.heading-ship.visual.heading)*3,-1,1),"sailDeployment":input.sailIntent*clampf(_recovery.restoringSeconds/2.0,0,1),"braking":false,"recovery":true}
