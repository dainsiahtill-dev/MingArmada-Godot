extends RefCounted
## Distinct original bowfroth + family sidefroth, source controllers/pools intact.
const Compiler=preload("res://modules/scene_engine/fidelity_fx/cloud_render_compiler.gd")
const Runtime=preload("res://modules/scene_engine/fidelity_fx/particle_runtime.gd")
const Math=preload("res://modules/scene_engine/fidelity_fx/native_particle_math.gd")
const Surface=preload("res://modules/scene_engine/water/source_surface.gd")
const FAMILIES:=["sloop","brigantine","frigate","barque","fluyt","merchantman","treasuregalleon","fast_galleon","tartane"]
var _compiler:=Compiler.new()
var _side:Dictionary={}
var _bow:Dictionary={}
var _particles:RefCounted
var _surface:RefCounted
var _container:Node3D
var _last_time:Variant=null
var _mesh_count:=0
var _side_uv:Variant=null
var _error:=""
var _packet:Dictionary={}
var _last_camera:Dictionary={}
var _last_accepted_time:=-1.0
var _last_sea:Callable
var _authored_keys:Dictionary={}

static func asset(name:String)->Dictionary:return JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/source_wake/"+name+".json"))
func configure(parent:Node3D,family:int,seed:int,source_resource_name:String="")->Dictionary:
	dispose()
	var family_name:=""
	if not source_resource_name.is_empty():
		for name:String in FAMILIES:
			if source_resource_name=="fx_ship_sidefroth_"+name+".nif":family_name=name;break
	elif family>=0 and family<FAMILIES.size():family_name=FAMILIES[family]
	if family_name.is_empty():return {"ok":false,"error":"Explicit source sidefroth resource name or target family enum required"}
	_container=Node3D.new();_container.name="AuthoredFroth";parent.add_child(_container);_surface=Surface.new(_container)
	var bow_asset:=asset("fx_ship_bowfroth.nif");_bow=_compiler.compile_asset(bow_asset);_side=_compiler.compile_asset(asset("fx_ship_sidefroth_"+family_name+".nif"))
	var runtime:=Runtime.new()
	if not runtime.configure(bow_asset,seed,false):_error=runtime.get_last_error();return {"ok":false,"error":_error}
	_particles=runtime.spawn_native(seed)
	return {"ok":true,"family":family_name,"native_equivalent":false,"unresolved":["native type%9 name/index mapping","475550 birth gate/full lifecycle","DX9/Godot pixels"]}

static func outer(packet:Dictionary,bow:bool)->Dictionary:
	var heading:=float(packet.get("sourceHeading",0.0));var c:=cos(heading);var s:=sin(heading)
	# 475550 submits both templates at the same Dummy_bowfroth world position.
	# A root-position side override is a separately declared target policy.
	var bow_position:Array=packet.get("sourceBowPosition",packet.sourcePosition)
	var position:Array=bow_position if bow else packet.get("sourceSidePosition",bow_position)
	return {"rotation":packet.get("sourceRotation",[c,-s,0.0,s,c,0.0,0.0,0.0,1.0]),"translation":position,"scale":float(packet.get("bowScale" if bow else "sideScale",packet.modelScale))}

func apply_snapshot(packet:Dictionary,accepted_time:float,water:Callable,sea:Callable)->void:
	if _particles==null:return
	var now:=float(packet.get("controllerAppTime",accepted_time))
	if not is_finite(now) or now<0.0 or (_last_time!=null and now<float(_last_time)):return
	_packet=packet.duplicate(true)
	_last_accepted_time=accepted_time;_last_sea=sea
	# Target sailing birth gate, not a recovered 475550 lifecycle rule. Keep
	# source time and surviving world-space droplets alive when the hull stops.
	var enabled:=bool(packet.get("enabled",true));_container.visible=true
	if _last_time!=now:
		_particles.set_source_outer(outer(packet,true));_particles.advance_native(now,false,enabled);_last_time=now
	var used:Dictionary={};_mesh_count=0;_authored_keys.clear()
	for kind:String in ["bow","side"]:
		if not enabled:continue
		var graph:Dictionary=_bow if kind=="bow" else _side
		var states:Array=_compiler.render_states(graph,now,outer(packet,kind=="bow"),true,{},true,false,true)
		for record:Dictionary in states:
			var controlled:Array=[];var matrix:PackedFloat32Array=record.uvMatrix
			for uv:Dictionary in record.sourceUV:controlled.append([Math.f32(matrix[0]*float(uv.u)+matrix[3]*float(uv.v)+matrix[6]),Math.f32(matrix[1]*float(uv.u)+matrix[4]*float(uv.v)+matrix[7])])
			record.uvs=controlled
			var key:=kind+"_"+str(record.block);_draw_record(key,record,packet,accepted_time,water,sea,true);used[key]=true;_authored_keys[key]=true;_mesh_count+=1
			if kind=="side":_side_uv=record.uvMatrix.duplicate()
	# Native camera basis must be provided by the scene adapter. A finite top
	# view fallback is explicitly target presentation only, never native evidence.
	var camera:Dictionary=packet.get("sourceCamera",{"right":[1.0,0.0,0.0],"up":[0.0,1.0,0.0],"direction":[0.0,0.0,-1.0]})
	used.merge(_draw_particles(packet,accepted_time,sea,camera));_last_camera=camera.duplicate(true)
	_surface.hide_unused(used)

