extends RefCounted
## CPU-only interface mask from an already sampled vertex-height lattice.
## Conservative relative to these lattice cells, not unsampled terrain peaks.
static func build(heights:Variant,side:int,bounds:Rect2)->Dictionary:
	if side<2 or side>4097:return {"valid":false,"error":"height lattice side must be2..4097"}
	if not heights is PackedFloat32Array or heights.size()!=side*side:return {"valid":false,"error":"height lattice data size/type mismatch"}
	if not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size.x<=0.0 or bounds.size.y<=0.0 or not bounds.end.is_finite():return {"valid":false,"error":"invalid world bounds"}
	for height:float in heights:
		if not is_finite(height):return {"valid":false,"error":"nonfinite terrain height"}
	var resolution:=side-1
	var data:=PackedByteArray();data.resize(resolution*resolution)
	for row in resolution:
		for column in resolution:
			var offset:=row*side+column
			var maximum:=maxf(maxf(heights[offset],heights[offset+1]),maxf(heights[offset+side],heights[offset+side+1]))
			data[row*resolution+column]=255 if maximum<0.0 else 0
	var domain:=Vector4(bounds.position.x,bounds.position.y,bounds.end.x,bounds.end.y)
	var digest:=HashingContext.new();digest.start(HashingContext.HASH_SHA256)
	digest.update("terrain-wet-mask-v1".to_utf8_buffer())
	digest.update(PackedFloat64Array([resolution,domain.x,domain.y,domain.z,domain.w]).to_byte_array())
	digest.update(data)
	return {"valid":true,"resolution":resolution,"bounds":domain,"data":data,"cell_m":bounds.size/float(resolution),"digest":digest.finish().hex_encode()}
