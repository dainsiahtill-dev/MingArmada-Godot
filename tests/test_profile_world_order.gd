extends SceneTree
func _initialize() -> void:
	var source := FileAccess.get_file_as_string("res://tools/profile-hull-dynamics-world.gd")
	var start := source.find("func profile_sea(")
	var body := source.substr(start)
	body = body.left(body.find("\nfunc "))
	var world := body.find('measure(costs,"world",')
	var interactive := body.find('measure(costs,"interactiveWater",func(): sea._apply_interactive_water(native))')
	var shadows := body.find("profile_shadows(sea,native,costs)")
	var ok := world >= 0 and interactive > world and shadows > interactive
	if not ok: printerr("FAIL: CPU stage observer must preserve production world -> interactive-water -> source-shadows order")
	print("PROFILE_WORLD_ORDER_TESTS assertions=1 failures=",0 if ok else 1)
	quit(0 if ok else 1)
