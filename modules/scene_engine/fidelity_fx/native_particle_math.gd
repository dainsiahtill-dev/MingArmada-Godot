extends RefCounted
## Ports of the completed native particle source. Arrays retain native Z-up units.
## Binary32 stores mirror the source oracle; transcendental x87 emulation is not claimed.
const Shared = preload("res://modules/scene_engine/fidelity_island/native_math.gd")
const GRAVITY_SCALE := 1.600000023841858
const SIZE_FLOOR := 0.00009999999747378752
## Vector components store binary32 in normal builds. Double-precision builds
## retain the explicit byte conversion; neither path uses mutable shared state.
const _VECTOR_BINARY32 := Vector3(16777217.0,0.0,0.0).x == 16777216.0
const ROTATION_ORDERS := [[0,1,2],[0,2,1],[1,2,0],[1,0,2],[2,0,1],[2,1,0]]

class CrtRand extends RefCounted:
	var state: int
	var draws := 0
	func _init(value: int = 1) -> void:
		self.seed(value)
	func seed(value: int) -> void:
		assert(value >= 0 and value <= 0xffffffff,"Explicit uint32 original CRT state required")
		state = value
		draws = 0
	func next() -> int:
		state = (state*0x343fd+0x269ec3)&0xffffffff
		draws += 1
		return (state >> 16)&0x7fff

static func f32(value: float) -> float:
	return Vector3(value,0.0,0.0).x if _VECTOR_BINARY32 else Shared.f32(value)

static func identity() -> Array:
	return [1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,1.0]

static func identity_transform() -> Dictionary:
	return {"rotation":identity(),"translation":[0.0,0.0,0.0],"scale":1.0}

static func vector(value: Dictionary) -> Array:
	return [value.x,value.y,value.z]

static func nif_matrix(value: Dictionary) -> Array:
	return [value.m_11,value.m_21,value.m_31,value.m_12,value.m_22,value.m_32,value.m_13,value.m_23,value.m_33]

static func multiply_matrix(a: Array, b: Array) -> Array:
	var out := []
	for row in 3:
		for col in 3:
			out.append(f32(a[row*3]*b[col]+a[row*3+1]*b[3+col]+a[row*3+2]*b[6+col]))
	return out

static func transform_vector(matrix: Array, value: Array) -> Array:
	var out := []
	for row in 3:
		out.append(f32(matrix[row*3]*value[0]+matrix[row*3+1]*value[1]+matrix[row*3+2]*value[2]))
	return out

static func transform_transpose(matrix: Array, value: Array) -> Array:
	var out := []
	for col in 3:
		out.append(f32(matrix[6+col]*value[2]+matrix[3+col]*value[1]+matrix[col]*value[0]))
	return out

static func compose(a: Dictionary, b: Dictionary) -> Dictionary:
	var value: Array = transform_vector(a.rotation,b.translation)
	var scale: float = f32(a.scale)
	return {"rotation":multiply_matrix(a.rotation,b.rotation),"scale":f32(scale*b.scale),"translation":[f32(scale*value[0]+a.translation[0]),f32(f32(scale*value[1])+a.translation[1]),f32(f32(scale*value[2])+a.translation[2])]}

static func inverse(value: Dictionary) -> Dictionary:
	var m: Array = value.rotation
	var rotation: Array = [m[0],m[3],m[6],m[1],m[4],m[7],m[2],m[5],m[8]]
	var scale: float = f32(1.0/value.scale)
	var negative := []
	for component in value.translation: negative.append(f32(-component))
	var translation: Array = transform_vector(rotation,negative)
	for i in 3: translation[i] = f32(scale*translation[i])
	return {"rotation":rotation,"scale":scale,"translation":translation}

