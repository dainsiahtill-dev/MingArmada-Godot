extends SceneTree
const Details=preload("res://modules/scene_engine/world/island_details.gd")
var assertions:=0
var failures:=0
func check(value: bool,detail: String) -> void:
	assertions+=1
	if not value: failures+=1; printerr("FAIL: ",detail)
func bay_height(x: float,z: float) -> float:
	# The origin lies in water; two detached shoulders have valid outer shores.
	return maxf(-20.0+40.0*maxf(0.0,1.0-pow((x-62.0)/35.0,2)-pow(z/24.0,2)), -20.0+32.0*maxf(0.0,1.0-pow((x+47.0)/30.0,2)-pow((z-12.0)/27.0,2)))
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var details:=Details.new(); root.add_child(details)
	var port:={"id":"irregular-bay","x":105.0,"z":0.0,"islandX":0.0,"islandZ":0.0,"radius":100.0}
	check(details.configure(bay_height,[port],{"max_instances":0}),"irregular reference coast sampler is accepted")
	for target: float in [-1.3,0.7,3.5]:
		var shore: Vector3=details._contour(port,0.0,target)
		check(shore.is_finite(),"coast discovery supports a submerged island center")
		if shore.is_finite():
			check(absf(shore.y-target)<0.002,"located reference shoreline has actual requested elevation")
			check(shore.x>62.0,"shore props use outer shoulder facing open water")
	var missing: Vector3=details._contour(port,PI/2.0,0.5)
	check(not missing.is_finite(),"empty bay directions do not invent shoreline props")
	details.dispose(); details.free(); await process_frame
	print("REFERENCE_COASTAL_DRESSING_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
