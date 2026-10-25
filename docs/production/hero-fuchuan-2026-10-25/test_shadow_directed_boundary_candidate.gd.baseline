extends SceneTree
const Math=preload("res://modules/scene_engine/fidelity_fx/source_shadow_math.gd")
const Adapter=preload("res://game/presentation/world/target_rigid_shadow_caster.gd")
const Ship=preload("res://game/presentation/ships/ship_view.gd")
const Prepared=preload("res://game/presentation/world/prepared_rigid_shadow.gd")
var assertions:=0
var failures:=0
func check(ok:bool,label:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL directed boundary candidate: ",label)
func _initialize()->void:run.call_deferred()
func candidate_for(volume:Dictionary)->Dictionary:
	var path:="res://game/research/shadow_directed_boundary_candidate.gd"
	if not ResourceLoader.exists(path):return {"ok":true,"geometry":volume,"addedSides":0}
	return load(path).adapt(volume)
func apex_balance(volume:Dictionary)->int:
	var balances:Dictionary={}
	for offset in range(0,volume.indices.size(),3):
		if volume.indices[offset+2]!=0:continue
		for corner in 2:
			var point:Array=volume.positions[volume.indices[offset+corner]]
			var key:=Vector3(point[0],point[1],point[2]);balances[key]=int(balances.get(key,0))+(1 if corner==0 else -1)
	var result:=0
	for value:int in balances.values():result+=absi(value)
	return result
func run()->void:
	# Two selected faces share the SAME directed edge 0->1. The old parity
	# oracle erases both, opening the extrusion along both endpoint rays.
	var positions:Array=[[0,0,0],[1,0,0],[0,1,0],[0,0,1]]
	var caps:Array=[0,1,2,0,1,3];var edges:Array=[]
	for offset in [0,3]:
		for side in 3:Math.toggle_edge(edges,caps[offset+side],caps[offset+(side+1)%3])
	var original:Dictionary=Math.build_volume_component(positions,[0,0,-1],edges,caps)
	var original_bytes:=var_to_bytes(original)
	check(edges.size()==4 and apex_balance(original)==4,"actual legacy oracle exposes missing doubled shared side")
	var adapted:Dictionary=candidate_for(original)
	check(adapted.ok and adapted.addedSides==2,"same-direction edge retains multiplicity two")
	check(apex_balance(adapted.geometry)==0,"candidate closes both extrusion rays")
	check(adapted.geometry.indices.slice(0,original.indices.size())==original.indices and adapted.geometry.positions.slice(0,original.positions.size())==original.positions,"candidate preserves every original side, cap, vertex and apex")
	check(var_to_bytes(original)==original_bytes,"candidate does not mutate caller geometry")
	if adapted.addedSides>0:
		check(adapted.geometry.indices.slice(original.indices.size())==[16,15,0,18,17,0],"two added triangles have literal source side winding")
		check(adapted.geometry.positions.slice(original.positions.size())==[[0.0,0.0,0.0],[1.0,0.0,0.0],[0.0,0.0,0.0],[1.0,0.0,0.0]],"only missing shared edge endpoints are appended")
	var ordinary:Dictionary=Math.build_volume_component(positions,[0,0,-1],[[0,1],[1,2],[2,0]],[0,1,2])
	var kept:Dictionary=candidate_for(ordinary)
	check(kept.ok and kept.addedSides==0 and kept.geometry==ordinary,"valid directed triangle is byte-equivalent")
	var ship:=Ship.new();root.add_child(ship);check(ship.configure("fuchuan"),"actual imported barque fixture configures")
	var mesh:MeshInstance3D=ship.get_model().find_child("native_hull_56_component_03",true,false)
	var adapter:=Adapter.new();var source:Dictionary=adapter._mesh_geometry(mesh.mesh)
	var prepared:=Prepared.new();check(prepared.configure(source.positions,source.faces).ok,"actual culprit source prepares")
	var actual:Dictionary=prepared.build_volume([-0.0372819900512695,0.71451473236084,0.698626399040222])
	var actual_before:=var_to_bytes(actual);var result:Dictionary=candidate_for(actual)
	check(apex_balance(actual)==4,"actual24s culprit retains the two-ray defect")
	check(result.ok and result.addedSides==2 and apex_balance(result.geometry)==0,"actual24s culprit needs exactly two additional sides")
	check(actual.indices.size()/3==42 and result.geometry.indices.size()/3==44,"candidate retains42 original triangles and appends only2")
	check(var_to_bytes(actual)==actual_before and result.geometry.direction==actual.direction,"actual frozen source payload unchanged")
	if result.addedSides>0:
		var n:int=actual.positions.size()
		check(result.geometry.positions.slice(n)==[source.positions[4],source.positions[12],source.positions[4],source.positions[12]],"actual missing sides trace specifically to welded source edge4to12")
		check(result.geometry.is_read_only() and result.geometry.positions.is_read_only() and result.geometry.indices.is_read_only(),"candidate publishes immutable container ownership")
	print("SHADOW_DIRECTED_BOUNDARY_EVIDENCE sourceVertices=",source.positions.size()," sourceFaces=",source.faces.size()," sourceTriangles=",actual.indices.size()/3," addedSides=",result.addedSides," apexBalanceBefore=",apex_balance(actual)," apexBalanceAfter=",apex_balance(result.geometry))
	adapter.dispose();ship.dispose();ship.free()
	print("SHADOW_DIRECTED_BOUNDARY_CANDIDATE_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
