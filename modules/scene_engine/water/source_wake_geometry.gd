extends RefCounted
## Finite 4DFD30 geometry from the 2026-10-13 native continuation.
## Binary32 stores are retained; ordinary Godot arithmetic is not x87 bit equivalence.
## Water fitting and sea clipping are presentation adapters outside source math.
const Surface=preload("res://modules/scene_engine/water/source_surface.gd")
const Segment=preload("res://modules/scene_engine/water/source_segment_intersection.gd")
const STATE_KEY:="source_wake_geometry_state"
const CAPACITY:=62

static func _f32(value:float)->float:return PackedFloat32Array([value])[0]
static func _state(history:RefCounted)->Dictionary:
	if history.has_meta(STATE_KEY):return history.get_meta(STATE_KEY)
	var vertices:=PackedVector3Array();vertices.resize(CAPACITY)
	var uvs:=PackedVector2Array();uvs.resize(CAPACITY)
	var colors:=PackedColorArray();colors.resize(CAPACITY)
	# Empty target buffers are not a claimed original constructor recovery.
	# Inactive UVs retain these values until an accepted active row writes them.
	for i in CAPACITY:colors[i]=Color.WHITE;uvs[i]=Vector2(float(i%2),0.0)
	var out:Dictionary={"native_vertices":vertices,"native_uvs":uvs,"native_colors":colors}
	history.set_meta(STATE_KEY,out)
	return out

static func _normal(value:Vector3)->Vector3:
	var length:=sqrt(float(value.x)*float(value.x)+float(value.y)*float(value.y)+float(value.z)*float(value.z))
	if not is_finite(length) or length<=_f32(0.000001):return Vector3.ZERO
	var inverse:=1.0/length
	return Vector3(_f32(float(value.x)*inverse),_f32(float(value.y)*inverse),_f32(float(value.z)*inverse))

static func _repair(vertices:PackedVector3Array)->int:
	var repaired:=0
	for row in range(1,30):
		# Original first segment is degenerate, and its anchor is cached before
		# the inner loop. This is not a general width-edge intersection test.
		var anchor:=Vector2(vertices[row*2].x,vertices[row*2].y)
		for candidate in range(row+1,mini(row+4,30)):
			var c:=Vector2(vertices[candidate*2].x,vertices[candidate*2].y)
			var d:=Vector2(vertices[candidate*2+1].x,vertices[candidate*2+1].y)
			var intersection:Dictionary=Segment.intersect(anchor,anchor,c,d)
			if not intersection.hit:continue
			var point:Vector2=intersection.point
			var dc:=Vector2(_f32(float(c.x)-point.x),_f32(float(c.y)-point.y))
			var dd:=Vector2(_f32(float(d.x)-point.x),_f32(float(d.y)-point.y))
			var right_distance:=float(dd.x)*dd.x+float(dd.y)*dd.y
			var left_distance:=float(dc.x)*dc.x+float(dc.y)*dc.y
			if right_distance<=left_distance:vertices[row*2+1]=vertices[row*2-1]
			else:vertices[row*2]=vertices[row*2-2]
			repaired+=1
	return repaired

static func _result(state:Dictionary,packet:Dictionary,time:float,water:Callable,sea:Callable,count:int,repairs:int,rejected:String="")->Dictionary:
	var vertices:=PackedVector3Array();var wet:=PackedByteArray();wet.resize(CAPACITY)
	var unit:=float(packet.sourceToWorld)
	var origin_array:Array=packet.get("worldOrigin",[0.0,0.0,0.0])
	var origin:=Vector3(origin_array[0],origin_array[1],origin_array[2])
	for i in CAPACITY:
		var native:Vector3=state.native_vertices[i]
		var p:=Surface.native_to_world([native.x,native.y,native.z],unit,origin)
		if i<count and rejected.is_empty():
			if water.is_valid():
				var height:=float(water.call(p.x,p.z,time))
				if is_finite(height):p.y=height+0.10
			wet[i]=1 if not sea.is_valid() or bool(sea.call(p.x,p.z)) else 0
		vertices.append(p)
	var indices:=PackedInt32Array()
	if rejected.is_empty():
		for row in range(int(count/2)-1):
			var a:=row*2;var b:=a+2
			if wet[a] and wet[b] and wet[a+1]:indices.append_array(PackedInt32Array([a,a+1,b]))
			if wet[a+1] and wet[b] and wet[b+1]:indices.append_array(PackedInt32Array([a+1,b+1,b]))
	return {"vertices":vertices,"uvs":state.native_uvs.duplicate(),"colors":state.native_colors.duplicate(),"indices":indices,"native_vertices":state.native_vertices.duplicate(),"native_equivalent":false,"finite_source_geometry":rejected.is_empty(),"finite_tangent_guard":false,"cross_repairs":repairs,"draw_vertex_count":count,"source_buffer_capacity":CAPACITY,"gpu_rejected":rejected,"precision":"Godot arithmetic with binary32 stores, not x87 bit equivalence","adaptations":["empty target initial buffers","zero-total/nonfinite GPU rejection","water_surface_fit","sea_triangle_clip"],"unresolved":["original geometry constructor/initial buffers","x87 midpoint rounding","original CRT NaN domain","DX9 draw/pixels"]}

