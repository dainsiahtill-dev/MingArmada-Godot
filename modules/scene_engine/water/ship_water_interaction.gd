extends RefCounted
## One-way visual interaction input, in world metres and accepted seconds.
## Five spheres approximate the actual cached hull waterline, not buoyancy.
const RADIUS_BEAM_RATIO:=0.20
const MIN_RADIUS_M:=0.20
const MAX_RADIUS_M:=2.0
const PROBE_WEIGHT:=0.20
const MIN_DELTA_SECONDS:=0.00001
const MAX_DELTA_SECONDS:=0.5
const TELEPORT_SPEED_MPS:=80.0
const MAX_VELOCITY_MPS:=20.0
const WAKE_MIN_SPEED_MPS:=0.05
const MAX_ACTORS:=64
var _actors:Dictionary={}

static func _number(value:Variant)->bool:
	return (value is float or value is int) and is_finite(float(value))

static func _section(sections:Array,z:float)->Vector3:
	for i in range(1,sections.size()):
		var a:Dictionary=sections[i-1];var b:Dictionary=sections[i]
		if z<=float(b.z):
			var t:=clampf((z-float(a.z))/(float(b.z)-float(a.z)),0.0,1.0)
			return Vector3(lerpf(a.left,b.left,t),z,lerpf(a.right,b.right,t))
	var last:Dictionary=sections[-1]
	return Vector3(last.left,last.z,last.right)

static func _center(section:Vector3)->Vector3:
	return Vector3((section.x+section.z)*.5,0.0,section.y)

static func _geometry(attachment:Dictionary)->Dictionary:
	if not attachment.get("surfaceProfile") is Dictionary or not attachment.get("bow") is Vector3:return {"error":"missing-profile-or-bow"}
	var profile:Dictionary=attachment.surfaceProfile
	if not profile.get("sections") is Array or not profile.get("hullToWorld") is Transform3D:return {"error":"missing-waterline-transform"}
	var sections:Array=profile.sections;var frame:Transform3D=profile.hullToWorld
	if sections.size()<2 or sections.size()>4096:return {"error":"invalid-section-count"}
	if not frame.origin.is_finite() or not frame.basis.x.is_finite() or not frame.basis.y.is_finite() or not frame.basis.z.is_finite() or not attachment.bow.is_finite():return {"error":"nonfinite-transform-or-bow"}
	var determinant:=frame.basis.determinant()
	if not is_finite(determinant) or absf(determinant)<0.00000001:return {"error":"singular-transform"}
	var last_z:=-INF;var beam:=0.0
	for section in sections:
		if not section is Dictionary:return {"error":"invalid-section"}
		for key:String in ["z","left","right"]:
			if not _number(section.get(key)):return {"error":"nonfinite-section"}
		if float(section.z)<=last_z or float(section.left)>float(section.right):return {"error":"unordered-section"}
		last_z=section.z;beam=maxf(beam,float(section.right)-float(section.left))
	beam*=frame.basis.x.length()
	var first:Vector3=_section(sections,sections[0].z);var last:Vector3=_section(sections,sections[-1].z)
	var local_bow:Vector3=frame.affine_inverse()*attachment.bow
	var bow:Vector3=first if absf(local_bow.z-first.y)<absf(local_bow.z-last.y) else last
	var stern:Vector3=last if bow==first else first
	var stern_world:Vector3=frame*_center(stern);var bow_world:Vector3=frame*_center(bow)
	var length:=stern_world.distance_to(bow_world)
	var heading:=Vector2(bow_world.x-stern_world.x,bow_world.z-stern_world.z)
	if not is_finite(beam) or not is_finite(length) or beam<=0.00001 or length<=0.00001 or not heading.is_finite() or heading.length_squared()<0.00000001:return {"error":"degenerate-world-waterline"}
	var locals:Array=[]
	for fraction:float in [.15,.5]:
		var section:=_section(sections,lerpf(stern.y,bow.y,fraction))
		locals.append(Vector3(section.x,0.0,section.y));locals.append(Vector3(section.z,0.0,section.y))
	locals.append(_center(_section(sections,lerpf(stern.y,bow.y,.85))))
	var points:Array=[]
	for point:Vector3 in locals:
		var world:Vector3=frame*point
		if not world.is_finite():return {"error":"nonfinite-world-probe"}
		points.append(world)
	return {"points":points,"local_points":locals,"stern":stern_world,"motion_origin":frame.origin,"forward":heading.normalized(),"beam":beam,"length":length,"radius":clampf(beam*RADIUS_BEAM_RATIO,MIN_RADIUS_M,MAX_RADIUS_M)}

static func _water_sample(water:Callable,point:Vector3,seconds:float)->Dictionary:
	var value:Variant=water.call(point.x,point.z,seconds)
	if _number(value):return {"height":float(value),"flow":Vector2.ZERO}
	if not value is Dictionary or not _number(value.get("height")):return {"error":"invalid-water-height"}
	var flow:Variant=value.get("flow",Vector2.ZERO)
	if not flow is Vector2 or not flow.is_finite():return {"error":"invalid-horizontal-flow"}
	return {"height":float(value.height),"flow":flow}

