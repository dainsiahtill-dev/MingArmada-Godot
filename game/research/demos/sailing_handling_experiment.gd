extends Node3D
## Isolated control experiment: production authority, ship and camera, diagnostic flat water.
## The host is the only clock owner. No career, persistence, network or duplicate force model.
const Encounter = preload("res://modules/naval_simulation/encounter.gd")
const Simulation = preload("res://game/runtime/sailing_simulation.gd")
const Ship = preload("res://game/presentation/ships/ship_view.gd")
const CameraRig = preload("res://game/presentation/world/ship_camera_controller.gd")
const STEP := 1.0/60.0
const KINDS := ["fuchuan","fisherman","patrol","merchant","voc","heavy"]
const SCENARIOS := ["pause-resume","headwind","turn","reverse","stop"]
const DEFAULTS := {"kind":"fuchuan","scenario":"pause-resume","input":"sails","handling":"assisted","camera_mode":"follow","paused":false}
const SCOPE := "Real Encounter/SailingSimulation, ShipView and ShipCameraController. Fixed flat deep water, seed 1661, headwind +X at 12m/s, 60Hz native steps. Diagnostic flat plane/grid only: no sea rendering, contact foam, crew or full-game performance claim. Scheduled pause uses one second of experiment timeline without accepting native time."
var _options := DEFAULTS.duplicate(true)
var _configured := false
var _disposed := false
var _ready_experiment := false
var _reason := ""
var _world: Node3D
var _ship: Node3D
var _camera: Camera3D
var _simulation: RefCounted
var _camera_rig: RefCounted
var _tick := 0
var _accumulator := 0.0
var _scheduled_pause := false
var _frame: Dictionary = {}

func _ready() -> void:
	set_process(false); set_physics_process(false)
	if _configured and not _disposed: _build()

func get_default_options() -> Dictionary: return DEFAULTS.duplicate(true)

func _validate(options: Dictionary) -> bool:
	return options.kind in KINDS and options.scenario in SCENARIOS and options.input in ["sails","controls","keys","course"] and options.handling in ["assisted","realistic"] and options.camera_mode in ["follow","high"] and options.paused is bool

func configure(options: Dictionary) -> Dictionary:
	var candidate := DEFAULTS.duplicate(true)
	candidate.merge(options.duplicate(true),true)
	if not _validate(candidate): return {"ok":false,"reason":"unsupported-handling-option"}
	dispose()
	_options = candidate; _configured = true; _disposed = false; _reason = ""
	_tick = 0; _accumulator = 0.0; _scheduled_pause = false; _frame.clear()
	if is_inside_tree(): _build()
	return {"ok":_reason.is_empty(),"ready":_ready_experiment,"pending":not is_inside_tree(),"reason":_reason}

func reset_experiment(options: Dictionary = {}) -> Dictionary:
	var camera_before: Dictionary = _camera_rig.status() if _camera_rig else {}
	var candidate := _options.duplicate(true); candidate.merge(options.duplicate(true),true)
	var result := configure(candidate)
	if result.ok and _ready_experiment and not camera_before.is_empty() and not options.has("camera_mode"):
		var current: Dictionary = _camera_rig.status()
		if camera_before.manual:
			var yaw_delta: float = atan2(sin(camera_before.targetYaw-current.targetYaw),cos(camera_before.targetYaw-current.targetYaw))
			_camera_rig.orbit(Vector2(-yaw_delta/0.004,(camera_before.targetPitch-current.targetPitch)/0.003))
		_camera_rig.zoom_by(-log(camera_before.targetRadius/current.targetRadius)/0.12)
		# Settle only explicit camera channels; native authority remains at tick 0.
		for sample in 60: _present(0.0,0.1)
	return result

