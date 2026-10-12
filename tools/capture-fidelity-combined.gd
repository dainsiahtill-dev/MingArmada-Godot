extends "res://tools/capture-fidelity-island.gd"
func _run() -> void:
	output="res://docs/migration/evidence/integrated-world/native-v1"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	if not check(DisplayServer.get_name()!="headless","actual native GPU required"): _finish(); return
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output)):
		check(false,"fresh evidence directory required"); _finish(); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output)); output_owned=true
	root.size=Vector2i(1600,900)
	settings=Settings.new("user://verification/combined-no-write-%d.json"%OS.get_process_id())
	var slot:=MemorySlot.new(); var legacy:=MemorySlot.new()
	main=Main.new(); main.router=Router.new({"mingqi_storage":slot,"legacy_storage":legacy,"settings_storage":settings}); root.add_child(main)
	await process_frame
	await _capture_menu()
	if OS.get_cmdline_user_args().has("--water-optics-probe"):
		await _capture_water_optics_probe(); _finish(); return
	if OS.get_cmdline_user_args().has("--particle-visibility-probe"):
		await _capture_combat(); _finish(); return
	if OS.get_cmdline_user_args().has("--destruction-visibility-probe"):
		await _capture_destruction_visibility_probe(); _finish(); return
	if OS.get_cmdline_user_args().has("--atmosphere-particles"):
		await _capture_atmosphere_particles(slot,legacy); _finish(); return
	if OS.get_cmdline_user_args().has("--ship-material-check"):
		await _capture_ship_material_layers(); _finish(); return
	if OS.get_cmdline_user_args().has("--reference-ships"):
		await _capture_reference_ships(slot, legacy); _finish(); return
	if OS.get_cmdline_user_args().has("--combat-only"):
		await _capture_combat(); _finish(); return
	var button: Button=main.menu.find_child("fidelity-island",true,false)
	if not check(button!=null and not button.disabled,"ordinary combined preview entry"): _finish(); return
	button.pressed.emit()
	if not await _await_scene("fidelity-island"): _finish(); return
	var scene: Control=main.current_scene; scene.paused=true; scene.seconds=12.0
	scene.sea.apply_settings({"quality":"high"})
	if OS.get_cmdline_user_args().has("--shore-artifact-check"):
		await _capture_shore_artifacts(scene); _finish(); return
	if OS.get_cmdline_user_args().has("--shore-depth-check"):
		scene.focus=Vector3(-60,5,390); scene.orbit={"yaw":-0.28,"elevation":0.76,"distance":160.0}
		scene.seconds=24.0; await _capture("shore-depth-baseline",scene)
		var shader:=Shader.new()
		shader.code=FileAccess.get_file_as_string("res://modules/scene_engine/terrain/natural_shore_surf.gdshader").replace("depth_draw_never;","depth_draw_never, depth_test_disabled;")
		var surf_nodes: Array=scene.world.get_node("StaticNaturalWorld").get("_dynamic_shore")
		for surf: Node3D in surf_nodes:
			for mesh: MeshInstance3D in surf.get_children(): (mesh.material_override as ShaderMaterial).shader=shader
		await _capture("shore-depth-disabled",scene)
		var original: Shader=load("res://modules/scene_engine/terrain/natural_shore_surf.gdshader")
		for surf: Node3D in surf_nodes:
			for mesh: MeshInstance3D in surf.get_children(): (mesh.material_override as ShaderMaterial).shader=original
		scene.world.get_ocean().set_reference_surface_state({"foam":false})
		await _capture("shore-source-only",scene)
		for surf: Node3D in surf_nodes: surf.hide()
		scene.world.get_ocean().set_reference_surface_state({"foam":true})
		await _capture("shore-old-only",scene)
		_finish(); return
	await _capture("combined-xiamen",scene)
	scene.focus=Vector3(-470,8,-65); scene.orbit={"yaw":-0.28,"elevation":0.63,"distance":300.0}
	await _capture("combined-forest-close",scene)
	scene.focus=Vector3(-265,0,-90); scene.orbit={"yaw":-0.1,"elevation":0.66,"distance":150.0}
	await _capture("combined-water-near",scene)
	scene.focus=Vector3(-480,2,-170); scene.orbit={"yaw":-0.20,"elevation":0.68,"distance":220.0}
	for time in [12.0,18.0,24.0]:
		scene.seconds=time; await _capture("combined-shore-%d"%int(time),scene)
	if OS.get_cmdline_user_args().has("--isolate-shore"):
		scene.world.get_ocean().set_reference_surface_state({"foam":false,"caustics":false})
		for time in [12.0,18.0]:
			scene.seconds=time; await _capture("source-surf-isolated-%d"%int(time),scene)
		var surfers: Array=scene.world.get_node("StaticNaturalWorld").get("_dynamic_shore")
		for surf: Node3D in surfers: surf.hide()
		await _capture("source-surf-hidden",scene)
		for surf: Node3D in surfers: surf.show()
		scene.world.get_ocean().set_reference_surface_state({"foam":true,"caustics":true})
		if OS.get_cmdline_user_args().has("--shore-only"): _finish(); return
	scene.focus=Vector3(420,5,160); scene.orbit={"yaw":-0.25,"elevation":0.72,"distance":420.0}
	await _capture("combined-kinmen-a",scene)
	scene.focus=Vector3(-60,5,390); scene.orbit={"yaw":-0.28,"elevation":0.76,"distance":270.0}
	await _capture("combined-islets",scene)
	check(scene.world.get_chunk_count()==0 and scene.world.get_distant_chunks().is_empty(),"actual combined scene uses finite native islands, no moving procedural tiles")
	check(scene.world.get_ocean().material_override.get_shader_parameter("wave_count")==5,"combined actual preview retains original five sea waves")
	check(scene.world.fidelity_diagnostics().geometryMode=="static_natural","sole public preview uses actual natural game world")
	main._return_from_scene(scene); await process_frame; await process_frame
	button=main.menu.find_child("mingqi",true,false)
	if not check(button!=null and button.is_visible_in_tree(),"ordinary new career is public"): _finish(); return
	button.pressed.emit()
	if not await _await_scene("mingqi"): _finish(); return
	var game: Node=main.current_scene
	game.runtime.set_pause("player",true); game.process_mode=Node.PROCESS_MODE_DISABLED
	game.interface.close_menu(); game.interface.close_panel()
	await _capture("formal-new-career",game)
	game.sea.apply_settings({"cameraFollow":false,"quality":"high"})
	game.sea.camera.position=Vector3(-450,170,-330); game.sea.camera.look_at(Vector3(-450,8,-60),Vector3.UP)
	await _capture("formal-xiamen-island",game)
	check(game.sea.world.fidelity_diagnostics().geometryMode=="static_natural","ordinary career shares preview natural world")
	check(slot.writes==0 and legacy.writes==0,"GPU inspection never writes user saves")
	main._return_from_scene(game); for frame in 5: await process_frame
	var checkpoint_path:="res://docs/migration/evidence/opening-story/fleet-stop-native-record-and-aftermath/journey-first.json"
	var checkpoint: Variant=JSON.parse_string(FileAccess.get_file_as_string(checkpoint_path))
	if not check(checkpoint is Dictionary and checkpoint.get("failures",1)==0 and not String(checkpoint.get("confirmedCheckpointJson","")).is_empty(),"existing verified Kinmen voyage checkpoint is available"): _finish(); return
	slot.raw=checkpoint.confirmedCheckpointJson; main._refresh_menu()
	button=main.menu.find_child("mingqi-continue",true,false)
	if not check(button!=null and not button.disabled,"ordinary Continue remains usable after composition migration"): _finish(); return
	button.pressed.emit()
	if not await _await_scene("mingqi"): _finish(); return
	game=main.current_scene; game.runtime.set_pause("player",true); game.process_mode=Node.PROCESS_MODE_DISABLED
	game.interface.close_menu(); game.interface.close_panel()
	await _capture("formal-continue-kinmen",game)
	check(game.sea.world.fidelity_diagnostics().geometryMode=="static_natural","continued career shares current world owner")
	check(slot.writes==0 and legacy.writes==0,"restoring genuine checkpoint does not overwrite either save slot")
	main._return_from_scene(game); for frame in 5: await process_frame
	_finish()

