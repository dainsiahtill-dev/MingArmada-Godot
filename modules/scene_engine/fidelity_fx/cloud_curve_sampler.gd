extends RefCounted
## Private snapshot of one immutable compiled-controller curve. Dynamic clocks
## stay with the controller. Raw and binary32 key times have distinct source uses.
const SourceMath=preload("res://modules/scene_engine/fidelity_island/native_math.gd")
var key_count:=0
var _scalar:=false
var _kind:=0
var _times:=PackedFloat64Array()
var _times32:=PackedFloat32Array()
var _values:=PackedFloat32Array()
var _backward:=PackedFloat32Array()
var _forward:=PackedFloat32Array()
var _vectors:Array=[]
var _float_store:=PackedFloat32Array([0.0])

func _init(group:Dictionary={})->void:
	var keys:Array=group.get("keys",[])
	key_count=keys.size()
	if keys.is_empty():return
	_scalar=keys[0].value is float or keys[0].value is int
	_kind=int(group.get("interpolation",0))
	for key:Dictionary in keys:
		_times.append(float(key.time));_times32.append(float(key.time))
		if _scalar:
			_values.append(float(key.value))
			if _kind==2:_backward.append(float(key.get("backward",NAN)));_forward.append(float(key.get("forward",NAN)))
		else:
			var value:Dictionary=key.value
			_vectors.append([float(value.get("x",0.0)),float(value.get("y",0.0)),float(value.get("z",0.0))])

func _f32(value:float)->float:
	_float_store[0]=value
	return _float_store[0]

func sample(time:float)->Variant:
	if key_count==0:return null
	var mapped:float=_f32(time)
	if _scalar:
		if _kind not in [1,2]:return NAN
		if mapped<=_times[0]:return _values[0]
		if mapped>=_times[-1]:return _values[-1]
		var index:=0
		while mapped>_times[index+1]:index+=1
		var t:float=_f32((mapped-_times32[index])/(_times32[index+1]-_times32[index]))
		if _kind==1:return _f32((1.0-t)*_values[index]+t*_values[index+1])
		return _f32(SourceMath.native_bezier(t,_values[index],_backward[index],_values[index+1],_forward[index+1]))
	# Native vector endpoints are unrounded doubles and freshly owned arrays.
	if mapped<=_times[0]:return _vectors[0].duplicate()
	if mapped>=_times[-1]:return _vectors[-1].duplicate()
	var index:=0
	while mapped>_times[index+1]:index+=1
	var fraction:float=_f32((mapped-_times[index])/(_times[index+1]-_times[index]))
	var a:Array=_vectors[index];var b:Array=_vectors[index+1];var result:Array=[]
	for i in 3:result.append(_f32(_f32((1.0-fraction)*float(a[i]))+_f32(fraction*float(b[i]))))
	return result
