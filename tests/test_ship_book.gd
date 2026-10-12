extends SceneTree
var failures := 0
var assertions := 0
var _sent_button_mask := 0
const SOURCE_FAMILIES := {"fuchuan":"barque","fisherman":"sloop1","merchant":"ship_merman","voc":"frigate","patrol":"ship_brigantine","heavy":"treasure_galleon"}
class FailingLibrary extends "res://modules/scene_engine/assets/asset_library.gd":
	var fail := true
	var attempts:Array[String]=[]
	func instantiate_model(path:String) -> Node3D:
		attempts.append(path)
		if fail and path=="res://assets/models/fidelity_naval/ship_merman.glb": return null
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
	scene.set_process(false)
	check(scene.startup_receipt.ok,"ship book loads default source GLB")
	for kind in ["fuchuan","fisherman","merchant","voc","patrol","heavy"]:
		for lod in 3:
			check(scene.select_ship(kind,lod).ok,"real ship GLB loads: %s LOD%s"%[kind,lod])
			check(scene.snapshot().path=="res://assets/models/fidelity_naval/%s.glb"%SOURCE_FAMILIES[kind] and scene.snapshot().source_kind==SOURCE_FAMILIES[kind],"selected game kind uses its distinct original reference family")
			var sails := 0
			for mesh in scene.ship_model.find_children("sail_*","MeshInstance3D",true,false):
				if mesh.get_meta("source_sail_control","") != "game_furl_inflate_morph":
					check(not mesh.visible and mesh.get_meta("damage_surface","") == "sail","original hidden furled targets do not create duplicate cloth")
					continue
				sails+=1
				check(mesh.mesh.get_blend_shape_count()==2 and mesh.get_meta("source_sail_control","")=="game_furl_inflate_morph","original rigid sail has explicit game furl/inflate controls")
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
	_mouse_button(scene,MOUSE_BUTTON_LEFT,true)
	scene._view.gui_input.emit(motion); check(scene.camera.position!=first,"native drag event moves actual camera")
	_mouse_button(scene,MOUSE_BUTTON_LEFT,false)
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
	_test_orbit_controls(scene)
	await _test_camera_gui_routing(scene)
	await _test_mouse_chords(scene)
	var injected:=FailingLibrary.new(); scene._library.dispose(); scene._library=injected
	scene.select_ship("fuchuan",0)
	var confirmed_model:Node3D=scene.ship_model; var confirmed:Dictionary=scene.snapshot()
	check(not scene.select_ship("merchant",2).ok and scene.ship_model==confirmed_model and scene.snapshot()==confirmed,"failed requested GLB preserves confirmed ship and presentation")
	injected.fail=false
	scene.find_child("RetryModel",true,false).pressed.emit()
	check(injected.attempts[-1]=="res://assets/models/fidelity_naval/ship_merman.glb" and scene.snapshot().kind=="merchant" and scene.snapshot().lod==2,"native RetryModel recovers last attempted ship/LOD")
	var leaves: Array = []; scene.main_menu_requested.connect(func(): leaves.append(true))
	_mouse_button(scene,MOUSE_BUTTON_RIGHT,true); _mouse_motion(scene,Vector2(40,10),MOUSE_BUTTON_MASK_RIGHT)
	scene.find_child("MainMenu",true,false).pressed.emit(); check(leaves.size()==1,"ship book returns through owner signal")
	var left_position:Vector3=scene.camera.position; var left_target:Vector3=scene._target
	scene._process(.016); _mouse_motion(scene,Vector2(40,10),MOUSE_BUTTON_MASK_RIGHT)
	check(scene.camera.position==left_position and scene._target==left_target,"disposed owner fences input and residual motion")
	check(scene.get("_held_mouse_buttons")==0,"disposed owner clears all held mouse buttons")
	scene.queue_free(); await process_frame; _finish()
func _mouse_button(scene, button:int, pressed:bool, modifiers:Dictionary={}) -> void:
	var event:=InputEventMouseButton.new(); event.button_index=button; event.pressed=pressed; event.position=Vector2(100,100)
	if button in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
		var bit:int=1<<(button-1)
		_sent_button_mask=(_sent_button_mask|bit) if pressed else (_sent_button_mask&~bit)
	event.button_mask=_sent_button_mask
	event.ctrl_pressed=modifiers.get("ctrl",false); event.meta_pressed=modifiers.get("meta",false); event.shift_pressed=modifiers.get("shift",false); event.alt_pressed=modifiers.get("alt",false)
	scene._view.gui_input.emit(event)
