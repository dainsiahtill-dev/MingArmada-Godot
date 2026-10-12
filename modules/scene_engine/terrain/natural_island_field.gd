extends RefCounted
## Independent, cached numeric terrain. No scene, port or legacy geography input.
## Coast distance establishes shore grading; broad spines establish mountains.
## OpenSimplex2S domain warp / ridged fBm add restrained, seedable variation.
## Sources: https://docs.godotengine.org/en/stable/classes/class_fastnoiselite.html
## https://www.redblobgames.com/maps/terrain-from-noise/#islands

const DEEP_HEIGHT := -24.0
const EXTENT_SCALE := 1.8
const DEFAULTS := {"seed": 1661, "center": Vector2.ZERO, "radius": 220.0, "peak": 58.0, "resolution": 257}

var _bounds := Rect2()
var _side := 0
var _heights := PackedFloat32Array()
var _options := {}
var _diagnostics := {}

func configure(options: Dictionary = {}) -> bool:
	var accepted := DEFAULTS.duplicate()
	for key: Variant in options:
		if not DEFAULTS.has(key):
			return false
		accepted[key] = options[key]
	if not _valid_options(accepted):
		return false
	if accepted == _options:
		return true
	var radius: float = accepted.radius
	var peak: float = accepted.peak
	var seed_value: int = accepted.seed
	var side: int = accepted.resolution
	var center: Vector2 = accepted.center
	var extent := radius * EXTENT_SCALE
	var footprint := Rect2(center - Vector2.ONE * extent, Vector2.ONE * extent * 2.0)
	if not footprint.position.is_finite() or not footprint.size.is_finite():
		return false
	var coast := _noise(seed_value, FastNoiseLite.FRACTAL_FBM, 0.82, 2)
	coast.domain_warp_enabled = true
	coast.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX_REDUCED
	coast.domain_warp_amplitude = 0.12
	coast.domain_warp_frequency = 0.55
	coast.domain_warp_fractal_type = FastNoiseLite.DOMAIN_WARP_FRACTAL_PROGRESSIVE
	coast.domain_warp_fractal_octaves = 2
	coast.domain_warp_fractal_lacunarity = 2.0
	coast.domain_warp_fractal_gain = 0.4
	var detail := _noise(seed_value ^ 0x5bd1e995, FastNoiseLite.FRACTAL_RIDGED, 3.6, 3)
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var phase := random.randf_range(0.0, TAU)
	var spine_shift := random.randf_range(-0.035, 0.035)
	var heights := PackedFloat32Array()
	heights.resize(side * side)
	for row: int in side:
		for column: int in side:
			# Derive local coordinates directly, avoiding translation-dependent rounding.
			var local := Vector2(-EXTENT_SCALE + float(column) * EXTENT_SCALE * 2.0 / float(side - 1), -EXTENT_SCALE + float(row) * EXTENT_SCALE * 2.0 / float(side - 1))
			var height := _height(local, radius, peak, phase, spine_shift, coast, detail)
			if not is_finite(height):
				return false
			heights[row * side + column] = height
	var diagnostics := _measure(heights, side, footprint, peak)
	diagnostics.seed = seed_value
	diagnostics.coast_noise = "OpenSimplex2S / progressive domain warp"
	diagnostics.ridge_noise = "OpenSimplex2S / 3 octave ridged fBm"
	diagnostics.harbor_features = 0
	diagnostics.sampling = "cached Float32: bilinear or a,b,c / c,b,d triangles"
	diagnostics.generation_count = int(_diagnostics.get("generation_count", 0)) + 1
	# Commit together only after validation and a complete finite generation.
	_options = accepted
	_bounds = footprint
	_side = side
	_heights = heights
	_diagnostics = diagnostics
	return true

func bounds() -> Rect2:
	return _bounds

func get_grid() -> Dictionary:
	# Packed arrays use copy-on-write; duplicate also protects exported ownership.
	return {"bounds": _bounds, "side": _side, "heights": _heights.duplicate()}

func get_diagnostics() -> Dictionary:
	return _diagnostics.duplicate(true)

func sample_height(x: float, z: float) -> float:
	return _sample_cached(x, z, false)

func sample_triangle_height(x: float, z: float) -> float:
	## Physical height for the surface's a,b,c / c,b,d triangle diagonal.
	return _sample_cached(x, z, true)

