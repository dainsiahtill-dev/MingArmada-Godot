extends RefCounted
# Numeric prediction only. No vessel/domain mutation. Peers retain measured
# velocity/yaw over a bounded interval; fresh checks and native contacts remain
# necessary when their controls or the environment change.
const ANGLE_STEP = PI / 90.0
const TRAVEL_SECONDS = 1.0
const TURN_SECONDS = 40.0
const STOP_SECONDS = 19.0
const MAX_HORIZON = TURN_SECONDS + STOP_SECONDS + TRAVEL_SECONDS
static func assess(own: Dictionary, peers: Array, terrain: Callable, sea_level: float) -> Dictionary:
	var error = wrapf(own.course - own.heading, -PI, PI)
	if own.brake <= 0.0 or own.yaw_damping <= 0.0: return {"ok":false,"reason":"insufficient-braking"}
	var stop_time: float = own.speed / own.brake
	var yaw_stop_time: float = maxf(0.0,log(maxf(absf(own.yawRate),0.005)/0.005)/own.yaw_damping)
	if maxf(stop_time,yaw_stop_time)>STOP_SECONDS: return {"ok":false,"reason":"stop-reserve"}
	# Encounter enforces a forty-second maximum turn, then neutral braking.
	# This horizon does not assume the proportional controller reaches its
	# target at a full-rudder constant rate. The final second is outgoing travel.
	var horizon = MAX_HORIZON
	var radius = sqrt(own.dimensions.length * own.dimensions.length + own.dimensions.width * own.dimensions.width) / 2.0
	# Brake must overcome bounded lateral crew/rudder acceleration. This radius
	# covers all directions of residual travel; no instantaneous pivot is assumed.
	var drift: float = own.speed * own.speed / (2.0 * own.brake) + own.speed / 60.0
	var yaw_stop: float = absf(own.yawRate) / own.yaw_damping
	var angular_pad: float = radius * ANGLE_STEP / 2.0
	var padding: float = 0.15 + drift + angular_pad
	var poses: Array = []
	var sweep = absf(error) + 2.0 * yaw_stop
	var steps = maxi(1, int(ceil(sweep / ANGLE_STEP)))
	for index in steps + 1:
		poses.append({"x":own.position.x,"z":own.position.z,"heading":own.heading - signf(error)*yaw_stop + signf(error)*sweep*index/steps,"padding":padding})
	# Outgoing travel is limited to a finite one-second acceleration and braking
	# envelope, bounded by the real target plus stopping distance. It is not a
	# claim that the entire trip or an arbitrary 45m beyond the port is clear.
	# Existing sailRecovery rises at .25/s after fully furled recovery. Integrate
	# that ramp instead of inventing a full-sail impulse at the end of the turn.
	var acceleration: float = own.lateral_acceleration + own.sail_acceleration*own.sail_start
	var future_speed: float = own.speed + acceleration*TRAVEL_SECONDS + own.sail_acceleration*0.25*TRAVEL_SECONDS*TRAVEL_SECONDS/2.0
	if future_speed > 1.2: return {"ok":false,"reason":"travel-speed-bound"}
	if future_speed/own.brake>STOP_SECONDS: return {"ok":false,"reason":"stop-reserve"}
	var travel: float = minf(own.distance,own.speed*TRAVEL_SECONDS+acceleration*TRAVEL_SECONDS*TRAVEL_SECONDS/2.0+own.sail_acceleration*0.25*pow(TRAVEL_SECONDS,3)/6.0)
	var stop_distance: float = future_speed * future_speed / (2.0 * own.brake)
	var travel_pad: float = padding + stop_distance + travel * sin(PI / 36.0)
	var travel_steps = maxi(1, int(ceil(travel / 0.5)))
	for index in travel_steps + 1:
		var ahead = travel * index / travel_steps
		poses.append({"x":own.position.x + cos(own.course) * ahead,"z":own.position.z + sin(own.course) * ahead,"heading":own.course,"padding":travel_pad + 0.25})
	for pose: Dictionary in poses:
		if not _wet(own.dimensions, pose, terrain, sea_level): return {"ok":false,"reason":"swept-depth","pose":pose}
		for peer: Dictionary in peers:
			if _moving_overlap(own.dimensions, pose, peer, horizon): return {"ok":false,"reason":"predicted-peer","peerId":peer.id}
	return {"ok":true,"horizon":horizon,"drift":drift,"travel":travel,"stoppingDistance":stop_distance}
static func _extent(dimensions: Dictionary, heading: float, axis: float) -> float:
	return absf(cos(heading-axis))*dimensions.length/2.0 + absf(sin(heading-axis))*dimensions.width/2.0
static func _moving_overlap(dimensions: Dictionary, pose: Dictionary, peer: Dictionary, horizon: float) -> bool:
	var radius = sqrt(peer.dimensions.length * peer.dimensions.length + peer.dimensions.width * peer.dimensions.width)/2.0
	# Continuous moving SAT: intersect the time interval of overlap on every
	# axis. Peer rotation is enclosed about its midpoint orientation by the
	# maximum angular arc. No moving peer can slip between temporal samples.
	var heading: float = peer.heading + peer.yawRate*horizon/2.0
	var padding: float = pose.padding + radius*absf(peer.yawRate)*horizon/2.0
	var dx: float = peer.position.x-pose.x
	var dz: float = peer.position.z-pose.z
	var entered = 0.0
	var exited = horizon
	for axis in [pose.heading,pose.heading+PI/2,heading,heading+PI/2]:
		var separation: float = dx*cos(axis)+dz*sin(axis)
		var velocity: float = peer.velocity.x*cos(axis)+peer.velocity.z*sin(axis)
		var extent = _extent(dimensions,pose.heading,axis)+_extent(peer.dimensions,heading,axis)+padding
		if absf(velocity)<1e-9:
			if absf(separation)>=extent: return false
			continue
		var first = (-extent-separation)/velocity
		var last = (extent-separation)/velocity
		entered=maxf(entered,minf(first,last));exited=minf(exited,maxf(first,last))
		if entered>exited: return false
	return true
static func _wet(dimensions: Dictionary, pose: Dictionary, terrain: Callable, sea_level: float) -> bool:
	if not terrain.is_valid(): return false
	var length: float = dimensions.length + pose.padding * 2.0
	var width: float = dimensions.width + pose.padding * 2.0
	# Match native nine-point wet-hull sampling, expanded for the bounded drift
	# and sampling arc. Native shore sweep still handles the actual next step.
	for forward in [-0.5,0.0,0.5]:
		for side in [-0.5,0.0,0.5]:
			var height = terrain.call(pose.x+cos(pose.heading)*length*forward-sin(pose.heading)*width*side,pose.z+sin(pose.heading)*length*forward+cos(pose.heading)*width*side)
			if not (height is float or height is int) or not is_finite(height) or height >= sea_level-dimensions.draft: return false
	return true
