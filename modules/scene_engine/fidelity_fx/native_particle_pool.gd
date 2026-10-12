extends RefCounted
## Native +68/+84/+86 active/pending pool; deletion intentionally skips swapped slot.
const Math = preload("res://modules/scene_engine/fidelity_fx/native_particle_math.gd")
var capacity: int
var num_active: int
var pending_count: int
var pending_start: int
var particles: Array = []
var births := 0
var requested := 0
var deaths := 0

func _init(data: Dictionary) -> void:
	capacity = int(data.num_vertices)
	num_active = int(data.get("num_active",0))
	pending_count = int(data.get("unknown_short_1",0))
	pending_start = int(data.get("unknown_short_2",num_active))
	var descriptions: Array = data.get("particle_descriptions",[])
	var vertices: Array = data.get("vertices",[])
	var colors: Array = data.get("vertex_colors",[])
	var radii: Array = data.get("radii",[])
	var sizes: Array = data.get("sizes",[])
	for i in capacity:
		var d: Dictionary = descriptions[i] if i < descriptions.size() else {}
		var color: Dictionary = colors[i] if i < colors.size() else {}
		particles.append({"position":Math.vector(vertices[i]) if i < vertices.size() else [0.0,0.0,0.0],"velocity":Math.vector(d.translation) if d.has("translation") else [0.0,0.0,0.0],"axis":d.get("unknown_floats_1",[1.0,0.0,0.0]).duplicate(),"age":d.get("unknown_float_1",0.0),"life":d.get("unknown_float_2",0.0),"lastUpdate":d.get("unknown_float_3",0.0),"generation":d.get("unknown_int_1",0),"radius":radii[i] if i < radii.size() else 1.0,"size":sizes[i] if i < sizes.size() else 1.0,"color":[color.r,color.g,color.b,color.a] if not color.is_empty() else [1.0,1.0,1.0,1.0]})

func reset() -> void:
	num_active = 0
	pending_count = 0
	pending_start = 0

func emit(emitter: Dictionary, packet: Dictionary, relative: Dictionary, rng) -> int:
	var count: int = int(packet.count)&65535
	requested += count
	var born := 0
	for i in count:
		var slot: int
		if pending_count != 0:
			slot = pending_start+pending_count
			if slot >= capacity: break
			pending_count += 1
		else:
			pending_start = num_active
			if num_active >= capacity: break
			slot = num_active
			pending_count = 1
		if slot == 65535: break
		particles[slot] = Math.box_birth(emitter,{"timestamp":packet.timestamp,"age":packet.ages[i]},relative,rng)
		born += 1
		births += 1
	return born

func remove(index: int) -> void:
	var last: int = num_active-1
	num_active -= 1
	particles[index] = particles[last].duplicate(true)
	deaths += 1

func commit() -> void:
	var old_active: int = num_active
	if old_active >= pending_start:
		num_active = old_active+pending_count
	else:
		num_active = pending_start+pending_count
		while old_active < pending_start and num_active > pending_start:
			remove(old_active)
			old_active += 1
		if old_active < pending_start:
			num_active = old_active
			pending_count = 0
			pending_start = old_active
			return
	pending_count = 0
	pending_start = num_active

func age_death(now: float, modifier: Dictionary) -> void:
	assert(not modifier.spawn_on_death,"SpawnOnDeath branch unported")
	# Native loop increments after removal; do not replace with a while/swap retry.
	var i := 0
	while i < num_active:
		var p: Dictionary = particles[i]
		p.age = Math.f32(Math.f32(now)-p.lastUpdate+p.age)
		if p.age > p.life: remove(i)
		i += 1

func position(now: float) -> void:
	commit()
	now = Math.f32(now)
	for i in num_active:
		var p: Dictionary = particles[i]
		var dt: float = now-p.lastUpdate
		var y: float = Math.f32(dt*p.velocity[1])
		var z: float = Math.f32(dt*p.velocity[2])
		p.position = [Math.f32(dt*p.velocity[0]+p.position[0]),Math.f32(y+p.position[1]),Math.f32(z+p.position[2])]
		p.lastUpdate = now

func active() -> Array:
	return particles.slice(0,num_active)

func fork():
	var out = get_script().new({"num_vertices":0,"num_active":0})
	out.capacity = capacity
	out.num_active = num_active
	out.pending_count = pending_count
	out.pending_start = pending_start
	out.particles = particles.duplicate(true)
	out.births = births
	out.requested = requested
	out.deaths = deaths
	return out