static func point(world: Dictionary, value: Array) -> Array:
	var m: Array = world.rotation
	if _VECTOR_BINARY32:
		# Component stores match the original f32 stores. Only x/y scaling has
		# an intermediate store; z rounds after its final scale-and-add.
		var v := Vector3(m[0]*value[0]+m[1]*value[1]+m[2]*value[2],m[3]*value[0]+m[4]*value[1]+m[5]*value[2],m[6]*value[0]+m[7]*value[1]+m[8]*value[2])
		var scaled := Vector2(world.scale*v.x,world.scale*v.y)
		var result := Vector3(scaled.x+world.translation[0],scaled.y+world.translation[1],world.scale*v.z+world.translation[2])
		return [result.x,result.y,result.z]
	var x: float = f32(m[0]*value[0]+m[1]*value[1]+m[2]*value[2])
	var y: float = f32(m[3]*value[0]+m[4]*value[1]+m[5]*value[2])
	var z: float = f32(m[6]*value[0]+m[7]*value[1]+m[8]*value[2])
	return [f32(f32(world.scale*x)+world.translation[0]),f32(f32(world.scale*y)+world.translation[1]),f32(world.scale*z+world.translation[2])]

static func system_world(world: Dictionary, world_space: bool) -> Dictionary:
	return {"rotation":identity(),"translation":[0.0,0.0,0.0],"scale":world.scale} if world_space else world

static func normalize(value: Array) -> Array:
	var length: float = sqrt(value[0]*value[0]+value[1]*value[1]+value[2]*value[2])
	if length <= 0.0000009999999974752427: return [0.0,0.0,0.0]
	return [f32(value[0]/length),f32(value[1]/length),f32(value[2]/length)]

static func controller_time(fields: Dictionary, time: float) -> float:
	assert(int(fields.flags)&8,"Inactive original controller")
	var clock = Shared.ControllerClock.new(fields)
	if int(fields.flags)&1: clock.advance(0.0)
	return clock.advance(time)

static func value_array(value) -> Variant:
	if value is int or value is float: return value
	if value is Dictionary and value.has("x"): return vector(value)
	if value is Dictionary and value.has("r"): return [value.r,value.g,value.b,value.a]
	return null

static func sample_keys(group: Dictionary, time: float):
	time = f32(time)
	var keys: Array = group.keys
	assert(not keys.is_empty() and int(group.interpolation) in [1,2],"Unsupported original key group")
	var first: Variant = value_array(keys[0].value)
	var last: Variant = value_array(keys[-1].value)
	if time <= float(keys[0].time): return first
	if time >= float(keys[-1].time): return last
	var index := 0
	while index+1 < keys.size() and time > float(keys[index+1].time): index += 1
	var a: Dictionary = keys[index]
	var b: Dictionary = keys[index+1]
	var t: float = f32((f32(time)-a.time)/(b.time-a.time))
	var av: Variant = value_array(a.value)
	var bv: Variant = value_array(b.value)
	if int(group.interpolation) == 2:
		assert(av is float or av is int,"Unsupported non-scalar cubic keys")
		return f32((((a.backward+b.forward-2.0*(bv-av))*t+3.0*(bv-av)-(2.0*a.backward+b.forward))*t+a.backward)*t+av)
	if av is float or av is int: return f32((1.0-t)*av+t*bv)
	var out := []
	for i in av.size(): out.append(f32(f32((1.0-t)*av[i])+f32(t*bv[i])))
	return out

static func vector_key(group: Dictionary, time: float) -> Array:
	var keys: Array = group.keys
	if keys.size() == 1: return vector(keys[0].value)
	assert(int(group.interpolation) == 1,"Unsupported original Vector3 interpolation")
	time = f32(time)
	assert(time >= keys[0].time and time <= keys[-1].time,"Outside original Vector3 interval")
	var index := 0
	while time > float(keys[index+1].time): index += 1
	var left: Dictionary = keys[index]
	var right: Dictionary = keys[index+1]
	var t: float = f32((time-left.time)/(right.time-left.time))
	var one: float = 1.0-t
	return [f32(t*right.value.x+one*left.value.x),f32(f32(t*right.value.y)+f32(one*left.value.y)),f32(f32(t*right.value.z)+f32(one*left.value.z))]

