extends SceneTree
const Library=preload("res://modules/scene_engine/assets/vegetation_library.gd")
var assertions:=0
var failures:=0
func check(value: bool,detail: String) -> void:
	assertions+=1
	if not value: failures+=1; printerr("FAIL: ",detail)
func flat_height(_x: float,_z: float) -> float: return 12.0
func steep_height(x: float,_z: float) -> float: return 45.0+x*0.9
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var library:=Library.new()
	var flat:=Node3D.new(); var steep:=Node3D.new(); root.add_child(flat); root.add_child(steep)
	library.populate(flat,flat_height,Vector2i.ZERO,100.0,24,[])
	library.populate(steep,steep_height,Vector2i.ZERO,100.0,24,[])
	check(flat.get_child_count()>0,"original vegetation remains on supported island ground")
	check(steep.get_child_count()==0,"reference cliff faces cannot sprout unsupported trees or grass")
	flat.free(); steep.free(); await process_frame
	print("REFERENCE_VEGETATION_SLOPES_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
