extends SceneTree
## Regression for the actual production-selected shadow geometry in its lab.
var assertions:=0
var failures:=0
func check(ok:bool,message:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL shadow proxy research: ",message)
func _initialize()->void:run.call_deferred()
func run()->void:
	var demo:Node3D=load("res://game/research/demos/shadow_edges_experiment.gd").new()
	demo.configure({"paused":true})
	var viewport:=SubViewport.new();viewport.own_world_3d=true;viewport.size=Vector2i(960,640);root.add_child(viewport);viewport.add_child(demo)
	check(demo.inspection_snapshot().ready,"actual shadow experiment ready")
	var ship:Node3D=demo.get("_ship");var adapter:RefCounted=demo.get("_adapter")
	var prepared:Dictionary=demo.get("_prepared");var proxies:=0
	for mesh:MeshInstance3D in ship.get_model().find_children("*","MeshInstance3D",true,false):
		if not mesh.has_meta("target_shadow_geometry") or not mesh.is_visible_in_tree():continue
		var id:="ship:"+str(mesh.name)
		if not prepared.has(id):continue
		proxies+=1
		var selected:Mesh=mesh.get_meta("target_shadow_geometry")
		var effective:Dictionary=adapter._mesh_geometry(selected)
		check(prepared[id].source_positions()==effective.positions,"prepared lab input equals production-selected shadow geometry: "+str(mesh.name))
	check(proxies==5,"all five real hero shadow proxies exercised")
	demo.dispose();viewport.free()
	print("SHADOW_PROXY_RESEARCH_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
