extends SceneTree
## Real Box03 bow mesh: add its source relief to the sampled water surface,
## while side foam stays planar and original topology/RGBA/UV remain intact.
const Froth=preload("res://modules/scene_engine/water/source_froth.gd")
const Compiler=preload("res://modules/scene_engine/fidelity_fx/cloud_render_compiler.gd")
const Surface=preload("res://modules/scene_engine/water/source_surface.gd")
const Math=preload("res://modules/scene_engine/fidelity_fx/native_particle_math.gd")
var assertions:=0
var failures:=0
var observations:Array=[]

func check(ok:bool,message:String)->bool:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL: ",message)
	return ok
func _initialize()->void:_run.call_deferred()
func _water(_x:float,_z:float,_time:float,offset:float)->float:return offset

func _mesh(froth:RefCounted,prefix:String)->MeshInstance3D:
	for node:Node in froth._container.get_children():
		if node is MeshInstance3D and str(node.name).begins_with(prefix):return node
	return null

func _case(parent:Node3D,offset:float)->Dictionary:
	var packet:={"sourcePosition":[0.0,0.0,0.0],"sourceBowPosition":[0.0,0.0,0.0],"sourceHeading":0.0,"modelScale":1.0,"sourceToWorld":0.02,"controllerAppTime":0.0,"enabled":true}
	var froth:=Froth.new();check(froth.configure(parent,3,17).ok,"real barque + common bow source configures")
	froth.apply_snapshot(packet,0.0,_water.bind(offset),Callable())
	var node:=_mesh(froth,"bow_")
	if not check(node!=null,"actual authored bow carrier exists"):froth.dispose();return {}
	var arrays:Array=node.mesh.surface_get_arrays(0)
	var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var uv:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
	var rgba:PackedColorArray=arrays[Mesh.ARRAY_COLOR]
	var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	var compiler:=Compiler.new()
	var graph:Dictionary=compiler.compile_asset(Froth.asset("fx_ship_bowfroth.nif"))
	var record:Dictionary=compiler.render_states(graph,0.0,Froth.outer(packet,true),true,{},true)[0]
	check(int(record.block)==82 and record.localVertices.size()==30 and record.triangles.size()==40,"source is the exact Box03 30-vertex/40-triangle mesh")
	check(vertices.size()==30 and indices.size()==120,"production retains complete original bow topology")
	var expected_colors:PackedColorArray=Compiler.authored_surface_colors(record)
	var anchor_array:Array=packet.sourceBowPosition
	var anchor:=Surface.native_to_world(anchor_array,float(packet.sourceToWorld))
	var original_min:=INF;var original_max:=-INF
	var rendered_min:=INF;var rendered_max:=-INF
	var opaque_min:=INF;var opaque_max:=-INF;var zero_alpha:=0
	for i in vertices.size():
		var original:Vector3=Surface.native_to_world(record.vertices[i],float(packet.sourceToWorld))
		var relief:float=original.y-anchor.y
		var rendered_relief:float=vertices[i].y-offset-0.10
		original_min=minf(original_min,relief);original_max=maxf(original_max,relief)
		rendered_min=minf(rendered_min,rendered_relief);rendered_max=maxf(rendered_max,rendered_relief)
		if expected_colors[i].a>=0.99:opaque_min=minf(opaque_min,relief);opaque_max=maxf(opaque_max,relief)
		if expected_colors[i].a==0.0:zero_alpha+=1
		check(absf(rendered_relief-relief)<0.00002,"water-fit preserves original relative height with ratio1 at bow vertex "+str(i))
		check(absf(vertices[i].x-original.x)<0.00002 and absf(vertices[i].z-original.z)<0.00002,"height fit preserves source X/Z")
		check(absf(rgba[i].a-expected_colors[i].a)<=1.0/255.0+0.00001 and absf(rgba[i].r-expected_colors[i].r)<=1.0/255.0+0.00001,"height fit leaves source vertex RGBA intact")
		var matrix:PackedFloat32Array=record.uvMatrix
		var texcoord:Dictionary=record.sourceUV[i]
		var expected_uv:=Vector2(Math.f32(matrix[0]*float(texcoord.u)+matrix[3]*float(texcoord.v)+matrix[6]),Math.f32(matrix[1]*float(texcoord.u)+matrix[4]*float(texcoord.v)+matrix[7]))
		check(uv[i]==expected_uv,"height fit leaves actual source-controlled UV intact")
	check(original_max-original_min>0.5,"actual source fixture has substantial relief, not a synthetic flat quad")
	check(rendered_max-rendered_min>0.5,"actual production mesh preserves substantial source relief")
	check(zero_alpha==18,"original transparent rim remains18 vertices")
	var side:=_mesh(froth,"side_")
	check(side!=null,"actual side foam carrier still exists")
	if side!=null:
		for vertex:Vector3 in side.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:check(absf(vertex.y-offset-0.10)<0.00002,"side foam retains its independent planar surface fit")
	var result:={"offset":offset,"sourceReliefMin":original_min,"sourceReliefMax":original_max,"sourceOpaqueReliefMin":opaque_min,"sourceOpaqueReliefMax":opaque_max,"renderedReliefMin":rendered_min,"renderedReliefMax":rendered_max,"vertices":vertices.duplicate(),"uvs":uv.duplicate(),"rgba":rgba.duplicate(),"transparentRimVertices":zero_alpha}
	observations.append(result);froth.dispose();return result

func _run()->void:
	var original_bytes:=FileAccess.get_file_as_bytes("res://assets/data/source_wake/fx_ship_bowfroth.nif.json")
	var parent:=Node3D.new();root.add_child(parent)
	var flat:=_case(parent,0.0)
	var raised:=_case(parent,3.0)
	if not flat.is_empty() and not raised.is_empty():
		check(flat.uvs==raised.uvs and flat.rgba==raised.rgba,"changing sampled water level never changes original UV/RGBA")
		for i in flat.vertices.size():
			check(absf(raised.vertices[i].y-flat.vertices[i].y-3.0)<0.00002,"water height offset translates bow relief intact")
	check(FileAccess.get_file_as_bytes("res://assets/data/source_wake/fx_ship_bowfroth.nif.json")==original_bytes,"original authored source asset remains unchanged")
	parent.free()
	for result:Dictionary in observations:
		result.erase("vertices");result.erase("uvs");result.erase("rgba")
	print("SOURCE_BOW_RELIEF_EVIDENCE ",JSON.stringify(observations))
	print("SOURCE_BOW_RELIEF_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
