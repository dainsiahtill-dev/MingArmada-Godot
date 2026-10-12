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
func _source_geometry(effects: Node3D) -> Array:
	var result: Array=[]
	for source: Node in effects.get_children():
		if not String(source.name).begins_with("CannonSource_"): continue
		for mesh: MeshInstance3D in source.get_children():
			if mesh.visible and mesh.mesh!=null and mesh.mesh.get_surface_count()>0:
				result.append({"vertices":mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX],"colors":mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR],"uv":mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV],"indices":mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]})
	return result
func _source_state(effects: Node3D) -> Dictionary:
	var states: Array=effects.diagnostics().get("source_effects",[])
	return states[0] if not states.is_empty() else {}
func _close(effects: Node3D) -> void: effects.dispose(); effects.free()
func _water(_x: float,_z: float,_seconds: float) -> float: return 0.0
func _run() -> void:
	var immediate := _view(10.0)
	immediate.apply_events([_event("fire","on-time",10.0)])
	check(immediate.diagnostics().source_fire==1 and immediate.diagnostics().puffs==0,"on-time fire creates the actual source cannon replay")
	var source: Dictionary=_source_state(immediate)
	check(source.get("age")==0.0 and source.get("accepted_time")==10.0 and source.get("origin")==Vector3(10,3,4),"on-time source fire starts at real event origin and accepted birth")
	immediate.apply_snapshot({"time":10.06,"projectiles":[]},0.0)
	check(immediate.diagnostics().source_particles>0 and not _source_geometry(immediate).is_empty(),"accepted source births create submitted textured cannon geometry")
	_close(immediate)

	var delayed := _view(10.0)
	var old_fire := _event("fire","delayed-fire",9.5)
	var before := old_fire.duplicate(true)
	delayed.apply_events([old_fire])
	check(delayed.diagnostics().source_fire==1 and _source_state(delayed).get("age")==0.5,"delayed cannon replay begins at actual half-second age")
	check(old_fire == before,"presentation never changes source event time or geometry")
	var chronological:=_view(9.5); chronological.apply_events([old_fire])
	chronological.apply_snapshot({"time":10.0,"projectiles":[]},0.0)
	var geometry: Array=_source_geometry(delayed)
	check(not geometry.is_empty(),"delayed source fire has surviving real particle geometry")
	check(geometry==_source_geometry(chronological),"delayed first frame matches the same source event aged through accepted snapshots")
	_close(chronological)
	delayed.apply_snapshot({"time":10.0,"projectiles":[]},0.5)
	check(_source_geometry(delayed)==geometry,"same accepted time freezes submitted source particle geometry despite wall delta")
	delayed.apply_events([old_fire]); check(delayed.diagnostics().source_fire==1 and _source_geometry(delayed)==geometry,"duplicate delayed event cannot restart source fire")
	delayed.apply_snapshot({"time":10.25,"projectiles":[]},0.0)
	check(_source_state(delayed).get("age")==0.75 and _source_geometry(delayed)!=geometry,"next accepted snapshot advances original event age and actual particle mesh")
	var retained: WeakRef=weakref(delayed.get_node_or_null("CannonSource_delayed-fire"))
	delayed.apply_snapshot({"time":8.0,"projectiles":[]},0.0)
	check(delayed.diagnostics().source_fire==0 and delayed.diagnostics().events==0,"rewind clears source fire and native event replay cache")
	check(retained==null or retained.get_ref()==null,"rewind releases real source replay owner and meshes")
	delayed.apply_snapshot({"time":10.0,"projectiles":[]},0.0); delayed.apply_events([old_fire])
	check(_source_state(delayed).get("age")==0.5 and _source_geometry(delayed)==geometry,"rewound replay reconstructs the same surviving source geometry at original age")
	delayed.apply_snapshot({"time":20.0,"projectiles":[]},0.0)
	check(delayed.diagnostics().source_fire==0,"finite source smoke expires relative to original fire time")
	_close(delayed)

	var hit := _view(10.0)
	hit.apply_events([_event("hit","delayed-hit",9.75)])
	check(hit.diagnostics().puffs == 6,"delayed hit retains surviving wood fragments")
	if not _nodes(hit).is_empty():
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
			check(rejected.diagnostics().puffs==0 and rejected.diagnostics().source_fire==0,fixture.name+" "+kind+" does not create new visible effects")
		_close(rejected)

	var damage := _view(10.0)
	damage.set_water_sampler(_water); damage.apply_snapshot({"time":10.0,"projectiles":[]},0.0)
	damage.apply_events([_event("mast-break","mast",9.5)])
	check(damage.diagnostics().puffs == 8,"delayed mast event retains eight surviving splinters")
	if not _nodes(damage).is_empty():
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
	for index in 100: salvo.append(_event("hit","salvo-%d"%index,9.5))
	budget.apply_events(salvo)
	check(budget.diagnostics().puffs==160,"delayed debris salvo obeys existing visible puff budget")
	_close(budget)
	print("REFERENCE_EVENT_TIME_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
