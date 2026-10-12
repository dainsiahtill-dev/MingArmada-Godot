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
var _life_sites: Array[Vector2]=[]
var _actual_buildings: Array[Dictionary]=[]
var _has_actual_buildings:=false
var _terrain_support: Callable
var _native_forest := false

func configure(height_sampler: Callable,ports: Array,options: Dictionary={}) -> bool:
	dispose()
	if not height_sampler.is_valid(): return false
	if options.has("native_forest") and not options.native_forest is bool: return false
	if ports.size()>64: return false
	for port in ports:
		if not port is Dictionary: return false
		for key in ["x","z","islandX","islandZ","radius"]:
			if not port.has(key) or not is_finite(float(port[key])): return false
		if float(port.radius)<=0.0: return false
	if options.has("existing_buildings"):
		if not options.existing_buildings is Array or options.existing_buildings.size()>4096: return false
		for site: Variant in options.existing_buildings:
			if not site is Dictionary or not (site.get("radius") is float or site.get("radius") is int): return false
			var radius:=float(site.radius)
			var input: Variant=site.get("position",site.get("point",Vector2.INF))
			var point: Vector2=Vector2.INF
			if input is Vector2: point=input
			elif input is Dictionary:
				if not (input.get("x") is float or input.get("x") is int) or not (input.get("z") is float or input.get("z") is int): return false
				point=Vector2(float(input.x),float(input.z))
			if not point.is_finite() or not is_finite(radius) or radius<0.0: return false
			_actual_buildings.append({"position":point,"radius":radius})
		_has_actual_buildings=true
	_sampler=height_sampler; _ports=ports.duplicate(true)
	_native_forest=bool(options.get("native_forest",false))
	_terrain_support=options.get("terrain_support",Callable())
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
	if _placements.size()>=_budget: return
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
	if _placements.size()>=_budget: return
	var survey:=_survey_dry_land(port,rng)
	var groves: Array[Vector2]=[]
	# Choose observed shoulders, never an assumed dry geometric island center.
	survey.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return a.score>b.score)
	for site: Dictionary in survey:
		if groves.size()>=5: break
		if site.height<3.0 or site.grade>.8: continue
		var point: Vector2=site.point
		var separated:=true
		for previous: Vector2 in groves:
			if previous.distance_to(point)<clampf(float(port.radius)*.18,12.0,32.0): separated=false
		if not separated or _excluded(point,5.0): continue
		groves.append(point)
		var breadth:=clampf(float(port.radius)*.15,10.0,24.0)
		for index in int(42*_density):
			var angle:=phase+index*2.399+rng.randf_range(-.3,.3)
			var offset:=Vector2(cos(angle),sin(angle)*.65)*sqrt(rng.randf())*breadth
			var sample:=point+offset.rotated(phase)
			var h:=float(_sampler.call(sample.x,sample.y))
			if not is_finite(h) or h<1.2: continue
			var gradient:=_terrain_gradient(sample)
			if not gradient.is_finite() or gradient.length()>1.0: continue
			var kind: String="shrub" if index%3==0 else "beach_grass"
			var size:=Vector3.ONE*rng.randf_range(3.5,5.7)
			if index%4==0 and h>6.0 and gradient.length()<=.75:
				kind="coastal_tree"; size=Vector3(rng.randf_range(1.15,1.4),rng.randf_range(1.25,1.55),rng.randf_range(1.1,1.4))
			elif index%4==0 and gradient.length()<=.45:
				kind="shore_tree"; size=Vector3.ONE*rng.randf_range(.95,1.35)
			_place(port,kind,"land",Vector3(sample.x,h,sample.y),size,rng)
	# Jagged mineral shoulders get elongated, slope-aligned clusters. They do not
	# turn into artificial rows of trees on an exposed peak or a steep wall.
	var rocky:=0
	for site: Dictionary in survey:
		if rocky>=14 or _placements.size()>=_budget: break
		if site.height<4.0 or site.grade<.40 or site.grade>3.0: continue
		var point: Vector2=site.point
		for fragment in 3:
			var gradient: Vector2=site.gradient
			var tangent:=Vector2(-gradient.y,gradient.x).normalized()
			var p:=point+tangent*(fragment-1)*rng.randf_range(3,6)+gradient.normalized()*rng.randf_range(-1.5,1.5)
			var h:=float(_sampler.call(p.x,p.y))
			if not is_finite(h) or h<.12: continue
			var yaw:=atan2(tangent.x,tangent.y)+rng.randf_range(-.28,.28)
			_place(port,"outcrop","land",Vector3(p.x,h,p.y),Vector3(rng.randf_range(4,8),rng.randf_range(1.6,3.2),rng.randf_range(2.2,4.5)),rng,Vector2.INF,yaw)
		rocky+=1
	# A dry-site pass supplies missing isolated canopy where a thin shoulder
	# cannot support a broad grove. Every individual tree is slope checked.
	var inland_trees:=0
	for placement: Dictionary in _placements:
		if placement.port_id==_identity(port) and placement.kind=="coastal_tree": inland_trees+=1
	for site: Dictionary in survey:
		if inland_trees>=16 or _placements.size()>=_budget: break
		if site.grade>.75 or site.height<=6.0: continue
		var before:=_placements.size()
		_place(port,"coastal_tree","land",Vector3(site.point.x,site.height,site.point.y),Vector3.ONE*rng.randf_range(1.2,1.4),rng)
		if _placements.size()>before: inland_trees+=1
	var low_trees:=0
	for site: Dictionary in survey:
		if low_trees>=14 or _placements.size()>=_budget: break
		if site.height<1.5 or site.grade>.45: continue
		var before:=_placements.size()
		_place(port,"shore_tree","land",Vector3(site.point.x,site.height,site.point.y),Vector3.ONE*rng.randf_range(.95,1.25),rng)
		if _placements.size()>before: low_trees+=1

