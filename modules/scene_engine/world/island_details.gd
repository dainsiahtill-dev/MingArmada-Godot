extends Node3D
## Deterministic coastal dressing. Read-only geography, no simulation ownership.
const Library=preload("res://modules/scene_engine/assets/coastal_detail_library.gd")
const HARD_INSTANCE_LIMIT:=4096
const PIER_TOP:=4.45
var _sampler: Callable
var _ports: Array=[]
var _library: RefCounted
var _groups: Array[MultiMeshInstance3D]=[]
var _placements: Array=[]
var _batches: Dictionary={}
var _budget:=0
var _density:=1.0
var _seed:=0
var _focus_distance:=1000.0
var _simulation_time:=0.0
var _disposed:=true

func configure(height_sampler: Callable,ports: Array,options: Dictionary={}) -> bool:
	dispose()
	if not height_sampler.is_valid(): return false
	if ports.size()>64: return false
	for port in ports:
		if not port is Dictionary: return false
		for key in ["x","z","islandX","islandZ","radius"]:
			if not port.has(key) or not is_finite(float(port[key])): return false
		if float(port.radius)<=0.0: return false
	_sampler=height_sampler; _ports=ports.duplicate(true)
	_ports.sort_custom(func(a: Dictionary,b: Dictionary)->bool: return _identity(a)<_identity(b))
	_seed=int(options.get("seed",0))
	var quality:=String(options.get("quality","balanced"))
	_density=0.55 if quality=="low" else (1.4 if quality=="high" else 1.0)
	_budget=clampi(int(options.get("max_instances",2200)),0,HARD_INSTANCE_LIMIT)
	_focus_distance=clampf(float(options.get("focus_distance",1000.0)),150.0,10000.0)
	if not is_finite(_focus_distance): _focus_distance=1000.0
	_library=Library.new(); _disposed=false
	for port: Dictionary in _ports:
		_build_island(port)
	_build_batches()
	return true

func _identity(port: Dictionary) -> String:
	return String(port.get("id","%s,%s" % [port.islandX,port.islandZ]))

func _build_island(port: Dictionary) -> void:
	var rng:=RandomNumberGenerator.new(); rng.seed=int(_identity(port).hash())+_seed*104729
	var phase:=rng.randf()*TAU
	var sectors:=int(44*_density)
	for index in sectors:
		if _placements.size()>=_budget: break
		var angle:=phase+index*TAU/sectors+rng.randf_range(-0.035,0.035)
		# Broken geological clusters, interrupted by broad clear beach sections.
		var cluster:=sin(angle*3.0+phase)>-0.15
		var shore:=_contour(port,angle,rng.randf_range(0.35,1.75))
		if shore.is_finite():
			if cluster and index%2==0:
				_place(port,"outcrop","land",shore,Vector3(rng.randf_range(3.8,8.8),rng.randf_range(1.7,4.7),rng.randf_range(3.0,7.0)),rng)
			for pebble_index in (3 if cluster else 1):
				var nearby:=Vector2(shore.x,shore.z)+Vector2(rng.randf_range(-5,5),rng.randf_range(-5,5))
				var h:=float(_sampler.call(nearby.x,nearby.y))
				if is_finite(h) and h>=0.12 and h<4.0:
					_place(port,"pebble","land",Vector3(nearby.x,h,nearby.y),Vector3(rng.randf_range(0.35,1.4),rng.randf_range(0.18,0.65),rng.randf_range(0.4,1.2)),rng)
		if cluster and index%3==0:
			var reef:=_contour(port,angle+0.03,rng.randf_range(-2.4,-0.55))
			if reef.is_finite(): _place(port,"reef","reef",reef,Vector3(rng.randf_range(2.2,5.1),minf(-reef.y*0.74,1.8),rng.randf_range(2.0,4.6)),rng)
		var dune:=_contour(port,angle+rng.randf_range(-0.045,0.045),rng.randf_range(2.2,4.8))
		if dune.is_finite() and index%2==0:
			for clump in 2:
				var offset:=Vector2(dune.x,dune.z)+Vector2(rng.randf_range(-2.0,2.0),rng.randf_range(-2.0,2.0))
				var h:=float(_sampler.call(offset.x,offset.y))
				if is_finite(h) and h>=0.12:
					var size:=rng.randf_range(2.5,3.2) if h>6.0 else rng.randf_range(1.0,1.85)
					_place(port,"beach_grass","land",Vector3(offset.x,h,offset.y),Vector3.ONE*size,rng)
		if dune.is_finite() and index%4==0:
			_place(port,"shrub","land",dune,Vector3.ONE*rng.randf_range(1.2,2.35),rng)
	_build_interior_patches(port,rng,phase)
	# Edge-only harbor props; deck center remains a two-way loading lane.
	var kinds:= ["crate","barrel","rope_coil","basket","cargo_net","bollard","crate","barrel","lantern"]
	for index in 18:
		var local:=Vector2((-1.0 if index%2==0 else 1.0)*rng.randf_range(2.35,2.75),3.0+floori(index/2.0)*4.7)
		var point:=_pier_world(port,local)
		var kind: String=kinds[index%kinds.size()]
		# Taller cargo reads from the ship camera; narrow footprint stays on deck.
		var scale:=Vector3(rng.randf_range(1.04,1.18),rng.randf_range(1.35,1.7),rng.randf_range(1.08,1.25))
		if kind in ["rope_coil","cargo_net"]: scale=Vector3(1.08,1.22,1.18)
		_place(port,kind,"dock",Vector3(point.x,PIER_TOP,point.y),scale,rng,local)

