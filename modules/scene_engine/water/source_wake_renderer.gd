extends RefCounted
## Production route owner behind the existing Wakes seam. No independent clock.
const History=preload("res://modules/scene_engine/water/source_wake_history.gd")
const Battle=preload("res://modules/scene_engine/water/source_battle_trail.gd")
const Geometry=preload("res://modules/scene_engine/water/source_wake_geometry.gd")
const Surface=preload("res://modules/scene_engine/water/source_surface.gd")
const Froth=preload("res://modules/scene_engine/water/source_froth.gd")
var _actors:Dictionary={}
var _owner:Node3D
var _epoch:Variant=null
var _time:=-1.0
var _errors:Dictionary={}
func _init(parent:Node3D)->void:_owner=parent
func transfer_owner(parent:Node3D)->void:
	# In-memory quality rebuild transfers sole ownership, retaining original
	# call index, histories, controller clocks and particle RNG/pools exactly.
	for actor:Dictionary in _actors.values():
		if actor.node.get_parent()!=null:actor.node.get_parent().remove_child(actor.node)
		if parent!=null:parent.add_child(actor.node)
	_owner=parent
static func route(native:Dictionary,ship:Dictionary={})->String:
	var attached:Dictionary=ship.get("sourceWake",{})
	if attached.has("route"):return str(attached.route)
	var wake:Dictionary=native.get("wake",{})
	if wake.has("route"):return str(wake.route)
	# Frozen environment.route is a gameplay string (sailing/battle), not
	# source-wake authority. Never eagerly call Dictionary.get on that string.
	var environment_route:Variant=native.get("environment",{}).get("route",null)
	return str(environment_route.get("wake","")) if environment_route is Dictionary else ""
func apply_snapshot(native:Dictionary,water:Callable,sea:Callable)->void:
	var epoch:Variant=native.get("wake",{}).get("epoch",native.get("environment",{}).get("epoch",0))
	if _epoch!=null and _epoch!=epoch:dispose()
	_epoch=epoch;_time=float(native.get("time",_time))
	var live:Dictionary={}
	for ship:Dictionary in native.get("ships",[]):
		var selected:=route(native,ship)
		if selected not in ["scene_30","battle_90"]:continue
		var id:=str(ship.get("id",""));var packet:Dictionary=ship.get("sourceWake",{})
		if id.is_empty() or not packet.has("sourcePosition") or not packet.has("sourceClock") or not packet.has("modelScale") or not is_finite(float(packet.get("sourceToWorld",NAN))) or float(packet.get("sourceToWorld",0.0))<=0.0 or not is_finite(float(packet.modelScale)) or float(packet.modelScale)<=0.0:
			_errors[id]="Explicit source position/clock/model scale/units missing";continue
		live[id]=true
		_errors.erase(id)
		if _actors.has(id) and _actors[id].route!=selected:_release(id)
		if not _actors.has(id):
			var node:=Node3D.new();node.name="SourceWake_"+id;_owner.add_child(node)
			var actor:Dictionary={"node":node,"route":selected,"surface":Surface.new(node),"call":null,"history":null,"battle_history":{},"froth":null,"geometry":{}}
			if selected=="scene_30":actor.history=History.new(packet.get("ini",{}),packet.modelScale,packet.get("markerId","root"),packet.sourcePosition)
			var froth_packet:Dictionary=packet.get("froth",{})
			if (froth_packet.has("family") or froth_packet.has("sourceResourceName")) and froth_packet.has("seed"):
				actor.froth=Froth.new();var configured:Dictionary=actor.froth.configure(node,int(froth_packet.get("family",-1)),int(froth_packet.seed),str(froth_packet.get("sourceResourceName","")))
				if not configured.ok:_errors[id]=configured.error
			_actors[id]=actor
		var actor:Dictionary=_actors[id];var call_index:Variant=packet.get("sourceCallIndex",native.get("wake",{}).get("sourceCallIndex",null))
		if call_index==null:_errors[id]="Explicit source-call index missing";continue
		if actor.call!=null and int(call_index)<=int(actor.call):continue
		actor.call=call_index
		if selected=="scene_30":
			var accepted:bool=actor.history.update(packet.sourcePosition,float(packet.sourceClock),packet.get("markerId","root"))
			if accepted:actor.geometry=Geometry.build(actor.history,packet,_time,water,sea)
			# Source distance rejection holds source rows. Target water fit still
			# follows accepted ocean time without recomputing source profile/alpha.
			elif actor.history.last_result=="distance-rejected" and not actor.geometry.is_empty():
				_fit_water(actor.geometry,_time,water)
			if not actor.geometry.is_empty():actor.surface.submit("SceneStrip",actor.geometry.vertices,actor.geometry.uvs,actor.geometry.colors,actor.geometry.indices,{"texture":"wake3unique.dds","alphaFlags":4333,"clampMode":3})
		else:_battle(actor,packet,water,sea)
		if actor.froth!=null:
			var attached:=packet.duplicate();attached.merge(packet.get("froth",{}),true)
			actor.froth.apply_snapshot(attached,_time,water,sea)
	for id:String in _actors.keys():
		if not live.has(id):_release(id)