func _capture_shore_artifacts(scene: Control) -> void:
	# Keep lens, clock, geometry and sea displacement identical in every A/B.
	# Use real owner APIs so the next frame cannot restore an isolated layer.
	scene.process_mode=Node.PROCESS_MODE_DISABLED
	scene.focus=Vector3(-350,0,-65); scene.orbit={"yaw":1.58,"elevation":0.86,"distance":125.0}
	scene.seconds=18.0
	var ocean: Node=scene.world.get_ocean()
	var surfers: Array=scene.world.get_node("StaticNaturalWorld").get("_dynamic_shore")
	if OS.get_cmdline_user_args().has("--far-water-check"):
		await _capture_far_water(scene)
		return
	if OS.get_cmdline_user_args().has("--shore-fusion-check"):
		if OS.get_cmdline_user_args().has("--shore-fusion-diagnostic"):
			scene.focus=Vector3(-340,0,-80); scene.camera.fov=25.0; scene.seconds=12.0
			await _capture("fusion-diagnostic-baseline",scene)
			for surf: Node3D in surfers: surf.hide()
			await _capture("fusion-diagnostic-primary-only",scene)
			for surf: Node3D in surfers: surf.show()
			ocean.set_reference_surface_state({"foam":false})
			await _capture("fusion-diagnostic-source-only",scene)
			capture_render_hook=func():
				for surf: Node3D in surfers:
					for mesh: MeshInstance3D in surf.get_children(): mesh.material_override.set_shader_parameter("controller_alpha",1.0)
			await _capture("fusion-diagnostic-source-alpha-one",scene)
			capture_render_hook=Callable(); ocean.set_reference_surface_state({"foam":true})
			for surf: Node3D in surfers: surf.hide()
			var material: ShaderMaterial=ocean.material_override
			var original: Shader=material.shader
			var coast:=FileAccess.get_file_as_string("res://modules/scene_engine/ocean/coastal_visuals.gdshaderinc")
			coast=coast.replace("coastal_foam_random(floor(world_xz * 2.25))","coastal_foam_patch(world_xz * 2.25)")
			var smooth_grain:=Shader.new()
			smooth_grain.code=FileAccess.get_file_as_string("res://modules/scene_engine/ocean/reference_game_water.gdshader").replace("#include \"res://modules/scene_engine/ocean/coastal_visuals.gdshaderinc\"",coast)
			capture_render_hook=func(): material.shader=smooth_grain
			await _capture("fusion-diagnostic-smooth-grain",scene)
			capture_render_hook=Callable(); material.shader=original
			return
		# Identical camera and half-second samples show inward movement and
		# erosion through more than one full 4.19-second advancing-wave cycle.
		scene.focus=Vector3(-340,0,-80); scene.camera.fov=25.0
		var dense_motion:=OS.get_cmdline_user_args().has("--shore-fusion-motion")
		for tick in (42 if dense_motion else 13):
			scene.seconds=6.0+float(tick)*(0.1 if dense_motion else 0.5)
			await _capture("fusion-close-%04d"%int(scene.seconds*100.0),scene)
		for time in [18.0,24.0,29.0,30.0,36.0]:
			scene.seconds=time; await _capture("fusion-life-%02d"%int(time),scene)
		scene.camera.fov=55.0; scene.seconds=12.0
		await _capture("fusion-game-distance",scene)
		check(ocean.material_override.get_shader_parameter("coastal_breaker_strength")==0.36,"primary curved fronts strengthened in actual GPU scene")
		check(ocean.material_override.get_shader_parameter("shoreline_residue_strength")==0.38,"contact residue reduced in actual GPU scene")
		return
	if OS.get_cmdline_user_args().has("--shore-final-check"):
		scene.focus=Vector3(-340,0,-80); scene.camera.fov=25.0
		for time in [0.0,6.0,12.0,18.0,24.0,29.0,30.0]:
			scene.seconds=time; await _capture("final-dock-close-%02d"%int(time),scene)
		scene.camera.fov=55.0
		for time in [12.0,24.0]:
			scene.seconds=time; await _capture("final-dock-medium-%02d"%int(time),scene)
		scene.focus=Vector3(-480,0,-170); scene.orbit={"yaw":-0.2,"elevation":0.82,"distance":125.0}
		for time in [6.0,12.0,18.0,24.0]:
			scene.seconds=time; await _capture("final-south-coast-%02d"%int(time),scene)
		scene.focus=Vector3(320,0,120); scene.orbit={"yaw":-1.4,"elevation":0.82,"distance":125.0}; scene.camera.fov=35.0
		for time in [12.0,24.0]:
			scene.seconds=time; await _capture("final-kinmen-%02d"%int(time),scene)
		scene.focus=Vector3(-60,5,390); scene.orbit={"yaw":-0.28,"elevation":0.76,"distance":160.0}; scene.camera.fov=55.0
		for time in [12.0,24.0]:
			scene.seconds=time; await _capture("final-supply-islet-%02d"%int(time),scene)
		scene.focus=Vector3(-415,5,-45); scene.orbit={"yaw":-0.18,"elevation":0.72,"distance":490.0}
		await _capture("final-world-wide",scene)
		check(scene.world.get_ocean().material_override.get_shader_parameter("wave_count")==5,"fixed coast keeps original five sea waves")
		main._return_from_scene(scene); for frame in 5: await process_frame
		var new_game: Button=main.menu.find_child("mingqi",true,false)
		if not check(new_game!=null and not new_game.disabled,"ordinary career control remains usable"): return
		new_game.pressed.emit()
		if not await _await_scene("mingqi"): return
		var game: Node=main.current_scene
		game.runtime.set_pause("player",true); game.process_mode=Node.PROCESS_MODE_DISABLED
		game.interface.close_menu(); game.interface.close_panel()
		game.sea.apply_settings({"cameraFollow":false,"quality":"high"})
		game.sea.set_camera_controller(func(): game.sea.camera.position=Vector3(-268,95,-80); game.sea.camera.look_at(Vector3(-340,0,-80),Vector3.UP))
		game._present(0.0); await _capture("final-formal-career-coast",game)
		check(game.sea.world.fidelity_diagnostics().geometryMode=="static_natural","shore fixes are used by the actual career world")
		main._return_from_scene(game); for frame in 5: await process_frame
		return
	if OS.get_cmdline_user_args().has("--water-ray-check"):
		scene.camera.fov=25.0; scene.focus=Vector3(-340,0,-80); scene.seconds=12.0
		for surf: Node3D in surfers: surf.hide()
		await _capture("rays-old-layers",scene)
		ocean.set_reference_surface_state({"caustics":false})
		await _capture("rays-no-caustics",scene)
		ocean.set_reference_surface_state({"foam":false})
		await _capture("rays-no-foam-no-caustics",scene)
		var material: ShaderMaterial=ocean.material_override
		var original: Shader=material.shader
		var code:=FileAccess.get_file_as_string("res://modules/scene_engine/ocean/reference_game_water.gdshader")
		if OS.get_cmdline_user_args().has("--shore-spec-check"):
			var fragment_normal:=Shader.new(); fragment_normal.code=code.replace("vec3 n=normalize(v_normal+", "vec3 n=normalize(reference_game_normal(v_world.xz,simulation_time)+")
			capture_render_hook=func(): material.shader=fragment_normal
			await _capture("spec-fragment-normal",scene)
			var no_micro:=Shader.new(); no_micro.code=code.replace("col+=reference_original_micro_sparkle(v_world.xz*surface_visual_scale,n,u_time,surface_wind_direction,surface_wind_speed,footprint*surface_visual_scale,length(u_eye.xz-v_world.xz),reflection_lobe);","")
			capture_render_hook=func(): material.shader=no_micro
			await _capture("spec-no-micro-sparkle",scene)
			var no_lobe:=Shader.new(); no_lobe.code=code.replace("col+=u_sun_color*(broad_spec+fine_spec*(.35+glint*.65));","")
			capture_render_hook=func(): material.shader=no_lobe
			await _capture("spec-no-lobes",scene)
			capture_render_hook=Callable(); material.shader=original
			material.set_shader_parameter("surface_ripple_light_strength",0.0)
			await _capture("spec-no-body-ripple-light",scene)
			return
		var no_refraction:=Shader.new(); no_refraction.code=code.replace("if(!u_refraction_enabled)refracted=water_color;","refracted=water_color;")
		capture_render_hook=func(): material.shader=no_refraction
		await _capture("rays-no-refraction",scene)
		var no_spec:=Shader.new(); no_spec.code=code.replace("col+=u_sun_color*(broad_spec+fine_spec*(.35+glint*.65));","").replace("col+=vec3(.085,.11,.10)*flecks*(.55+glint*.45);","").replace("col+=reference_original_micro_sparkle(v_world.xz*surface_visual_scale,n,u_time,surface_wind_direction,surface_wind_speed,footprint*surface_visual_scale,length(u_eye.xz-v_world.xz),reflection_lobe);","")
		capture_render_hook=func(): material.shader=no_spec
		await _capture("rays-no-specular",scene)
		ocean.set_reference_surface_state({"foam":true})
		var edge_only:=Shader.new(); edge_only.code=code.replace("col=mix(col,vec3(.89,.96,.94),max(edge_foam*.67,surf*.92));","col=vec3(edge_foam);").replace("mix(col,source_sky(normalize(v_world-u_eye)),fog)","col")
		capture_render_hook=func(): material.shader=edge_only
		await _capture("rays-edge-foam-map",scene)
		var surf_only:=Shader.new(); surf_only.code=edge_only.code.replace("col=vec3(edge_foam);","col=vec3(surf);")
		capture_render_hook=func(): material.shader=surf_only
		await _capture("rays-analytic-surf-map",scene)
		capture_render_hook=Callable(); material.shader=original
		return
	if OS.get_cmdline_user_args().has("--shore-uv-check"):
		scene.camera.fov=25.0
		scene.focus=Vector3(-340,0,-80)
		scene.seconds=12.0
		await _capture("shore-close-all",scene)
		for surf: Node3D in surfers: surf.hide()
		await _capture("shore-close-source-hidden",scene)
		ocean.set_reference_surface_state({"foam":false,"caustics":false})
		await _capture("shore-close-no-foam-no-caustics",scene)
		for surf: Node3D in surfers: surf.show()
		await _capture("shore-close-source-only",scene)
		if OS.get_cmdline_user_args().has("--shore-mip-check"):
			var source_code:=FileAccess.get_file_as_string("res://modules/scene_engine/terrain/natural_shore_surf.gdshader")
			var coarse:=Shader.new(); coarse.code=source_code.replace("texture(shore_texture,UV)","textureLod(shore_texture,UV,5.0)")
			for surf: Node3D in surfers:
				for mesh: MeshInstance3D in surf.get_children(): (mesh.material_override as ShaderMaterial).shader=coarse
			await _capture("shore-mip5-clamped",scene)
			var coarse_bounded:=Shader.new(); coarse_bounded.code=coarse.code.replace("vec4 color=textureLod(shore_texture,UV,5.0);","if (any(lessThan(UV, vec2(0.0))) || any(greaterThan(UV, vec2(1.0)))) discard;\n\tvec4 color=textureLod(shore_texture,UV,5.0);")
			for surf: Node3D in surfers:
				for mesh: MeshInstance3D in surf.get_children(): (mesh.material_override as ShaderMaterial).shader=coarse_bounded
			await _capture("shore-mip5-uv-bounded",scene)
			return
		var bounded:=Shader.new()
		bounded.code=FileAccess.get_file_as_string("res://modules/scene_engine/terrain/natural_shore_surf.gdshader").replace("vec4 color=texture(shore_texture,UV);","if (any(lessThan(UV, vec2(0.0))) || any(greaterThan(UV, vec2(1.0)))) discard;\n\tvec4 color=texture(shore_texture,UV);")
		for surf: Node3D in surfers:
			for mesh: MeshInstance3D in surf.get_children(): (mesh.material_override as ShaderMaterial).shader=bounded
		await _capture("shore-close-source-uv-bounded",scene)
		for time in [6.0,18.0,24.0]:
			scene.seconds=time; await _capture("shore-close-bounded-%02d"%int(time),scene)
		return
	await _capture("dock-all-layers",scene)
	for surf: Node3D in surfers: surf.hide()
	await _capture("dock-source-surf-hidden",scene)
	ocean.set_reference_surface_state({"foam":false})
	await _capture("dock-all-foam-hidden",scene)
	ocean.set_reference_surface_state({"caustics":false})
	await _capture("dock-no-foam-no-caustics",scene)
	for surf: Node3D in surfers: surf.show()
	await _capture("dock-source-surf-only",scene)
	for surf: Node3D in surfers: surf.hide()
	ocean.set_reference_surface_state({"foam":true})
	await _capture("dock-old-foam-only",scene)
	for surf: Node3D in surfers: surf.show()
	ocean.set_reference_surface_state({"caustics":true})
	for time in [0.0,6.0,12.0,24.0,29.0]:
		scene.seconds=time; await _capture("dock-time-%02d"%int(time),scene)
	scene.focus=Vector3(-480,0,-170); scene.orbit={"yaw":-0.2,"elevation":0.82,"distance":125.0}
	for time in [6.0,12.0,18.0,24.0]:
		scene.seconds=time; await _capture("south-coast-%02d"%int(time),scene)

