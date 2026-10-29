extends "res://tools/profile-hull-dynamics-world.gd"
## Existing hero-fuchuan topic, actual formal fixture -> isolated GPU stage.
## No product edits, authority advance, performance or complete-world claim.
const HeroExperiment=preload("res://game/research/demos/hero_fuchuan_experiment.gd")
const AudioCleanup=preload("res://tests/fixtures/audio_cleanup.gd")
const FILES=["res://tools/research/compare-hero-formal-light.gd","res://game/research/demos/hero_fuchuan_experiment.gd","res://game/research/fixtures/hero_rig_shadow_probe.gd","res://game/research/fixtures/hero_palette_provider.gd","res://modules/scene_engine/assets/hero_ship_provider.gd","res://game/presentation/world/naval_world_view.gd","res://modules/scene_engine/world/world_view.gd","res://game/presentation/ships/ship_damage.gd","res://game/presentation/world/target_rigid_shadow_caster.gd","res://modules/scene_engine/fidelity_fx/source_shadow_renderer.gd","res://modules/scene_engine/fidelity_fx/source_shadow_compositor.gd","res://modules/scene_engine/fidelity_fx/source_shadow_rd.gd","res://assets/models/hero_fuchuan_v3_r6/fuchuan-lod0.glb"]
const CAMERA_KEYS=["projection","fov","size","frustum_offset","near","far","keep_aspect","h_offset","v_offset","cull_mask"]
var rows:Array=[]
var file_hashes:Dictionary={}
var persisted_before:Dictionary={}
var started:String
var formal:Dictionary={}
var demo:Node3D
var stage:SubViewport
var aa_study:=false
var upper_study:=false
var palette_study:=false
var world_study:=false
var rig_study:=false
var filter_study:=false
var proxy_study:=false
var base_shadow_quality:=2
var requested_shadow_quality:=2
var base_shadow_blur:=1.0
var base_normal_bias:=2.0
var model_variant:="art_r6"

func source_hashes()->Dictionary:
	var out:Dictionary={}
	for path:String in FILES:out[path]=FileAccess.get_sha256(path)
	for lod in 3:
		var path:="res://assets/models/hero_fuchuan_v3_%s/fuchuan-lod%d.glb"%[model_variant.trim_prefix("art_"),lod]
		out[path]=FileAccess.get_sha256(path)
	return out

func persisted()->Dictionary:
	var out:Dictionary={}
	for path:String in ["user://settings.json","user://saves/mingqi-v2.json","user://saves/legacy-v1.json"]:out[path]=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
	return out

func save_binary(name:String,value:Variant)->void:
	var bytes:=var_to_bytes(value)
	var file:=FileAccess.open(output.path_join(name),FileAccess.WRITE)
	check(file!=null,"fixture writable "+name)
	if file==null:return
	file.store_buffer(bytes);file.close()
	check(FileAccess.get_file_as_bytes(output.path_join(name))==bytes,"fixture exact readback "+name)

func settle()->void:
	for frame in 4:await process_frame
	await RenderingServer.frame_post_draw

func teak_materials(actor:Node3D)->Array:
	var out:Array=[];var seen:Dictionary={}
	var damage:RefCounted=actor.get("_damage")
	for entry:Dictionary in damage.get("_materials"):
		if entry.original is StandardMaterial3D and entry.original.resource_name=="teak":
			out.append({"material":entry.material,"shader":true,"color":entry.material.get_shader_parameter("original_color")})
			seen[entry.material.get_instance_id()]=true
	for model:Node3D in actor.get("_models"):
		for mesh:MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
			if mesh.mesh==null:continue
			for index in mesh.mesh.get_surface_count():
				var material:Material=mesh.get_active_material(index)
				if material is StandardMaterial3D and material.resource_name=="teak" and not seen.has(material.get_instance_id()):
					out.append({"material":material,"shader":false,"color":material.albedo_color})
					seen[material.get_instance_id()]=true
	return out

