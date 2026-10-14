extends SceneTree
const Renderer=preload("res://modules/scene_engine/water/source_wake_renderer.gd")
var assertions:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,why:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL: ",why)
func water(x:float,z:float,time:float)->float:return sin(x*.05+z*.03+time)*.4
func target(position:Vector3,speed:float=4.8)->Dictionary:
	return {"enabled":true,"position":position,"forward":Vector3(0,0,-1),"speed":speed,"beam":9.0,"length":32.0,"hullAlive":true}
func packet(index:int,time:float,with_flow:bool=true)->Dictionary:
	var wake:Dictionary={"route":"scene_30","sourceCallIndex":index,"sourceClock":time,"sourcePosition":[100.0+index*40.0,100.0,0.0],"markerId":1,"modelScale":1.0,"sourceToWorld":0.02135352848}
	if with_flow:wake.targetTrail=target(Vector3(0,0,-index*.6))
	return {"time":time,"wake":{"route":"scene_30","epoch":1},"ships":[{"id":"ship","sourceWake":wake}]}
func run()->void:
	var owner:=Node3D.new();root.add_child(owner)
	var renderer:=Renderer.new(owner)
	renderer.apply_snapshot(packet(0,0.0),water,Callable())
	check(renderer._actors.ship.get("flow")!=null,"explicit targetTrail creates candidate through the actual production owner")
	if not FileAccess.file_exists("res://modules/scene_engine/water/wake_flow.gd"):
		renderer.dispose();owner.free();finish();return
	var flow_script:Script=load("res://modules/scene_engine/water/wake_flow.gd")
	var flow:RefCounted=flow_script.new(owner)
	flow.apply_snapshot(target(Vector3.ZERO),0.0,water,Callable())
	flow.apply_snapshot(target(Vector3(0,0,-.6)),.125,water,Callable())
	check(flow.diagnostics().visible and flow.diagnostics().samples==2,"moving stern creates visible short flow within0.5s")
	var first_vertices:PackedVector3Array=flow._node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var width_xz:=Vector2(first_vertices[4].x-first_vertices[0].x,first_vertices[4].z-first_vertices[0].z).length()
	check(width_xz>=9.0*.6 and width_xz<=9.0*.75,"young flow occupies a readable fraction of actual hull beam, not hairline tracks")
	var grain_image:Image=flow._material.get_shader_parameter("source_texture").get_image()
	if grain_image.is_compressed():grain_image.decompress()
	var center_alpha:=0.0
	for row in grain_image.get_height():center_alpha+=grain_image.get_pixel(grain_image.get_width()/2,row).a
	center_alpha/=grain_image.get_height()
	check(center_alpha>0.1,"core grain has actual center coverage instead of the native dual-rail empty center")
	var first:Vector2=flow._samples[0].position
	var updates:int=flow.diagnostics().updates
	flow.apply_snapshot(target(Vector3(3000,20,0)),.125,water,Callable())
	check(flow.diagnostics().updates==updates and flow._samples[0].position==first,"same accepted time cannot duplicate or move history")
	var turn:=target(Vector3(.6,0,-.8));turn.forward=Vector3.RIGHT
	flow.apply_snapshot(turn,.25,water,Callable())
	check(flow._samples[0].position==first,"turn leaves old world-space births in place")
	var count:int=flow.diagnostics().samples
	turn.position.y=15.0;flow.apply_snapshot(turn,.5,water,Callable())
	check(flow.diagnostics().samples==count,"vertical heave does not emit horizontal travel")
	var arrays:Array=flow._node.mesh.surface_get_arrays(0)
	for vertex:Vector3 in arrays[Mesh.ARRAY_VERTEX]:check(vertex.is_finite() and absf(vertex.y-water(vertex.x,vertex.z,.5)-.08)<.00001,"carrier refits current accepted five-wave sampler")
	var invalid:=target(Vector3(NAN,0,0));flow.apply_snapshot(invalid,.6,water,Callable())
	check(flow.diagnostics().time==.5,"invalid packet is atomic")
	var stopped:=target(Vector3(.6,0,-.8),0.0);stopped.enabled=false
	flow.apply_snapshot(stopped,1.0,water,Callable());check(flow.diagnostics().samples==count and not flow.diagnostics().emitting,"stop does not spawn, old births retained")
	flow.apply_snapshot(stopped,13.0,water,Callable())
	var old_vertices:PackedVector3Array=flow._node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var old_width:=Vector2(old_vertices[4].x-old_vertices[0].x,old_vertices[4].z-old_vertices[0].z).length()
	check(old_width>=9.0*1.3 and old_width<=9.0*1.6,"aging wake diffuses across water instead of retaining thin parallel lines")
	flow.apply_snapshot(stopped,16.0,water,Callable());check(flow.diagnostics().samples==0 and not flow.diagnostics().visible,"stopped history fully expires within bounded lifetime")
	flow.dispose();flow=flow_script.new(owner)
	for i in 1200:flow.apply_snapshot(target(Vector3(0,0,-float(i)*.3125),10.0),i/32.0,water,Callable())
	check(flow.diagnostics().samples<=128 and flow.diagnostics().samples>50,"long voyage has bounded useful world history")
	flow.apply_snapshot(target(Vector3(3000,0,0),10.0),38.0,water,Callable())
	arrays=flow._node.mesh.surface_get_arrays(0)
	var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	var no_bridge:=true
	for i in range(0,indices.size(),3):no_bridge=no_bridge and vertices[indices[i]].distance_to(vertices[indices[i+1]])<100.0 and vertices[indices[i]].distance_to(vertices[indices[i+2]])<100.0
	check(no_bridge,"teleport cannot create an across-map triangle")
	flow.apply_snapshot(target(Vector3(3000,0,-.7)),38.125,water,func(_x,_z):return false)
	check(not flow.diagnostics().visible,"dry surface mask removes all submitted triangles")
	flow.apply_snapshot(target(Vector3.ZERO),1.0,water,Callable());check(flow.diagnostics().samples==1 and flow.diagnostics().time==1.0,"rewind starts fresh world history")
	var node_id:int=flow._node.get_instance_id();flow.dispose();flow.dispose()
	check(not is_instance_id_valid(node_id) and flow.diagnostics().samples==0,"dispose releases real mesh carrier idempotently")
	renderer.apply_snapshot(packet(1,.125),water,Callable())
	check(renderer._actors.ship.flow.diagnostics().visible,"candidate receives real owner accepted updates")
	check(not renderer._actors.ship.surface.nodes.SceneStrip.visible,"explicit candidate avoids double drawing original strip")
	var baseline:=packet(2,.25);baseline.ships[0].sourceWake.targetTrail.enabled=false
	renderer.apply_snapshot(baseline,water,Callable())
	check(renderer._actors.ship.flow==null and renderer._actors.ship.surface.nodes.SceneStrip.visible,"explicit disabled candidate restores actual source strip for baseline A/B")
	renderer.apply_snapshot(packet(3,.375,false),water,Callable())
	check(renderer._actors.ship.flow==null and renderer._actors.ship.history.updates==4,"removing target adapter releases candidate and preserves native history")
	renderer.dispose();owner.free();finish()
func finish()->void:
	print("WAKE_FLOW_TESTS assertions=",assertions," failures=",failures);quit(1 if failures else 0)