static func quaternion_multiply(left: Array, right: Array) -> Array:
	var w: float = left[0]
	var x: float = left[1]
	var y: float = left[2]
	var z: float = left[3]
	var rw: float = right[0]
	var rx: float = right[1]
	var ry: float = right[2]
	var rz: float = right[3]
	return [f32(rw*w-rx*x-y*ry-z*rz),f32(x*rw+rz*y+rx*w-z*ry),f32(z*rx+w*ry+y*rw-rz*x),f32(rz*w+x*ry+z*rw-y*rx)]

static func euler_quaternion(groups: Array, order: int, time: float) -> Array:
	assert(order >= 0 and order < ROTATION_ORDERS.size(),"Original rotation_order required")
	var qs := []
	for axis in 3:
		var angle: float = Shared.interpolate_float_keys(groups[axis],f32(time)) if not groups[axis].keys.is_empty() else 0.0
		var half: float = angle*0.5
		var q: Array = [f32(cos(half)),0.0,0.0,0.0]
		q[axis+1] = f32(sin(half))
		qs.append(q)
	var result := [1.0,0.0,0.0,0.0]
	for axis in ROTATION_ORDERS[order]: result = quaternion_multiply(qs[axis],result)
	return result

static func quaternion_matrix(q: Array) -> Array:
	var w: float = q[0]
	var x: float = q[1]
	var y: float = q[2]
	var z: float = q[3]
	var x2: float = x+x
	var y2: float = y+y
	var z2: float = f32(z+z)
	var wx: float = f32(x2*w)
	var wy: float = f32(y2*w)
	var wz: float = f32(z2*w)
	var xx: float = f32(x2*x)
	var xy: float = f32(y2*x)
	var xz: float = f32(z2*x)
	var yy: float = y2*y
	var yz: float = z2*y
	var zz: float = z2*z
	return [f32(1.0-(zz+yy)),f32(xy-wz),f32(xz+wy),f32(xy+wz),f32(1.0-(zz+xx)),f32(yz-wx),f32(xz-wy),f32(wx+yz),f32(1.0-(yy+xx))]

static func visibility_at(keys: Array, time: float) -> bool:
	assert(not keys.is_empty(),"Empty visibility fallback unverified")
	var index := 0
	while index+1 < keys.size() and time >= float(keys[index+1].time): index += 1
	return bool(keys[index].value)

static func box_birth(emitter: Dictionary, packet: Dictionary, relative: Dictionary, rng) -> Dictionary:
	# These native constants are binary32 too; restore after decimal lexer conversion.
	var norm: float = f32(0.000030518509447574615)
	var symmetric: float = f32(0.00006103701889514923)
	var speed: float = f32((rng.next()*norm-0.5)*emitter.speed_variation+emitter.speed)
	var declination: float = f32((rng.next()*symmetric-1.0)*emitter.declination_variation+emitter.declination)
	var planar: float = (rng.next()*symmetric-1.0)*emitter.planar_angle_variation+emitter.planar_angle
	var x: float = f32(cos(planar)*sin(declination))
	var velocity: Array = [f32(x*speed),f32(sin(declination)*sin(planar)*speed),f32(cos(declination)*speed)]
	var life: float = f32((rng.next()*norm-0.5)*emitter.life_span_variation+emitter.life_span)
	var y: float = f32(rng.next()*norm)
	var xx: float = f32(rng.next()*norm)
	var z: float = rng.next()*norm
	var position: Array = [f32((xx-0.5)*emitter.width),f32((y-0.5)*emitter.height),f32((z-0.5)*emitter.depth)]
	var color: Dictionary = emitter.initial_color
	return {"position":point(relative,position),"velocity":transform_vector(relative.rotation,velocity),"axis":[1.0,0.0,0.0],"age":f32(packet.age),"life":life,"lastUpdate":f32(f32(packet.timestamp)-f32(packet.age)),"generation":0,"radius":emitter.initial_radius,"size":1.0,"color":[color.r,color.g,color.b,color.a]}

