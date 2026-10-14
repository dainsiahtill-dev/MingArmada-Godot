extends RefCounted
## Immutable target-rigid source data. Exact source Math remains the generic oracle.
const Math = preload("res://modules/scene_engine/fidelity_fx/source_shadow_math.gd")
var _source:Array=[]
var _normals:=PackedVector3Array()
var _triangles:Array=[]
var _mask:=PackedByteArray()
var _light:Array=[]
var _edges:Array=[]
var _caps:Array=[]
var _base_positions:Array=[]
var _indices:Array=[]
var _last_volume:Dictionary={}
var _last_light:Array=[]
var _configured:=false
var _topology_ready:=false
var _topology_builds:=0
var _classifications:=0
var _volume_builds:=0

static func toggle_edge(edges:Array,lookup:Dictionary,a:int,b:int)->void:
	a=a&65535;b=b&65535
	var key:int=(mini(a,b)<<16)|maxi(a,b)
	if lookup.has(key):
		var index:int=lookup[key];var last:=edges.size()-1
		if index!=last:
			var moved:Array=edges[last];edges[index]=moved
			lookup[(mini(moved[0],moved[1])<<16)|maxi(moved[0],moved[1])]=index
		edges.pop_back();lookup.erase(key)
	else:lookup[key]=edges.size();edges.append([a,b])

func configure(positions:Array,faces:Array)->Dictionary:
	var source:Array=[];var triangles:Array=[];var normals:=PackedVector3Array()
	if positions.size()>=32768:return {"ok":false,"reason":"rigid geometry exceeds signed edge index scope"}
	for point in positions:
		if not point is Array or point.size()!=3:return {"ok":false,"reason":"native dimensions required"}
		var converted:Array=[]
		for component in point:
			if not (component is float or component is int) or not is_finite(float(component)) or not is_finite(Math.f32(float(component))):return {"ok":false,"reason":"finite positions required"}
			converted.append(Math.f32(float(component)))
		converted.make_read_only();source.append(converted)
	for face in faces:
		if not face is Dictionary or not face.get("normal") is Vector3 or not face.normal.is_finite() or not face.get("indices") is Array or face.indices.size()!=3:return {"ok":false,"reason":"rigid triangle required"}
		var triangle:Array=[]
		for index in face.indices:
			if not index is int or index<0 or index>=source.size():return {"ok":false,"reason":"finite signed edge index required"}
			triangle.append(index)
		triangle.make_read_only();triangles.append(triangle);normals.append(face.normal)
	source.make_read_only();triangles.make_read_only()
	_source=source;_triangles=triangles;_normals=normals;_configured=true
	_topology_ready=false;_mask=PackedByteArray();_light=[];_edges=[];_caps=[];_base_positions=[];_indices=[];_last_volume={};_last_light=[]
	_topology_builds=0;_classifications=0;_volume_builds=0
	return {"ok":true}

func select_topology(local_light:Array)->Dictionary:
	if not _configured:return {"error":"unconfigured rigid source"}
	if local_light.size()!=3:return {"error":"native dimensions required"}
	for component in local_light:
		if not (component is float or component is int) or not is_finite(float(component)) or not is_finite(Math.f32(Math.f32(float(component))*Math.EXTRUSION)):return {"error":"finite direction required"}
	if _topology_ready and local_light==_light:return {"edges":_edges,"caps":_caps}
	var direction:=Vector3(local_light[0],local_light[1],local_light[2])
	var mask:=PackedByteArray();mask.resize(_normals.size())
	for i in _normals.size():mask[i]=int(_normals[i].dot(direction)<0.0)
	_classifications+=1
	if not _topology_ready or mask!=_mask:
		var edges:Array=[];var caps:Array=[];var lookup:Dictionary={}
		for i in _triangles.size():
			if mask[i]==0:continue
			var triangle:Array=_triangles[i];caps.append_array(triangle)
			for side in 3:toggle_edge(edges,lookup,triangle[side],triangle[(side+1)%3])
		if 1+2*edges.size()+caps.size()>65535:return {"error":"volume exceeds uint16 scope"}
		var points:Array=[];var indices:Array=[]
		if not edges.is_empty():points.append([])
		for edge:Array in edges:
			var n:=points.size();indices.append_array([n+1,n,0]);points.append(_source[edge[0]]);points.append(_source[edge[1]])
		for i in range(0,caps.size(),3):
			var n:=points.size();indices.append_array([n+2,n+1,n])
			for j in 3:points.append(_source[caps[i+j]])
		for edge:Array in edges:edge.make_read_only()
		edges.make_read_only();caps.make_read_only();points.make_read_only();indices.make_read_only()
		_edges=edges;_caps=caps;_base_positions=points;_indices=indices;_mask=mask;_topology_ready=true;_topology_builds+=1
	_light=local_light.duplicate();_light.make_read_only()
	return {"edges":_edges,"caps":_caps}

func build_volume(local_light:Array)->Dictionary:
	var topology:=select_topology(local_light)
	if topology.has("error"):return topology
	if not _last_volume.is_empty() and _last_light==local_light:return _last_volume
	var direction:Array=[]
	for component in local_light:direction.append(Math.f32(Math.f32(float(component))*Math.EXTRUSION))
	var output:Array=_base_positions.duplicate(false)
	if not _edges.is_empty():
		var first:Array=_source[_edges[0][0]]
		var apex:Array=[Math.f32(direction[0]+first[0]),Math.f32(direction[1]+first[1]),Math.f32(direction[2]+first[2])]
		apex.make_read_only();output[0]=apex
	direction.make_read_only();output.make_read_only()
	var result:={"direction":direction,"positions":output,"indices":_indices,"vertexCount":output.size(),"triangleCount":_edges.size()+_caps.size()/3}
	result.make_read_only();_last_volume=result;_last_light=_light;_volume_builds+=1
	return result

func source_positions()->Array:return _source
func matches(caster:Dictionary)->bool:
	return not caster.get("skinned",false) and is_same(caster.get("positions"),_source) and is_same(caster.get("edges"),_edges) and is_same(caster.get("capIndices"),_caps) and caster.get("localLight")==_light
func owns_volume(volume:Dictionary)->bool:return is_same(volume,_last_volume)
func diagnostics()->Dictionary:return {"sourceVertices":_source.size(),"faces":_normals.size(),"classifications":_classifications,"topologyBuilds":_topology_builds,"volumeBuilds":_volume_builds}
