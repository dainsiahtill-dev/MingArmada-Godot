extends SceneTree
## Target sailing birth gate: stopping suppresses new births, not elapsed time.
## This is not a recovered 475550 lifecycle rule.
const Froth=preload("res://modules/scene_engine/water/source_froth.gd")
var assertions:=0
var failures:=0
var evidence:Dictionary={}
func check(ok:bool,message:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL froth emission gate: ",message)
func _initialize()->void:_run.call_deferred()
func _water(_x:float,_z:float,_time:float)->float:return 0.0
func packet(time:float,enabled:bool)->Dictionary:
	return {"sourcePosition":[100.0,100.0,0.0],"sourceBowPosition":[100.0,100.0,0.0],"modelScale":1.0,"sourceToWorld":0.02,"controllerAppTime":time,"enabled":enabled,"sourceCamera":{"right":[1.0,0.0,0.0],"up":[0.0,1.0,0.0],"direction":[0.0,0.0,-1.0]}}
func particle_vertices(froth:RefCounted)->PackedVector3Array:
	for node:Node in (froth.get("_container") as Node3D).get_children():
		if node is MeshInstance3D and str(node.name).begins_with("ParticleSystem_") and node.visible and node.mesh!=null:
			return node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].duplicate()
	return PackedVector3Array()
func _run()->void:
	var parent:=Node3D.new();root.add_child(parent)
	var froth:=Froth.new();check(froth.configure(parent,0,7).ok,"actual source bow/side instance configures")
	froth.apply_snapshot(packet(0.0,true),0.0,_water,Callable())
	froth.apply_snapshot(packet(1.0,true),1.0,_water,Callable())
	var particles:RefCounted=froth.get("_particles")
	var moving:Dictionary=particles.diagnostics()
	check(moving.active>0 and moving.births>0,"real source emitters contain surviving water droplets before stopping")
	evidence.moving={"time":moving.time,"births":moving.births,"requested":moving.requested,"active":moving.active}
	froth.apply_snapshot(packet(1.05,false),1.05,_water,Callable())
	var residual:Dictionary=particles.diagnostics()
	evidence.residual={"time":residual.time,"births":residual.births,"requested":residual.requested,"active":residual.active}
	check(residual.births==moving.births and residual.requested==moving.requested,"disabled snapshot suppresses only new particle births")
	check(residual.active>0 and (froth.get("_container") as Node3D).visible,"existing droplets remain visible briefly after stopping")
	for node:Node in (froth.get("_container") as Node3D).get_children():
		if str(node.name).begins_with("bow_") or str(node.name).begins_with("side_"):
			check(not (node as MeshInstance3D).visible,"stopped hull does not retain attached authored froth")
	var before_camera:Dictionary=particles.source_state()
	var before_vertices:=particle_vertices(froth)
	froth.redraw_camera({"right":[0.0,1.0,0.0],"up":[0.0,0.0,1.0],"direction":[-1.0,0.0,0.0]})
	check(not before_vertices.is_empty() and particle_vertices(froth)!=before_vertices,"stopped residual droplets still face the changed camera in actual surface vertices")
	check(particles.source_state()==before_camera,"camera redraw never advances disabled pools or RNG")
	for time:float in [2.0,3.0,4.0,5.0,6.0,7.0,8.0,9.0,10.0]:
		froth.apply_snapshot(packet(time,false),time,_water,Callable())
	var stopped:Dictionary=particles.diagnostics()
	evidence.stopped={"time":stopped.time,"births":stopped.births,"requested":stopped.requested,"active":stopped.active}
	check(stopped.time==10.0,"disabled snapshots keep source particle clock current")
	check(stopped.active==0,"source lifetime modifiers retire every pre-stop droplet")
	check(stopped.births==moving.births and stopped.requested==moving.requested,"nine seconds stopped do not enqueue suppressed births")
	froth.apply_snapshot(packet(10.1,true),10.1,_water,Callable())
	var resumed:Dictionary=particles.diagnostics()
	evidence.resumed={"time":resumed.time,"births":resumed.births,"requested":resumed.requested,"active":resumed.active}
	# Original four constant rates 4/3.52/4.8/3.2 cross no integer birth boundary
	# in [10.0,10.1]. Catch up from 1.0 would request far more than zero.
	check(resumed.requested==stopped.requested and resumed.births==stopped.births,"resume does not replay the disabled emission interval")
	check(resumed.active==0,"resume does not upload a burst of stale water droplets")
	froth.apply_snapshot(packet(10.3,true),10.3,_water,Callable())
	var sailing_again:Dictionary=particles.diagnostics()
	evidence.sailing_again={"time":sailing_again.time,"births":sailing_again.births,"requested":sailing_again.requested,"active":sailing_again.active}
	check(sailing_again.requested==resumed.requested+3 and sailing_again.births==resumed.births+3,"the next genuine emission interval creates three fresh droplets")
	froth.dispose();parent.free()
	print("SOURCE_FROTH_EMISSION_GATE_EVIDENCE ",JSON.stringify(evidence))
	print("SOURCE_FROTH_EMISSION_GATE_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