func _survey_dry_land(port: Dictionary,rng: RandomNumberGenerator) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	var center:=Vector2(float(port.islandX),float(port.islandZ))
	var radius:=float(port.radius)
	for row in 21:
		for column in 21:
			var point:=center+Vector2((column/20.0*2-1)*radius,(row/20.0*2-1)*radius)
			point+=Vector2(rng.randf_range(-.15,.15),rng.randf_range(-.15,.15))*radius/10.0
			var h:=float(_sampler.call(point.x,point.y))
			if not is_finite(h) or h<1.2: continue
			var gradient:=_terrain_gradient(point)
			if not gradient.is_finite(): continue
			var grade:=gradient.length()
			result.append({"point":point,"height":h,"gradient":gradient,"grade":grade,"score":h*.12-grade*4+rng.randf_range(0,4)})
	# Thin source ridges can fit between coarse lattice knots. Refine observed
	# dry neighborhoods instead of assuming their geometric center is habitable.
	result.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return a.score>b.score)
	var initial:=result.slice(0,mini(40,result.size()))
	for site: Dictionary in initial:
		for row in [-1,0,1]:
			for column in [-1,0,1]:
				if row==0 and column==0: continue
				var point: Vector2=site.point+Vector2(column,row)*radius/40.0
				var h:=float(_sampler.call(point.x,point.y))
				if not is_finite(h) or h<1.2: continue
				var gradient:=_terrain_gradient(point)
				if not gradient.is_finite(): continue
				var grade:=gradient.length()
				result.append({"point":point,"height":h,"gradient":gradient,"grade":grade,"score":h*.12-grade*4+rng.randf_range(0,4)})
	return result

func _terrain_gradient(point: Vector2) -> Vector2:
	return Vector2((float(_sampler.call(point.x+2,point.y))-float(_sampler.call(point.x-2,point.y)))/4.0,(float(_sampler.call(point.x,point.y+2))-float(_sampler.call(point.x,point.y-2)))/4.0)

