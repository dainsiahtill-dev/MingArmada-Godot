extends "res://game/presentation/world/prepared_rigid_shadow.gd"
## Target-only repair of the source parity boundary on nonmanifold hull meshes.
## Source triangles remain an exact prefix; no caster identity or shader policy.
var _boundary_ready:=false
var _boundary_topology:Array=[]
var _boundary_base:Array=[]
var _boundary_indices:Array=[]
var _boundary_source_volume:Dictionary={}
var _boundary_volume:Dictionary={}
var _boundary_builds:=0
var _boundary_error:=""
var _added_sides:=0
var _apex_index:=-1
var _apex_anchor:Array=[]

func configure(positions:Array,faces:Array)->Dictionary:
	var result:=super.configure(positions,faces)
	if not result.ok:return result
	_boundary_ready=false;_boundary_topology=[];_boundary_base=[];_boundary_indices=[]
	_boundary_source_volume={};_boundary_volume={};_boundary_builds=0;_boundary_error=""
	_added_sides=0;_apex_index=-1;_apex_anchor=[]
	return result

static func _accumulate(residual:Dictionary,a:int,b:int,weight:int)->void:
	if a==b:return
	var key:int=(mini(a,b)<<16)|maxi(a,b)
	residual[key]=int(residual.get(key,0))+weight*(1 if a<b else -1)

func _prepare_boundary(original:Dictionary)->void:
	_boundary_builds+=1;_boundary_error="";_added_sides=0
	_boundary_base=[];_boundary_indices=[];_apex_index=-1;_apex_anchor=[]
	var residual:Dictionary={}
	for offset in range(0,_caps.size(),3):
		for side in 3:_accumulate(residual,_caps[offset+side],_caps[offset+(side+1)%3],1)
	for edge:Array in _edges:_accumulate(residual,edge[0],edge[1],-1)
	var missing:Array=[];var count:=0
	for key:int in residual:
		var balance:int=residual[key]
		if balance==0:continue
		var a:int=key>>16;var b:int=key&65535
		missing.append({"a":a if balance>0 else b,"b":b if balance>0 else a,"count":absi(balance)})
		count+=absi(balance)
	if count==0:return
	var append_apex:=_edges.is_empty()
	if original.positions.size()+2*count+int(append_apex)>65535:
		# Keep the full original caster visible; never truncate or silently drop
		# it to fit a repair. The target adapter exposes this unresolved limit.
		_boundary_error="directed boundary repair exceeds uint16 volume scope"
		return
	_boundary_base=original.positions.duplicate(false);_boundary_indices=original.indices.duplicate()
	_apex_index=_boundary_base.size() if append_apex else 0
	_apex_anchor=_source[missing[0].a]
	if append_apex:_boundary_base.append([])
	for edge:Dictionary in missing:
		for _repeat in edge.count:
			var first:=_boundary_base.size()
			_boundary_base.append(_source[edge.a]);_boundary_base.append(_source[edge.b])
			_boundary_indices.append_array([first+1,first,_apex_index])
	_boundary_base.make_read_only();_boundary_indices.make_read_only();_added_sides=count

func build_volume(local_light:Array)->Dictionary:
	var original:=super.build_volume(local_light)
	if original.has("error"):return original
	# Original Prepared owns immutable indices for one exact face-sign pattern.
	# Direction/apex changes do not cause another global edge/cap scan.
	if not _boundary_ready or not is_same(_boundary_topology,original.indices):
		_prepare_boundary(original);_boundary_topology=original.indices;_boundary_ready=true
	if _added_sides==0:
		_boundary_source_volume=original;_boundary_volume=original
		return original
	if is_same(_boundary_source_volume,original):return _boundary_volume
	var points:=_boundary_base.duplicate(false)
	if _apex_index==0:
		points[0]=original.positions[0]
	else:
		var apex:Array=[]
		for axis in 3:apex.append(Math.f32(original.direction[axis]+_apex_anchor[axis]))
		apex.make_read_only();points[_apex_index]=apex
	points.make_read_only()
	var result:=original.duplicate(false)
	result.positions=points;result.indices=_boundary_indices
	result.vertexCount=points.size();result.triangleCount=_boundary_indices.size()/3
	result.make_read_only();_boundary_source_volume=original;_boundary_volume=result
	return result

func owns_volume(volume:Dictionary)->bool:
	return is_same(volume,_boundary_volume) and super.owns_volume(_boundary_source_volume)

func diagnostics()->Dictionary:
	var result:=super.diagnostics()
	result.boundaryBuilds=_boundary_builds;result.addedSides=_added_sides;result.boundaryError=_boundary_error
	return result
