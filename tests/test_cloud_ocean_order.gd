extends SceneTree
const Atmosphere=preload("res://modules/scene_engine/fidelity_fx/atmosphere.gd")
const Weather=preload("res://modules/environment_engine/weather_state.gd")
const Ocean=preload("res://modules/scene_engine/ocean/projected_ocean.gd")
var assertions:=0
var failures:=0
func check(ok:bool,message:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL: ",message)
func _initialize()->void:run.call_deferred()
func run()->void:
	var owner:=Node3D.new();root.add_child(owner)
	var camera:=Camera3D.new();owner.add_child(camera);camera.position=Vector3(0,40,100);camera.look_at(Vector3.ZERO)
	var ocean:=Ocean.new();owner.add_child(ocean);ocean.configure(camera,load("res://assets/textures/waternormals.jpg"),12,3000);ocean.set_visual_style(1)
	var renderer:=Atmosphere.new()
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/fidelity_fx/manifest.json"))
	check(renderer.configure(owner,manifest,{"fog_placements":[Transform3D.IDENTITY]}).ok,"actual assets")
	var weather:=Weather.new();weather.configure({"epoch":10,"model_scale":10.0})
	var packet:Dictionary=weather.advance(1.0,{},{});var retained:=var_to_bytes(packet)
	renderer.apply_snapshot({"environment":packet},camera)
	var sea_priority:int=ocean.material_override.render_priority
	var cloud_correct:=true;var shadow_unchanged:=true;var fog_unchanged:=true
	for group:Array in renderer._clouds:
		for record:Dictionary in group:cloud_correct=cloud_correct and record.material.render_priority>sea_priority
	for instance:Dictionary in renderer._weather:
		for record:Dictionary in instance.meshes:
			if record.bakedShadow:shadow_unchanged=shadow_unchanged and record.material.render_priority==0
			else:cloud_correct=cloud_correct and record.material.render_priority>sea_priority
	for instance:Dictionary in renderer._fog:
		for record:Dictionary in instance.meshes:fog_unchanged=fog_unchanged and record.material.render_priority==0
	check(cloud_correct,"sky and moving world clouds compose after depth-writing sea")
	check(shadow_unchanged and fog_unchanged,"baked receiver shadows and ground fog retain separate pass policy")
	var origin:Vector3=renderer._weather[0].meshes[0].node.global_position
	camera.position+=Vector3(50,30,10);camera.look_at(Vector3.ZERO)
	renderer.apply_snapshot({"environment":packet},camera)
	check(renderer._weather[0].meshes[0].node.global_position==origin,"world cloud translation does not follow camera")
	check(var_to_bytes(packet)==retained,"camera-only refresh leaves native center and clock untouched")
	var moved:Dictionary=weather.advance(2.0,{},{})
	renderer.apply_snapshot({"environment":moved},camera)
	check(moved.worldClouds[0].worldPosition!=packet.worldClouds[0].worldPosition,"accepted weather moves real world cloud")
	renderer.configure(owner,manifest,{})
	renderer.apply_snapshot({"environment":moved},camera)
	check(renderer._weather[0].meshes.filter(func(r):return not r.bakedShadow).all(func(r):return r.material.render_priority>sea_priority),"rebuild retains compositing policy")
	renderer.dispose();owner.free()
	print("CLOUD_OCEAN_ORDER_TESTS assertions=",assertions," failures=",failures);quit(1 if failures else 0)