func _capture_far_water(scene: Control) -> void:
	scene.process_mode=Node.PROCESS_MODE_DISABLED
	scene.focus=Vector3(-470,5,-65); scene.orbit={"yaw":-0.50,"elevation":0.38,"distance":490.0}
	scene.camera.fov=55.0; scene.seconds=12.0
	await _capture("far-water-baseline",scene)
	var material: ShaderMaterial=scene.world.get_ocean().material_override
	var original: Shader=material.shader
	var code:=FileAccess.get_file_as_string("res://modules/scene_engine/ocean/reference_game_water.gdshader")
	if OS.get_cmdline_user_args().has("--far-water-regression-ab"):
		var needle:="vec3 n=normalize(optical_macro_normal+vec3(world_slopes.x,0,world_slopes.y));"
		if not check(code.contains(needle),"old optical normal counterfactual can be isolated"): return
		var unfiltered:=Shader.new(); unfiltered.code=code.replace(needle,"vec3 n=normalize(macro_normal+vec3(world_slopes.x,0,world_slopes.y));")
		var views:=[
			{"name":"far","focus":Vector3(-470,5,-65),"orbit":{"yaw":-0.50,"elevation":0.38,"distance":490.0},"fov":55.0},
			{"name":"near","focus":Vector3(-340,0,-80),"orbit":{"yaw":1.58,"elevation":0.86,"distance":125.0},"fov":25.0},
			{"name":"near-low","focus":Vector3(-270,0,-140),"orbit":{"yaw":1.58,"elevation":0.15,"distance":100.0},"fov":55.0}
		]
		for view: Dictionary in views:
			scene.focus=view.focus; scene.orbit=view.orbit; scene.camera.fov=view.fov; scene.seconds=12.0
			capture_render_hook=Callable(); material.shader=original
			await _capture("regression-%s-fixed"%view.name,scene)
			capture_render_hook=func(): material.shader=unfiltered
			await _capture("regression-%s-unfiltered"%view.name,scene)
		capture_render_hook=Callable(); material.shader=original
		return
	if OS.get_cmdline_user_args().has("--far-water-grazing-diagnostic"):
		var needle:="vec3 n=normalize(optical_macro_normal+vec3(world_slopes.x,0,world_slopes.y));"
		if not check(code.contains(needle),"grazing diagnostic optical expression exists"): return
		for upper: float in [0.40,0.60]:
			var replacement:="vec3 n=normalize(normalize(mix(vec3(0,1,0),optical_macro_normal,smoothstep(0.05,%s,abs(normalize(u_eye-v_world).y))))+vec3(world_slopes.x,0,world_slopes.y));"%str(upper)
			var isolated:=Shader.new(); isolated.code=code.replace(needle,replacement)
			capture_render_hook=func(): material.shader=isolated
			await _capture("far-water-grazing-%02d"%int(round(upper*100.0)),scene)
		capture_render_hook=Callable(); material.shader=original
		return
	if OS.get_cmdline_user_args().has("--far-water-diagnostic"):
		var overrides:={
			"far-water-flat-macro":["vec3 n=normalize(optical_macro_normal+vec3(world_slopes.x,0,world_slopes.y));","vec3 n=normalize(vec3(0,1,0)+vec3(world_slopes.x,0,world_slopes.y));"],
			"far-water-no-texture-normal":["vec2 world_slopes=wind*slopes.x+across*slopes.y;","vec2 world_slopes=vec2(0.0);"],
			"far-water-no-additive-specular":["col+=u_sun_color*(broad_spec+fine_spec*glint);",""],
			"far-water-flat-fresnel":["float f=.02+.98*pow(1.0-max(dot(n,view_dir),0.0),5.0);","float f=.02;"],
			"far-water-flat-body-light":["water_color*=reference_surface_ripple_light(dot(n,light_direction),light_direction.y,surface_ripple_light_strength);",""]
		}
		for label: String in overrides:
			var change: Array=overrides[label]
			if not check(code.contains(change[0]),"single-layer diagnostic replacement exists: "+label): continue
			var isolated:=Shader.new(); isolated.code=code.replace(change[0],change[1])
			capture_render_hook=func(): material.shader=isolated
			await _capture(label,scene)
		capture_render_hook=Callable(); material.shader=original
		return
	for time in [12.1,12.2,18.0,24.0]:
		scene.seconds=time; await _capture("far-water-motion-%04d"%int(round(time*100.0)),scene)
	scene.seconds=12.0; scene.orbit.yaw=1.40; await _capture("far-water-cross-bearing",scene)
	scene.orbit={"yaw":-0.50,"elevation":0.24,"distance":490.0}
	await _capture("far-water-low-angle",scene)
	scene.orbit={"yaw":-0.50,"elevation":0.55,"distance":750.0}
	await _capture("far-water-wide",scene)
	scene.focus=Vector3(-470,5,-65); scene.orbit={"yaw":-0.50,"elevation":0.40,"distance":320.0}
	await _capture("far-water-island-scale",scene)
	scene.focus=Vector3(-340,0,-80); scene.orbit={"yaw":1.58,"elevation":0.86,"distance":125.0}; scene.camera.fov=25.0
	await _capture("far-water-near-regression",scene)
	scene.focus=Vector3(-270,0,-140); scene.orbit={"yaw":1.58,"elevation":0.15,"distance":100.0}; scene.camera.fov=55.0
	await _capture("far-water-near-low-angle",scene)
	check(material.get_shader_parameter("wave_count")==5,"far optical repair preserves original five physical waves")
	check(material.get_shader_parameter("coastal_breaker_strength")==0.36 and material.get_shader_parameter("shoreline_residue_strength")==0.38,"accepted shoreline fusion and residue settings remain intact")