static func grow_fade(modifier: Dictionary, particle: Dictionary) -> float:
	var grow := 1.0
	var fade := 1.0
	if particle.generation == modifier.grow_generation and particle.age < modifier.grow_time: grow = particle.age/modifier.grow_time
	var remaining: float = f32(particle.life-particle.age)
	if particle.generation == modifier.fade_generation and remaining < modifier.fade_time: fade = remaining/modifier.fade_time
	return f32(maxf(SIZE_FLOOR,minf(grow,fade)))

static func particle_color(group: Dictionary, particle: Dictionary) -> Array:
	var t: float = maxf(group.keys[0].time,minf(group.keys[-1].time,f32(particle.age/particle.life)))
	var out: Array = sample_keys(group,t)
	for i in out.size(): out[i] = clampf(out[i],0.0,1.0)
	return out

static func sphere_gravity(modifier: Dictionary, particle: Dictionary, origin: Array, now: float) -> Dictionary:
	assert(int(modifier.force_type) == 1 and modifier.turbulence == 0,"Unsupported sphere gravity variant")
	var dx: float = f32(origin[0])-f32(particle.position[0])
	var dy: float = f32(origin[1])-f32(particle.position[1])
	var dz: float = f32(origin[2])-f32(particle.position[2])
	var stored_z: float = f32(dz)
	var length: float = sqrt(dz*stored_z+dy*dy+dx*dx)
	var inverse_length: float = 1.0/length if length != 0.0 else 1.0
	var nx: float = dx*inverse_length
	var ny: float = dy*inverse_length
	var nz: float = f32(stored_z*inverse_length)
	var decay: float = f32(1.0 if modifier.decay == 0 else exp(-length*f32(modifier.decay)))
	var strength: float = f32(modifier.strength)
	var dt: float = f32(f32(now)-f32(particle.lastUpdate))
	var x: float = f32(f32(nx*decay)*strength)*GRAVITY_SCALE
	var y: float = f32(f32(ny*decay*strength)*GRAVITY_SCALE)
	var z: float = f32(strength*(nz*decay)*GRAVITY_SCALE)
	var delta: Array = [f32(x*dt),f32(y*dt),f32(f32(z+0.0)*dt)]
	var out: Dictionary = particle.duplicate()
	out.velocity = []
	for i in 3: out.velocity.append(f32(delta[i]+f32(particle.velocity[i])))
	return out

static func planar_gravity(modifier: Dictionary, particle: Dictionary, origin: Array, axis: Array, now: float) -> Dictionary:
	assert(int(modifier.force_type) == 0 and modifier.turbulence == 0,"Unsupported planar gravity variant")
	var decay: float = f32(modifier.decay)
	var strength: float = f32(modifier.strength)
	var dt: float = f32(f32(now)-particle.lastUpdate)
	var p: Array = particle.position
	var dot: float = axis[2]*(origin[2]-p[2])+axis[1]*(origin[1]-p[1])+(origin[0]-p[0])*axis[0]
	var attenuation: float = 1.0 if decay == 0 else exp(-absf(dot)*decay)
	var x: float = f32(f32(axis[0]*attenuation)*strength)*GRAVITY_SCALE
	var y: float = f32(f32(f32(axis[1]*attenuation)*strength)*GRAVITY_SCALE)
	var z: float = f32(attenuation*axis[2]*strength*GRAVITY_SCALE+0.0)
	var out: Dictionary = particle.duplicate()
	out.velocity = [f32(f32((x+0.0)*dt)+particle.velocity[0]),f32(f32((y+0.0)*dt)+particle.velocity[1]),f32(f32(z*dt)+particle.velocity[2])]
	return out

