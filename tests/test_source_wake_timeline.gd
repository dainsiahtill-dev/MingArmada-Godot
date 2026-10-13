extends SceneTree
const Wakes=preload("res://game/presentation/water/wake_trails.gd")
var assertions:=0
var failures:=0
var water_calls:=0
func check(ok:bool,message:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL: ",message)
func _initialize()->void:_run.call_deferred()
func water(_x:float,_z:float,_time:float)->float:water_calls+=1;return 0.35
func packet(call_index:int,time:float,x:float,camera:Dictionary)->Dictionary:
	return {"time":time,"environment":{"route":"sailing"},"wake":{"route":"scene_30","epoch":1,"sourceCallIndex":call_index},"ships":[{"id":"ship","sourceWake":{"route":"scene_30","sourceCallIndex":call_index,"sourceClock":time,"sourcePosition":[x,100,0],"modelScale":0.1,"sourceToWorld":0.01,"markerId":"Dummy_Wake","sourceHeading":0.0,"froth":{"family":0,"seed":7,"enabled":true,"controllerAppTime":time,"sourceBowPosition":[x+20,100,0],"sourceCamera":camera}}}]}
func _run()->void:
	var a:Dictionary={"right":[1.0,0.0,0.0],"up":[0.0,1.0,0.0],"direction":[0.0,0.0,-1.0]}
	var b:Dictionary={"right":[0.0,1.0,0.0],"up":[-1.0,0.0,0.0],"direction":[0.0,0.0,-1.0]}
	var wakes:=Wakes.new();root.add_child(wakes);wakes.configure(water)
	wakes.apply_snapshot(packet(0,0.0,100,a));wakes.apply_snapshot(packet(1,0.25,104,a))
	var renderer:RefCounted=wakes.get("_source_wakes");var actor:Dictionary=renderer.get("_actors").ship;var froth:RefCounted=actor.froth
	var runtime:RefCounted=froth.get("_particles");var state:Dictionary=runtime.source_state();var history:PackedByteArray=actor.history.ring_bytes()
	var particles:MeshInstance3D=froth.get("_container").get_node("ParticleSystem_8")
	var before:PackedVector3Array=particles.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var bow:MeshInstance3D=froth.get("_container").find_child("bow_*",false,false);var bow_mesh:int=bow.mesh.get_instance_id()
	var before_water:=water_calls;var before_uv:Variant=froth.diagnostics().side_uv
	wakes.apply_snapshot(packet(1,0.25,104,b))
	var after:PackedVector3Array=particles.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(before!=after,"same original source call with changed camera rotates actual ParticleSystem_8 billboard")
	check(runtime.source_state()==state and actor.history.ring_bytes()==history,"camera-only presentation changes no native history/RNG/birth/pool state")
	check(froth.diagnostics().side_uv==before_uv and bow.mesh.get_instance_id()==bow_mesh and water_calls==before_water,"camera-only redraw does not advance UV clock or rebuild/sample authored froth")
	var uploads:int=froth.get("_surface").rebuilds+froth.get("_surface").region_uploads
	wakes.apply_snapshot(packet(1,0.25,104,b))
	check(froth.get("_surface").rebuilds+froth.get("_surface").region_uploads==uploads,"unchanged paused camera/source packet performs no mesh upload")
	for i in range(2,45):wakes.apply_snapshot(packet(i,float(i)/4,100+i*4,b))
	var future_node:Node3D=renderer.get("_actors").ship.node
	wakes.apply_snapshot(packet(0,0.0,100,a))
	check(not is_instance_valid(future_node),"same-epoch target presentation rewind releases all future wake/froth nodes")
	check(wakes.diagnostics().source_updates==1 and wakes.diagnostics().source_samples==1,"earlier packet starts fresh target history rather than retaining future geometry")
	check(wakes.diagnostics().get("source_target_rewind_guards",0)==1,"restart is explicitly diagnosed as target presentation rewind guard")
	var restarted:Dictionary=renderer.get("_actors").ship
	check(restarted.froth.get("_particles").source_state().rng.draws==0,"target rewind restarts explicit seed/pool without claiming old original history restore")
	wakes.apply_snapshot(packet(1,0.25,104,b))
	check(wakes.diagnostics().source_updates==2 and wakes.diagnostics().source_particle_births>0,"earlier accepted timeline continues original ring and new froth births after guard")
	wakes.dispose();wakes.free()
	print("SOURCE_WAKE_TIMELINE_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
