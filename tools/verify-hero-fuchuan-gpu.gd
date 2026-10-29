extends SceneTree
const Experiment=preload("res://game/research/demos/hero_fuchuan_experiment.gd")
const EvidenceGate=preload("res://tools/research/hero_gpu_evidence_gate.gd")
var output:="res://docs/production/hero-fuchuan-2026-10-25/gpu-independent-v1"
var continuous:=""
var model:="hero"
var shadows:="native"
var daylight:="studio"
var failures:Array[String]=[]
var files:Array[Dictionary]=[]
var shadow_frames:Array[Dictionary]=[]
var gate=EvidenceGate.new()

func check(condition:bool,detail:String)->bool:
	if not condition:
		failures.append(detail)
		printerr("HERO_FUCHUAN_GPU_FAIL ",detail)
	return condition

func refuse(reason:String,demo:Node=null)->void:
	if is_instance_valid(demo):demo.free()
	printerr("HERO_FUCHUAN_GPU_REFUSED ",reason)
	quit(1)

func _source_hashes()->Dictionary:
	return gate.watched_source_hashes(model)

func frame(demo:Node,label:String)->bool:
	var before:Dictionary=demo.shadow_diagnostics()
	await process_frame
	await RenderingServer.frame_post_draw
	if shadows=="native":return true
	var after:Dictionary=demo.shadow_diagnostics()
	var verdict:Dictionary=gate.shadow_evidence(before,after)
	var casters:Dictionary=gate.caster_evidence(demo,model,shadows)
	shadow_frames.append({"phase":label,"before":before,"after":after,"casterBinding":casters,"counterCheck":verdict})
	return check(verdict.ok and casters.ok,"shadow evidence "+label+": "+str(verdict.errors)+" "+str(casters.reason))

func save_frame(path:String,label:String,time:float)->Dictionary:
	var texture:=root.get_texture()
	if not check(texture!=null,"viewport texture exists: "+label):return {}
	var pixels:=texture.get_image()
	var saved:Dictionary=gate.save_png(pixels,path,label,time,root.size)
	if not check(saved.ok,"PNG capture "+label+": "+str(saved.get("reason",""))):return {}
	files.append(saved.entry)
	return saved.entry
