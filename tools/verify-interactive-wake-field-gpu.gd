extends SceneTree
## Numerical GPU QA only. Root runs serially with an actual renderer, never --headless.
const Field = preload("res://modules/scene_engine/water/interactive_wake_field.gd")
var failures: Array[String] = []
var receipts: Array = []
var output := ""
var field: RefCounted
var callback_result: Dictionary = {}
var waiting := false
var publication_checks: Array = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, why: String) -> void:
	if not ok: failures.append(why); printerr("FAIL: ",why)
func settle(seconds: float = -1.0) -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec()-start<10000:
		await process_frame
		var d: Dictionary=field.diagnostics()
		if not str(d.error).is_empty():check(false,"field error: "+str(d.error));return false
		# QA has no sea consumer. It explicitly accepts the pair before waiting for idle.
		var surface:Dictionary=field.acquire_surface()
		if not surface.is_empty():field.acknowledge_surface(int(surface.generation))
		d=field.diagnostics()
		if d.ready and not d.pending and (seconds<0 or abs(float(d.time)-seconds)<0.000001):return true
	check(false,"timed out waiting for published field "+str(seconds));return false
func received(result: Dictionary) -> void:
	callback_result=result;waiting=false
func capture(label: String) -> PackedByteArray:
	waiting=true;callback_result={};field.request_readback(received)
	var start:=Time.get_ticks_msec()
	while waiting and Time.get_ticks_msec()-start<10000:await process_frame
	check(not waiting,"bounded async readback: "+label)
	check(str(callback_result.get("error","missing callback")).is_empty(),"readback succeeds: "+label)
	var data: PackedByteArray=callback_result.get("data",PackedByteArray())
	check(data.size()==64*64*16,"complete RGBA32F field: "+label)
	if data.size()!=64*64*16:return data
	var max_height:=0.0;var foam_sum:=0.0;var finite:=true
	for i in 64*64:
		for channel in 4:finite=finite and is_finite(data.decode_float(i*16+channel*4))
		max_height=maxf(max_height,absf(data.decode_float(i*16)))
		foam_sum+=data.decode_float(i*16+12)
	check(finite,"finite field: "+label);check(max_height<=0.250001,"height bound: "+label)
	var file:=FileAccess.open(output+"/"+label+".rgba32f",FileAccess.WRITE);file.store_buffer(data);file.close()
	var image:=Image.create_from_data(64,64,false,Image.FORMAT_RGBAF,data)
	image.save_exr(output+"/"+label+".exr",false)
	receipts.append({"label":label,"diagnostics":callback_result.diagnostics,"bounds":callback_result.bounds,"max_abs_height":max_height,"foam_sum":foam_sum,"sha256":FileAccess.get_sha256(output+"/"+label+".rgba32f")})
	check(int(callback_result.diagnostics.dropped_steps)==0,"controlled run has no dropped simulation steps: "+label)
	return data
func submit(seconds: float, center: Vector2, emitters: Array = [], wakes: Array = []) -> bool:
	field.advance(seconds,center,emitters,wakes);return await settle(seconds)
func value(data: PackedByteArray,x:int,y:int,channel:int=0)->float:
	return data.decode_float((y*64+x)*16+channel*4) if data.size()==64*64*16 else NAN
func foam_centroids(data: PackedByteArray) -> Vector4:
	var left:=0.0;var right:=0.0;var lm:=0.0;var rm:=0.0
	for y in range(34,56):
		for x in range(2,62):
			var amount:=value(data,x,y,3);var world_x:float=-12.0+(float(x)+0.5)*0.375
			if x<32:left+=amount*world_x;lm+=amount
			else:right+=amount*world_x;rm+=amount
	return Vector4(left/maxf(lm,0.000001),right/maxf(rm,0.000001),lm,rm)
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	if output.is_empty() or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output)):
		printerr("FAIL: --output must name a new directory");quit(1);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	field=Field.new()
	var configured: Dictionary=field.configure({"resolution":64,"extent_m":24.0,"damping":0.0,"activity_foam":0.0})
	check(bool(configured.get("ok",false)),"global RD configures")
	if configured.get("ok",false) and await publication_lifecycle() and await settle():await scenarios()
	field.dispose();field.dispose()
	for i in 4:await process_frame
	check(not field.diagnostics().get("cleanup_pending",false) and field.diagnostics().resource_count==0,"render-thread disposal acknowledged with zero owned resources")
	var proof:={"valid":failures.is_empty(),"failures":failures,"receipts":receipts,"publication_checks":publication_checks,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"sources":{},"scope":"GPU numerical field/readback/lifecycle only. No sea render, ship appearance or game FPS acceptance."}
	for path in ["modules/scene_engine/water/interactive_wake_field.gd","modules/scene_engine/water/interactive_wake_field_rd.gd","modules/scene_engine/water/interactive_wake_height.glsl","modules/scene_engine/water/interactive_wake_foam.glsl","tools/verify-interactive-wake-field-gpu.gd"]:proof.sources[path]=FileAccess.get_sha256("res://"+path)
	var file:=FileAccess.open(output+"/GPU_VERIFY.json",FileAccess.WRITE);file.store_string(JSON.stringify(proof,"\t"));file.close()
	print("INTERACTIVE_WAKE_GPU receipts=",receipts.size()," failures=",failures.size());quit(1 if failures.size() else 0)
