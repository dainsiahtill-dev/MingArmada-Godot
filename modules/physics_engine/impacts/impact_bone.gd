extends RigidBody3D
## Jolt owns articulated positions/joints. Accepted delta gates force integration.

var simulation_velocity := Vector3.ZERO
var simulation_spin := Vector3.ZERO
var phase := 0.0
var previous_phase := 0.0
var accepted_delta := 0.0
var water_sampler := Callable()
var deck_sampler := Callable()
var target_id := ""
var radius := 0.075
var water_supported := false
var contact := "air"
var wet_age := 0.0
var _velocity_scale := 1.0
var _first := true
var _last_active := false

func request_step(delta: float, accepted_phase: float) -> void:
	accepted_delta = delta
	previous_phase = phase
	phase = accepted_phase
	freeze = delta <= 0.0
	if delta > 0.0:
		sleeping = false

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if accepted_delta <= 0.0:
		if _last_active:
			simulation_velocity = state.linear_velocity / _velocity_scale
			simulation_spin = state.angular_velocity / _velocity_scale
		_last_active = false
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		return
	var delta := accepted_delta
	accepted_delta = 0.0
	if not _first and _last_active:
		simulation_velocity = state.linear_velocity / _velocity_scale
		simulation_spin = state.angular_velocity / _velocity_scale
	_first = false
	_last_active = true
	var previous := state.transform.origin
	var water := -INF
	if water_sampler.is_valid():
		var previous_water: float = water_sampler.call(previous.x, previous.z, previous_phase)
		if is_finite(previous_water) and previous.y - radius >= previous_water:
			water_supported = true
		water = water_sampler.call(previous.x, previous.z, phase)
	simulation_velocity.y -= 9.81 * delta
	contact = "air"
	var predicted := previous + simulation_velocity * delta
	if deck_sampler.is_valid():
		var support: Dictionary = deck_sampler.call(target_id, predicted, previous, phase, previous_phase)
		if not support.is_empty():
			var normal: Vector3 = support.normal
			var depth := (predicted - Vector3(support.point)).dot(normal) - radius
			if depth < 0.0 and (previous - Vector3(support.point)).dot(normal) >= radius - 0.1:
				simulation_velocity -= normal * minf(0.0, simulation_velocity.dot(normal))
				contact = "deck"
	if is_finite(water) and predicted.y - radius <= water:
		contact = "water"
		if water_supported:
			var level := water + radius - wet_age * 0.45
			if predicted.y < level:
				simulation_velocity.y = maxf(simulation_velocity.y, (level - previous.y) / delta)
		wet_age += delta
		simulation_velocity *= pow(0.94, delta * 120.0)
	elif contact == "deck":
		simulation_velocity *= pow(0.985, delta * 120.0)
	_velocity_scale = delta / state.step
	state.linear_velocity = simulation_velocity * _velocity_scale
	state.angular_velocity = simulation_spin * _velocity_scale
