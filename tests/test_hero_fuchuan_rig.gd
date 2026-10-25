extends SceneTree
const Ship=preload("res://game/presentation/ships/ship_view.gd")
const Hero=preload("res://modules/scene_engine/assets/hero_ship_provider.gd")
const Encounter=preload("res://modules/naval_simulation/encounter.gd")
const Crew=preload("res://game/presentation/crew/crew_view.gd")
var assertions:=0
var failures:=0
func check(v:bool,why:String)->void:
	assertions+=1
	if not v:failures+=1;printerr("FAIL: ",why)
func _initialize()->void:run.call_deferred()
func run()->void:
	var view:=Ship.new();root.add_child(view)
	check(view.configure("fuchuan",null,Hero.new()),"original flagship configures in real ShipView")
	var state={"id":"player","time":0.0,"kind":"fuchuan","sailAngle":0.0,"sailDeployment":1.0,"rudder":0.0,"hull":100,"sail":100,"crew":100,"visual":{"position":{"x":0,"y":0,"z":0},"heading":PI/2,"pitch":0,"heel":0,"velocity":{"x":0,"z":0}}}
	var wind={"direction":{"x":1,"y":0},"speed":14}
	view.apply_snapshot(state,wind,0)
	var model:Node3D=view.get_model()
	var rudder:=model.find_child("rudder_pivot",true,false) as Node3D
	var tiller:=model.find_child("tiller_grip",true,false) as Node3D
	var sail:=model.find_child("sail_1",true,false) as MeshInstance3D
	var mast:=model.find_child("mast_1",true,false) as Node3D
	var has_cloth_transmission:=false
	for surface in sail.mesh.get_surface_count():
		var original=sail.mesh.surface_get_material(surface)
		var drawn=sail.get_active_material(surface)
		if original.resource_name=="canvas" and drawn is ShaderMaterial:
			has_cloth_transmission=drawn.get_shader_parameter("authored_thin_cloth")==true
		if original.resource_name!="canvas":check(drawn is StandardMaterial3D,"solid battens and sheets do not receive cloth-tearing shader")
	check(has_cloth_transmission,"authored thin cloth retains readable backlighting after damage material binding")
	var rest:=rudder.transform;var rest_tiller:=tiller.global_transform
	check(sail.get_blend_shape_value(0)==0,"full deployment displays open cloth and battens")
	state.time=1.0;state.rudder=1.0;state.sailAngle=.4;state.sailDeployment=0.0
	var untouched:Dictionary=state.duplicate(true)
	view.apply_snapshot(state,wind,1)
	check(absf(rudder.rotation.y-.42)<.001 and not rudder.transform.is_equal_approx(rest),"accepted rudder drives the blade")
	check(not tiller.global_transform.is_equal_approx(rest_tiller),"same pivot drives physical tiller grip")
	check(absf(mast.rotation.y+.4)<.001,"accepted trim turns the sail assembly")
	check(sail.get_blend_shape_value(0)==1 and sail.get_blend_shape_value(1)==0,"fully furled cloth/battens cannot remain inflated")
	check(state==untouched,"visual integration never mutates authority")
	var paused:=tiller.global_transform
	view.apply_snapshot(state,wind,0);check(tiller.global_transform==paused,"repeated paused time holds steering still")
	state.time=0.0;state.rudder=0.0;state.sailAngle=0.0;state.sailDeployment=1.0
	view.apply_snapshot(state,wind,0);check(rudder.transform.is_equal_approx(rest) and sail.get_blend_shape_value(0)==0,"rewind restores rig initial state")
	var crew:=Crew.new();view.add_child(crew)
	check(crew.configure("fuchuan",model),"new hull supports production deck actors")
	crew.apply_snapshot(state,wind,0)
	check(crew.get_visible_count()>0,"actual crew are visible on the authored deck")
	var water:Dictionary=view.source_water_attachment()
	check(water.has("surfaceProfile") and water.has("flowStern"),"normal water-effects adapter receives new hull contour")
	var socket:=model.find_child("socket_smoke_port_00",true,false) as Node3D
	var shot={"type":"fire","id":"hero-port-1","shipId":"player","side":"port","time":0.0,"position":{"x":socket.global_position.x,"y":socket.global_position.y,"z":socket.global_position.z}}
	var smoke:Variant=view.source_fire_position(shot)
	check(smoke is Vector3 and smoke.distance_to(socket.global_position)<.001,"real smoke adapter uses authored muzzle position")
	var barrel:=model.find_child("barrel_port_00",true,false) as Node3D
	var barrel_before:=barrel.global_position
	view.apply_events([shot])
	var recoil:=barrel.global_position-barrel_before
	check(recoil.length()>.5 and recoil.normalized().dot(Vector3.RIGHT)<-.99,"visible cannon recoils opposite port shot")
	var shrouds:=model.find_child("rigging_1",true,false) as Node3D
	var shroud_rest:=shrouds.transform
	state.time=1.0;state.sail=0.0;view.apply_snapshot(state,wind,1)
	state.time=4.0;view.apply_snapshot(state,wind,3)
	check(not shrouds.transform.is_equal_approx(shroud_rest),"standing shrouds fall with their destroyed mast")
	crew.dispose();crew.free();view.dispose();view.free();await process_frame
	var ordinary:=Ship.new();root.add_child(ordinary)
	check(ordinary.configure("fuchuan") and ordinary.get_model().get_meta("model_origin","")=="blender_authored","ordinary player renderer selects the authored flagship")
	ordinary.dispose();ordinary.free();await process_frame
	print("HERO_FUCHUAN_RIG_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