func control_spec() -> Array:
	return [
		{"id":"scenario","label":"操作序列（重置）","type":"choice","value":_options.scenario,"choices":[{"value":"pause-resume","label":"迎风暂停后继续"},{"value":"headwind","label":"持续迎风"},{"value":"turn","label":"右转90度"},{"value":"reverse","label":"反打180度"},{"value":"stop","label":"收帆减速"}]},
		{"id":"input","label":"开始航行的输入（重置）","type":"choice","value":_options.input,"choices":[{"value":"sails","label":"帆量指令"},{"value":"controls","label":"控件指令"},{"value":"keys","label":"W键"},{"value":"course","label":"鼠标航向"}]},
		{"id":"handling","label":"现有操控模式（重置）","type":"choice","value":_options.handling,"choices":[{"value":"assisted","label":"休闲助力"},{"value":"realistic","label":"原物理模式"}]},
		{"id":"kind","label":"船型（重置）","type":"choice","value":_options.kind,"choices":[{"value":"fuchuan","label":"福船"},{"value":"heavy","label":"重舰"},{"value":"fisherman","label":"渔舟"},{"value":"patrol","label":"巡逻船"},{"value":"merchant","label":"商船"},{"value":"voc","label":"荷兰商船"}]},
		{"id":"camera_mode","label":"镜头","type":"choice","value":_options.camera_mode,"choices":[{"value":"follow","label":"跟船"},{"value":"high","label":"俯视"}]}
	]

func set_parameter(id: String,value: Variant) -> Dictionary:
	if id not in ["scenario","input","handling","kind","camera_mode"]: return {"ok":false,"reason":"unknown-parameter"}
	var candidate := _options.duplicate(true); candidate[id] = value
	if not _validate(candidate): return {"ok":false,"reason":"unsupported-handling-option"}
	if id == "camera_mode": set_camera_mode(value)
	return {"ok":true,"id":id,"value":value,"reset_required":id != "camera_mode" and value != _options[id]}

func _build() -> void:
	_world = Node3D.new(); _world.name = "ExperimentWorld"; add_child(_world)
	var native := Encounter.new({"mode":"continuous","referenceHandling":true,"battleId":"handling-experiment","seed":1661,
		"playerId":"player","controllableShipIds":["player"],"hostileTargets":{},"oceanWaves":[],
		"wind":{"direction":{"x":1.0,"y":0.0},"speed":12.0},
		"sampleTerrainHeight":func(_x: float,_z: float) -> float: return -80.0,
		"ships":[{"id":"player","kind":_options.kind,"team":"player","heading":0.0,"speed":0.0,"sailDeployment":0.0,"autoTrim":true,"position":{"x":0.0,"z":0.0}}]})
	if not native.last_error.is_empty(): _reason = native.last_error; return
	_simulation = Simulation.new(native); _simulation.set_handling_mode(_options.handling)
	match _options.input:
		"sails": _simulation.set_sails(0.8)
		"controls": _simulation.action({"type":"controls","rudder":0.0,"sailDeployment":0.8,"autoTrim":true})
		"keys": _simulation.set_held("KeyW",true)
		"course": _simulation.set_course({"x":1000.0,"z":0.0})
	_ship = Ship.new(); _ship.name = "Ship"; _world.add_child(_ship)
	if not _ship.configure(_options.kind): _reason = "ship-unavailable"; return
	_camera_rig = CameraRig.new()
	_camera = Camera3D.new(); _camera.name = "Camera"; _camera.current = true; _camera.fov = 55.0; _camera.near = 0.5; _camera.far = 2000.0; _world.add_child(_camera)
	var light := DirectionalLight3D.new(); light.rotation_degrees = Vector3(-50,-25,0); light.light_energy = 1.3; _world.add_child(light)
	var environment := WorldEnvironment.new(); environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR; environment.environment.background_color = Color("759ca9")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_color = Color.WHITE; environment.environment.ambient_light_energy = 0.6; _world.add_child(environment)
	var surface := MeshInstance3D.new(); var plane := PlaneMesh.new(); plane.size = Vector2(1000,1000); surface.mesh = plane
	var material := StandardMaterial3D.new(); material.albedo_color = Color("244d60"); material.roughness = 1.0; surface.material_override = material; surface.position.y = -0.3; _world.add_child(surface)
	for index in range(-5,6):
		for along_x: bool in [true,false]:
			var line := MeshInstance3D.new(); var mesh := BoxMesh.new(); mesh.size = Vector3(200,0.02,0.05) if along_x else Vector3(0.05,0.02,200); line.mesh = mesh
			line.position = Vector3(0,-0.25,index*20) if along_x else Vector3(index*20,-0.25,0); _world.add_child(line)
	_ready_experiment = true
	_simulation.set_paused(_options.paused)
	_present(0.0)

