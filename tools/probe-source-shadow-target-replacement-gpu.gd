extends "res://tools/probe-source-shadow-gpu.gd"

func sized_texture(device:RenderingDevice,side:int,format:int,usage:int,data:PackedByteArray)->RID:
	var desc:=RDTextureFormat.new();desc.width=side;desc.height=side;desc.format=format;desc.usage_bits=usage
	return device.texture_create(desc,RDTextureView.new(),[data])

func run()->void:
	var device:=RenderingServer.create_local_rendering_device()
	if device==null:printerr("GPU_UNAVAILABLE");quit(1);return
	print("GPU_DEVICE ",device.get_device_name()," api=",RenderingServer.get_current_rendering_driver_name())
	var backend:=Backend.new();check(backend.initialize(device),"initialize")
	var rgba:=PackedByteArray();rgba.resize(64*64*4);rgba.fill(255)
	var depths:=PackedFloat32Array();depths.resize(64*64);depths.fill(0.5)
	var depth:=texture(device,RenderingDevice.DATA_FORMAT_R32_SFLOAT,RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT,depths.to_byte_array())
	var color:=texture(device,RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM,RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT,rgba)
	var front:Dictionary={"geometry":{"positions":[[-0.8,-0.8,0.8],[0.8,-0.8,0.8],[0,0.8,0.8]],"indices":[0,1,2]}}
	var sizes:Array[int]=[64,96,32,64]
	for replacement in 4:
		var side:int=sizes[replacement]
		check(backend.render(color,depth,Vector2i(side,side),Projection.IDENTITY,[front]),"target draw %d size%d"%[replacement,side])
		device.submit();device.sync()
		var center:int=device.texture_get_data(color,0)[(int(side/2)*side+int(side/2))*4]
		check(center>=126 and center<=129,"replacement pixel %d"%replacement)
		var old_framebuffer:RID=backend.get("_framebuffer")
		device.free_rid(color)
		check(old_framebuffer.is_valid() and not device.framebuffer_is_valid(old_framebuffer),"external color free auto-invalidates framebuffer, RID token stays nonzero")
		if replacement<3:
			var next_side:int=sizes[replacement+1]
			rgba.resize(next_side*next_side*4);rgba.fill(255)
			color=sized_texture(device,next_side,RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM,RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT,rgba)
			device.free_rid(depth);depths.resize(next_side*next_side);depths.fill(0.5)
			depth=sized_texture(device,next_side,RenderingDevice.DATA_FORMAT_R32_SFLOAT,RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT,depths.to_byte_array())
	# Disposal must also tolerate target destruction preceding owner teardown.
	backend.dispose();backend.dispose();device.free_rid(depth);device.free()
	print("SOURCE_SHADOW_TARGET_REPLACEMENT_GPU failures=",failures)
	quit(1 if failures else 0)
