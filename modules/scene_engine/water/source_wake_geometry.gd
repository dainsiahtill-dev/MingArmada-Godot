extends RefCounted
## Source finite profile/dual-edge strip; finite normalize/head placement is a
## target adapter. Full original 4E0075..4E0D ABI/GPU equivalence is unresolved.
const Surface=preload("res://modules/scene_engine/water/source_surface.gd")
static func crossing(a:Vector2,b:Vector2,c:Vector2,d:Vector2)->Variant:
	var ab:=b-a;var cd:=d-c;var denominator:=ab.cross(cd)
	if absf(denominator)<0.00000001:return null
	var t:float=(c-a).cross(cd)/denominator;var u:float=(c-a).cross(ab)/denominator
	return a+ab*t if t>0.0 and t<1.0 and u>0.0 and u<1.0 else null
static func build(history:RefCounted,packet:Dictionary,time:float,water:Callable,sea:Callable)->Dictionary:
	var rows:Array=history.profile();var vertices:=PackedVector3Array();var uvs:=PackedVector2Array();var colors:=PackedColorArray();var indices:=PackedInt32Array();var wet:Array=[]
	var native_edges:Array=[];var prior:Vector3=Vector3.ZERO;var adapted:=false
	for row in rows.size():
		var record:Dictionary=rows[row]
		if not record.active:
			native_edges.append([prior,prior]);continue
		var center:=Vector3(record.position[0],record.position[1],record.position[2]);prior=center
		var newer:Vector3=center;var older:Vector3=center
		if row>0 and rows[row-1].active:newer=Vector3(rows[row-1].position[0],rows[row-1].position[1],rows[row-1].position[2])
		if row+1<rows.size() and rows[row+1].active:older=Vector3(rows[row+1].position[0],rows[row+1].position[1],rows[row+1].position[2])
		var tangent:=newer-older
		if tangent.length_squared()<0.00000001:
			var heading:=float(packet.get("sourceHeading",0.0));tangent=Vector3(cos(heading),sin(heading),0.0);adapted=true
		else:tangent=tangent.normalized()
		var side:=Vector3(-tangent.y,tangent.x,0.0)*float(record.half_width)
		native_edges.append([center-side,center+side])
	# Recovered nearby-cross intent: compare only three neighbouring width
	# edges, collapse closest offending side. This finite topology policy is
	# explicit adaptation until the complete original ABI is differentially run.
	var repairs:=0
	for row in native_edges.size():
		for other in range(maxi(0,row-3),row):
			var first:Array=native_edges[row];var second:Array=native_edges[other]
			var hit:Variant=crossing(Vector2(first[0].x,first[0].y),Vector2(first[1].x,first[1].y),Vector2(second[0].x,second[0].y),Vector2(second[1].x,second[1].y))
			if hit==null:continue
			var index:=0 if Vector2(first[0].x,first[0].y).distance_squared_to(hit)<Vector2(first[1].x,first[1].y).distance_squared_to(hit) else 1
			first[index]=Vector3(hit.x,hit.y,first[index].z);repairs+=1
	var unit:=float(packet.sourceToWorld);var origin_array:Array=packet.get("worldOrigin",[0.0,0.0,0.0]);var origin:=Vector3(origin_array[0],origin_array[1],origin_array[2])
	for row in rows.size():
		var record:Dictionary=rows[row]
		for edge in 2:
			var native:Vector3=native_edges[row][edge];var p:=Surface.native_to_world([native.x,native.y,native.z],unit,origin)
			if water.is_valid():
				var height:=float(water.call(p.x,p.z,time))
				if is_finite(height):p.y=height+0.10
			vertices.append(p);wet.append(not sea.is_valid() or bool(sea.call(p.x,p.z)))
			uvs.append(Vector2(float(edge),float(record.uv[edge][1]) if record.active else 0.0))
			colors.append(Color(1.0,1.0,1.0,float(record.alpha)))
	var drawn_rows:=mini(rows.size(),int(history.vertex_count/2))
	for row in range(drawn_rows-1):
		var a:=row*2;var b:=a+2
		if wet[a] and wet[b] and wet[a+1]:indices.append_array(PackedInt32Array([a,a+1,b]))
		if wet[a+1] and wet[b] and wet[b+1]:indices.append_array(PackedInt32Array([a+1,b+1,b]))
	return {"vertices":vertices,"uvs":uvs,"colors":colors,"indices":indices,"native_equivalent":false,"finite_tangent_guard":adapted,"cross_repairs":repairs,"adaptations":["finite strip/head tangent","nearby self-cross adapter","water_surface_fit","sea_triangle_clip"],"unresolved":["full original normalization/head/strip ABI","original NaN LUT","DX9 draw/pixels"]}
