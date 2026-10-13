extends RefCounted
## 5C0660 local CPU stream, 36-byte FVF338 vertices. One owner per system.
## Scalar stores/ARGB/index order follow the original x86 fixture, including
## unnormalized normals and b.z's delayed store. Godot GPU layout is an adapter.
## The owner may fill only while its worker owns the replay. Main joins before
## consuming these mutable buffers; different effects never share this object.
const Math = preload("res://modules/scene_engine/fidelity_fx/native_particle_math.gd")
const CORNERS := [Vector2(0,1),Vector2(1,1),Vector2(1,0),Vector2(0,0)]
var capacity: int
var count := 0
var vertex_count := 0
var index_count := 0
var triangle_count := 0
var vertex_bytes := PackedByteArray()
var attribute_bytes := PackedByteArray()
var vertices := PackedVector3Array()
var normals := PackedVector3Array()
var uvs := PackedVector2Array()
var colors := PackedColorArray()
var indices := PackedInt32Array()

func _init(reserved: int = 0) -> void:
	assert(reserved >= 0 and reserved <= 16384,"Packed particle adapter capacity must fit native u16 active indices")
	capacity = reserved
	vertex_bytes.resize(capacity*144); attribute_bytes.resize(capacity*48)
	vertices.resize(capacity*4); normals.resize(capacity*4)
	uvs.resize(capacity*4); colors.resize(capacity*4)
	# Original index-manager reservation is 24N u16 indices; Godot requires i32.
	# Only first 6*count indices are ever submitted by the adapter.
	indices.resize(capacity*24)
	for quad in capacity*4:
		var base := quad*4; var offset := quad*6
		indices[offset] = base; indices[offset+1] = base+1; indices[offset+2] = base+2
		indices[offset+3] = base; indices[offset+4] = base+2; indices[offset+5] = base+3

func _write_vertex(index: int, position: Vector3, normal: Vector3, argb: int, native_uv: Vector2, controlled_uv: Vector2, color: Color) -> void:
	vertices[index] = position; normals[index] = normal
	uvs[index] = controlled_uv; colors[index] = color
	var offset := index*36
	vertex_bytes.encode_float(offset,position.x); vertex_bytes.encode_float(offset+4,position.y); vertex_bytes.encode_float(offset+8,position.z)
	vertex_bytes.encode_float(offset+12,normal.x); vertex_bytes.encode_float(offset+16,normal.y); vertex_bytes.encode_float(offset+20,normal.z)
	vertex_bytes.encode_u32(offset+24,argb)
	vertex_bytes.encode_float(offset+28,native_uv.x); vertex_bytes.encode_float(offset+32,native_uv.y)
	# Native ARGB to Godot RGBA, without a second float-color quantization.
	var attribute := index*12
	attribute_bytes[attribute] = (argb >> 16)&255; attribute_bytes[attribute+1] = (argb >> 8)&255
	attribute_bytes[attribute+2] = argb&255; attribute_bytes[attribute+3] = (argb >> 24)&255
	attribute_bytes.encode_float(attribute+4,controlled_uv.x); attribute_bytes.encode_float(attribute+8,controlled_uv.y)

