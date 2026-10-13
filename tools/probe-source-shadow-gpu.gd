extends SceneTree
const Backend=preload("res://modules/scene_engine/fidelity_fx/source_shadow_rd.gd")
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	print("GPU_CHECK ",label," ",ok)
	if not ok:failures+=1
func texture(device:RenderingDevice,format:int,usage:int,data:PackedByteArray)->RID:
	var desc:=RDTextureFormat.new();desc.width=64;desc.height=64;desc.format=format;desc.usage_bits=usage
	return device.texture_create(desc,RDTextureView.new(),[data])
func run()->void:
	var device:=RenderingServer.create_local_rendering_device()
	if device==null:printerr("GPU_UNAVAILABLE");quit(1);return
	print("GPU_DEVICE ",device.get_device_name()," vendor=",device.get_device_vendor_name()," api=",RenderingServer.get_current_rendering_driver_name())
	var backend:=Backend.new()
	check(backend.initialize(device),"shader compile "+backend.last_error)
	if not backend.last_error.is_empty():backend.dispose();device.free();quit(1);return
	var rgba:=PackedByteArray();rgba.resize(64*64*4);rgba.fill(255)
	var color:=texture(device,RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM,RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT|RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT,rgba)
	var depths:=PackedFloat32Array();depths.resize(64*64);depths.fill(0.5)
	var depth:=texture(device,RenderingDevice.DATA_FORMAT_R32_SFLOAT,RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT,depths.to_byte_array())
	# Counterclockwise clip-space front triangle, opposite back face, and a
	# depth-rejected back face. These isolate clamp inc/dec and receiver depth.
	var front:Dictionary={"geometry":{"positions":[[-0.8,-0.8,0.8],[0.8,-0.8,0.8],[0,0.8,0.8]],"indices":[0,1,2]}}
	var back:Dictionary={"geometry":{"positions":[[-0.8,-0.8,0.8],[0,0.8,0.8],[0.8,-0.8,0.8]],"indices":[0,1,2]}}
	var behind:Dictionary={"geometry":{"positions":[[-0.8,-0.8,0.2],[0,0.8,0.2],[0.8,-0.8,0.2]],"indices":[0,1,2]}}
	for sample in [{"name":"front increments and quad darkens","volumes":[front],"dark":true},{"name":"front back cancel","volumes":[front,back],"dark":false},{"name":"back decrement clamps zero","volumes":[back],"dark":false},{"name":"caster order preserves per caster two draws","volumes":[back,front],"dark":true},{"name":"receiver rejects far back","volumes":[front,behind],"dark":true},{"name":"empty clears prior stencil","volumes":[],"dark":false},{"name":"overlap shades once","volumes":[front,front],"dark":true}]:
		device.texture_update(color,0,rgba)
		check(backend.render(color,depth,Vector2i(64,64),Projection.IDENTITY,sample.volumes),sample.name+" draw "+backend.last_error)
		device.submit();device.sync()
		var pixels:=device.texture_get_data(color,0);var center:int=pixels[(32*64+32)*4];var corner:int=pixels[0]
		print("GPU_PIXEL ",sample.name," center=",center," corner=",corner)
		check((center>=126 and center<=129) if sample.dark else center==255,sample.name+" center")
		check(corner==255,sample.name+" outside")
	var before:Variant=backend.get("upload_count")
	backend.render(color,depth,Vector2i(64,64),Projection.IDENTITY,[front,front])
	device.submit();device.sync()
	check(before!=null and backend.get("upload_count")==before,"unchanged geometry reuses GPU buffers")
	backend.dispose();backend.dispose()
	check(backend.initialize(device),"reinitialize after disposal")
	backend.dispose();device.free_rid(color);device.free_rid(depth);device.free()
	print("SOURCE_SHADOW_GPU failures=",failures)
	quit(1 if failures else 0)
