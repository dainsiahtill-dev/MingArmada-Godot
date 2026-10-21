extends "res://tools/profile-hull-dynamics-world.gd"
## Root-exclusive GPU capture. Replaces scripts on the same six shore Nodes;
## never creates duplicate geometry or changes production source/defaults.
const SOURCE="res://modules/scene_engine/terrain/natural_shore_surf.gd"
const BASELINE="res://tests/fixtures/natural_shore_before_visibility.gd"
var capture:=""
var fixed_tick:=30
var checks:=0
var shores:Array=[]
var source_scripts:Array=[]
var candidate_script:GDScript
var baseline_script:GDScript
var ocean:Node3D
var surface:ShaderMaterial
var camera:Camera3D
var packet:Dictionary={}
var cases:Array=[]
var mirror_case:Dictionary={}
var stage:="entry"
var finished:=false
const WATCHDOG_SECONDS:=120.0
const SHORE_ONLY_LAYER:=1<<18 # WATER_LAYER is 1<<19 and is excluded by the real mirror.
var render_scope:="full"
var stability_setup:Dictionary={}
var probes:Array=[]
var source_hashes:Dictionary={}

func check(ok:bool,message:String)->bool:
	checks+=1
	return super.check(ok,message)

func fingerprint(value:Variant)->String:return var_to_bytes(value).hex_encode().sha256_text()