func _build_working_harbor(port: Dictionary,rng: RandomNumberGenerator) -> void:
	var accepted: Array[Vector2]=[]
	_build_landing_life(port,rng)
	# First inspect the real, narrow landing, then the surrounding natural dry
	# land. Old x=28/38, y=65+ rows missed the reference world's habitable apron.
	var wanted:=6 if _density>=1.0 else 4
	for index in 144:
		if accepted.size()>=wanted: break
		if _placements.size()>=_budget: return
		var side: float=-1.0 if index%2==0 else 1.0
		var row:=floori(index/8.0)
		var across: float=[18.0,25.0,36.0,50.0][floori(index/2.0)%4]
		var local:=Vector2(side*(across+rng.randf_range(-.25,.25)),53.0+row*11.0+rng.randf_range(-.5,.5))
		var point:=_pier_world(port,local)
		var height:=float(_sampler.call(point.x,point.y))
		if not is_finite(height) or height<1.5: continue
		for attempt in 3:
			var kind: String=["market_stall","lean_to","harbor_house"][(accepted.size()+attempt)%3]
			var size:=Vector3.ONE*(rng.randf_range(.66,.80) if kind=="market_stall" else rng.randf_range(.82,.94))
			var yaw:=_pier_angle(port)+PI+rng.randf_range(-.08,.08)
			var previous:=_placements.size()
			_place(port,kind,"land",Vector3(point.x,height,point.y),size,rng,Vector2.INF,yaw)
			if _placements.size()>previous:
				accepted.append(point); break
	# A coarse natural-land scan can miss the last usable narrow apron pocket.
	# Probe compact counters individually; never flatten terrain to fit a house.
	for index in 96:
		if accepted.size()>=3 or _placements.size()>=_budget: break
		var side: float=-1 if index%2==0 else 1
		var local:=Vector2(side*(16.4+(floori(index/2.0)%4)*2.8),44.0+floori(index/8.0)*3.0)
		var point:=_pier_world(port,local)
		var h:=float(_sampler.call(point.x,point.y))
		if not is_finite(h) or h<1.5: continue
		var before:=_placements.size()
		_place(port,"market_stall","land",Vector3(point.x,h,point.y),Vector3.ONE*rng.randf_range(.58,.66),rng,Vector2.INF,_pier_angle(port)+PI)
		if _placements.size()>before: accepted.append(point)
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
	# Short, curved connections exist only where a supported destination exists.
	# No empty paired straight roads running toward an invented settlement.
	for building_index in accepted.size():
		var target: Vector2=accepted[building_index]
		var local:=_pier_local(port,target)
		var start:=_pier_world(port,Vector2(signf(local.x)*17.0,43.0))
		var delta:=target-start
		if delta.length()<.01: continue
		var direction:=delta.normalized(); var cross:=Vector2(-direction.y,direction.x)
		var length:=maxf(delta.length()-6.6,0.0)
		var steps:=clampi(int(length/1.6)+1,1,int(48*_density))
		for step in steps:
			var t:=float(step)/maxi(steps-1,1)
			var center:=start+direction*length*t+cross*sin(t*PI)*(1.1+.3*(building_index%3))
			for lane in 2:
				var point:=center+cross*((lane-.5)*1.1+rng.randf_range(-.25,.25))
				_gravel_at(port,point,rng)
	# Small irregular working-yard aprons surround the real disembarkation area.
	for side: float in [-1.0,1.0]:
		if not accepted.any(func(p: Vector2):return _pier_local(port,p).x*side>0): continue
		for index in 24:
			var angle:=index*2.399
			var local:=Vector2(side*(17.3+cos(angle)*3.3),46.0+sin(angle)*3.2)
			_gravel_at(port,_pier_world(port,local),rng)

func _gravel_at(port: Dictionary,point: Vector2,rng: RandomNumberGenerator) -> void:
	var h:=float(_sampler.call(point.x,point.y))
	if not is_finite(h) or h<1.2: return
	_place(port,"path_gravel","land",Vector3(point.x,h,point.y),Vector3(rng.randf_range(1.05,1.65),rng.randf_range(.07,.14),rng.randf_range(1.0,1.55)),rng)

func _build_landing_life(port: Dictionary,rng: RandomNumberGenerator) -> void:
	var placed:=0
	for index in 48:
		if placed>=2 or _placements.size()>=_budget: return
		var side: float=-1 if index%2==0 else 1
		var local:=Vector2(side*(17.0+(floori(index/2.0)%3)*6.0),43.0+floori(index/6.0)*7.0)
		var point:=_pier_world(port,local)
		var h:=float(_sampler.call(point.x,point.y))
		if not is_finite(h) or h<1.5: continue
		var kind: String="beached_boat" if placed%2==0 else "drying_rack"
		var previous:=_placements.size()
		_place(port,kind,"land",Vector3(point.x,h,point.y),Vector3.ONE*rng.randf_range(.75,1.0),rng,Vector2.INF,_pier_angle(port)+rng.randf_range(-.28,.28))
		if _placements.size()>previous: placed+=1

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
	var lowest:=bounds.position.y
	for vertex: Vector3 in _library.get_mesh(kind).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if absf(vertex.y-lowest)>.001: continue
		var foot:=point+basis*vertex
		var ground:=float(_sampler.call(foot.x,foot.z))
		if not is_finite(ground) or foot.y>ground+.05: return false
	return true

