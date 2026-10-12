extends SceneTree
const Deck = preload("res://game/presentation/crew/deck_stations.gd")
const Crew = preload("res://game/presentation/crew/crew_view.gd")
var assertions := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(value: bool, reason: String) -> void:
	assertions += 1
	if not value: failures += 1; printerr("FAIL: ", reason)
func _surface(name: String, x0: float, x1: float, z0: float, z1: float, y: float) -> MeshInstance3D:
	var arrays: Array=[]; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(x0,y,z0),Vector3(x1,y,z0),Vector3(x0,y,z1),Vector3(x1,y,z1)])
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,2,1,1,2,3])
	var mesh:=ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var node:=MeshInstance3D.new(); node.name=name; node.mesh=mesh; node.set_meta("deck_support",true)
	return node
func _run() -> void:
	var model:=Node3D.new(); root.add_child(model); model.set_meta("source_family","Sloop")
	model.add_child(_surface("SourceDeckMain",-4.0,4.0,-12.0,12.0,2.0))
	model.add_child(_surface("SourceDeckRaised",-2.0,2.0,-10.0,-6.0,3.0))
	var obstacle:=MeshInstance3D.new(); obstacle.mesh=BoxMesh.new(); obstacle.position=Vector3(0.0,4.45,-8.0); obstacle.set_meta("deck_obstacle",true); model.add_child(obstacle)
	var deck:=Deck.new()
	check(deck.configure("fuchuan",model),"source semantic deck meshes supply live crew stations without an authored-name proxy")
	check(deck.faces.size()==12,"deck support uses both submitted source triangle streams")
	var main: Dictionary=deck.sample(0.0,0.0); var raised: Dictionary=deck.sample(0.0,-8.0)
	check(not main.is_empty() and absf(float(main.point.y)-2.0)<0.001,"source triangle support is not raised by legacy plank decoration")
	check(not raised.is_empty() and absf(float(raised.point.y)-3.0)<0.001,"raised source deck wins over lower hull triangles")
	check(deck.sample(5.0,0.0).is_empty(),"missing source deck triangle cannot become a fabricated flat platform")
	check(not deck.call("_clear",0.0,-8.0,24.0,8.0),"raised-deck actor checks obstacle at actual support height")
	model.add_child(_surface("SourceUnderwaterHull",-4.0,4.0,13.0,17.0,-1.0))
	var mast:=Node3D.new(); mast.name="mast_01"; model.add_child(mast)
	check(deck.configure("fuchuan",model),"merged source structural hull remains usable with its underwater faces")
	check(deck.sample(0.0,15.0).is_empty(),"underwater hull triangles are not a standing deck")
	check(not deck.call("_clear",0.0,0.0,29.0,8.0),"actual mast footprint excludes sailors at the supported deck height")
	model.free()
	var invalid:=Node3D.new(); root.add_child(invalid)
	var crew:=Crew.new(); root.add_child(crew)
	check(not crew.configure("fuchuan",invalid),"deckless source model is rejected explicitly")
	check(crew.get_impact_pool()==null and crew.get_child_count()==0,"failed crew configuration leaves no physical or animated ownership")
	crew.apply_snapshot({"id":"deckless","time":2.0,"crew":20.0,"hull":100.0},{},0.0)
	check(crew.get_visible_count()==0,"rejected crew adapter cannot submit unsupported sailors")
	check(crew.get("_disposed")==true,"failed crew setup rolls back before later snapshot or LOD calls")
	crew.dispose(); crew.free(); invalid.free()
	print("REFERENCE_SHIP_DECK_SAFETY assertions=%d failures=%d"%[assertions,failures]); quit(1 if failures else 0)
