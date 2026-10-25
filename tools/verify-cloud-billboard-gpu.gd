extends "res://tools/verify-architecture-lab-gpu.gd"
## Optional registered architecture workload; fixed accepted-time GPU pairs.
const CLOUD_STEP:=1.0/32.0
const CLOUD_FRAMES:=96
const AudioCleanup=preload("res://tests/fixtures/audio_cleanup.gd")
var _demo:Node3D
var _viewport:SubViewport
var _reflection:SubViewport
var _frame_pairs:Array=[]
var _settle_frames:=0
var _submission_contract:=false

func _value(value:Variant)->Variant:
	if value is Texture2D:return {"textureRid":value.get_rid().get_id(),"width":value.get_width(),"height":value.get_height()}
	if value is RID:return {"rid":value.get_id()}
	if value is Object:return {"objectId":value.get_instance_id(),"class":value.get_class()}
	if value is Dictionary:
		var out:Dictionary={}
		for key:Variant in value:out[key]=_value(value[key])
		return out
	if value is Array:
		var out:Array=[]
		for item:Variant in value:out.append(_value(item))
		return out
	return value

func _material(material:Material)->Dictionary:
	if material==null:return {}
	var out:Dictionary={"rid":material.get_rid().get_id(),"class":material.get_class(),"properties":{}}
	for property:Dictionary in material.get_property_list():
		if int(property.usage)&PROPERTY_USAGE_STORAGE:out.properties[property.name]=_value(material.get(property.name))
	if material is ShaderMaterial:
		out.shaderRid=material.shader.get_rid().get_id();out.uniforms={}
		for uniform:Dictionary in material.shader.get_shader_uniform_list():out.uniforms[uniform.name]=_value(material.get_shader_parameter(uniform.name))
	return out

func _submission()->PackedByteArray:
	var meshes:Array=[]
	for node:MeshInstance3D in _demo.get("_world").find_children("*","MeshInstance3D",true,false):
		if not node.is_visible_in_tree() or node.mesh==null:continue
		var materials:Array=[];var morphs:Array=[]
		for index in node.mesh.get_surface_count():materials.append(_material(node.get_active_material(index)))
		for index in node.mesh.get_blend_shape_count():morphs.append(node.get_blend_shape_value(index))
		meshes.append({"node":str(_demo.get_path_to(node)),"instanceRid":node.get_instance().get_id(),"meshRid":node.mesh.get_rid().get_id(),"transform":node.global_transform,"layers":node.layers,"castShadow":node.cast_shadow,"customAabb":node.custom_aabb,"meshAabb":node.mesh.get_aabb(),"materials":materials,"overlay":_material(node.material_overlay),"blendShapes":morphs})
	var camera:Camera3D=_demo.get("_camera")
	var mirror:Camera3D=_demo.get("_ocean").get_reflection_camera()
	var environment:Environment=_demo.get("_world").find_children("*","WorldEnvironment",true,false)[0].environment
	var sky:Dictionary={"id":environment.sky.get_instance_id(),"processMode":environment.sky.process_mode,"material":_material(environment.sky.sky_material)} if environment.sky!=null else {}
	return var_to_bytes({"meshes":meshes,"camera":{"transform":camera.get_camera_transform(),"projection":camera.get_camera_projection(),"cullMask":camera.cull_mask},"reflection":{"transform":mirror.get_camera_transform(),"projection":mirror.get_camera_projection(),"cullMask":mirror.cull_mask},"environment":{"id":environment.get_instance_id(),"background":environment.background_mode,"ambientColor":environment.ambient_light_color,"ambientEnergy":environment.ambient_light_energy,"sky":sky}})

