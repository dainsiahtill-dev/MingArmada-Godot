extends RefCounted
## Main-thread facade. One executing request + one latest snapshot, stable texture.
const Backend = preload("res://modules/scene_engine/water/interactive_wake_field_rd.gd")
var _backend: RefCounted
var _textures: Array[Texture2DRD] = [Texture2DRD.new(),Texture2DRD.new()]
var _slot := 0
var _generation := 0
var _awaiting_ack := false
var _surface: Dictionary = {}
var _options: Dictionary = {}
var _epoch := 0
var _in_flight := false
var _queued: Dictionary = {}
var _disposed := false
var _coalesced := 0
var _snapshot := {"ready":false,"pending":false,"error":"","time":0.0,"tick":0,"resolution":256,"extent_m":96.0,
	"window_origin":Vector2.ZERO,"bounds":Vector4.ZERO,"steps":0,"remaps":0,"resets":0,"emitter_count":0,"wake_count":0,
	"texture_count":0,"resource_count":0,"dropped_steps":0,"queue_coalesced":0,"land_masked":false,"disposed":false}
func configure(options: Dictionary = {}) -> Dictionary:
	if _disposed:return {"ok":false,"error":"Field disposed"}
	if _backend!=null:return {"ok":false,"error":"Dispose before reconfiguration"}
	_options={"resolution":256,"extent_m":96.0,"fixed_step":1.0/60.0,"wave_speed":1.2,"height_limit":0.25,
		"damping":0.35,"foam_decay":0.214,"foam_diffusion":0.04,"flow":Vector2.ZERO,"edge_cells":12.0,"edge_damping":4.0,"activity_foam":0.08,"wet_mask":{},
		"foam_drift_speed":0.5,"foam_drift_decay":0.18,"foam_source_rate":2.5}
	for key in options:
		if _options.has(key):_options[key]=options[key]
	for key in _options:
		if key=="flow" or key=="wet_mask":continue
		if not (_options[key] is float or _options[key] is int) or not is_finite(float(_options[key])):
			return {"ok":false,"error":"Invalid field option: "+str(key)}
	if not _options.flow is Vector2 or not _options.flow.is_finite():return {"ok":false,"error":"Invalid ambient flow"}
	if not _valid_mask(_options.wet_mask):return {"ok":false,"error":"Invalid wet_mask R8 data or world bounds"}
	var n:=int(_options.resolution)
	if n<16 or n>512 or n%8!=0 or n!=float(_options.resolution) or _options.extent_m<=0.0 or _options.fixed_step<1.0/240.0 or _options.fixed_step>1.0/15.0 or _options.height_limit<=0.0:
		return {"ok":false,"error":"Invalid grid, extent, step or height limit"}
	for key in ["damping","foam_decay","foam_diffusion","edge_damping","activity_foam","wave_speed","foam_drift_speed","foam_drift_decay","foam_source_rate"]:
		if _options[key]<0.0:return {"ok":false,"error":"Negative field option: "+key}
	var dx:=float(_options.extent_m)/n
	_options.wave_speed=minf(float(_options.wave_speed),0.7*dx/float(_options.fixed_step))
	_options.foam_diffusion=minf(float(_options.foam_diffusion),0.24*dx*dx/float(_options.fixed_step))
	_snapshot.resolution=n;_snapshot.extent_m=_options.extent_m
	if DisplayServer.get_name()=="headless":
		_snapshot.error="Global RenderingDevice unavailable in headless mode";return {"ok":false,"pending":false,"error":_snapshot.error}
	var shape:=_load_shape()
	if shape.is_empty():_snapshot.error="Original wake3unique DDS mask unavailable";return {"ok":false,"error":_snapshot.error}
	_backend=Backend.new();_in_flight=true;_snapshot.pending=true
	RenderingServer.call_on_render_thread(_backend.initialize.bind(_options.duplicate(true),shape,_published.bind(_epoch)))
	return {"ok":true,"pending":true,"options":_options.duplicate(true)}
func _valid_mask(mask: Variant) -> bool:
	if not mask is Dictionary:return false
	if mask.is_empty():return true
	if not mask.get("resolution") is int or mask.resolution<=0 or mask.resolution>4096:return false
	if not mask.get("bounds") is Vector4 or not mask.bounds.is_finite():return false
	if mask.bounds.z<=mask.bounds.x or mask.bounds.w<=mask.bounds.y:return false
	return mask.get("data") is PackedByteArray and mask.data.size()==mask.resolution*mask.resolution
func _load_shape() -> Dictionary:
	# Decode source bytes on CPU: no main-thread Texture.get_image/GPU download.
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/source_wake/texture-manifest.json"))
	for entry: Dictionary in manifest.get("textures",[]):
		if entry.get("name","")!="wake3unique.dds":continue
		var formats: Dictionary={"DXT1":Image.FORMAT_DXT1,"DXT3":Image.FORMAT_DXT3,"DXT5":Image.FORMAT_DXT5}
		var image:=Image.create_from_data(int(entry.width),int(entry.height),bool(entry.mipmaps),formats[entry.format],FileAccess.get_file_as_bytes(entry.payload))
		if image.decompress()!=OK:return {}
		image.clear_mipmaps();image.convert(Image.FORMAT_RGBA8)
		return {"size":Vector2i(image.get_width(),image.get_height()),"data":image.get_data()}
	return {}
func _valid_emitter(item: Variant) -> bool:
	if not item is Dictionary:return false
	for key in ["position","velocity"]:
		if not item.get(key) is Vector3 or not item[key].is_finite():return false
	for key in ["radius","wetness","weight"]:
		if not (item.get(key) is float or item.get(key) is int) or not is_finite(float(item[key])):return false
	return item.radius>0.0 and item.wetness>=0.0 and item.wetness<=1.0 and item.get("id") is String
