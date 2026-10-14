extends SceneTree
const Prepared=preload("res://game/presentation/world/prepared_rigid_shadow.gd")
const Adapter=preload("res://game/presentation/world/target_rigid_shadow_caster.gd")
const Renderer=preload("res://modules/scene_engine/fidelity_fx/source_shadow_renderer.gd")
const Frame=preload("res://modules/scene_engine/fidelity_fx/prepared_shadow_frame.gd")
const Ship=preload("res://game/presentation/ships/ship_view.gd")
var assertions:=0
var failures:=0
class Actor extends Node3D:
	var model:Node3D
	func get_model()->Node3D:return model
func _initialize()->void:run.call_deferred()
func check(ok:bool,why:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL target shadow boundary: ",why)
func owner()->RefCounted:
	var path:="res://game/presentation/world/target_shadow_boundary.gd"
	return load(path).new() if ResourceLoader.exists(path) else Prepared.new()
func faces(indices:Array)->Array:
	var output:Array=[]
	for triangle:Array in indices:output.append({"indices":triangle,"normal":Vector3.BACK})
	return output
func preserves(actual:Dictionary,original:Dictionary)->bool:
	return actual.direction==original.direction and actual.positions.slice(0,original.positions.size())==original.positions and actual.indices.slice(0,original.indices.size())==original.indices
func ray_balance(volume:Dictionary)->int:
	var apex:=-1
	for i in volume.positions.size():
		var point:Array=volume.positions[i]
		if Vector3(point[0],point[1],point[2]).length()>1e8:apex=i;break
	if apex<0:return 0
	var balances:Dictionary={}
	for i in range(0,volume.indices.size(),3):
		if volume.indices[i+2]!=apex:continue
		for corner in 2:
			var p:Array=volume.positions[volume.indices[i+corner]]
			var key:=Vector3(p[0],p[1],p[2])
			balances[key]=int(balances.get(key,0))+(1 if corner==0 else -1)
	var total:=0
	for balance:int in balances.values():total+=absi(balance)
	return total
func fixtures()->void:
	var points:Array=[[0,0,0],[1,0,0],[0,1,0],[0,0,1]]
	for copies in [2,3,4]:
		var triangles:Array=[]
		for _i in copies:triangles.append([0,1,2])
		var source:=Prepared.new();source.configure(points,faces(triangles))
		var target:=owner();target.configure(points,faces(triangles))
		var original:Dictionary=source.build_volume([0,0,-1]);var actual:Dictionary=target.build_volume([0,0,-1])
		var added:int=actual.triangleCount-original.triangleCount
		check(added==6 if copies<4 else added==12,"same-direction multiplicity retained for "+str(copies)+" coincident faces")
		check(preserves(actual,original),"original index and vertex prefixes retained for multiplicity "+str(copies))
		check(ray_balance(actual)==0,"all appended apex rays balance for multiplicity "+str(copies))
		if copies%2==0:
			check(source.select_topology([0,0,-1]).edges.is_empty(),"even multiplicity fixture has zero original sides but nonempty caps")
			check(actual.positions.size()==original.positions.size()+1+2*added,"zero-side repair appends one apex after original cap vertices")
			if added>0:check(actual.indices[original.indices.size()+2]==original.positions.size(),"zero-side triangles refer to appended apex, preserving source index0")
	for triangles:Array in [[[0,1,2],[1,0,3]],[[0,2,1],[0,1,3],[1,2,3],[2,0,3]]]:
		var source:=Prepared.new();source.configure(points,faces(triangles))
		var target:=owner();target.configure(points,faces(triangles))
		check(target.build_volume([0,0,-1])==source.build_volume([0,0,-1]),"opposite shared edges and closed oriented mesh remain byte-equivalent")
	var source:=Prepared.new();source.configure(points,faces([[0,1,2],[0,1,3]]))
	var target:=owner();target.configure(points,faces([[0,1,2],[0,1,3]]))
	var original:Dictionary=source.build_volume([.1,.2,-1]);var first:Dictionary=target.build_volume([.1,.2,-1])
	var saved:=var_to_bytes(first)
	check(first.triangleCount==original.triangleCount+2 and ray_balance(original)==4 and ray_balance(first)==0,"two selected faces sharing one directed edge repair the exact two-ray defect")
	check(preserves(first,original),"existing-apex repair preserves every original vertex and triangle")
	var builds:int=target.diagnostics().get("boundaryBuilds",0)
	check(builds==1,"initial topology builds one boundary receipt")
	var second:Dictionary=target.build_volume([.100001,.2,-1])
	check(target.diagnostics().get("boundaryBuilds",0)==builds and is_same(first.indices,second.indices),"light changes with identical face signs reuse boundary topology and indices")
	check(second.positions[0]!=first.positions[0] and preserves(second,source.build_volume([.100001,.2,-1])),"every changed light preserves exact original f32 apex")
	check(var_to_bytes(first)==saved and first.is_read_only() and first.positions.is_read_only() and first.indices.is_read_only(),"older publication remains immutable after the next light")
	for point:Array in first.positions:check(point.is_read_only(),"published point arrays have no mutable holder")
	check(target.owns_volume(second) and is_same(target.build_volume([.100001,.2,-1]),second),"corrected current output is certified and exact repeated light reuses it")
	target.build_volume([0,0,1])
	check(target.diagnostics().get("boundaryBuilds",0)==builds+1 and target.diagnostics().get("addedSides",-1)==0,"face-sign change rebuilds receipt and clears obsolete additions")
	check(not target.owns_volume(second),"previous corrected volume cannot receive current-owner certificate")
	target.configure(points,faces([[0,1,2]]));target.build_volume([0,0,-1])
	check(target.diagnostics().get("boundaryBuilds",0)==1,"reconfigure releases old boundary caches")
func bounded()->void:
	var triangles:Array=[]
	for _i in 11000:triangles.append([0,1,2])
	var points:Array=[[0,0,0],[1,0,0],[0,1,0]]
	var source:=Prepared.new();source.configure(points,faces(triangles))
	var target:=owner();target.configure(points,faces(triangles))
	var actual:Dictionary=target.build_volume([0,0,-1])
	check(actual==source.build_volume([0,0,-1]) and actual.vertexCount<=65535,"out-of-scope repair retains complete bounded original geometry instead of dropping caster")
	check(not str(target.diagnostics().get("boundaryError","")).is_empty(),"bounded fallback exposes a repair diagnostic")
func real_mesh()->void:
	var ship:=Ship.new();root.add_child(ship);check(ship.configure("fuchuan"),"actual culprit model configures")
	var mesh:MeshInstance3D=ship.get_model().find_child("native_hull_56_component_03",true,false)
	var adapter:=Adapter.new();var geometry:Dictionary=adapter._mesh_geometry(mesh.mesh)
	var target:=owner();target.configure(geometry.positions,geometry.faces)
	var actual:Dictionary=target.build_volume([-.0372819900512695,.71451473236084,.698626399040222])
	check(actual.triangleCount==44 and ray_balance(actual)==0 and target.diagnostics().get("addedSides",0)==2,"generic helper fixes real imported defect with exactly two additional sides")
	adapter.dispose();ship.dispose();ship.free()
func production_seam()->void:
	var mesh:=ArrayMesh.new();var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2,0,1,2]);mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var actors:Dictionary={}
	for name:String in ["unrelated-alpha","another-beta"]:
		var actor:=Actor.new();root.add_child(actor);actor.model=Node3D.new();actor.add_child(actor.model)
		var part:=MeshInstance3D.new();part.name="generic-double";part.mesh=mesh;part.set_meta("target_rigid_shadow_caster",true);actor.model.add_child(part);actors[name]=actor
	var adapter:=Adapter.new();var renderer:=Renderer.new();var camera:=Camera3D.new();root.add_child(camera);renderer.configure(actors.values()[0],camera)
	var packet:Dictionary=adapter.compose({},actors,Vector3.BACK,false)
	renderer.apply_snapshot(packet.native,packet.actors)
	check(renderer.diagnostics().volumeCount==2,"production adapter retains both arbitrary named casters")
	for volume:Dictionary in renderer.get("_volumes").values():check(volume.geometry.triangleCount==8,"all target casters receive generic zero-side repair without identity filter")
	var frame:=Frame.new();check(frame.configure(renderer.get("_volumes").values()),"corrected owner satisfies existing immutable publication seam")
	for volume:Dictionary in frame.snapshot():check(is_same(volume.geometry,renderer.get("_volumes")[volume.id].geometry),"certified corrected geometry uses existing frozen fast path")
	check(adapter.diagnostics().get("boundaryBuilds",0)==2,"production diagnostics exposes exactly one build per unchanged topology")
	renderer.dispose();adapter.dispose();camera.free()
	for actor:Node3D in actors.values():actor.free()
func run()->void:
	fixtures();bounded();real_mesh();production_seam()
	print("TARGET_SHADOW_BOUNDARY_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