func _mouse_motion(scene, movement:Vector2, mask:int, modifiers:Dictionary={}) -> void:
	var event:=InputEventMouseMotion.new(); event.relative=movement; event.position=Vector2(100,100)+movement; event.button_mask=mask
	event.ctrl_pressed=modifiers.get("ctrl",false); event.meta_pressed=modifiers.get("meta",false); event.shift_pressed=modifiers.get("shift",false); event.alt_pressed=modifiers.get("alt",false)
	scene._view.gui_input.emit(event)
func _settle_camera(scene) -> void:
	for frame in 500: scene._process(1.0/60)
func _offset(yaw:float,pitch:float,distance:float) -> Vector3:
	return Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*distance
func _test_orbit_controls(scene) -> void:
	_settle_camera(scene); scene.set_angle("quarter")
	scene._view.size=Vector2(800,400)
	var initial_target:Vector3=scene._target; var initial_offset:Vector3=scene.camera.position-initial_target
	var yaw:float=atan2(initial_offset.x,initial_offset.z); var pitch:float=atan2(initial_offset.y,Vector2(initial_offset.x,initial_offset.z).length())
	var distance:float=initial_offset.length(); var movement:=Vector2(40,20)
	var delta_yaw:float=-TAU*movement.x/400; var delta_pitch:float=TAU*movement.y/400
	_mouse_motion(scene,movement,MOUSE_BUTTON_MASK_LEFT)
	check(scene.camera.position.is_equal_approx(initial_target+initial_offset),"drag must begin in model view; stale held-button motion alone is ignored")
	_mouse_button(scene,MOUSE_BUTTON_LEFT,true); _mouse_motion(scene,movement,MOUSE_BUTTON_MASK_LEFT)
	check(scene.camera.position.is_equal_approx(initial_target+_offset(yaw+delta_yaw*.05,pitch+delta_pitch*.05,distance)),"orbit event applies exact source height-normalized 5% spherical delta")
	_mouse_button(scene,MOUSE_BUTTON_LEFT,false)
	for frame in 4: scene._process(.001 if frame%2 else .25)
	var applied:float=1-pow(.95,5)
	check(scene.camera.position.is_equal_approx(initial_target+_offset(yaw+delta_yaw*applied,pitch+delta_pitch*applied,distance)),"released orbit decays remaining delta by .95 per frame independent of delta time")
	check(scene._target.is_equal_approx(initial_target) and is_equal_approx(scene.snapshot().distance,distance),"orbit preserves target and radius")
	_settle_camera(scene); scene.set_angle("quarter")
	scene._view.size=Vector2(800,800)
	initial_offset=scene.camera.position-scene._target; yaw=atan2(initial_offset.x,initial_offset.z); pitch=atan2(initial_offset.y,Vector2(initial_offset.x,initial_offset.z).length())
	_mouse_button(scene,MOUSE_BUTTON_LEFT,true); _mouse_motion(scene,movement,MOUSE_BUTTON_MASK_LEFT); _mouse_button(scene,MOUSE_BUTTON_LEFT,false)
	check(scene.camera.position.is_equal_approx(scene._target+_offset(yaw+delta_yaw*.025,pitch+delta_pitch*.025,distance)),"double viewport height halves orbit sensitivity")
	_settle_camera(scene); scene.set_angle("quarter"); scene._view.size=Vector2(800,400); scene._view.stretch_shrink=2
	initial_target=scene._target; initial_offset=scene.camera.position-initial_target
	var basis:Basis=scene.camera.basis; var pan:Vector3=(-basis.x*movement.x+basis.y*movement.y)*(2*distance*tan(deg_to_rad(45)/2)/400)
	_mouse_button(scene,MOUSE_BUTTON_RIGHT,true); _mouse_motion(scene,movement,MOUSE_BUTTON_MASK_RIGHT); _mouse_button(scene,MOUSE_BUTTON_RIGHT,false)
	check(scene._target.is_equal_approx(initial_target+pan*.05),"right pan translates target in camera screen plane using FOV/radius and displayed height despite render downscale")
	check((scene.camera.position-scene._target).is_equal_approx(initial_offset),"pan translates camera and target together without orbit or zoom")
	for frame in 4: scene._process(.016)
	check(scene._target.is_equal_approx(initial_target+pan*applied),"pan inertia accumulates exact source 5%/95% recurrence after release")
	for modifier in ["ctrl","meta","shift"]:
		_settle_camera(scene); scene.set_angle("quarter"); initial_target=scene._target; initial_offset=scene.camera.position-initial_target
		basis=scene.camera.basis; pan=(-basis.x*movement.x+basis.y*movement.y)*(2*distance*tan(deg_to_rad(45)/2)/400)
		_mouse_button(scene,MOUSE_BUTTON_LEFT,true,{modifier:true}); _mouse_motion(scene,movement,MOUSE_BUTTON_MASK_LEFT)
		check(scene._target.is_equal_approx(initial_target+pan*.05) and (scene.camera.position-scene._target).is_equal_approx(initial_offset),modifier+" left drag swaps to pan and stays pan when modifier changes during drag")
		_mouse_button(scene,MOUSE_BUTTON_LEFT,false)
		_settle_camera(scene); scene.set_angle("quarter"); initial_target=scene._target
		_mouse_button(scene,MOUSE_BUTTON_RIGHT,true,{modifier:true}); _mouse_motion(scene,movement,MOUSE_BUTTON_MASK_RIGHT)
		check(scene._target.is_equal_approx(initial_target) and not scene.camera.position.is_equal_approx(initial_target+initial_offset),modifier+" right drag swaps to orbit")
		_mouse_button(scene,MOUSE_BUTTON_RIGHT,false)
	_settle_camera(scene); scene.set_angle("quarter"); initial_target=scene._target
	_mouse_button(scene,MOUSE_BUTTON_LEFT,true,{"alt":true}); _mouse_motion(scene,movement,MOUSE_BUTTON_MASK_LEFT); _mouse_button(scene,MOUSE_BUTTON_LEFT,false)
	check(scene._target.is_equal_approx(initial_target),"Alt retains source left orbit rather than pan")
	_settle_camera(scene); scene.set_angle("quarter"); initial_target=scene._target
	_mouse_button(scene,MOUSE_BUTTON_MIDDLE,true); _mouse_motion(scene,Vector2(30,100),MOUSE_BUTTON_MASK_MIDDLE)
	check(is_equal_approx(scene.snapshot().distance,distance/.95) and scene._target.is_equal_approx(initial_target),"middle drag dolly uses .95^(abs(pixel delta)*.01), ignores horizontal delta")
	_mouse_button(scene,MOUSE_BUTTON_WHEEL_UP,true)
	check(is_equal_approx(scene.snapshot().distance,distance/.95),"source wheel is ignored during active pointer drag")
	_mouse_motion(scene,Vector2(0,-100),MOUSE_BUTTON_MASK_MIDDLE); _mouse_button(scene,MOUSE_BUTTON_MIDDLE,false)
	check(is_equal_approx(scene.snapshot().distance,distance),"middle drag opposite direction restores exact distance")
	var wheel:=InputEventMouseButton.new(); wheel.button_index=MOUSE_BUTTON_WHEEL_UP; wheel.pressed=true; wheel.factor=2
	scene._view.gui_input.emit(wheel)
	check(is_equal_approx(scene.snapshot().distance,distance*pow(.95,2)),"native wheel factor preserves normalized source exponential dolly")
	check(scene._target.is_equal_approx(initial_target),"zoomToCursor default false leaves target unchanged")
	scene.set_angle("quarter"); distance=scene.snapshot().distance
	wheel.factor=1; wheel.ctrl_pressed=true; scene._view.gui_input.emit(wheel)
	check(is_equal_approx(scene.snapshot().distance,distance*pow(.95,10)),"source synthetic Ctrl-wheel pinch uses tenfold delta without physical Control key")
	scene.set_angle("quarter")
	var control:=InputEventKey.new(); control.keycode=KEY_CTRL; control.physical_keycode=KEY_CTRL; control.pressed=true; root.push_input(control)
	scene._view.gui_input.emit(wheel)
	check(is_equal_approx(scene.snapshot().distance,distance*.95),"physical Control key keeps ordinary Ctrl-wheel delta rather than pinch acceleration")
	control.pressed=false; root.push_input(control)
	for angle in scene.ANGLES:
		_settle_camera(scene); scene.set_angle(angle)
		var preset_position:Vector3=scene.camera.position; var preset_target:Vector3=scene._target
		check(preset_position.is_equal_approx(_source_preset_position(scene,angle)),"settled preset uses exact source camera position: "+angle)
		var draft:float=0
		for ship:Dictionary in scene.SHIPS:
			if ship.id==scene.snapshot().kind: draft=ship.draft
		var expected_target:Vector3=Vector3(0,-draft*.65,0) if angle=="underwater" else scene._center
		check(preset_target.is_equal_approx(expected_target),"settled preset uses exact source center/draft target: "+angle)
		_mouse_button(scene,MOUSE_BUTTON_LEFT,true); _mouse_motion(scene,movement,MOUSE_BUTTON_MASK_LEFT); _mouse_button(scene,MOUSE_BUTTON_LEFT,false)
		scene.set_angle(angle)
		var preset_offset:Vector3=preset_position-preset_target
		var preset_yaw:float=atan2(preset_offset.x,preset_offset.z); var preset_pitch:float=atan2(preset_offset.y,Vector2(preset_offset.x,preset_offset.z).length())
		check(scene.camera.position.is_equal_approx(preset_target+_offset(preset_yaw+delta_yaw*.95*.05,preset_pitch+delta_pitch*.95*.05,preset_offset.length())),"preset reframe preserves source pending orbit and performs one controls.update: "+angle)
		_settle_camera(scene); scene.set_angle(angle); preset_target=scene._target; basis=scene.camera.basis
		pan=(-basis.x*movement.x+basis.y*movement.y)*(2*(scene.camera.position-preset_target).length()*tan(deg_to_rad(45)/2)/400)
		_mouse_button(scene,MOUSE_BUTTON_RIGHT,true); _mouse_motion(scene,movement,MOUSE_BUTTON_MASK_RIGHT); _mouse_button(scene,MOUSE_BUTTON_RIGHT,false)
		scene.set_angle(angle)
		check(scene._target.is_equal_approx(preset_target+pan*.95*.05),"preset preserves source pending pan during camera/target replacement: "+angle)
	_settle_camera(scene); scene.set_angle("bow")
	_mouse_button(scene,MOUSE_BUTTON_LEFT,true); _mouse_motion(scene,Vector2(0,100000),MOUSE_BUTTON_MASK_LEFT); _mouse_button(scene,MOUSE_BUTTON_LEFT,false)
	var pole_offset:Vector3=scene.camera.position-scene._target
	var horizontal:float=Vector2(pole_offset.x,pole_offset.z).length()/pole_offset.length()
	check(absf(horizontal-.000001)<.0000001 and pole_offset.y>0,"source minPolarAngle zero clamps at spherical epsilon 1e-6, not .01")
	_settle_camera(scene); scene.set_angle("bow")
	_mouse_button(scene,MOUSE_BUTTON_LEFT,true); _mouse_motion(scene,Vector2(0,-100000),MOUSE_BUTTON_MASK_LEFT); _mouse_button(scene,MOUSE_BUTTON_LEFT,false)
	pole_offset=scene.camera.position-scene._target; horizontal=Vector2(pole_offset.x,pole_offset.z).length()/pole_offset.length()
	check(absf(horizontal-.000001)<.0000001 and pole_offset.y<0,"setAngle overrides mount limit to source maxPolarAngle PI")
	_settle_camera(scene); scene.set_angle("quarter")
	scene.zoom(.000001); check(is_equal_approx(scene.snapshot().distance,scene._scale*.25),"source GLB scale defines exact minimum dolly radius")
	scene.zoom(1000000); check(is_equal_approx(scene.snapshot().distance,scene._scale*4),"source GLB scale defines exact maximum dolly radius")
	_settle_camera(scene); scene.set_angle("quarter")
	basis=scene.camera.basis; pan=(-basis.x*movement.x+basis.y*movement.y)*(2*(scene.camera.position-scene._target).length()*tan(deg_to_rad(45)/2)/400)
	_mouse_button(scene,MOUSE_BUTTON_RIGHT,true); _mouse_motion(scene,movement,MOUSE_BUTTON_MASK_RIGHT); _mouse_button(scene,MOUSE_BUTTON_RIGHT,false)
	var old_pan_residual:Vector3=pan*.95
	scene.select_ship("fuchuan",0)
	check(scene._target.is_equal_approx(scene._center+old_pan_residual*.05),"successful model replacement preserves source controls pan residual")
	_settle_camera(scene); scene.set_angle("quarter")
	_mouse_button(scene,MOUSE_BUTTON_RIGHT,true); _mouse_motion(scene,Vector2(100000,0),MOUSE_BUTTON_MASK_RIGHT); _mouse_button(scene,MOUSE_BUTTON_RIGHT,false)
	check(scene._target.distance_to(scene._center)>scene._scale*4,"default source maxTargetRadius Infinity permits unrestricted panning")
	_settle_camera(scene); scene.set_angle("quarter"); scene._view.stretch_shrink=1; scene._layout()
	check(scene._view.focus_mode==Control.FOCUS_NONE,"model viewport never takes sidebar keyboard focus")
