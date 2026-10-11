extends SceneTree
const World = preload("res://modules/scene_engine/world/world_view.gd")
var failures := 0
var assertions := 0
func _initialize() -> void: _run.call_deferred()
func check(value: bool, reason: String) -> void:
	assertions += 1
	if not value: failures += 1; printerr("FAIL: ",reason)
func _height(x: float,z: float) -> float:
	return 35.0 * maxf(0.0,1.0-minf(Vector2(x-710.0,z).length_squared(),Vector2(x-2000.0,z).length_squared())/10000.0)-3.0
func _run() -> void:
	var view := World.new(); root.add_child(view)
	var camera := Camera3D.new(); root.add_child(camera)
	camera.position = Vector3(0,60,30); camera.look_at(Vector3(710,0,0))
	var ports := [{"id":"far","x":620.0,"z":0.0,"islandX":710.0,"islandZ":0.0,"radius":100.0},{"id":"beyond1500","x":1910.0,"z":0.0,"islandX":2000.0,"islandZ":0.0,"radius":100.0}]
	check(view.configure(_height,[],{"camera":camera,"ports":ports,"chunk_radius":0,"resolution":8,"vegetation":false,"collision":false,"island_details":false}),"distant support scene configures")
	check(view.has_method("get_distant_chunks"),"islands beyond close terrain retain bounded low-detail terrain support")
	if view.has_method("get_distant_chunks"):
		var distant: Array = view.get_distant_chunks()
		check(not distant.is_empty() and distant.size() <= 128,"far terrain has an explicit budget")
		var has_land := false
		for chunk in distant:
			var mesh: ArrayMesh = chunk.mesh
			for p: Vector3 in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				if p.y > 20.0: has_land = true
			check(chunk.find_children("*","CollisionShape3D",true,false).is_empty(),"far terrain cannot add distant physical collisions")
		check(has_land,"visible far buildings have actual non-flat island terrain")
		var beyond := false
		for chunk in distant:
			if chunk.name == "DistantTerrain_8_0": beyond = true
		check(beyond,"islands beyond1500 still have terrain when inside the4000 camera range")
		view.apply_snapshot({"time":1.0,"focus":{"x":710.0,"z":0.0}})
		for chunk in view.get_distant_chunks():
			check(chunk.name != "DistantTerrain_2_0","near and far terrain never overlap the same chunk")
		var refs: Array = []
		for chunk in view.get_distant_chunks(): refs.append(weakref(chunk))
		view.dispose()
		check(view.get_distant_chunks().is_empty(),"dispose clears far terrain ownership")
		for item in refs: check(item.get_ref() == null,"distant GPU geometry released on scene exit")
	var crowded: Array = []
	for index in 6:
		crowded.append({"id":"budget%d" % index,"x":index*3000.0,"z":0.0,"islandX":index*3000.0,"islandZ":0.0,"radius":1000.0})
	check(view.configure(func(_x,_z):return 10.0,[],{"camera":camera,"ports":crowded,"chunk_radius":0,"resolution":4,"vegetation":false,"collision":false,"island_details":false}),"oversubscribed distant support configures")
	check(view.get_distant_chunks().size() <= 128,"many large islands cannot exceed distant tile budget")
	var last_dock := view.find_child("budget5",true,false) as Node3D
	check(last_dock != null and not last_dock.visible,"unsupported port visuals hide when distant tile budget is exhausted")
	view.dispose(); view.free(); camera.free()
	print("DISTANT_ISLAND_SUPPORT_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
