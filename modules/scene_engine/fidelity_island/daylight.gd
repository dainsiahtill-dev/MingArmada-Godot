extends RefCounted
## Exact authored TimeOfDay keys plus confirmed source float-store layout.
## Does not modify the formal game's sun, environment, fog or gameplay clock.

const Native = preload("res://modules/scene_engine/fidelity_island/native_math.gd")
const Asset = preload("res://modules/scene_engine/fidelity_island/mesh_asset.gd")
const SOURCE_PATH := "res://assets/data/fidelity_island/timeofday-original.json"
const WEIGHTS := [0.1184634417295456,0.23931433260440826,0.2844444513320923,0.23931433260440826,0.1184634417295456]
const POINTS := [0.04691007733345032,0.23076534271240234,0.5,0.7692346572875977,0.9530898928642273]

static func _vec(value: Dictionary) -> Array:
	return [Native.f32(float(value.x)),Native.f32(float(value.y)),Native.f32(float(value.z))]

static func vector_coefficients(group: Dictionary) -> Array:
	if int(group.get("interpolation",0)) != 2: return []
	var keys: Array = group.get("keys",[])
	var result: Array = []
	for i in maxi(0,keys.size()-1):
		var a: Dictionary = keys[i]
		var b: Dictionary = keys[i+1]
		var p: Array = _vec(a.value)
		var q: Array = _vec(b.value)
		var outgoing: Array = _vec(a.backward)
		var incoming: Array = _vec(b.forward)
		var d: Array = [float(q[0])-float(p[0]),float(q[1])-float(p[1]),float(q[2])-float(p[2])]
		var c2: Array = [Native.f32(Native.f32(float(d[0])*3.0)-Native.f32(float(outgoing[0])+float(outgoing[0])+float(incoming[0]))),Native.f32(float(d[1])*3.0-(float(outgoing[1])+float(outgoing[1])+float(incoming[1]))),Native.f32(Native.f32(Native.f32(float(d[2]))*3.0)-(Native.f32(float(outgoing[2])+float(outgoing[2]))+float(incoming[2])))]
		var c3: Array = [Native.f32(float(outgoing[0])+float(incoming[0])-Native.f32(float(d[0])*2.0)),Native.f32(float(outgoing[1])+float(incoming[1])-float(d[1])*2.0),Native.f32(Native.f32(float(outgoing[2])+float(incoming[2]))-Native.f32(float(d[2]))*2.0)]
		result.append({"p":p,"out":outgoing,"c2":c2,"c3":c3})
	return result

static func _vector_value(c: Dictionary, parameter: float) -> Array:
	var t: float = Native.f32(parameter)
	return [Native.f32((Native.f32(Native.f32(t*float(c.c3[0])+float(c.c2[0]))*t)+float(c.out[0]))*t+float(c.p[0])),Native.f32(Native.f32(Native.f32((t*float(c.c3[1])+float(c.c2[1]))*t)+float(c.out[1]))*t+float(c.p[1])),Native.f32(Native.f32(Native.f32((Native.f32(t*float(c.c3[2]))+float(c.c2[2]))*t+float(c.out[2]))*t)+float(c.p[2]))]

static func _vector_derivative(c: Dictionary, parameter: float) -> Array:
	var t: float = Native.f32(parameter)
	var t3: float = t*3.0
	return [Native.f32(Native.f32((t3*float(c.c3[0])+float(c.c2[0])+float(c.c2[0]))*t)+float(c.out[0])),Native.f32((Native.f32(float(c.c2[1])+float(c.c2[1]))+Native.f32(t3*float(c.c3[1])))*t+float(c.out[1])),Native.f32(Native.f32(Native.f32(float(c.c2[2])+float(c.c2[2]))+Native.f32(t3*float(c.c3[2])))*t+float(c.out[2]))]

static func vector_value(group: Dictionary, segment: int, parameter: float) -> Array:
	var coefficients: Array = vector_coefficients(group)
	return [] if segment < 0 or segment >= coefficients.size() else _vector_value(coefficients[segment],parameter)

static func vector_derivative(group: Dictionary, segment: int, parameter: float) -> Array:
	var coefficients: Array = vector_coefficients(group)
	return [] if segment < 0 or segment >= coefficients.size() else _vector_derivative(coefficients[segment],parameter)

static func vector_at(group: Dictionary, time: float) -> Array:
	var keys: Array = group.get("keys",[])
	if keys.is_empty(): return []
	if time <= float(keys[0].time): return _vec(keys[0].value)
	if time >= float(keys[-1].time): return _vec(keys[-1].value)
	var i := 0
	while time > float(keys[i+1].time): i += 1
	var t: float = Native.f32((time-Native.f32(float(keys[i].time)))/(Native.f32(float(keys[i+1].time))-Native.f32(float(keys[i].time))))
	return _vector_value(vector_coefficients(group)[i],t)

static func _integral(coefficients: Array, segment: int, parameter: float) -> float:
	var sum := 0.0
	for j in 5:
		var d: Array = _vector_derivative(coefficients[segment],Native.f32(parameter*float(POINTS[j])))
		var length: float = sqrt(float(d[0])*float(d[0])+float(d[2])*float(d[2])+float(d[1])*float(d[1]))
		sum = Native.f32(length*float(WEIGHTS[j])+sum)
	return sum*parameter