func _capture_ship_material_layers() -> void:
	# Execute the actual production fragment program on the native GPU. Only
	# lighting is disabled to compare layer math against independent source math.
	var viewport := SubViewport.new(); viewport.size = Vector2i(128, 128)
	viewport.own_world_3d = true; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new(); camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.5; camera.position = Vector3(0, 0, 3); viewport.add_child(camera); camera.current = true
	var surface := MeshInstance3D.new(); var quad := QuadMesh.new(); quad.size = Vector2(2, 2); surface.mesh = quad
	viewport.add_child(surface)
	var material := ShaderMaterial.new(); var shader := Shader.new()
	shader.code = FileAccess.get_file_as_string("res://game/presentation/ships/ship_damage.gdshader").replace("render_mode cull_disabled;", "render_mode cull_disabled, unshaded;")
	material.shader = shader; surface.material_override = material
	material.set_shader_parameter("use_original_albedo", true)
	material.set_shader_parameter("use_original_vertex_color", false)
	material.set_shader_parameter("sail_surface", false)
	material.set_shader_parameter("use_source_hull_layers", true)
	material.set_shader_parameter("original_has_damage_uv", true)
	var samples: Array[Color] = []
	for input: Color in [Color(0.7, 0.25, 0.12, 0.4), Color(0.05, 0.75, 0.2, 1), Color(0.1, 0.2, 0.8, 0.25), Color(0.6, 0.06, 0.5, 0.35)]:
		var image := Image.create(2, 2, false, Image.FORMAT_RGBA8); image.fill(input)
		samples.append(image.get_pixel(0, 0))
		material.set_shader_parameter(["original_albedo", "original_player", "original_upgrade", "reference_damage"][samples.size() - 1], ImageTexture.create_from_image(image))
	for row: Array in [["healthy", false, true], ["damaged", true, true], ["missing-source-uv", true, false], ["healthy-alpha-test", false, true]]:
		material.set_shader_parameter("use_reference_damage", row[1]); material.set_shader_parameter("original_has_damage_uv", row[2])
		material.set_shader_parameter("original_alpha_cutoff", 0.6 if row[0] == "healthy-alpha-test" else 0.0)
		for frame in 6: await process_frame
		await RenderingServer.frame_post_draw
		var pixels := viewport.get_texture().get_image(); var actual := pixels.get_pixel(64, 64)
		var damage_alpha: float = samples[3].a if row[1] and row[2] else 0.0
		var one := clampf(damage_alpha + samples[2].a, 0, 1); var two := clampf(one + samples[0].a, 0, 1)
		var expected := (samples[3].srgb_to_linear() * damage_alpha + samples[2].srgb_to_linear() * (one - damage_alpha) + samples[0].srgb_to_linear() * (two - one) + samples[1].srgb_to_linear() * (1.0 - two)).linear_to_srgb()
		var error := Vector3(actual.r - expected.r, actual.g - expected.g, actual.b - expected.b).length()
		check(error < 0.025, "actual source hull layer pixel " + row[0] + ": " + str(error))
		var path: String = output + "/ship-material-" + row[0] + ".png"; pixels.save_png(path)
		var info := {"label": "ship-material-" + row[0], "actual": [actual.r, actual.g, actual.b], "expected": [expected.r, expected.g, expected.b], "error": error, "imageSha256": FileAccess.get_sha256(path), "materialShaderSha256": FileAccess.get_sha256("res://game/presentation/ships/ship_damage.gdshader"), "scope": "Native GPU production fragment with lighting disabled; independent original PSShipHull alpha-priority expectation, not a game frame."}
		var receipt := FileAccess.open(path.get_basename() + ".json", FileAccess.WRITE); receipt.store_string(JSON.stringify(info, "\t")); receipt.close(); captures.append(info)
	# Select through the real ShipDamage binding, not a hand-picked test shader.
	var environment := WorldEnvironment.new(); var lighting := Environment.new()
	lighting.background_mode=Environment.BG_COLOR; lighting.background_color=Color(0.03,0.15,0.6)
	environment.environment=lighting; viewport.add_child(environment)
	var model := Node3D.new(); viewport.add_child(model); surface.reparent(model)
	surface.name="hull"
	var original := StandardMaterial3D.new(); original.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	var transparent_pixels:=Image.create(2,2,false,Image.FORMAT_RGBA8); transparent_pixels.fill(Color(0.7,0.1,0.1,0.0))
	original.albedo_texture=ImageTexture.create_from_image(transparent_pixels); surface.material_override=original
	var helper=load("res://game/presentation/ships/ship_damage.gd").new()
	var models: Array[Node3D]=[model]; helper.configure(models)
	material=surface.material_override as ShaderMaterial
	var selected_shader:=Shader.new()
	selected_shader.code=material.shader.code.replace("render_mode cull_disabled;","render_mode cull_disabled, unshaded;").replace("render_mode cull_disabled, depth_prepass_alpha;","render_mode cull_disabled, depth_prepass_alpha, unshaded;")
	material.shader=selected_shader
	surface.hide(); for frame in 6: await process_frame
	await RenderingServer.frame_post_draw
	var background:=viewport.get_texture().get_image().get_pixel(64,64)
	surface.show()
	var blend_colors: Array[Color]=[]
	for alpha: float in [0.0,0.5,1.0]:
		var pixels:=Image.create(2,2,false,Image.FORMAT_RGBA8); pixels.fill(Color(0.7,0.1,0.1,alpha))
		material.set_shader_parameter("original_albedo",ImageTexture.create_from_image(pixels))
		for frame in 6: await process_frame
		await RenderingServer.frame_post_draw
		var rendered:=viewport.get_texture().get_image(); var actual:=rendered.get_pixel(64,64)
		blend_colors.append(actual)
		var path:=output+"/ship-material-blend-%d.png"%roundi(alpha*100); rendered.save_png(path)
		var info:={"label":"ship-material-blend-%d"%roundi(alpha*100),"actual":[actual.r,actual.g,actual.b],"background":[background.r,background.g,background.b],"sourceAlpha":pixels.get_pixel(0,0).a,"imageSha256":FileAccess.get_sha256(path),"scope":"Native GPU real ShipDamage shader selection for blend-only source texture."}
		var receipt:=FileAccess.open(path.get_basename()+".json",FileAccess.WRITE); receipt.store_string(JSON.stringify(info,"\t")); receipt.close(); captures.append(info)
	check(Vector3(blend_colors[0].r-background.r,blend_colors[0].g-background.g,blend_colors[0].b-background.b).length()<0.002,"zero-alpha original texture preserves exact rendered background")
	var expected_half: Color=(blend_colors[2].srgb_to_linear()*(128.0/255.0)+background.srgb_to_linear()*(127.0/255.0)).linear_to_srgb()
	check(Vector3(blend_colors[1].r-expected_half.r,blend_colors[1].g-expected_half.g,blend_colors[1].b-expected_half.b).length()<0.025,"half-alpha source texture blends rather than becoming an opaque plate")
	helper.dispose()
	viewport.free()