func _sample_cached(x: float, z: float, triangles: bool) -> float:
	if _side < 2 or not is_finite(x) or not is_finite(z):
		return NAN
	if x < _bounds.position.x or z < _bounds.position.y or x > _bounds.end.x or z > _bounds.end.y:
		return DEEP_HEIGHT
	var gx := (x - _bounds.position.x) * float(_side - 1) / _bounds.size.x
	var gz := (z - _bounds.position.y) * float(_side - 1) / _bounds.size.y
	# Knot snapping preserves exact Float32 geometry even after float arithmetic.
	if absf(gx - roundf(gx)) < 0.000000001:
		gx = roundf(gx)
	if absf(gz - roundf(gz)) < 0.000000001:
		gz = roundf(gz)
	var column := mini(int(floor(gx)), _side - 2)
	var row := mini(int(floor(gz)), _side - 2)
	var fx := gx - float(column)
	var fz := gz - float(row)
	var a := row * _side + column
	if triangles:
		if fx + fz <= 1.0:
			return _heights[a] + (_heights[a + 1] - _heights[a]) * fx + (_heights[a + _side] - _heights[a]) * fz
		var d := a + _side + 1
		return _heights[d] + (_heights[a + _side] - _heights[d]) * (1.0 - fx) + (_heights[a + 1] - _heights[d]) * (1.0 - fz)
	return lerpf(lerpf(_heights[a], _heights[a + 1], fx), lerpf(_heights[a + _side], _heights[a + _side + 1], fx), fz)

func _valid_options(options: Dictionary) -> bool:
	if typeof(options.seed) != TYPE_INT or options.seed < -2147483648 or options.seed > 2147483647:
		return false
	if typeof(options.center) != TYPE_VECTOR2 or not options.center.is_finite():
		return false
	if not _finite_number(options.radius) or options.radius < 1.0 or options.radius > 100000.0:
		return false
	if not _finite_number(options.peak) or options.peak < 8.0 or options.peak > options.radius:
		return false
	return typeof(options.resolution) == TYPE_INT and options.resolution >= 17 and options.resolution <= 1025

func _finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))