func _supported_life_prop(kind: String,point: Vector3,basis: Basis) -> bool:
	var mesh: ArrayMesh=_library.get_mesh(kind)
	var bounds:=mesh.get_aabb()
	for x: float in [bounds.position.x,bounds.position.x+bounds.size.x]:
		for z: float in [bounds.position.z,bounds.position.z+bounds.size.z]:
			var p:=point+basis*Vector3(x,0,z)
			var h:=float(_sampler.call(p.x,p.z))
			if not is_finite(h) or h<.12: return false
	for vertex: Vector3 in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if absf(vertex.y-bounds.position.y)>.001: continue
		var foot:=point+basis*vertex
		var h:=float(_sampler.call(foot.x,foot.z))
		if not is_finite(h) or foot.y>h+.12: return false
	return true

func _contour(port: Dictionary,angle: float,target: float) -> Vector3:
	var center:=Vector2(float(port.islandX),float(port.islandZ))
	var direction:=Vector2(cos(angle),sin(angle)*0.82)
	var radius:=float(port.radius)
	var outer:=1.15; var inner:=0.0
	var lo:=center+direction*radius*outer
	var low_h:=float(_sampler.call(lo.x,lo.y))
	if not is_finite(low_h) or low_h>target: return Vector3(INF,INF,INF)
	# Reference coastlines contain bays, detached islets and submerged centers.
	# Find the first water-to-land shoulder from offshore, then refine only that
	# bracket. A radius-to-center bisection assumes one round mound and misses it.
	var found:=false
	for step in 64:
		inner=1.15*(1.0-float(step+1)/64.0)
		var candidate:=center+direction*radius*inner
		var height:=float(_sampler.call(candidate.x,candidate.y))
		if not is_finite(height): return Vector3(INF,INF,INF)
		if height>=target:
			found=true; break
		outer=inner
	if not found: return Vector3(INF,INF,INF)
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
		# Legacy callers keep their original inner ring. Formal reference worlds
		# can report only the houses whose actual footings passed terrain checks.
		if not _has_actual_buildings:
			for index in 9:
				var house:=Vector2(float(port.islandX)+cos(index*2.15)*float(port.radius)*0.42,float(port.islandZ)+sin(index*2.15)*float(port.radius)*0.32)
				if point.distance_to(house)<9.0+clearance: return true
	for site: Dictionary in _actual_buildings:
		if point.distance_to(site.position)<float(site.radius)+clearance: return true
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
	var basis:=(_ground_basis(point,rotation) if kind in ["path_gravel","outcrop","beached_boat"] else Basis(Vector3.UP,rotation))*Basis.from_scale(size)
	if kind=="path_gravel":
		var vertices: PackedVector3Array=_library.get_mesh(kind).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for vertex: Vector3 in vertices:
			if absf(vertex.y)>0.001: continue
			var contact:=point+basis*vertex
			var h:=float(_sampler.call(contact.x,contact.z))
			if not is_finite(h) or absf(contact.y-h)>0.18: return
	if kind in ["harbor_house","lean_to","market_stall"]:
		for previous: Vector2 in _life_sites:
			if previous.distance_to(Vector2(point.x,point.z))<clearance+3.0: return
		if not _supported_building(kind,point,size,rotation): return
		_building_sites.append({"point":Vector2(point.x,point.z),"radius":clearance})
	if kind in ["coastal_tree","shore_tree"]:
		if _native_forest: return
		var gradient:=_terrain_gradient(Vector2(point.x,point.z))
		var maximum:=.75 if kind=="coastal_tree" else .45
		if not gradient.is_finite() or gradient.length()>maximum: return
		if point.y<(6.0 if kind=="coastal_tree" else 1.5): return
		for previous: Vector2 in _tree_sites:
			if previous.distance_to(Vector2(point.x,point.z))<5.5: return
		_tree_sites.append(Vector2(point.x,point.z))
	if kind in ["beached_boat","drying_rack"]:
		if not _supported_life_prop(kind,point,basis): return
		for previous: Vector2 in _life_sites:
			if previous.distance_to(Vector2(point.x,point.z))<5.0: return
		_life_sites.append(Vector2(point.x,point.z))
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
		var radius:=float(group.get_meta("island_radius"))
		group.visible=focus.distance_to(center)<=_focus_distance+radius and (not _terrain_support.is_valid() or bool(_terrain_support.call(center,radius)))
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
	_terrain_support=Callable()
	for node in _groups:
		if is_instance_valid(node): node.free()
	_groups.clear(); _placements.clear(); _batches.clear(); _ports.clear()
	_building_sites.clear(); _tree_sites.clear(); _life_sites.clear()
	_actual_buildings.clear(); _has_actual_buildings=false
	_library=null; _sampler=Callable(); _simulation_time=0.0
