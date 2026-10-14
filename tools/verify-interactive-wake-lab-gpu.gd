extends SceneTree
## Serial real-GPU lab driver. Main thread never advances past an unpublished
## input. Screenshots/readback are QA-only; this is not full-game performance.
const Experiment = preload("res://game/research/demos/wake_flow_experiment.gd")
const STEP := 1.0/32.0
const SOURCES := ["tools/verify-interactive-wake-lab-gpu.gd","game/research/demos/wake_flow_experiment.gd","game/research/demos/hull_contact_experiment.gd","game/presentation/ships/ship_view.gd","game/presentation/crew/crew_view.gd","game/presentation/world/source_water_packet.gd","game/runtime/sailing_runtime.gd","modules/scene_engine/water/ship_water_interaction.gd","modules/scene_engine/water/interactive_wake_field.gd","modules/scene_engine/water/interactive_wake_field_rd.gd","modules/scene_engine/water/interactive_wake_height.glsl","modules/scene_engine/water/interactive_wake_foam.glsl","modules/scene_engine/water/source_wake_renderer.gd","modules/scene_engine/water/source_surface.gd","modules/scene_engine/water/source_wake_history.gd","modules/scene_engine/water/source_wake_geometry.gd","modules/scene_engine/water/hull_contact_froth.gd","modules/scene_engine/water/wake_flow.gd","modules/scene_engine/water/wake_flow.gdshader","modules/scene_engine/ocean/projected_ocean.gd","modules/scene_engine/ocean/projected_grid_coverage.gd","modules/scene_engine/ocean/reference_game_water.gdshader","modules/scene_engine/ocean/interactive_wake_surface.gdshaderinc"]
var output := ""
var output_owned := false
var mode := "source"
var ticks := 256
var every := 1
var windows: Array = []
var options := {"kind":"fuchuan","scenario":"cruise","turn_direction":"right","camera_mode":"high","zoom":0.65,"quality":"balanced","carrier_mode":"projected","projected_resolution":80,"carrier_extent":384.0,"contact_enabled":true,"field_debug":"none","flow_enabled":false,"field_enabled":false}
var demo: Node3D
var failures: Array[String] = []
var captures: Array = []
var sources: Dictionary = {}
var readback: Dictionary = {}
var readback_done := false
var generation := 0
var timings_us: Array = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool,reason: String) -> void:
	if not ok: failures.append(reason);printerr("FAIL interactive wake lab GPU: ",reason)
static func capture_ticks(total: int,interval: int,stage_windows: Array = []) -> Array:
	if total<1 or interval<1:return []
	if stage_windows.size()>3:return []
	for window: Variant in stage_windows:
		if not window is Array or window.size()!=2 or not window[0] is int or not window[1] is int:return []
		if window[0]<0 or window[1]>total or window[1]<window[0] or window[1]-window[0]>64:return []
	var result: Array=[0]
	for tick in range(1,total+1):
		var in_window := false
		for window: Array in stage_windows:in_window=in_window or (tick>=window[0] and tick<=window[1])
		if tick%interval==0 or tick==total or in_window:result.append(tick)
	return result
static func capture_inventory_valid(records: Array,total: int,interval: int,candidate: String,stage_windows: Array = []) -> bool:
	var expected := capture_ticks(total,interval,stage_windows)
	if expected.is_empty() or records.size()!=expected.size():return false
	var previous := -1.0
	for index in records.size():
		if not records[index] is Dictionary:return false
		var record: Dictionary=records[index]
		var seconds: Variant=record.get("time")
		if record.get("tick")!=expected[index] or not (seconds is float or seconds is int) or not is_finite(float(seconds)) or float(seconds)<0.0 or float(seconds)<=previous:return false
		previous=float(seconds)
		for key in ["image_sha256","ship_sha256","controls_sha256"]:
			var digest: String=str(record.get(key,""))
			if digest.length()!=64 or not digest.is_valid_hex_number(false):return false
		if record.get("camera_transform",[]).size()!=16 or record.get("camera_projection",[]).size()!=16:return false
		if candidate=="field" and (record.get("field_status")!="ready" or not record.get("field_bound",false)):return false
	return true
static func summarize_readback(receipt: Dictionary) -> Dictionary:
	var bytes: PackedByteArray=receipt.get("data",PackedByteArray())
	var size := int(receipt.get("resolution",0))
	if not str(receipt.get("error","")).is_empty():return {"ok":false,"error":receipt.error}
	if receipt.get("format")!="rgba32f" or size<1 or size>512 or bytes.size()!=size*size*16:return {"ok":false,"error":"invalid-readback-layout"}
	var floats := bytes.to_float32_array();var max_height:=0.0;var max_foam:=0.0;var min_foam:=1.0
	for index in range(0,floats.size(),4):
		for channel in 4:
			if not is_finite(floats[index+channel]):return {"ok":false,"error":"nonfinite-field-data"}
		max_height=maxf(max_height,absf(floats[index]));max_foam=maxf(max_foam,floats[index+3]);min_foam=minf(min_foam,floats[index+3])
	return {"ok":max_height<=0.25001 and min_foam>=-0.00001 and max_foam<=1.00001,"all_finite":true,"max_abs_height_m":max_height,"max_foam":max_foam,"min_foam":min_foam,"bytes":bytes.size()}