func set_teak(entries:Array,gain:Vector3)->void:
	for entry:Dictionary in entries:
		var color:Color=entry.color
		if gain!=Vector3.ONE:
			var linear:=color.srgb_to_linear()
			linear.r*=gain.x;linear.g*=gain.y;linear.b*=gain.z
			color=linear.linear_to_srgb();color.a=entry.color.a
		if entry.shader:entry.material.set_shader_parameter("original_color",color)
		else:entry.material.albedo_color=color

func set_aa(factor:String)->void:
	# A is the actual runtime policy (currently 4x MSAA). Explicit standalone
	# alternatives must not accidentally inherit it and combine techniques.
	stage.msaa_3d=Viewport.MSAA_DISABLED if factor in ["E-none","F-fxaa"] else int(formal.viewportAA.msaa3D)
	stage.screen_space_aa=Viewport.SCREEN_SPACE_AA_FXAA if factor=="F-fxaa" else Viewport.SCREEN_SPACE_AA_DISABLED if factor=="E-none" else int(formal.viewportAA.screenSpaceAA)
	stage.use_taa=false if factor in ["E-none","F-fxaa"] else bool(formal.viewportAA.taa)
	stage.scaling_3d_mode=int(formal.viewportAA.scaling3DMode)
	stage.scaling_3d_scale=float(formal.viewportAA.scaling3DScale)
	check((factor!="E-none" or (stage.msaa_3d==Viewport.MSAA_DISABLED and stage.screen_space_aa==Viewport.SCREEN_SPACE_AA_DISABLED and not stage.use_taa)) and (factor!="F-fxaa" or (stage.msaa_3d==Viewport.MSAA_DISABLED and stage.screen_space_aa==Viewport.SCREEN_SPACE_AA_FXAA and not stage.use_taa)),"actual standalone AA policy readback "+factor)

func set_filter_factor(factor:String,light:DirectionalLight3D)->Dictionary:
	requested_shadow_quality=3 if factor=="soft_medium" else 4 if factor=="soft_high" else base_shadow_quality
	RenderingServer.directional_soft_shadow_filter_set_quality(requested_shadow_quality)
	light.shadow_blur=0.0 if factor=="blur_zero" else base_shadow_blur
	light.shadow_normal_bias=0.0 if factor=="normal_bias_zero" else base_normal_bias
	check(light.shadow_enabled and light.shadow_blur==(0.0 if factor=="blur_zero" else base_shadow_blur) and light.shadow_normal_bias==(0.0 if factor=="normal_bias_zero" else base_normal_bias),"actual retained shadow map and light filter properties "+factor)
	return {"qualityRequested":requested_shadow_quality,"qualityStartupPolicy":base_shadow_quality,"qualityReadback":"RenderingServer setter has no runtime getter; requested enum only","shadowBlur":light.shadow_blur,"normalBias":light.shadow_normal_bias,"bias":light.shadow_bias,"maxDistance":light.directional_shadow_max_distance,"split1":light.directional_shadow_split_1,"split2":light.directional_shadow_split_2,"split3":light.directional_shadow_split_3,"shadowMode":light.directional_shadow_mode,"angularDistance":light.light_angular_distance}

func capture(viewport:Viewport,label:String,metadata:Dictionary)->void:
	await settle()
	var image:Image=viewport.get_texture().get_image()
	check(image!=null and image.get_width()==1600 and image.get_height()==900,"actual 1600x900 GPU buffer "+label)
	if image==null:return
	var path:=output.path_join(label+".png")
	check(image.save_png(path)==OK,"raw PNG saved "+label)
	metadata=metadata.duplicate(true)
	metadata.viewportAA={"msaa3D":viewport.msaa_3d,"screenSpaceAA":viewport.screen_space_aa,"taa":viewport.use_taa,"scaling3DScale":viewport.scaling_3d_scale,"scaling3DMode":viewport.scaling_3d_mode}
	rows.append({"image":path,"sha256":FileAccess.get_sha256(path),"inputs":metadata})

