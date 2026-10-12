extends RefCounted
## Source-bound 54FFE0 / 57F750 / 547DF0 semantic ports. Explicit binary32
## stores follow the confirmed JavaScript oracle; no general x87 emulator claim.

static func f32(value: float) -> float:
	var bytes := PackedByteArray()
	bytes.resize(4)
	bytes.encode_float(0, value)
	return bytes.decode_float(0)

class ControllerClock extends RefCounted:
	var controller: Dictionary
	var last := 0.0
	var accumulated := 0.0
	var started := false

	static func f32(value: float) -> float:
		var bytes := PackedByteArray()
		bytes.resize(4)
		bytes.encode_float(0,value)
		return bytes.decode_float(0)

	func _init(value: Dictionary) -> void:
		controller = value.duplicate(true)

	func reset() -> void:
		last = 0.0
		accumulated = 0.0
		started = false

	func advance(app_time: float) -> float:
		var c: Dictionary = controller
		var now: float = f32(app_time)
		var flags: int = int(c.get("flags", 0))
		var delta: float = now-last if started else (0.0 if flags & 1 else now)
		var sum: float = delta*float(c.get("frequency", 1.0))+accumulated
		accumulated = f32(sum)
		last = now
		started = true
		var raw: float = f32(sum+float(c.get("phase", 0.0)))
		var start: float = f32(float(c.get("start_time", 0.0)))
		var stop: float = f32(float(c.get("stop_time", 0.0)))
		var span: float = f32(stop-start)
		var cycle: int = (flags >> 1) & 3
		var mapped: float = raw
		if cycle == 0:
			if span == 0.0:
				mapped = start
			else:
				mapped = fmod(raw-start,span)+start
				if mapped < start: mapped += span
		elif cycle == 1:
			if span == 0.0:
				mapped = start
			else:
				var twice: float = f32(span+span)
				mapped = fmod(raw,twice)
				if mapped < 0.0: mapped += twice
				if mapped > span: mapped = twice-mapped
				mapped += start
		mapped = clampf(mapped,start,stop)
		if flags & 16: mapped = stop-(mapped-start)
		return mapped

static func native_bezier(t: float, left: float, outgoing: float, right: float, incoming: float) -> float:
	return (((outgoing+incoming-(right-left+right-left))*t+(right-left)*3.0-(outgoing+outgoing+incoming))*t+outgoing)*t+left

static func interpolate_float_keys(group: Dictionary, time: float) -> float:
	var mapped: float = f32(time)
	var keys: Array = group.get("keys", [])
	var kind: int = int(group.get("interpolation", 0))
	if keys.is_empty() or kind not in [1,2]: return NAN
	if mapped <= float(keys[0].time): return f32(float(keys[0].value))
	if mapped >= float(keys[-1].time): return f32(float(keys[-1].value))
	var index := 0
	while mapped > float(keys[index+1].time): index += 1
	var left: Dictionary = keys[index]
	var right: Dictionary = keys[index+1]
	var t: float = f32((mapped-f32(float(left.time)))/(f32(float(right.time))-f32(float(left.time))))
	if kind == 1: return f32((1.0-t)*f32(float(left.value))+t*f32(float(right.value)))
	return f32(native_bezier(t,f32(float(left.value)),f32(float(left.backward)),f32(float(right.value)),f32(float(right.forward))))

static func evaluate_float_controller(controller: Dictionary, group: Dictionary, app_time: float, epoch: float = 0.0) -> float:
	if (int(controller.get("flags",0)) & 8) == 0: return NAN
	var clock := ControllerClock.new(controller)
	if int(controller.flags) & 1: clock.advance(epoch)
	return interpolate_float_keys(group,clock.advance(app_time))

static func texture_transform(desc: Dictionary, overrides: Dictionary = {}) -> PackedFloat32Array:
	var kind: int = int(desc.get("transform_type", -1))
	if kind not in [0,1]: return PackedFloat32Array()
	var translation: Dictionary = desc.get("translation", {})
	var scale: Dictionary = desc.get("tiling", desc.get("scale", {}))
	var center: Dictionary = desc.get("center_offset", desc.get("center", {}))
	var tu: float = float(overrides.get("translationU",translation.get("u",0.0)))
	var tv: float = float(overrides.get("translationV",translation.get("v",0.0)))
	var su: float = float(overrides.get("scaleU",scale.get("u",1.0)))
	var sv: float = float(overrides.get("scaleV",scale.get("v",1.0)))
	var cu: float = float(center.get("u",0.0))
	var cv: float = float(center.get("v",0.0))
	var angle: float = float(overrides.get("rotation",desc.get("w_rotation",desc.get("rotation",0.0))))
	var c: float = f32(cos(angle))
	var s: float = f32(sin(angle))
	if kind == 0:
		return PackedFloat32Array([c*su,s*su,0.0,-s*sv,c*sv,0.0,f32(tu-cu)*c-(tv-cv)*s+cu,(tu-cu)*s+(tv-cv)*c+cv,1.0])
	return PackedFloat32Array([c*su,-s*sv,0.0,s*su,c*sv,0.0,su*(f32(-cu-tu)*c+(tv-cv)*s)+cu,sv*((tv-cv)*c-f32(-cu-tu)*s)+cv,1.0])

static func texture_basis(matrix: PackedFloat32Array) -> Basis:
	if matrix.size() != 9: return Basis.IDENTITY
	return Basis(Vector3(matrix[0],matrix[1],matrix[2]),Vector3(matrix[3],matrix[4],matrix[5]),Vector3(matrix[6],matrix[7],matrix[8]))