static func _fit_water(geometry:Dictionary,time:float,water:Callable)->void:
	if not water.is_valid():return
	var vertices:PackedVector3Array=geometry.vertices
	for i in vertices.size():
		var height:=float(water.call(vertices[i].x,vertices[i].z,time))
		if is_finite(height):vertices[i].y=height+0.10
	geometry.vertices=vertices

func _battle(actor:Dictionary,packet:Dictionary,water:Callable,sea:Callable)->void:
	var input:Dictionary=packet.get("battle",{}).duplicate(true)
	for field:String in ["type","tick","x","y","heading","map_origin_x","map_origin_y","sine_boundary","hold_history"]:
		if not input.has(field):_errors[actor.node.name]="Explicit original battle input missing: "+field;return
	if not input.has("history"):
		if actor.battle_history.is_empty():
			actor.battle_history={"x":[],"y":[],"heading":[]}
			for _i in 90:actor.battle_history.x.append(int(packet.sourcePosition[0]));actor.battle_history.y.append(int(packet.sourcePosition[1]));actor.battle_history.heading.append(int(input.heading))
		input.history=actor.battle_history
	var out:=Battle.draw(input);actor.battle_history=out.history;actor.geometry={"draw_arguments":out.draw_arguments,"native_equivalent":false,"adaptations":["source integer->target units","water_surface_fit","source draw carrier/material backend"]}
	var unit:=float(packet.sourceToWorld);var origin_array:Array=packet.get("worldOrigin",[0.0,0.0,0.0]);var origin:=Vector3(origin_array[0],origin_array[1],origin_array[2])
	for draw_index in out.draw_arguments.size():
		var args:Array=out.draw_arguments[draw_index];var vertices:=PackedVector3Array();var uvs:=PackedVector2Array();var colors:=PackedColorArray();var indices:=PackedInt32Array();var wet:Array=[]
		for i in 4:
			var p:=Surface.native_to_world([Battle.signed(int(args[i*3])),Battle.signed(int(args[i*3+1])),0.0],unit,origin)
			if water.is_valid():
				var height:=float(water.call(p.x,p.z,_time))
				if is_finite(height):p.y=height+0.10+float(draw_index%3)*0.002
			vertices.append(p);wet.append(not sea.is_valid() or bool(sea.call(p.x,p.z)))
			uvs.append(Vector2(float(args[12+i*2])/1000.0,float(args[13+i*2])/1000.0));colors.append(Color(1,1,1,float((int(args[20+i])>>24)&255)/255.0))
		if wet[0] and wet[1] and wet[2]:indices.append_array(PackedInt32Array([0,2,1]))
		if wet[0] and wet[2] and wet[3]:indices.append_array(PackedInt32Array([0,3,2]))
		actor.surface.submit("BattleDraw_"+str(draw_index),vertices,uvs,colors,indices,{"texture":"wake3.dds","alphaFlags":4333,"clampMode":3})

func diagnostics()->Dictionary:
	var routes:Dictionary={};var updates:=0;var samples:=0;var froth_meshes:=0;var systems:=0;var births:=0;var regions:=0;var battle_draws:=0
	for actor:Dictionary in _actors.values():
		routes[actor.route]=int(routes.get(actor.route,0))+1;regions+=int(actor.surface.region_uploads)
		if actor.history!=null:
			updates+=actor.history.updates
			for point:Dictionary in actor.history.points:
				if point.active:samples+=1
		else:samples+=actor.battle_history.get("x",[]).size();battle_draws+=actor.geometry.get("draw_arguments",[]).size()
		if actor.froth!=null:
			var report:Dictionary=actor.froth.diagnostics();froth_meshes+=report.authored_meshes;systems+=report.particle_systems;births+=report.native_births
	return {"source_routes":routes,"source_updates":updates,"source_samples":samples,"authored_froth_meshes":froth_meshes,"source_particle_systems":systems,"source_particle_births":births,"source_battle_draws":battle_draws,"source_region_uploads":regions,"source_errors":_errors.duplicate(),"source_native_equivalent":false,"source_unresolved":["full strip/head/normalize/self-cross ABI","zero-length NaN LUT","475550 full lifecycle","DX9 backend/pixels"],"source_adaptations":["source units/accepted cadence","finite first-frame tangent/profile guard","target water surface fit","sea clipping","battle material carrier"]}
func _release(id:String)->void:
	var actor:Dictionary=_actors[id]
	if actor.froth!=null:actor.froth.dispose()
	actor.surface.dispose();actor.node.free();_actors.erase(id)
func dispose()->void:
	for id:String in _actors.keys():_release(id)
	_epoch=null;_time=-1.0;_errors.clear()