func _hashes()->Dictionary:
	var result:=super._hashes()
	for path:String in ["tools/verify-cloud-billboard-gpu.gd","game/research/demos/architecture_cloud_pair.gd","game/research/demos/architecture_billboard_candidate.gd","game/research/fixtures/cloud_billboard_baseline.gd","modules/scene_engine/fidelity_fx/cloud_render_compiler.gd","modules/scene_engine/fidelity_fx/cloud_transform_kernel.gd","modules/scene_engine/fidelity_fx/cloud_native.gd","modules/scene_engine/fidelity_fx/atmosphere.gd","modules/scene_engine/fidelity_fx/atmosphere.gdshader","modules/environment_engine/weather_state.gd","assets/models/hero_fuchuan_v3_r6/fuchuan-lod0.glb","assets/data/fidelity_fx/manifest.json"]:result[path]=FileAccess.get_sha256("res://"+path)
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/fidelity_fx/manifest.json"))
	result["game/research/demos/architecture_compiler_adapter.gd"]=FileAccess.get_sha256("res://game/research/demos/architecture_compiler_adapter.gd")
	for entry:Dictionary in manifest.atmosphere.assets:result[entry.data_path]=FileAccess.get_sha256(entry.data_path)
	return result

func _pass(label:String)->Dictionary:
	await _frames(2);await RenderingServer.frame_post_draw
	var main_image:Image=_viewport.get_texture().get_image()
	var reflection_image:Image=_reflection.get_texture().get_image()
	var settled:=0;var reads:Array=[]
	if _settle_frames>0:
		var prior_main:=main_image.get_data();var prior_reflection:=reflection_image.get_data()
		for attempt in 48:
			await process_frame;await RenderingServer.frame_post_draw
			main_image=_viewport.get_texture().get_image();reflection_image=_reflection.get_texture().get_image()
			var current_main:=main_image.get_data();var current_reflection:=reflection_image.get_data()
			var same:bool=current_main==prior_main and current_reflection==prior_reflection
			settled=settled+1 if same else 0
			reads.append({"read":attempt+1,"sameAsPrior":same,"consecutiveStable":settled})
			prior_main=current_main;prior_reflection=current_reflection
			if settled>=_settle_frames:break
		check(settled>=_settle_frames,"main/reflection buffers reach declared consecutive stability "+label)
	check(not main_image.is_empty() and not reflection_image.is_empty(),"main/reflection GPU buffers exist "+label)
	var main_path:=output+"/"+label+"-main.png"
	var reflection_path:=output+"/"+label+"-reflection.png"
	check(main_image.save_png(main_path)==OK and reflection_image.save_png(reflection_path)==OK,"raw main/reflection PNG written "+label)
	var submission:=_submission() if _submission_contract else PackedByteArray()
	var submission_path:=output+"/"+label+"-submission.bin"
	if _submission_contract:
		var file:=FileAccess.open(submission_path,FileAccess.WRITE);file.store_buffer(submission);file.close()
	return {"main":main_image.get_data(),"reflection":reflection_image.get_data(),"submission":submission,"proof":{"main":{"path":main_path,"sha256":FileAccess.get_sha256(main_path),"size":[main_image.get_width(),main_image.get_height()]},"reflection":{"path":reflection_path,"sha256":FileAccess.get_sha256(reflection_path),"size":[reflection_image.get_width(),reflection_image.get_height()]},"submission":{"path":submission_path,"sha256":FileAccess.get_sha256(submission_path) if _submission_contract else "","bytes":submission.size()},"stabilization":{"requiredConsecutive":_settle_frames,"finalConsecutive":settled,"readbacks":reads}}}

