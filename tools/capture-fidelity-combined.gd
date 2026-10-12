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
	game._command({"type":"resume"})
	var side: String=game.runtime.nearest_side()
	button=game.interface.find_child("fire_"+side,true,false)
	if not check(button!=null and not button.disabled,"actual battle fire control is enabled"): return
	button.pressed.emit()
	check(not game.sea.effects.get("_source_fire").is_empty(),"actual player fire created source muzzle/smoke effect in the formal scene")
	var initial_time: float=game.runtime.snapshot().naval.time
	var ticks:=0
	for target in [9,30,90,180]:
		# Native focus protection also fires during screenshot export. Each
		# scripted batch explicitly uses the normal Resume command, and proves
		# the requested fixed ticks advanced rather than relabeling a paused PNG.
		game._command({"type":"resume"})
		while ticks<target:
			game.sea.observe_projectiles(game.runtime.snapshot().naval)
			game._present(game.runtime.advance(1.0/60.0)); ticks+=1
		check(absf(float(game.runtime.snapshot().naval.time)-initial_time-float(target)/60.0)<0.03,"actual combat clock reached requested capture tick %d"%target)
		await _capture("formal-battle-%03d"%target,game)
	check(game.sea.world.fidelity_diagnostics().geometryMode=="static_natural","battle particles share actual new game world")
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