static func bounds(vertices: Array) -> Dictionary:
	if vertices.is_empty(): return {"center":[0.0,0.0,0.0],"radius":0.0}
	var low: Array = vertices[0].duplicate()
	var high: Array = vertices[0].duplicate()
	for value in vertices:
		for i in 3:
			low[i] = minf(low[i],value[i])
			high[i] = maxf(high[i],value[i])
	var center: Array = [f32(f32(high[0]+low[0])*0.5),f32(f32(high[1]+low[1])*0.5),f32((high[2]+low[2])*0.5)]
	var squared := 0.0
	for value in vertices:
		var x: float = value[0]-center[0]
		var y: float = value[1]-center[1]
		var z: float = value[2]-center[2]
		var next: float = z*z+y*y+x*x
		if next > squared: squared = f32(next)
	return {"center":center,"radius":f32(sqrt(squared))}

static func nearest_even(value: float) -> int:
	var base: int = int(floor(value))
	var part: float = value-base
	if part == 0.5: return base if base%2 == 0 else base+1
	return int(floor(value+0.5))

static func particle_quad_context(world: Dictionary, camera: Dictionary) -> Dictionary:
	# This is the unchanged scalar prefix of particle_quad. Its inputs belong
	# to one system/view, so the same native float stores need only run once.
	var scaled := []
	for component in world.rotation: scaled.append(f32(component*world.scale))
	var right: Array = transform_transpose(scaled,camera.right)
	var up: Array = transform_transpose(scaled,camera.up)
	var inverse_scale: float = 1.0/world.scale
	var sum: Array = [f32((right[0]+up[0])*inverse_scale),f32((up[1]+right[1])*inverse_scale),f32(f32(up[2]+right[2])*inverse_scale)]
	var difference: Array = [f32((up[0]-right[0])*inverse_scale),f32((up[1]-right[1])*inverse_scale),f32(f32(up[2]-right[2])*inverse_scale)]
	return {"sum":sum,"difference":difference}

static func particle_quad_prepared(particle: Dictionary, context: Dictionary) -> Dictionary:
	var sum: Array = context.sum
	var difference: Array = context.difference
	var factor: float = particle.size*particle.radius
	var a: Array = [f32(sum[0]*factor),f32(sum[1]*factor),f32(sum[2]*factor)]
	var b: Array = [f32(difference[0]*factor),f32(difference[1]*factor),difference[2]*factor]
	var p: Array = particle.position
	var vertices: Array = [[],[],[],[]]
	for i in 3:
		vertices[0].append(f32(p[i]-a[i]))
		vertices[1].append(f32(p[i]-b[i]))
		vertices[2].append(f32(a[i]+p[i]))
		vertices[3].append(f32(b[i]+p[i]))
	var bytes := []
	var colors := []
	for component in particle.color:
		var byte: int = nearest_even(f32(component*255.0))&255
		bytes.append(byte)
		colors.append(byte/255.0)
	var argb: int = ((bytes[3]<<24)|(bytes[0]<<16)|(bytes[1]<<8)|bytes[2])&0xffffffff
	return {"vertices":vertices,"uvs":[[0,1],[1,1],[1,0],[0,0]],"triangles":[[0,1,2],[0,2,3]],"argb":argb,"color":colors}

static func particle_uv_template(desc: Dictionary, values: Dictionary = {}) -> Array:
	var corners: Array = [[0,1],[1,1],[1,0],[0,0]]
	if not desc.get("has_texture_transform",false): return corners
	var overrides := {}
	var names := ["translationU","translationV","rotation","scaleU","scaleV"]
	for operation in values: overrides[names[int(operation)]] = values[operation]
	var matrix: PackedFloat32Array = Shared.texture_transform(desc,overrides)
	var result := []
	for uv: Array in corners:
		result.append([f32(matrix[0]*uv[0]+matrix[3]*uv[1]+matrix[6]),f32(matrix[1]*uv[0]+matrix[4]*uv[1]+matrix[7])])
	return result

