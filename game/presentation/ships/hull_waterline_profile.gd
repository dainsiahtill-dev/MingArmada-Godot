extends RefCounted
## Target local-froth footprint, sampled once from actual rigid hull meshes.
## Local Y=0 is the target reference waterline, not recovered original scaling.
const EPSILON:=0.00001
const SECTION_COUNT:=96

static func build(model:Node3D)->Dictionary:
	if model==null:return {}
	var segments:Array=[]
	for candidate:Node in model.find_children("*","MeshInstance3D",true,false):
		if str(candidate.get_meta("damage_surface",""))!="hull":continue
		var node:=candidate as MeshInstance3D
		if node.mesh==null:continue
		# Ship models also configure before entering SceneTree. Accumulate
		# local ancestors, avoiding global_transform's in-tree requirement.
		var transform:=_relative_transform(node,model)
		for surface:int in node.mesh.get_surface_count():
			if node.mesh.surface_get_primitive_type(surface)!=Mesh.PRIMITIVE_TRIANGLES:continue
			var arrays:Array=node.mesh.surface_get_arrays(surface)
			var points:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
			var count:=indices.size() if not indices.is_empty() else points.size()
			for start:int in range(0,count-2,3):
				var triangle:Array[Vector3]=[]
				for offset:int in 3:
					var index:int=indices[start+offset] if not indices.is_empty() else start+offset
					triangle.append(transform*points[index])
				var crossing:=_waterline_segment(triangle)
				if crossing.size()==2:segments.append(crossing)
	if segments.is_empty():return {}
	var near_z:=INF;var far_z:=-INF
	for segment:Array in segments:
		for point:Vector2 in segment:near_z=minf(near_z,point.y);far_z=maxf(far_z,point.y)
	if not is_finite(near_z) or far_z-near_z<=EPSILON:return {}
	var sections:Array[Dictionary]=[];var beam:=0.0
	for index:int in SECTION_COUNT+1:
		var z:=lerpf(near_z,far_z,float(index)/float(SECTION_COUNT))
		var left:=INF;var right:=-INF
		for segment:Array in segments:
			var a:Vector2=segment[0];var b:Vector2=segment[1]
			if z<minf(a.y,b.y)-EPSILON or z>maxf(a.y,b.y)+EPSILON:continue
			if absf(a.y-b.y)<=EPSILON:
				if absf(z-a.y)<=EPSILON:left=minf(left,minf(a.x,b.x));right=maxf(right,maxf(a.x,b.x))
			else:
				var weight:=clampf((z-a.y)/(b.y-a.y),0.0,1.0)
				var x:=lerpf(a.x,b.x,weight)
				left=minf(left,x);right=maxf(right,x)
		if not is_finite(left) or not is_finite(right):continue
		sections.append({"z":z,"left":left,"right":right})
		beam=maxf(beam,right-left)
	if sections.size()<2 or beam<=EPSILON:return {}
	return {"sections":sections,"beam":beam}

static func _relative_transform(node:Node3D,model:Node3D)->Transform3D:
	var transform:=Transform3D.IDENTITY
	var current:=node
	while current!=null and current!=model:
		transform=current.transform*transform
		current=current.get_parent_node_3d()
	return transform

static func _waterline_segment(triangle:Array[Vector3])->Array[Vector2]:
	var points:Array[Vector2]=[]
	if absf(triangle[0].y)<=EPSILON and absf(triangle[1].y)<=EPSILON and absf(triangle[2].y)<=EPSILON:return points
	for edge:int in 3:
		var a:Vector3=triangle[edge];var b:Vector3=triangle[(edge+1)%3]
		if absf(a.y)<=EPSILON:_append_unique(points,Vector2(a.x,a.z))
		if a.y*b.y<0.0:
			var point:=a.lerp(b,-a.y/(b.y-a.y))
			_append_unique(points,Vector2(point.x,point.z))
	return points

static func _append_unique(points:Array[Vector2],point:Vector2)->void:
	if not point.is_finite():return
	for existing:Vector2 in points:
		if existing.distance_squared_to(point)<EPSILON*EPSILON:return
	points.append(point)
