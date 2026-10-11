extends SceneTree
var failures := 0
var assertions := 0
class FailingLibrary extends "res://modules/scene_engine/assets/asset_library.gd":
	var fail := true
	var attempts:Array[String]=[]
	func instantiate_model(path:String) -> Node3D:
		attempts.append(path)
		if fail and path=="res://assets/models/ships/merchant-lod2.glb": return null
		return super.instantiate_model(path)
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures += 1; printerr("FAIL: ",message)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	if not ResourceLoader.exists("res://game/scenes/ship_book/ship_book.tscn"):
		check(false,"native ship book exists with real GLB inspection"); _finish(); return
	var scene = load("res://game/scenes/ship_book/ship_book.tscn").instantiate()
	root.add_child(scene); await process_frame
	check(scene.startup_receipt.ok,"ship book loads default source GLB")
	for kind in ["fuchuan","fisherman","merchant","voc","patrol","heavy"]:
		for lod in 3:
			check(scene.select_ship(kind,lod).ok,"real ship GLB loads: %s LOD%s"%[kind,lod])
			check(scene.snapshot().path=="res://assets/models/ships/%s-lod%d.glb"%[kind,lod],"selected LOD is actual original asset")
			var sails := 0
			for mesh in scene.ship_model.find_children("sail_*","MeshInstance3D",true,false):
				sails+=1
				check(mesh.mesh.get_blend_shape_count()==2,"original sail morphs remain native")
			check(sails>0,"real ship retains authored rigging")
	scene.select_ship("fuchuan",0)
	var original: Dictionary = scene.snapshot()
	check(not scene.select_ship("missing",0).ok and scene.snapshot()==original,"bad ship preserves confirmed presentation")
	check(not scene.select_ship("fuchuan",9).ok,"invalid LOD refused")
	scene.set_furl(.75); scene.animate_model(0)
	for mesh in scene.ship_model.find_children("sail_*","MeshInstance3D",true,false):
		for index in mesh.mesh.get_blend_shape_count():
			var morph = mesh.mesh.get_blend_shape_name(index)
			if morph==&"furl": check(is_equal_approx(mesh.get_blend_shape_value(index),.75),"slider drives actual furl morph")
	var first: Vector3 = scene.camera.position
	var motion:=InputEventMouseMotion.new(); motion.button_mask=MOUSE_BUTTON_MASK_LEFT; motion.relative=Vector2(50,20)
	scene._view.gui_input.emit(motion); check(scene.camera.position!=first,"native drag event moves actual camera")
	var old_distance: float = scene.snapshot().distance
	var wheel:=InputEventMouseButton.new(); wheel.pressed=true; wheel.button_index=MOUSE_BUTTON_WHEEL_UP
	scene._view.gui_input.emit(wheel); check(scene.snapshot().distance<old_distance,"native wheel event changes bounded camera distance")
	for angle in ["quarter","bow","starboard","stern","port","underwater"]:
		check(scene.set_angle(angle),"source camera preset: "+angle)
		check(scene.sea.visible==(angle!="underwater"),"underwater hides sea for hull inspection")
	var yaw: float = scene.ship_model.rotation.y
	scene.find_child("TurnShip",true,false).pressed.emit(); check(is_equal_approx(scene.ship_model.rotation.y,yaw+PI/4),"native rotate button turns actual ship45degrees")
	scene.find_child("CannonRecoil",true,false).pressed.emit(); scene.animate_model(0)
	var barrels = scene.ship_model.find_children("barrel_*","Node3D",true,false)
	check(not barrels.is_empty(),"source real cannon barrels exist")
	if not barrels.is_empty():
		var recoil_z: float = barrels[0].position.z
		scene.animate_model(.5); check(barrels[0].position.z>recoil_z,"400ms recoil returns real cannon to rest")
	var rudder = scene.ship_model.find_child("rudder_pivot",true,false)
	check(rudder!=null,"authored rudder pivot remains native")
	if rudder:
		var rudder_yaw:float=rudder.rotation.y; scene.animate_model(.5)
		check(not is_equal_approx(rudder.rotation.y,rudder_yaw),"source rudder animation changes actual rig")
	var picker=scene.find_child("ShipKind",true,false)
	picker.select(3); picker.item_selected.emit(3)
	check(scene.snapshot().kind=="voc" and scene.find_child("ShipDescription",true,false).text.contains("40 m"),"native ship selector hydrates actual source dimensions")
	var lod_picker=scene.find_child("ShipLOD",true,false)
	lod_picker.select(2); lod_picker.item_selected.emit(2)
	check(scene.snapshot().lod==2,"native LOD selector loads actual distance model")
	scene.zoom(.00001); var minimum:float=scene.snapshot().distance
	scene.zoom(.00001); check(is_equal_approx(scene.snapshot().distance,minimum),"zoom clamps lower model-relative distance")
	scene.zoom(10000); var maximum:float=scene.snapshot().distance
	scene.zoom(10000); check(is_equal_approx(scene.snapshot().distance,maximum),"zoom clamps upper model-relative distance")
	var injected:=FailingLibrary.new(); scene._library.dispose(); scene._library=injected
	scene.select_ship("fuchuan",0)
	var confirmed_model:Node3D=scene.ship_model; var confirmed:Dictionary=scene.snapshot()
	check(not scene.select_ship("merchant",2).ok and scene.ship_model==confirmed_model and scene.snapshot()==confirmed,"failed requested GLB preserves confirmed ship and presentation")
	injected.fail=false
	scene.find_child("RetryModel",true,false).pressed.emit()
	check(injected.attempts[-1]=="res://assets/models/ships/merchant-lod2.glb" and scene.snapshot().kind=="merchant" and scene.snapshot().lod==2,"native RetryModel recovers last attempted ship/LOD")
	var leaves: Array = []; scene.main_menu_requested.connect(func(): leaves.append(true))
	scene.find_child("MainMenu",true,false).pressed.emit(); check(leaves.size()==1,"ship book returns through owner signal")
	scene.queue_free(); await process_frame; _finish()
func _finish() -> void:
	print("SHIP_BOOK_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
