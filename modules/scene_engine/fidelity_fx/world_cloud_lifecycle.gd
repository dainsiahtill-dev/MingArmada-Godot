extends RefCounted
## Target-only visual trajectories. Native weather/RNG and three actor budgets
## stay authoritative; whole cloud/shadow bounds must exit before recycling.
const VIEW_MARGIN_METRES:=48.0
const VELOCITY_RESPONSE_SECONDS:=0.2
var _actors:Dictionary={}
func clear()->void:_actors.clear()
func snapshot()->Dictionary:return _actors.duplicate(true)
func restore(state:Dictionary)->void:_actors=state.duplicate(true)
func rebase_time(time:float)->void:
	if not is_finite(time) or time<0.0:return
	# Resuming a display hold starts from the retained pose, without catch-up.
	for state:Dictionary in _actors.values():state.time=time
static func vector(value:Array)->Vector3:return Vector3(float(value[0]),float(value[1]),float(value[2]))
func advance(index:int,packet:Dictionary,time:float,radius:float,visible:Callable)->Dictionary:
	var raw:=vector(packet.worldPosition)
	var velocity:=vector(packet.get("driftVelocity",[0.0,0.0,0.0]))
	var generation:=int(packet.get("generation",0))
	if not raw.is_finite() or not velocity.is_finite() or not is_finite(time) or not is_finite(radius) or radius<0.0:return {}
	if not _actors.has(index) or time<float(_actors[index].time):
		_actors[index]={"position":raw,"velocity":velocity,"time":time,"generation":generation,"retiring":false,"recycles":0,"waiting":0}
	var state:Dictionary=_actors[index]
	# Camera-only refreshes can change visibility but never advance/recycle.
	if time<=float(state.time):return state.duplicate(true)
	var dt:=time-float(state.time)
	state.time=time
	if generation!=int(state.generation):
		state.generation=generation;state.retiring=true
	var previous_velocity:=Vector3(state.velocity)
	var decay:=exp(-dt/VELOCITY_RESPONSE_SECONDS)
	# Integrate the complete exponential transition, independent of frame splits.
	state.position=Vector3(state.position)+velocity*dt+(previous_velocity-velocity)*VELOCITY_RESPONSE_SECONDS*(1.0-decay)
	state.velocity=velocity+(previous_velocity-velocity)*decay
	if state.retiring and not visible.call(state.position,radius+VIEW_MARGIN_METRES):
		var candidate:=raw
		var incoming:=-Vector3(state.velocity).normalized()
		var stride:=maxf(128.0,2.0*(radius+VIEW_MARGIN_METRES))
		var available:bool=not bool(visible.call(candidate,radius+VIEW_MARGIN_METRES))
		# Bounded search; waiting is preferable to an on-screen replacement.
		for attempt in 64:
			if available or incoming.length_squared()<0.0001:break
			candidate+=incoming*stride
			available=not visible.call(candidate,radius+VIEW_MARGIN_METRES)
		if available:
			state.position=candidate;state.retiring=false;state.recycles+=1
		else:state.waiting+=1
	return state.duplicate(true)
static func sphere_in_views(center:Vector3,radius:float,planes:Array[Plane],additional_planes:Array[Plane]=[])->bool:
	return _sphere_in_frustum(center,radius,planes) or (not additional_planes.is_empty() and _sphere_in_frustum(center,radius,additional_planes))
static func _sphere_in_frustum(center:Vector3,radius:float,planes:Array[Plane])->bool:
	for plane:Plane in planes:
		if plane.distance_to(center)>radius:return false
	return true
