extends SceneTree
## Pure camera output from real native ship snapshots. Root owns Godot execution.
const CAMERA_PATH := "res://game/presentation/world/ship_camera_controller.gd"
const Encounter = preload("res://modules/naval_simulation/encounter.gd")
const STEP := 1.0 / 60.0
var assertions := 0
var failures := 0
var _camera_script: Script

func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		printerr("FAIL camera: ", detail)

func _native(position: Vector2 = Vector2(100.0,-30.0), heading: float = 0.0, speed: float = 0.0) -> RefCounted:
	var native := Encounter.new({"mode":"continuous", "playerId":"player", "controllableShipIds":["player"],
		"oceanWaves":[], "wind":{"direction":{"x":1.0,"y":0.0},"speed":0.0},
		"ships":[{"id":"player", "kind":"fuchuan", "team":"player", "heading":heading, "speed":speed,
			"sailDeployment":0.0, "position":{"x":position.x,"z":position.y}}]})
	check(native.last_error.is_empty(), "actual Encounter configures camera fixture")
	return native

func _ship(position: Vector2 = Vector2(100.0,-30.0), heading: float = 0.0, speed: float = 0.0) -> Dictionary:
	return _native(position, heading, speed).snapshot().ships[0]

func _rig() -> RefCounted: return _camera_script.new()

func _step(rig: RefCounted, ship: Dictionary, seconds: float = STEP, settings: Dictionary = {}, tactical: bool = false, zoom: float = 1.0) -> Dictionary:
	var value: Variant = rig.call("step", ship, seconds, settings, tactical, zoom)
	return value if value is Dictionary else {}

func _settle(rig: RefCounted, ship: Dictionary, settings: Dictionary = {}, tactical: bool = false, ticks: int = 120) -> Dictionary:
	var result: Dictionary = {}
	for tick in ticks: result = _step(rig, ship, STEP, settings, tactical)
	return result

func _state(rig: RefCounted) -> Dictionary:
	var value: Variant = rig.call("status")
	return value if value is Dictionary else {}

func _valid(frame: Dictionary) -> bool:
	return frame.get("position") is Vector3 and frame.get("target") is Vector3 and frame.get("up") is Vector3 and frame.position.is_finite() and frame.target.is_finite() and frame.up.is_finite() and frame.position.y >= 4.0 and absf(frame.up.length()-1.0) < 1e-5

func _bounded(state: Dictionary) -> bool:
	return state.has_all(["manual","yaw","pitch","radius","targetRadius"]) and state.manual is bool and is_finite(float(state.yaw)) and is_finite(float(state.pitch)) and is_finite(float(state.radius)) and is_finite(float(state.targetRadius)) and float(state.pitch) >= deg_to_rad(20.0)-1e-6 and float(state.pitch) <= deg_to_rad(72.0)+1e-6 and float(state.radius) >= 36.0-1e-6 and float(state.radius) <= 220.0+1e-6 and float(state.targetRadius) >= 36.0-1e-6 and float(state.targetRadius) <= 220.0+1e-6

func _angle_delta(a: float, b: float) -> float: return atan2(sin(a-b),cos(a-b))