func _run()->void:
	_started_utc=Time.get_datetime_string_from_system(true)
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		elif arg.begins_with("--settle-frames="):_settle_frames=int(arg.trim_prefix("--settle-frames="))
		elif arg=="--submission-contract":_submission_contract=true
	check(_settle_frames in [0,8],"declared stabilization mode is original two-frame or eight consecutive equal buffers")
	check(DisplayServer.get_name()!="headless","actual GPU renderer required")
	check(not output.is_empty() and output.begins_with("res://") and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output)),"fresh explicit directory required")
	if not failures.is_empty():await _finish();return
	DirAccess.make_dir_recursive_absolute(output);_created_output=true
	source_hashes=_hashes();persisted_before=_persisted()
	root.size=Vector2i(1600,1000);root.content_scale_size=root.size;root.unresizable=true;root.unfocusable=true;root.gui_disable_input=true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	create_timer(240).timeout.connect(func():printerr("CLOUD_BILLBOARD_GPU watchdog expired");quit(1))
	_main=Main.instantiate();root.add_child(_main);await _frames(4)
	var button:Button=_main.menu.find_child("laboratory",true,false)
	check(button!=null and button.is_visible_in_tree() and not button.disabled,"ordinary homepage laboratory button available")
	if button==null:await _finish();return
	await _capture("00-home")
	button.pressed.emit()
	for frame in 120:
		await process_frame
		if is_instance_valid(_main.current_scene):break
	_lab=_main.current_scene
	check(is_instance_valid(_lab) and _lab.startup_receipt.get("ok",false),"existing lab reached through public route")
	if not is_instance_valid(_lab):await _finish();return
	_lab.set_process(false)
	check(_lab.select_topic(TOPIC),"same registered architecture topic selected")
	check(_lab.start_demo({"kind":"fuchuan","depth":4.0,"clouds":true,"billboard_variant":"candidate","paused":false,"camera_mode":"side"}).get("ok",false),"optional paired cloud workload configured")
	_demo=_lab._demo;_viewport=_lab.find_child("ExperimentViewport",true,false)
	if not is_instance_valid(_demo):await _finish();return
	_reflection=_demo.get("_ocean").get_reflection_viewport()
	check(is_instance_valid(_reflection),"production planar reflection remains active")
	if not is_instance_valid(_reflection):await _finish();return
	var initial:Dictionary=_demo.inspection_snapshot()
	check(initial.clouds.ready and initial.clouds.exact and initial.clouds.baselineHash==initial.clouds.candidateHash,"initial complete cloud states exact")
	await _capture("01-cloud-workload")
	for frame in CLOUD_FRAMES:
		if frame==CLOUD_FRAMES/2:_lab._change_parameter("camera_mode","high")
		_demo.advance(CLOUD_STEP)
		var accepted:Dictionary=_demo.inspection_snapshot()
		check(accepted.clouds.compilerPaths.baseline=="res://game/research/fixtures/cloud_billboard_baseline.gd" and accepted.clouds.compilerPaths.candidate=="res://game/research/demos/architecture_billboard_candidate.gd","actual frozen/candidate delegate identities read back at frame%d"%frame)
		var physical:=_physical(accepted)
		check(accepted.baseline==accepted.candidate and accepted.clouds.exact and accepted.clouds.baselineHash==accepted.clouds.candidateHash,"paired numerical/source output exact at frame%d"%frame)
		_lab._change_parameter("billboard_variant","baseline")
		var baseline:Dictionary=await _pass("frame-%04d-baseline"%frame)
		var hold:Dictionary=await _pass("frame-%04d-hold"%frame)
		_lab._change_parameter("billboard_variant","candidate")
		var candidate:Dictionary=await _pass("frame-%04d-candidate"%frame)
		var main_hold:bool=baseline.main==hold.main
		var reflection_hold:bool=baseline.reflection==hold.reflection
		var main_exact:bool=baseline.main==candidate.main
		var reflection_exact:bool=baseline.reflection==candidate.reflection
		if _submission_contract:
			check(baseline.submission==hold.submission and baseline.submission==candidate.submission,"same visible GPU resources, transforms, uniforms, AABBs, cameras and sky submission bytes exact frame%d"%frame)
		else:
			check(main_hold and reflection_hold,"baseline pure redraw main/reflection byte-exact frame%d"%frame)
			check(main_exact and reflection_exact,"candidate main/reflection byte-exact frame%d"%frame)
		check(_physical(_demo.inspection_snapshot())==physical,"GPU waits and path switches spend no accepted state at frame%d"%frame)
		_frame_pairs.append({"frame":frame,"acceptedSnapshot":accepted.baseline,"acceptedTime":accepted.time,"renderTime":accepted.render_time,"clouds":accepted.clouds,"cameraTransform":accepted.camera_transform,"cameraProjection":accepted.camera_projection,"baseline":baseline.proof,"hold":hold.proof,"candidate":candidate.proof,"submissionExact":baseline.submission==hold.submission and baseline.submission==candidate.submission if _submission_contract else null,"mainHoldExact":main_hold,"reflectionHoldExact":reflection_hold,"mainExact":main_exact,"reflectionExact":reflection_exact})
		if frame%32==0:print("CLOUD_BILLBOARD_GPU_PROGRESS frames=",frame+1," failures=",failures.size())
	_demo.set_paused(true)
	var paused:Dictionary=_demo.inspection_snapshot();var held:=_physical(paused)
	_demo.advance(1.0);_demo.orbit_camera(.23,.07);_demo.zoom_camera(-.1)
	check(_physical(_demo.inspection_snapshot())==held and _demo.inspection_snapshot().clouds.exact,"paused camera repaint preserves accepted state and paired cloud output")
	await _capture("02-paused-camera")
	var observer:Dictionary=_demo.inspection_snapshot().camera_controls
	_demo.reset_experiment()
	var reset:Dictionary=_demo.inspection_snapshot()
	check(reset.time==0.0 and reset.tick==0 and reset.camera_controls==observer and reset.clouds.exact,"same conditions reset restores origin and preserves observer")
	await _capture("03-reset")
	comparisons.append({"initial":initial,"paused":paused,"reset":reset})
	var demo_id:=_demo.get_instance_id();_lab._show_paper();_demo=null
	check(not is_instance_id_valid(demo_id),"host releases paired cloud/ship/ocean demo")
	_lab.main_menu_requested.emit();await _frames(4);_lab=null
	check(_main.current_scene==null and _main.menu.is_visible_in_tree(),"public laboratory return path releases experiment")
	check(_persisted()==persisted_before,"settings and saves unchanged")
	check(_hashes()==source_hashes,"source/assets unchanged during capture")
	check(_frame_pairs.size()==CLOUD_FRAMES,"complete fixed-step continuous sequence retained")
	await _finish()

