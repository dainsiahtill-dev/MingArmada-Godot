extends SceneTree
const Weather=preload("res://modules/environment_engine/weather_state.gd")
var assertions:=0
var failures:=0
func check(ok:bool,message:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL: ",message)
func _initialize()->void:run.call_deferred()
func row(x:float,generation:int,velocity:float=-10.0)->Dictionary:
	return {"worldPosition":[x,30.0,0.0],"generation":generation,"driftVelocity":[velocity,0.0,0.0]}
func run()->void:
	var w:=Weather.new()
	w.configure({"initial_state":{"lightTime":1200,"windHeading":1073741760,"windDisplacement":0,"windVelocity":0,"centers":[{"x":-16001,"y":0},{"x":3000,"y":4000},{"x":6000,"y":-4000}]},"source_environment":{"movementSpeed":0}})
	var initial:Dictionary=w.snapshot()
	var next:Dictionary=w.advance(1.0/32.0,{},{})
	check(initial.worldClouds[0].get("generation",-1)==0 and next.worldClouds[0].get("generation",-1)==1,"native center reset publishes exact generation")
	check(next.worldClouds[0].has("driftVelocity"),"continuous source drift is explicit")
	w.reset({"source_calls_per_second":0})
	check(w.snapshot()==next,"invalid reset preserves the accepted environment packet")
	var after_rejected_reset:Dictionary=w.advance(2.0/32.0,{},{})
	check(after_rejected_reset.worldClouds[0].generation==1,"invalid reset preserves generation on subsequent advance")
	var path:="res://modules/scene_engine/fidelity_fx/world_cloud_lifecycle.gd"
	check(ResourceLoader.exists(path),"world cloud lifecycle adapter exists")
	if not ResourceLoader.exists(path):finish();return
	var flow:RefCounted=load(path).new()
	var seen:=func(p:Vector3,r:float)->bool:return p.x-r<=100.0 and p.x+r>=-100.0
	var pose:Dictionary=flow.advance(0,row(0,0),0.0,20.0,seen)
	pose=flow.advance(0,row(200,1),1.0,20.0,seen)
	check(pose.position.x<0 and absf(pose.position.x)<11 and pose.retiring,"visible reset retains outgoing cloud and moves it")
	var before:Dictionary=flow.snapshot()
	flow.advance(0,row(200,1),1.0,20.0,func(_p,_r):return false)
	check(flow.snapshot()==before,"paused camera-only refresh cannot retire/rebirth clouds")
	for tick in range(2,17):pose=flow.advance(0,row(0,1),float(tick),20.0,seen)
	check(pose.retiring,"whole cloud edge and safety margin must leave before recycle")
	pose=flow.advance(0,row(0,1),17.0,20.0,seen)
	check(not pose.retiring and pose.recycles==1,"old full bounds outside view permit one recycle")
	check(not seen.call(pose.position,68.0),"new generation starts outside expanded view")
	var saved:Dictionary=flow.snapshot()
	var restored:RefCounted=load(path).new();restored.restore(saved)
	check(restored.snapshot()==saved,"presentation state can survive owner recreation")
	var a:Dictionary=flow.advance(0,row(-1,1),18.0,20.0,seen)
	var b:Dictionary=restored.advance(0,row(-1,1),18.0,20.0,seen)
	check(a==b,"restored visual trajectory continues deterministically")
	flow.clear();check(flow.snapshot().is_empty(),"epoch clear releases all actor histories")
	var smooth:RefCounted=load(path).new()
	smooth.advance(0,row(0,0,-96),0.0,20.0,seen)
	var prior:=0.0;var peak:=0.0
	for tick in range(1,121):
		pose=smooth.advance(0,row(-3.0*floor(tick*32.0/60.0),0,-96),tick/60.0,20.0,seen)
		peak=maxf(peak,absf(pose.position.x-prior));prior=pose.position.x
	check(peak<1.601 and absf(prior+192.0)<.001,"discrete source positions produce continuous 60Hz drift")
	check_velocity_integration(path,seen)
	check_time_rebase(path,seen)
	check_frusta(load(path))
	print("CLOUD_LIFECYCLE_METRICS max_step=",peak)
	finish()
func check_velocity_integration(path:String,seen:Callable)->void:
	var coarse:RefCounted=load(path).new()
	var fine:RefCounted=load(path).new()
	coarse.advance(0,row(0,0,-100.0),0.0,20.0,seen)
	fine.advance(0,row(0,0,-100.0),0.0,20.0,seen)
	var coarse_pose:Dictionary=coarse.advance(0,row(0,0,100.0),1.0,20.0,seen)
	var fine_pose:Dictionary={}
	for tick in range(1,61):fine_pose=fine.advance(0,row(0,0,100.0),tick/60.0,20.0,seen)
	check(Vector3(coarse_pose.position).distance_to(fine_pose.position)<0.0001,"velocity response displacement is invariant to time partition")
	check(Vector3(coarse_pose.velocity).distance_to(fine_pose.velocity)<0.0001,"velocity response endpoint is invariant to time partition")
	# Exact integral for -100 -> +100 m/s, response time 0.2s, over one second.
	check(absf(float(coarse_pose.position.x)-(100.0-40.0*(1.0-exp(-5.0))))<0.0001,"velocity response integrates the complete transition")
func check_time_rebase(path:String,seen:Callable)->void:
	var flow:RefCounted=load(path).new()
	check(flow.has_method("rebase_time"),"held presentation trajectories support clock rebasing")
	if not flow.has_method("rebase_time"):return
	for index in 3:flow.advance(index,row(index*10.0,0,-96.0),0.0,20.0,seen)
	flow.advance(0,row(200.0,1,-96.0),1.0/60.0,20.0,seen)
	var before:Dictionary=flow.snapshot()
	var expected:Dictionary=before.duplicate(true)
	for state:Dictionary in expected.values():state.time=60.0
	flow.rebase_time(60.0)
	check(flow.snapshot()==expected,"rebasing updates all three actor clocks without changing pose velocity or lifecycle metadata")
	var resumed:Dictionary=flow.advance(0,row(1000.0,4,96.0),60.0,20.0,seen)
	check(flow.snapshot()==expected,"same accepted resume time cannot move or recycle held actors")
	resumed=flow.advance(0,row(1000.0,4,96.0),60.0+1.0/60.0,20.0,seen)
	check(Vector3(resumed.position).distance_to(before[0].position)<1.601,"first resumed frame integrates only its own delta after a sixty-second hold")
	check(resumed.retiring and resumed.generation==4 and resumed.recycles==before[0].recycles,"resume retains outgoing cloud and admits latest generation without a visible replacement")
	var valid:Dictionary=flow.snapshot()
	flow.rebase_time(NAN);flow.rebase_time(-1.0)
	check(flow.snapshot()==valid,"invalid rebase clocks cannot corrupt held trajectories")
	flow.clear();flow.rebase_time(60.0)
	check(flow.snapshot().is_empty(),"rebasing an empty lifecycle cannot create actors")
func check_frusta(lifecycle:GDScript)->void:
	var viewport:=SubViewport.new()
	viewport.size=Vector2i(512,512)
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	var camera:=Camera3D.new()
	viewport.add_child(camera)
	camera.position=Vector3(0.0,10.0,0.0)
	camera.near=1.0;camera.far=100.0;camera.fov=90.0
	var planes:Array[Plane]=camera.get_frustum()
	check(planes.size()==6,"Camera3D supplies all six real frustum planes")
	check(lifecycle.sphere_in_views(Vector3(0.0,10.0,-10.0),0.1,planes),"sphere inside real main frustum remains visible")
	var outside_points:Array[Vector3]=[Vector3(0.0,10.0,-0.2),Vector3(0.0,10.0,-101.0),Vector3(-15.0,10.0,-10.0),Vector3(15.0,10.0,-10.0),Vector3(0.0,25.0,-10.0),Vector3(0.0,-5.0,-10.0)]
	for index in outside_points.size():check(not lifecycle.sphere_in_views(outside_points[index],0.1,planes),"real main frustum rejects outside face %d"%index)
	check(lifecycle.sphere_in_views(Vector3(10.5,10.0,-10.0),1.0,planes),"whole sphere edge crossing a frustum face remains visible")
	var reflection:=Camera3D.new()
	viewport.add_child(reflection)
	# Real reflected camera for a main camera at y=10 and nonzero tide y=3.
	reflection.position=Vector3(0.0,-4.0,0.0)
	reflection.near=camera.near;reflection.far=camera.far;reflection.fov=camera.fov
	var reflection_planes:Array[Plane]=reflection.get_frustum()
	var reflection_only:=Vector3(0.0,-4.0,-10.0)
	check(not lifecycle.sphere_in_views(reflection_only,0.1,planes),"reflection-only cloud is outside the main frustum")
	check(lifecycle.sphere_in_views(reflection_only,0.1,planes,reflection_planes),"actual nonzero-tide reflection frustum protects reflected cloud")
	check(not lifecycle.sphere_in_views(Vector3(0.0,30.0,-10.0),0.1,planes,reflection_planes),"sphere outside both real views can be recycled")
	viewport.free()
func finish()->void:
	print("WORLD_CLOUD_LIFECYCLE_TESTS assertions=",assertions," failures=",failures);quit(1 if failures else 0)
