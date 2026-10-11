extends RefCounted
# Relative motion slab sweep; rotation subdivided exactly like source collision.ts.
static func sweep_moving_box(from: Dictionary, to: Dictionary, previous: Dictionary, current: Dictionary, box: Dictionary) -> Variant:
	var rotation = atan2(sin(current.heading - previous.heading), cos(current.heading - previous.heading))
	var pieces = maxi(1, int(ceil(absf(rotation) / 0.015)))
	for i in pieces:
		var t0 = float(i) / pieces
		var t1 = float(i + 1) / pieces
		var heading = previous.heading + rotation * ((t0 + t1) / 2.0)
		var a = _local(from, to, previous, current, t0, heading)
		var b = _local(from, to, previous, current, t1, heading)
		var minimum = [-box.length / 2.0, box.bottom, -box.width / 2.0]
		var maximum = [box.length / 2.0, box.top, box.width / 2.0]
		var entry = 0.0
		var leave = 1.0
		for axis in 3:
			var d = b[axis] - a[axis]
			if absf(d) < 1e-12:
				if a[axis] < minimum[axis] or a[axis] > maximum[axis]: entry = 2.0; break
			else:
				var p = (minimum[axis] - a[axis]) / d
				var q = (maximum[axis] - a[axis]) / d
				entry = maxf(entry, minf(p, q))
				leave = minf(leave, maxf(p, q))
		if entry <= leave and entry <= 1.0 and leave >= 0.0: return t0 + maxf(0.0, entry) / pieces
	return null
static func _local(from: Dictionary, to: Dictionary, previous: Dictionary, current: Dictionary, t: float, heading: float) -> Array:
	var dx = lerpf(from.x, to.x, t) - lerpf(previous.position.x, current.position.x, t)
	var dz = lerpf(from.z, to.z, t) - lerpf(previous.position.z, current.position.z, t)
	return [dx * cos(heading) + dz * sin(heading), lerpf(from.y, to.y, t) - lerpf(previous.position.y, current.position.y, t), -dx * sin(heading) + dz * cos(heading)]