func hashes() -> Dictionary:
	var result := {}
	for path: String in SOURCES:result[path]=FileAccess.get_sha256("res://"+path) if FileAccess.file_exists("res://"+path) else "missing"
	return result
func poll_field(target_time: float) -> bool:
	if mode!="field":return true
	for attempt in 240:
		demo.advance(0.0)
		var info: Dictionary=demo.inspection_snapshot()
		var field: Dictionary=info.get("field",{})
		if info.get("field_status")=="error":check(false,"field error: "+str(info.get("field_error","")));return false
		var published := float(field.get("published_time",field.get("time",-1.0)))
		if info.get("field_bound",false) and field.get("ready",false) and not field.get("pending",true) and published+0.000001>=target_time:
			check(int(field.get("dropped_steps",0))==0,"field must not drop accepted steps")
			check(published<=target_time+0.000001,"published field cannot run ahead of authoritative time")
			return failures.is_empty()
		await process_frame
	check(false,"field publication timed out at accepted time "+str(target_time))
	return false
func capture(tick: int) -> void:
	await RenderingServer.frame_post_draw
	var info: Dictionary=demo.inspection_snapshot()
	check(framing_valid(),"complete visible vessel AABBs and two waterline lengths aft remain in frame")
	var file_name := "t%04d.png"%tick
	var image: Image=root.get_texture().get_image()
	check(image!=null and not image.is_empty(),"nonempty GPU framebuffer")
	if image==null or image.is_empty():return
	check(image.save_png(output+"/"+file_name)==OK,"save raw frame "+file_name)
	captures.append({"image":file_name,"image_sha256":FileAccess.get_sha256(output+"/"+file_name),"tick":tick,"time":info.time,"native_time":info.time,"observer_time":info.presentation_time,"field_requested_time":info.field_requested_time,"field_status":info.field_status,"field_bound":info.field_bound,"field":info.field,"field_published_bounds":info.field_published_bounds,"field_surface_generation":info.field_surface_generation,"interaction":info.interaction,"interaction_duplicate_skips":info.interaction_duplicate_skips,"controls":info.parameters,"controls_sha256":var_to_bytes(info.parameters).hex_encode().sha256_text(),"ship_sha256":var_to_bytes(info.native_ship).hex_encode().sha256_text(),"native_ship":info.native_ship,"camera_transform":info.camera_transform,"camera_projection":info.camera_projection,"camera_framing":info.camera_framing,"carrier":info.carrier,"tail":info.tail,"tail_visible":info.tail_visible,"contact_visible":info.contact_visible,"speed":info.target_trail.speed})
func framing_valid() -> bool:
	var camera: Camera3D=demo.get("_camera")
	var ship: Node3D=demo.get("_ship")
	var points := PackedVector3Array()
	for node: Node in ship.get_model().find_children("*","MeshInstance3D",true,false):
		if not node.is_visible_in_tree():continue
		var box: AABB=node.get_aabb()
		for corner in 8:points.append(node.global_transform*box.get_endpoint(corner))
	var attachment: Dictionary=ship.source_water_attachment()
	var profile: Dictionary=attachment.surfaceProfile
	var length: float=absf(float(profile.sections[-1].z)-float(profile.sections[0].z))*profile.hullToWorld.basis.z.length()
	var heading: float=demo.inspection_snapshot().native_ship.heading
	points.append(attachment.flowStern);points.append(attachment.flowStern-Vector3(cos(heading),0,sin(heading))*length*2.0)
	var size: Vector2=camera.get_viewport().get_visible_rect().size
	for point: Vector3 in points:
		var pixel:=camera.unproject_position(point)
		if camera.is_position_behind(point) or pixel.x<8 or pixel.y<8 or pixel.x>size.x-8 or pixel.y>size.y-8:return false
	return not points.is_empty()