func finish_capture(reason:String)->void:
	if finished:return
	finished=true
	var proof:Dictionary={"status":"production shore culling vs frozen pre-culling source","scope":"Same actual shore Nodes/meshes/materials, fixed accepted packet/tick per pair, actual main/reflection cameras, nonempty original-shader pixel contribution controls, baseline hold, strict raw GPU pixel comparison and visible complete shader parameters/source outputs. No frame-time/FPS performance claim.","renderScope":render_scope,"stabilitySetup":stability_setup,"completed":reason=="complete","finishReason":reason,"lastStage":stage,"watchdogSeconds":WATCHDOG_SECONDS,"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"fixedTick":fixed_tick,"acceptedTime":packet.get("time"),"sourceHashesAtStart":source_hashes,"productionSourceSHA256":source_hashes.get(SOURCE),"baselineSourceSHA256":source_hashes.get(BASELINE),"driverSHA256":source_hashes.get("res://tools/capture-shore-frustum-culling.gd"),"baselineWithViewStubSHA256":baseline_script.source_code.sha256_text() if baseline_script!=null else "","candidateLoadedSHA256":candidate_script.source_code.sha256_text() if candidate_script!=null else "","closeupProbes":probes,"mirrorOnlyWitness":mirror_case,"assertions":checks,"failures":failures,"cases":cases}
	var file:=FileAccess.open(capture.path_join("receipt.json"),FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(proof,"\t"));file.close()
	else:check(false,"capture receipt writable: "+str(FileAccess.get_open_error()))
	print("SHORE_CULLING_GPU_TESTS assertions=",checks," failures=",failures.size()," reason=",reason," stage=",stage," output=",capture.path_join("receipt.json"))
	# Request exit before any cleanup callback can itself fail. SceneTree owns Nodes.
	quit(0 if reason=="complete" and failures.is_empty() else 1)

func arm_watchdog()->void:
	# SceneTreeTimer survives freeze_callbacks and ignores pause/time scale. A runtime
	# script error aborting run() still reaches this fence instead of the 180s wrapper.
	create_timer(WATCHDOG_SECONDS,true,false,true).timeout.connect(func():
		if finished:return
		check(false,"internal GPU capture watchdog expired at "+stage)
		finish_capture("watchdog")
	)

func bind_actual_entry()->bool:
	var interface:Variant=game.get("interface")
	if not check(interface is CanvasLayer,"actual sail interface is CanvasLayer"):return false
	interface.visible=false
	var sea:Variant=game.get("sea")
	if not check(sea is Node3D and sea.has_method("_world_packet"),"actual sea presenter interface"):return false
	var world:Variant=sea.get("world")
	if not check(world is Node3D and world.has_method("get_ocean"),"actual world presenter interface"):return false
	var natural:Variant=world.get("_natural_world")
	if not check(natural is Node3D,"actual natural world owner"):return false
	var owners:Variant=natural.get("_dynamic_shore")
	if not check(owners is Array and owners.size()==6,"same actual six island owners"):return false
	for shore:Variant in owners:
		if not check(shore is Node3D and shore.get_script() is GDScript and shore.has_method("apply_snapshot") and shore.has_method("diagnostics"),"actual shore Node/script interface"):return false
		var materials:Variant=shore.get("_materials")
		if not check(materials is Array and not materials.is_empty(),"actual shore material collection"):return false
		for material:Variant in materials:
			if not check(material is ShaderMaterial and material.shader!=null,"actual shore shader material interface"):return false
	var actual_ocean:Variant=world.get_ocean()
	if not check(actual_ocean is Node3D and actual_ocean.has_method("get_reflection_viewport") and actual_ocean.has_method("get_reflection_camera") and actual_ocean.has_method("set_simulation_time") and actual_ocean.has_method("update_projection"),"actual ocean/reflection interface"):return false
	var actual_surface:Variant=actual_ocean.get("material_override")
	var actual_camera:Variant=sea.get("camera")
	if not check(actual_surface is ShaderMaterial and actual_camera is Camera3D,"actual ocean material and main camera types"):return false
	if not check(actual_ocean.get_reflection_viewport() is SubViewport and actual_ocean.get_reflection_camera() is Camera3D,"actual reflection viewport and camera types"):return false
	var snapshot:Variant=sea.get("_snapshot")
	if not check(snapshot is Dictionary,"actual source snapshot dictionary"):return false
	var actual_packet:Variant=sea._world_packet(snapshot)
	if not check(actual_packet is Dictionary,"actual world packet dictionary"):return false
	var time:Variant=actual_packet.get("time")
	if not check((time is float or time is int) and is_finite(float(time)),"actual accepted packet time is finite"):return false
	shores=owners.duplicate();ocean=actual_ocean;surface=actual_surface;camera=actual_camera;packet=actual_packet.duplicate(true)
	for shore:Node3D in shores:source_scripts.append(shore.get_script())
	return true

func freeze_internal_processing(node:Node)->void:
	# set_process(false) alone does not express the engine internal-processing
	# contract of imported AnimationMixer/Skeleton Nodes. Retain their sampled pose.
	node.process_mode=Node.PROCESS_MODE_DISABLED
	for child:Node in node.get_children():freeze_internal_processing(child)

func viewport_state(viewport:Viewport)->Dictionary:
	return {"taa":viewport.use_taa,"debanding":viewport.use_debanding,"screenSpaceAA":viewport.screen_space_aa,"msaa3D":viewport.msaa_3d,"scaling3DMode":viewport.scaling_3d_mode,"scaling3DScale":viewport.scaling_3d_scale}

func render_state()->Dictionary:
	var transforms:Array=[];var skeletons:Array=[];var animations:Array=[]
	for node:Node in main.find_children("*","",true,false):
		if node is Node3D:transforms.append([str(node.get_path()),node.global_transform,node.visible])
		if node is Skeleton3D:
			var poses:Array=[]
			for bone in node.get_bone_count():poses.append(node.get_bone_pose(bone))
			skeletons.append([str(node.get_path()),poses])
		if node is AnimationPlayer:animations.append([str(node.get_path()),node.current_animation,node.current_animation_position,node.is_playing(),node.callback_mode_process])
	var water:Variant=game.sea.get("_interactive_water")
	var water_state:Dictionary=water.diagnostics() if water!=null else {}
	var field:Dictionary=water_state.get("field",{})
	return {"node3DCount":transforms.size(),"node3DSHA256":fingerprint(transforms),"skeletonCount":skeletons.size(),"skeletonSHA256":fingerprint(skeletons),"animationCount":animations.size(),"animationSHA256":fingerprint(animations),"interactive":{"boundGeneration":water_state.get("bound_generation"),"fieldGeneration":field.get("generation"),"time":field.get("time"),"pending":field.get("pending"),"queued":field.get("queued"),"awaitingAck":field.get("awaiting_ack")},"viewports":{"main":viewport_state(root),"reflection":viewport_state(ocean.get_reflection_viewport())}}

func stabilize_entry()->bool:
	stage="freeze-internal-processing-and-drain-field"
	freeze_internal_processing(main)
	PhysicsServer3D.set_active(false)
	stability_setup={"allNodeProcessModesDisabled":true,"physicsServerActive":false,"visualPoseRetained":true,"aaOverrides":false,"renderScope":render_scope,"boundaries":"full retains original visual instances/materials/compositors/AA. shore-environment hides only Crew/UI. shore-environment-no-foliage additionally hides original forest roots to isolate the GPU05 drift at canopy pixel (303,12..16). Original ground/ocean/depth/lighting/ships/compositors remain in both environment scopes. shore-only isolates shore geometry via layers and removes compositors/UI. Scoped passes do not establish full-world pixel equivalence including the hidden owners."}
	var water:Variant=game.sea.get("_interactive_water")
	if water!=null:
		var drained:=false
		for frame in 240:
			water.poll()
			var status:Dictionary=water.diagnostics();var field:Dictionary=status.get("field",{})
			if not bool(field.get("pending",false)) and not bool(field.get("queued",false)) and not bool(field.get("awaiting_ack",false)):
				stability_setup.interactiveDrained=status;drained=true;break
			await process_frame
			if finished:return false
		if not check(drained,"initial interactive field publications fully drained before GPU pairs"):return false
		game.sea.wakes.set_interactive_coverage(water.covered_actor_ids())
	if render_scope=="shore-only":
		var shore_mesh_ids:Dictionary={}
		for shore:Node3D in shores:
			for mesh:MeshInstance3D in shore.find_children("*","MeshInstance3D",true,false):shore_mesh_ids[mesh.get_instance_id()]=true
		var count:=0
		for node:Node in main.find_children("*","",true,false):
			if node is VisualInstance3D:
				if shore_mesh_ids.has(node.get_instance_id()):node.layers=SHORE_ONLY_LAYER;count+=1
				else:node.layers=node.layers & ~SHORE_ONLY_LAYER
			if node is CanvasLayer:node.visible=false
		camera.cull_mask=SHORE_ONLY_LAYER;camera.compositor=null
		ocean.get_reflection_camera().compositor=null
		stability_setup.isolatedShoreMeshes=count
		if not check(count==1704,"shore-only retains all 1704 original subdivided shore meshes"):return false
	elif render_scope in ["shore-environment","shore-environment-no-foliage"]:
		var hidden_crew:Array=[]
		for crew:Node3D in game.sea.sailors.values():
			hidden_crew.append(str(crew.get_path()));crew.visible=false
		for node:Node in main.find_children("*","CanvasLayer",true,false):node.visible=false
		stability_setup.hiddenCrewRoots=hidden_crew
		stability_setup.retainedEnvironment="Original camera layers, terrain, ocean, vegetation, ships, all source textures/uniforms, lights, opaque depth/background, source compositor and actual planar reflection viewport/camera. Only non-shore Crew and UI are hidden identically in all controls."
		if render_scope=="shore-environment-no-foliage":
			var hidden_forest:Array=[]
			var natural:Node3D=game.sea.world.get("_natural_world")
			for forest:Node3D in natural.get("_trees"):
				hidden_forest.append(str(forest.get_path()));forest.visible=false
			stability_setup.hiddenVegetationRoots=hidden_forest
			stability_setup.retainedEnvironment="Original ground/ocean/depth/background/ship meshes/lights/compositors/camera layers/source shader inputs and actual reflection. Non-shore forest roots plus Crew/UI are hidden identically. GPU05's two nonempty exact cases retain forest; this scope specifically isolates its one-column canopy drift for same-time reentry."
	await settle()
	if finished:return false
	stability_setup.initialRenderState=render_state()
	return true

func swap_script(shore:Node3D,script:Script)->void:
	var values:Dictionary={}
	for property:Dictionary in shore.get_script().get_script_property_list():values[property.name]=shore.get(property.name)
	shore.set_script(script)
	for property:Dictionary in script.get_script_property_list():
		if values.has(property.name):shore.set(property.name,values[property.name])

func baseline_scripts()->void:
	for index in shores.size():
		swap_script(shores[index],baseline_script)
		shores[index].set("_has_applied_time",false)

func candidate_scripts(previous_time:float)->void:
	for shore:Node3D in shores:
		shore.apply_snapshot({"time":previous_time})
		swap_script(shore,candidate_script)

func supply_views()->void:
	var viewport:SubViewport=ocean.get_reflection_viewport()
	var enabled:=is_instance_valid(viewport) and viewport.render_target_update_mode!=SubViewport.UPDATE_DISABLED
	for shore:Node3D in shores:shore.set_view_cameras(camera,ocean.get_reflection_camera(),enabled)

func apply_world(candidate:bool)->void:
	# Set-time/projection synchronizes the actual mirror before view capture.
	# World receives the identical frozen packet afterwards, preserving its own sequence.
	ocean.set_simulation_time(float(packet.time));ocean.update_projection()
	if candidate:supply_views()
	game.sea.world.apply_snapshot(packet,0.0)

func settle()->void:
	for frame in 12:await process_frame
	await RenderingServer.frame_post_draw

func render_info(viewport:Viewport)->Dictionary:
	if not is_instance_valid(viewport):return {}
	var rid:=viewport.get_viewport_rid();var result:Dictionary={}
	for pair:Array in [["drawCalls",RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME],["objects",RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME],["primitives",RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME]]:
		result[pair[0]]=RenderingServer.viewport_get_render_info(rid,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,pair[1])
	return result

func capture_frame(label:String)->Dictionary:
	stage=label+":settle"
	var state_before:=render_state()
	await settle()
	if finished:return {"images":{},"stats":{}}
	stage=label+":readback"
	var state_after:=render_state()
	check(var_to_bytes(state_before)==var_to_bytes(state_after),label+" CPU transforms/bones/animations/field binding and viewport AA remain frozen")
	var result:Dictionary={"images":{},"stats":{"main":render_info(root),"reflection":render_info(ocean.get_reflection_viewport())},"renderStateBefore":state_before,"renderStateAfter":state_after}
	for pair:Array in [["main",root],["reflection",ocean.get_reflection_viewport()]]:
		var viewport:Viewport=pair[1]
		if not check(is_instance_valid(viewport),label+" viewport "+pair[0]):continue
		var texture:ViewportTexture=viewport.get_texture()
		if not check(texture!=null,label+" actual viewport texture "+pair[0]):continue
		var image:Image=texture.get_image()
		if not check(image!=null and not image.is_empty(),label+" actual GPU image "+pair[0]):continue
		var path:=capture.path_join(label+"-"+pair[0]+".png")
		check(image.save_png(path)==OK,"native PNG saved "+path)
		result.images[pair[0]]={"image":image,"path":path,"width":image.get_width(),"height":image.get_height(),"format":image.get_format(),"sha256":image.get_data().hex_encode().sha256_text()}
	return result

func image_diff(left:Dictionary,right:Dictionary)->Dictionary:
	var result:Dictionary={}
	for key:String in left:
		if not right.has(key):result[key]={"error":"missing view"};continue
		var a:Image=left[key].image;var b:Image=right[key].image
		if a.get_size()!=b.get_size() or a.get_format()!=b.get_format():result[key]={"error":"image layout differs"};continue
		var av:=a.get_data();var bv:=b.get_data();var changed:=0;var maximum:=0
		if av==bv:
			result[key]={"changedBytes":0,"totalBytes":av.size(),"maxByteDelta":0,"exact":true};continue
		for index in av.size():
			var delta:=absi(int(av[index])-int(bv[index]))
			if delta>0:changed+=1;maximum=maxi(maximum,delta)
		result[key]={"changedBytes":changed,"totalBytes":av.size(),"maxByteDelta":maximum,"exact":changed==0}
	return result

func strip_images(value:Dictionary)->Dictionary:
	value=value.duplicate(true)
	for key:String in value.images:value.images[key].erase("image")
	return value

func material_snapshot(shore:Node3D)->Array:
	var result:Array=[]
	for material:ShaderMaterial in shore.get("_materials"):
		var values:Dictionary={}
		for uniform:Dictionary in material.shader.get_shader_uniform_list():
			var name:String=uniform.name;values[name]=material.get_shader_parameter(name)
		result.append(values)
	return result

func source_snapshot()->Array:
	var result:Array=[]
	for shore:Node3D in shores:
		var state:Dictionary=shore.diagnostics();state.erase("research")
		result.append({"source":state,"materials":material_snapshot(shore)})
	return result

func compare_sources(expected:Array)->Array:
	var result:Array=[]
	for index in shores.size():
		var shore:Node3D=shores[index];var actual:Dictionary=shore.diagnostics();actual.erase("research")
		var work:Dictionary=shore.presentation_diagnostics()
		check(var_to_bytes(actual)==var_to_bytes(expected[index].source),"full source output exact owner "+str(index))
		var materials_equal:=true
		if work.visible:
			materials_equal=var_to_bytes(material_snapshot(shore))==var_to_bytes(expected[index].materials)
			check(materials_equal,"all actual visible shader parameters exact owner "+str(index))
		result.append({"owner":index,"visible":work.visible,"viewHits":work.viewHits,"sourceBaseline":fingerprint(expected[index].source),"sourceCandidate":fingerprint(actual),"visibleMaterialsEqual":materials_equal,"samples":work.samples,"writes":work.materialWrites})
	return result

func intersects(bounds:AABB,planes:Array)->bool:
	for plane:Plane in planes:
		var outside:=true
		for index in 8:
			if plane.distance_to(bounds.get_endpoint(index))<=0.01:outside=false;break
		if outside:return false
	return true

func mirror_hits(bounds:AABB,eye:Vector3,target_y:float)->Array:
	camera.global_position=eye;camera.look_at(bounds.get_center()+Vector3(0,target_y,0),Vector3.UP)
	ocean.set_simulation_time(float(packet.time));ocean.update_projection()
	var mirror:Variant=ocean.get_reflection_camera()
	if not check(mirror is Camera3D,"actual reflection camera remains valid during witness search"):return [false,false]
	return [intersects(bounds,camera.get_frustum()),intersects(bounds,mirror.get_frustum())]

func find_mirror_only(bounds:AABB)->Dictionary:
	var size:=maxf(bounds.size.length(),100.0);var center:=bounds.get_center()
	for height:float in [20.0,80.0,200.0]:
		var eye:=center+Vector3(0,height,size*2.0)
		var low:float=-size*40.0;var high:=0.0
		if mirror_hits(bounds,eye,low)[0] or not mirror_hits(bounds,eye,high)[0]:continue
		for iteration in 40:
			var middle:float=(low+high)*.5
			if mirror_hits(bounds,eye,middle)[0]:high=middle
			else:low=middle
		for offset:float in [0.0,-.0001,-.001,-.01,-.05]:
			var hits:=mirror_hits(bounds,eye,low+offset)
			if hits==[false,true]:return {"found":true,"hits":hits,"transform":camera.global_transform,"height":height,"targetOffset":low+offset}
	return {"found":false}

func capture_without_shore(label:String)->Dictionary:
	var visibility:Array=[]
	for shore:Node3D in shores:visibility.append(shore.visible);shore.visible=false
	var background:Dictionary=await capture_frame(label)
	for index in shores.size():shores[index].visible=visibility[index]
	return background

func find_nonempty_closeup()->Dictionary:
	# Camera search changes no shader input, clock, opacity, geometry or sorting.
	# The original shore shader reads only its source textures/field uniforms and
	# simulation_time, not SCREEN_TEXTURE/DEPTH_TEXTURE or shader TIME.
	var targets:Array=[]
	for owner:Node3D in shores:
		var state:Dictionary=owner.diagnostics()
		for index in state.states.size():
			if float(state.states[index].visibleAlpha)>0.3:targets.append({"alpha":state.states[index].visibleAlpha,"owner":owner,"index":index,"patch":state.packets[index]})
	targets.sort_custom(func(a:Dictionary,b:Dictionary):return float(a.alpha)>float(b.alpha))
	baseline_scripts()
	for index in mini(12,targets.size()):
		var record:Dictionary=targets[index];var patch:Dictionary=record.patch
		var point:Vector2=patch.center+patch.outward*(float(patch.offshoreStart)+float(patch.span)*.5)
		var target:Vector3=record.owner.global_transform*Vector3(point.x,0.055,point.y)
		target.y=float(surface.get_shader_parameter("u_tide"))+.055
		var outward:Vector3=record.owner.global_basis*Vector3(patch.outward.x,0,patch.outward.y)
		camera.global_position=target+outward*24.0+Vector3(0,18,0);camera.look_at(target)
		camera.near=.1;camera.far=4000.0;apply_world(false)
		var material:ShaderMaterial=record.owner.get("_materials")[record.index]
		var actual:Dictionary=await capture_frame("closeup-probe-%02d-source"%index)
		if finished:return {}
		var background:Dictionary=await capture_without_shore("closeup-probe-%02d-no-shore"%index)
		if finished:return {}
		var difference:=image_diff(actual.images,background.images)
		probes.append({"index":index,"sourceAlpha":record.alpha,"actualControllerAlpha":material.get_shader_parameter("controller_alpha"),"actualSourceAlphaThreshold":material.get_shader_parameter("source_alpha_threshold"),"shaderPath":material.shader.resource_path,"target":target,"targetGroundHeight":record.owner.get("_field").sample_triangle_height(point.x,point.y),"camera":camera.global_transform,"difference":difference,"source":strip_images(actual),"noShore":strip_images(background)})
		if int(difference.get("main",{}).get("changedBytes",0))>0 and int(difference.get("reflection",{}).get("changedBytes",0))>0:return {"pose":camera.global_transform,"target":target}
	check(false,"original shader has nonempty main AND actual reflection closeup pixels; no opacity/threshold override allowed")
	return {}

func capture_case(label:String,pose:Transform3D,near:float,far:float,exercise_reentry:bool=false)->void:
	stage=label+":baseline-source"
	camera.global_transform=pose;camera.near=near;camera.far=far
	baseline_scripts();apply_world(false)
	var expected:=source_snapshot()
	var reference:Dictionary=await capture_frame(label+"-baseline")
	if finished:return
	# Separate an actual write-free redraw from the original repeated same-time
	# World submission control. Neither check relaxes zero-byte pixel equality.
	var redraw:Dictionary=await capture_frame(label+"-baseline-pure-redraw")
	if finished:return
	var redraw_diff:=image_diff(reference.images,redraw.images)
	for view:String in ["main","reflection"]:
		check(not redraw_diff.get(view,{}).has("error") and bool(redraw_diff.get(view,{}).get("exact",false)),label+" pure redraw baseline GPU image stable "+view)
	var background:Dictionary=await capture_without_shore(label+"-no-shore-control")
	if finished:return
	var contribution:=image_diff(reference.images,background.images)
	for view:String in ["main","reflection"]:
		check(not contribution.get(view,{}).has("error") and int(contribution.get(view,{}).get("changedBytes",0))>0,label+" original shore contributes nonempty actual GPU pixels "+view)
	apply_world(false);var control:Dictionary=await capture_frame(label+"-baseline-control")
	if finished:return
	stage=label+":candidate-source"
	candidate_scripts(float(packet.time)-1.0/60.0)
	var hidden_work:Array=[]
	if exercise_reentry:
		camera.global_position=Vector3(10000000,100,10000000);camera.look_at(Vector3(10000000,100,10001000),Vector3.UP)
		apply_world(true)
		for shore:Node3D in shores:
			var work:Dictionary=shore.presentation_diagnostics();hidden_work.append({"visible":work.visible,"samples":work.samples,"writes":work.materialWrites,"accepted":work.acceptedTime,"submitted":work.submittedTime})
		for row:Dictionary in hidden_work:check(not row.visible and row.samples==0 and row.writes==0,"same-time reentry starts from genuinely unsubmitted hidden frame")
		camera.global_transform=pose
	apply_world(true)
	var current_work:Array=[]
	for shore:Node3D in shores:
		var work:Dictionary=shore.presentation_diagnostics();current_work.append({"visible":work.visible,"samples":work.samples,"writes":work.materialWrites,"viewHits":work.viewHits})
	var actual:Dictionary=await capture_frame(label+"-candidate")
	if finished:return
	stage=label+":source-and-pixel-compare"
	var source_proof:=compare_sources(expected)
	var hold_diff:=image_diff(reference.images,control.images);var candidate_diff:=image_diff(control.images,actual.images)
	for view:String in hold_diff:
		check(not hold_diff[view].has("error") and bool(hold_diff[view].get("exact",false)),label+" unchanged baseline GPU image stable "+view)
		check(not candidate_diff.get(view,{}).has("error") and bool(candidate_diff.get(view,{}).get("exact",false)),label+" candidate exact raw GPU pixels "+view)
	cases.append({"case":label,"acceptedTime":packet.time,"near":near,"far":far,"camera":pose,"baseline":strip_images(reference),"baselinePureRedraw":strip_images(redraw),"baselinePureRedrawDiff":redraw_diff,"noShoreControl":strip_images(background),"shoreContribution":contribution,"baselineControl":strip_images(control),"candidate":strip_images(actual),"baselineHoldDiff":hold_diff,"candidateDiff":candidate_diff,"hiddenBeforeReentry":hidden_work,"workBeforeDiagnostics":current_work,"sourceProof":source_proof})

func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):capture=arg.trim_prefix("--capture=")
		if arg.begins_with("--tick="):fixed_tick=int(arg.trim_prefix("--tick="))
		if arg.begins_with("--scope="):render_scope=arg.trim_prefix("--scope=")
	if not check(DisplayServer.get_name()!="headless","GPU capture needs actual display/rendering backend"):quit(1);return
	if not check(not capture.is_empty() and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(capture)),"fresh explicit capture directory"):quit(1);return
	if not check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture))==OK,"create fresh capture directory"):quit(1);return
	arm_watchdog()
	for path:String in [SOURCE,BASELINE,"res://modules/scene_engine/terrain/shore_view_bounds.gd","res://modules/scene_engine/terrain/natural_world.gd","res://modules/scene_engine/world/world_view.gd","res://tools/capture-shore-frustum-culling.gd"]:source_hashes[path]=FileAccess.get_sha256(path)
	if not check(render_scope in ["full","shore-only","shore-environment","shore-environment-no-foliage"],"explicit supported render scope"):finish_capture("invalid-render-scope");return
	if not check(fixed_tick>0 and fixed_tick<=120,"fixed tick is in the bounded capture range 1..120"):finish_capture("invalid-tick");return
	stage="baseline-and-production-compile"
	candidate_script=load(SOURCE)
	baseline_script=GDScript.new()
	# The frozen algorithm is unchanged. This no-op only lets the new actual
	# NaturalWorld composition call its camera-input interface on the baseline.
	baseline_script.source_code=FileAccess.get_file_as_string(BASELINE)+"\nfunc set_view_cameras(_main:Camera3D,_reflection:Camera3D=null,_enabled:bool=false)->void:\n\tpass\n"
	if not check(candidate_script.can_instantiate() and baseline_script.reload()==OK,"frozen pre-culling baseline and actual production candidate compile"):finish_capture("baseline-compile");return
	stage="public-entry-startup"
	root.size=Vector2i(1200,900);root.content_scale_size=root.size
	main=Main.new();main.router=Router.new({"mingqi_storage":MemorySlot.new(),"legacy_storage":MemorySlot.new(),"settings_storage":Settings.new("user://verification/shore-gpu-no-write-%d.json"%OS.get_process_id())});root.add_child(main)
	for frame in 5:await process_frame
	var sail:Variant=main.menu.find_child("sail",true,false)
	if not check(sail is BaseButton,"actual public sail button"):finish_capture("public-entry-button");return
	sail.pressed.emit()
	var ready:=false
	for frame in 400:
		await process_frame
		if not is_instance_valid(main.current_scene):continue
		var receipt:Variant=main.current_scene.get("startup_receipt")
		if receipt is Dictionary and bool(receipt.get("ok",false)):ready=true;break
	if not check(ready,"actual public sail startup receipt ready"):finish_capture("public-entry-startup");return
	game=main.current_scene;freeze_callbacks(main)
	stage="fixed-tick-presentation"
	for reason:String in ["menu","player","blur"]:game.runtime.set_pause(reason,false)
	var consumed:=0.0
	for tick in fixed_tick:consumed+=game.runtime.advance(STEP)
	game._present(consumed)
	stage="bind-actual-entry-types"
	if not bind_actual_entry():finish_capture("actual-entry-interface");return
	if not await stabilize_entry():finish_capture("stabilize-entry");return
	if render_scope in ["shore-only","shore-environment","shore-environment-no-foliage"]:
		var closeup:Dictionary=await find_nonempty_closeup()
		if finished:return
		if closeup.is_empty():finish_capture("empty-original-shore");return
		var close_pose:Transform3D=closeup.pose
		await capture_case("shore-closeup",close_pose,.1,4000.0)
		if finished:return
		var distance:=close_pose.origin.distance_to(closeup.target)
		await capture_case("shore-near-plane",close_pose,distance,4000.0)
		if finished:return
		await capture_case("same-time-reentry",close_pose,.1,4000.0,true)
		if finished:return
		mirror_case={"scope":"No claim of nonempty actual mirror-only pixels when main excludes the entire conservative island AABB. Shader vertices and their tide-reflected positions both lie inside its +/-amplitude+1m Y bound; complete main exclusion also excludes every potentially mirrored vertex. Enabled mirror union logic is independently tested with supplied Camera3D views in the numerical production contract."}
		stage="complete";finish_capture("complete");return
	var normal_pose:=camera.global_transform;var normal_near:=camera.near;var normal_far:=camera.far
	await capture_case("normal",normal_pose,normal_near,normal_far)
	if finished:return
	var bounds:AABB=shores[0].presentation_diagnostics().bounds;var center:=bounds.get_center();var size:=maxf(bounds.size.length(),100.0)
	camera.global_position=Vector3(center.x,center.y,bounds.position.z-2.0);camera.look_at(center,Vector3.UP)
	await capture_case("near-plane",camera.global_transform,2.0,maxf(10000.0,size*4.0))
	if finished:return
	camera.near=.1;camera.far=maxf(10000.0,size*100.0)
	stage="actual-mirror-only-witness-search"
	mirror_case=find_mirror_only(bounds)
	check(bool(mirror_case.get("found",false)),"actual mirrored camera union has a reflection-only bound witness")
	if mirror_case.get("found",false):await capture_case("actual-mirror-only",mirror_case.transform,camera.near,camera.far)
	if finished:return
	await capture_case("same-time-reentry",normal_pose,normal_near,normal_far,true)
	if finished:return
	stage="complete"
	finish_capture("complete")
