extends Node3D
## One registered research topic, two isolated demonstrations and clocks.
const Workshop = preload("res://game/research/demos/crew_workshop_experiment.gd")
const Battle = preload("res://game/research/demos/crew_battle_experiment.gd")
var _inner: Node3D
var _mode := "workshop"
var _disposed := false

func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	_attach()

func _attach() -> void:
	if is_instance_valid(_inner) and _inner.get_parent() == null and is_inside_tree(): add_child(_inner)

func get_default_options() -> Dictionary:
	var view := Workshop.new()
	var options: Dictionary = view.get_default_options()
	view.free()
	options.mode = "workshop"
	return options

func configure(options: Dictionary) -> Dictionary:
	var mode = options.get("mode","workshop")
	if not mode is String or mode not in ["workshop","battle"]: return {"ok":false,"reason":"未知船员实验模式"}
	var candidate: Node3D = Battle.new() if mode == "battle" else Workshop.new()
	var parameters := options.duplicate(true)
	parameters.erase("mode")
	var receipt: Dictionary = candidate.configure(parameters)
	if not receipt.ok:
		candidate.free()
		return receipt
	dispose()
	_inner = candidate
	_mode = mode
	_disposed = false
	set_process(false)
	set_physics_process(false)
	_attach()
	return {"ok":true,"ready":is_inside_tree(),"pending":not is_inside_tree()}

func prepare_start_options(cached: Dictionary, overrides: Dictionary) -> Dictionary:
	var result := cached.duplicate(true)
	var requested = overrides.get("mode",cached.get("mode","workshop"))
	if requested != cached.get("mode","workshop") and requested in ["workshop","battle"]:
		var view: Node3D = Battle.new() if requested == "battle" else Workshop.new()
		result = view.get_default_options()
		view.free()
		for key in ["paused","camera_mode"]:
			if cached.has(key): result[key] = cached[key]
		result.mode = requested
	result.merge(overrides,true)
	return result

func reset_experiment(overrides: Dictionary = {}) -> Dictionary:
	if not is_instance_valid(_inner): return {"ok":false,"reason":"实验尚未配置"}
	if overrides.has("mode") and overrides.mode != _mode:
		var next := {"mode":overrides.mode,"paused":inspection_snapshot().paused}
		next.merge(overrides,true)
		return configure(next)
	var parameters := overrides.duplicate(true)
	parameters.erase("mode")
	var receipt: Dictionary = _inner.reset_experiment(parameters)
	if receipt.ok: receipt.snapshot = inspection_snapshot()
	return receipt

func control_spec() -> Array:
	var specs: Array = [{"id":"mode","label":"船员课题","type":"choice","value":_mode,"choices":[{"value":"workshop","label":"船上作业"},{"value":"battle","label":"同预算实弹对照"}]}]
	if is_instance_valid(_inner): specs.append_array(_inner.control_spec())
	return specs

func set_parameter(id: String,value: Variant) -> Dictionary:
	if id == "mode":
		if not value is String or value not in ["workshop","battle"]: return {"ok":false,"reason":"未知船员实验模式"}
		return {"ok":true,"id":id,"value":value,"reset_required":value != _mode}
	if not is_instance_valid(_inner): return {"ok":false,"reason":"实验尚未配置"}
	return _inner.set_parameter(id,value)

func advance(delta: float) -> void:
	if is_instance_valid(_inner): _inner.advance(delta)
func set_paused(value: bool) -> void:
	if is_instance_valid(_inner): _inner.set_paused(value)
func set_camera_mode(value: String) -> void:
	if is_instance_valid(_inner): _inner.set_camera_mode(value)
func orbit_camera(yaw: float,pitch: float) -> void:
	if is_instance_valid(_inner): _inner.orbit_camera(yaw,pitch)
func zoom_camera(amount: float) -> void:
	if is_instance_valid(_inner): _inner.zoom_camera(amount)

func inspection_snapshot() -> Dictionary:
	if not is_instance_valid(_inner): return {"ready":false,"disposed":_disposed,"parameters":{"mode":_mode},"tick":0,"time":0.0}
	var state: Dictionary = _inner.inspection_snapshot()
	state.parameters.mode = _mode
	return state

func dispose() -> void:
	_disposed = true
	if is_instance_valid(_inner):
		_inner.dispose()
		if _inner.get_parent() == self: remove_child(_inner)
		_inner.free()
	_inner = null

func _exit_tree() -> void: dispose()
