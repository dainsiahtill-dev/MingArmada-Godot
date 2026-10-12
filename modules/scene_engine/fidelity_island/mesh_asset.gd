extends RefCounted
## Converts the recovered rigid mesh stream without rebuilding topology or mip
## chains. The Geometry color stream is the original experimental FPCW037F
## nearest-even path, not Godot's ordinary color quantizer.

static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

static func float32(value: float) -> float:
	var bytes := PackedByteArray(); bytes.resize(4)
	bytes.encode_float(0, value)
	return bytes.decode_float(0)

static func geometry_color_byte(value: float) -> int:
	if not is_finite(value) or value < 0.0 or value > 1.0: return -1
	var scaled := float32(float32(value) * 255.0)
	var lower := int(floor(scaled))
	var fraction := scaled - float(lower)
	if fraction > 0.5: return lower + 1
	if fraction < 0.5: return lower
	return lower + (lower & 1)

static func pack_geometry_color_argb(rgba: Array) -> int:
	if rgba.size() != 4: return -1
	var channels: Array[int] = []
	for value: Variant in rgba:
		if not (value is int or value is float): return -1
		var channel := geometry_color_byte(float(value))
		if channel < 0: return -1
		channels.append(channel)
	return (channels[3] << 24) | (channels[0] << 16) | (channels[1] << 8) | channels[2]

static func unpack_argb(argb: int) -> Vector4:
	return Vector4(float((argb >> 16) & 255), float((argb >> 8) & 255), float(argb & 255), float((argb >> 24) & 255))

static func native_to_godot(point: Vector3) -> Vector3:
	return Vector3(point.x, point.z, -point.y)

static func texture_from_entry(entry: Dictionary) -> Texture2D:
	# BC bytes are the original compressed payload, including every original mip.
	# The decoded fallback also contains every authored mip; generate_mipmaps is
	# deliberately absent from this adapter.
	var formats := {"FORMAT_DXT1":Image.FORMAT_DXT1, "FORMAT_DXT3":Image.FORMAT_DXT3, "FORMAT_DXT5":Image.FORMAT_DXT5}
	var path := str(entry.get("compressedMipPath", ""))
	var format: int = int(formats.get(entry.get("godotCompressedImageFormat", ""), -1))
	if format < 0 or not FileAccess.file_exists(path):
		path = str(entry.get("rgbaMipPath", "")); format = Image.FORMAT_RGBA8
	if not FileAccess.file_exists(path): return null
	var image := Image.create_from_data(int(entry.get("width", 0)), int(entry.get("height", 0)), bool(entry.get("mipmaps", false)), format, FileAccess.get_file_as_bytes(path))
	if image == null or image.is_empty(): return null
	return ImageTexture.create_from_image(image)

static func surface(vertices: PackedVector3Array, normals: PackedVector3Array, uv: PackedVector2Array, indices: PackedInt32Array, packed_colors: PackedFloat32Array, adjustments: PackedFloat32Array) -> ArrayMesh:
	if vertices.is_empty() or normals.size() != vertices.size() or uv.size() != vertices.size() or indices.is_empty(): return null
	if packed_colors.size() != vertices.size() * 4 or adjustments.size() != vertices.size() * 4: return null
	var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	# CUSTOM0 holds actual RGBA bytes as float32 (not COLOR). Godot's color
	# compression / color-space path must not alter the source address or B/A.
	arrays[Mesh.ARRAY_CUSTOM0] = packed_colors
	arrays[Mesh.ARRAY_CUSTOM1] = adjustments
	var flags := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	if mesh.get_surface_count() != 1: return null
	return mesh
