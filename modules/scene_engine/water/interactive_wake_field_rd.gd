extends RefCounted
## Render-thread-only GPU owner. No submit/sync: this uses the GLOBAL device.
const HEIGHT_PATH := "res://modules/scene_engine/water/interactive_wake_height.glsl"
const FOAM_PATH := "res://modules/scene_engine/water/interactive_wake_foam.glsl"
var options: Dictionary = {}
var device: RenderingDevice
var resources: Array[RID] = []
var height: Array[RID] = []
var foam: Array[RID] = []
var outputs: Array[RID] = []
var height_sets: Array[RID] = []
var foam_sets: Array[RID] = []
var height_shader := RID()
var foam_shader := RID()
var height_pipeline := RID()
var foam_pipeline := RID()
var source_buffer := RID()
var state_index := 0
var output_index := 0
var time := NAN
var accumulator := 0.0
var origin := Vector2.ZERO
var tick := 0
var total_steps := 0
var remaps := 0
var resets := 0
var dropped_steps := 0
var disposed := false
var readbacks := 0
var error := ""
var cleanup_callback := Callable()

func keep(rid: RID) -> RID:
	if rid.is_valid(): resources.append(rid)
	return rid
func make_texture(format: int, bytes: PackedByteArray, size: Vector2i, storage: bool = true) -> RID:
	var description := RDTextureFormat.new()
	description.width=size.x; description.height=size.y; description.format=format
	description.usage_bits=RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT|RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	if storage:description.usage_bits|=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	return keep(device.texture_create(description,RDTextureView.new(),[bytes]))
func compile_shader(path: String) -> RID:
	var source := RDShaderSource.new()
	source.source_compute=FileAccess.get_file_as_string(path).replace("#[compute]", "")
	var spirv := device.shader_compile_spirv_from_source(source)
	var message := spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not message.is_empty(): error=path+": "+message; return RID()
	return keep(device.shader_create_from_spirv(spirv))
func uniform(kind: int, binding: int, ids: Array[RID]) -> RDUniform:
	var result := RDUniform.new(); result.uniform_type=kind; result.binding=binding
	for id in ids: result.add_id(id)
	return result
func initialize(settings: Dictionary, shape: Dictionary, callback: Callable) -> void:
	if disposed: return
	options=settings.duplicate(true); device=RenderingServer.get_rendering_device()
	if device==null: error="Global RenderingDevice unavailable"; callback.call_deferred(receipt()); return
	height_shader=compile_shader(HEIGHT_PATH); foam_shader=compile_shader(FOAM_PATH)
	if not error.is_empty(): callback.call_deferred(receipt()); return
	height_pipeline=keep(device.compute_pipeline_create(height_shader)); foam_pipeline=keep(device.compute_pipeline_create(foam_shader))
	var size := Vector2i(options.resolution,options.resolution)
	var zero_h := PackedByteArray(); zero_h.resize(size.x*size.y*8)
	var zero_f := PackedByteArray(); zero_f.resize(size.x*size.y*16)
	var zero_o := PackedByteArray(); zero_o.resize(size.x*size.y*16)
	for i in 2:
		height.append(make_texture(RenderingDevice.DATA_FORMAT_R32G32_SFLOAT,zero_h,size))
		foam.append(make_texture(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT,zero_f,size))
		outputs.append(make_texture(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT,zero_o,size))
	var zero_sources := PackedByteArray(); zero_sources.resize(960)
	source_buffer=keep(device.storage_buffer_create(960,zero_sources))
	var shape_texture := make_texture(RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM,shape.data,shape.size,false)
	var mask: Dictionary=options.get("wet_mask",{})
	var mask_size:=int(mask.get("resolution",1))
	var mask_texture:=make_texture(RenderingDevice.DATA_FORMAT_R8_UNORM,mask.get("data",PackedByteArray([255])),Vector2i(mask_size,mask_size),false)
	var sampler_state := RDSamplerState.new()
	sampler_state.min_filter=RenderingDevice.SAMPLER_FILTER_LINEAR; sampler_state.mag_filter=RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.repeat_u=RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE; sampler_state.repeat_v=RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	var sampler := keep(device.sampler_create(sampler_state))
	sampler_state.min_filter=RenderingDevice.SAMPLER_FILTER_NEAREST;sampler_state.mag_filter=RenderingDevice.SAMPLER_FILTER_NEAREST
	var mask_sampler:=keep(device.sampler_create(sampler_state))
	for i in 2:
		height_sets.append(keep(device.uniform_set_create([
			uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,0,[height[i]]), uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,1,[height[1-i]]),
			uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,2,[source_buffer]),
			uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE,3,[mask_sampler,mask_texture])],height_shader,0)))
		for out in 2:
			foam_sets.append(keep(device.uniform_set_create([
				uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,0,[foam[i]]), uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,1,[foam[1-i]]),
				uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,2,[height[1-i]]),uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,3,[outputs[out]]),
				uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,4,[source_buffer]),
				uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE,5,[sampler,shape_texture]),
				uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE,6,[mask_sampler,mask_texture])],foam_shader,0)))
	for rid in height_sets+foam_sets:
		if not rid.is_valid(): error="Could not allocate field uniform sets"
	callback.call_deferred(receipt())