func publication_lifecycle() -> bool:
	var start:=Time.get_ticks_msec()
	while not field.diagnostics().ready and Time.get_ticks_msec()-start<10000:
		await process_frame
		if not str(field.diagnostics().error).is_empty():check(false,str(field.diagnostics().error));return false
	var first:Dictionary=field.acquire_surface()
	check(not first.is_empty(),"initial zero surface has a binding receipt")
	if first.is_empty():return false
	check(first.bounds.z>first.bounds.x and first.bounds.w>first.bounds.y,"initialization binding carries usable matching bounds")
	check(field.diagnostics().awaiting_ack and not field.diagnostics().pending,"render completion is distinct from consumer acknowledgement")
	var first_rid:RID=first.texture.texture_rd_rid
	for i in range(1,25):field.advance(float(i)/60.0,Vector2(float(i),0),[],[])
	for i in 4:await process_frame
	var blocked:Dictionary=field.diagnostics()
	check(blocked.queued and blocked.awaiting_ack and not blocked.pending and blocked.time==0.0,"no consumer ACK keeps queue bounded without writing displayed slot")
	check(field.acquire_surface().texture.texture_rd_rid==first_rid and field.acquire_surface().generation==first.generation,"unacknowledged texture generation cannot change")
	field.acknowledge_surface(int(first.generation)-1)
	check(field.diagnostics().awaiting_ack,"stale ACK cannot release queued output")
	publication_checks.append({"initial":first.bounds,"generation":first.generation,"blocked":blocked})
	field.acknowledge_surface(int(first.generation))
	if not await settle(24.0/60.0):return false
	var second:Dictionary=field.acquire_surface()
	check(second.generation>first.generation and second.texture!=first.texture,"next generation uses alternate fixed wrapper")
	check(first.texture.texture_rd_rid==first_rid,"older wrapper RID is immutable when new generation appears")
	field.acknowledge_surface(int(first.generation));field.acknowledge_surface(int(second.generation))
	return true