func _capture_reference_ships(slot: RefCounted, legacy: RefCounted) -> void:
	var button: Button = main.menu.find_child("ships", true, false)
	if not check(button != null and not button.disabled, "ordinary ship book is available"): return
	button.pressed.emit()
	if not await _await_scene("ships"): return
	var book: Control = main.current_scene
	book.process_mode = Node.PROCESS_MODE_DISABLED
	for kind: String in ["fuchuan", "fisherman", "merchant", "voc", "patrol", "heavy"]:
		if not check(book.select_ship(kind, 0).ok, "actual ship book selects source " + kind): return
		book.set_angle("quarter"); book.animate_model(0.0)
		await _capture_ship_book("source-ship-" + kind, book)
		if kind != "fuchuan":
			book.set_furl(1.0); await _capture_ship_book("source-ship-furled-" + kind, book)
	book.select_ship("fuchuan", 0); book.set_angle("starboard")
	await _capture_ship_book("source-ship-starboard", book)
	book.set_furl(1.0); await _capture_ship_book("source-ship-furled", book)
	book.set_furl(0.0); book.set_angle("quarter")
	book._damage.apply_snapshot({"hull":100.0,"sail":100.0,"sailAngle":0.0},1.0,true)
	book._damage.apply_snapshot({"hull":100.0,"sail":0.0,"sailAngle":0.0},2.0,true)
	book._damage.apply_snapshot({"hull":100.0,"sail":0.0,"sailAngle":0.0},5.0,true)
	book.set_meta("capture_inspection", {"type":"controlled presentation damage snapshot", "hull":100.0,"sail":0.0,"scope":"Native ship book damage inspection, not a player-triggered combat result."})
	await _capture_ship_book("source-ship-dismast-inspection", book)
	book.remove_meta("capture_inspection"); book.select_ship("fuchuan",0)
	book.set_furl(0.0); book.set_angle("underwater")
	await _capture_ship_book("source-ship-underwater", book)
	main._return_from_scene(book); for frame in 5: await process_frame
	button = main.menu.find_child("mingqi", true, false)
	if not check(button != null and not button.disabled, "ordinary career available with source models"): return
	button.pressed.emit()
	if not await _await_scene("mingqi"): return
	var game: Node = main.current_scene
	game.runtime.set_pause("player", true); game.process_mode = Node.PROCESS_MODE_DISABLED
	game.interface.close_menu(); game.interface.close_panel()
	game.sea.apply_settings({"cameraFollow": false, "quality": "high"})
	var ship: Node3D = game.sea.ships.values()[0]
	var point: Vector3 = ship.global_position
	game.sea.set_camera_controller(func():
		game.sea.camera.position = point + Vector3(32, 26, 40)
		game.sea.camera.look_at(point + Vector3.UP * 5, Vector3.UP))
	game._present(0.0)
	await _capture("source-formal-career-close", game)
	var sailors: Dictionary = {}
	for id: String in game.sea.sailors:
		sailors[id] = game.sea.sailors[id].diagnostics()
	check(not sailors.is_empty(), "actual career source ships have separate deck crew owners")
	var audit := {"ships": {}, "sailors": sailors}
	for id: String in game.sea.ships:
		audit.ships[id] = {"sourceKind": game.sea.ships[id].source_kind(), "damage": game.sea.ships[id].damage_diagnostics()}
	var receipt := FileAccess.open(output + "/source-formal-models.json", FileAccess.WRITE)
	if check(receipt != null, "formal source model audit opens"):
		receipt.store_string(JSON.stringify(audit, "\t")); receipt.close()
	main._return_from_scene(game); for frame in 5: await process_frame
	await _capture_combat()
	check(slot.writes == 0 and legacy.writes == 0, "source model native validation preserved both save slots")

