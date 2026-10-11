extends SceneTree

const WAVE_PATH := "res://modules/physics_engine/ocean/reference_gerstner_wave_field.gd"
const MODEL_PATH := "res://modules/scene_engine/reference_island_water/ocean_model.gd"
const RENDERER_PATH := "res://modules/scene_engine/reference_island_water/ocean_renderer.gd"
var assertions := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, reason: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		if failures < 15: printerr("FAIL: ",reason)
func near(a: float,b: float,epsilon: float=1.0e-10) -> bool: return absf(a-b)<=epsilon
func _run() -> void:
	for path: String in [WAVE_PATH,MODEL_PATH,RENDERER_PATH]: check(FileAccess.file_exists(path),"direct demo port exists: "+path)
	if failures:
		print("REFERENCE_DEMO_OCEAN_TESTS assertions=",assertions," failures=",failures)
		quit(1); return
	var waves_script: GDScript = load(WAVE_PATH)
	var model: GDScript = load(MODEL_PATH)
	var renderer_script: GDScript = load(RENDERER_PATH)
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference-demo-ocean.json"))
	check(model.has_method("wave_uniforms"),"render-layer model owns source wave uniforms without importing physics")
	if model.has_method("wave_uniforms"):
		var render_uniforms: Array = model.wave_uniforms()
		var previous_uniforms: Array = waves_script.descriptors()
		for wave in 4:
			for axis in 4: check(render_uniforms[wave][axis]==previous_uniforms[wave][axis],"render-owned wave uniforms retain exactly the previous GPU Float32 values")
	for entry: Dictionary in fixture.samples:
		var result: Dictionary = waves_script.wave_at(entry.x,entry.z,entry.time,entry.tide,entry.strength,entry.footprint)
		for axis in 3:
			check(near(result.position[axis],entry.position[axis],1.0e-9),"Gerstner displaced position matches original JS")
			check(near(result.normal[axis],entry.normal[axis]),"Gerstner analytic normal matches original JS")
		var waves: RefCounted = waves_script.new()
		check(waves.configure({"tide":entry.tide,"strength":entry.strength,"footprint":entry.footprint}),"wave state accepted")
		var world: Dictionary = waves.sample(result.position[0],result.position[2],entry.time)
		check(near(world.height,result.position[1],1.0e-9),"world-XZ inverse returns height of horizontally displaced point")
		check(world.residual<=1.0e-9,"world-XZ inverse converges")
		for axis in 3: check(near(world.normal[axis],result.normal[axis],3.0e-7),"world-XZ inverse retains analytic normal")
		check(near(waves.sample_height(result.position[0],result.position[2],entry.time),world.height),"scalar water height shares inverse contract")
	for entry: Dictionary in fixture.visibility: check(near(waves_script.wave_visibility(entry.length,entry.footprint),entry.value),"footprint filter matches original JS")
	var data: Dictionary = model.ocean_arrays(192)
	check(data.positions.size()==int(fixture.mesh.vertices),"direct ocean grid has original 37249 vertices")
	check(data.indices.size()==int(fixture.mesh.indices),"direct ocean grid retains original triangle count")
	for entry: Dictionary in fixture.mesh.samples:
		for axis in 3: check(data.positions[int(entry.index)][axis]==float(entry.position[axis]),"spread grid retains original Float32 positions")
		check(data.footprint[int(entry.index)]==float(entry.footprint),"spread footprint retains original Float32 spacing")
	for index in fixture.mesh.firstIndices.size(): check(data.indices[index]==int(fixture.mesh.firstIndices[index]),"ocean topology retains a,c,b / b,c,d diagonals")
	var field := {"width":2,"height":2,"values":[128,128,128,128],"extent":160.0,"heightScale":.35,"seaIndex":128,"terrainResolution":1}
	var height_image := Image.create(2,2,false,Image.FORMAT_RF)
	height_image.fill(Color(-4.0,0,0))
	field.heightTexture=ImageTexture.create_from_image(height_image)
	var owner := Node3D.new(); root.add_child(owner)
	var camera := Camera3D.new(); owner.add_child(camera)
	camera.set_perspective(45.0,.3,1200.0)
	camera.position=Vector3(-87,116,115); camera.look_at(Vector3.ZERO,Vector3.UP)
	var ocean: Node3D = renderer_script.new(); owner.add_child(ocean)
	var invalid_field := field.duplicate()
	invalid_field.extent=NAN
	check(not ocean.configure(invalid_field,camera),"nonfinite terrain extent rejected before allocating targets")
	invalid_field=field.duplicate(); invalid_field.oceanResolution=0
	check(not ocean.configure(invalid_field,camera),"invalid spread grid resolution rejected before allocating targets")
	check(ocean.configure(field,camera,{"tide":0.0}),"renderer accepts same field/camera/state contract")
	var uniforms: Array = ocean.get_water_material().shader.get_shader_uniform_list()
	check(uniforms.size()>=15,"ported water shader is parsed with all required source parameters")
	ocean.render({"tide":1.25,"strength":1.0,"reflection":true},camera,8.25)
	var diagnostic: Dictionary = ocean.diagnostics()
	check(diagnostic.reflectionMethod=="planar-subviewport","reflection is actual mirror viewport, never SSR")
	check(diagnostic.sharedWorld and diagnostic.offscreenTargets==1,"mirror uses same World3D with one color target")
	check(diagnostic.waterLayerExcluded,"reflection camera excludes its own ocean layer")
	check(diagnostic.acceptedTime==8.25 and diagnostic.tide==1.25,"render uses supplied accepted clock and tide")
	check(near(diagnostic.mirrorEye.y,2.5-camera.global_position.y,1.0e-5),"mirror eye follows exact tide plane")
	check(ocean.get_sky_material()!=null,"source sky shader is available to the scene environment")
	var first_viewport: SubViewport = ocean.get_reflection_viewport()
	var first_camera: Camera3D = ocean.get_reflection_camera()
	for _request in 3: ocean.render({"tide":1.25,"reflection":true},camera,8.25)
	check(first_viewport==ocean.get_reflection_viewport() and first_camera==ocean.get_reflection_camera(),"repeated/paused frames reuse mirror nodes")
	for entry: Dictionary in fixture.reflection:
		ocean.render({"tide":entry.tide,"reflection":true},camera,8.25)
		for axis in 3: check(near(first_camera.global_position[axis],entry.eye[axis],1.0e-5),"actual mirror eye matches source reflectCamera fixture")
		check(first_camera.global_basis.y.y<0.0,"actual mirror up is reflected as in source")
	ocean.render({"tide":1.25,"reflection":true},camera,8.25)
	ocean.render({"tide":NAN,"reflection":true},camera,9.0)
	check(ocean.diagnostics().acceptedTime==8.25 and ocean.diagnostics().tide==1.25,"invalid scalar frame is rejected without corrupting accepted state")
	for point: Vector3 in [Vector3(0,0,0),Vector3(5,2,3),Vector3(-4,8,-7)]:
		var projected: Vector2 = ocean.reflection_uv(point)
		var actual: Vector2 = first_camera.unproject_position(point)/Vector2(first_viewport.size)
		check(projected.distance_to(actual)<1.0e-5,"mirror UV projection matches actual Godot camera including viewport Y")
	ocean.render({"reflection":false},camera,8.25)
	check(first_viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED and not ocean.diagnostics().reflectionEnabled,"reflection toggle disables real viewport draw")
	owner.remove_child(camera)
	ocean.render({"reflection":true},camera,9.0)
	check(not ocean.diagnostics().reflectionEnabled and first_viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"detached camera safely disables reflection")
	owner.add_child(camera)
	ocean.render({"reflection":true},camera,9.0)
	check(ocean.diagnostics().reflectionEnabled,"reattached camera restores actual mirror rendering")
	ocean.dispose()
	check(ocean.diagnostics().offscreenTargets==0,"dispose removes mirror target")
	owner.free()
	print("REFERENCE_DEMO_OCEAN_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
