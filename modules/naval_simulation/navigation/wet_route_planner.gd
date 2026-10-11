extends RefCounted
# One shared million-sample budget includes endpoints, shortcuts, edges and smoothing.
var remaining = 1000000
var exceeded = false
var radius = 0.0
var _hull: Dictionary
var _sample: Callable
var _sea = 0.0
var _start: Dictionary
func plan(start: Dictionary, target: Dictionary, hull: Dictionary, sample: Callable, sea_level: float = 0.0) -> Dictionary:
	remaining = 1000000
	exceeded = false
	radius = _hypot(hull.length, hull.width) / 2.0 + 8
	_hull = hull; _sample = sample; _sea = sea_level; _start = start
	if not [start.x, start.z, target.x, target.z, hull.length, hull.width, hull.draft, sea_level, radius].all(func(v): return is_finite(v)) or hull.length <= 0 or hull.width <= 0 or hull.draft <= 0 or radius > 128: return _fail("invalid-route-input")
	var distance = _distance(target, start)
	if not is_finite(distance) or distance > 2048 or [start.x, start.z, target.x, target.z].any(func(v): return absf(v) > 1e7): return _fail("route-distance-limit")
	if not _wet(start) or not _wet(target): return _fail("unsafe-endpoint")
	if _segment(start, target): return {"ok": true, "points": [target.duplicate(true)]}
	var root = {"x": 0, "z": 0, "g": 0.0}
	var open = [root]
	var best = {"0,0": 0.0}
	var expanded = 0
	while not open.is_empty() and expanded < 4096 and not exceeded:
		expanded += 1
		# ECMAScript Array.sort is stable; Godot sort_custom is not. Keep equal
		# candidate order, including the source comparator's arithmetic order.
		for sort_index in range(1, open.size()):
			var candidate = open[sort_index]
			var slot = sort_index
			while slot > 0 and candidate.g + _distance(_point(candidate), target) - open[slot - 1].g - _distance(_point(open[slot - 1]), target) < 0:
				open[slot] = open[slot - 1]; slot -= 1
			open[slot] = candidate
		var node = open.pop_front()
		var p = _point(node)
		if _distance(p, target) < 64 and _segment(p, target):
			var path = [target.duplicate(true)]
			var n = node
			while n.has("parent"): path.push_front(_point(n)); n = n.parent
			var simplified = []
			var from = start
			var i = 0
			while i < path.size() and not exceeded:
				var end = i
				while end + 1 < path.size() and _segment(from, path[end + 1]): end += 1
				simplified.append(path[end]); from = path[end]; i = end + 1
			return _fail("route-sample-budget") if exceeded else {"ok": true, "points": simplified}
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				if dx == 0 and dz == 0: continue
				var x = node.x + dx
				var z = node.z + dz
				var g = node.g + _hypot(dx, dz) * 32
				var key = str(x) + "," + str(z)
				if absi(x) > 32 or absi(z) > 32 or g >= best.get(key, INF) or best.size() >= 4096: continue
				var next = {"x": x, "z": z, "g": g, "parent": node}
				if not _segment(p, _point(next)): continue
				best[key] = g; open.append(next)
	return _fail("route-sample-budget" if exceeded else "no-safe-route")
func _wet(p: Dictionary) -> bool:
	var x = -radius
	while x <= radius:
		var z = -radius
		while z <= radius:
			if x * x + z * z <= radius * radius:
				remaining -= 1
				if remaining < 0: exceeded = true; return false
				var h = _sample.call(p.x + x, p.z + z)
				if not is_finite(h) or h >= _sea - _hull.draft: return false
			z += 4.0
		x += 4.0
	return true
func _segment(a: Dictionary, b: Dictionary) -> bool:
	var n = ceil(_distance(a, b) / 4.0)
	if not is_finite(n) or n > 512: exceeded = true; return false
	for i in int(n) + 1:
		if not _wet({"x": a.x + (b.x - a.x) * i / maxf(1, n), "z": a.z + (b.z - a.z) * i / maxf(1, n)}): return false
	return true
func _point(node: Dictionary) -> Dictionary: return {"x": _start.x + node.x * 32, "z": _start.z + node.z * 32}
func _hypot(x: float, z: float) -> float:
	var maximum = maxf(absf(x), absf(z))
	if maximum == 0: return 0.0
	return sqrt(pow(x / maximum, 2) + pow(z / maximum, 2)) * maximum
func _distance(a: Dictionary, b: Dictionary) -> float: return _hypot(a.x - b.x, a.z - b.z)
func _fail(reason: String) -> Dictionary: return {"ok": false, "reason": "route-sample-budget" if exceeded else reason}