func _source_preset_position(scene,angle:String) -> Vector3:
	var scale:float=scene._scale; var center:Vector3=scene._center
	match angle:
		"bow": return Vector3(0,center.y+scale*.35,scale*1.65)
		"stern": return Vector3(0,center.y+scale*.35,-scale*1.65)
		"starboard": return Vector3(-scale*1.65,center.y+scale*.35,0)
		"port": return Vector3(scale*1.65,center.y+scale*.35,0)
		"underwater": return Vector3(-scale*1.05,-scale*.3,scale*.75)
		_: return Vector3(scale*1.25,center.y+scale*.6,scale*1.3)
func _test_camera_gui_routing(scene) -> void:
	root.size=Vector2i(1600,900); await process_frame
	_settle_camera(scene); scene.set_angle("quarter"); scene._layout(); await process_frame
	var initial_position:Vector3=scene.camera.position; var initial_target:Vector3=scene._target
	var picker=scene.find_child("ShipKind",true,false); picker.grab_focus()
	var wheel:=InputEventMouseButton.new(); wheel.pressed=true; wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN; wheel.position=picker.get_global_rect().get_center(); root.push_input(wheel,true)
	check(scene.camera.position.is_equal_approx(initial_position) and scene._target.is_equal_approx(initial_target),"actual root-routed wheel over sidebar never reaches camera control")
	wheel.pressed=false; root.push_input(wheel,true)
	var key:=InputEventKey.new(); key.pressed=true; key.keycode=KEY_LEFT; key.physical_keycode=KEY_LEFT; root.push_input(key)
	check(scene.camera.position.is_equal_approx(initial_position),"focused sidebar owns arrow keys; source never enabled OrbitControls keyboard pan")
	picker.get_popup().hide()
	# Real GUI dispatch starts orbit inside view and preserves the selector's focus.
	var position:Vector2=scene._view.get_global_rect().get_center()
	var press:=InputEventMouseButton.new(); press.pressed=true; press.button_index=MOUSE_BUTTON_LEFT; press.button_mask=MOUSE_BUTTON_MASK_LEFT; press.position=position; press.global_position=position; root.push_input(press,true)
	var motion:=InputEventMouseMotion.new(); motion.position=position+Vector2(40,20); motion.global_position=motion.position; motion.relative=Vector2(40,20); motion.button_mask=MOUSE_BUTTON_MASK_LEFT; root.push_input(motion,true)
	check(not scene.camera.position.is_equal_approx(initial_position),"actual root-routed pointer inside viewport reaches native camera")
	check(root.gui_get_focus_owner()==picker,"actual model-view click leaves sidebar keyboard focus intact")
	press.pressed=false; press.position=motion.position; root.push_input(press,true)
	_settle_camera(scene); scene.set_angle("quarter")
	var projection:Projection=scene.camera.get_camera_projection()
	check(is_equal_approx(projection.y.y,1/tan(deg_to_rad(45)/2)),"camera retains source 45-degree vertical FOV")
	check(is_equal_approx(projection.y.y/projection.x.x,float(scene._viewport.size.x)/scene._viewport.size.y),"camera projection uses actual ship viewport aspect")
	root.size=Vector2i(800,450); scene._view.stretch_shrink=2; await process_frame
	scene._layout(); await process_frame
	_settle_camera(scene); scene.set_angle("quarter")
	initial_target=scene._target; var initial_offset:Vector3=scene.camera.position-initial_target
	var yaw:float=atan2(initial_offset.x,initial_offset.z); var pitch:float=atan2(initial_offset.y,Vector2(initial_offset.x,initial_offset.z).length())
	var screen_transform:Transform2D=root.get_final_transform()
	position=screen_transform*scene._view.get_global_rect().get_center()
	press.pressed=true; press.position=position; press.global_position=position; root.push_input(press,false)
	motion.position=position+Vector2(40,20); motion.global_position=motion.position; motion.relative=Vector2(40,20); root.push_input(motion,false)
	var displayed_height:float=scene._view.size.y*screen_transform.get_scale().y
	check(scene.camera.position.is_equal_approx(initial_target+_offset(yaw-TAU*40/displayed_height*.05,pitch+TAU*20/displayed_height*.05,initial_offset.length())),"actual stretched-window input and downscaled viewport retain source displayed-height orbit sensitivity")
	press.pressed=false; press.position=motion.position; root.push_input(press,false)
	_settle_camera(scene); scene.set_angle("quarter"); scene._view.stretch_shrink=1