func plan_advance(request: Dictionary) -> Dictionary:
	# Pure clock/window planning also exercised headlessly. GPU execution consumes this result.
	var seconds := float(request.seconds)
	if not is_finite(seconds) or absf(seconds)>1e12 or float(options.fixed_step)<1.0/240.0 or float(options.fixed_step)>1.0/15.0:
		return {"error":"Unsupported time or fixed step; state unchanged"}
	var dx := float(options.extent_m)/float(options.resolution)
	var next_origin: Vector2 = (request.center/ dx).floor()*dx-Vector2.ONE*float(options.extent_m)*0.5
	var reset: bool = is_nan(time) or seconds<time or next_origin.distance_to(origin)>float(options.extent_m)*0.5
	var previous := origin
	var steps := 0
	if reset:
		accumulator=0.0; resets+=1;tick=0
	else:
		accumulator+=maxf(0.0,seconds-time)
		var available := floori((accumulator+0.00000001)/float(options.fixed_step))
		steps=mini(8,available); dropped_steps+=maxi(0,available-steps)
		accumulator-=available*float(options.fixed_step)
		accumulator=maxf(0.0,accumulator)
	if next_origin!=origin: remaps+=1
	time=seconds; origin=next_origin; tick+=steps; total_steps+=steps
	return {"old_origin":previous,"origin":origin,"reset":reset,"steps":steps,"remainder":accumulator,"seconds":seconds}

func push_constants(plan: Dictionary, dt: float, offset: float, emitter_count: int, wake_count: int, reset: bool) -> PackedByteArray:
	var old: Vector2=plan.old_origin; var now: Vector2=plan.origin
	var dx := float(options.extent_m)/float(options.resolution)
	var flow: Vector2=options.flow
	var mask: Dictionary=options.get("wet_mask",{})
	var bounds: Vector4=mask.get("bounds",Vector4(0,0,1,1))
	var values := PackedFloat32Array([old.x,old.y,now.x,now.y,float(options.resolution),dx,dt,float(options.wave_speed),
		float(options.damping),float(options.height_limit),2.0,float(options.foam_decay),flow.x,flow.y,float(options.foam_diffusion),float(options.edge_cells),
		0,0,0,0,offset,float(options.activity_foam),float(options.edge_damping),0,bounds.x,bounds.y,bounds.z,bounds.w])
	var bytes := values.to_byte_array()
	bytes.encode_s32(64,emitter_count); bytes.encode_s32(68,wake_count); bytes.encode_s32(72,1 if reset else 0)
	bytes.encode_s32(76,0 if mask.is_empty() else 1)
	return bytes
func pack_sources(emitters: Array, wakes: Array) -> PackedByteArray:
	var packed := PackedFloat32Array(); packed.resize(240)
	for i in emitters.size():
		var item: Dictionary=emitters[i]; var pos: Vector3=item.position; var vel: Vector3=item.velocity; var at := i*12
		packed[at]=pos.x;packed[at+1]=pos.y;packed[at+2]=pos.z;packed[at+3]=item.radius
		packed[at+4]=vel.x;packed[at+5]=vel.y;packed[at+6]=vel.z;packed[at+7]=item.wetness;packed[at+8]=item.weight
	for i in wakes.size():
		var item: Dictionary=wakes[i]; var pos: Vector3=item.stern; var forward: Vector2=item.forward; var at := 192+i*12
		packed[at]=pos.x;packed[at+1]=pos.z;packed[at+2]=forward.x;packed[at+3]=forward.y
		packed[at+4]=item.beam;packed[at+5]=item.speed;packed[at+6]=item.wetness
	return packed.to_byte_array()