func _capture_ship_book(label: String, book: Control) -> void:
	for frame in 5: await process_frame
	await RenderingServer.frame_post_draw
	var pixels := root.get_texture().get_image()
	var path := output + "/" + label + ".png"
	if not check(pixels != null and not pixels.is_empty() and pixels.save_png(path) == OK, "actual source ship book PNG " + label): return
	var info := {"label": label, "imageSha256": FileAccess.get_sha256(path), "route": "actual main menu / ship book", "gpu": RenderingServer.get_video_adapter_name(), "renderingMethod": RenderingServer.get_current_rendering_method(), "viewport": [pixels.get_width(), pixels.get_height()], "snapshot": book.snapshot(), "cameraPosition": str(book.camera.position), "modelManifestSha256": FileAccess.get_sha256("res://assets/data/fidelity_naval/ships-manifest.json"), "materialShaderSha256": FileAccess.get_sha256("res://game/presentation/ships/ship_damage.gdshader"), "scope": "Actual current native source-model adaptation; no original game rendering fidelity or historical Chinese hull claim."}
	info.damageShaderBodySha256=FileAccess.get_sha256("res://game/presentation/ships/ship_damage_surface.gdshaderinc")
	info.alphaShaderSha256=FileAccess.get_sha256("res://game/presentation/ships/ship_damage_alpha.gdshader")
	if book.has_meta("capture_inspection"): info.inspection=book.get_meta("capture_inspection")
	var receipt := FileAccess.open(path.get_basename() + ".json", FileAccess.WRITE)
	if check(receipt != null, "source ship metadata opens"):
		receipt.store_string(JSON.stringify(info, "\t")); receipt.close(); captures.append(info)

func _capture_water_optics_probe() -> void:
	var button: Button=main.menu.find_child("duel",true,false)
	if not check(button!=null and not button.disabled,"ordinary naval scene for water optics probe"): return
	button.pressed.emit()
	if not await _await_scene("duel"): return
	var game: Node=main.current_scene
	game.process_mode=Node.PROCESS_MODE_DISABLED
	game._command({"type":"resume"})
	game.sea.apply_settings({"quality":"high","cameraFollow":false})
	game.sea.set_camera_controller(func(): game.sea.camera.position=Vector3(35,23,48); game.sea.camera.look_at(Vector3(0,4,3),Vector3.UP))
	game._present(0.0)
	var material: ShaderMaterial=game.sea.world.get_ocean().material_override
	if not check(material!=null,"actual water optical shader material exists"): return
	await _capture("water-probe-baseline",game)
	var optical_cases: Array=[{"name":"normal-flat","key":"u_strength","value":0.0},{"name":"no-scene-reflection","key":"u_use_reflection","value":false},{"name":"no-sun-specular","key":"u_sun_color","value":Vector3.ZERO},{"name":"no-reference-color","key":"has_reference_water_textures","value":false}]
	for optical: Dictionary in optical_cases:
		var original: Variant=material.get_shader_parameter(optical.key)
		capture_render_hook=func(): material.set_shader_parameter(optical.key,optical.value)
		game.set_meta("capture_inspection",{"type":"same-frame optical ablation","uniform":optical.key})
		await _capture("water-probe-"+String(optical.name),game)
		capture_render_hook=Callable(); material.set_shader_parameter(optical.key,original)
	var atmosphere_container: Node3D=game.sea.world.atmosphere.get("_container")
	atmosphere_container.visible=false
	game.set_meta("capture_inspection",{"type":"same-frame optical ablation","owner":"cloud and ground-fog container"})
	await _capture("water-probe-no-clouds",game)
	atmosphere_container.visible=true; game.remove_meta("capture_inspection")

func _capture_atmosphere_particles(slot: RefCounted, legacy: RefCounted) -> void:
	var button: Button=main.menu.find_child("mingqi",true,false)
	if not check(button!=null and not button.disabled,"ordinary career entry for atmosphere inspection"): return
	button.pressed.emit()
	if not await _await_scene("mingqi"): return
	var game: Node=main.current_scene
	game.process_mode=Node.PROCESS_MODE_DISABLED
	game.runtime.set_pause("player",true)
	game.interface.close_menu(); game.interface.close_panel()
	game.sea.apply_settings({"quality":"high"})
	game._present(0.0)
	await _capture("atmosphere-career-captain",game)
	var point: Vector3=game.sea.ships.values()[0].global_position
	game.sea.set_camera_controller(func():
		game.sea.camera.position=point+Vector3(24,12,45)
		game.sea.camera.look_at(point+Vector3.UP*8,Vector3.UP))
	game._present(0.0)
	await _capture("atmosphere-career-sky",game)
	var sky_before: Dictionary=game.sea.world.atmosphere.diagnostics()
	game._present(0.0)
	check(game.sea.world.atmosphere.diagnostics()==sky_before,"paused current scene atmosphere stays at accepted time")
	main._return_from_scene(game); for frame in 5: await process_frame
	await _capture_combat()
	check(slot.writes==0 and legacy.writes==0,"particle capture preserves actual user save slots")

