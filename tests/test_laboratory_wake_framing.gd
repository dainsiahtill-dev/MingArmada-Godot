extends SceneTree
var assertions := 0
var failures := 0
func check(ok: bool,detail: String) -> void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL wake framing: ",detail)
func _initialize() -> void:run.call_deferred()
func vessel_in_frame(demo: Node3D) -> bool:
	var camera: Camera3D=demo.get("_camera")
	for node: Node in demo.get("_ship").get_model().find_children("*","MeshInstance3D",true,false):
		if not node.is_visible_in_tree():continue
		var box: AABB=node.get_aabb()
		for corner in 8:
			var point: Vector3=node.global_transform*box.get_endpoint(corner)
			var pixel:=camera.unproject_position(point)
			if camera.is_position_behind(point) or pixel.x<16 or pixel.x>1184 or pixel.y<16 or pixel.y>744:return false
	return true
func tail_in_frame(demo: Node3D) -> bool:
	var attachment: Dictionary=demo.get("_ship").source_water_attachment()
	var profile: Dictionary=attachment.surfaceProfile
	var length: float=absf(float(profile.sections[-1].z)-float(profile.sections[0].z))*profile.hullToWorld.basis.z.length()
	var heading: float=demo.inspection_snapshot().native_ship.heading
	var forward:=Vector3(cos(heading),0,sin(heading))
	var camera: Camera3D=demo.get("_camera")
	for point: Vector3 in [attachment.flowStern,attachment.flowStern-forward*length*2.0]:
		var pixel:=camera.unproject_position(point)
		if camera.is_position_behind(point) or pixel.x<16 or pixel.x>1184 or pixel.y<16 or pixel.y>744:return false
	return true
func run() -> void:
	var demo=load("res://game/research/demos/wake_flow_experiment.gd").new()
	check(demo.get_default_options().get("turn_direction")=="right","existing positive-rudder default explicitly remains right")
	check(not demo.configure({"turn_direction":"up"}).ok,"unsupported turn direction rejected")
	check(demo.configure({"camera_mode":"high","zoom":.65,"scenario":"cruise"}).ok,"reported GPU framing fixture configures")
	var viewport:=SubViewport.new();viewport.size=Vector2i(1200,760);viewport.own_world_3d=true
	root.add_child(viewport);viewport.add_child(demo)
	for tick in 256:demo.advance(1.0/32.0)
	check(vessel_in_frame(demo),"high zoom .65 at8s includes every visible real-mesh AABB including main sail")
	check(tail_in_frame(demo),"high zoom .65 at8s includes stern and two actual waterline lengths aft")
	var source_camera: Transform3D=demo.get("_camera").global_transform
	check(demo.reset_experiment({"field_enabled":true}).ok,"field uses same initial fixture")
	for tick in 256:demo.advance(1.0/32.0)
	check(demo.get("_camera").global_transform.is_equal_approx(source_camera),"field selection cannot change camera fit")
	check(demo.reset_experiment({"field_enabled":false,"scenario":"turn"}).ok,"existing turn fixture remains available")
	for tick in 127:demo.advance(1.0/32.0)
	var right_before: Dictionary=demo.inspection_snapshot().native_ship
	check(right_before.rudder==0.0,"turn remains straight through observation tick127")
	demo.advance(1.0/32.0)
	check(demo.inspection_snapshot().native_ship.rudder==.45,"default right turn commands actual positive rudder on tick128")
	for tick in 128:demo.advance(1.0/32.0)
	var right_after: Dictionary=demo.inspection_snapshot().native_ship
	var left: Dictionary=demo.reset_experiment({"turn_direction":"left"})
	check(left.ok,"left direction accepted by existing experiment")
	if left.ok:
		for tick in 127:demo.advance(1.0/32.0)
		check(demo.inspection_snapshot().native_ship==right_before,"left/right preserve identical real motion before trigger")
		demo.advance(1.0/32.0)
		check(demo.inspection_snapshot().native_ship.rudder==-.45,"left branch is not overwritten by inherited positive rudder")
		for tick in 128:demo.advance(1.0/32.0)
		var left_after: Dictionary=demo.inspection_snapshot().native_ship
		check(left_after.heading<right_after.heading and left_after.position!=right_after.position,"opposite rudder changes actual physics trajectory")
		check(vessel_in_frame(demo) and tail_in_frame(demo),"left-turn camera retains actual vessel and aft inspection span")
		var change: Dictionary=demo.set_parameter("turn_direction","right")
		check(change.get("reset_required",false) and demo.inspection_snapshot().parameters.turn_direction=="left","direction change requires independent initial history")
	demo.dispose();viewport.free()
	print("LABORATORY_WAKE_FRAMING_PASS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