static func _wetness(point:Vector3,height:float,radius:float)->float:
	# Normalized sphere/plane intersection area, a compact artistic support.
	# Zero above OR below the interface by one radius; one at the waterline.
	var distance:float=(point.y-height)/radius
	return maxf(0.0,1.0-distance*distance)

func _empty(id:String,reason:String)->Dictionary:
	return {"emitters":[],"wake":{},"diagnostics":{"accepted":false,"reason":reason,"actor_count":_actors.size(),"id":id,"probe_count":0}}

func sample(id:String,attachment:Dictionary,seconds:float,water:Callable,hull_alive:bool=true)->Dictionary:
	if id.is_empty() or not is_finite(seconds) or seconds<0.0:return _empty(id,"invalid-id-or-time")
	if not hull_alive:forget(id);return _empty(id,"hull-inactive")
	if not water.is_valid():return _empty(id,"invalid-water-callable")
	var previous:Dictionary=_actors.get(id,{})
	if not previous.is_empty() and seconds==float(previous.time):return _empty(id,"duplicate")
	if previous.is_empty() and _actors.size()>=MAX_ACTORS:return _empty(id,"actor-capacity")
	var geometry:=_geometry(attachment)
	if geometry.has("error"):return _empty(id,geometry.error)
	# Validate all external water samples before changing any accepted history.
	var waters:Array=[]
	for point:Vector3 in geometry.points:
		var sampled:=_water_sample(water,point,seconds)
		if sampled.has("error"):return _empty(id,sampled.error)
		waters.append(sampled)
	var stern_water:=_water_sample(water,geometry.stern,seconds)
	if stern_water.has("error"):return _empty(id,stern_water.error)
	var delta:=seconds-float(previous.time) if not previous.is_empty() else 0.0
	var reason:="advance"
	if previous.is_empty():reason="first"
	elif delta<0.0:reason="rewind"
	elif delta<MIN_DELTA_SECONDS:reason="small-interval"
	elif delta>MAX_DELTA_SECONDS:reason="gap"
	elif geometry.local_points!=previous.local_points:reason="profile-changed"
	else:
		var max_distance:=0.0
		for i in geometry.points.size():max_distance=maxf(max_distance,geometry.points[i].distance_to(previous.points[i]))
		if max_distance>maxf(20.0,float(geometry.length)*1.5) or max_distance/delta>TELEPORT_SPEED_MPS:reason="teleport"
	var advancing:=reason=="advance"
	var emitters:Array=[];var probes:Array=[];var clamped:=0
	for i in geometry.points.size():
		var point:Vector3=geometry.points[i];var sampled:Dictionary=waters[i]
		var velocity:Vector3=(point-previous.points[i])/delta if advancing else Vector3.ZERO
		if advancing:velocity-=Vector3(sampled.flow.x,0.0,sampled.flow.y)
		if velocity.length()>MAX_VELOCITY_MPS:velocity=velocity.limit_length(MAX_VELOCITY_MPS);clamped+=1
		var wet:=_wetness(point,sampled.height,geometry.radius)
		emitters.append({"position":point,"velocity":velocity,"radius":geometry.radius,"wetness":wet,"weight":PROBE_WEIGHT,"id":"%s:probe%d"%[id,i]})
		probes.append({"local_position":geometry.local_points[i],"position":point,"velocity":velocity,"water_height":sampled.height,"flow":sampled.flow,"wetness":wet})
	# The full-pose probes include angular motion. Long-wake travel must use
	# the hull transform origin so a stationary pitch/roll cannot invent surge.
	var center_velocity:Vector3=(geometry.motion_origin-previous.motion_origin)/delta if advancing else Vector3.ZERO
	var center_flow:Vector2=(waters[2].flow+waters[3].flow)*.5
	var horizontal:=Vector2(center_velocity.x,center_velocity.z)-center_flow if advancing else Vector2.ZERO
	var speed:=minf(horizontal.length(),MAX_VELOCITY_MPS)
	var stern_wet:=_wetness(geometry.stern,stern_water.height,geometry.radius)
	var wake:Dictionary={}
	if advancing and speed>WAKE_MIN_SPEED_MPS and stern_wet>0.0:
		wake={"stern":geometry.stern,"forward":geometry.forward,"beam":geometry.beam,"speed":speed,"wetness":stern_wet,"id":id}
	_actors[id]={"time":seconds,"points":geometry.points.duplicate(),"local_points":geometry.local_points.duplicate(),"motion_origin":geometry.motion_origin}
	return {"emitters":emitters,"wake":wake,"diagnostics":{"accepted":true,"advanced":advancing,"reason":reason,"time":seconds,"dt":delta,"actor_count":_actors.size(),"id":id,"probe_count":emitters.size(),"beam_m":geometry.beam,"length_m":geometry.length,"radius_m":geometry.radius,"speed_mps":speed,"stern":geometry.stern,"stern_wetness":stern_wet,"clamped_velocities":clamped,"probes":probes}}

func forget(id:String)->void:
	_actors.erase(id)

func clear()->void:
	_actors.clear()