func _capture_combat() -> void:
	var button: Button=main.menu.find_child("duel",true,false)
	if not check(button!=null and not button.disabled,"ordinary single-ship battle entry"): return
	button.pressed.emit()
	if not await _await_scene("duel"): return
	var game: Node=main.current_scene
	game.process_mode=Node.PROCESS_MODE_DISABLED; game._command({"type":"resume"})
	game.sea.apply_settings({"cameraFollow":false,"quality":"high"})
	game.sea.set_camera_controller(func(): game.sea.camera.position=Vector3(65,35,85); game.sea.camera.look_at(Vector3(0,4,12),Vector3.UP))
	game._present(0.0)
	await _capture("formal-battle-ready",game)
	if OS.get_cmdline_user_args().has("--reference-ships") or OS.get_cmdline_user_args().has("--atmosphere-particles") or OS.get_cmdline_user_args().has("--particle-visibility-probe"):
		if OS.get_cmdline_user_args().has("--atmosphere-particles") or OS.get_cmdline_user_args().has("--particle-visibility-probe"):
			# Inspect the firing starboard side, using the established ocean-safe
			# camera height instead of hiding the flash behind the opposite hull.
			game.sea.set_camera_controller(func(): game.sea.camera.position=Vector3(-35,23,48); game.sea.camera.look_at(Vector3(0,6,3),Vector3.UP))
		else:
			game.sea.set_camera_controller(func(): game.sea.camera.position=Vector3(35,23,48); game.sea.camera.look_at(Vector3(0,4,3),Vector3.UP))
		game._present(0.0)
		await _capture("source-formal-battle-close",game)
		if OS.get_cmdline_user_args().has("--atmosphere-particles"):
			var water_material: ShaderMaterial=game.sea.world.get_ocean().material_override
			check(water_material.get_shader_parameter("water_legacy_optics")==false,"new production water optics is the default")
			capture_render_hook=func(): water_material.set_shader_parameter("water_legacy_optics",true)
			game.set_meta("capture_inspection",{"type":"same-frame optical comparison","uniform":"water_legacy_optics","value":true})
			await _capture("water-legacy-optics-same-frame",game)
			capture_render_hook=Callable(); water_material.set_shader_parameter("water_legacy_optics",false); game.remove_meta("capture_inspection")
	game._command({"type":"resume"})
	var side: String=game.runtime.nearest_side()
	button=game.interface.find_child("fire_"+side,true,false)
	if not check(button!=null and not button.disabled,"actual battle fire control is enabled"): return
	var before_fire: Dictionary=game.runtime.snapshot().naval
	var player_id: String=before_fire.playerId
	var ammo_before:=0
	for ship: Dictionary in before_fire.ships:
		if ship.id==player_id: ammo_before=int(ship.ammo.solid)
	var initial_time: float=before_fire.time
	button.pressed.emit()
	# UI commands enter the real fixed-step input queue. Consume that step
	# before any await or Resume, whose focus protection clears queued input.
	game.sea.observe_projectiles(game.runtime.snapshot().naval)
	var consumed: float=game.runtime.advance(1.0/60.0)
	var original_events: Array=game.runtime.simulation.get("_events").duplicate(true)
	var player_shots: Array=original_events.filter(func(event: Dictionary)->bool:return event.get("type")=="fire" and event.get("shipId")==player_id)
	game._present(consumed)
	var ammo_after:=0
	for ship: Dictionary in game.runtime.snapshot().naval.ships:
		if ship.id==player_id: ammo_after=int(ship.ammo.solid)
	check(ammo_after<ammo_before and player_shots.size()==1,"actual UI player fire consumes ammunition and emits its own authoritative shot")
	var player_effects: Array=[]
	for shot: Dictionary in player_shots:
		var source: Variant=game.sea.ships[player_id].source_fire_position(shot)
		for effect: Dictionary in game.sea.effects.get("_source_fire"):
			if String(effect.node.name)!="CannonSource_"+String(shot.id): continue
			var state: Dictionary=effect.node.diagnostics()
			check(source is Vector3 and state.origin.distance_to(source)<0.01,"player shot effect uses the actual original-model muzzle")
			player_effects.append({"eventId":shot.id,"shipId":shot.shipId,"source":state.source,"origin":{"x":state.origin.x,"y":state.origin.y,"z":state.origin.z}})
	check(player_effects.size()==player_shots.size() and not player_effects.is_empty(),"formal scene contains source effects matched to actual player event IDs")
	var fire_receipt:=FileAccess.open(output+"/source-player-fire-contract.json",FileAccess.WRITE)
	if check(fire_receipt!=null,"actual player fire receipt opens"):
		fire_receipt.store_string(JSON.stringify({"input":"actual HUD fire button signal followed by one real simulation tick","side":side,"playerId":player_id,"ammoBefore":ammo_before,"ammoAfter":ammo_after,"events":player_shots,"effects":player_effects},"\t")); fire_receipt.close()
	var ticks:=1
	var targets: Array=[2,4,8,16,30,60,120,180] if OS.get_cmdline_user_args().has("--atmosphere-particles") else [9,30,90,180]
	if OS.get_cmdline_user_args().has("--particle-visibility-probe"): targets=[2,4]
	var effect_frames: Array=[]
	for target in targets:
		# Native focus protection also fires during screenshot export. Each
		# scripted batch explicitly uses the normal Resume command, and proves
		# the requested fixed ticks advanced rather than relabeling a paused PNG.
		game._command({"type":"resume"})
		while ticks<target:
			game.sea.observe_projectiles(game.runtime.snapshot().naval)
			game._present(game.runtime.advance(1.0/60.0)); ticks+=1
		check(absf(float(game.runtime.snapshot().naval.time)-initial_time-float(target)/60.0)<0.03,"actual combat clock reached requested capture tick %d"%target)
		await _capture("formal-battle-%03d"%target,game)
		if OS.get_cmdline_user_args().has("--atmosphere-particles") and target==2:
			capture_render_hook=func():
				for source_effect: Dictionary in game.sea.effects.get("_source_fire"):
					for mesh: MeshInstance3D in source_effect.node.get_children():
						if mesh.get_meta("display_role","")=="game_flash": mesh.visible=false
			game.set_meta("capture_inspection",{"type":"same-frame optical ablation","owner":"game muzzle flash only"})
			await _capture("formal-battle-002-no-game-flash",game)
			capture_render_hook=Callable(); game.remove_meta("capture_inspection")
			for source_effect: Dictionary in game.sea.effects.get("_source_fire"):
				for mesh: MeshInstance3D in source_effect.node.get_children():
					if mesh.get_meta("display_role","")=="game_flash": mesh.visible=true
		if OS.get_cmdline_user_args().has("--particle-visibility-probe") and target==4:
			var visible_flash: Array=[]
			for effect: Dictionary in game.sea.effects.get("_source_fire"):
				for mesh: MeshInstance3D in effect.node.get_children():
					if mesh.get_meta("display_role","")!="game_flash": continue
					var point: Vector3=mesh.global_position
					visible_flash.append({"event":String(effect.node.name),"world":point,"pixel":game.sea.camera.unproject_position(point),"bounds":mesh.get_aabb(),"materialTint":mesh.material_override.get_shader_parameter("display_tint")})
			var receipt:=FileAccess.open(output+"/flash-visibility-probe.json",FileAccess.WRITE)
			if check(receipt!=null,"flash visibility geometry receipt opens"):
				receipt.store_string(JSON.stringify(visible_flash,"\t")); receipt.close()
			game.sea.ships[player_id].visible=false
			await _capture("probe-004-no-player-ship",game)
			game.sea.world.get_ocean().visible=false
			await _capture("probe-004-no-player-ship-or-ocean",game)
			game.sea.world.get_ocean().visible=true; game.sea.ships[player_id].visible=true
			return
		if OS.get_cmdline_user_args().has("--atmosphere-particles"):
			var frame_effects: Array=[]
			for effect: Dictionary in game.sea.effects.get("_source_fire"):
				var state: Dictionary=effect.node.diagnostics()
				frame_effects.append({"eventId":String(effect.node.name).trim_prefix("CannonSource_"),"age":state.get("age"),"origin":state.get("origin"),"source":state.get("source"),"profile":state.get("render_profile"),"particles":state.get("active",state.get("particles",0)),"renderedMeshes":state.get("rendered_meshes"),"renderedTriangles":state.get("rendered_triangles"),"flash":state.get("game_flash")})
			effect_frames.append({"tick":target,"time":game.runtime.snapshot().naval.time,"effects":frame_effects,"sky":game.sea.world.atmosphere.diagnostics()})
		if target == 9 and OS.get_cmdline_user_args().has("--reference-ships"):
			var effects: Dictionary = game.sea.effects.diagnostics()
			var receipt := FileAccess.open(output + "/source-formal-fire.json", FileAccess.WRITE)
			if check(receipt != null, "actual source muzzle effect receipt opens"):
				receipt.store_string(JSON.stringify(effects, "\t")); receipt.close()
	check(game.sea.world.fidelity_diagnostics().geometryMode=="static_natural","battle particles share actual new game world")
	if OS.get_cmdline_user_args().has("--atmosphere-particles"):
		var receipt:=FileAccess.open(output+"/particle-event-frames.json",FileAccess.WRITE)
		if check(receipt!=null,"real particle lifecycle receipt opens"):
			receipt.store_string(JSON.stringify(effect_frames,"\t")); receipt.close()
		var now: float=game.runtime.snapshot().naval.time
		game.set_meta("capture_inspection",{"type":"controlled production effect event","scope":"Visual destruction/splash inspection, not an actual battle outcome."})
		game.sea.effects.apply_events([{"id":"controlled-destruction-inspection","type":"destruction-explosion","time":now-0.06,"position":{"x":0.0,"y":5.0,"z":0.0}}])
		await _capture("controlled-destruction-inspection",game)
		var smoke_receipt:=FileAccess.open(output+"/controlled-destruction-state.json",FileAccess.WRITE)
		if check(smoke_receipt!=null,"controlled destruction state receipt opens"):
			var state: Array=[]
			for puff: Dictionary in game.sea.effects.get("_puffs"):
				state.append({"worldPosition":puff.node.global_position,"pixel":game.sea.camera.unproject_position(puff.node.global_position),"visible":puff.node.is_visible_in_tree(),"size":puff.node.scale,"color":puff.material.albedo_color,"unshaded":puff.material.shading_mode==BaseMaterial3D.SHADING_MODE_UNSHADED})
			smoke_receipt.store_string(JSON.stringify(state,"\t")); smoke_receipt.close()
		for variant in range(1,4):
			var ordinal:=0
			var id: String="controlled-splash-%d-%d"%[variant,ordinal]
			while 1+posmod(absi(id.hash()),3)!=variant:
				ordinal+=1; id="controlled-splash-%d-%d"%[variant,ordinal]
			game.sea.effects.apply_events([{"id":id,"type":"splash","time":now-0.35,"position":{"x":-24.0+(variant-1)*15.0,"y":0.0,"z":-16.0}}])
			var found:=false
			for source: Dictionary in game.sea.effects.diagnostics().water.fidelity_sources:
				if source.source=="cannon_ball_splash_0%d.nif"%variant:
					check(String(source.get("render_error","error")).is_empty(),"whole original splash material stream renders variant %d"%variant)
					check(int(source.rendered_triangles)>0,"original splash has submitted mesh geometry variant %d"%variant); found=true
			check(found,"production water presenter chooses original splash variant %d"%variant)
			await _capture("controlled-splash-%02d-inspection"%variant,game)
		game.remove_meta("capture_inspection")
	main._return_from_scene(game); for frame in 5: await process_frame

