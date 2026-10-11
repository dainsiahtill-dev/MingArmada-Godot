extends SceneTree
## Delayed native events must reconstruct visible age rather than replay birth.
const Effects = preload("res://game/presentation/combat/combat_effects.gd")
var assertions := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ",message)
func _view(time: float) -> Node3D:
	var effects := Effects.new(); root.add_child(effects)
	effects.apply_snapshot({"time":time,"projectiles":[]},0.0)
	return effects
func _event(kind: String, id: String, time: float) -> Dictionary:
	return {"id":id,"type":kind,"time":time,"projectileId":"shot-"+id,"position":{"x":10.0,"y":3.0,"z":4.0},"velocity":{"x":1.0,"y":0.0,"z":0.0}}
func _nodes(effects: Node3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for child in effects.get_children():
		if child is MeshInstance3D: result.append(child)
	return result
func _close(effects: Node3D) -> void: effects.dispose(); effects.free()
func _water(_x: float,_z: float,_seconds: float) -> float: return 0.0
func _run() -> void:
	var immediate := _view(10.0)
	immediate.apply_events([_event("fire","on-time",10.0)])
	check(immediate.diagnostics().puffs == 7,"on-time fire retains flash plus six smoke puffs")
	var flash: MeshInstance3D = _nodes(immediate)[0]
	check(flash.position == Vector3(10,3,4) and flash.scale.is_equal_approx(Vector3.ONE*1.1),"on-time flash retains original origin and size")
	check(is_equal_approx(flash.material_override.albedo_color.a,0.95),"on-time flash retains original opacity")
	_close(immediate)

	var delayed := _view(10.0)
	var old_fire := _event("fire","delayed-fire",9.5)
	var before := old_fire.duplicate(true)
	delayed.apply_events([old_fire])
	check(delayed.diagnostics().puffs == 6,"delayed fire omits already-expired muzzle flash")
	check(old_fire == before,"presentation never changes source event time or geometry")
	var smoke: Array[MeshInstance3D] = []
	for node in _nodes(delayed):
		if node.material_override.albedo_color.r < 0.9: smoke.append(node)
	check(smoke.size() == 6,"delayed fire retains surviving six smoke puffs")
	if not smoke.is_empty():
		check(smoke[0].position.is_equal_approx(Vector3(9.6,3.35,4.15)),"delayed smoke first frame starts at its true half-second trajectory")
		check(smoke[0].scale.is_equal_approx(Vector3.ONE*1.65),"delayed smoke first frame starts at its true half-second size")
		check(is_equal_approx(smoke[0].material_override.albedo_color.a,0.4),"delayed smoke first frame starts at its true half-second opacity")
	var paused_positions: Array[Vector3] = []; var paused_sizes: Array[Vector3] = []; var paused_opacity: Array[float] = []
	for node in smoke:
		paused_positions.append(node.position); paused_sizes.append(node.scale); paused_opacity.append(node.material_override.albedo_color.a)
	delayed.apply_snapshot({"time":10.0,"projectiles":[]},0.5)
	var frozen := true
	for index in smoke.size():
		frozen = frozen and smoke[index].position == paused_positions[index] and smoke[index].scale == paused_sizes[index] and smoke[index].material_override.albedo_color.a == paused_opacity[index]
	check(frozen,"same accepted time freezes every delayed smoke property even with wall delta")
	delayed.apply_events([old_fire]); check(delayed.diagnostics().puffs == 6,"duplicate delayed event cannot replay a flash or smoke")
	delayed.apply_snapshot({"time":10.25,"projectiles":[]},0.0)
	if not smoke.is_empty():
		check(smoke[0].position.is_equal_approx(Vector3(9.4,3.525,4.225)),"next accepted snapshot advances smoke from original event time")
	delayed.apply_snapshot({"time":8.0,"projectiles":[]},0.0)
	check(delayed.diagnostics().puffs == 0 and delayed.diagnostics().events == 0,"rewind clears smoke and native event replay cache")
	var released := true
	for node in smoke: released = released and not is_instance_valid(node)
	check(released,"rewind releases all old real smoke nodes")
	delayed.apply_snapshot({"time":10.0,"projectiles":[]},0.0); delayed.apply_events([old_fire])
	check(delayed.diagnostics().puffs == 6,"rewound replay reconstructs surviving age without replaying expired flash")
	delayed.apply_snapshot({"time":12.01,"projectiles":[]},0.0)
	check(delayed.diagnostics().puffs == 0,"smoke expires relative to original fire time")
	_close(delayed)

	var hit := _view(10.0)
	hit.apply_events([_event("hit","delayed-hit",9.75)])
	check(hit.diagnostics().puffs == 6,"delayed hit retains surviving wood fragments")
	var fragment: MeshInstance3D = _nodes(hit)[0]
	check(fragment.position.is_equal_approx(Vector3(10,3.375,4.75)),"delayed hit first frame starts at its true quarter-second trajectory")
	check(fragment.scale.is_equal_approx(Vector3.ONE*0.145),"delayed hit first frame starts at its true quarter-second size")
	check(is_equal_approx(fragment.material_override.albedo_color.a,0.6861111111),"delayed hit first frame starts at its true quarter-second opacity")
	hit.apply_snapshot({"time":10.7,"projectiles":[]},0.0)
	check(hit.diagnostics().puffs == 0,"wood fragments expire relative to original hit time")
	_close(hit)

	for fixture: Dictionary in [{"time":11.0,"name":"future"},{"time":6.0,"name":"expired"}]:
		var rejected := _view(10.0)
		for kind: String in ["fire","hit"]:
			rejected.apply_events([_event(kind,fixture.name+kind,fixture.time)])
			check(rejected.diagnostics().puffs == 0,fixture.name+" "+kind+" does not create new visible effects")
		_close(rejected)

	var damage := _view(10.0)
	damage.set_water_sampler(_water); damage.apply_snapshot({"time":10.0,"projectiles":[]},0.0)
	damage.apply_events([_event("mast-break","mast",9.5)])
	check(damage.diagnostics().puffs == 8,"delayed mast event retains eight surviving splinters")
	var splinter: MeshInstance3D = _nodes(damage)[0]
	check(splinter.position.is_equal_approx(Vector3(10,3.55,5)),"delayed mast splinter is immediately placed at existing accepted age")
	damage.apply_events([_event("destruction-explosion","destruction",9.5)])
	check(damage.diagnostics().puffs == 16,"delayed destruction retains smoke and omits expired explosion flash")
	damage.apply_events([_event("sinking-froth","sink",9.5)])
	check(damage.diagnostics().splashes == 1,"sinking event still reaches surface-only froth presenter")
	var froth: Node3D = damage.get_node("WaterSplashes").get_child(0)
	check(froth.get_node("SurfaceFroth").visible and not froth.get_node("WaterColumn").visible and not froth.get_node("WorldDroplets").visible,"sinking remains surface froth without cannon plume or droplets")
	_close(damage)

	var budget := _view(10.0)
	var salvo: Array = []
	for index in 100: salvo.append(_event("fire","salvo-%d"%index,9.5))
	budget.apply_events(salvo)
	check(budget.diagnostics().puffs == 160,"delayed salvo obeys existing visible puff budget")
	_close(budget)
	print("REFERENCE_EVENT_TIME_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
