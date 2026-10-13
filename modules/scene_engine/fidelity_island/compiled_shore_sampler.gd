extends RefCounted
## Prepared absolute-time shore sampling. Original native_math remains the oracle.
## Cache immutable descriptors and key stores; never accumulate frame deltas.
const Native = preload("res://modules/scene_engine/fidelity_island/native_math.gd")
var _sources: Array[Dictionary] = []
var _curves: Dictionary = {}
var _rounding := PackedFloat32Array()
var _matrix := PackedFloat32Array()
var texture_matrix := Basis.IDENTITY
var alpha_phase := 0.0

func _f32(value: float) -> float:
	# The same binary32 store/load without two byte-buffer native method calls.
	_rounding[0]=value
	return _rounding[0]

func configure(source: Dictionary) -> bool:
	_sources.clear(); _curves.clear(); _rounding.resize(1); _matrix.resize(9)
	for name: String in ["translation","scale","alpha"]:
		var group: Dictionary = source.get("curves",{}).get(name,{})
		var kind: int = int(group.get("interpolation",0))
		if kind not in [1,2] or group.get("keys",[]).is_empty(): return false
		var keys: Array[PackedFloat64Array] = []
		for key: Dictionary in group.keys:
			# Raw time remains the comparison boundary; binary32 time/value/tangents
			# retain the exact stores used by Native.interpolate_float_keys.
			keys.append(PackedFloat64Array([float(key.time),_f32(float(key.time)),_f32(float(key.value)),_f32(float(key.get("backward",0.0))),_f32(float(key.get("forward",0.0)))]))
		var coefficients: Array[PackedFloat64Array] = []
		for i in keys.size()-1:
			var left: float=keys[i][2]; var outgoing: float=keys[i][3]
			var right: float=keys[i+1][2]; var incoming: float=keys[i+1][4]
			# Cache independent terms separately: combining A-B here would change
			# the oracle's ((c0*t+A)-B) double-precision expression tree.
			coefficients.append(PackedFloat64Array([outgoing+incoming-(right-left+right-left),(right-left)*3.0,outgoing+outgoing+incoming]))
		_curves[name] = {"kind":kind,"keys":keys,"coefficients":coefficients}
	for mesh: Dictionary in source.get("meshes",[]):
		var controllers: Dictionary = mesh.get("controllers",{})
		var prepared: Dictionary = {}
		for name: String in ["translation","scale","alpha"]:
			var clock: Dictionary = controllers.get(name,{})
			var flags: int = int(clock.get("flags",0))
			if flags & 8 == 0: return false
			var start: float = _f32(float(clock.get("start_time",0.0)))
			var stop: float = _f32(float(clock.get("stop_time",0.0)))
			var span: float = _f32(stop-start)
			prepared[name] = PackedFloat64Array([flags,float(clock.get("frequency",1.0)),float(clock.get("phase",0.0)),start,stop,span,_f32(span+span)])
		prepared.shared_scale_alpha = prepared.scale == prepared.alpha
		var desc: Dictionary = mesh.get("texture",{})
		var kind: int = int(desc.get("transform_type",-1))
		if kind not in [0,1]: return false
		var center: Dictionary = desc.get("center_offset",desc.get("center",{}))
		var scale: Dictionary = desc.get("tiling",desc.get("scale",{}))
		var angle: float = float(desc.get("w_rotation",desc.get("rotation",0.0)))
		prepared.texture = PackedFloat64Array([kind,float(desc.get("translation",{}).get("v",0.0)),float(scale.get("v",1.0)),float(center.get("u",0.0)),float(center.get("v",0.0)),_f32(cos(angle)),_f32(sin(angle))])
		_sources.append(prepared)
	return not _sources.is_empty()