func clear_main()->void:
	if not is_instance_valid(main):return
	var playbacks:=AudioCleanup.stop_players(main)
	main.free();main=null;game=null
	await process_frame
	check(await AudioCleanup.wait_for_release(self,playbacks),"actual audio ownership released")

func run()->void:
	output="";started=Time.get_datetime_string_from_system(true)
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		elif arg=="--aa-study":aa_study=true
		elif arg=="--upper-study":upper_study=true
		elif arg=="--palette-study":palette_study=true
		elif arg=="--world-study":world_study=true
		elif arg=="--rig-study":rig_study=true
		elif arg=="--filter-study":filter_study=true
		elif arg=="--proxy-study":proxy_study=true
		elif arg.begins_with("--model="):model_variant=arg.trim_prefix("--model=")
	if not check(int(aa_study)+int(upper_study)+int(palette_study)+int(world_study)+int(rig_study)+int(filter_study)+int(proxy_study)<=1 and model_variant in ["art_r6","art_r7a","art_r7b","art_r7c","art_r8b","art_r9","art_r9b","art_r11","art_r11b","art_r12","art_r13","art_r14b"],"independent valid study mode/model required"):quit(1);return
	if not check(not output.is_empty() and output.begins_with("res://") and not DirAccess.dir_exists_absolute(output),"fresh explicit res output required"):quit(1);return
	if not check(DisplayServer.get_name()!="headless","real GPU required"):quit(1);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	file_hashes=source_hashes();persisted_before=persisted()
	create_timer(240).timeout.connect(func():printerr("HERO_FORMAL_LIGHT watchdog expired");quit(1))
	root.borderless=true;root.size=Vector2i(1600,900);root.content_scale_size=Vector2i(1600,900)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT;root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_IGNORE
	root.unresizable=true;root.unfocusable=true;root.gui_disable_input=true
	var career:=MemorySlot.new();var legacy:=MemorySlot.new();slots=[career,legacy]
	var isolated_settings:=Settings.new("user://verification/hero-light-no-write-%d.json"%OS.get_process_id())
	main=Main.new();main.router=Router.new({"mingqi_storage":career,"legacy_storage":legacy,"settings_storage":isolated_settings});root.add_child(main)
	for frame in 5:await process_frame
	seed(1661);main.menu.find_child("sail",true,false).pressed.emit()
	for frame in 400:
		await process_frame
		if is_instance_valid(main.current_scene) and main.current_scene.get("startup_receipt").get("ok",false):break
	if not check(is_instance_valid(main.current_scene) and main.current_scene.get("startup_receipt").get("ok",false),"ordinary public sail initialized"):await finish();return
	game=main.current_scene;freeze_callbacks(main)
	var sea:Node3D=game.sea
	var native:Dictionary=sea.get("_snapshot").duplicate(true)
	var authority:Dictionary=game.runtime.snapshot().duplicate(true)
	var player:Dictionary={}
	for ship:Dictionary in native.ships:
		if str(ship.id)==str(native.playerId):player=ship.duplicate(true);break
	if not check(not player.is_empty() and player.kind=="fuchuan","actual main actor is fuchuan"):await finish();return
	player.time=native.time
	var settings:Dictionary=isolated_settings.snapshot()
	check(not settings.sound and not settings.music and settings.quality=="balanced","default balanced and muted preserved")
	var environment:Environment=sea.get("_environment").duplicate(true)
	var light:DirectionalLight3D=sea.get("_sun").duplicate()
	var camera:Camera3D=sea.camera
	var camera_values:Dictionary={"transform":camera.global_transform}
	for key:String in CAMERA_KEYS:camera_values[key]=camera.get(key)
	formal={"encounterSeed":1661,"displaySnapshot":native,"authoritativeSnapshot":authority,"player":player,"wind":native.get("wind",{}).duplicate(true),"camera":camera_values,"target":sea.get("_camera_target"),"settings":settings,"lightingTarget":sea.world.get("_source_lighting").duplicate(true),"actualLight":{"transform":light.transform,"color":light.light_color,"energy":light.light_energy,"shadowEnabled":light.shadow_enabled},"actualAmbient":{"color":environment.ambient_light_color,"energy":environment.ambient_light_energy},"sourceShadowStatus":sea.source_shadow_status()}
	formal.viewportAA={"msaa3D":root.msaa_3d,"screenSpaceAA":root.screen_space_aa,"taa":root.use_taa,"scaling3DScale":root.scaling_3d_scale,"scaling3DMode":root.scaling_3d_mode}
	save_binary("formal-fixture.bin",formal)
	check(ResourceSaver.save(environment,output.path_join("formal-environment.tres"))==OK,"actual formal Environment saved")
	var packed:=PackedScene.new();check(packed.pack(light)==OK and ResourceSaver.save(packed,output.path_join("formal-sun.tscn"))==OK,"actual formal sun saved")
	var frozen:=var_to_bytes(authority)
	await capture(root,"00-formal-baseline",{"scope":"ordinary sail unchanged","formal":formal})
	check(var_to_bytes(game.runtime.snapshot())==frozen and var_to_bytes(sea.get("_snapshot"))==var_to_bytes(native),"GPU wait preserves complete live authority and presented snapshot")
	if world_study:
		var view:Node3D=sea.ships[str(native.playerId)]
		var crew:Node3D=sea.sailors[str(native.playerId)]
		var view_id:=view.get_instance_id();var crew_id:=crew.get_instance_id()
		var actor_count:int=sea.ships.size();var visible_crew:=0
		for actor:Node3D in sea.sailors.values():visible_crew+=actor.get_visible_count()
		var path:="res://assets/models/hero_fuchuan_v3_%s/fuchuan-lod0.glb"%model_variant.trim_prefix("art_")
		file_hashes[path]=FileAccess.get_sha256(path)
		var provider:RefCounted=load("res://game/research/fixtures/hero_palette_provider.gd").new("art_r6",true,model_variant.trim_prefix("art_")) if model_variant!="art_r6" else load("res://modules/scene_engine/assets/hero_ship_provider.gd").new("art_r6",true)
		check(view.configure(player.kind,sea.library,provider),"controlled display candidate bound to actual player ShipView")
		view.apply_snapshot(player,formal.wind,0.0)
		view.set_lod_distance(camera.position.distance_to(view.position))
		check(crew.set_ship_model(view.get_model()),"actual crew rebinds unchanged candidate deck")
		crew.apply_snapshot(player,formal.wind,0.0)
		sea._apply_source_shadows(native)
		var next_crew:=0
		for actor:Node3D in sea.sailors.values():next_crew+=actor.get_visible_count()
		check(view.get_model().get_meta("source_path","")==path,"full-world actual candidate resource readback")
		check(view_id==view.get_instance_id() and crew_id==crew.get_instance_id() and sea.ships.size()==actor_count and visible_crew==next_crew,"same full-world actors and visible crew retained")
		await capture(root,"01-world-"+model_variant,{"scope":"controlled actual whole-world render audition; player display model only, no authority advance; not native play","modelSource":path,"modelSHA256":FileAccess.get_sha256(path),"sourceTime":native.time,"camera":camera.global_transform,"projection":camera.get_camera_projection(),"settings":settings,"shipCount":actor_count,"visibleCrew":next_crew,"shadowStatus":sea.source_shadow_status()})
		check(var_to_bytes(game.runtime.snapshot())==frozen and var_to_bytes(sea.get("_snapshot"))==var_to_bytes(native),"whole-world audition preserves complete authority/display packet")
		var final_hashes:=source_hashes();final_hashes[path]=FileAccess.get_sha256(path)
		check(file_hashes==final_hashes and persisted_before==persisted(),"whole-world audition sources and personal storage unchanged")
		for slot:RefCounted in slots:check(slot.writes==0,"whole-world audition writes no checkpoints")
		light.free()
		await finish();return
	await clear_main()
	# Reuse the registered hero-fuchuan experiment in a separate World3D. Its
	# synthetic seed1650/time0 remain shell metadata, never the formal authority.
	stage=SubViewport.new();stage.name="FormalLightStudy";stage.size=Vector2i(1600,900);stage.own_world_3d=true;stage.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(stage)
	demo=HeroExperiment.new();stage.add_child(demo)
	check(demo.configure({"model":model_variant,"animated":false,"paused":true,"shadows":"authored"}).ok,"existing hero experiment configured")
	await settle() # Complete its one-shot native-map/stencil handoff first.
	var world:Node3D=demo.get("_world")
	var env_node:WorldEnvironment=world.find_children("*","WorldEnvironment",true,false)[0]
	env_node.environment=environment
	var old_light:DirectionalLight3D=demo.get("_sun");old_light.free();world.add_child(light);demo.set("_sun",light)
	var stage_camera:Camera3D=demo.get("_camera")
	for key:String in CAMERA_KEYS:stage_camera.set(key,camera_values[key])
	stage_camera.global_transform=camera_values.transform;stage_camera.environment=environment
	var actor:Node3D=demo.get("_ship")
	actor.apply_snapshot(player,formal.wind,0.0)
	for mesh:MeshInstance3D in world.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh is PlaneMesh:mesh.position=Vector3(player.visual.position.x,player.visual.position.y-2.25,player.visual.position.z)
	demo.refresh_shadow_projection()
	await settle()
	var model:Node3D=actor.get_model()
	var actual_source:String=model.get_meta("source_path","")
	check(actual_source=="res://assets/models/hero_fuchuan_v3_%s/fuchuan-lod0.glb"%model_variant.trim_prefix("art_"),"actual selected model source readback")
	file_hashes[actual_source]=FileAccess.get_sha256(actual_source)
	var actor_transform:=actor.global_transform
	var model_transform:=model.transform
	var shell_before:Dictionary=demo.inspection_snapshot()
	var base_ambient:float=environment.ambient_light_energy
	var base_sun:float=light.light_energy
	base_shadow_quality=int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality",2))
	base_shadow_blur=light.shadow_blur;base_normal_bias=light.shadow_normal_bias
	var base_camera:Transform3D=stage_camera.global_transform
	var teak:=teak_materials(actor)
	check(not teak.is_empty(),"actual authored teak material roles found for D")
	var factors:Array=["A-source","E-none","F-fxaa"] if aa_study else ["A-source","B-ambient070","C-sun120","D-teak-linear"]
	if upper_study:factors=["A-source","G-ambient100","H-teak-upper"]
	if palette_study:factors=["A-source"]
	if rig_study:
		factors=["baseline","native_off","stencil_off","rig_cast_off","sail_cast_off"]
		check(demo.set_parameter("rig_probe","baseline").ok,"rig diagnostic captures post-handoff baseline")
		check(light.shadow_enabled,"native map enabled at rig diagnostic baseline")
	if filter_study:
		factors=["baseline","soft_medium","soft_high","blur_zero","normal_bias_zero"]
		check(demo.set_parameter("rig_probe","baseline").ok,"filter study keeps complete original shadow routes")
	if proxy_study:
		factors=["baseline","deck_visible","hull_visible","deck_down4mm","hull_down35mm","single_sample"]
		check(demo.set_parameter("rig_probe","baseline").ok,"proxy study captures post-handoff original inputs")
	for angle:String in ["formal","reverse"]:
		stage_camera.global_transform=base_camera
		if angle=="reverse":
			var target:Vector3=formal.target
			stage_camera.global_position=target+(base_camera.origin-target).rotated(Vector3.UP,PI)
			stage_camera.look_at(target)
		demo.refresh_shadow_projection()
		for factor:String in factors:
			var filter_receipt:Dictionary={}
			if filter_study:filter_receipt=set_filter_factor(factor,light)
			if rig_study or proxy_study:
				check(demo.set_parameter("rig_probe","baseline" if factor=="single_sample" else factor).ok,"rig factor accepted "+factor)
			environment.ambient_light_energy=1.00 if factor=="G-ambient100" else .70 if factor=="B-ambient070" else base_ambient
			light.light_energy=base_sun*1.20 if factor=="C-sun120" else base_sun
			var teak_gain:=Vector3(1.80,1.65,1.50) if factor=="H-teak-upper" else Vector3(1.20,1.15,1.10) if factor=="D-teak-linear" else Vector3.ONE
			set_teak(teak,teak_gain)
			set_aa("E-none" if proxy_study and factor=="single_sample" else factor)
			demo.refresh_shadow_projection()
			await settle()
			var shadow_before:Dictionary=demo.shadow_diagnostics()
			await capture(stage,angle+"-"+factor,{"scope":"isolated hero stage; plain receiver; no crew/ocean/other boats; projection-off factors diagnostic only","fixtureSHA256":FileAccess.get_sha256(output.path_join("formal-fixture.bin")),"factor":factor,"teakLinearGain":[teak_gain.x,teak_gain.y,teak_gain.z],"teakMaterialCount":teak.size(),"camera":stage_camera.global_transform,"projection":stage_camera.get_camera_projection(),"ambientEnergy":environment.ambient_light_energy,"ambientColor":environment.ambient_light_color,"sunEnergy":light.light_energy,"sunColor":light.light_color,"sunTransform":light.transform,"actorTransform":actor.global_transform,"shadowDiagnostics":shadow_before,"shellInspection":demo.inspection_snapshot(),"sourceTime":native.time})
			if rig_study or proxy_study:verify_rig_factor("baseline" if factor=="single_sample" else factor,shadow_before,demo.shadow_diagnostics())
			if filter_study:
				verify_rig_factor("baseline",shadow_before,demo.shadow_diagnostics())
				rows[-1].inputs.nativeShadowFilter=filter_receipt
			check(actor.global_transform==actor_transform and model.transform==model_transform,"fixed actor/model pose "+angle+factor)
			var shell_now:Dictionary=demo.inspection_snapshot()
			if rig_study or proxy_study:shell_now.parameters.rig_probe="baseline"
			check(shell_now==shell_before,"no synthetic shell advance "+angle+factor)
	# Identical 24-angle small camera arc per AA mode, all at source time0.
	if filter_study:
		for factor:String in ["baseline","soft_medium","soft_high"]:
			var filter_receipt:=set_filter_factor(factor,light)
			for frame in 16:
				var target:Vector3=formal.target
				stage_camera.global_transform=base_camera
				stage_camera.global_position=target+(base_camera.origin-target).rotated(Vector3.UP,float(frame)/15.0*.03)
				stage_camera.look_at(target);demo.refresh_shadow_projection()
				await capture(stage,"filter-arc-%s-%03d"%[factor,frame],{"scope":"controlled small camera arc; no authority advance or native sailing/FPS claim","factor":factor,"frame":frame,"nativeShadowFilter":filter_receipt,"camera":stage_camera.global_transform,"shadowDiagnostics":demo.shadow_diagnostics(),"sourceTime":native.time})
				check(demo.inspection_snapshot()==shell_before,"filter arc preserves accepted state "+factor+str(frame))
	if aa_study:
		for factor:String in factors:
			set_aa(factor)
			for frame in 24:
				var target:Vector3=formal.target
				stage_camera.global_transform=base_camera
				stage_camera.global_position=target+(base_camera.origin-target).rotated(Vector3.UP,float(frame)/23.0*.06)
				stage_camera.look_at(target);demo.refresh_shadow_projection()
				await capture(stage,"arc-%s-%03d"%[factor,frame],{"scope":"camera arc only, not sailing or FPS","factor":factor,"frame":frame,"sourceTime":native.time,"camera":stage_camera.global_transform,"shadowDiagnostics":demo.shadow_diagnostics()})
				check(demo.inspection_snapshot()==shell_before,"arc preserves accepted state "+factor+str(frame))
	set_teak(teak,Vector3.ONE)
	if rig_study or proxy_study:check(demo.set_parameter("rig_probe","baseline").ok,"rig diagnostic restores baseline before disposal")
	if filter_study:set_filter_factor("baseline",light)
	var final_hashes:=source_hashes();final_hashes[actual_source]=FileAccess.get_sha256(actual_source)
	check(file_hashes==final_hashes,"all watched sources/model unchanged during run")
	check(persisted_before==persisted(),"personal settings/saves unchanged")
	for slot:RefCounted in slots:check(slot.writes==0,"no checkpoint writes")
	await finish()

