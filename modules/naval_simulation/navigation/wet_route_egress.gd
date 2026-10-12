extends RefCounted
# Directed low-speed connection into the original circle-safe Planner domain.
# Numeric only: authority, controls and measured-state refresh belong to Encounter.
const Planner=preload("res://modules/naval_simulation/navigation/wet_route_planner.gd")
const Clearance=preload("res://modules/naval_simulation/navigation/approach_clearance.gd")
const SPEED_CAP=0.35
const MAX_SAIL=0.1
const COURSE_TOLERANCE=PI/180.0
const TURN_SECONDS=60.0
const TRAVEL_SECONDS=180.0
const HORIZON=TURN_SECONDS+TRAVEL_SECONDS+Clearance.STOP_SECONDS
static func plan(own: Dictionary,target: Dictionary,peers: Array,terrain: Callable,sea_level: float=0.0) -> Dictionary:
	var original=Planner.new()
	var result: Dictionary=original.plan(own.position,target,own.dimensions,terrain,sea_level)
	if result.ok or result.reason!="unsafe-endpoint" or not original._wet(target):return {"ok":false,"reason":"ineligible-endpoint"}
	if original._wet(own.position):return {"ok":false,"reason":"safe-start"}
	var nodes: Array=[]
	for dx in [-1,0,1]:
		for dz in [-1,0,1]:
			if dx==0 and dz==0:continue
			nodes.append({"x":own.position.x+dx*32.0,"z":own.position.z+dz*32.0})
	nodes.sort_custom(func(a,b):return _distance(a,target)<_distance(b,target))
	for node: Dictionary in nodes:
		var clearance=assess(own,node,peers,terrain,sea_level)
		if not clearance.ok:continue
		var onward: Dictionary=Planner.new().plan(node,target,own.dimensions,terrain,sea_level)
		if onward.ok:return {"ok":true,"node":node,"course":clearance.course,"clearance":clearance}
	return {"ok":false,"reason":"no-safe-egress"}
static func assess(own: Dictionary,node: Dictionary,peers: Array,terrain: Callable,sea_level: float=0.0) -> Dictionary:
	if own.speed>SPEED_CAP+0.05 or own.brake<=0 or own.yaw_damping<=0:return {"ok":false,"reason":"motion-budget"}
	if not Clearance._wet(own.dimensions,{"x":own.position.x,"z":own.position.z,"heading":own.heading,"padding":0.0},terrain,sea_level):return {"ok":false,"reason":"current-depth"}
	var distance=_distance(own.position,node)
	if distance>46:return {"ok":false,"reason":"connector-distance"}
	var course=atan2(node.z-own.position.z,node.x-own.position.x)
	if own.wind_speed>0 and absf(wrapf(course-own.wind_from,-PI,PI))<own.safe_wind:return {"ok":false,"reason":"wind"}
	var error=wrapf(course-own.heading,-PI,PI)
	var yaw_stop: float=absf(own.yawRate)/own.yaw_damping
	if own.speed/own.brake>Clearance.STOP_SECONDS or yaw_stop>PI/6:return {"ok":false,"reason":"stop-reserve"}
	var radius=sqrt(own.dimensions.length*own.dimensions.length+own.dimensions.width*own.dimensions.width)/2.0
	var drift: float=own.speed*own.speed/(2.0*own.brake)+own.speed/60.0
	var padding: float=0.15+drift+radius*Clearance.ANGLE_STEP/2.0
	var poses: Array=[]
	# Both sides of measured residual yaw are enclosed before the shortest turn;
	# this includes braking motion rather than assuming an instantaneous pivot.
	var sweep=absf(error)+2.0*yaw_stop
	var steps=maxi(1,int(ceil(sweep/Clearance.ANGLE_STEP)))
	var direction=signf(error) if absf(error)>1e-9 else 1.0
	for i in steps+1:
		poses.append({"x":own.position.x,"z":own.position.z,"heading":own.heading-direction*yaw_stop+direction*sweep*i/steps,"padding":padding})
	# Every outgoing native nine-point footprint at half-meter intervals is
	# expanded for continuous translation, one-tick acceleration, heading error,
	# measured residual drift and the complete furled stopping reserve.
	var acceleration: float=own.lateral_acceleration+own.sail_acceleration*MAX_SAIL
	var future_speed=maxf(own.speed,SPEED_CAP)+acceleration/60.0
	if future_speed/own.brake>Clearance.STOP_SECONDS:return {"ok":false,"reason":"stop-reserve"}
	var travel_padding: float=0.25+radius*COURSE_TOLERANCE+distance*sin(COURSE_TOLERANCE)+future_speed*future_speed/(2.0*own.brake)+drift
	steps=maxi(1,int(ceil(distance/0.5)))
	for i in steps+1:
		poses.append({"x":lerpf(own.position.x,node.x,float(i)/steps),"z":lerpf(own.position.z,node.z,float(i)/steps),"heading":course,"padding":travel_padding})
	for pose: Dictionary in poses:
		if not _wet_envelope(own.dimensions,pose,terrain,sea_level):return {"ok":false,"reason":"swept-depth","pose":pose}
		for peer: Dictionary in peers:
			if Clearance._moving_overlap(own.dimensions,pose,peer,HORIZON):return {"ok":false,"reason":"predicted-peer","peerId":peer.id}
	return {"ok":true,"course":course,"distance":distance,"horizon":HORIZON,"padding":travel_padding}
static func _wet_envelope(dimensions: Dictionary,pose: Dictionary,terrain: Callable,sea_level: float) -> bool:
	if not terrain.is_valid():return false
	# Retain every actual native point; an expanded rectangle's nine points
	# alone omit actual corners. Probe each point's uncertainty neighborhood,
	# not merely the larger rectangle. Native next-tick contacts remain final.
	var padding: float=pose.padding
	for forward in [-0.5,0.0,0.5]:
		for side in [-0.5,0.0,0.5]:
			var x: float=pose.x+cos(pose.heading)*dimensions.length*forward-sin(pose.heading)*dimensions.width*side
			var z: float=pose.z+sin(pose.heading)*dimensions.length*forward+cos(pose.heading)*dimensions.width*side
			for dx in [-padding,0.0,padding]:
				for dz in [-padding,0.0,padding]:
					var height=terrain.call(x+dx,z+dz)
					if not (height is float or height is int) or not is_finite(height) or height>=sea_level-dimensions.draft:return false
	return Clearance._wet(dimensions,pose,terrain,sea_level)
static func _distance(a: Dictionary,b: Dictionary) -> float:
	return sqrt(pow(a.x-b.x,2)+pow(a.z-b.z,2))
