extends SceneTree

const FIELD_PATH := "res://modules/scene_engine/terrain/natural_island_field.gd"
var assertions := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, reason: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL: ", reason)

func _finish() -> void:
	print("NATURAL_ISLAND_FIELD_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)

func _run() -> void:
	check(ResourceLoader.exists(FIELD_PATH), "independent numeric island field exists")
	if not ResourceLoader.exists(FIELD_PATH):
		_finish()
		return
	var field_script: Script = load(FIELD_PATH)
	var field: RefCounted = field_script.new()
	check(is_nan(field.sample_height(0.0, 0.0)), "unconfigured field returns missing height")
	var options := {"seed": 1661, "center": Vector2.ZERO, "radius": 220.0, "peak": 58.0, "resolution": 129}
	check(field.configure(options), "valid deterministic island configures")
	var grid: Dictionary = field.get_grid()
	var footprint: Rect2 = field.bounds()
	var side: int = grid.side
	var heights: PackedFloat32Array = grid.heights.duplicate()
	check(grid.bounds == footprint and side == 129 and heights.size() == side * side, "complete cached grid supplies geometry extent and dimensions")
	check(footprint.position == Vector2(-396.0, -396.0) and footprint.size == Vector2(792.0, 792.0), "geometry spans island, graded seabed and deep margin")
	var finite := true
	var edges_deep := true
	var minimum := INF
	var maximum := -INF
	var land_count := 0
	var midland_count := 0
	var mountain_count := 0
	var max_index := 0
	for index: int in heights.size():
		var height: float = heights[index]
		finite = finite and is_finite(height)
		minimum = minf(minimum, height)
		if height > maximum:
			maximum = height
			max_index = index
		if height > 0.0:
			land_count += 1
		if height > 5.0 and height < 25.0:
			midland_count += 1
		if height > 35.0:
			mountain_count += 1
		var row := index / side
		var column := index % side
		if row == 0 or column == 0 or row == side - 1 or column == side - 1:
			edges_deep = edges_deep and height == -24.0
	check(finite and minimum == -24.0 and maximum >= 40.0 and maximum <= 58.0, "all heights finite with deep seabed and graded mountain peaks")
	check(edges_deep, "every geometry border finishes on deep seabed")
	check(midland_count > land_count * 0.25, "raised midlands occupy meaningful land area")
	check(mountain_count > land_count * 0.10, "mountains cover broad area rather than isolated needles")
	check(_largest_land_component(heights, side) == land_count, "natural coast encloses one connected island without wet channels")
	var broad_peak_nodes := 0
	var peak_row := max_index / side
	var peak_column := max_index % side
	for row: int in range(peak_row - 3, peak_row + 4):
		for column: int in range(peak_column - 3, peak_column + 4):
			if row >= 0 and column >= 0 and row < side and column < side and heights[row * side + column] > maximum * 0.75:
				broad_peak_nodes += 1
	check(broad_peak_nodes >= 30, "highest ridge retains a broad shoulder at grid scale")
	var raised_core := true
	for z: int in range(-80, 81, 20):
		for x: int in range(-110, 111, 20):
			raised_core = raised_core and field.sample_height(float(x), float(z)) > 3.0
	check(raised_core, "central interior has continuous raised ground")
	var step: float = footprint.size.x / float(side - 1)
	var exact_knots := true
	for index: int in [0, 1, side - 1, side * (side / 2) + side / 2, side * side - 1]:
		var x: float = footprint.position.x + float(index % side) * step
		var z: float = footprint.position.y + float(index / side) * step
		exact_knots = exact_knots and field.sample_height(x, z) == heights[index]
	check(exact_knots, "sampler preserves exact cached Float32 mesh knots including closed border")
	var a := 62 * side + 58
	var expected: float = heights[a] * 0.1875 + heights[a + 1] * 0.0625 + heights[a + side] * 0.5625 + heights[a + side + 1] * 0.1875
	var query_x: float = footprint.position.x + 58.25 * step
	var query_z: float = footprint.position.y + 62.75 * step
	check(absf(field.sample_height(query_x, query_z) - expected) < 0.000001, "interior sampler uses bilinear interpolation of the same four cached corners")
	check(is_nan(field.sample_height(NAN, 0.0)) and is_nan(field.sample_height(0.0, INF)), "nonfinite queries return missing height")
	check(field.sample_height(-396.001, 0.0) == -24.0 and field.sample_height(0.0, 396.001) == -24.0, "finite outside geometry continues deep seabed")
	check(field.has_method("sample_triangle_height"), "numeric field supplies actual mesh triangle height without renderer dependency")
	if field.has_method("sample_triangle_height"):
		var lower_expected: float = heights[a] * 0.5 + heights[a + 1] * 0.2 + heights[a + side] * 0.3
		var upper_expected: float = heights[a + side + 1] * 0.5 + heights[a + side] * 0.2 + heights[a + 1] * 0.3
		check(absf(field.sample_triangle_height(footprint.position.x + 58.2 * step, footprint.position.y + 62.3 * step) - lower_expected) < 0.000001, "lower triangle uses independently weighted a b c cached vertices")
		check(absf(field.sample_triangle_height(footprint.position.x + 58.8 * step, footprint.position.y + 62.7 * step) - upper_expected) < 0.000001, "upper triangle uses independently weighted c b d cached vertices")
		check(field.sample_triangle_height(-396.0, -396.0) == -24.0 and field.sample_triangle_height(396.0, 396.0) == -24.0, "triangle sampler includes closed border knots")
		check(field.sample_triangle_height(-397.0, 0.0) == -24.0 and is_nan(field.sample_triangle_height(NAN, 0.0)) and is_nan(field.sample_triangle_height(0.0, INF)), "triangle sampler retains seabed outside and missing nonfinite input")
	grid.heights[0] = 500.0
	check(field.sample_height(-396.0, -396.0) == -24.0, "caller cannot mutate accepted height cache through grid export")
	var repeat: RefCounted = field_script.new()
	check(repeat.configure(options) and repeat.get_grid().heights == heights, "same seed and options reproduce exact full grid")
	check(repeat.configure({"seed": 1662, "resolution": 129}), "different seed configures")
	check(repeat.get_grid().heights != heights and absf(repeat.sample_height(120.0, 75.0) - field.sample_height(120.0, 75.0)) > 0.01, "seed changes actual height values and coast detail")
	var accepted: Dictionary = field.get_grid()
	for invalid: Dictionary in [{"radius": -1.0}, {"radius": INF}, {"radius": "220"}, {"peak": NAN}, {"peak": 0.0}, {"center": Vector2(INF, 0.0)}, {"center": Vector3.ZERO}, {"resolution": 8}, {"resolution": 129.5}, {"seed": 1.5}, {"port_channel": true}]:
		check(not field.configure(invalid), "malformed config rejected before cache replacement: " + str(invalid))
		check(field.get_grid() == accepted, "failed configuration leaves accepted geometry intact")
	var diagnostics: Dictionary = field.get_diagnostics()
	check(diagnostics.seed == 1661 and diagnostics.land_samples == land_count and diagnostics.mountain_samples == mountain_count, "diagnostics report accepted numeric generation")
	check(diagnostics.coast_closed and diagnostics.land_components == 1 and diagnostics.harbor_features == 0, "diagnostics expose closed organic coast with no harbor geometry")
	check(diagnostics.max_gradient < 1.5, "cached terrain has no steep ring or high frequency spikes")
	check(field.configure(options) and field.get_diagnostics().generation_count == 1, "reapplying accepted configuration does not regenerate cache")
	diagnostics.seed = 999
	check(field.get_diagnostics().seed == 1661, "exported diagnostics cannot mutate accepted state")
	var coast_radii := PackedFloat32Array()
	var beach_and_shelf := true
	for angle_index: int in 24:
		var direction := Vector2.from_angle(float(angle_index) * TAU / 24.0)
		var low := 0.0
		var high := 330.0
		for iteration: int in 18:
			var middle := (low + high) * 0.5
			var position := direction * middle
			if field.sample_height(position.x, position.y) > 0.0:
				low = middle
			else:
				high = middle
		coast_radii.append(low)
		var beach := direction * (low - 7.0)
		var shelf := direction * (high + 15.0)
		var deep := direction * (high + 120.0)
		beach_and_shelf = beach_and_shelf and field.sample_height(beach.x, beach.y) > 0.0 and field.sample_height(beach.x, beach.y) < 5.0
		beach_and_shelf = beach_and_shelf and field.sample_height(shelf.x, shelf.y) < -0.1 and field.sample_height(shelf.x, shelf.y) > -10.0
		beach_and_shelf = beach_and_shelf and field.sample_height(deep.x, deep.y) <= -23.0
	coast_radii.sort()
	check(coast_radii[-1] - coast_radii[0] > 30.0, "coastline has broad headlands and bays")
	check(beach_and_shelf, "all sampled coast directions retain beach, shallow shelf and deep water transition")
	var translated: RefCounted = field_script.new()
	check(translated.configure({"seed": 1661, "center": Vector2(510.0, -730.0), "resolution": 129}), "numeric field supports translated center without scene nodes")
	check(translated.get_grid().heights == heights and translated.sample_height(530.0, -715.0) == field.sample_height(20.0, 15.0), "translation preserves local terrain and cached sampling")
	var weak: WeakRef = weakref(translated)
	translated = null
	check(weak.get_ref() == null, "numeric field has no retained scene node or shared resource ownership")
	var full_field: RefCounted = field_script.new()
	check(full_field.configure(), "default visual field configures full 257 grid")
	var full_grid: Dictionary = full_field.get_grid()
	var full_metrics: Dictionary = full_field.get_diagnostics()
	check(full_grid.side == 257 and full_grid.heights.size() == 66049 and full_metrics.land_components == 1 and full_metrics.coast_closed, "default geometry spans complete connected land and deep rim")
	var maximum_triangle_error := _maximum_triangle_difference(full_grid.heights, full_grid.side)
	check(maximum_triangle_error < 0.25, "default bilinear field stays within 25 cm of cached mesh triangles")
	check(absf(float(full_metrics.get("max_bilinear_triangle_error", INF)) - maximum_triangle_error) < 0.000001, "cached diagnostics report conservative bilinear versus triangle error")
	for seed_value: int in [1, -8, 2147483647, -2147483648]:
		check(repeat.configure({"seed": seed_value, "resolution": 65}), "integer boundary seed configures: " + str(seed_value))
		var seeded_metrics: Dictionary = repeat.get_diagnostics()
		check(seeded_metrics.land_components == 1 and seeded_metrics.coast_closed and is_finite(seeded_metrics.max_height), "different deterministic seed retains finite connected island")
	print("NATURAL_ISLAND_METRICS ", JSON.stringify(full_field.get_diagnostics()))
	_finish()

func _maximum_triangle_difference(heights: PackedFloat32Array, side: int) -> float:
	# At cell center, bilinear uses four equal weights; either diagonal uses two.
	# This cross-corner difference also bounds error everywhere inside that cell.
	var maximum := 0.0
	for row: int in side - 1:
		for column: int in side - 1:
			var index := row * side + column
			var difference: float = absf(heights[index] + heights[index + side + 1] - heights[index + 1] - heights[index + side]) * 0.25
			maximum = maxf(maximum, difference)
	return maximum

func _largest_land_component(heights: PackedFloat32Array, side: int) -> int:
	var visited := PackedByteArray()
	visited.resize(heights.size())
	var largest := 0
	for first: int in heights.size():
		if heights[first] <= 0.0 or visited[first]:
			continue
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
	return largest