func _finish()->void:
	if is_instance_valid(_main):
		var playbacks:Array[WeakRef]=AudioCleanup.stop_players(_main);_main.free();_main=null
		check(await AudioCleanup.wait_for_release(self,playbacks),"task-owned audio resources released")
	if _created_output:
		var report:Dictionary={"schemaVersion":1,"recordType":"gpu-capture","valid":failures.is_empty(),"topic":TOPIC,"startedAtUtc":_started_utc,"finishedAtUtc":Time.get_datetime_string_from_system(true),"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"sources":source_hashes,"persistedBefore":persisted_before,"persistedAfter":_persisted(),"controls":{"encounterSeed":1661,"skyCrtSeed":1,"acceptedStep":CLOUD_STEP,"continuousFrames":CLOUD_FRAMES,"sourceSeconds":CLOUD_FRAMES*CLOUD_STEP,"rootViewport":[1600,1000],"stabilization":{"requiredConsecutiveEqualMainAndReflection":_settle_frames,"maximumReadbacks":48,"acceptedTimeAdvancesWhileWaiting":false},"camera":"side first48 frames, high next48; follows same accepted ship","quality":"isolated demo balanced; same production ocean and reflection","actors":"one visible production ship, two physics authorities, two atmosphere owners with exactly one visible"},"assertions":assertions,"failures":failures,"captures":captures,"framePairs":_frame_pairs,"lifecycle":comparisons,"scope":"Actual ordinary menu -> existing laboratory -> optional paired cloud workload. 96 consecutive accepted1/32 steps; each main/reflection candidate compared with frozen baseline plus same-state redraw control. Raw GPU PNGs and complete accepted snapshots retained. Diagnostic comparison overhead excludes performance claims; no full-game/crew/combat FPS certification."}
		report.acceptanceMethod="same visible GPU carrier/resources: complete observed submission bytes exact, complete source states exact, continuous actual GPU main/reflection capture; final image equality reported separately, not claimed" if _submission_contract else "strict complete image bytes exact"
		var file:=FileAccess.open(output+"/GPU_VERIFY.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("CLOUD_BILLBOARD_GPU frames=",_frame_pairs.size()," assertions=",assertions," failures=",failures.size())
	quit(1 if not failures.is_empty() else 0)
