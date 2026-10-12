extends RefCounted
## The same rigid horizontal mapping used by ReferenceIslandProfile.
## Native Pirates coordinates are Z-up and rows advance toward negative Y.
## No terrain heights, collider vertices or port approach are changed here.

static func _vector2(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() == 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2(NAN, NAN)

static func valid_mapping(mapping: Dictionary) -> bool:
	for key: String in ["sourceCenter", "sourceOutward", "islandCenter", "inward"]:
		if not _vector2(mapping.get(key)).is_finite():
			return false
	var scale: Variant = mapping.get("scale")
	if not (scale is float or scale is int) or not is_finite(float(scale)) or float(scale) <= 0.0:
		return false
	return absf(_vector2(mapping.sourceOutward).length_squared()-1.0) < 0.0001 and absf(_vector2(mapping.inward).length_squared()-1.0) < 0.0001

static func world_to_source_pixel(world: Vector2, mapping: Dictionary) -> Vector2:
	if not world.is_finite() or not valid_mapping(mapping):
		return Vector2(NAN, NAN)
	var inward := _vector2(mapping.inward).normalized()
	var outward := _vector2(mapping.sourceOutward).normalized()
	var across := Vector2(-inward.y, inward.x)
	var source_across := Vector2(-outward.y, outward.x)
	var offset := world - _vector2(mapping.islandCenter)
	return _vector2(mapping.sourceCenter) + (outward * offset.dot(-inward) + source_across * offset.dot(across)) / float(mapping.scale)

static func source_pixel_to_world(pixel: Vector2, mapping: Dictionary) -> Vector2:
	if not pixel.is_finite() or not valid_mapping(mapping):
		return Vector2(NAN, NAN)
	var inward := _vector2(mapping.inward).normalized()
	var outward := _vector2(mapping.sourceOutward).normalized()
	var across := Vector2(-inward.y, inward.x)
	var source_across := Vector2(-outward.y, outward.x)
	var offset := pixel - _vector2(mapping.sourceCenter)
	return _vector2(mapping.islandCenter) + (-inward * offset.dot(outward) + across * offset.dot(source_across)) * float(mapping.scale)

static func source_axes(mapping: Dictionary) -> Dictionary:
	if not valid_mapping(mapping):
		return {}
	var inward := _vector2(mapping.inward).normalized()
	var outward := _vector2(mapping.sourceOutward).normalized()
	var across := Vector2(-inward.y, inward.x)
	var source_across := Vector2(-outward.y, outward.x)
	# A native +Y normal points opposite the increasing image row.
	return {"column": -inward * outward.x + across * source_across.x,
		"row": -inward * outward.y + across * source_across.y}

static func native_direction_to_world(direction: Vector3, mapping: Dictionary) -> Vector3:
	var axes := source_axes(mapping)
	if axes.is_empty() or not direction.is_finite():
		return Vector3(NAN, NAN, NAN)
	var horizontal: Vector2 = axes.column*direction.x-axes.row*direction.y
	return Vector3(horizontal.x, direction.z, horizontal.y)

static func shader_mapping(mapping: Dictionary, width: int, height: int) -> Dictionary:
	if not valid_mapping(mapping) or width < 2 or height < 2:
		return {}
	# Derive the affine coefficients analytically in float64 scalar arithmetic.
	# Differencing two large Float32 Vector2 sample results loses texture precision.
	var inward := _vector2(mapping.inward).normalized()
	var outward := _vector2(mapping.sourceOutward).normalized()
	var across := Vector2(-inward.y, inward.x)
	var source_across := Vector2(-outward.y, outward.x)
	var scale := float(mapping.scale)
	var xx: float = (-float(inward.x)*float(outward.x)+float(across.x)*float(source_across.x))/scale
	var xz: float = (-float(inward.y)*float(outward.x)+float(across.y)*float(source_across.x))/scale
	var zx: float = (-float(inward.x)*float(outward.y)+float(across.x)*float(source_across.y))/scale
	var zz: float = (-float(inward.y)*float(outward.y)+float(across.y)*float(source_across.y))/scale
	var center := _vector2(mapping.islandCenter)
	var source_center := _vector2(mapping.sourceCenter)
	var ox: float = float(source_center.x)-xx*float(center.x)-xz*float(center.y)
	var oz: float = float(source_center.y)-zx*float(center.x)-zz*float(center.y)
	var axes := source_axes(mapping)
	return {"source_uv_row_x": Vector2(xx/float(width), xz/float(width)),
		"source_uv_row_z": Vector2(zx/float(height), zz/float(height)),
		"source_uv_offset": Vector2((ox+0.5)/float(width), (oz+0.5)/float(height)),
		"source_column_axis": axes.column, "source_row_axis": axes.row,
		"source_size": Vector2(width, height)}

static func valid_metadata(metadata: Dictionary) -> bool:
	var scale: Variant = metadata.get("effectiveScale")
	return scale is Array and scale.size() == 3 and is_finite(float(scale[0])) and is_finite(float(scale[1])) and is_finite(float(scale[2])) and float(scale[0]) > 0.0 and float(scale[1]) > 0.0 and float(scale[2]) > 0.0

static func _native_components(value: Variant) -> PackedFloat64Array:
	if value is Vector3:
		return PackedFloat64Array([value.x, value.y, value.z])
	if (value is Array or value is PackedFloat64Array) and value.size() == 3:
		var components := PackedFloat64Array()
		for axis in 3:
			if not (value[axis] is float or value[axis] is int) or not is_finite(float(value[axis])):
				return PackedFloat64Array()
			components.append(float(value[axis]))
		return components
	return PackedFloat64Array()

static func native_to_source_pixel(native: Variant, metadata: Dictionary, includes_root_translation: bool = false) -> Vector2:
	var local := _native_components(native)
	if local.size() != 3 or not valid_metadata(metadata):
		return Vector2(NAN, NAN)
	if includes_root_translation:
		var translation := _native_components(metadata.get("translation"))
		if translation.size() != 3:
			return Vector2(NAN, NAN)
		for axis in 3:
			local[axis] -= translation[axis]
	return Vector2(local[0] / float(metadata.effectiveScale[0]), -local[1] / float(metadata.effectiveScale[1]))

static func source_pixel_to_native_components(pixel: Vector2, height_index: float, metadata: Dictionary, include_root_translation: bool = false) -> PackedFloat64Array:
	if not pixel.is_finite() or not is_finite(height_index) or not valid_metadata(metadata):
		return PackedFloat64Array()
	var result := PackedFloat64Array([float(pixel.x)*float(metadata.effectiveScale[0]), -float(pixel.y)*float(metadata.effectiveScale[1]), height_index*float(metadata.effectiveScale[2])])
	if include_root_translation:
		var translation := _native_components(metadata.get("translation"))
		if translation.size() != 3:
			return PackedFloat64Array()
		for axis in 3:
			result[axis] += translation[axis]
	return result

static func source_pixel_to_native(pixel: Vector2, height_index: float, metadata: Dictionary, include_root_translation: bool = false) -> Vector3:
	var result := source_pixel_to_native_components(pixel, height_index, metadata, include_root_translation)
	if result.size() != 3:
		return Vector3(NAN, NAN, NAN)
	# Compatibility display API is intentionally quantized once to Vector3 f32.
	# Rebase with the components API before conversion when source origins are large.
	return Vector3(result[0], result[1], result[2])

static func native_to_world_xz(native: Vector3, metadata: Dictionary, mapping: Dictionary, includes_root_translation: bool = false) -> Vector2:
	return source_pixel_to_world(native_to_source_pixel(native, metadata, includes_root_translation), mapping)

static func native_to_godot(native: Vector3) -> Vector3:
	return Vector3(native.x, native.z, -native.y)

static func godot_to_native(world: Vector3) -> Vector3:
	return Vector3(world.x, -world.z, world.y)
