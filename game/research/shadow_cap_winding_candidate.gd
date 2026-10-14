extends RefCounted
## Research-only adapter for the finite source volume layout. No production hook.
## Changes near-cap index winding only; unknown layouts are explicitly rejected.
static func adapt(geometry:Dictionary)->Dictionary:
	if not geometry.get("positions") is Array or not geometry.get("indices") is Array:return {"ok":false,"reason":"missing-volume-arrays"}
	var positions:Array=geometry.positions;var indices:Array=geometry.indices
	if indices.size()%3!=0 or int(geometry.get("vertexCount",-1))!=positions.size():return {"ok":false,"reason":"invalid-volume-counts"}
	if positions.is_empty() and indices.is_empty():return {"ok":true,"geometry":geometry,"sideTriangles":0,"capTriangles":0,"reason":"empty-volume"}
	if positions.size()<2 or not positions[0] is Array or not positions[1] is Array or positions[0].size()!=3 or positions[1].size()!=3:return {"ok":false,"reason":"missing-apex-anchor"}
	var apex:=Vector3(positions[0][0],positions[0][1],positions[0][2])
	var anchor:=Vector3(positions[1][0],positions[1][1],positions[1][2])
	if not apex.is_finite() or not anchor.is_finite():return {"ok":false,"reason":"nonfinite-source-point"}
	if apex.distance_to(anchor)<=1000000.0:return {"ok":false,"reason":"not-the-source-finite-apex-layout"}
	var sides:=0
	while sides*3<indices.size() and indices[sides*3+2]==0:
		if indices[sides*3]!=sides*2+2 or indices[sides*3+1]!=sides*2+1:return {"ok":false,"reason":"unexpected-side-layout"}
		sides+=1
	var caps:int=indices.size()/3-sides
	if positions.size()!=1+2*sides+3*caps:return {"ok":false,"reason":"unexpected-source-vertex-layout"}
	var changed:Array=indices.duplicate()
	for cap in caps:
		var offset: int=(sides+cap)*3
		var first:int=1+2*sides+3*cap
		if indices[offset]!=first+2 or indices[offset+1]!=first+1 or indices[offset+2]!=first:return {"ok":false,"reason":"unexpected-cap-layout"}
		changed[offset]=first;changed[offset+2]=first+2
	changed.make_read_only()
	var output:=geometry.duplicate(false);output.indices=changed;output.make_read_only()
	return {"ok":true,"geometry":output,"sideTriangles":sides,"capTriangles":caps,"reason":"cap-only-winding"}