func redraw_camera(camera:Dictionary)->void:
	# Pure rendering from last accepted source state. No history, clock advance,
	# native birth/pool/RNG work or authored water-fit/upload on camera changes.
	if _particles==null or _last_time==null or camera==_last_camera:return
	var used:=_authored_keys.duplicate()
	used.merge(_draw_particles(_packet,_last_accepted_time,_last_sea,camera))
	_last_camera=camera.duplicate(true);_surface.hide_unused(used)

func _draw_particles(packet:Dictionary,accepted_time:float,sea:Callable,camera:Dictionary)->Dictionary:
	var used:Dictionary={}
	for original:Dictionary in _particles.batch_meshes(camera):
		if original.get("kind","")!="particle system":continue
		var record:=original.duplicate();var transformed:Array=[];var batch:RefCounted=record.batch
		var controlled:Array=[];var triangles:Array=[];var vertex_colors:Array=[]
		for i in batch.vertex_count:
			var point:Vector3=batch.vertices[i]
			transformed.append(Math.point(record.world,[point.x,point.y,point.z]))
			controlled.append([batch.uvs[i].x,batch.uvs[i].y]);vertex_colors.append(batch.colors[i])
		for i in range(0,batch.index_count,3):triangles.append([batch.indices[i],batch.indices[i+1],batch.indices[i+2]])
		record.vertices=transformed;record.uvs=controlled;record.triangles=triangles;record.vertex_colors=vertex_colors
		var key:="ParticleSystem_"+str(record.block)
		_draw_record(key,record,packet,accepted_time,Callable(),sea,false);used[key]=true
	return used

func _draw_record(key:String,record:Dictionary,packet:Dictionary,time:float,water:Callable,sea:Callable,fit:bool)->void:
	var units:=float(packet.sourceToWorld);var origin_array:Array=packet.get("worldOrigin",[0.0,0.0,0.0]);var origin:=Vector3(origin_array[0],origin_array[1],origin_array[2])
	var vertices:=PackedVector3Array();var uvs:=PackedVector2Array();var colors:=PackedColorArray();var indices:=PackedInt32Array();var wet:Array=[]
	var color:Array=record.get("color",[1.0,1.0,1.0]);var alpha:=float(record.get("alpha",1.0))
	var authored_colors:PackedColorArray=Compiler.authored_surface_colors(record) if record.has("localVertices") else PackedColorArray()
	for i in record.vertices.size():
		var p:=Surface.native_to_world(record.vertices[i],units,origin)
		if fit and water.is_valid():
			var height:=float(water.call(p.x,p.z,time))
			if is_finite(height):p.y=height+0.10
		vertices.append(p);wet.append(not sea.is_valid() or bool(sea.call(p.x,p.z)))
		uvs.append(Vector2(record.uvs[i][0],record.uvs[i][1]))
		if record.has("vertex_colors"):colors.append(record.vertex_colors[i])
		elif not authored_colors.is_empty():colors.append(authored_colors[i])
		else:colors.append(Color(color[0],color[1],color[2],alpha))
	for triangle:Array in record.triangles:
		if wet[int(triangle[0])] and wet[int(triangle[1])] and wet[int(triangle[2])]:indices.append_array(PackedInt32Array([int(triangle[0]),int(triangle[2]),int(triangle[1])]))
	_surface.submit(key,vertices,uvs,colors,indices,record)

func diagnostics()->Dictionary:
	var particles:Dictionary=_particles.diagnostics() if _particles!=null else {}
	return {"authored_meshes":_mesh_count,"particle_systems":particles.get("systems",0),"native_births":particles.get("births",0),"side_uv":_side_uv,"error":_error,"native_equivalent":false,"adaptations":["water_surface_fit","sea_triangle_clip","target_attachment/lifecycle","finite_camera_fallback"],"region_uploads":_surface.region_uploads if _surface!=null else 0}
func dispose()->void:
	if _surface!=null:_surface.dispose()
	if is_instance_valid(_container):_container.free()
	_surface=null;_container=null;_particles=null;_side.clear();_bow.clear();_last_time=null;_mesh_count=0;_side_uv=null;_last_camera.clear();_authored_keys.clear();_packet.clear();_last_accepted_time=-1.0;_last_sea=Callable()
