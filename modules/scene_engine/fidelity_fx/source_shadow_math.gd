extends RefCounted
## Finite source 0x512AC0 / 0x5126A1..0x51289F / 0x50F130 / 0x4BC190.
## No inference of caster classification, skinning or actor light producer.
const EXTRUSION:=1000000000.0
const ROTATION_THRESHOLD:=0.9998477101325989
static func f32(value:float)->float:
	return PackedFloat32Array([value])[0]

static func toggle_edge(edges:Array,a:int,b:int)->void:
	a=a&65535;b=b&65535
	for i in edges.size():
		var edge=edges[i]
		if (edge[0]==a and edge[1]==b) or (edge[0]==b and edge[1]==a):
			edges[i]=edges[-1];edges.pop_back();return
	edges.append([a,b])

static func build_volume_component(positions:Array,local_light:Array,edges:Array,cap_indices:Array)->Dictionary:
	if local_light.size()!=3 or cap_indices.size()%3:return {"error":"native dimensions required"}
	if 1+2*edges.size()+cap_indices.size()>65535:return {"error":"out of finite uint16 scope"}
	var source:Array=[]
	for p in positions:
		if p.size()!=3:return {"error":"native dimensions required"}
		var v:Array=[]
		for x in p:
			if not is_finite(float(x)) or not is_finite(f32(float(x))):return {"error":"finite positions required"}
			v.append(f32(float(x)))
		source.append(v)
	var direction:Array=[]
	for x in local_light:
		var v:=f32(f32(float(x))*EXTRUSION)
		if not is_finite(v):return {"error":"finite direction required"}
		direction.append(v)
	for edge in edges:
		if edge.size()!=2:return {"error":"edge dimensions required"}
		for j in edge:
			if int(j)<0 or int(j)>=mini(32768,source.size()):return {"error":"finite signed edge index required"}
	for j in cap_indices:
		if int(j)<0 or int(j)>=mini(65536,source.size()):return {"error":"finite cap index required"}
	var output:Array=[];var indices:Array=[]
	if not edges.is_empty():
		var first:Array=source[int(edges[0][0])]
		output.append([f32(direction[0]+first[0]),f32(direction[1]+first[1]),f32(direction[2]+first[2])])
	for edge in edges:
		var n:=output.size();indices.append_array([n+1,n,0]);output.append(source[int(edge[0])]);output.append(source[int(edge[1])])
	for i in range(0,cap_indices.size(),3):
		var n:=output.size();indices.append_array([n+2,n+1,n])
		for j in 3:output.append(source[int(cap_indices[i+j])])
	return {"direction":direction,"positions":output,"indices":indices,"vertexCount":output.size(),"triangleCount":edges.size()+cap_indices.size()/3}

static func should_rebuild(skinned:bool,has_volume:bool,current:Array,previous:Array,threshold:float=ROTATION_THRESHOLD)->bool:
	if skinned or not has_volume:return true
	if current.size()!=9 or previous.size()!=9:return true
	for column in [0,1,0]:
		var dot:=0.0
		for row in [2,1,0]:dot+=f32(float(current[row*3+column]))*f32(float(previous[row*3+column]))
		if not is_finite(dot) or dot<=f32(threshold):return true
	return false

static func registration_allowed(display_shadows:bool,feature_bits:int,has_actor_casters:bool,actor_field_144:bool)->bool:
	return display_shadows and (feature_bits&0x20)!=0 and has_actor_casters and not actor_field_144
