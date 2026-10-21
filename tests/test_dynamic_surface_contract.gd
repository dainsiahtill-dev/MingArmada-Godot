extends SceneTree
const Source=preload("res://modules/scene_engine/fidelity_fx/presentation.gd")
var assertions:=0
var failures:=0
func check(ok:bool,message:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL dynamic surface: ",message)
func _initialize()->void:run.call_deferred()
func run()->void:
	var path:="res://modules/scene_engine/rendering/dynamic_surface_buffer.gd"
	check(ResourceLoader.exists(path),"particles and water share a dedicated public surface upload module")
	var source_script:Script=Source
	check(source_script.get_script_method_list().any(func(method:Dictionary):return method.name=="get_texture"),"source textures have a public cached query")
	if not ResourceLoader.exists(path):finish();return
	var buffer:Script=load(path)
	var uv:=PackedVector2Array([Vector2(.25,.5),Vector2(.75,1.0),Vector2.ZERO])
	var colors:=PackedColorArray([Color(.1,.2,.3,.4),Color(1.1,-.2,.5,1),Color.WHITE])
	check(buffer.attributes(uv,colors)==Source._surface_attributes(uv,colors),"shared byte packing preserves exact float32 UV/color quantization")
	var expected:=PackedByteArray([25,51,76,102,0,0,128,62,0,0,0,63,255,0,127,255,0,0,64,63,0,0,128,63,255,255,255,255,0,0,0,0,0,0,0,0])
	check(buffer.attributes(uv,colors)==expected,"independent literal oracle: UNORM8 clamping/truncation and little-endian float32 UV")
	var vertices:=PackedVector3Array([Vector3.ZERO,Vector3(1,0,0),Vector3(0,0,1)])
	check(buffer.bounds(vertices)==Source._local_bounds(vertices),"shared bounds preserve planar minimum extent")
	check(buffer.bounds(vertices)==AABB(Vector3.ZERO,Vector3(1,0.00001,1)),"planar bounds match independent expected minimum extent")
	var owner:=Node3D.new();root.add_child(owner)
	var carrier:=MeshInstance3D.new();owner.add_child(carrier)
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_COLOR]=colors;arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,2,1])
	var layout:Dictionary=buffer.submit(carrier,arrays,{},false)
	check(layout.vertex_count==3 and carrier.mesh.get_surface_count()==1,"shared submit owns one explicit surface")
	vertices[1].x=3.0;arrays[Mesh.ARRAY_VERTEX]=vertices
	layout=buffer.submit(carrier,arrays,layout,false)
	check(carrier.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]==vertices,"dummy renderer receives actual updated arrays")
	check(buffer.bounds(vertices).end.x==3.0,"changed vertex bounds remain conservative")
	owner.free();finish()
func finish()->void:
	print("DYNAMIC_SURFACE_CONTRACT_TESTS assertions=",assertions," failures=",failures);quit(1 if failures else 0)
