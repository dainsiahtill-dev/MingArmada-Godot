extends RefCounted

var _texture: ImageTexture
var _coast_texture: ImageTexture
var _bounds := Vector4.ZERO

func configure(height_sampler: Callable, bounds: Rect2, resolution: int = 256) -> bool:
	if not height_sampler.is_valid() or not bounds.size.is_finite() or not bounds.position.is_finite() or bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return false
	var size := clampi(resolution, 16, 1024)
	var heights := PackedFloat32Array()
	heights.resize(size * size)
	for row in size:
		var z := bounds.position.y + bounds.size.y * float(row) / (size - 1)
		for column in size:
			var x := bounds.position.x + bounds.size.x * float(column) / (size - 1)
			var value: Variant = height_sampler.call(x, z)
			if not (value is float or value is int) or not is_finite(value):
				return false
			heights[row * size + column] = value
	var height_image := Image.create_from_data(size, size, false, Image.FORMAT_RF, heights.to_byte_array())
	var distances := PackedFloat32Array()
	distances.resize(size * size)
	distances.fill(1.0e6)
	var dx := bounds.size.x / (size - 1)
	var dz := bounds.size.y / (size - 1)
	var diagonal := sqrt(dx * dx + dz * dz)
	# Coast means a real land/water crossing. A submerged sandbank may tint the
	# water turquoise, but must not manufacture a circular white surf outline.
	for row in size:
		for column in size:
			var i := row * size + column
			var dry := heights[i] >= 0.0
			if column > 0 and (heights[i - 1] >= 0.0) != dry or row > 0 and (heights[i - size] >= 0.0) != dry:
				distances[i] = 0.0
	for row in size:
		for column in size:
			var i := row * size + column
			if column > 0: distances[i] = minf(distances[i], distances[i - 1] + dx)
			if row > 0: distances[i] = minf(distances[i], distances[i - size] + dz)
			if column > 0 and row > 0: distances[i] = minf(distances[i], distances[i - size - 1] + diagonal)
			if column < size - 1 and row > 0: distances[i] = minf(distances[i], distances[i - size + 1] + diagonal)
	for row in range(size - 1, -1, -1):
		for column in range(size - 1, -1, -1):
			var i := row * size + column
			if column < size - 1: distances[i] = minf(distances[i], distances[i + 1] + dx)
			if row < size - 1: distances[i] = minf(distances[i], distances[i + size] + dz)
			if column < size - 1 and row < size - 1: distances[i] = minf(distances[i], distances[i + size + 1] + diagonal)
			if column > 0 and row < size - 1: distances[i] = minf(distances[i], distances[i + size - 1] + diagonal)
	var coast_image := Image.create_from_data(size, size, false, Image.FORMAT_RF, distances.to_byte_array())
	_coast_texture = ImageTexture.create_from_image(coast_image)
	_texture = ImageTexture.create_from_image(height_image)
	_bounds = Vector4(bounds.position.x, bounds.position.y, bounds.end.x, bounds.end.y)
	return true

func get_texture() -> Texture2D:
	return _texture

func get_bounds() -> Vector4:
	return _bounds

func get_coast_texture() -> Texture2D:
	return _coast_texture