func _mapped(clock: PackedFloat64Array,now: float) -> float:
	# This is the oracle's fresh/reset clock at absolute time (epoch zero).
	# Its accumulated binary32 store is not read before the first result: raw
	# uses the original double sum, then stores sum+phase, exactly as Native.
	var flags: int = int(clock[0])
	var sum: float = now*clock[1]
	_rounding[0]=sum+clock[2]
	var raw: float = _rounding[0]
	var start: float = clock[3]; var stop: float = clock[4]; var span: float = clock[5]
	var cycle: int = (flags >> 1) & 3
	var mapped: float = raw
	if cycle == 0:
		mapped = start if span == 0.0 else fmod(raw-start,span)+start
		if mapped < start: mapped += span
	elif cycle == 1:
		if span == 0.0: mapped = start
		else:
			var twice: float = clock[6]
			mapped = fmod(raw,twice)
			if mapped < 0.0: mapped += twice
			if mapped > span: mapped = twice-mapped
			mapped += start
	mapped = clampf(mapped,start,stop)
	if flags & 16: mapped = stop-(mapped-start)
	return mapped

func _interpolate(group: Dictionary,time: float) -> float:
	_rounding[0]=time
	var mapped: float = _rounding[0]
	var keys: Array[PackedFloat64Array] = group.keys
	if mapped <= keys[0][0]: return keys[0][2]
	if mapped >= keys[-1][0]: return keys[-1][2]
	var index := 0
	while mapped > keys[index+1][0]: index += 1
	var left: PackedFloat64Array = keys[index]; var right: PackedFloat64Array = keys[index+1]
	_rounding[0]=(mapped-left[1])/(right[1]-left[1])
	var t: float = _rounding[0]
	if int(group.kind) == 1:
		_rounding[0]=(1.0-t)*left[2]+t*right[2]
		return _rounding[0]
	var coefficients: PackedFloat64Array = group.coefficients[index]
	_rounding[0]=((coefficients[0]*t+coefficients[1]-coefficients[2])*t+left[3])*t+left[2]
	return _rounding[0]

func _texture(desc: PackedFloat64Array,tu: float,su: float) -> void:
	var kind: int = int(desc[0]); var tv: float = desc[1]; var sv: float = desc[2]
	var cu: float = desc[3]; var cv: float = desc[4]; var c: float = desc[5]; var s: float = desc[6]
	# Reuse storage, with the same binary32 matrix stores and expression order.
	_matrix[0]=c*su; _matrix[2]=0.0; _matrix[5]=0.0; _matrix[8]=1.0
	if kind == 0:
		_matrix[1]=s*su; _matrix[3]=-s*sv; _matrix[4]=c*sv
		_rounding[0]=tu-cu
		_matrix[6]=_rounding[0]*c-(tv-cv)*s+cu
		_matrix[7]=(tu-cu)*s+(tv-cv)*c+cv
	else:
		_matrix[1]=-s*sv; _matrix[3]=s*su; _matrix[4]=c*sv
		_rounding[0]=-cu-tu
		var term: float = _rounding[0]
		_matrix[6]=su*(term*c+(tv-cv)*s)+cu
		_matrix[7]=sv*((tv-cv)*c-term*s)+cv
	texture_matrix = Basis(Vector3(_matrix[0],_matrix[1],_matrix[2]),Vector3(_matrix[3],_matrix[4],_matrix[5]),Vector3(_matrix[6],_matrix[7],_matrix[8]))

func sample(index: int,time: float) -> Dictionary:
	# Public sampling keeps fresh, independently owned outputs. The live surf
	# consumer supplies its already allocated per-patch state below.
	var state: Dictionary = {}
	sample_into(index,time,state)
	return state

func sample_into(index: int,time: float,state: Dictionary) -> void:
	var prepared: Dictionary = _sources[index]
	_rounding[0]=time
	var now: float = _rounding[0]
	var translation_time: float = _mapped(prepared.translation,now)
	var alpha_time: float = _mapped(prepared.alpha,now)
	var scale_time: float = alpha_time if prepared.shared_scale_alpha else _mapped(prepared.scale,now)
	state.translationU = _interpolate(_curves.translation,translation_time)
	state.scaleU = _interpolate(_curves.scale,scale_time)
	state.alpha = _interpolate(_curves.alpha,alpha_time)
	var alpha_clock: PackedFloat64Array = prepared.alpha
	alpha_phase = (alpha_time-alpha_clock[3])/(alpha_clock[4]-alpha_clock[3])
	_texture(prepared.texture,float(state.translationU),float(state.scaleU))