func verify_rig_factor(mode:String,before:Dictionary,after:Dictionary)->void:
	var state:Dictionary=after.rigProbe
	check(state.mode==mode and state.nativeEnabled==(mode!="native_off") and state.effectEnabled==(mode!="stencil_off"),"actual two-route factor readback "+mode)
	check(state.geometryMaterialsPoseVisibilityUnchanged,"rig factors preserve every mesh/material/local-pose/visibility "+mode)
	var rigs:=0;var sails:=0
	for mesh:Dictionary in state.meshes:
		var is_rig:bool=mesh.name.begins_with("rigging_");var is_sail:bool=mesh.name.begins_with("sail_")
		rigs+=int(is_rig);sails+=int(is_sail)
		check(mesh.cast==(0 if (mode=="rig_cast_off" and is_rig) or (mode=="sail_cast_off" and is_sail) else mesh.baselineCast),"actual caster factor "+mode+mesh.path)
		var selected:bool=(mode.begins_with("deck_") and mesh.name=="deck") or (mode.begins_with("hull_") and mesh.name=="hull")
		check(mesh.proxyChanged==selected,"only declared stencil proxy changed "+mode+mesh.path)
		if selected:check(mesh.proxyMeshId==(mesh.visibleMeshId if mode.ends_with("visible") else mesh.proxyMeshId) and mesh.proxyMeshId!=mesh.baselineProxyId,"actual proxy replacement resource "+mode+mesh.path)
	check(rigs>0 and sails>0,"both actual caster groups present "+mode)
	check(after.renderer.gpu.get("initialized",false) and str(after.renderer.gpu.get("error","")).is_empty(),"no native fallback while probing "+mode)
	var previous:int=before.renderer.gpu.get("frames",-1);var current:int=after.renderer.gpu.get("frames",-1)
	check(previous>=0 and (current==previous if mode=="stencil_off" else current>previous),"actual compositor callback counter "+mode)
	rows[-1].inputs.shadowDiagnosticsAfter=after

