extends RefCounted
## Camera intent and smoothing only. Native ship snapshots remain read-only.
## Explicit input may settle on a render delta while the simulation is paused;
## automatic position, heading, heave and shake use consumed native time only.
const MIN_RADIUS := 36.0
const MAX_RADIUS := 220.0
const MIN_PITCH := PI / 9.0
const MAX_PITCH := PI * 0.4
const REAR_YAW := -2.27
const CAPTAIN_RADIUS := 68.0
const TACTICAL_RADIUS := 170.0
var _ready := false
var _manual := false
var _tactical := false
var _input_settling := false
var _yaw_input := false
var _pitch_input := false
var _radius_input := false
var _yaw := REAR_YAW
var _target_yaw := REAR_YAW
var _pitch := deg_to_rad(32.0)
var _target_pitch := deg_to_rad(32.0)
var _radius := CAPTAIN_RADIUS
var _target_radius := CAPTAIN_RADIUS
var _zoom := 1.0
var _external_zoom := 1.0
var _heading := 0.0
var _elapsed := 0.0
var _focus := Vector3.ZERO
var _last_anchor := Vector3.ZERO
var _frame: Dictionary = {}

static func _finite(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _number(value: Variant, fallback: float = 0.0) -> float:
	return float(value) if _finite(value) else fallback

static func _angle(value: float) -> float:
	return atan2(sin(value),cos(value))

func _base_radius() -> float:
	return TACTICAL_RADIUS if _tactical else CAPTAIN_RADIUS

func _default_pitch() -> float:
	return deg_to_rad(58.0 if _tactical else 32.0)

func step(ship: Dictionary, seconds: float, settings: Dictionary = {}, tactical: bool = false, zoom: float = 1.0, input_seconds: float = 0.0) -> Dictionary:
	var visual: Dictionary = ship.get("visual",{})
	var point: Dictionary = visual.get("position",{})
	if not _finite(point.get("x")) or not _finite(point.get("y")) or not _finite(point.get("z")):
		return _frame.duplicate()
	var dt := clampf(seconds,0.0,0.25) if is_finite(seconds) else 0.0
	var input_dt := clampf(input_seconds,0.0,0.1) if is_finite(input_seconds) else 0.0
	var reduced := bool(settings.get("reducedMotion",false))
	var follow := bool(settings.get("cameraFollow",true)) or tactical
	var stability := clampf(_number(settings.get("horizonStability",1.0),1.0),0.0,1.0)
	var heave := 0.0 if reduced else maxf(float(point.y),0.0)*lerpf(0.2,0.04,stability)
	var anchor := Vector3(point.x,3.0+heave,point.z)
	var heading := _number(visual.get("heading"),_heading)
	var mode_changed := _tactical != tactical
	_tactical = tactical
	if is_finite(zoom) and zoom > 0.0 and zoom != _external_zoom:
		_external_zoom = zoom
		_zoom = clampf(zoom,MIN_RADIUS/_base_radius(),MAX_RADIUS/_base_radius())
		_target_radius = clampf(_base_radius()*_zoom,MIN_RADIUS,MAX_RADIUS)
		_radius_input = true
	if mode_changed:
		_zoom = clampf(_zoom,MIN_RADIUS/_base_radius(),MAX_RADIUS/_base_radius())
		_target_radius = clampf(_base_radius()*_zoom,MIN_RADIUS,MAX_RADIUS)
		_target_pitch = _default_pitch()
		# A mode snapshot alone cannot invent elapsed time while paused. Explicit
		# recenter/orbit inputs already own their smoothing channels below.
		if dt == 0.0 and not _pitch_input and not _radius_input:
			_pitch = _target_pitch; _radius = _target_radius
	if not _ready or follow:
		_heading = heading
		if not _manual: _target_yaw = _angle(heading+REAR_YAW)
	var desired := anchor
	if not reduced:
		var velocity: Dictionary = visual.get("velocity",{})
		var ahead := Vector3(_number(velocity.get("x")),0,_number(velocity.get("z")))*0.65
		var dimensions: Dictionary = ship.get("dimensions",{})
		desired += ahead.limit_length(clampf(_number(dimensions.get("length"),10.0),1.0,10.0))
	if not _ready:
		_focus = desired
		_yaw = _target_yaw; _pitch = _target_pitch; _radius = _target_radius
		_ready = true
	elif follow:
		if dt > 0.0: _focus = _focus.lerp(desired,1.0-exp(-5.0*dt))
		elif anchor != _last_anchor: _focus += anchor-_last_anchor
	_last_anchor = anchor
	# Wheel, orbit and recenter own separate channels. A paused wheel zoom must
	# not lend its render clock to an unfinished automatic heading turn.
	var follow_dt := dt if follow else 0.0
	var yaw_dt := maxf(follow_dt,maxf(dt,input_dt) if _yaw_input else 0.0)
	var pitch_dt := maxf(follow_dt,maxf(dt,input_dt) if _pitch_input else 0.0)
	var radius_dt := maxf(follow_dt,maxf(dt,input_dt) if _radius_input else 0.0)
	if yaw_dt > 0.0: _yaw = _angle(_yaw+_angle(_target_yaw-_yaw)*(1.0-exp(-(9.0 if _manual or _yaw_input else 3.0)*yaw_dt)))
	if pitch_dt > 0.0: _pitch = lerpf(_pitch,_target_pitch,1.0-exp(-9.0*pitch_dt))
	if radius_dt > 0.0: _radius = lerpf(_radius,_target_radius,1.0-exp(-9.0*radius_dt))
	if absf(_angle(_target_yaw-_yaw)) < 0.00001: _yaw = _target_yaw; _yaw_input = false
	if absf(_pitch-_target_pitch) < 0.00001: _pitch = _target_pitch; _pitch_input = false
	if absf(_radius-_target_radius) < 0.001: _radius = _target_radius; _radius_input = false
	_input_settling = _yaw_input or _pitch_input or _radius_input
	_elapsed = fmod(_elapsed+follow_dt,10000.0)
	var offset := Vector3(cos(_yaw)*cos(_pitch),sin(_pitch),sin(_yaw)*cos(_pitch))*_radius
	var eye := _focus+offset
	var shake := 0.0 if reduced or tactical else clampf(_number(settings.get("cameraShake",0.0)),0.0,1.0)*0.35
	if shake > 0.0: eye += Vector3(sin(_elapsed*13.0),sin(_elapsed*17.0)*0.6,sin(_elapsed*11.0))*shake
	eye.y = maxf(eye.y,4.0)
	var roll := 0.0 if reduced else clampf(_number(visual.get("heel",0.0)),-1.0,1.0)*(1.0-stability)
	var up := Vector3(sin(roll)*cos(_heading),cos(roll),-sin(roll)*sin(_heading)).normalized()
	if not follow and not _frame.is_empty(): up = _frame.up
	_frame = {"position":eye,"target":_focus,"up":up}
	return _frame.duplicate()

func orbit(delta: Vector2) -> bool:
	if not delta.is_finite(): return false
	_manual = true
	_target_yaw = _angle(_target_yaw-clampf(delta.x,-10000.0,10000.0)*0.004)
	_target_pitch = clampf(_target_pitch+clampf(delta.y,-10000.0,10000.0)*0.003,MIN_PITCH,MAX_PITCH)
	_yaw_input = true; _pitch_input = true
	_input_settling = true
	return true

func zoom_by(steps: float) -> bool:
	if not is_finite(steps): return false
	_target_radius = clampf(_target_radius*exp(-clampf(steps,-100.0,100.0)*0.12),MIN_RADIUS,MAX_RADIUS)
	_zoom = _target_radius/_base_radius()
	_radius_input = true
	_input_settling = true
	return true

func recenter() -> void:
	_manual = false
	_zoom = 1.0
	_external_zoom = 1.0
	_target_yaw = _angle(_heading+REAR_YAW)
	_target_pitch = _default_pitch()
	_target_radius = _base_radius()
	_yaw_input = true; _pitch_input = true; _radius_input = true
	_input_settling = true

func reset() -> void:
	_ready = false; _manual = false; _tactical = false; _input_settling = false
	_yaw_input = false; _pitch_input = false; _radius_input = false
	_yaw = REAR_YAW; _target_yaw = REAR_YAW
	_pitch = deg_to_rad(32.0); _target_pitch = _pitch
	_radius = CAPTAIN_RADIUS; _target_radius = CAPTAIN_RADIUS
	_zoom = 1.0; _external_zoom = 1.0; _heading = 0.0; _elapsed = 0.0
	_focus = Vector3.ZERO; _last_anchor = Vector3.ZERO; _frame.clear()

func status() -> Dictionary:
	return {"manual":_manual,"mode":"manual" if _manual else "follow","yaw":_yaw,"targetYaw":_target_yaw,
		"pitch":_pitch,"targetPitch":_target_pitch,"radius":_radius,"targetRadius":_target_radius,"zoom":_zoom,"settling":_input_settling}