func _follow_and_authority() -> void:
	var native := _native()
	var packet: Dictionary = native.snapshot()
	var ship: Dictionary = packet.ships[0]
	var untouched := ship.duplicate(true)
	var rig := _rig()
	var frame := _step(rig, ship)
	check(_valid(frame) and _bounded(_state(rig)), "default camera yields finite bounded frame above sea")
	if not _valid(frame): return
	var forward := Vector3(cos(ship.visual.heading),0,sin(ship.visual.heading))
	var side := Vector3(-forward.z,0,forward.x)
	var offset: Vector3 = frame.position-frame.target
	var horizontal := Vector3(offset.x,0,offset.z)
	check(horizontal.dot(forward) < -horizontal.length()*0.25 and absf(horizontal.dot(side)) > horizontal.length()*0.2,
		"default view follows from an oblique rear quarter")
	var moving := _ship(Vector2(100,-30),0.0,12.0)
	var moving_frame := _step(_rig(), moving)
	check(_valid(moving_frame), "moving native fixture keeps valid camera output")
	if _valid(moving_frame):
		var ahead: float = moving_frame.target.x-float(moving.visual.position.x)
		check(ahead > 0.0 and ahead <= float(moving.dimensions.length), "forward lookahead is useful and bounded by a ship length")
	check(ship == untouched and native.snapshot() == packet, "camera never mutates caller snapshot or native authority")
	var shifted := _ship(Vector2(130,-30))
	var smooth := _step(rig, shifted)
	check(_valid(smooth) and smooth.position.distance_to(frame.position) > 0.0 and smooth.position.distance_to(frame.position) < 30.0,
		"positive render delta smoothly follows a position change")

func _pause_and_follow_gate() -> void:
	var rig := _rig()
	var ship := _ship()
	var first := _step(rig, ship)
	check(_step(rig, ship, 0.0) == first, "unchanged zero-delta snapshot returns exactly the same camera frame")
	var shifted := _ship(Vector2(180,-90))
	var paused := _step(rig, shifted, 0.0)
	check(_valid(paused) and paused.position.is_equal_approx(first.position+Vector3(80,0,-60)) and paused.target.is_equal_approx(first.target+Vector3(80,0,-60)),
		"zero-delta external position change follows immediately without a new clock")
	var locked := _rig()
	var settings := {"cameraFollow":false,"cameraShake":0.0}
	var fixed := _step(locked, ship, STEP, settings)
	var moved := _ship(Vector2(450,220),2.7,8.0)
	var still := _settle(locked, moved, settings)
	check(_valid(still) and still.position == fixed.position, "cameraFollow false freezes camera position despite ship movement and heading")
	var tactical := _settle(locked, moved, settings, true)
	check(_valid(tactical) and tactical.position.distance_to(fixed.position) > 100.0 and Vector2(tactical.target.x-moved.visual.position.x,tactical.target.z-moved.visual.position.z).length() <= float(moved.dimensions.length),
		"tactical view continues following while ordinary follow is disabled")

func _independent_camera_clocks() -> void:
	var ship := _ship()
	var turned := _ship(Vector2(100,-30),1.2)
	var paused := _rig()
	_step(paused,ship)
	_step(paused,turned)
	var lag := _state(paused)
	check(absf(_angle_delta(float(lag.targetYaw),float(lag.yaw))) > 0.5,
		"pause fixture retains an unfinished automatic heading turn")
	check(paused.call("zoom_by",1.0), "paused wheel supplies an explicit zoom intent")
	var wheel_zoom: float = _state(paused).zoom
	var result: Dictionary = {}
	for tick in 6:
		result = paused.call("step",turned,0.0,{},false,wheel_zoom,0.1)
	check(_valid(result) and float(_state(paused).radius) < float(lag.radius),
		"render input time settles explicit zoom while native time remains paused")
	check(absf(_angle_delta(float(_state(paused).yaw),float(lag.yaw))) < 1e-6,
		"paused wheel input clock cannot advance unfinished automatic heading follow")

	var locked := _rig()
	_step(locked,ship)
	var turning := _step(locked,turned)
	check(absf(_angle_delta(float(_state(locked).targetYaw),float(_state(locked).yaw))) > 0.5,
		"follow-toggle fixture catches automatic turn before it settles")
	var stopped := _step(locked,turned,0.2,{"cameraFollow":false,"cameraShake":0.0})
	check(_valid(stopped) and stopped.position == turning.position,
		"disabling follow immediately freezes eye position during an unfinished automatic turn")

	var shaking := _rig()
	var active_settings := {"cameraFollow":true,"cameraShake":1.0}
	var initial := _step(shaking,ship,STEP,active_settings)
	var moving_eye := _step(shaking,ship,0.2,active_settings)
	check(_valid(moving_eye) and moving_eye.position.distance_to(initial.position) > 0.01,
		"follow-toggle fixture contains visible native-clock camera shake")
	var frozen_settings := {"cameraFollow":false,"cameraShake":1.0}
	var frozen: Dictionary = {}
	for tick in 30: frozen = _step(shaking,ship,STEP,frozen_settings)
	check(_valid(frozen) and frozen.position == moving_eye.position,
		"native time may continue after follow is disabled without moving the frozen eye through shake")

