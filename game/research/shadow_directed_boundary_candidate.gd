extends RefCounted
## Diagnostic only: retain all source triangles and append signed missing sides.
## Near-cap winding and the source Math oracle are intentionally unchanged.
const Layout=preload("res://game/research/shadow_cap_winding_candidate.gd")
static func adapt(geometry:Dictionary)->Dictionary:
	var layout:Dictionary=Layout.adapt(geometry)
	if not layout.ok:return layout
	var sides:int=layout.sideTriangles;var caps:int=layout.capTriangles
	if sides==0:return {"ok":true,"geometry":geometry,"addedSides":0,"missing":[]}
	var source:Array=geometry.positions;var vertices:Dictionary={};var points:Array=[];var remap:Array=[]
	for point in source:
		if not point is Array or point.size()!=3:return {"ok":false,"reason":"invalid-source-point"}
		var p:=Vector3(point[0],point[1],point[2])
		if not p.is_finite():return {"ok":false,"reason":"nonfinite-source-point"}
		if not vertices.has(p):vertices[p]=points.size();points.append(point)
		remap.append(vertices[p])
	var residual:Dictionary={}
	for cap in caps:
		var first:int=1+2*sides+3*cap
		for side in 3:
			var a:int=remap[first+side];var b:int=remap[first+(side+1)%3]
			var key:=Vector2i(mini(a,b),maxi(a,b))
			if a!=b:residual[key]=int(residual.get(key,0))+(1 if a<b else -1)
	for side in sides:
		var a:int=remap[1+side*2];var b:int=remap[2+side*2]
		var key:=Vector2i(mini(a,b),maxi(a,b))
		if a!=b:residual[key]=int(residual.get(key,0))-(1 if a<b else -1)
	var positions:Array=source.duplicate(false);var indices:Array=geometry.indices.duplicate();var missing:Array=[]
	for key:Vector2i in residual:
		var count:int=residual[key]
		if count==0:continue
		var a:int=key.x if count>0 else key.y;var b:int=key.y if count>0 else key.x
		missing.append({"a":points[a],"b":points[b],"multiplicity":absi(count)})
		for repeat in absi(count):
			if positions.size()+2>65535:return {"ok":false,"reason":"candidate-exceeds-source-index-scope"}
			var n:=positions.size();positions.append(points[a]);positions.append(points[b]);indices.append_array([n+1,n,0])
	var added:int=(indices.size()-geometry.indices.size())/3
	if added==0:return {"ok":true,"geometry":geometry,"addedSides":0,"missing":missing}
	positions.make_read_only();indices.make_read_only()
	var result:Dictionary=geometry.duplicate(false);result.positions=positions;result.indices=indices;result.vertexCount=positions.size();result.triangleCount=indices.size()/3;result.make_read_only()
	return {"ok":true,"geometry":result,"addedSides":added,"missing":missing}