func _finish() -> void:
	print("SHIP_BOOK_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
func _route_button(position:Vector2,button:int,pressed:bool,mask:int) -> void:
	var event:=InputEventMouseButton.new(); event.position=position; event.global_position=position; event.button_index=button; event.pressed=pressed; event.button_mask=mask
	Input.parse_input_event(event); Input.flush_buffered_events()
func _route_motion(position:Vector2,movement:Vector2,mask:int) -> void:
	var event:=InputEventMouseMotion.new(); event.position=position+movement; event.global_position=event.position; event.relative=movement; event.button_mask=mask
	Input.parse_input_event(event); Input.flush_buffered_events()
func _test_mouse_chords(scene) -> void:
	root.size=Vector2i(1600,900); await process_frame; scene._layout(); await process_frame
	_settle_camera(scene); scene.set_angle("quarter")
	var position:Vector2=scene._view.get_global_rect().get_center(); var movement:=Vector2(40,20)
	var target:Vector3=scene._target; var offset:Vector3=scene.camera.position-target
	var yaw:float=atan2(offset.x,offset.z); var pitch:float=atan2(offset.y,Vector2(offset.x,offset.z).length())
	var angular:Vector2=Vector2(-movement.x,movement.y)*TAU/scene._view.size.y
	_route_button(position,MOUSE_BUTTON_LEFT,true,MOUSE_BUTTON_MASK_LEFT)
	_route_motion(position,movement,MOUSE_BUTTON_MASK_LEFT)
	_route_button(position,MOUSE_BUTTON_RIGHT,true,MOUSE_BUTTON_MASK_LEFT|MOUSE_BUTTON_MASK_RIGHT)
	_route_motion(position,movement,MOUSE_BUTTON_MASK_LEFT|MOUSE_BUTTON_MASK_RIGHT)
	check(scene._target.is_equal_approx(target) and scene.camera.position.is_equal_approx(target+_offset(yaw+angular.x*.1475,pitch+angular.y*.1475,offset.length())),"routed left+right chord retains first orbit gesture and exact recurrence")
	_route_button(position,MOUSE_BUTTON_RIGHT,false,MOUSE_BUTTON_MASK_LEFT)
	_route_motion(position,movement,MOUSE_BUTTON_MASK_LEFT)
	check(scene._target.is_equal_approx(target) and scene.camera.position.is_equal_approx(target+_offset(yaw+angular.x*.290125,pitch+angular.y*.290125,offset.length())),"routed secondary release with left still held continues source orbit")
	_route_button(position,MOUSE_BUTTON_LEFT,false,0)
	var released_position:Vector3=scene.camera.position
	_route_motion(position,movement,0)
	check(scene.camera.position.is_equal_approx(released_position),"routed last button release ends pointer gesture")
	_settle_camera(scene); scene.set_angle("quarter"); target=scene._target; offset=scene.camera.position-target
	_route_button(position,MOUSE_BUTTON_LEFT,true,MOUSE_BUTTON_MASK_LEFT)
	_route_button(position,MOUSE_BUTTON_RIGHT,true,MOUSE_BUTTON_MASK_LEFT|MOUSE_BUTTON_MASK_RIGHT)
	_route_button(position,MOUSE_BUTTON_LEFT,false,MOUSE_BUTTON_MASK_RIGHT)
	_route_motion(position,movement,MOUSE_BUTTON_MASK_RIGHT)
	check(scene._target.is_equal_approx(target) and not scene.camera.position.is_equal_approx(target+offset),"routed original left release with right still held retains first orbit gesture")
	_route_button(position,MOUSE_BUTTON_RIGHT,false,0)
	_settle_camera(scene); scene.set_angle("quarter"); target=scene._target; offset=scene.camera.position-target
	var pan:Vector3=(-scene.camera.basis.x*movement.x+scene.camera.basis.y*movement.y)*(2*offset.length()*tan(deg_to_rad(45)/2)/scene._view.size.y)
	_route_button(position,MOUSE_BUTTON_RIGHT,true,MOUSE_BUTTON_MASK_RIGHT)
	_route_button(position,MOUSE_BUTTON_LEFT,true,MOUSE_BUTTON_MASK_LEFT|MOUSE_BUTTON_MASK_RIGHT)
	_route_button(position,MOUSE_BUTTON_RIGHT,false,MOUSE_BUTTON_MASK_LEFT)
	_route_motion(position,movement,MOUSE_BUTTON_MASK_LEFT)
	check(scene._target.is_equal_approx(target+pan*.05) and (scene.camera.position-scene._target).is_equal_approx(offset),"routed right-first chord retains pan after original right release")
	_route_button(position,MOUSE_BUTTON_LEFT,false,0)
	_settle_camera(scene); scene.set_angle("quarter"); var distance:float=scene.snapshot().distance
	_route_button(position,MOUSE_BUTTON_MIDDLE,true,MOUSE_BUTTON_MASK_MIDDLE)
	_route_button(position,MOUSE_BUTTON_LEFT,true,MOUSE_BUTTON_MASK_LEFT|MOUSE_BUTTON_MASK_MIDDLE)
	_route_button(position,MOUSE_BUTTON_MIDDLE,false,MOUSE_BUTTON_MASK_LEFT)
	_route_motion(position,Vector2(0,100),MOUSE_BUTTON_MASK_LEFT)
	check(is_equal_approx(scene.snapshot().distance,distance/.95),"routed middle-first chord retains dolly while only secondary left remains")
	_route_button(position,MOUSE_BUTTON_LEFT,false,0)
	_settle_camera(scene); scene.set_angle("quarter")
	_route_button(position,MOUSE_BUTTON_LEFT,true,MOUSE_BUTTON_MASK_LEFT)
	_route_button(position,MOUSE_BUTTON_RIGHT,true,MOUSE_BUTTON_MASK_LEFT|MOUSE_BUTTON_MASK_RIGHT)
	scene.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(scene.get("_held_mouse_buttons")==0 and scene._camera_gesture==scene.CameraGesture.NONE,"focus cancellation clears held mouse chord and active gesture")
	# The native input system still needs physical release events after a synthetic
	# focus notification; those must not resurrect the cancelled camera gesture.
	_route_button(position,MOUSE_BUTTON_LEFT,false,MOUSE_BUTTON_MASK_RIGHT); _route_button(position,MOUSE_BUTTON_RIGHT,false,0)
	released_position=scene.camera.position; _route_motion(position,movement,0)
	check(scene.camera.position.is_equal_approx(released_position),"focus cancellation ignores stale post-focus releases/motion")
	_route_button(position,MOUSE_BUTTON_RIGHT,true,MOUSE_BUTTON_MASK_RIGHT); _route_motion(position,movement,MOUSE_BUTTON_MASK_RIGHT)
	check(scene._target!=scene._center,"new first press after focus cancellation starts fresh pan gesture")
	_route_button(position,MOUSE_BUTTON_RIGHT,false,0)
	_settle_camera(scene); scene.set_angle("quarter")
