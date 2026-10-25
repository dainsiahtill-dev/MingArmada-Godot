extends SceneTree
## Ordered target edge cancellation must exactly match unchanged native math.
const Adapter=preload("res://game/presentation/world/target_rigid_shadow_caster.gd")
const Math=preload("res://modules/scene_engine/fidelity_fx/source_shadow_math.gd")
const Ship=preload("res://game/presentation/ships/ship_view.gd")
class RigidActor extends Node3D:
	var model:Node3D
	func get_model()->Node3D:return model
var assertions:=0
var failures:=0
var caster_checks:=0
var volume_vertices:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,message:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL target rigid edges: ",message)
func compare_sequence(adapter:RefCounted,sequence:Array,label:String)->void:
	var actual:Array=[];var oracle:Array=[];var lookup:Dictionary={}
	for step in sequence.size():
		var edge:Array=sequence[step]
		Math.toggle_edge(oracle,edge[0],edge[1])
		adapter.call("_toggle_indexed_edge",actual,lookup,edge[0],edge[1])
		check(actual==oracle,label+" ordered orientation/parity/swap-pop at "+str(step))
		var mapped:=lookup.size()==actual.size()
		for i in actual.size():
			var a:int=actual[i][0];var b:int=actual[i][1]
			# Independent integer encoding; no float hash or implementation helper.
			var key:int=mini(a,b)*65536+maxi(a,b)
			mapped=mapped and lookup.get(key,-1)==i
		check(mapped,label+" moved-last-edge lookup remains correct at "+str(step))
func compare_packet(adapter:RefCounted,packet:Dictionary,label:String)->void:
	for caster:Dictionary in packet.native.sourceShadows.casters:
		var mesh:MeshInstance3D=packet.actors[caster.actorId]
		var geometry:Dictionary=adapter._mesh_geometry(mesh.get_meta("target_shadow_geometry",mesh.mesh))
		var light:=Vector3(caster.localLight[0],caster.localLight[1],caster.localLight[2])
		var edges:Array=[];var caps:Array=[]
		for face:Dictionary in geometry.faces:
			if face.normal.dot(light)>=0.0:continue
			caps.append_array(face.indices)
			for i in 3:Math.toggle_edge(edges,face.indices[i],face.indices[(i+1)%3])
		check(caster.edges==edges,label+" exact ordered edge list "+caster.id)
		check(caster.capIndices==caps,label+" exact ordered cap list "+caster.id)
		var actual:Dictionary=Math.build_volume_component(caster.positions,caster.localLight,caster.edges,caster.capIndices)
		var oracle:Dictionary=Math.build_volume_component(geometry.positions,caster.localLight,edges,caps)
		check(not actual.has("error") and actual==oracle,label+" exact source volume positions/indices/direction/counts "+caster.id)
		if not actual.has("error"):volume_vertices+=int(actual.vertexCount)
		caster_checks+=1
func real_ships()->void:
	var adapter:=Adapter.new();var ships:Dictionary={}
	for kind:String in ["fuchuan","merchant","fisherman"]:
		var ship:=Ship.new();root.add_child(ship);check(ship.configure(kind),"actual ship configures "+kind);ships[kind]=ship
	for frame in 4:
		for kind:String in ships:
			var ship:Node3D=ships[kind]
			ship.set_lod_distance(230.0 if kind=="merchant" and frame>=2 else 50.0)
			ship.apply_snapshot({"time":float(frame)/60.0,"position":{"x":float(frame),"y":sin(float(frame))*.4,"z":2.0},"heading":.45+float(frame)*.003,"pitch":.012*float(frame),"heel":-.018*float(frame),"sailDeployment":1.0,"sailAngle":.8,"hull":100.0},{},0.0)
		var light:=Vector3(.35+float(frame)*.001,-.8,.5).normalized()
		var packet:Dictionary=adapter.compose({},ships,light,false,true)
		check(packet.native.sourceShadows.casters.size()>0,"three real ships keep actual caster population")
		compare_packet(adapter,packet,"real frame"+str(frame))
	# Removal/reappearance must not leave an edge index associated with an old part.
	var packet:Dictionary=adapter.compose({}, {"fuchuan":ships.fuchuan},Vector3.DOWN,false,true)
	compare_packet(adapter,packet,"real removal")
	packet=adapter.compose({},ships,Vector3(.2,-.9,.4).normalized(),false,true)
	compare_packet(adapter,packet,"real reappearance")
	adapter.dispose()
	for ship:Node3D in ships.values():ship.dispose();ship.free()
func large_mesh()->void:
	var actor:=RigidActor.new();root.add_child(actor);actor.model=Node3D.new();actor.add_child(actor.model)
	var mesh:=ArrayMesh.new();var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);var vertices:=PackedVector3Array();var indices:=PackedInt32Array()
	for i in 2048:
		var point:=Vector3(float(i)*2.0,0.0,0.0)
		vertices.append_array(PackedVector3Array([point,point+Vector3.UP,point+Vector3.FORWARD]))
		indices.append_array(PackedInt32Array([i*3,i*3+1,i*3+2]))
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_INDEX]=indices;mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var node:=MeshInstance3D.new();node.name="disjoint_large";node.mesh=mesh;node.set_meta("target_rigid_shadow_caster",true);actor.model.add_child(node)
	var adapter:=Adapter.new();var packet:Dictionary=adapter.compose({}, {"large":actor},Vector3.LEFT,false,true)
	check(packet.native.sourceShadows.casters.size()==1,"large finite actual mesh registers one caster")
	if packet.native.sourceShadows.casters.size()==1:
		check(packet.native.sourceShadows.casters[0].edges.size()==6144,"large disjoint triangles retain every oriented edge")
		compare_packet(adapter,packet,"large2048")
	adapter.dispose();actor.free()
func run()->void:
	var adapter:=Adapter.new()
	if check_index_api(adapter):
		compare_sequence(adapter,[[0,1],[1,2],[2,3],[3,4],[1,0],[4,3],[2,1],[0,1],[1,0],[0,1],[3,2],[4,5],[5,4]],"cancellation")
		compare_sequence(adapter,[[0,65535],[-1,0],[65536,1],[1,0],[32767,32768],[32768,32767],[-32768,1],[1,32768]],"uint16 aliases")
		var rng:=RandomNumberGenerator.new();rng.seed=9713
		var sequence:Array=[]
		for i in 2048:
			var a:=rng.randi_range(0,63);var b:=rng.randi_range(0,63)
			sequence.append([a,b] if i%3 else [b,a])
		compare_sequence(adapter,sequence,"seeded2048")
	adapter.dispose();real_ships();large_mesh()
	print("TARGET_RIGID_SHADOW_EDGES_EVIDENCE casters=",caster_checks," comparedVolumeVertices=",volume_vertices)
	print("TARGET_RIGID_SHADOW_EDGES_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
func check_index_api(adapter:RefCounted)->bool:
	var present:=adapter.has_method("_toggle_indexed_edge")
	check(present,"target cancellation uses indexed lookup while preserving native edge sequence")
	return present
