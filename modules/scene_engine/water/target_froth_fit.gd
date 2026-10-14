extends RefCounted
## Target surface-footprint fit. Source mesh/UV/RGBA assets remain untouched.
## Preserve the authored cross-band shape, but anchor its inner edge to the
## actual hull waterline and give the boat-exterior band a bounded width.
static func sample(rows:Array,z:float,field:String)->float:
	if rows.is_empty():return 0.0
	if z<=float(rows[0].z):return float(rows[0][field])
	if z>=float(rows[-1].z):return float(rows[-1][field])
	var low:=0;var high:=rows.size()-1
	while high-low>1:
		var middle:=int((low+high)/2)
		if z<=float(rows[middle].z):high=middle
		else:low=middle
	var span:=float(rows[high].z)-float(rows[low].z)
	return lerpf(float(rows[low][field]),float(rows[high][field]),clampf((z-float(rows[low].z))/span,0.0,1.0)) if span>0.00001 else float(rows[high][field])

static func bow_profile(profile:Dictionary,world_anchor:Vector3)->Dictionary:
	var sections:Array=profile.get("sections",[])
	if sections.size()<2 or not profile.get("worldToHull") is Transform3D:return {}
	var local:Vector3=profile.worldToHull*world_anchor
	var low_tip:=float(sections[0].z);var high_tip:=float(sections[-1].z)
	var direction:=1.0 if absf(local.z-high_tip)<=absf(local.z-low_tip) else -1.0
	var tip:=high_tip if direction>0.0 else low_tip
	var run:=float(profile.get("targetBowRun",0.0))
	if not is_finite(run) or run<=0.0:return {}
	var inner:=clampf(tip-direction*run,low_tip,high_tip)
	var low:=minf(tip,inner);var high:=maxf(tip,inner)
	var clipped:Array=[]
	clipped.append({"z":low,"left":sample(sections,low,"left"),"right":sample(sections,low,"right")})
	for row:Dictionary in sections:
		if float(row.z)>low+0.00001 and float(row.z)<high-0.00001:clipped.append(row)
	clipped.append({"z":high,"left":sample(sections,high,"left"),"right":sample(sections,high,"right")})
	var result:=profile.duplicate(false);result.sections=clipped
	return result

static func prepare(vertices:PackedVector3Array,colors:PackedColorArray,profile:Dictionary,triangles:Array)->Dictionary:
	# Carrier rows are not necessarily aligned vertex rows (one authored side
	# uses staggered triangulation). Intersect the real triangles once, including
	# interpolated alpha, instead of grouping vertices at approximately equal Z.
	var to_local:Transform3D=profile.worldToHull;var points:=PackedVector3Array();var low:=INF;var high:=-INF
	for p:Vector3 in vertices:
		var local:=to_local*p;points.append(local);low=minf(low,local.z);high=maxf(high,local.z)
	var positive:Array=[];var negative:Array=[]
	for row in 97:
		var z:=lerpf(low,high,float(row)/96.0);var near_p:=INF;var near_n:=INF;var far_p:=0.0;var far_n:=0.0
		for triangle:Array in triangles:
			var hits:Array=[]
			for edge in 3:
				var ia:=int(triangle[edge]);var ib:=int(triangle[(edge+1)%3]);var a:Vector3=points[ia];var b:Vector3=points[ib]
				var span:=float(b.z)-float(a.z)
				if absf(span)<0.000001:continue
				var t:=(z-float(a.z))/span
				if t<0.0 or t>1.0:continue
				hits.append({"x":lerpf(a.x,b.x,t),"alpha":lerpf(colors[ia].a,colors[ib].a,t)})
			if hits.size()<2:continue
			var candidates:=hits.duplicate()
			var a:Dictionary=hits[0];var b:Dictionary=hits[1];var alpha_span:=float(b.alpha)-float(a.alpha)
			if absf(alpha_span)>0.000001:
				var t:=(.25-float(a.alpha))/alpha_span
				if t>=0.0 and t<=1.0:candidates.append({"x":lerpf(a.x,b.x,t),"alpha":.25})
			for point:Dictionary in candidates:
				if point.x>0.00001:
					far_p=maxf(far_p,point.x)
					if point.alpha>=.24999:near_p=minf(near_p,point.x)
				elif point.x<-.00001:
					far_n=maxf(far_n,-point.x)
					if point.alpha>=.24999:near_n=minf(near_n,-point.x)
		if is_finite(near_p) and far_p-near_p>.00001:positive.append({"z":z,"near":near_p,"far":far_p})
		if is_finite(near_n) and far_n-near_n>.00001:negative.append({"z":z,"near":near_n,"far":far_n})
	return {"low":low,"high":high,"positive":positive,"negative":negative}
static func apply(vertices:PackedVector3Array,colors:PackedColorArray,profile:Dictionary,carrier:Dictionary)->PackedVector3Array:
	var sections:Array=profile.get("sections",[])
	if vertices.is_empty() or colors.size()!=vertices.size() or sections.size()<2 or not profile.get("worldToHull") is Transform3D or not profile.get("hullToWorld") is Transform3D:return vertices
	var width:=float(profile.get("targetOuterWidth",0.0))
	if not is_finite(width) or width<=0.0:return vertices
	var to_local:Transform3D=profile.worldToHull;var to_world:Transform3D=profile.hullToWorld
	var local:=PackedVector3Array();var low:=float(carrier.get("low",0.0));var high:=float(carrier.get("high",0.0))
	for p:Vector3 in vertices:local.append(to_local*p)
	if high-low<=0.00001:return vertices
	var positive:Array=carrier.get("positive",[]);var negative:Array=carrier.get("negative",[])
	var cap:=width*.65;var start:=float(sections[0].z)-cap;var end:=float(sections[-1].z)+cap
	var result:=PackedVector3Array()
	for p:Vector3 in local:
		var rows:Array=positive if p.x>=0.0 else negative
		var z:=lerpf(start,end,clampf((float(p.z)-low)/(high-low),0.0,1.0));var x:=float(p.x)
		if not rows.is_empty() and absf(x)>0.00001:
			var near_edge:=sample(rows,p.z,"near");var far_edge:=sample(rows,p.z,"far")
			var across:=clampf((absf(x)-near_edge)/maxf(0.00001,far_edge-near_edge),0.0,1.0)
			var side:=1.0 if x>=0.0 else -1.0;var edge:=sample(sections,z,"right" if side>0.0 else "left")
			x=edge+side*across*width
		result.append(to_world*Vector3(x,p.y,z))
	return result