func _build_interior_patches(port: Dictionary,rng: RandomNumberGenerator,phase: float) -> void:
	var center:=Vector2(float(port.islandX),float(port.islandZ))
	var radius:=float(port.radius)
	# Three irregular patches, broad empty land between them. Reuse understory and
	# low weathered rock silhouettes rather than adding trees or asset categories.
	for patch in 3:
		var angle:=phase+patch*TAU/3.0+rng.randf_range(-0.3,0.3)
		var patch_center:=center+Vector2(cos(angle),sin(angle)*0.82)*radius*rng.randf_range(0.28,0.53)
		var breadth:=rng.randf_range(12.0,21.0)*clampf(radius/130.0,0.8,1.35)
		for index in int(22*_density):
			var scatter_angle:=rng.randf()*TAU
			var distance:=sqrt(rng.randf())*breadth
			var offset:=Vector2(cos(scatter_angle)*distance,sin(scatter_angle)*distance*0.56).rotated(angle+0.6)
			var point:=patch_center+offset
			var height:=float(_sampler.call(point.x,point.y))
			if not is_finite(height) or height<=6.0: continue
			var kind: String="shrub" if index%3==0 else "beach_grass"
			var scale:=Vector3.ONE*rng.randf_range(2.5,4.4)
			if index%7==0:
				kind="outcrop"; scale=Vector3(rng.randf_range(3.0,6.0),rng.randf_range(0.55,1.1),rng.randf_range(2.7,5.2))
			_place(port,kind,"land",Vector3(point.x,height,point.y),scale,rng)

func _contour(port: Dictionary,angle: float,target: float) -> Vector3:
	var center:=Vector2(float(port.islandX),float(port.islandZ))
	var direction:=Vector2(cos(angle),sin(angle)*0.82)
	var radius:=float(port.radius)
	var outer:=1.15; var inner:=0.12
	var lo:=center+direction*radius*outer; var hi:=center+direction*radius*inner
	var low_h:=float(_sampler.call(lo.x,lo.y)); var high_h:=float(_sampler.call(hi.x,hi.y))
	if not is_finite(low_h) or not is_finite(high_h) or low_h>target or high_h<target: return Vector3(INF,INF,INF)
	for iteration in 14:
		var middle:=(outer+inner)*0.5; var p:=center+direction*radius*middle
		var h:=float(_sampler.call(p.x,p.y))
		if not is_finite(h): return Vector3(INF,INF,INF)
		if h<target: outer=middle
		else: inner=middle
	var point:=center+direction*radius*((outer+inner)*0.5)
	var height:=float(_sampler.call(point.x,point.y))
	return Vector3(point.x,height,point.y) if is_finite(height) else Vector3(INF,INF,INF)

func _pier_angle(port: Dictionary) -> float:
	return atan2(float(port.islandX)-float(port.x),float(port.islandZ)-float(port.z))

func _pier_world(port: Dictionary,local: Vector2) -> Vector2:
	var angle:=_pier_angle(port)
	return Vector2(float(port.x),float(port.z))+Vector2(cos(angle)*local.x+sin(angle)*local.y,-sin(angle)*local.x+cos(angle)*local.y)

func _pier_local(port: Dictionary,point: Vector2) -> Vector2:
	var angle:=_pier_angle(port); var p:=point-Vector2(float(port.x),float(port.z))
	return Vector2(cos(angle)*p.x-sin(angle)*p.y,sin(angle)*p.x+cos(angle)*p.y)