func run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):output=argument.trim_prefix("--output=")
		elif argument.begins_with("--mode="):mode=argument.trim_prefix("--mode=")
		elif argument.begins_with("--ticks="):ticks=int(argument.trim_prefix("--ticks="))
		elif argument.begins_with("--every="):every=int(argument.trim_prefix("--every="))
		elif argument.begins_with("--window="):
			var pair := argument.trim_prefix("--window=").split(":")
			if pair.size()!=2 or not pair[0].is_valid_int() or not pair[1].is_valid_int():check(false,"window uses start:end observation ticks")
			else:windows.append([int(pair[0]),int(pair[1])])
		elif argument.begins_with("--scenario="):options.scenario=argument.trim_prefix("--scenario=")
		elif argument.begins_with("--turn-direction="):options.turn_direction=argument.trim_prefix("--turn-direction=")
		elif argument.begins_with("--kind="):options.kind=argument.trim_prefix("--kind=")
		elif argument.begins_with("--camera="):options.camera_mode=argument.trim_prefix("--camera=")
		elif argument.begins_with("--debug="):options.field_debug=argument.trim_prefix("--debug=")
		elif argument.begins_with("--quality="):options.quality=argument.trim_prefix("--quality=")
		elif argument.begins_with("--zoom="):options.zoom=float(argument.trim_prefix("--zoom="))
		elif argument.begins_with("--carrier="):options.carrier_extent=float(argument.trim_prefix("--carrier="))
		elif argument.begins_with("--carrier-mode="):options.carrier_mode=argument.trim_prefix("--carrier-mode=")
		elif argument.begins_with("--projected-resolution="):options.projected_resolution=int(argument.trim_prefix("--projected-resolution="))
		elif argument=="--no-contact":options.contact_enabled=false
		else:check(false,"unknown argument "+argument)
	check(mode in ["source","field","historical-v2"],"mode is source, field or historical-v2")
	check(ticks>=1 and ticks<=4096 and every>=1 and every<=ticks,"bounded nonempty capture schedule")
	check(not capture_ticks(ticks,every,windows).is_empty(),"up to three ordered windows, each at most64 ticks and within run")
	check(not output.is_empty() and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output)),"new output directory required")
	if not failures.is_empty():finish();return
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))==OK,"create fresh output directory")
	if not failures.is_empty():finish();return
	output_owned=true
	check(DisplayServer.get_name()!="headless","this driver requires real GPU; workers must use headless contract tests")
	if not failures.is_empty():finish();return
	root.size=Vector2i(1200,760);root.content_scale_size=root.size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	options.field_enabled=mode=="field";options.flow_enabled=mode=="historical-v2"
	sources=hashes();demo=Experiment.new();generation+=1
	var configured: Dictionary=demo.configure(options)
	check(configured.get("ok",false),"experiment configuration accepted")
	root.add_child(demo)
	check(demo.inspection_snapshot().get("ready",false),"real scene owner ready")
	if not failures.is_empty():finish();return
	if not await poll_field(float(demo.inspection_snapshot().field_requested_time)):finish();return
	await capture(0)
	var expected := capture_ticks(ticks,every,windows)
	for tick in range(1,ticks+1):
		var start := Time.get_ticks_usec()
		demo.advance(STEP)
		timings_us.append(Time.get_ticks_usec()-start)
		var info: Dictionary=demo.inspection_snapshot()
		if not await poll_field(float(info.field_requested_time)):break
		if tick in expected:await capture(tick)
		else:await process_frame
	if mode=="field" and failures.is_empty():
		demo.request_field_readback(receive_readback.bind(generation))
		for attempt in 240:
			if readback_done:break
			await process_frame
		check(readback_done and str(readback.get("error","")).is_empty(),"explicit final GPU readback completed")
	demo.set_paused(true)
	var paused: Dictionary=demo.inspection_snapshot()
	demo.advance(1.0);demo.orbit_camera(0.0,0.0)
	var still: Dictionary=demo.inspection_snapshot()
	check(still.time==paused.time and still.field.get("tick",0)==paused.field.get("tick",0),"paused observer preserves accepted physics and field tick")
	check(capture_inventory_valid(captures,ticks,every,mode,windows),"complete ordered capture inventory with receipts")
	check(hashes()==sources,"source hashes remain frozen across GPU run")
	finish()
func receive_readback(receipt: Dictionary,epoch: int) -> void:
	if epoch!=generation:return
	readback_done=true
	readback=receipt.duplicate(true)
	var bytes: PackedByteArray=readback.get("data",PackedByteArray())
	readback.erase("data")
	var summary := summarize_readback(receipt)
	readback.merge(summary,true)
	check(summary.get("ok",false),"raw GPU readback has complete finite bounded channels: "+str(summary.get("error","")))
	if not bytes.is_empty() and output_owned:
		var file := FileAccess.open(output+"/field-final.rgba32f",FileAccess.WRITE)
		if file!=null:file.store_buffer(bytes);file.close()
		else:check(false,"write raw field readback")
		readback.file="field-final.rgba32f";readback.sha256=FileAccess.get_sha256(output+"/field-final.rgba32f");readback.bytes=bytes.size()
	else:check(false,"readback contains actual GPU bytes")
func finish() -> void:
	var final_info: Dictionary=demo.inspection_snapshot() if is_instance_valid(demo) else {}
	if output_owned:
		var result := {"valid":failures.is_empty(),"failures":failures,"scope":"Independent real Ship/Crew/Ocean/SailingRuntime, open water; CPU advance timings exclude async GPU waiting and are not GPU or full-game FPS.","mode":mode,"options":options,"fixed_step":STEP,"ticks":ticks,"capture_interval":every,"capture_windows":windows,"consecutive_accepted_frames":every==1,"sources":sources,"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"viewport":[1200,760],"captures":captures,"readback":readback,"cpu_advance_us":timings_us,"final":final_info}
		var file := FileAccess.open(output+"/GPU_VERIFY.json",FileAccess.WRITE)
		if file!=null:file.store_string(JSON.stringify(result,"\t"));file.close()
		else:check(false,"write GPU receipt")
	generation+=1
	if is_instance_valid(demo):demo.dispose();demo.free()
	for i in 2:await process_frame
	print("INTERACTIVE_WAKE_LAB_GPU captures=",captures.size()," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
