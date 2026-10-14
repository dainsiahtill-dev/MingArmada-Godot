extends SceneTree
## Run with a real renderer. Fixed independent shore fixture and direct production
## projection candidate; captures are raw, not native user input or game FPS.
const Shore = preload("res://game/research/demos/shore_surf_experiment.gd")
const OceanDemo = preload("res://game/research/demos/ocean_surface_experiment.gd")
const Coverage = preload("res://modules/scene_engine/ocean/projected_grid_coverage.gd")
var output := ""
var failures: Array = []
var captures: Array = []
var shoal_mode := false
var diagnose := false
var bank_palette := false
var reflection_edge := false
func _initialize() -> void: run.call_deferred()
func frames(count: int) -> void:
	for _i in count: await process_frame
func check(ok: bool,why: String) -> void:
	if not ok: failures.append(why);printerr("FAIL: ",why)
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg=="--shoal":shoal_mode=true
		if arg=="--diagnose":diagnose=true
		if arg=="--bank-palette":bank_palette=true
		if arg=="--reflection-edge":reflection_edge=true
	if output.is_empty() or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output)):
		printerr("FAIL: --output must name a new directory");quit(1);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size=Vector2i(1260,449)
	var viewport := SubViewport.new();viewport.size=root.size;viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var demo: Node3D = OceanDemo.new() if shoal_mode else Shore.new();viewport.add_child(demo)
	check(demo.configure({"paused":true,"fixture":"supply_shoal","projection_guard":true,"bank_water_weight":0.0,"bank_palette_weight":0.0} if shoal_mode else {"paused":true}).ok,"existing fixture configures")
	if diagnose:
		demo.set_paused(false)
		for _i in 64:demo.advance(1.0/32.0)
		demo.set_paused(true)
		demo._camera.position=demo._focus+demo._outward*45.0+Vector3.UP*9.0;demo._camera.look_at(demo._focus)
		for factor: String in ["retained","no-refraction","no-reflection","density160","density320"]:
			var resolution := 160 if factor=="density160" else (320 if factor=="density320" else 80)
			demo._ocean.configure(demo._camera,load("res://assets/textures/waternormals.jpg"),resolution,3000.0)
			demo._ocean.set_projection_padding(0.10);demo._ocean.set_projection_guard_enabled(true)
			demo._ocean.set_refraction_enabled(factor!="no-refraction");demo._ocean.set_reflection_enabled(factor!="no-reflection")
			demo._ocean.update_projection()
			await frames(3);await RenderingServer.frame_post_draw
			var name := "low-t064-"+factor+".png"
			check(viewport.get_texture().get_image().save_png(output+"/"+name)==OK,name)
			captures.append({"image":name,"factor":factor,"resolution":resolution,"state":demo.inspection_snapshot()})
		var diagnosis := {"valid":failures.is_empty(),"failures":failures,"captures":captures,"scope":"Single-factor low-view diagnostics. Refraction/reflection removal and increased carrier density are diagnostic-only, not accepted production changes."}
		var diagnosis_file := FileAccess.open(output+"/GPU_VERIFY.json",FileAccess.WRITE);diagnosis_file.store_string(JSON.stringify(diagnosis,"\t"));diagnosis_file.close()
		demo.dispose();viewport.free();await frames(2);print("VOYAGE_VISUAL_GPU captures=",captures.size()," failures=",failures.size());quit(1 if failures.size() else 0);return
	for seconds: float in [0.0,0.5,2.0,8.0]:
		demo.set_paused(false)
		while demo.inspection_snapshot().tick<int(seconds*32):demo.advance(1.0/32.0)
		demo.set_paused(true)
		for mode: String in ["close","wide","low"]:
			demo.set_camera_mode({"close":"camera_near","wide":"camera_mid","low":"camera_horizon"}[mode] if shoal_mode else ("close" if mode=="low" else mode))
			if mode=="low" and not shoal_mode:
				demo._camera.position=demo._focus+demo._outward*45.0+Vector3.UP*9.0;demo._camera.look_at(demo._focus)
			for candidate: bool in [false,true]:
				if shoal_mode:
					demo.set_parameter("bank_water_weight",0.65 if candidate or bank_palette else 0.0)
					if bank_palette: demo.set_parameter("bank_palette_weight",0.65 if candidate else 0.0)
				else:
					demo.set_parameter("projection_guard",candidate or reflection_edge);demo._ocean._projection_initialized=false;demo._ocean.update_projection()
					if reflection_edge:demo.set_parameter("reflection_edge_feather",0.08 if candidate else 0.0)
				await frames(3);await RenderingServer.frame_post_draw
				var label := "%s-t%03d-%s"%[mode,int(seconds*32),"candidate" if candidate else "baseline"]
				var image := viewport.get_texture().get_image()
				check(image.save_png(output+"/"+label+".png")==OK,label)
				captures.append({"image":label+".png","candidate":candidate,"state":demo.inspection_snapshot(),"sha256":FileAccess.get_sha256(output+"/"+label+".png")})
				if reflection_edge and mode=="low" and seconds==2.0 and candidate:
					check(demo._ocean.get_reflection_viewport().get_texture().get_image().save_png(output+"/low-t064-raw-mirror.png")==OK,"raw mirror target")
	var proof := {"valid":failures.is_empty(),"failures":failures,"captures":captures,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"scope":"Existing isolated shore-surf; same-time original projection versus conservative wave-volume footprint. Original shaders, five waves, feather0.6/weight0.55, no ships or game FPS.","sources":{}}
	if shoal_mode:proof.scope="Existing ocean-surface demo with actual supply-shoal grid/material. Same-time bank water weight0/.65; original physics and actual five waves. No fleet or game FPS."
	if bank_palette:proof.scope="Existing actual supply-shoal fixture. Bank scattering fixed0.65; palette weight0/.65 is the only factor. Original physics and actual five waves. No fleet or game FPS."
	if reflection_edge:proof.scope="Existing shore-surf, conservative projection fixed on. Mirror edge feather0/.08 only; raw mirror target saved at low t2. Central island reflection remains real shared-world geometry."
	for path: String in ["modules/scene_engine/ocean/projected_ocean.gd","modules/scene_engine/ocean/projected_grid_coverage.gd","modules/scene_engine/ocean/reference_game_water.gdshader","modules/scene_engine/ocean/water_environment_optics.gdshaderinc","modules/scene_engine/ocean/reference_shore_foam.gdshaderinc","modules/scene_engine/terrain/shoal_field.gd","modules/scene_engine/terrain/terrain_surface.gdshader","game/research/demos/shore_surf_experiment.gd","game/research/demos/ocean_surface_experiment.gd","tools/verify-voyage-visual-gpu.gd"]:proof.sources[path]=FileAccess.get_sha256("res://"+path)
	proof.engine=Engine.get_version_info();proof.viewport=[viewport.size.x,viewport.size.y];proof.quality="balanced"
	var file := FileAccess.open(output+"/GPU_VERIFY.json",FileAccess.WRITE);file.store_string(JSON.stringify(proof,"\t"));file.close()
	demo.dispose();viewport.free();await frames(2)
	print("VOYAGE_VISUAL_GPU captures=",captures.size()," failures=",failures.size());quit(1 if failures.size() else 0)