func _valid_wake(item: Variant) -> bool:
	if not item is Dictionary or not item.get("stern") is Vector3 or not item.stern.is_finite():return false
	if not item.get("forward") is Vector2 or not item.forward.is_finite() or item.forward.length_squared()<0.000001:return false
	for key in ["beam","speed","wetness"]:
		if not (item.get(key) is float or item.get(key) is int) or not is_finite(float(item[key])):return false
	return item.beam>0.0 and item.speed>=0.0 and item.wetness>=0.0 and item.wetness<=1.0 and item.get("id") is String
func prepare_request(seconds: float, center: Vector2, emitters: Array, wakes: Array) -> Dictionary:
	if not is_finite(seconds) or absf(seconds)>1e12 or not center.is_finite():return {"error":"Time outside supported +/-1e12 seconds or invalid window"}
	for item in emitters:
		if not _valid_emitter(item):return {"error":"Invalid emitter; snapshot rejected atomically"}
	for item in wakes:
		if not _valid_wake(item):return {"error":"Invalid wake; snapshot rejected atomically"}
	var es:=emitters.duplicate(true);var ws:=wakes.duplicate(true)
	es.sort_custom(func(a,b):
		var da:=Vector2(a.position.x,a.position.z).distance_squared_to(center);var db:=Vector2(b.position.x,b.position.z).distance_squared_to(center)
		return str(a.id)<str(b.id) if da==db else da<db)
	ws.sort_custom(func(a,b):
		var da:=Vector2(a.stern.x,a.stern.z).distance_squared_to(center);var db:=Vector2(b.stern.x,b.stern.z).distance_squared_to(center)
		return str(a.id)<str(b.id) if da==db else da<db)
	es=es.slice(0,16);ws=ws.slice(0,4)
	var selected_e: Array=[];var selected_w: Array=[]
	for item: Dictionary in es:selected_e.append(item.id)
	for item: Dictionary in ws:item.forward=item.forward.normalized();selected_w.append(item.id)
	return {"seconds":seconds,"center":center,"emitters":es,"wakes":ws,"selected_emitters":selected_e,"selected_wakes":selected_w,
		"omitted_emitters":maxi(0,emitters.size()-16),"omitted_wakes":maxi(0,wakes.size()-4)}
func advance(seconds: float, center: Vector2, emitters: Array, wakes: Array = []) -> Dictionary:
	if _disposed or _backend==null:return diagnostics()
	var request:=prepare_request(seconds,center,emitters,wakes)
	if request.has("error"):
		var rejected:=diagnostics();rejected.input_error=request.error;return rejected
	if _in_flight or _awaiting_ack:
		if not _queued.is_empty():_coalesced+=1
		_queued=request;return diagnostics()
	_dispatch(request);return diagnostics()
func _dispatch(request: Dictionary) -> void:
	_in_flight=true;_snapshot.pending=true
	RenderingServer.call_on_render_thread(_backend.advance.bind(request,_published.bind(_epoch)))
func _published(receipt: Dictionary, epoch: int) -> void:
	if _disposed or epoch!=_epoch:return
	# Each slot's wrapper binds one immutable RID for its entire resource lifetime.
	# No next output is written until the consumer acknowledges the complete pair.
	if receipt.ready:
		_slot=int(receipt.output_index)
		if not _textures[_slot].texture_rd_rid.is_valid():_textures[_slot].texture_rd_rid=receipt.output_rid
		_generation+=1;_awaiting_ack=true
		_surface={"texture":_textures[_slot],"bounds":receipt.bounds,"generation":_generation,"time":receipt.time}
	receipt.erase("output_rid");_snapshot=receipt.duplicate(true);_snapshot.pending=false
	_snapshot.queue_coalesced=_coalesced;_in_flight=false
func acquire_surface() -> Dictionary:
	return _surface.duplicate() if _snapshot.ready and not _disposed else {}
func acknowledge_surface(generation: int) -> void:
	if _disposed or not _awaiting_ack or generation!=_generation:return
	_awaiting_ack=false
	if not _queued.is_empty() and _snapshot.error.is_empty():
		var request:=_queued;_queued={};_dispatch(request)
func surface_texture() -> Texture2D:return _textures[_slot]
func surface_bounds() -> Vector4:return _snapshot.bounds
func diagnostics() -> Dictionary:
	var result:=_snapshot.duplicate(true);result.pending=_in_flight;result.queue_coalesced=_coalesced
	result.awaiting_ack=_awaiting_ack;result.queued=not _queued.is_empty();result.generation=_generation
	return result
func request_readback(callback: Callable) -> void:
	if not _snapshot.ready or _disposed:
		callback.call_deferred({"error":"Field not ready","data":PackedByteArray()});return
	RenderingServer.call_on_render_thread(_backend.request_readback.bind(callback,diagnostics(),_textures[_slot].texture_rd_rid))
func dispose() -> void:
	if _disposed:return
	_disposed=true;_epoch+=1;_queued={};_in_flight=false;_awaiting_ack=false;_surface={}
	for texture in _textures:texture.texture_rd_rid=RID()
	_snapshot.ready=false;_snapshot.pending=false;_snapshot.disposed=true
	_snapshot.cleanup_pending=_backend!=null
	if _backend!=null:RenderingServer.call_on_render_thread(_backend.dispose.bind(_cleanup_finished.bind(_epoch)))
func _cleanup_finished(receipt: Dictionary, epoch: int) -> void:
	if not _disposed or epoch!=_epoch:return
	_snapshot.resource_count=receipt.resource_count;_snapshot.texture_count=receipt.texture_count;_snapshot.cleanup_pending=false
