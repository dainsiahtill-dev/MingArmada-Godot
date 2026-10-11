extends SceneTree
const Details=preload("res://modules/scene_engine/world/island_details.gd")
const Height=preload("res://modules/scene_engine/terrain/height_field.gd")
const Library=preload("res://modules/scene_engine/assets/coastal_detail_library.gd")
var assertions:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, reason: String) -> void:
	assertions+=1
	if not ok: failures+=1; printerr("FAIL: ",reason)
func run() -> void:
	var ports: Array=JSON.parse_string(FileAccess.get_file_as_string("res://game/data/mingqi_geography.json"))
	var field:=Height.new()
	check(field.configure_ports(ports,true,{"reference_islands":true}),"real irregular three-island geography is used by the art acceptance")
	var details:=Details.new(); root.add_child(details)
	# This isolated layer has no separately rendered legacy houses. Its caller
	# supplies the actual empty footprint list, rather than a fabricated circle.
	check(details.configure(field.sample_height,ports,{"seed":13,"max_instances":2200,"existing_buildings":[]}),"coastal composition consumes the actual new height authority and real caller-owned buildings")
	var audit: Dictionary=details.diagnostics()
	var library:=Library.new()
	var counts: Dictionary={}
	for placement: Dictionary in audit.placements:
		if not counts.has(placement.port_id): counts[placement.port_id]={}
		var tally: Dictionary=counts[placement.port_id]
		tally[placement.kind]=int(tally.get(placement.kind,0))+1
		if placement.zone=="land":
			check(absf(placement.position.y-field.sample_height(placement.position.x,placement.position.z))<.001,"actual dry-ground anchors follow reference slopes and bays")
		if placement.zone!="dock":
			check(not (absf(placement.pier_local.x)<13.0 and placement.pier_local.y> -110.0 and placement.pier_local.y<65.0),"irregular-profile details still leave the original landing and approach lane open")
		if placement.kind in ["coastal_tree","shore_tree"]:
			var p: Vector3=placement.position
			var gradient:=Vector2((field.sample_height(p.x+2,p.z)-field.sample_height(p.x-2,p.z))/4,(field.sample_height(p.x,p.z+2)-field.sample_height(p.x,p.z-2))/4)
			check(gradient.length()<=(.75001 if placement.kind=="coastal_tree" else .45001),"each rendered tree stands on a genuinely low slope instead of a naked reference peak")
		if placement.kind in ["harbor_house","lean_to","market_stall","beached_boat","drying_rack"]:
			var mesh: ArrayMesh=library.get_mesh(placement.kind)
			var bottom: float=mesh.get_aabb().position.y
			var grounded:=true
			for vertex: Vector3 in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				if absf(vertex.y-bottom)>.001: continue
				var world: Vector3=placement.transform*vertex
				if world.y>field.sample_height(world.x,world.z)+(.12 if placement.kind in ["beached_boat","drying_rack"] else .05): grounded=false
			check(grounded,"actual architecture and fishing silhouettes retain supported footings across their true mesh footprint")
		if placement.kind=="path_gravel":
			var contact:=true
			for vertex: Vector3 in library.get_mesh("path_gravel").surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				if absf(vertex.y)>.001: continue
				var world: Vector3=placement.transform*vertex
				if absf(world.y-field.sample_height(world.x,world.z))>.18: contact=false
			check(contact,"curved path and working-yard stones remain fitted to the actual local source slope")
	print("REFERENCE_ISLAND_ART_COUNTS ",counts)
	print("REFERENCE_ISLAND_ART_RESOURCES instances=",audit.instance_count," meshes=",audit.mesh_count," vertices=",audit.mesh_vertices)
	for port: Dictionary in ports:
		var tally: Dictionary=counts.get(port.id,{})
		var architecture: int=int(tally.get("harbor_house",0))+int(tally.get("lean_to",0))+int(tally.get("market_stall",0))
		check(architecture>=3,"actual narrow landing discovers supported working-harbor buildings: "+str(port.id))
		check(int(tally.get("beached_boat",0))+int(tally.get("drying_rack",0))>=2,"reference harbor contains grounded fishing life silhouettes: "+str(port.id))
		check(int(tally.get("coastal_tree",0))+int(tally.get("shore_tree",0))>=5,"reference dry slopes contain readable inland/low coastal canopy rather than center-in-water placements: "+str(port.id))
		check(int(tally.get("path_gravel",0))>=12,"ground dressing follows supported actual harbor destinations: "+str(port.id))
	check(audit.instance_count<=2200 and audit.mesh_count<=24,"art keeps its declared instance and reusable mesh ownership caps")
	details.free(); _check_actual_building_mask(); await process_frame
	print("REFERENCE_ISLAND_ART_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)

func _check_actual_building_mask() -> void:
	var details:=Details.new();root.add_child(details)
	var port:={"id":"mask","x":90.0,"z":0.0,"islandX":0.0,"islandZ":0.0,"radius":100.0}
	var flat:=func(_x,_z):return 10.0
	var legacy:=Vector2(cos(2.15)*42.0,sin(2.15)*32.0)
	check(details.configure(flat,[port],{"max_instances":0}),"legacy callers still receive the original settlement exclusion")
	check(details._excluded(legacy,0),"the old house ring remains protected for callers without real footprints")
	check(details.configure(flat,[port],{"max_instances":0,"existing_buildings":[]}),"a caller can report that no legacy house was built")
	check(not details._excluded(legacy,0),"missing actual house no longer reserves a phantom plot")
	var real:=Vector2(-45,20)
	check(details.configure(flat,[port],{"max_instances":0,"existing_buildings":[{"position":real,"radius":7.0}]}),"actual native building footprints are accepted")
	check(details._excluded(real+Vector2(6,0),0) and not details._excluded(real+Vector2(15,0),0),"only the genuine footprint and requested clearance are excluded")
	check(not details.configure(flat,[port],{"max_instances":0,"existing_buildings":[{"position":real,"radius":NAN}]}),"invalid geometry masks cannot silently pollute placement")
	details.free()
