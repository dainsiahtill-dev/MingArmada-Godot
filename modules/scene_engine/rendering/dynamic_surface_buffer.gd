extends RefCounted
## Stateless upload adapter. Callers own nodes and layouts; no global scene state.
static func layout(mesh: ArrayMesh, indices: PackedInt32Array) -> Dictionary:
	var count := mesh.surface_get_array_len(0)
	var format := int(mesh.surface_get_format(0))
	var out := {"mesh_id":mesh.get_instance_id(),"vertex_count":count,"indices":indices.duplicate(),
		"vertex_stride":RenderingServer.mesh_surface_get_format_vertex_stride(format,count),
		"attribute_stride":RenderingServer.mesh_surface_get_format_attribute_stride(format,count),
		"color_offset":RenderingServer.mesh_surface_get_format_offset(format,count,Mesh.ARRAY_COLOR),
		"uv_offset":RenderingServer.mesh_surface_get_format_offset(format,count,Mesh.ARRAY_TEX_UV)}
	var expected := Mesh.ARRAY_FORMAT_VERTEX|Mesh.ARRAY_FORMAT_COLOR|Mesh.ARRAY_FORMAT_TEX_UV|Mesh.ARRAY_FORMAT_INDEX
	out.supported = ((format & ((1 << Mesh.ARRAY_MAX)-1)) == expected
		and (format & (Mesh.ARRAY_FLAG_USE_2D_VERTICES|Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)) == 0
		and out.vertex_stride == 12 and out.attribute_stride == 12 and out.color_offset == 0 and out.uv_offset == 4)
	return out

static func bounds(vertices: PackedVector3Array) -> AABB:
	if vertices.is_empty(): return AABB()
	var low := vertices[0]
	var high := low
	for vertex: Vector3 in vertices:
		low = low.min(vertex); high = high.max(vertex)
	return AABB(low,(high-low).max(Vector3(0.00001,0.00001,0.00001)))

static func attributes(uv: PackedVector2Array, colors: PackedColorArray) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(uv.size()*12)
	for index in uv.size():
		var offset := index*12
		var color: Color = colors[index]
		# Match ArrayMesh: double multiply, clamp, truncation; float32 UV.
		data[offset] = int(clampf(color.r*255.0,0.0,255.0))
		data[offset+1] = int(clampf(color.g*255.0,0.0,255.0))
		data[offset+2] = int(clampf(color.b*255.0,0.0,255.0))
		data[offset+3] = int(clampf(color.a*255.0,0.0,255.0))
		data.encode_float(offset+4,uv[index].x)
		data.encode_float(offset+8,uv[index].y)
	return data

static func submit(node: MeshInstance3D, arrays: Array, previous: Dictionary, region_updates: bool, original_attributes: PackedByteArray = PackedByteArray()) -> Dictionary:
	var mesh := node.mesh as ArrayMesh
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var reuse: bool = (region_updates and mesh != null and not previous.is_empty() and bool(previous.supported)
		and int(previous.mesh_id) == mesh.get_instance_id() and int(previous.vertex_count) == vertices.size()
		and uv.size() == vertices.size() and colors.size() == vertices.size() and previous.indices == indices)
	var out: Dictionary
	if reuse:
		mesh.surface_update_vertex_region(0,0,vertices.to_byte_array())
		mesh.surface_update_attribute_region(0,0,original_attributes if not original_attributes.is_empty() else attributes(uv,colors))
		var local_bounds := bounds(vertices)
		if mesh.custom_aabb != local_bounds: mesh.custom_aabb = local_bounds
		out = previous
	else:
		mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
		node.mesh = mesh
		out = layout(mesh,indices)
		if region_updates and not original_attributes.is_empty() and bool(out.supported):
			mesh.surface_update_attribute_region(0,0,original_attributes)
	out.reused = reuse
	return out