func _orbit_and_recenter() -> void:
	var rig := _rig()
	var ship := _ship()
	_step(rig, ship)
	check(rig.call("orbit",Vector2(80,-24)), "finite RMB orbit intent is accepted")
	_settle(rig, ship)
	var manual := _state(rig)
	check(_bounded(manual) and manual.manual, "orbit creates a bounded manual camera")
	var world_yaw: float = manual.get("yaw",0.0)
	for heading: float in [2.5,-2.8,1.3]: _settle(rig,_ship(Vector2(100,-30),heading))
	check(_state(rig).manual and absf(_angle_delta(float(_state(rig).yaw),world_yaw)) < 1e-6,
		"manual orbit preserves world yaw through large ship heading changes")
	var turned := _ship(Vector2(100,-30),1.3)
	rig.call("recenter")
	var centered := _settle(rig, turned)
	check(_valid(centered) and not _state(rig).manual, "F recenter restores automatic heading follow")
	var reference := _rig()
	_settle(reference, turned)
	check(absf(_angle_delta(float(_state(rig).yaw),float(_state(reference).yaw))) < 0.02,
		"recenter converges to the same native heading-follow yaw")
	var before: float = _state(rig).yaw
	_settle(rig,_ship(Vector2(100,-30),1.6))
	check(absf(_angle_delta(float(_state(rig).yaw),before)-0.3) < 0.03, "automatic yaw follows later ship turns after recenter")
	var wrapped := _rig()
	_step(wrapped,_ship(Vector2(100,-30),PI-0.02))
	var start_yaw: float = _state(wrapped).yaw
	var near_wrap := _step(wrapped,_ship(Vector2(100,-30),-PI+0.02))
	check(_valid(near_wrap) and absf(_angle_delta(float(_state(wrapped).yaw),start_yaw)) < 0.06,
		"automatic follow takes the shortest yaw path across plus/minus PI")

func _zoom_and_limits() -> void:
	var rig := _rig()
	var ship := _ship()
	_step(rig, ship)
	# Move away from the lower bound before checking smooth inward zoom.
	rig.call("zoom_by",-3.0)
	_settle(rig, ship)
	var before := _state(rig)
	check(rig.call("zoom_by",1.0), "finite wheel input is accepted")
	var target := _state(rig)
	var expected := clampf(float(before.targetRadius)*exp(-0.12),36.0,220.0)
	check(absf(float(target.targetRadius)-expected) < 1e-5, "one wheel step changes target radius by exp(-0.12)")
	_step(rig, ship)
	var eased := _state(rig)
	check(float(eased.radius) <= float(before.radius) and float(eased.radius) >= expected and absf(float(eased.radius)-expected) > 1e-5,
		"wheel zoom eases current radius toward its target")
	_settle(rig, ship)
	check(absf(float(_state(rig).radius)-expected) < 0.1, "zoom converges without fixed-step intent overwrite")
	check(rig.call("zoom_by",-1e12), "huge finite wheel-out input is safely clamped")
	var far := _settle(rig, ship)
	check(_valid(far) and _bounded(_state(rig)) and absf(float(_state(rig).targetRadius)-220.0) < 1e-5, "huge wheel-out cannot exceed 220m")
	check(rig.call("zoom_by",1e12), "huge finite wheel-in input is safely clamped")
	var near := _settle(rig, ship)
	check(_valid(near) and _bounded(_state(rig)) and absf(float(_state(rig).targetRadius)-36.0) < 1e-5, "huge wheel-in cannot pass 36m")
	for delta: Vector2 in [Vector2(1e12,1e12),Vector2(-1e12,-1e12)]:
		check(rig.call("orbit",delta), "huge finite orbit is bounded instead of producing nonfinite angles")
		check(_valid(_settle(rig,ship)) and _bounded(_state(rig)), "orbit pitch stays within 20–72 degrees")
	var below := ship.duplicate(true)
	below.visual.position.y = -100.0
	check(_valid(_step(rig,below,0.0)), "camera height stays above sea even for an externally submerged snapshot")

