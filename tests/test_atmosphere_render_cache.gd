extends SceneTree
const Atmosphere=preload("res://modules/scene_engine/fidelity_fx/atmosphere.gd")
const Native=preload("res://modules/scene_engine/fidelity_fx/cloud_native.gd")
const COMPILED_PATH="res://modules/scene_engine/fidelity_fx/cloud_render_compiler.gd"
class ObservedAtmosphere extends Atmosphere:
	var delivered:Array=[]
	func _update_group(records:Array,meshes:Array,placement:Transform3D,scale_adaptation:float)->void:
		delivered.append(meshes)
		super._update_group(records,meshes,placement,scale_adaptation)
var assertions:=0
var failures:=0
func check(value:bool,reason:String)->void:
	assertions+=1
	if not value:failures+=1;printerr("FAIL atmosphere render cache: ",reason)
func _initialize()->void:_run.call_deferred()
func _run()->void:
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/fidelity_fx/manifest.json"))
	var host:=Node3D.new();root.add_child(host)
	var camera:=Camera3D.new();host.add_child(camera);camera.position=Vector3(33,27,-39);camera.look_at(Vector3(0,3,0))
	var atmosphere:=ObservedAtmosphere.new()
	check(atmosphere.configure(host,manifest,{"cloud_sky_radius":2600.0,"cloud_bounds_layer":true,"fog_placements":[Transform3D(Basis.IDENTITY,Vector3(0,4,0))],"fog_opacity":.035}).ok,"actual source atmosphere configures")
	atmosphere.apply_snapshot({"time":0.0},camera)
	var first:Array=atmosphere.delivered.duplicate()
	check(first.size()==31,"actual renderer delivers all 30 cloud groups and one 20-mesh fog group")
	var token:=RefCounted.new()
	for group:Array in first:group[0]["_test_render_cache_probe"]=token
	atmosphere.delivered.clear()
	atmosphere.apply_snapshot({"time":0.0},camera,Vector3(1,0,2))
	for i in first.size():
		check(atmosphere.delivered[i][0].get("_test_render_cache_probe")==token,"same-time source state is reused rather than regenerated: group "+str(i))
	check(atmosphere.get("_container").get_meta("snapshot_focus")==Vector3(1,0,2),"cached pause still observes latest focus")
	var cloud_node:Node3D=atmosphere.get("_clouds")[0][0].node
	var original_position:=cloud_node.global_position
	camera.position+=Vector3(5,2,-3)
	atmosphere.delivered.clear();atmosphere.apply_snapshot({"time":0.0},camera)
	check(cloud_node.global_position.distance_to(original_position+Vector3(5,0,-3))<.001,"camera translation follows sky without moving the navigation floor")
	for i in first.size():check(atmosphere.delivered[i][0].get("_test_render_cache_probe")==token,"translation reuses native pose while placement updates: "+str(i))
	camera.look_at(Vector3(0,10,20))
	atmosphere.delivered.clear();atmosphere.apply_snapshot({"time":0.0},camera)
	for i in 30:check(atmosphere.delivered[i][0].get("_test_render_cache_probe")!=token,"camera basis change recalculates native cloud/bounds: "+str(i))
	check(atmosphere.delivered[30][0].get("_test_render_cache_probe")==token,"view-independent fog remains cached while the camera turns")
	_check_live_oracle(atmosphere,camera)
	atmosphere.apply_snapshot({"time":.2},camera);_check_live_oracle(atmosphere,camera)
	atmosphere.apply_snapshot({"time":33.4},camera);_check_live_oracle(atmosphere,camera)
	atmosphere.set_reduced_motion(true)
	var held_time:float=atmosphere.get("_cloud_time")
	atmosphere.apply_snapshot({"time":40.0},camera)
	check(atmosphere.get("_cloud_time")==held_time,"reduced motion preserves animation clock")
	camera.look_at(Vector3(-30,2,15));atmosphere.apply_snapshot({"time":40.0},camera);_check_live_oracle(atmosphere,camera)
	atmosphere.set_reduced_motion(false);atmosphere.apply_snapshot({"time":.2},camera);_check_live_oracle(atmosphere,camera)
	atmosphere.reset_timeline();atmosphere.apply_snapshot({"time":0.0},camera);_check_live_oracle(atmosphere,camera)
	var time_before:float=atmosphere.get("_time")
	var pose_before:Transform3D=cloud_node.global_transform
	atmosphere.delivered.clear()
	atmosphere.apply_snapshot({"time":NAN},camera)
	check(atmosphere.delivered.is_empty() and atmosphere.get("_time")==time_before and cloud_node.global_transform==pose_before,"invalid time does not rebuild or poison live cached pose")
	if ResourceLoader.exists(COMPILED_PATH):_check_compiled_oracle(manifest)
	else:check(false,"compiled dynamic renderer exists independently of the full source oracle")
	atmosphere.dispose();host.free()
	print("ATMOSPHERE_RENDER_CACHE_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
func _check_live_oracle(atmosphere:RefCounted,camera:Camera3D)->void:
	var assets:Dictionary=atmosphere.get("_assets")
	var ring:Dictionary=atmosphere.get("_ring")
	var actual:Array=atmosphere.delivered
	var native_camera:Dictionary=Atmosphere._camera_basis(camera)
	var lows:Array=[]
	var expected:Array=[]
	for clone:Dictionary in ring.nodes:
		var outer:Dictionary={"rotation":clone.rotation,"translation":Native.transform_vector(clone.rotation,[0,1,0]),"scale":1.0}
		var meshes:Array=Native.original_meshes(assets[clone.prototype],0.0,outer,false,native_camera)
		expected.append(meshes)
		var low:=INF
		for mesh:Dictionary in meshes:
			for point:Array in mesh.vertices:low=minf(low,float(point[2])*float(atmosphere.get("_sky_radius")))
		lows.append(low)
	var minimum:float=lows.min();var maximum:float=lows.max()
	var records:Array=atmosphere.get("_clouds")
	for i in ring.nodes.size():
		var low:float=lows[i]
		var origin:Vector3=atmosphere.get("_sky_origin")
		origin.y=float(atmosphere.get("_sky_floor"))+(low-minimum)/maxf(.001,maximum-minimum)*float(atmosphere.get("_sky_variation"))-low
		for j in expected[i].size():
			var mesh:Dictionary=expected[i][j]
			var state:Dictionary=records[i][j]
			var world:Dictionary=mesh.world
			var basis:Basis=Atmosphere._rotation(world.rotation).scaled(Vector3.ONE*float(world.scale)*float(atmosphere.get("_sky_radius"))/Atmosphere.SOURCE_METRES)
			var position:Vector3=Atmosphere._native_to_godot(world.translation)*float(atmosphere.get("_sky_radius"))
			var target:=Transform3D(Basis.IDENTITY,origin)*Transform3D(basis,position)
			check(state.node.global_transform.is_equal_approx(target),"live cloud TRS and original vertex-derived navigation floor agree")
			check(state.material.get_shader_parameter("source_billboard_enabled")==not mesh.get("billboard",{}).is_empty(),"live cloud retains per-view shader billboard")
			check(state.node.visible==(float(mesh.alpha)>0),"live visibility agrees with original source alpha")
func _check_compiled_oracle(manifest:Dictionary)->void:
	var renderer:RefCounted=load(COMPILED_PATH).new()
	var camera_cases:Array=[{}, {"direction":[0,1,0],"up":[0,0,1],"right":[1,0,0]}, {"direction":[0,0,-1],"up":[0,1,0],"right":[1,0,0]}]
	for entry:Dictionary in manifest.atmosphere.assets:
		var asset:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(entry.data_path))
		var compiled:Dictionary=renderer.compile_asset(asset)
		var animate:bool=entry.file=="fx_groundfog01.nif"
		for time:float in [0.0,.1,12.0,33.333335876464844,33.5,66.8,.1,0.0]:
			for camera:Dictionary in camera_cases:
				var outer:Dictionary={"rotation":Native.multiply_matrix(Native.rotation_x(.17),Native.rotation_z(.55)),"translation":[.1,.2,.3],"scale":1.15}
				var original:Array=Native.original_meshes(asset,time,outer,animate,camera)
				var states:Array=renderer.render_states(compiled,time,outer,animate,camera,true)
				check(states.size()==original.size(),"compiled graph preserves source leaf order/count")
				for i in original.size():
					for field:String in ["asset","block","texture","world","billboard","alpha","color","uvMatrix","alphaFlags","threshold","clampMode","filterMode","localVertices","sourceUV","triangles","vertices"]:
						check(states[i].get(field)==original[i].get(field),"compiled original field exact: "+str(entry.file)+"/"+field)
				var light:Array=renderer.render_states(compiled,time,outer,animate,camera,false)
				for i in light.size():
					check(not light[i].has("vertices") and not light[i].has("uvs"),"light path never generates unused geometry")
					for field:String in ["world","billboard","alpha","color","uvMatrix"]:check(light[i].get(field)==original[i].get(field),"geometry-free states retain exact original animation")
