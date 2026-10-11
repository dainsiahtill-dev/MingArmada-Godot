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
var _building_sites: Array=[]
var _tree_sites: Array=[]

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
	_build_working_harbor(port,rng)
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
	# Three asymmetrical groves with canopy, dense undergrowth and rocky shoulders.
	# Broad unoccupied spaces between them keep the island legible at ship scale.
	for patch in 3:
		var angle:=phase+patch*TAU/3.0+rng.randf_range(-0.3,0.3)
		var patch_center:=center+Vector2(cos(angle),sin(angle)*0.82)*radius*rng.randf_range(0.28,0.53)
		var breadth:=rng.randf_range(24.0,37.0)*clampf(radius/130.0,0.8,1.35)
		for index in int(48*_density):
			var scatter_angle:=rng.randf()*TAU
			var distance:=sqrt(rng.randf())*breadth
			var offset:=Vector2(cos(scatter_angle)*distance,sin(scatter_angle)*distance*0.56).rotated(angle+0.6)
			var point:=patch_center+offset
			var height:=float(_sampler.call(point.x,point.y))
			if not is_finite(height) or height<=6.0: continue
			var kind: String="shrub" if index%3==0 else "beach_grass"
			var scale:=Vector3.ONE*rng.randf_range(3.5,6.2)
			if index%6==0:
				kind="coastal_tree"; scale=Vector3.ONE*rng.randf_range(1.2,1.85)
			elif index%8==0:
				kind="outcrop"; scale=Vector3(rng.randf_range(8.0,13.0),rng.randf_range(1.8,3.8),rng.randf_range(6.7,11.2))
			_place(port,kind,"land",Vector3(point.x,height,point.y),scale,rng)
	# A compact central copse keeps small supply islands readable when settlement
	# and approach clearances remove most outer grove candidates.
	var tree_count:=0
	for placement: Dictionary in _placements:
		if placement.port_id==_identity(port) and placement.kind=="coastal_tree": tree_count+=1
	for index in 18:
		if tree_count>=8: break
		var angle:=phase+index*2.399
		var point:=center+Vector2(cos(angle),sin(angle)*0.82)*radius*(0.08+(index%3)*0.055)
		var height:=float(_sampler.call(point.x,point.y))
		if not is_finite(height) or height<=6.0: continue
		var previous:=_placements.size()
		_place(port,"coastal_tree","land",Vector3(point.x,height,point.y),Vector3.ONE*rng.randf_range(1.2,1.4),rng)
		if _placements.size()>previous: tree_count+=1

func _build_working_harbor(port: Dictionary,rng: RandomNumberGenerator) -> void:
	var accepted: Array[Vector2]=[]
	# Architecture is grouped into two yards flanking the reserved pier approach.
	# Larger ports reach farther inland; varying setbacks keep a broken frontage.
	var wanted:=6 if _density>=1.0 else 4
	for index in 24:
		if accepted.size()>=wanted: break
		var side: float=-1.0 if index%2==0 else 1.0
		var row:=floori(index/6.0)
		var local:=Vector2(side*(28.0+(index%3)*10.0+rng.randf_range(-3,3)),43.0+float(port.radius)*0.12+row*13.0+rng.randf_range(-4,4))
		var point:=_pier_world(port,local)
		var height:=float(_sampler.call(point.x,point.y))
		if not is_finite(height) or height<1.5: continue
		var kind: String=["harbor_house","lean_to","market_stall"][index%3]
		var size:=Vector3.ONE*rng.randf_range(0.9,1.12)
		var yaw:=_pier_angle(port)+PI+rng.randf_range(-0.18,0.18)
		var previous:=_placements.size()
		_place(port,kind,"land",Vector3(point.x,height,point.y),size,rng,Vector2.INF,yaw)
		if _placements.size()>previous: accepted.append(point)
	for building_index in accepted.size():
		var building: Vector2=accepted[building_index]
		# Small working-yard cargo bundles sit outside building footprints.
		for index in 6:
			var angle:=index*1.37+building_index*0.41
			var point:=building+Vector2(cos(angle),sin(angle))*rng.randf_range(6.5,10.0)
			var h:=float(_sampler.call(point.x,point.y))
			if not is_finite(h) or h<0.12: continue
			var kind: String=["crate","barrel","basket","cargo_net"][index%4]
			_place(port,kind,"land",Vector3(point.x,h,point.y),Vector3.ONE*rng.randf_range(1.0,1.5),rng)
	# Paths are many small volumetric warm stones aligned to sampled slopes.
	# No giant plane, texture projection, altered terrain, or water objects.
	for side: float in [-1.0,1.0]:
		var start_local:=Vector2(side*16.8,34.0+float(port.radius)*0.07)
		var start:=_pier_world(port,start_local)
		var end_z:=start_local.y
		for point: Vector2 in accepted:
			var local:=_pier_local(port,point)
			if local.x*side<0.0: continue
			end_z=maxf(end_z,local.y+4.0)
		var target:=_pier_world(port,Vector2(side*16.8,end_z))
		var farthest:=start.distance_to(target)
		if farthest<8.0: continue
		var direction:=(target-start).normalized()
		var cross:=Vector2(-direction.y,direction.x)
		var length:=maxf(farthest-6.5,2.0)
		# Catalog radii cannot turn a decorative path into an unbounded loop.
		var steps:=clampi(int(length/1.6)+1,1,int(72*_density))
		for step in steps:
			var t:=float(step)/steps
			var center:=start+direction*length*t+cross*sin(t*PI)*0.45
			for lane in 2:
				var point:=center+cross*((lane-0.5)*2.0+rng.randf_range(-0.35,0.35))+direction*rng.randf_range(-0.35,0.35)
				var h:=float(_sampler.call(point.x,point.y))
				if not is_finite(h) or h<1.2: continue
				_place(port,"path_gravel","land",Vector3(point.x,h,point.y),Vector3(rng.randf_range(2.0,3.1),rng.randf_range(0.09,0.18),rng.randf_range(1.7,2.5)),rng)