func _noise(seed_value: int, fractal: int, frequency: float, octaves: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = fractal
	noise.frequency = frequency
	noise.fractal_octaves = octaves
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.42
	return noise

func _height(local: Vector2, radius: float, peak: float, phase: float, spine_shift: float, coast: FastNoiseLite, detail: FastNoiseLite) -> float:
	# Low-amplitude smooth displacement keeps broad headlands and a connected core.
	var warped := local + Vector2(coast.get_noise_2d(local.x, local.y), coast.get_noise_2d(local.x + 9.7, local.y - 5.1)) * 0.035
	var ellipse := Vector2(warped.x, warped.y / 0.8)
	var angle := atan2(ellipse.y, ellipse.x)
	var boundary := 1.0 + 0.060 * sin(2.0 * angle + phase) + 0.055 * cos(3.0 * angle - phase * 0.7)
	boundary += 0.115 * _angular_bump(angle, -2.6 + phase * 0.10, 0.36)
	boundary += 0.075 * _angular_bump(angle, 0.45 + phase * 0.07, 0.42)
	boundary -= 0.105 * _angular_bump(angle, 1.30 + phase * 0.08, 0.38)
	var distance := (boundary - ellipse.length()) * radius * 0.8
	if distance <= 0.0:
		var offshore := -distance / radius
		return -3.0 * smoothstep(0.0, 0.09, offshore) - 21.0 * smoothstep(0.06, 0.43, offshore)
	var inland := distance / radius
	var beach := 2.2 * smoothstep(0.0, 0.055, inland)
	var midlands := 6.2 * smoothstep(0.025, 0.30, inland)
	var spine_z := -0.025 + spine_shift + 0.105 * sin((warped.x + 0.32) * 3.6)
	var spine_cross := exp(-pow((warped.y - spine_z) / 0.225, 2.0))
	var spine_ends := exp(-pow(warped.x / 0.79, 4.0))
	var spine_lift := 0.57 + 0.29 * exp(-pow((warped.x + 0.22) / 0.29, 2.0)) + 0.15 * exp(-pow((warped.x - 0.38) / 0.30, 2.0))
	var ridge := spine_cross * spine_ends * spine_lift
	var branch_distance := _segment_distance(warped, Vector2(-0.27, 0.035), Vector2(-0.67, -0.30))
	var branch := 0.32 * exp(-pow(branch_distance / 0.19, 2.0))
	var mountain_mask := smoothstep(0.05, 0.26, inland)
	var broad_mountain := maxf(ridge, branch) * peak * 0.87
	# Detail remains ~1 m, well below broad ridge relief; no noisy shoreline band.
	var fine_relief := detail.get_noise_2d(warped.x, warped.y) * peak * 0.021 * sqrt(maxf(ridge, 0.0))
	return minf(peak, beach + midlands + mountain_mask * (broad_mountain + fine_relief))

func _angular_bump(angle: float, center: float, width: float) -> float:
	return exp(-pow(wrapf(angle - center, -PI, PI) / width, 2.0))

func _segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var segment := b - a
	var amount := clampf((point - a).dot(segment) / segment.length_squared(), 0.0, 1.0)
	return point.distance_to(a + segment * amount)

func _measure(heights: PackedFloat32Array, side: int, footprint: Rect2, peak: float) -> Dictionary:
	var minimum := INF
	var maximum := -INF
	var land := 0
	var midland := 0
	var mountain := 0
	var coast_crossings := 0
	var coast_closed := true
	var max_gradient := 0.0
	var max_triangle_error := 0.0
	var step := footprint.size.x / float(side - 1)
	for row: int in side:
		for column: int in side:
			var index := row * side + column
			var height: float = heights[index]
			minimum = minf(minimum, height)
			maximum = maxf(maximum, height)
			if height > 0.0:
				land += 1
			if height > 5.0 and height < 25.0:
				midland += 1
			if height > peak * (35.0 / 58.0):
				mountain += 1
			if column == 0 or row == 0 or column == side - 1 or row == side - 1:
				coast_closed = coast_closed and height == DEEP_HEIGHT
			if column < side - 1 and (height > 0.0) != (heights[index + 1] > 0.0):
				coast_crossings += 1
			if row < side - 1 and (height > 0.0) != (heights[index + side] > 0.0):
				coast_crossings += 1
			if row < side - 1 and column < side - 1:
				# Bilinear minus triangle is this cross-corner term times u*v or
				# (1-u)*(1-v), whose maximum on either triangle is exactly 1/4.
				var saddle: float = absf(height + heights[index + side + 1] - heights[index + 1] - heights[index + side]) * 0.25
				max_triangle_error = maxf(max_triangle_error, saddle)
			if column > 0 and row > 0 and column < side - 1 and row < side - 1:
				var dx := (heights[index + 1] - heights[index - 1]) / (2.0 * step)
				var dz := (heights[index + side] - heights[index - side]) / (2.0 * step)
				max_gradient = maxf(max_gradient, sqrt(dx * dx + dz * dz))
	var connected := _land_components(heights, side)
	return {"samples": heights.size(), "side": side, "min_height": minimum, "max_height": maximum, "land_samples": land, "midland_samples": midland, "mountain_samples": mountain, "mountain_land_fraction": float(mountain) / maxi(land, 1), "coastline_crossings": coast_crossings, "coastline_length": float(coast_crossings) * step * PI / 4.0, "coast_closed": coast_closed, "land_components": connected.count, "largest_land_fraction": float(connected.largest) / maxi(land, 1), "max_gradient": max_gradient, "max_bilinear_triangle_error": max_triangle_error}

func _land_components(heights: PackedFloat32Array, side: int) -> Dictionary:
	var visited := PackedByteArray()
	visited.resize(heights.size())
	var count := 0
	var largest := 0
	for first: int in heights.size():
		if heights[first] <= 0.0 or visited[first]:
			continue
		count += 1
		var queue := PackedInt32Array([first])
		visited[first] = 1
		var cursor := 0
		while cursor < queue.size():
			var current: int = queue[cursor]
			cursor += 1
			for neighbor: int in [current - side, current + side, current - 1, current + 1]:
				if neighbor < 0 or neighbor >= heights.size() or visited[neighbor] or heights[neighbor] <= 0.0:
					continue
				if absi(neighbor - current) == 1 and neighbor / side != current / side:
					continue
				visited[neighbor] = 1
				queue.append(neighbor)
		largest = maxi(largest, queue.size())
	return {"count": count, "largest": largest}