func _excluded(point: Vector2,clearance: float) -> bool:
	for port: Dictionary in _ports:
		var local:=_pier_local(port,point)
		if absf(local.x)<13.0+clearance and local.y> -110.0-clearance and local.y<65.0+clearance: return true
		# Existing WorldView houses occupy a compact inner island ring.
		for index in 9:
			var house:=Vector2(float(port.islandX)+cos(index*2.15)*float(port.radius)*0.42,float(port.islandZ)+sin(index*2.15)*float(port.radius)*0.32)
			if point.distance_to(house)<9.0+clearance: return true
	for first in _ports.size():
		for second in range(first+1,_ports.size()):
			var a:=Vector2(float(_ports[first].x),float(_ports[first].z)); var b:=Vector2(float(_ports[second].x),float(_ports[second].z))
			var delta:=b-a
			if delta.length_squared()<0.01: continue
			var t:=clampf((point-a).dot(delta)/delta.length_squared(),0.0,1.0)
			if point.distance_to(a+delta*t)<24.0+clearance: return true
	return false

func _place(port: Dictionary,kind: String,zone: String,point: Vector3,size: Vector3,rng: RandomNumberGenerator,pier_local: Vector2=Vector2.INF) -> void:
	if _placements.size()>=_budget: return
	if zone!="dock" and _excluded(Vector2(point.x,point.z),maxf(size.x,size.z)*0.6): return
	if zone=="land" and point.y<0.12: return
	if zone=="reef" and (point.y< -2.6 or point.y> -0.18): return
	var variant:=rng.randi_range(0,2) if kind in ["outcrop","pebble","reef"] else 0
	var rotation:=rng.randf()*TAU if zone!="dock" else _pier_angle(port)+rng.randf_range(-0.25,0.25)
	var id:=_identity(port); var key:="%s/%s/%d" % [id,kind,variant]
	if not _batches.has(key): _batches[key]={"kind":kind,"variant":variant,"port":port,"transforms":[],"colors":[]}
	var basis:=Basis(Vector3.UP,rotation).scaled(size)
	_batches[key].transforms.append(Transform3D(basis,point))
	_batches[key].colors.append(Color.WHITE.darkened(rng.randf_range(0.0,0.16)))
	_placements.append({"port_id":id,"kind":kind,"zone":zone,"position":point,"scale":size,"pier_local":_pier_local(port,Vector2(point.x,point.z)) if zone!="dock" else pier_local})

func _build_batches() -> void:
	for key: String in _batches:
		var batch: Dictionary=_batches[key]
		var multi:=MultiMesh.new(); multi.transform_format=MultiMesh.TRANSFORM_3D; multi.use_colors=true
		multi.mesh=_library.get_mesh(batch.kind,batch.variant); multi.instance_count=batch.transforms.size()
		for index in multi.instance_count:
			multi.set_instance_transform(index,batch.transforms[index]); multi.set_instance_color(index,batch.colors[index])
		var node:=MultiMeshInstance3D.new(); node.name=key.replace("/","_"); node.multimesh=multi
		node.material_override=multi.mesh.surface_get_material(0)
		node.set_meta("island_center",Vector2(float(batch.port.islandX),float(batch.port.islandZ)))
		node.set_meta("island_radius",float(batch.port.radius))
		add_child(node); _groups.append(node)
	_batches.clear()

func apply_snapshot(snapshot: Dictionary,consumed: float=0.0) -> void:
	if _disposed: return
	var seconds:=float(snapshot.get("time",_simulation_time))
	if is_finite(seconds): _simulation_time=seconds
	var focus: Vector2=Vector2.ZERO; var input=snapshot.get("focus",Vector2.ZERO)
	if input is Vector2: focus=input
	elif input is Dictionary: focus=Vector2(float(input.get("x",0)),float(input.get("z",0)))
	if not focus.is_finite(): return
	for group in _groups:
		var center: Vector2=group.get_meta("island_center")
		group.visible=focus.distance_to(center)<=_focus_distance+float(group.get_meta("island_radius"))
	# Static art has no wall-clock/wind process; zero accepted time is exact.
	if consumed<0.0: return

func diagnostics() -> Dictionary:
	var resources: Dictionary=_library.diagnostics() if _library else {"mesh_count":0,"mesh_vertices":0,"material_count":0}
	var visible:=0
	for group in _groups:
		if group.visible: visible+=1
	return {"instance_count":_placements.size(),"group_count":_groups.size(),"visible_group_count":visible,"mesh_count":resources.mesh_count,"mesh_vertices":resources.mesh_vertices,"material_count":resources.material_count,"owned_nodes":_groups.size(),"instance_budget":_budget,"hard_instance_limit":HARD_INSTANCE_LIMIT,"simulation_time":_simulation_time,"placements":_placements.duplicate(true)}

func dispose() -> void:
	_disposed=true
	for node in _groups:
		if is_instance_valid(node): node.free()
	_groups.clear(); _placements.clear(); _batches.clear(); _ports.clear()
	_library=null; _sampler=Callable(); _simulation_time=0.0