func _capture_destruction_visibility_probe() -> void:
	var button: Button=main.menu.find_child("duel",true,false)
	if not check(button!=null and not button.disabled,"ordinary battle entry for destruction visibility inspection"): return
	button.pressed.emit()
	if not await _await_scene("duel"): return
	var game: Node=main.current_scene
	game.process_mode=Node.PROCESS_MODE_DISABLED
	game.sea.apply_settings({"cameraFollow":false,"quality":"high"})
	game.sea.set_camera_controller(func():
		game.sea.camera.position=Vector3(-35,23,48)
		game.sea.camera.look_at(Vector3(-12,6,-5),Vector3.UP))
	game._present(0.0)
	await _capture("destruction-visibility-baseline",game)
	var born: float=game.runtime.snapshot().naval.time
	# The earlier inspection was inside the intact ship and was depth-occluded.
	# Inspect the unchanged production presenter over open water; label this
	# explicitly as a controlled effect, not a simulated ship destruction.
	game.set_meta("capture_inspection",{"type":"controlled production destruction event","position":[-24,6,-16],"scope":"No ship was destroyed by this inspection event."})
	game.sea.effects.apply_events([{"id":"controlled-visible-destruction","type":"destruction-explosion","time":born,"position":{"x":-24.0,"y":6.0,"z":-16.0}}])
	var ticks:=0
	for target in [4,36,120]:
		game._command({"type":"resume"})
		while ticks<target:
			game.sea.observe_projectiles(game.runtime.snapshot().naval)
			game._present(game.runtime.advance(1.0/60.0)); ticks+=1
		check(absf(float(game.runtime.snapshot().naval.time)-born-float(target)/60.0)<0.03,"destruction inspection actual clock %d"%target)
		await _capture("controlled-visible-destruction-%03d"%target,game)
	game.remove_meta("capture_inspection")
	main._return_from_scene(game); for frame in 5: await process_frame

func _capture_menu() -> void:
	for frame in 5: await process_frame
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	var path:=output+"/ordinary-main-menu.png"
	if not check(image!=null and not image.is_empty() and image.save_png(path)==OK,"ordinary consolidated menu PNG"): return
	var info:={"label":"ordinary-main-menu","imageSha256":FileAccess.get_sha256(path),"route":"actual main menu","gpu":RenderingServer.get_video_adapter_name(),"viewport":[image.get_width(),image.get_height()],"dev":main.router.dev,"qa":main.router.qa}
	var file:=FileAccess.open(path.get_basename()+".json",FileAccess.WRITE)
	if check(file!=null,"menu metadata opens"): file.store_string(JSON.stringify(info,"\t")); file.close(); captures.append(info)