static func build(history:RefCounted,packet:Dictionary,time:float,water:Callable,sea:Callable)->Dictionary:
	var state:=_state(history)
	var current_array:Array=packet.get("sourcePosition",history.points[history.head].p)
	var current:=Vector3(_f32(current_array[0]),_f32(current_array[1]),_f32(current_array[2]))
	var head_array:Array=history.points[history.head].p
	var head_position:=Vector3(head_array[0],head_array[1],head_array[2])
	var delta:=current-head_position
	var head_offset:=_f32(sqrt(float(delta.z)*delta.z+float(delta.x)*delta.x+float(delta.y)*delta.y))
	var denominator:=float(history.total)+head_offset
	var draw_count:=mini(58,maxi(0,int(history.vertex_count)))
	# The original first accepted sample can produce NaN geometry under the
	# declared CRT oracle. Never send that unverified domain to the Godot GPU.
	if not current.is_finite() or not is_finite(denominator) or denominator<=0.0:
		return _result(state,packet,time,water,sea,draw_count,0,"zero-total/nonfinite source domain")
	var vertices:PackedVector3Array=state.native_vertices.duplicate()
	var uvs:PackedVector2Array=state.native_uvs.duplicate()
	var colors:PackedColorArray=state.native_colors.duplicate()
	var distance:=head_offset
	var startup:=minf(1.0,maxi(int(history.updates)-30,0)*_f32(0.05))
	for row in 30:
		var index:=posmod(int(history.head)-row,30)
		var p:Dictionary=history.points[index]
		if not p.active:
			vertices[row*2]=current if row==0 else vertices[row*2-2]
			vertices[row*2+1]=current if row==0 else vertices[row*2-1]
			colors[row*2]=Color(1,1,1,0);colors[row*2+1]=Color(1,1,1,0)
			continue
		var age:=clampf(_f32((float(history.time)-float(p.born))/float(history.cfg.WakeDestroyTime)),0.0,1.0)
		var fraction:=clampf(_f32(distance/denominator),0.0,1.0)
		distance=_f32(distance+float(p.length))
		var center:=Vector3(p.p[0],p.p[1],p.p[2])
		var tangent:Vector3
		if index==int(history.head):tangent=current-center
		else:
			var older:Dictionary=history.points[posmod(index-1,30)]
			tangent=center-Vector3(older.p[0],older.p[1],older.p[2])
		if row==29:tangent=-tangent
		var unit:=_normal(tangent)
		var domain:=_f32(1.0-fraction*age)
		var curve_scale:=_f32(distance*_f32(0.0025)*250.0)
		var spread:float=history.curve(domain,curve_scale,1.0)
		var half_width:=float(history.cfg.WakeMaximumWidth)*float(history.scale)
		if float(history.scale)>=_f32(0.4):half_width=(float(history.cfg.WakeMaximumWidth)+spread)*float(history.scale)
		var stored_x:=_f32(float(unit.x)*half_width)
		var stored_z:=_f32(float(unit.z)*half_width)
		var side:=-float(unit.y)
		vertices[row*2]=Vector3(_f32(float(center.x)-side*half_width),_f32(float(center.y)-stored_x),_f32(float(center.z)-stored_z))
		vertices[row*2+1]=Vector3(_f32(float(center.x)+side*half_width),_f32(float(center.y)+stored_x),_f32(float(center.z)+stored_z))
		if row==1:
			var hy:=_f32(float(p.length)*float(unit.y));var hz:=_f32(float(p.length)*float(unit.z))
			for edge in 2:
				var q:Vector3=vertices[2+edge]
				vertices[edge]=Vector3(_f32(float(q.x)-float(unit.x)*float(p.length)),_f32(float(q.y)-hy),_f32(float(q.z)-hz))
		var alpha:=0.0 if row<=1 else _f32(startup*(60-row*2)*_f32(1.0/60.0))
		colors[row*2]=Color(1,1,1,alpha);colors[row*2+1]=Color(1,1,1,alpha)
		uvs[row*2]=Vector2(0.0,p.v);uvs[row*2+1]=Vector2(1.0,p.v)
	for vertex:Vector3 in vertices:
		if not vertex.is_finite():return _result(state,packet,time,water,sea,draw_count,0,"nonfinite source geometry")
	var repairs:=_repair(vertices)
	state.native_vertices=vertices;state.native_uvs=uvs;state.native_colors=colors
	history.set_meta(STATE_KEY,state)
	return _result(state,packet,time,water,sea,draw_count,repairs)