func finish()->void:
	await clear_main()
	if is_instance_valid(demo):demo.dispose();demo.free()
	if is_instance_valid(stage):stage.free()
	if not output.is_empty() and DirAccess.dir_exists_absolute(output):
		var file:=FileAccess.open(output.path_join("LIGHT_STUDY.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify({"schemaVersion":1,"topic":"hero-fuchuan","recordType":"gpu-capture","aaStudy":aa_study,"upperStudy":upper_study,"paletteStudy":palette_study,"worldStudy":world_study,"rigStudy":rig_study,"filterStudy":filter_study,"proxyStudy":proxy_study,"modelVariant":model_variant,"valid":failures.is_empty(),"startedAtUtc":started,"finishedAtUtc":Time.get_datetime_string_from_system(true),"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"sourceHashes":file_hashes,"persistedBefore":persisted_before,"persistedAfter":persisted(),"formalFixture":formal,"captures":rows,"failures":failures,"scope":"Controlled full-world runtime audition, frozen authority; not native play or performance certification." if world_study else "Independent factor study using fresh ordinary-sail fixture. Separate lighting/material, AA or rig ablation mode; factors never combined. Projection-off is diagnostic only; qualitative GPU, no FPS claim."},"\t"));file.close()
	print("HERO_FORMAL_LIGHT_STUDY captures=",rows.size()," failures=",failures.size())
	quit(1 if not failures.is_empty() else 0)