func _ground_basis(point: Vector3,yaw: float) -> Basis:
	var dx:=(float(_sampler.call(point.x+0.3,point.z))-float(_sampler.call(point.x-0.3,point.z)))/0.6
	var dz:=(float(_sampler.call(point.x,point.z+0.3))-float(_sampler.call(point.x,point.z-0.3)))/0.6
	if not is_finite(dx) or not is_finite(dz): return Basis()
	var normal:=Vector3(-dx,1.0,-dz).normalized()
	var forward:=Vector3(sin(yaw),0,cos(yaw))
	forward=(forward-normal*normal.dot(forward)).normalized()
	return Basis(normal.cross(forward).normalized(),normal,forward)

func _supported_building(kind: String,point: Vector3,size: Vector3,yaw: float) -> bool:
	var bounds: AABB=_library.get_mesh(kind).get_aabb()
	var basis:=Basis(Vector3.UP,yaw).scaled(size)
	var minimum:= -3.0
	var maximum:=2.15 if kind=="harbor_house" else (2.3 if kind=="lean_to" else 1.0)
	# Footing depths are authored in the plinth/posts; reject terrain which would
	# expose their bottoms or intersect above floor/counter height.
	for x: float in [bounds.position.x*0.8,(bounds.position.x+bounds.size.x)*0.8]:
		for z: float in [bounds.position.z*0.8,(bounds.position.z+bounds.size.z)*0.8]:
			var corner:=point+basis*Vector3(x,0,z)
			var delta:=float(_sampler.call(corner.x,corner.z))-point.y
			if not is_finite(delta) or delta<minimum*size.y or delta>maximum*size.y: return false
	return true

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

func _place(port: Dictionary,kind: String,zone: String,point: Vector3,size: Vector3,rng: RandomNumberGenerator,pier_local: Vector2=Vector2.INF,yaw: float=NAN) -> void:
	if _placements.size()>=_budget: return
	var bounds: AABB=_library.get_mesh(kind).get_aabb()
	var clearance:=maxf(bounds.size.x*size.x,bounds.size.z*size.z)*0.6
	if zone!="dock" and _excluded(Vector2(point.x,point.z),clearance): return
	if zone!="dock":
		for site: Dictionary in _building_sites:
			if Vector2(point.x,point.z).distance_to(site.point)<float(site.radius)+clearance+0.8: return
	if zone=="land" and point.y<0.12: return
	if zone=="reef" and (point.y< -2.6 or point.y> -0.18): return
	var variant:=rng.randi_range(0,2) if kind in ["outcrop","pebble","reef"] else 0
	var rotation:=yaw if is_finite(yaw) else (rng.randf()*TAU if zone!="dock" else _pier_angle(port)+rng.randf_range(-0.25,0.25))
	var id:=_identity(port); var key:="%s/%s/%d" % [id,kind,variant]
	# Scale local axes after slope alignment; global row scaling would flatten
	# the tilt when gravel has a 0.1m height but a 2m footprint.
	var basis:=(_ground_basis(point,rotation) if kind=="path_gravel" else Basis(Vector3.UP,rotation))*Basis.from_scale(size)
	if kind=="path_gravel":
		var vertices: PackedVector3Array=_library.get_mesh(kind).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for vertex: Vector3 in vertices:
			if absf(vertex.y)>0.001: continue
			var contact:=point+basis*vertex
			var h:=float(_sampler.call(contact.x,contact.z))
			if not is_finite(h) or absf(contact.y-h)>0.18: return
	if kind in ["harbor_house","lean_to","market_stall"]:
		if not _supported_building(kind,point,size,rotation): return
		_building_sites.append({"point":Vector2(point.x,point.z),"radius":clearance})
	if kind=="coastal_tree":
		for previous: Vector2 in _tree_sites:
			if previous.distance_to(Vector2(point.x,point.z))<5.5: return
		_tree_sites.append(Vector2(point.x,point.z))
	if not _batches.has(key): _batches[key]={"kind":kind,"variant":variant,"port":port,"transforms":[],"colors":[]}
	_batches[key].transforms.append(Transform3D(basis,point))
	_batches[key].colors.append(Color.WHITE.darkened(rng.randf_range(0.0,0.16)))
	_placements.append({"port_id":id,"kind":kind,"zone":zone,"position":point,"scale":size,"transform":Transform3D(basis,point),"pier_local":_pier_local(port,Vector2(point.x,point.z)) if zone!="dock" else pier_local})

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
	_building_sites.clear(); _tree_sites.clear()
	_library=null; _sampler=Callable(); _simulation_time=0.0