func _initialize()->void:run.call_deferred()
func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg.begins_with("--continuous="):continuous=arg.trim_prefix("--continuous=")
		if arg.begins_with("--model="):model=arg.trim_prefix("--model=")
		if arg.begins_with("--shadows="):shadows=arg.trim_prefix("--shadows=")
		if arg.begins_with("--daylight="):daylight=arg.trim_prefix("--daylight=")
	if output.is_empty() or DirAccess.dir_exists_absolute(output) or FileAccess.file_exists(output) or (not continuous.is_empty() and (DirAccess.dir_exists_absolute(continuous) or FileAccess.file_exists(continuous))):
		refuse("fresh output directories required");return
	var demo:=Experiment.new()
	var configured:Dictionary=demo.configure({"animated":false,"model":model,"shadows":shadows,"daylight":daylight})
	if not configured.get("ok",false):
		refuse(str(configured.get("reason","configure-failed")),demo);return
	if root.use_xr:
		refuse("single-view viewport required for draw accounting",demo);return
	if DisplayServer.get_name()=="headless" or (shadows!="native" and RenderingServer.get_rendering_device()==null):
		refuse("GPU display unavailable for requested shadow mode",demo);return
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))!=OK:
		refuse("could not create output directory",demo);return
	if not continuous.is_empty() and DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(continuous))!=OK:
		refuse("could not create continuous output directory",demo);return
	root.size=Vector2i(1280,900)
	root.add_child(demo)
	if not demo.inspection_snapshot().ready or not is_instance_valid(demo._ship) or not is_instance_valid(demo._ship.get_model()):
		refuse("configured model is not ready",demo);return
	var hashes:=_source_hashes()
	var r9_provenance:Dictionary={}
	if model in ["art_r9","art_r9b"]:
		r9_provenance=gate.r9_asset_evidence(hashes,model.trim_prefix("art_"))
		if not r9_provenance.ok:
			refuse("R9 asset provenance mismatch: "+str(r9_provenance.errors),demo);return
	if model=="art_r11":
		r9_provenance=gate.r11_asset_evidence(hashes)
		if not r9_provenance.ok:
			refuse("R11 asset provenance mismatch: "+str(r9_provenance.errors),demo);return
	var source_path:String=demo._ship.get_model().get_meta("source_path","")
	var asset_hash:=FileAccess.get_sha256(source_path) if FileAccess.file_exists(source_path) else ""
	var expected:Array[String]=gate.expected_source_paths(model)
	if hashes.values().has("MISSING") or expected.size()!=3 or source_path!=expected[0] or asset_hash.is_empty():
		refuse("actual model source is missing or does not match requested model",demo);return
	var asset_hashes:Dictionary={}
	for lod in 3:
		var loaded:Node=demo._ship.get_node_or_null("LOD%d"%lod)
		var path:String=str(loaded.get_meta("source_path", "")) if loaded!=null else ""
		if path!=expected[lod] or not FileAccess.file_exists(path):
			refuse("LOD%d actual source is missing or does not match requested model"%lod,demo);return
		asset_hashes[path]=FileAccess.get_sha256(path)
	var initial:=demo.inspection_snapshot()
	var initial_ship_snapshot:Dictionary=demo._ship.get("_snapshot").duplicate(true)
	var initial_wind:Dictionary=demo._ship.get("_wind").duplicate(true)
	check(initial_ship_snapshot==initial.snapshot,"initial actor snapshot matches experiment")
	var warm_receipts:Array[Dictionary]=[]
	if shadows!="native":
		var initialized:=false
		for attempt in 20:
			await process_frame
			await RenderingServer.frame_post_draw
			demo.refresh_shadow_projection()
			var diagnostic:Dictionary=demo.shadow_diagnostics()
			warm_receipts.append(diagnostic)
			var gpu:Dictionary=diagnostic.get("renderer",{}).get("gpu",{})
			if gpu.get("initialized",false) and str(gpu.get("error","")).is_empty() and int(gpu.get("frames",0))>0 and int(gpu.get("draws",0))>1:
				initialized=true
				break
		check(initialized,"authored/visible compositor initialized and submitted geometry; native fallback is not accepted")
	else:
		await process_frame
		await process_frame
	if failures.is_empty() and (await frame(demo,"full-sail")):
		save_frame(output.path_join("full-sail.png"),"full-sail",demo.inspection_snapshot().time)
	if failures.is_empty():
		demo.orbit_camera(PI,0)
		if await frame(demo,"reverse-light"):save_frame(output.path_join("reverse-light.png"),"reverse-light",demo.inspection_snapshot().time)
	demo.orbit_camera(-PI,0)
	var detail_frames:Array=[]
	var camera:Camera3D=demo._camera
	var camera_before:=camera.transform
	for view:Dictionary in [{"name":"stern-deck-detail","position":Vector3(-13,9,12),"target":Vector3(-7,3.7,0)},{"name":"hull-guns-detail","position":Vector3(1,4.5,12),"target":Vector3(1,1.5,0)},{"name":"cloth-detail","position":Vector3(0,16,12),"target":Vector3(0,14,0)}]:
		if not failures.is_empty():break
		camera.position=view.position;camera.look_at(view.target)
		if await frame(demo,view.name):
			var saved:=save_frame(output.path_join(view.name+".png"),view.name,demo.inspection_snapshot().time)
			if not saved.is_empty():detail_frames.append({"image":view.name+".png","position":view.position,"target":view.target,"time":demo.inspection_snapshot().time})
	camera.transform=camera_before
	var states:Array=[]
	var frame_hashes:Array=[]
	var pose_frames:Array=[]
	var sail_min:=INF;var sail_max:=-INF;var rudder_min:=INF;var rudder_max:=-INF
	if failures.is_empty():check(demo.set_parameter("animated",true).get("ok",false),"animation parameter accepted")
	for i in range(257):
		if not failures.is_empty():break
		if i>0:demo.advance(1.0/32.0)
		if not (await frame(demo,"motion-%03d"%i)):break
		var state:Dictionary=demo.inspection_snapshot()
		if not check(absf(float(state.time)-float(i)/32.0)<0.000001,"fixed simulation time at frame %d"%i):break
		var pose:Dictionary=gate.pose_evidence(demo,model,state.snapshot)
		if not check(pose.ok,"actual sail/rudder pose matches snapshot at frame %d"%i):break
		states.append(state);pose_frames.append(pose)
		sail_min=minf(sail_min,float(state.snapshot.sailDeployment));sail_max=maxf(sail_max,float(state.snapshot.sailDeployment))
		rudder_min=minf(rudder_min,float(state.snapshot.rudder));rudder_max=maxf(rudder_max,float(state.snapshot.rudder))
		if not continuous.is_empty():
			var raw_path:=continuous.path_join("frame-%04d.png"%i)
			var raw:=save_frame(raw_path,"motion-%04d"%i,float(state.time))
			if raw.is_empty():break
			frame_hashes.append({"frame":i,"time":state.time,"path":raw_path,"sha256":raw.sha256})
		if i%64==0:
			save_frame(output.path_join("sequence-%03d.png"%i),"sequence-%03d"%i,float(state.time))
	if failures.is_empty():
		check(states.size()==257 and (continuous.is_empty() or frame_hashes.size()==257),"all 257 requested motion frames recorded")
		check(sail_max-sail_min>0.5 and rudder_max-rudder_min>1.0,"motion sequence contains substantial sail and rudder movement")
	demo.set_paused(true)
	var before:=demo.inspection_snapshot();demo.advance(1)
	var pause_ok:=before==demo.inspection_snapshot()
	check(pause_ok,"paused experiment remains unchanged")
	# Controlled action samples: identical accepted time, heading, rudder,
	# wind and state, varying only sail deployment. LOD is selected through
	# the real distance API while the camera remains fixed for shape comparison.
	var fixed:Dictionary=before.snapshot.duplicate(true)
	fixed.sailAngle=0.0;fixed.rudder=0.35;fixed.sail=100.0
	var wind:Dictionary=initial_wind.duplicate(true)
	var direction:Dictionary=wind.get("direction",{})
	var visual:Dictionary=fixed.get("visual",{})
	var velocity:Dictionary=visual.get("velocity",{})
	check(float(wind.get("speed",-1))==14.0 and float(direction.get("x",0))==1.0 and float(direction.get("y",1))==0.0 and absf(float(visual.get("heading",0))-PI/2.0)<0.000001 and float(velocity.get("x",1))==0.0 and float(velocity.get("z",1))==0.0,"fixed action wind and geometry match the declared independent inflation expectation")
	var deployment_frames:Array=[]
	var lod_frames:Array=[]
	demo._ship.set_lod_distance(0.0)
	for amount:float in [0.0,0.25,0.5,0.75,1.0]:
		if not failures.is_empty():break
		var state:Dictionary=fixed.duplicate(true);state.sailDeployment=amount
		demo._ship.apply_snapshot(state,wind,0)
		demo.refresh_shadow_projection()
		var selected:Dictionary=gate.lod_evidence(demo,model,0)
		var components:Dictionary=gate.deployment_evidence(demo,model,state,wind,-14.0/18.0*amount)
		if not check(selected.ok and components.ok,"actual deployment %.2f LOD0 and canvas/batten state: %s %s"%[amount,str(selected.errors),str(components.get("errors",[]))]):break
		var phase:="deployment-%03d"%roundi(amount*100)
		if not (await frame(demo,phase)):break
		var saved:=save_frame(output.path_join(phase+".png"),phase,float(state.time))
		if saved.is_empty():break
		deployment_frames.append({"phase":phase,"deployment":amount,"wind":wind.duplicate(true),"snapshot":state,"lodEvidence":selected,"components":components,"file":saved})
	for lod in 3:
		if not failures.is_empty():break
		var distance:float=[0.0,220.0,650.0][lod]
		demo._ship.set_lod_distance(distance)
		var state:Dictionary=fixed.duplicate(true);state.sailDeployment=1.0
		demo._ship.apply_snapshot(state,wind,0)
		demo.refresh_shadow_projection()
		var selected:Dictionary=gate.lod_evidence(demo,model,lod)
		var components:Dictionary=gate.deployment_evidence(demo,model,state,wind,-14.0/18.0)
		if not check(selected.ok and components.ok,"actual LOD%d and canvas/batten state: %s %s"%[lod,str(selected.errors),str(components.get("errors",[]))]):break
		var phase:="lod-%d"%lod
		if not (await frame(demo,phase)):break
		var saved:=save_frame(output.path_join(phase+".png"),phase,float(state.time))
		if saved.is_empty():break
		lod_frames.append({"phase":phase,"lod":lod,"distanceArgument":distance,"wind":wind.duplicate(true),"snapshot":state,"lodEvidence":selected,"components":components,"file":saved})
	var action_evidence:Dictionary=gate.action_capture_evidence(deployment_frames,lod_frames,files,shadow_frames,model,shadows,wind,output)
	check(action_evidence.ok,"complete fixed-wind deployment and LOD frame evidence: "+str(action_evidence.errors))
	# Damage samples again use the normal closest presentation model.
	demo._ship.set_lod_distance(0.0)
	var full_state:Dictionary=fixed.duplicate(true);full_state.sailDeployment=1.0
	demo._ship.apply_snapshot(full_state,wind,0)
	demo.refresh_shadow_projection()
	var damage_frames:Array=[]
	var intact_color:Dictionary={}
	if model=="art_r11":
		intact_color=gate.canvas_color_evidence(demo)
		check(intact_color.ok,"R11 intact canvas color binding: "+str(intact_color.errors))
	for health:float in [80.0,60.0,30.0]:
		if not failures.is_empty():break
		var damage_state:Dictionary=demo.inspection_snapshot().snapshot.duplicate(true)
		damage_state.sail=health;damage_state.sailDeployment=1.0;damage_state.sailAngle=0.0
		demo._ship.apply_snapshot(damage_state,{"direction":{"x":1,"y":0},"speed":14},0)
		var color_evidence:Dictionary={}
		if model=="art_r11":
			color_evidence=gate.canvas_color_evidence(demo)
			if not check(color_evidence.ok,"R11 damaged canvas color binding: "+str(color_evidence.errors)):break
		demo.refresh_shadow_projection()
		if not (await frame(demo,"sail-health-%d"%int(health))):break
		var filename:="sail-health-%d.png"%int(health)
		if not save_frame(output.path_join(filename),filename,float(damage_state.time)).is_empty():damage_frames.append({"image":filename,"snapshot":damage_state,"canvasColorEvidence":color_evidence,"scope":"controlled intermediate cloth damage"})
	var reset:=demo.reset_experiment({"animated":false,"paused":false})
	var reset_lod:Dictionary={"ok":false};var reset_pose:Dictionary={"ok":false}
	var reset_ok:=false
	if reset.get("ok",false) and is_instance_valid(demo._ship) and is_instance_valid(demo._ship.get_model()):
		reset_lod=gate.lod_evidence(demo,model,0)
		reset_pose=gate.pose_evidence(demo,model,initial.snapshot)
		reset_ok=demo.inspection_snapshot()==initial and demo._ship.get("_snapshot")==initial_ship_snapshot and demo._ship.get("_wind")==initial_wind and reset_lod.ok and reset_pose.ok
	check(reset_ok,"reset restores initial snapshot, actual actor pose, wind and LOD0")
	var reset_record:Dictionary={}
	if failures.is_empty():
		var reset_ready:=shadows=="native"
		if shadows!="native":
			for attempt in 20:
				await process_frame;await RenderingServer.frame_post_draw
				demo.refresh_shadow_projection()
				var current:Dictionary=demo.shadow_diagnostics().get("renderer",{}).get("gpu",{})
				if current.get("initialized",false) and str(current.get("error","")).is_empty() and int(current.get("frames",0))>0 and int(current.get("draws",0))>1:
					reset_ready=true;break
		check(reset_ready,"reset compositor completes native-to-authored shadow handoff")
		if failures.is_empty() and (await frame(demo,"reset-initial")):
			var saved:=save_frame(output.path_join("reset-initial.png"),"reset-initial",float(initial.snapshot.time))
			if not saved.is_empty():reset_record={"phase":"reset-initial","snapshot":demo._ship.get("_snapshot").duplicate(true),"wind":demo._ship.get("_wind").duplicate(true),"lodEvidence":reset_lod,"poseEvidence":reset_pose,"file":saved}
	var reset_evidence:Dictionary=gate.reset_capture_evidence(reset_record,initial_ship_snapshot,initial_wind,files,shadow_frames,model,shadows,output)
	check(reset_evidence.ok,"reset rendered-frame evidence: "+str(reset_evidence.errors))
	var source_ok:bool=hashes==_source_hashes()
	for path:String in asset_hashes:source_ok=source_ok and FileAccess.file_exists(path) and asset_hashes[path]==FileAccess.get_sha256(path)
	check(source_ok,"watched sources and all selected LOD assets unchanged")
	if failures.is_empty():check(files.size()==22+(257 if not continuous.is_empty() else 0),"all requested named PNGs were recorded")
	var file_result:Dictionary=gate.file_evidence(files)
	var files_ok:bool=file_result.ok
	check(files_ok,"every saved PNG retains its SHA256: "+str(file_result.errors))
	var motion_range:Dictionary={"sailDeployment":[sail_min,sail_max],"rudder":[rudder_min,rudder_max]} if not states.is_empty() else {"sailDeployment":[],"rudder":[]}
	var report:Dictionary={"scope":"independent GPU rig; automated snapshot sequence, not native gameplay or FPS; compositor counters do not prove exact per-submission render-thread revision identity; LOD frames use distance API with a fixed camera","model":model,"shadows":shadows,"daylight":daylight,"sourcePath":source_path,"assetSha256":asset_hash,"assetHashes":asset_hashes,"r9AssetProvenance":r9_provenance,"sourceSha256":hashes,"sourcesUnchanged":source_ok,"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"engine":Engine.get_version_info(),"fixedStep":1.0/32.0,"frames":states,"poseFrames":pose_frames,"continuousRequested":not continuous.is_empty(),"continuousFrames":frame_hashes,"savedFiles":files,"filesUnchanged":files_ok,"shadowWarmup":warm_receipts,"shadowFrames":shadow_frames,"deploymentFrames":deployment_frames,"lodFrames":lod_frames,"actionCaptureEvidence":action_evidence,"intactCanvasColorEvidence":intact_color,"damageFrames":damage_frames,"detailFrames":detail_frames,"pauseUnchanged":pause_ok,"resetInitialSnapshotEqual":reset_ok,"resetFrame":reset_record,"resetCaptureEvidence":reset_evidence,"motionRange":motion_range,"failures":failures}
	var report_path:=output.path_join("manifest.json")
	if check(not FileAccess.file_exists(report_path),"manifest destination remains fresh"):
		var file:=FileAccess.open(report_path,FileAccess.WRITE)
		if check(file!=null,"manifest opens for writing"):
			file.store_string(JSON.stringify(report,"\t"))
			check(file.get_error()==OK,"manifest write succeeded")
			file.close()
	demo.dispose();demo.free();await process_frame
	print("HERO_FUCHUAN_GPU_CHECK frames=",states.size()," failures=",failures.size())
	quit(1 if not failures.is_empty() else 0)
