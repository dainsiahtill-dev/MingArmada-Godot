extends SceneTree
## Catches formal-game fallback to reference heightmaps, harbor cuts, moving
## terrain windows, or a shoal that exists only in the ocean's color mask.
const Height = preload("res://modules/scene_engine/terrain/height_field.gd")
const Natural = preload("res://modules/scene_engine/terrain/natural_island_field.gd")
const Geography = preload("res://game/scenes/common/reference_geography.gd")
const World = preload("res://modules/scene_engine/world/world_view.gd")
const Mingqi = preload("res://game/scenes/mingqi/mingqi_scene.gd")
const AudioCleanup = preload("res://tests/fixtures/audio_cleanup.gd")
var assertions := 0
var failures := 0
func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ",detail)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var ports: Array = JSON.parse_string(FileAccess.get_file_as_string("res://game/data/mingqi_geography.json"))
	var height := Height.new()
	check(height.configure_ports(ports,true,Geography.options()),"formal game geography configures")
	check(height.has_method("natural_islands"),"formal height owner exposes immutable natural grids")
	if not height.has_method("natural_islands"): _finish(); return
	var islands: Array = height.natural_islands()
	check(islands.size()==3 and height.reference_profiles().is_empty(),"formal game owns three natural islands without source-heightmap substitution")
	if islands.size()!=3: _finish(); return
	for index in 3:
		var port: Dictionary = ports[index]
		var scale_value: float = [0.8,0.65,0.6][index]
		var field: RefCounted = islands[index].field
		var independent := Natural.new()
		check(independent.configure({"seed":1661+index,"center":Vector2(port.islandX,port.islandZ),"radius":port.radius*scale_value,"peak":float(port.peak),"resolution":257}),"independent accepted natural field configures")
		check(field.get_grid()==independent.get_grid(),"formal island is unchanged accepted natural v1 geometry; no harbor channels or apron")
		check(field.get_diagnostics().harbor_features==0,"formal natural island has no artificial harbor geometry")
		for direction in [Vector2(0.27,0.13),Vector2(-0.42,0.22),Vector2(0.83,-0.41)]:
			var p: Vector2 = Vector2(port.islandX,port.islandZ)+direction*port.radius*scale_value
			check(absf(height.sample_height(p.x,p.y)-field.sample_triangle_height(p.x,p.y))<0.000001,"native ship/navigation heights use actual rendered triangle surface")
		for x in [-21.0,0.0,21.0]:
			for z in [-21.0,0.0,21.0]:
				check(height.sample_height(port.x+x,port.z+z)<-3.0,"unchanged business port anchor has wet full-hull clearance")
	var before := height.sample_height(-480,-60)
	check(not height.configure_ports(ports,true,{"natural_islands":"yes"}) and height.sample_height(-480,-60)==before,"invalid natural mode preserves accepted terrain atomically")
	var world := World.new(); root.add_child(world)
	check(world.configure(height.sample_height,[],{"ports":ports,"vegetation":false,"island_details":false,"collision":false,"static_shore_resolution":256}),"formal world composes real natural meshes")
	var meshes: Array = world.get_static_island_meshes()
	check(meshes.size()==4 and world.get_chunk_count()==0 and world.get_distant_chunks().is_empty(),"three finite natural surfaces and one real shoal replace moving camera terrain")
	for mesh: MeshInstance3D in meshes:
		var arrays: Array=mesh.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		var side := int(sqrt(vertices.size()))
		var field: RefCounted=height.natural_terrain_grids().filter(func(entry): return entry.id==mesh.get_meta("natural_island_id"))[0].field
		# These weights read real submitted geometry, independently of both
		# numeric and presentation sampling implementations.
		for row_fraction in [0.31,0.50,0.69]:
			var t := (int(side*row_fraction)*(side-1)+int(side*0.45))*6
			var a: Vector3=vertices[indices[t]]; var b: Vector3=vertices[indices[t+1]]; var c: Vector3=vertices[indices[t+2]]
			var point := a*0.2+b*0.3+c*0.5
			check(absf(field.sample_triangle_height(point.x,point.z)-point.y)<0.00002,"numeric field agrees with independently weighted submitted mesh triangle")
	check(world.has_method("sample_rendered_terrain_height"),"formal world exposes actual rendered terrain sampler")
	var port_root: Node3D=world.get_node("Ports")
	for port: Dictionary in ports:
		var visual: Node3D=port_root.get_node(NodePath(port.id))
		check(visual.position==Vector3(port.x,0,port.z),"port visual keeps canonical business anchor")
		check(visual.has_meta("real_shore_landing"),"natural port adapts pier to actual shore without moving terrain")
		if visual.has_meta("real_shore_landing"):
			var landing: Vector2=visual.get_meta("real_shore_landing")
			check(height.sample_height(landing.x,landing.y)>=1.2 and height.sample_height(landing.x,landing.y)<2.5,"pier reaches real low beach landing")
	var houses := 0
	for house: Node3D in port_root.get_children():
		if ports.any(func(port): return str(port.id)==str(house.name)): continue
		if house.get_child_count()==0: continue
		houses+=1
		var foundation: MeshInstance3D=house.get_child(0)
		var box: BoxMesh=foundation.mesh
		for x in [-box.size.x*0.5,box.size.x*0.5]:
			for z in [-box.size.z*0.5,box.size.z*0.5]:
				var point: Vector3=house.transform*Vector3(x,0,z)
				var ground: float=height.sample_height(point.x,point.z)
				check(ground>0.5 and foundation.position.y-box.size.y*0.5+house.position.y<=ground,"every real house footing reaches dry accepted ground")
	check(houses>0,"formal natural town retains real supported houses")
	if world.has_method("sample_rendered_terrain_height"):
		for p in [Vector2(-480,-60),Vector2(420,160),Vector2(-60,390),Vector2(-12.05358347586106,34.60177510837365)]:
			check(absf(world.sample_rendered_terrain_height(p.x,p.y)-height.sample_height(p.x,p.y))<0.00001,"rendered land and supply shoal exactly match native depth authority")
		var midpoint := Vector2(ports[0].x,ports[0].z).lerp(Vector2(ports[1].x,ports[1].z),0.5)
		check(height.sample_height(midpoint.x,midpoint.y)>-3.0 and world.sample_rendered_terrain_height(midpoint.x,midpoint.y)>-3.0,"navigation shoal has matching visible physical seabed")
	var ids := meshes.map(func(node): return node.get_instance_id())
	world.apply_snapshot({"time":12.0,"focus":Vector2(9000,-4000)})
	check(world.get_static_island_meshes().map(func(node): return node.get_instance_id())==ids and world.get_chunk_build_count()==0,"moving camera cannot regenerate natural grids or mesh nodes")
	var surf: Array=world.fidelity_diagnostics().geometry.get("shoreSurf",[])
	check(surf.size()==3,"formal world owns advancing shoreline loop for each real natural island")
	for loop: Dictionary in surf:
		check(loop.time==12.0 and loop.surfaceWaveCount==5,"shoreline receives shared runtime clock and unchanged five sea waves")
	world.apply_snapshot({"time":18.0,"focus":Vector2(9000,-4000)})
	var advanced: Array=world.fidelity_diagnostics().geometry.get("shoreSurf",[])
	for index in mini(surf.size(),advanced.size()):
		check(advanced[index].time==18.0 and advanced[index].states!=surf[index].states and advanced[index].geometryBuilds==surf[index].geometryBuilds,"shoreline advances authored controllers without rebuilding coast")
	world.dispose(); world.dispose()
	check(world.get_static_island_meshes().is_empty() and world.get_children().is_empty(),"natural terrain disposal releases all scene owners")
	world.free()
	var scene := Mingqi.new(); root.add_child(scene); await process_frame; scene.set_physics_process(false)
	check(scene.startup_receipt.get("ok",false),"actual formal Mingqi scene bootstraps accepted natural terrain")
	if scene.startup_receipt.get("ok",false):
		check(scene.heights.natural_islands().size()==3 and scene.world.fidelity_diagnostics().geometryMode=="static_natural","current formal game uses integrated natural world")
		check(scene.runtime.snapshot().campaign.ports.size()==3,"canonical game port catalog remains three ports")
		for ship: Dictionary in scene.runtime.snapshot().naval.ships:
			check(ship.hull>0,"formal opening fleet retains live native vessels")
			var dims: Dictionary=ship.dimensions
			var pose: Dictionary=ship.visual
			for forward in [-0.5,0.0,0.5]:
				for side_value in [-0.5,0.0,0.5]:
					var x: float=pose.position.x+cos(pose.heading)*dims.length*forward-sin(pose.heading)*dims.width*side_value
					var z: float=pose.position.z+sin(pose.heading)*dims.length*forward+cos(pose.heading)*dims.width*side_value
					check(scene.heights.sample_height(x,z)<-dims.draft-0.3,"actual opening ship dimensions and effective draft have full-hull clearance")
	var playbacks: Array[WeakRef]=AudioCleanup.stop_players(scene)
	scene.free(); await process_frame; await process_frame
	check(await AudioCleanup.wait_for_release(self,playbacks),"formal scene shutdown releases actual stopped audio playbacks before exit")
	_finish()
func _finish() -> void:
	print("NATURAL_GAME_WORLD_TESTS assertions=",assertions," failures=",failures)
	quit(0 if failures==0 else 1)