func advance(delta: float) -> void:
	if not _ready_experiment or _disposed or not is_finite(delta) or delta <= 0.0: return
	if _options.paused: _present(0.0,minf(delta,0.1)); return
	_accumulator += minf(delta,0.1)
	var count := 0
	while _accumulator+1e-12 >= STEP and count < 6:
		_tick += 1
		if _tick == 121:
			_simulation.set_held("KeyW",false)
			match _options.scenario:
				"pause-resume": _scheduled_pause = true; _simulation.set_paused(true)
				"turn": _simulation.set_course({"x":0.0,"z":1000.0})
				"reverse": _simulation.set_course({"x":-1000.0,"z":0.0})
				"stop": _simulation.stop_course()
		if _tick == 181 and _scheduled_pause: _scheduled_pause = false; _simulation.set_paused(false)
		var previous_time: float = _simulation.snapshot().time
		_simulation.advance(STEP)
		_present(float(_simulation.snapshot().time)-previous_time,STEP)
		_accumulator -= STEP; count += 1

func set_paused(value: bool) -> void:
	_options.paused = value
	_accumulator = 0.0
	if _simulation: _simulation.set_paused(value or _scheduled_pause)

func set_camera_mode(value: String) -> void:
	if value not in ["follow","high"]: return
	_options.camera_mode = value
	if _camera_rig: _camera_rig.recenter(); _present(0.0,0.1)

func orbit_camera(yaw_delta: float,pitch_delta: float) -> void:
	if not _camera_rig or not is_finite(yaw_delta) or not is_finite(pitch_delta): return
	if yaw_delta != 0.0 or pitch_delta != 0.0: _camera_rig.orbit(Vector2(-yaw_delta/0.004,pitch_delta/0.003))
	_present(0.0,0.1)

func zoom_camera(amount: float) -> void:
	if not _camera_rig or not is_finite(amount): return
	_camera_rig.zoom_by(-amount/0.12); _present(0.0,0.1)

func _present(consumed: float,input_seconds: float = 0.0) -> void:
	if not _ready_experiment: return
	var native: Dictionary = _simulation.snapshot()
	var ship: Dictionary = Simulation._ship(native,"player"); ship.time = native.time
	_ship.apply_snapshot(ship,native.wind,consumed)
	_frame = _camera_rig.step(ship,consumed,{"reducedMotion":true},_options.camera_mode == "high",1.0,input_seconds)
	_camera.global_position = _frame.position; _camera.look_at(_frame.target,_frame.up)

func inspection_snapshot() -> Dictionary:
	var native: Dictionary = _simulation.snapshot() if _simulation else {}
	var ship: Dictionary = Simulation._ship(native,"player")
	return {"ready":_ready_experiment,"disposed":_disposed,"reason":_reason,"parameters":_options.duplicate(true),
		"paused":_options.paused,"scheduled_pause":_scheduled_pause,"tick":_tick,"time":native.get("time",0.0),"timeline_seconds":_tick*STEP,
		"fixed_step":STEP,"seed":1661,"native":native,"camera":_frame.duplicate(true),"camera_state":_camera_rig.status() if _camera_rig else {},"scope":SCOPE,
		"telemetry":{"speed_mps":Vector2(ship.visual.velocity.x,ship.visual.velocity.z).length() if not ship.is_empty() else 0.0,
			"heading_degrees":rad_to_deg(ship.visual.heading) if not ship.is_empty() else 0.0,"handling":_simulation.handling_status() if _simulation else {}},
		"resources":{"world":1 if is_instance_valid(_world) else 0,"runtime":1 if _simulation else 0,"ship":1 if is_instance_valid(_ship) else 0}}

func dispose() -> void:
	_ready_experiment = false; _disposed = true
	if _simulation: _simulation.set_paused(true)
	_simulation = null; _camera_rig = null
	if is_instance_valid(_ship): _ship.dispose()
	_ship = null; _camera = null
	if is_instance_valid(_world): _world.free()
	_world = null

func _exit_tree() -> void: dispose()
