extends RefCounted
## Private diagnostic: replay already-presented methods at the same accepted
## time/camera. No simulation advance, actor removal, effect toggle or FPS claim.
const Crew=preload("res://game/presentation/crew/crew_view.gd")

static func _elapsed(start:int)->float:
	return float(Time.get_ticks_usec()-start)/1000.0

static func sample(sea:Node3D,native:Dictionary)->Dictionary:
	if not is_instance_valid(sea) or bool(sea.get("_disposed")):
		return {"ok":false,"reason":"presentation-disposed"}
	var accepted:Variant=native.get("time")
	if not (accepted is float or accepted is int) or not is_finite(float(accepted)) or not native.get("ships") is Array:
		return {"ok":false,"reason":"invalid-native-snapshot"}
	var prior:Dictionary=sea.get("_snapshot")
	if prior.is_empty() or prior.get("time")!=accepted or prior.get("battleId","")!=native.get("battleId",""):
		return {"ok":false,"reason":"snapshot-must-already-be-presented"}
	var camera:Camera3D=sea.get("camera")
	var views:Dictionary=sea.get("ships")
	var sailors:Dictionary=sea.get("sailors")
	var effects:Node3D=sea.get("effects")
	var wakes:Node3D=sea.get("wakes")
	var world:Node3D=sea.get("world")
	if not is_instance_valid(camera) or not is_instance_valid(effects) or not is_instance_valid(wakes) or not is_instance_valid(world):
		return {"ok":false,"reason":"presentation-owner-missing"}
	var fleet:Array=native.ships
	if views.size()!=fleet.size() or sailors.size()!=fleet.size():
		return {"ok":false,"reason":"fleet-must-already-be-instantiated"}
	for ship:Dictionary in fleet:
		var id:String=str(ship.get("id",""))
		if not views.has(id) or not sailors.has(id) or not is_instance_valid(views[id]) or not is_instance_valid(sailors[id]):
			return {"ok":false,"reason":"fleet-must-already-be-instantiated","shipId":id}
		if views[id].get("_time")!=accepted or sailors[id].get("_time")!=accepted or views[id].get("_kind")!=ship.get("kind"):
			return {"ok":false,"reason":"ship-must-already-match-snapshot","shipId":id}
	# This order and the allocation request thresholds match NavalWorldView.
	# consumed=0 preserves accepted time, recoil and impact integration state.
	var method_ms:Dictionary={"effects":0.0,"allocation":0.0,"shipCopy":0.0,"shipApply":0.0,"shipLOD":0.0,"crewModel":0.0,"crewLOD":0.0,"crewAllocation":0.0,"crewApply":0.0,"wakes":0.0,"world":0.0}
	var start:int=Time.get_ticks_usec()
	effects.apply_snapshot(native,0.0)
	method_ms.effects=_elapsed(start)
	start=Time.get_ticks_usec()
	var requests:Array=[]
	for ship:Dictionary in fleet:
		var p:Dictionary=ship.visual.position
		var distance:float=camera.position.distance_to(Vector3(p.x,p.y,p.z))
		var count:int=int(ship.crew)
		var requested:int=mini(24,count) if distance<=220 else mini(8,count) if distance<=650 else mini(2,count) if distance<=1200 else 0
		requests.append({"id":ship.id,"distance":distance,"requested":requested})
	var allocations:Dictionary=Crew.allocate_sailors(requests)
	method_ms.allocation=_elapsed(start)
	var rows:Array=[]
	var kinds:Dictionary={}
	var crew_active:int=0
	for ship:Dictionary in fleet:
		var id:String=str(ship.id)
		var view:Node3D=views[id]
		var crew:Node3D=sailors[id]
		var row:Dictionary={"id":id,"kind":ship.kind,"methodMs":{}}
		var cost:Dictionary=row.methodMs
		start=Time.get_ticks_usec()
		var timed:Dictionary=ship.duplicate(true)
		timed.time=accepted
		cost.shipCopy=_elapsed(start)
		start=Time.get_ticks_usec()
		view.apply_snapshot(timed,native.get("wind",{}),0.0)
		cost.shipApply=_elapsed(start)
		start=Time.get_ticks_usec()
		view.set_lod_distance(camera.position.distance_to(view.position))
		cost.shipLOD=_elapsed(start)
		start=Time.get_ticks_usec()
		crew.set_ship_model(view.get_model())
		cost.crewModel=_elapsed(start)
		start=Time.get_ticks_usec()
		crew.set_lod_distance(camera.position.distance_to(view.position))
		cost.crewLOD=_elapsed(start)
		start=Time.get_ticks_usec()
		crew.set_allocation(int(allocations.get(id,0)))
		cost.crewAllocation=_elapsed(start)
		start=Time.get_ticks_usec()
		crew.apply_snapshot(timed,native.get("wind",{}),0.0)
		cost.crewApply=_elapsed(start)
		for key:String in cost:method_ms[key]+=float(cost[key])
		# Metadata collection is outside every method's measured interval.
		var diagnostic:Dictionary=crew.diagnostics()
		var clips:Dictionary={}
		for role:Dictionary in diagnostic.get("roles",[]):
			var clip:String=str(role.get("clip",""))
			clips[clip]=int(clips.get(clip,0))+1
		row.crew={"active":diagnostic.get("visible",0),"lod":diagnostic.get("lod",0),"impacts":diagnostic.get("impact_count",0),"clips":clips}
		row.shipLOD=view.get_lod()
		row.modelInstances=(view.get("_models") as Array).size()
		row.allocated=int(allocations.get(id,0))
		kinds[str(ship.kind)]=int(kinds.get(str(ship.kind),0))+1
		crew_active+=int(diagnostic.get("visible",0))
		rows.append(row)
	var wake_same_time:bool=wakes.get("_time")==accepted
	start=Time.get_ticks_usec()
	wakes.apply_snapshot(native)
	method_ms.wakes=_elapsed(start)
	var focus:Vector3=sea.get("_last_target")
	start=Time.get_ticks_usec()
	world.apply_snapshot({"time":accepted,"wind":native.get("wind",{}),"battleId":native.get("battleId",""),"focus":{"x":focus.x,"z":focus.z}},0.0)
	method_ms.world=_elapsed(start)
	var total:float=0.0
	for value:Variant in method_ms.values():total+=float(value)
	var world_detail: Dictionary={}
	var ocean: Node3D=world.get_ocean()
	start=Time.get_ticks_usec(); ocean.set_simulation_time(float(accepted))
	world_detail.oceanTime=_elapsed(start)
	start=Time.get_ticks_usec(); ocean.update_projection()
	world_detail.oceanProjection=_elapsed(start)
	start=Time.get_ticks_usec()
	var natural: Node3D=world.get("_natural_world")
	if is_instance_valid(natural): natural.apply_snapshot({"time":accepted,"focus":Vector2(focus.x,focus.z)},0.0)
	world_detail.naturalWorld=_elapsed(start)
	var forest_state: Dictionary={"time":accepted,"focus":Vector2(focus.x,focus.z),"lighting":{"lightDirection":Vector3(0.5,-0.8,-0.3).normalized(),"lightColor":Vector3(1,0.95,0.82),"ambient":Vector3(0.35,0.40,0.30),"customFog":false}}
	start=Time.get_ticks_usec()
	if is_instance_valid(natural):
		for trees: Node3D in natural.get("_trees"): trees.apply_snapshot(forest_state,0.0)
	world_detail.forest=_elapsed(start)
	start=Time.get_ticks_usec()
	if is_instance_valid(natural):
		for surf: Node3D in natural.get("_dynamic_shore"): surf.apply_snapshot({"time":accepted,"focus":Vector2(focus.x,focus.z)},0.0)
	world_detail.shore=_elapsed(start)
	start=Time.get_ticks_usec()
	var weather: RefCounted=world.get("atmosphere")
	if weather: weather.apply_snapshot({"time":accepted},camera,Vector3(focus.x,0,focus.z))
	world_detail.atmosphere=_elapsed(start)
	return {"ok":true,"scope":"CPU same-time method replay; excludes camera/event handling, Sea snapshot copy and metadata collection; not FPS/GPU timing","acceptedTime":accepted,"consumed":0.0,"shipCount":fleet.size(),"kinds":kinds,"crewActive":crew_active,"methodMs":method_ms,"worldDetailMs":world_detail,"methodTotalMs":total,"ships":rows,"wakesSameTimeReentry":wake_same_time,"sourceFire":(effects.get("_source_fire") as Array).size(),"projectiles":(effects.get("_balls") as Dictionary).size()}