func _reduced_and_invalid() -> void:
	var ship := _ship()
	var rig := _rig()
	var settings := {"reducedMotion":true,"cameraShake":1.0,"horizonStability":0.0}
	var frame := _step(rig,ship,STEP,settings)
	var rolling := ship.duplicate(true)
	rolling.visual.heel = 0.8
	rolling.visual.pitch = -0.5
	var no_roll := _settle(rig,rolling,settings)
	check(_valid(no_roll) and no_roll.up.is_equal_approx(Vector3.UP) and no_roll.position.is_equal_approx(frame.position),
		"reduced motion removes hull roll and camera shake")
	for delta: Vector2 in [Vector2(NAN,0),Vector2(0,INF)]:
		var before := _state(rig)
		check(not rig.call("orbit",delta) and _state(rig) == before, "nonfinite orbit is rejected without state mutation")
	for steps: float in [NAN,INF,-INF]:
		var before := _state(rig)
		check(not rig.call("zoom_by",steps) and _state(rig) == before, "nonfinite wheel input is rejected without state mutation")
	for seconds: float in [NAN,INF,-1.0,1e12]:
		check(_valid(_step(rig,ship,seconds,settings)) and _bounded(_state(rig)), "invalid/huge elapsed input keeps finite bounded camera output")
	var bad := ship.duplicate(true)
	bad.visual.position.x = NAN
	check(_valid(_step(rig,bad)), "nonfinite native position cannot poison existing camera frame")
	check(_valid(_step(rig,ship,STEP,{},false,INF)) and _bounded(_state(rig)), "nonfinite external zoom cannot poison camera state")
	rig.call("reset")
	var fresh := _rig()
	check(_step(rig,ship) == _step(fresh,ship) and _state(rig) == _state(fresh), "reset restores a fresh deterministic camera")

func _finish() -> void:
	print("SHIP_CAMERA_CONTROLLER_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)

func _initialize() -> void:
	var exists := ResourceLoader.exists(CAMERA_PATH)
	check(exists, "new pure ship camera controller exists")
	if not exists: _finish(); return
	_camera_script = load(CAMERA_PATH) as Script
	check(_camera_script != null and _camera_script.can_instantiate() and _camera_script.get_instance_base_type() == "RefCounted", "controller is a constructible pure RefCounted")
	if _camera_script == null or not _camera_script.can_instantiate() or _camera_script.get_instance_base_type() != "RefCounted": _finish(); return
	var probe := _rig()
	var ready := true
	for method: String in ["step","orbit","zoom_by","recenter","reset","status"]:
		var available := probe.has_method(method)
		check(available, "camera API is available: " + method)
		ready = ready and available
	if ready:
		var initial := _step(probe,_ship())
		var valid_shape := _valid(initial) and _bounded(_state(probe))
		check(valid_shape, "step/status publish the complete finite camera contract")
		ready = ready and valid_shape
	if ready:
		_follow_and_authority()
		_pause_and_follow_gate()
		_independent_camera_clocks()
		_orbit_and_recenter()
		_zoom_and_limits()
		_reduced_and_invalid()
	_finish()