static func particle_quad(particle: Dictionary, world: Dictionary, camera: Dictionary) -> Dictionary:
	var scaled := []
	for component in world.rotation: scaled.append(f32(component*world.scale))
	var right: Array = transform_transpose(scaled,camera.right)
	var up: Array = transform_transpose(scaled,camera.up)
	var inverse_scale: float = 1.0/world.scale
	var sum: Array = [f32((right[0]+up[0])*inverse_scale),f32((up[1]+right[1])*inverse_scale),f32(f32(up[2]+right[2])*inverse_scale)]
	var difference: Array = [f32((up[0]-right[0])*inverse_scale),f32((up[1]-right[1])*inverse_scale),f32(f32(up[2]-right[2])*inverse_scale)]
	var factor: float = particle.size*particle.radius
	var a: Array = [f32(sum[0]*factor),f32(sum[1]*factor),f32(sum[2]*factor)]
	var b: Array = [f32(difference[0]*factor),f32(difference[1]*factor),difference[2]*factor]
	var p: Array = particle.position
	var vertices: Array = [[],[],[],[]]
	for i in 3:
		vertices[0].append(f32(p[i]-a[i]))
		vertices[1].append(f32(p[i]-b[i]))
		vertices[2].append(f32(a[i]+p[i]))
		vertices[3].append(f32(b[i]+p[i]))
	var bytes := []
	var colors := []
	for component in particle.color:
		var byte: int = nearest_even(f32(component*255.0))&255
		bytes.append(byte)
		colors.append(byte/255.0)
	var argb: int = ((bytes[3]<<24)|(bytes[0]<<16)|(bytes[1]<<8)|bytes[2])&0xffffffff
	return {"vertices":vertices,"uvs":[[0,1],[1,1],[1,0],[0,0]],"triangles":[[0,1,2],[0,2,3]],"argb":argb,"color":colors}

static func texture_uv(uv: Array, desc: Dictionary, values: Dictionary = {}) -> Array:
	if not desc.get("has_texture_transform",false): return uv.duplicate()
	var overrides := {}
	var names := ["translationU","translationV","rotation","scaleU","scaleV"]
	for operation in values: overrides[names[int(operation)]] = values[operation]
	var matrix: PackedFloat32Array = Shared.texture_transform(desc,overrides)
	return [f32(matrix[0]*uv[0]+matrix[3]*uv[1]+matrix[6]),f32(matrix[1]*uv[0]+matrix[4]*uv[1]+matrix[7])]

static func material_source_state(input: Dictionary) -> Dictionary:
	var calls := []
	var source_after: int = int(input.previousSource)
	var use_scene_lights := false
	var vertex_mode: int = int(input.vertexMode)
	if (input.baseDescriptorPresent and input.baseDescriptorField4Nonzero and input.applyMode == 0) or (input.lightingMode == 0 and vertex_mode == 1):
		calls.append({"state":137,"value":0,"save":0})
		return {"calls":calls,"sourceAfter":source_after,"useSceneLights":use_scene_lights}
	if input.lightingMode == 0:
		if source_after == 1:
			for state in [148,147,145]: calls.append({"state":state,"value":0,"save":0})
			source_after = 0
	else:
		if vertex_mode != source_after:
			calls.append({"state":148,"value":1 if vertex_mode == 1 else 0,"save":0})
			calls.append({"state":147,"value":1 if vertex_mode == 2 else 0,"save":0})
			calls.append({"state":145,"value":1 if vertex_mode == 2 else 0,"save":0})
			source_after = vertex_mode
		use_scene_lights = true
	calls.append({"state":137,"value":1,"save":0})
	if use_scene_lights: calls.append({"state":139,"value":0xff000000,"save":0})
	return {"calls":calls,"sourceAfter":source_after,"useSceneLights":use_scene_lights}