func fill(particles: Array, active: int, world: Dictionary, camera: Dictionary, uv_template: Array = [], has_colors: bool = true) -> bool:
	# Reject the caller's range before modifying the last accepted prefix.
	if active < 0 or active > capacity or active > particles.size(): return false
	if active == 0:
		count = 0; vertex_count = 0; index_count = 0; triangle_count = 0
		return true
	var rotation: Array = world.get("rotation",[])
	var right: Array = camera.get("right",[]); var up: Array = camera.get("up",[])
	var scale := float(world.get("scale",0.0))
	if rotation.size() != 9 or right.size() != 3 or up.size() != 3 or not is_finite(scale) or scale == 0.0 or (not uv_template.is_empty() and uv_template.size() != 4): return false
	var m0 := Math.f32(rotation[0]*scale); var m1 := Math.f32(rotation[1]*scale); var m2 := Math.f32(rotation[2]*scale)
	var m3 := Math.f32(rotation[3]*scale); var m4 := Math.f32(rotation[4]*scale); var m5 := Math.f32(rotation[5]*scale)
	var m6 := Math.f32(rotation[6]*scale); var m7 := Math.f32(rotation[7]*scale); var m8 := Math.f32(rotation[8]*scale)
	var r0 := Math.f32(m6*right[2]+m3*right[1]+m0*right[0])
	var r1 := Math.f32(m7*right[2]+m4*right[1]+m1*right[0])
	var r2 := Math.f32(m8*right[2]+m5*right[1]+m2*right[0])
	var u0 := Math.f32(m6*up[2]+m3*up[1]+m0*up[0])
	var u1 := Math.f32(m7*up[2]+m4*up[1]+m1*up[0])
	var u2 := Math.f32(m8*up[2]+m5*up[1]+m2*up[0])
	var inverse := 1.0/scale
	var s0 := Math.f32((r0+u0)*inverse); var s1 := Math.f32((u1+r1)*inverse); var s2 := Math.f32(Math.f32(u2+r2)*inverse)
	var d0 := Math.f32((u0-r0)*inverse); var d1 := Math.f32((u1-r1)*inverse); var d2 := Math.f32(Math.f32(u2-r2)*inverse)
	var normal := Vector3(r1*u2-r2*u1,r2*u0-r0*u2,r0*u1-r1*u0)
	var uv0: Vector2 = CORNERS[0] if uv_template.is_empty() else Vector2(uv_template[0][0],uv_template[0][1])
	var uv1: Vector2 = CORNERS[1] if uv_template.is_empty() else Vector2(uv_template[1][0],uv_template[1][1])
	var uv2: Vector2 = CORNERS[2] if uv_template.is_empty() else Vector2(uv_template[2][0],uv_template[2][1])
	var uv3: Vector2 = CORNERS[3] if uv_template.is_empty() else Vector2(uv_template[3][0],uv_template[3][1])
	for i in active:
		# Read the existing native pool slot. No new particle/quad dictionary,
		# Array, UV copy, node, material wrapper or descriptor inside this loop.
		var particle: Dictionary = particles[i]; var p: Array = particle.position
		var factor: float = particle.size*particle.radius
		var a := Vector3(s0*factor,s1*factor,s2*factor)
		var b := Vector2(d0*factor,d1*factor); var bz: float = d2*factor
		var argb := 0xffffffff
		if has_colors:
			var c: Array = particle.color
			var ca := Math.nearest_even(Math.f32(c[3]*255.0)); var cr := Math.nearest_even(Math.f32(c[0]*255.0))
			var cg := Math.nearest_even(Math.f32(c[1]*255.0)); var cb := Math.nearest_even(Math.f32(c[2]*255.0))
			# Native shifts/ORs: no independent channel masks or clamp beforehand.
			argb = ((((((ca << 8)|cr) << 8)|cg) << 8)|cb)&0xffffffff
		var color := Color(float((argb >> 16)&255)/255.0,float((argb >> 8)&255)/255.0,float(argb&255)/255.0,float((argb >> 24)&255)/255.0)
		_write_vertex(i*4,Vector3(p[0]-a.x,p[1]-a.y,p[2]-a.z),normal,argb,CORNERS[0],uv0,color)
		_write_vertex(i*4+1,Vector3(p[0]-b.x,p[1]-b.y,p[2]-bz),normal,argb,CORNERS[1],uv1,color)
		_write_vertex(i*4+2,Vector3(a.x+p[0],a.y+p[1],a.z+p[2]),normal,argb,CORNERS[2],uv2,color)
		_write_vertex(i*4+3,Vector3(b.x+p[0],b.y+p[1],bz+p[2]),normal,argb,CORNERS[3],uv3,color)
	count = active; vertex_count = active*4; index_count = active*6; triangle_count = active*2
	return true

static func _median(depths: PackedFloat32Array, lower: int, upper: int) -> float:
	var middle := (lower+upper) >> 1
	var first := depths[lower]; var center := depths[middle]; var last := depths[upper]
	if first >= center:
		if first < last: return first
		if center < last: return last
		return center
	if center < last: return center
	if first < last: return last
	return first

static func _quicksort(ids: PackedInt32Array, depths: PackedFloat32Array, lower: int, upper: int) -> void:
	while upper > lower:
		var left := lower-1; var right := upper+1; var pivot := _median(depths,lower,upper)
		while true:
			right -= 1
			while pivot < depths[right]: right -= 1
			left += 1
			while depths[left] < pivot: left += 1
			if left >= right: break
			var id := ids[left]; ids[left] = ids[right]; ids[right] = id
			var depth := depths[left]; depths[left] = depths[right]; depths[right] = depth
		if right == upper: upper = right-1
		else:
			_quicksort(ids,depths,lower,right)
			lower = right+1

static func sort_transparent(ids: PackedInt32Array, depths: PackedFloat32Array, active: int) -> bool:
	if active < 0 or active > ids.size() or active > depths.size(): return false
	for i in active:
		if not is_finite(depths[i]): return false
	_quicksort(ids,depths,0,active-1)
	return true