func scenarios() -> void:
	if not await submit(0.0,Vector2.ZERO):return
	var emitter:={"position":Vector3(0.1875,0,0.1875),"velocity":Vector3(0,1,0),"radius":1.0,"weight":1.0,"wetness":1.0,"id":"impulse"}
	if not await submit(1.0/60.0,Vector2.ZERO,[emitter]):return
	var impulse:=await capture("01-impulse")
	# At the source centre, v=.45/60; h=v/60=.000125, independent hand calculation.
	check(absf(value(impulse,32,32)-0.000125)<0.0000001,"first GPU impulse matches hand-derived h=.000125m")
	check(value(impulse,38,32)<0.0,"vertical input has balancing negative outer ring")
	if not await submit(1.0/60.0,Vector2.ZERO,[emitter]):return
	var duplicate:=await capture("02-duplicate")
	check(impulse==duplicate,"duplicate accepted time neither injects nor ages")
	if not await submit(1.0/60.0,Vector2(0.375,0),[emitter]):return
	var remapped:=await capture("03-remap")
	check(absf(value(remapped,31,32)-value(impulse,32,32))<0.0000001,"window shifts one cell while world impulse stays fixed")
	for step in range(2,61):
		if not await submit(float(step)/60.0,Vector2(0.375,0)):return
	var propagated:=await capture("04-propagated")
	check(absf(value(propagated,35,32)-value(remapped,35,32))>0.000001,"unforced water continues propagating after input stops")
	if not await submit(0.0,Vector2.ZERO):return
	var reset:=await capture("05-rewind-reset")
	check(absf(value(reset,32,32))<0.000000001,"rewind clears old height")
	check(field.diagnostics().tick==0 and field.diagnostics().total_steps==60,"rewind resets epoch tick while lifetime step count stays explicit")
	var wake:={"stern":Vector3.ZERO,"forward":Vector2(0,-1),"beam":5.0,"speed":3.54,"wetness":1.0,"id":"dual"}
	for step in range(1,61):
		if not await submit(float(step)/60.0,Vector2.ZERO,[],[wake]):return
	var foamed:=await capture("06-dual-foam")
	var left:=0.0;var middle:=0.0;var right:=0.0
	for y in range(34,48):
		for x in range(16,48):
			var density:=value(foamed,x,y,3)
			if x<29:left+=density
			elif x>34:right+=density
			else:middle+=density
	check(left>0.05 and right>0.05,"original shape creates both lateral lobes")
	check(middle<minf(left,right)*0.25,"central plume does not replace dual-sided source")
	var before:float=receipts.back().foam_sum
	var born_centroids:=foam_centroids(foamed)
	for step in range(61,121):
		if not await submit(float(step)/60.0,Vector2.ZERO):return
	var stopped:=await capture("07-stopped-decay")
	var after:float=receipts.back().foam_sum
	check(after>0.0 and after<before,"stopped foam persists and decays instead of freezing/deleting")
	var stopped_centroids:=foam_centroids(stopped)
	check(stopped_centroids.x<born_centroids.x-0.15 and stopped_centroids.y>born_centroids.y+0.15,"left/right foam centroids continue separating after sources stop")
	publication_checks.append({"foam_birth_centroids":born_centroids,"foam_stopped_centroids":stopped_centroids})
	# A new orthogonal source is far from the old lobes. Stored old drift must not
	# rotate with the latest ship heading; measure only the old world-Z strip.
	var turned:=wake.duplicate(true);turned.stern=Vector3(0,0,-9);turned.forward=Vector2(1,0);turned.id="new-heading-far-away"
	for step in range(121,181):
		if not await submit(float(step)/60.0,Vector2.ZERO,[],[turned]):return
	var turn_history:=await capture("09-old-drift-after-turn")
	var old_centroids:=foam_centroids(turn_history)
	check(old_centroids.x<stopped_centroids.x-0.10 and old_centroids.y>stopped_centroids.y+0.10,"new ship heading does not rotate old foam drift in world history")
	check(old_centroids.z+old_centroids.w<stopped_centroids.z+stopped_centroids.w,"old-region foam decays while distant new source turns")
	publication_checks.append({"old_centroids_after_distant_turn":old_centroids})
	field.dispose()
	for i in 3:await process_frame
	field=Field.new()
	var mask:=PackedByteArray([0,0,0,0])
	check(field.configure({"resolution":64,"extent_m":24.0,"wet_mask":{"resolution":2,"bounds":Vector4(-4,-4,4,4),"data":mask}}).get("ok",false),"static R8 dry mask configures")
	if not await settle():return
	if not await submit(0.0,Vector2.ZERO):return
	var outside:=emitter.duplicate(true);outside.position=Vector3(6.1875,0,0.1875);outside.id="outside-mask-domain"
	for step in range(1,31):
		if not await submit(float(step)/60.0,Vector2.ZERO,[emitter,outside],[wake]):return
	var masked:=await capture("08-dry-mask")
	var dry_zero:=true
	for y in range(22,42):
		for x in range(22,42):
			for channel in 4:dry_zero=dry_zero and value(masked,x,y,channel)==0.0
	check(dry_zero,"dry cells block both height propagation and foam, including normals")
	check(absf(value(masked,48,32))>0.0001,"outside static mask domain remains wet")
	check(field.diagnostics().land_masked,"published diagnostics identifies terrain propagation mask")
	# QA lifetime: queued downloads may complete after dispose; callback must report stale data.
	waiting=true;callback_result={};field.request_readback(received);field.dispose()
	var start:=Time.get_ticks_msec()
	while waiting and Time.get_ticks_msec()-start<10000:await process_frame
	check(not waiting,"disposed pending readback completes without hanging")
	check(not str(callback_result.get("error","")).is_empty(),"disposed pending readback cannot claim valid pixels")
	for i in 3:
		var transient:=Field.new();transient.configure({"resolution":64,"extent_m":24.0});transient.dispose()
	for i in 4:await process_frame