static func _path_lengths(coefficients: Array) -> Array:
	var result: Array = [0.0]
	for i in coefficients.size(): result.append(Native.f32(_integral(coefficients,i,1.0)+float(result[-1])))
	return result

static func path_lengths(group: Dictionary) -> Array:
	return _path_lengths(vector_coefficients(group))

static func path_sample(group: Dictionary, fraction: float) -> Dictionary:
	var coefficients: Array = vector_coefficients(group)
	if coefficients.is_empty(): return {}
	var lengths: Array = _path_lengths(coefficients)
	var amount: float = Native.f32(fraction)
	if amount < 0.0: amount = Native.f32(fmod(amount,1.0)+1.0)
	if amount > 1.0: amount = Native.f32(fmod(amount,1.0))
	if amount == 0.0: return {"left":0,"right":1,"t":0.0,"position":_vector_value(coefficients[0],0.0)}
	if amount == 1.0:
		var final: int = lengths.size()-2
		return {"left":final,"right":final+1,"t":1.0,"position":_vector_value(coefficients[final],1.0)}
	var distance: float = Native.f32(amount*float(lengths[-1]))
	var i := 0
	while distance > float(lengths[i+1]): i += 1
	var local: float = Native.f32(distance-float(lengths[i]))
	var t: float = Native.f32(local/(float(lengths[i+1])-float(lengths[i])))
	for _iteration in 32:
		var difference: float = _integral(coefficients,i,t)-local
		if absf(difference) <= 0.00009999999747378752: break
		var d: Array = _vector_derivative(coefficients[i],t)
		var speed: float = sqrt(float(d[0])*float(d[0])+float(d[2])*float(d[2])+float(d[1])*float(d[1]))
		t = Native.f32(t-Native.f32(difference)/speed)
	return {"left":i,"right":i+1,"t":t,"position":_vector_value(coefficients[i],t)}

static func light_direction(position: Array, target: Array) -> Array:
	var v: Array = []
	for i in 3: v.append(Native.f32(Native.f32(float(target[i]))-Native.f32(float(position[i]))))
	var length: float = sqrt(float(v[0])*float(v[0])+float(v[1])*float(v[1])+float(v[2])*float(v[2]))
	return [Native.f32(float(v[0])/length),Native.f32(float(v[1])/length),Native.f32(float(v[2])/length)]

static func initial_fog_values(far: float) -> Array:
	var density: float = Native.f32((100.0-40.0)*0.009999999776482582)
	return [Native.f32(1.0/Native.f32(far)),Native.f32(1.0-density),Native.f32(1.0/density)]

static func _color(blocks: Dictionary, id: int, time: float) -> Array:
	var light: Dictionary = blocks[id]
	var controller: Dictionary = blocks[int(light.controller.ref)]
	var clock := Native.ControllerClock.new(controller)
	var result: Array = vector_at(blocks[int(controller.data.ref)].data,clock.advance(time))
	for i in 3: result[i] = clampf(float(result[i]),0.0,1.0)
	return result

static func sample(authored_time: float) -> Dictionary:
	if not is_finite(authored_time): return {}
	var time: float = clampf(authored_time,0.0,24.0)
	var source: Dictionary = Asset.read_json(SOURCE_PATH)
	var blocks := {}
	for block: Dictionary in source.get("blocks",[]): blocks[int(block.id)] = block.fields
	if blocks.size() != 39: return {}
	var path_controller: Dictionary = blocks[26]
	if int(path_controller.unknown_short_2) != 18 or int(blocks[27].unknown_1) != 4: return {}
	var fraction: float = Native.evaluate_float_controller(path_controller,blocks[32].data,time)
	var path: Dictionary = path_sample(blocks[31].data,fraction)
	var target: Array = _vec(blocks[30].translation)
	var light: Array = _color(blocks,33,time)
	var fog: Array = _color(blocks,22,time)
	var ambient_color: Array = _color(blocks,36,time)
	var ambient: Array = []
	var palm_light: Array = []
	var palm_ambient: Array = []
	for i in 3:
		ambient.append(Native.f32((float(fog[i])*Native.f32(float(blocks[22].dimmer))+float(ambient_color[i])*Native.f32(float(blocks[36].dimmer)))*0.5))
		palm_light.append(Native.f32(float(light[i])*Native.f32(float(blocks[33].dimmer))))
		palm_ambient.append(Native.f32(float(ambient_color[i])*Native.f32(float(blocks[36].dimmer))))
	var ambient_alpha: float = Native.f32((float(ambient[0])+float(ambient[1])+float(ambient[2]))*0.1666666716337204)
	return {"time":time,"lightDirection":light_direction(path.position,target),"lightColor":light,"ambient":ambient,"ambientAlpha":ambient_alpha,"palmLightColor":palm_light,"palmAmbient":palm_ambient,"fogColor":fog,"ambientColor":ambient_color,"path":path,"authority":"4AC640/4AC4F0/57BE00/57AA50/57A5D0/57A1D0/57B500/5421B0","scope":"Original authored TimeOfDay, source key evaluation; original runtime scheduler/frame not captured. Existing formal-game lighting remains unchanged."}