func advance(request: Dictionary, callback: Callable) -> void:
	if disposed: return
	if device==null or not error.is_empty(): callback.call_deferred(receipt()); return
	var plan := plan_advance(request)
	if plan.has("error"):
		var rejected:=receipt();rejected.error=plan.error;callback.call_deferred(rejected);return
	if plan.steps==0 and not plan.reset and plan.old_origin==plan.origin:
		# Exact paused output, avoiding even +/-zero churn and redundant GPU commands.
		callback.call_deferred(receipt());return
	var sources := pack_sources(request.emitters,request.wakes)
	device.buffer_update(source_buffer,0,sources.size(),sources)
	output_index=1-output_index
	var list := device.compute_list_begin()
	var count := maxi(1,int(plan.steps))
	for i in count:
		var dt := float(options.fixed_step) if plan.steps>0 else 0.0
		var offset := float(count-1-i)*dt+float(plan.remainder)
		var constants := push_constants(plan,dt,offset,request.emitters.size(),request.wakes.size(),bool(plan.reset) and i==0)
		device.compute_list_bind_compute_pipeline(list,height_pipeline)
		device.compute_list_bind_uniform_set(list,height_sets[state_index],0)
		device.compute_list_set_push_constant(list,constants,constants.size())
		device.compute_list_dispatch(list,int(options.resolution)/8,int(options.resolution)/8,1)
		device.compute_list_add_barrier(list)
		device.compute_list_bind_compute_pipeline(list,foam_pipeline)
		device.compute_list_bind_uniform_set(list,foam_sets[state_index*2+output_index],0)
		# Height kernel stays112 bytes; foam alone adds persistent visual-drift controls.
		var dx:=float(options.extent_m)/float(options.resolution)
		var drift_speed:=minf(float(options.foam_drift_speed),0.5*dx/float(options.fixed_step))
		var foam_constants:=constants.duplicate()
		foam_constants.append_array(PackedFloat32Array([drift_speed,float(options.foam_drift_decay),float(options.foam_source_rate),minf(0.08,0.24*dx*dx/float(options.fixed_step))]).to_byte_array())
		device.compute_list_set_push_constant(list,foam_constants,foam_constants.size())
		device.compute_list_dispatch(list,int(options.resolution)/8,int(options.resolution)/8,1)
		device.compute_list_add_barrier(list)
		state_index=1-state_index; plan.old_origin=plan.origin
	device.compute_list_end()
	var result := receipt()
	result.steps=plan.steps;result.emitter_count=request.emitters.size();result.wake_count=request.wakes.size()
	result.selected_emitters=request.selected_emitters;result.selected_wakes=request.selected_wakes
	result.omitted_emitters=request.omitted_emitters;result.omitted_wakes=request.omitted_wakes
	callback.call_deferred(result)
func receipt() -> Dictionary:
	var extent := float(options.get("extent_m",96.0))
	return {"ready":device!=null and error.is_empty() and not disposed and outputs.size()==2,"error":error,"disposed":disposed,
		"time":0.0 if is_nan(time) else time,"tick":tick,"total_steps":total_steps,"resolution":options.get("resolution",256),"extent_m":extent,
		"window_origin":origin,"bounds":Vector4(origin.x,origin.y,origin.x+extent,origin.y+extent),
		"steps":0,"remaps":remaps,"resets":resets,"emitter_count":0,"wake_count":0,"dropped_steps":dropped_steps,
		"texture_count":8 if not resources.is_empty() else 0,"resource_count":resources.size(),"land_masked":not options.get("wet_mask",{}).is_empty(),
		"output_rid":outputs[output_index] if outputs.size()==2 else RID(),"output_index":output_index,"format":"rgba32f"}
func request_readback(callback: Callable, snapshot: Dictionary, output_rid: RID) -> void:
	if disposed or device==null or not output_rid.is_valid():
		callback.call_deferred({"error":"Field disposed or unavailable","data":PackedByteArray()});return
	if readbacks>0:
		callback.call_deferred({"error":"One QA readback already pending","data":PackedByteArray()});return
	readbacks+=1
	var status := device.texture_get_data_async(output_rid,0,_readback_finished.bind(callback,snapshot))
	if status!=OK:
		readbacks-=1; callback.call_deferred({"error":"GPU readback request failed: "+str(status),"data":PackedByteArray()})
func _readback_finished(bytes: PackedByteArray, callback: Callable, snapshot: Dictionary) -> void:
	# Callback thread is not assumed; all device lifetime changes stay on render thread.
	RenderingServer.call_on_render_thread(_finish_readback_render.bind(bytes,callback,snapshot))
func _finish_readback_render(bytes: PackedByteArray, callback: Callable, snapshot: Dictionary) -> void:
	var result := {"error":"" if not disposed else "Field disposed during readback","data":bytes if not disposed else PackedByteArray(),
		"resolution":snapshot.resolution,"format":"rgba32f","bounds":snapshot.bounds,"diagnostics":snapshot.duplicate(true)}
	readbacks-=1; callback.call_deferred(result)
	if disposed and readbacks==0: free_resources()
func dispose(callback: Callable = Callable()) -> void:
	if disposed:return
	disposed=true;cleanup_callback=callback
	if readbacks==0: free_resources()
func free_resources() -> void:
	if device!=null:
		for i in range(resources.size()-1,-1,-1): device.free_rid(resources[i])
	resources.clear();height.clear();foam.clear();outputs.clear();height_sets.clear();foam_sets.clear()
	if cleanup_callback.is_valid():
		cleanup_callback.call_deferred(receipt());cleanup_callback=Callable()
