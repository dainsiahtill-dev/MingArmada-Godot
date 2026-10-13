extends RefCounted
## Explicit target scene units/cadence/ship-class adapter. Native formulas live
## in water modules; these mappings are not recovered original actor producers.
const FAMILIES := {"sloop1":0,"ship_brigantine":1,"frigate":2,"barque":3,"ship_merman":5,"treasure_galleon":6}
const FROTH_NAMES := ["sloop","brigantine","frigate","barque","fluyt","merchantman","treasuregalleon","fast_galleon","tartane"]
static func native_vector(p:Vector3)->Array:return [p.x,-p.z,p.y]
static func native_rotation(b:Basis)->Array:
	var axes:=Basis(Vector3.RIGHT,Vector3(0,0,-1),Vector3.UP)
	var r:=axes.inverse()*b*axes
	return [r.x.x,r.y.x,r.z.x,r.x.y,r.y.y,r.z.y,r.x.z,r.y.z,r.z.z]
static func compose(native:Dictionary,actors:Dictionary,camera:Camera3D)->Dictionary:
	var result:=native.duplicate(false)
	result.ships=[]
	for ship:Dictionary in native.get("ships",[]):result.ships.append(ship.duplicate(false))
	var environment:Dictionary=native.get("environment",{})
	var time:=float(environment.get("acceptedTime",native.get("time",0.0)))
	var call_index:=int(environment.get("sourceCallIndex",floor(time*32.0)))
	var route:="battle_90" if environment.get("route","sailing")=="battle" else "scene_30"
	result.wake={"route":route,"epoch":environment.get("epoch",native.get("battleId","")),"sourceCallIndex":call_index,"adaptation":"target accepted cadence and native model units"}
	for state:Dictionary in result.get("ships",[]):
		var actor:Node3D=actors.get(str(state.get("id","")))
		if actor==null or not actor.has_method("source_water_attachment"):continue
		var attachment:Dictionary=actor.source_water_attachment()
		if attachment.is_empty():continue
		var unit:=float(attachment.sourceToWorld)
		var raw_position:=native_vector(attachment.wake/unit)
		# Only the 30-point sailing path uses planar travel. Battle's native
		# integer XY input and independent local froth retain the raw marker.
		var position:=native_vector(attachment.get("trail",attachment.wake)/unit) if route=="scene_30" else raw_position
		var bow:=native_vector(attachment.bow/unit)
		var family:=int(FAMILIES.get(attachment.sourceResourceName,0))
		var visual:Dictionary=state.get("visual",state)
		var velocity:Dictionary=visual.get("velocity",state.get("velocity",{}))
		var speed:=Vector2(float(velocity.get("x",0.0)),float(velocity.get("z",velocity.get("y",0.0)))).length()
		var enabled:=speed>0.35 and float(state.get("hull",100.0))>0.0 and not bool(state.get("sunk",false)) and float(state.get("sailDeployment",1.0))>0.0
		var packet:={"route":route,"sourcePosition":position,"markerId":attachment.markerId,"sourceClock":time,"modelScale":attachment.modelScale,"sourceToWorld":unit,"worldOrigin":[0.0,0.0,0.0],"sourceCallIndex":call_index,"epoch":result.wake.epoch,"sourceRotation":native_rotation(attachment.rotation),"adaptation":"native lowend markers; target scene30 yaw-only horizontal travel input, raw battle/froth poses, world coordinates and family selection"}
		packet.froth={"family":family,"sourceResourceName":"fx_ship_sidefroth_"+FROTH_NAMES[family]+".nif","sourcePosition":raw_position,"sourceBowPosition":bow,"controllerAppTime":time,"enabled":enabled,"seed":absi(str(state.id).hash())%2147483647,"scalePolicy":"target actual model root scale; native class scale table unavailable"}
		if is_instance_valid(camera):
			packet.froth.sourceCamera={"right":native_vector(camera.global_basis.x),"up":native_vector(camera.global_basis.y),"direction":native_vector(-camera.global_basis.z)}
		# 4756B0 coordinates divide by 400; invert that target mapping. Source
		# heading uses sin/cos fixed turns. Class enum is explicitly target-selected.
		var heading:=float(visual.get("heading",0.0))
		var fixed_heading:=int(fposmod(heading+PI/2.0,TAU)/TAU*4294967296.0)
		if fixed_heading>=2147483648:fixed_heading-=4294967296
		packet.battle={"type":family,"tick":call_index,"hold_history":false,"x":roundi(float(position[0])*400.0),"y":roundi(float(position[1])*400.0),"heading":fixed_heading,"map_origin_x":0,"map_origin_y":0,"sine_boundary":65536,"adaptation":"target inverse divide400 and selected resource family; original class mapping unavailable"}
		state.sourceWake=packet
	return result
