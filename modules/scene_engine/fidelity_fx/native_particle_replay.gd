extends RefCounted
## Direct native variable-dt replay. Observation-time canonical grid lives in facade.
const Math = preload("res://modules/scene_engine/fidelity_fx/native_particle_math.gd")
const Pool = preload("res://modules/scene_engine/fidelity_fx/native_particle_pool.gd")
const Emitter = preload("res://modules/scene_engine/fidelity_fx/native_emitter_controller.gd")
const Batch = preload("res://modules/scene_engine/fidelity_fx/cpu_particle_batch.gd")
var asset: Dictionary
var blocks: Dictionary
var seed_value: int
var rng
var systems: Array = []
var time = null
# Lazy, independent presentation storage. Forks share only immutable blueprints;
# neither native state publication nor the legacy particle API exposes batches.
var _particle_batches: Dictionary = {}
var _batch_records: Dictionary = {}
var batch_error := ""

func _init(source: Dictionary = {}, seed: int = 1, index: Dictionary = {}) -> void:
	asset = source
	blocks = index
	seed_value = seed
	rng = Math.CrtRand.new(seed)
	# Forks fill an empty replay with already prepared blueprint references and
	# independent mutable state. Do not build original pools only to replace them.
	if source.is_empty(): return
	for block in asset.blocks:
		if block.type != "NiParticleSystem": continue
		var controller: Dictionary
		var reset_controller: Dictionary
		for candidate in asset.blocks:
			if candidate.fields.get("target") == null or int(candidate.fields.target.ref) != int(block.id): continue
			if candidate.type == "NiPSysEmitterCtlr": controller = candidate
			elif candidate.type == "NiPSysResetOnLoopCtlr": reset_controller = candidate
		var modifiers := []
		for ref in block.fields.modifiers: modifiers.append(blocks[int(ref.ref)])
		# Stable sort by source order: preserve equal-order authored insertion order.
		for i in range(1,modifiers.size()):
			var cursor: int = i
			while cursor > 0 and modifiers[cursor-1].fields.order > modifiers[cursor].fields.order:
				var temporary = modifiers[cursor]
				modifiers[cursor] = modifiers[cursor-1]
				modifiers[cursor-1] = temporary
				cursor -= 1
		var emitter: Dictionary
		for modifier in modifiers:
			if modifier.type == "NiPSysBoxEmitter": emitter = modifier
		systems.append({"block":block,"modifiers":modifiers,"emitter":emitter,"controller":Emitter.new(controller.fields,blocks[int(controller.fields.data.ref)].fields),"resetController":reset_controller,"pool":Pool.new(blocks[int(block.fields.data.ref)].fields),"lastUpdate":null,"lastResetMapped":null,"world":Math.identity_transform(),"bounds":{"center":[0.0,0.0,0.0],"radius":0.0},"boundCounter":0})

func _visit_world(id: int, outer: Dictionary, now: float, worlds: Dictionary) -> void:
	var block: Dictionary = blocks[id]
	var fields: Dictionary = block.fields
	var local: Dictionary = {"rotation":Math.nif_matrix(fields.rotation) if fields.has("rotation") else Math.identity(),"translation":Math.vector(fields.translation) if fields.has("translation") else [0.0,0.0,0.0],"scale":fields.get("scale",1.0)}
	for controller in controllers(block):
		if controller.type != "NiKeyframeController": continue
		var data: Dictionary = blocks[int(controller.fields.data.ref)].fields
		var mapped: float = Math.controller_time(controller.fields,now)
		if not data.get("translations",{}).get("keys",[]).is_empty(): local.translation = Math.vector_key(data.translations,mapped)
		if not data.get("scales",{}).get("keys",[]).is_empty(): local.scale = Math.sample_keys(data.scales,mapped)
		if data.get("num_rotation_keys",0) != 0:
			local.rotation = Math.quaternion_matrix(Math.euler_quaternion(data.xyz_rotations,int(data.rotation_order),mapped))
	var world: Dictionary = Math.compose(outer,local)
	worlds[id] = world
	for child in fields.get("children",[]): _visit_world(int(child.ref),world,now,worlds)

func authored_world_transforms(now: float) -> Dictionary:
	var worlds := {}
	for root in asset.roots: _visit_world(int(root),Math.identity_transform(),now,worlds)
	return worlds

func controllers(block: Dictionary) -> Array:
	var out := []
	var ref = block.fields.get("controller")
	while ref != null:
		var controller: Dictionary = blocks[int(ref.ref)]
		out.append(controller)
		ref = controller.fields.get("next_controller")
	return out

func advance(now: float) -> void:
	now = Math.f32(now)
	var worlds: Dictionary = authored_world_transforms(now)
	for system in systems:
		system.world = Math.system_world(worlds[int(system.block.id)],bool(system.block.fields.world_space))
		var reset_fields: Dictionary = system.resetController.fields.duplicate()
		reset_fields.flags = int(reset_fields.flags)&~6
		var reset_mapped: float = Math.controller_time(reset_fields,now)
		var needs_reset: bool = system.lastResetMapped != null and system.lastResetMapped > reset_mapped
		system.lastResetMapped = reset_mapped
		var previous: float = system.lastUpdate if system.lastUpdate != null else now
		var relative: Dictionary = Math.compose(Math.inverse(system.world),worlds[int(system.emitter.fields.emitter_object.ref)])
		var packets: Array = system.controller.advance(now,previous)
		for packet in packets: system.pool.emit(system.emitter.fields,packet,relative,rng)
		system.pool.commit()
		if needs_reset or (system.lastUpdate != null and system.lastUpdate > now):
			system.pool.reset()
			system.lastUpdate = null
		if system.lastUpdate == null: system.lastUpdate = now
		for modifier in system.modifiers:
			var m: Dictionary = modifier.fields
			if not m.active: continue
			match modifier.type:
				"NiPSysAgeDeathModifier": system.pool.age_death(now,m)
				"NiPSysGrowFadeModifier":
					for particle in system.pool.active(): particle.size = Math.grow_fade(m,particle)
				"NiPSysColorModifier":
					for particle in system.pool.active(): particle.color = Math.particle_color(blocks[int(m.data.ref)].fields.data,particle)
				"NiPSysGravityModifier":
					var gravity: Dictionary = Math.compose(Math.inverse(system.world),worlds[int(m.gravity_object.ref)])
					var axis: Array = Math.normalize(Math.transform_vector(gravity.rotation,Math.vector(m.gravity_axis)))
					for i in system.pool.num_active:
						var particle: Dictionary = system.pool.particles[i]
						system.pool.particles[i] = Math.planar_gravity(m,particle,gravity.translation,axis,now) if int(m.force_type) == 0 else Math.sphere_gravity(m,particle,gravity.translation,now)
				"NiPSysPositionModifier": system.pool.position(now)
				"NiPSysBoxEmitter", "NiPSysSpawnModifier": pass # Original nullsub_5 update slot.
				"NiPSysBoundUpdateModifier":
					system.boundCounter = (int(system.boundCounter)+1)&65535
					if system.boundCounter > m.update_skip:
						var vertices := []
						for particle in system.pool.active(): vertices.append(particle.position)
						system.bounds = Math.bounds(vertices)
						if system.pool.num_active != 0 and system.bounds.radius == 0.0:
							system.bounds.radius = Math.f32(system.pool.particles[0].size*system.pool.particles[0].radius)
						system.boundCounter = 0
				_: assert(false,"Unsupported original modifier " + str(modifier.type))
		system.lastUpdate = now
	time = now

func fork():
	var out = get_script().new({},seed_value,{})
	out.asset = asset
	out.blocks = blocks
	out.time = time
	out.rng.state = rng.state
	out.rng.draws = rng.draws
	for i in systems.size():
		var source: Dictionary = systems[i]
		var target: Dictionary = source.duplicate()
		target.modifiers = source.modifiers.duplicate()
		target.controller = source.controller.fork()
		target.pool = source.pool.fork()
		target.world = source.world.duplicate(true)
		target.bounds = source.bounds.duplicate(true)
		out.systems.append(target)
	return out

func source_state() -> Dictionary:
	var records := []
	for system in systems:
		var pool = system.pool
		records.append({"block":system.block.id,"capacity":pool.capacity,"numActive":pool.num_active,"pendingCount":pool.pending_count,"pendingStart":pool.pending_start,"births":pool.births,"requested":pool.requested,"deaths":pool.deaths,"particles":pool.particles.duplicate(true),"bounds":system.bounds.duplicate(true),"boundCounter":system.boundCounter,"world":system.world.duplicate(true)})
	return {"rng":{"state":rng.state,"draws":rng.draws},"systems":records}

func snapshot() -> Array:
	var records := []
	for system in systems:
		for i in system.pool.num_active:
			var record: Dictionary = system.pool.particles[i].duplicate(true)
			record.asset = asset.name
			record.block = system.block.id
			record.name = system.block.name
			record.particle = i
			record.world = system.world.duplicate(true)
			record.world_position = Math.point(system.world,record.position)
			records.append(record)
	return records

func sample_property_controller(controller: Dictionary):
	return Math.sample_keys(blocks[int(controller.fields.data.ref)].fields.data,Math.controller_time(controller.fields,time))

func _particle_quad_context(world: Dictionary, camera: Dictionary) -> Dictionary:
	return Math.particle_quad_context(world,camera)

func _particle_quad_from_context(particle: Dictionary, context: Dictionary) -> Dictionary:
	return Math.particle_quad_prepared(particle,context)

func _particle_uv_template(desc: Dictionary, values: Dictionary) -> Array:
	return Math.particle_uv_template(desc,values)

func particle_meshes(camera: Dictionary) -> Array:
	var meshes := []
	for system in systems:
		if system.pool.num_active == 0: continue
		var properties := {}
		for ref in system.block.fields.properties:
			var property: Dictionary = blocks[int(ref.ref)]
			properties[property.type] = property
		var texturing: Dictionary = properties.NiTexturingProperty
		var alpha: Dictionary = properties.get("NiAlphaProperty",{})
		var desc: Dictionary = texturing.fields.base_texture
		var source: Dictionary = blocks[int(desc.source.ref)]
		var values := {}
		for controller in controllers(texturing): values[int(controller.fields.operation)] = sample_property_controller(controller)
		var context := _particle_quad_context(system.world,camera)
		var uv_template := _particle_uv_template(desc,values)
		for i in system.pool.num_active:
			var particle: Dictionary = system.pool.particles[i]
			var quad: Dictionary = _particle_quad_from_context(particle,context)
			var vertices := []
			# Output records retain their original independent writable UV arrays.
			var uvs := uv_template.duplicate(true)
			for p in quad.vertices: vertices.append(Math.point(system.world,p))
			meshes.append({"asset":asset.name,"block":system.block.id,"name":system.block.name,"particle":i,"texture":str(source.fields.file_name).to_lower(),"vertices":vertices,"uvs":uvs,"triangles":quad.triangles,"color":quad.color.slice(0,3),"alpha":quad.color[3],"alphaFlags":alpha.get("fields",{}).get("flags",0),"threshold":alpha.get("fields",{}).get("threshold",0),"clampMode":desc.clamp_mode,"filterMode":desc.filter_mode,"world":{"translation":Math.point(system.world,particle.position)},"argb":quad.argb})
	return meshes

func particle_system_meshes(camera: Dictionary) -> Array:
	batch_error = ""
	var meshes: Array = []
	for system: Dictionary in systems:
		var id := int(system.block.id)
		var batch: RefCounted = _particle_batches.get(id)
		if batch == null:
			# Reserve each original system's complete capacity, including zero-active
			# systems. Every lifecycle owns these buffers; no static mutable arena.
			batch = Batch.new(int(system.pool.capacity)); _particle_batches[id] = batch
		if system.pool.num_active == 0:
			batch.fill(system.pool.particles,0,system.world,camera)
			continue
		var record: Dictionary = _batch_records.get(id,{})
		var texturing: Dictionary
		if record.is_empty():
			var properties := {}
			for ref in system.block.fields.properties:
				var property: Dictionary = blocks[int(ref.ref)]; properties[property.type] = property
			texturing = properties.NiTexturingProperty
			var desc: Dictionary = texturing.fields.base_texture
			var alpha: Dictionary = properties.get("NiAlphaProperty",{}).get("fields",{})
			record = {"asset":asset.name,"block":id,"name":system.block.name,"kind":"particle system","batch":batch,
				"texture":str(blocks[int(desc.source.ref)].fields.file_name).to_lower(),"alphaFlags":alpha.get("flags",0),"threshold":alpha.get("threshold",0),
				"clampMode":desc.clamp_mode,"filterMode":desc.filter_mode,"texturing_block":int(texturing.id)}
			_batch_records[id] = record
		else: texturing = blocks[int(record.texturing_block)]
		var values := {}
		for controller in controllers(texturing): values[int(controller.fields.operation)] = sample_property_controller(controller)
		var uv_template := _particle_uv_template(texturing.fields.base_texture,values)
		var data: Dictionary = blocks[int(system.block.fields.data.ref)].fields
		# Filling is observable work. Never put this call in assert: release
		# exports omit assertions, but must still produce the complete stream.
		var filled: bool = batch.fill(system.pool.particles,int(system.pool.num_active),system.world,camera,uv_template,bool(data.get("has_vertex_colors",true)))
		if not filled:
			batch_error = "Original CPU particle batch rejected its native active prefix"
			return []
		# Borrowed mutable system descriptor. Caller consumes after its worker join
		# and before a subsequent fill; main never reads a pending worker payload.
		record.world = system.world; record.bounds = system.bounds
		meshes.append(record)
	return meshes

func _visit_mesh(block: Dictionary, inherited: Dictionary, visible: bool, now: float, worlds: Dictionary, meshes: Array) -> void:
	var properties: Dictionary = inherited.duplicate()
	for ref in block.fields.get("properties",[]):
		var property: Dictionary = blocks[int(ref.ref)]
		properties[property.type] = property
	visible = visible and not (int(block.fields.get("flags",0))&1)
	for controller in controllers(block):
		if controller.type == "NiVisController":
			visible = visible and Math.visibility_at(blocks[int(controller.fields.data.ref)].fields.keys,Math.controller_time(controller.fields,now))
	if visible and block.type in ["NiTriShape","NiTriStrips"]:
		var data: Dictionary = blocks[int(block.fields.data.ref)]
		var texturing: Dictionary = properties.NiTexturingProperty
		var desc: Dictionary = texturing.fields.base_texture
		var material: Dictionary = properties.get("NiMaterialProperty",{})
		var alpha_property: Dictionary = properties.get("NiAlphaProperty",{})
		var values := {}
		var alpha: float = material.get("fields",{}).get("alpha",1.0)
		if not material.is_empty():
			for controller in controllers(material): alpha = Math.sample_keys(blocks[int(controller.fields.data.ref)].fields.data,Math.controller_time(controller.fields,now))
		for controller in controllers(texturing): values[int(controller.fields.operation)] = Math.sample_keys(blocks[int(controller.fields.data.ref)].fields.data,Math.controller_time(controller.fields,now))
		var world: Dictionary = worlds[int(block.id)]
		var vertices := []
		var uvs := []
		for vertex in data.fields.vertices: vertices.append(Math.point(world,Math.vector(vertex)))
		for uv in data.fields.uv_sets[int(desc.uv_set)]: uvs.append(Math.texture_uv([uv.u,uv.v],desc,values))
		var color: Array = [1.0,1.0,1.0]
		if not material.is_empty(): color = [material.fields.diffuse_color.r,material.fields.diffuse_color.g,material.fields.diffuse_color.b]
		var mesh := {"asset":asset.name,"block":block.id,"name":block.name,"kind":"authored mesh","texture":str(blocks[int(desc.source.ref)].fields.file_name).to_lower(),"vertices":vertices,"uvs":uvs,"triangles":data.effective_triangles,"color":color,"alpha":alpha,"alphaFlags":alpha_property.get("fields",{}).get("flags",0),"threshold":alpha_property.get("fields",{}).get("threshold",0),"clampMode":desc.clamp_mode,"filterMode":desc.filter_mode,"world":world,"sourceRenderScope":"original authored mesh and alpha/UV controllers; unlit material observer, ordinary vertex-color upload/lighting unresolved"}
		if data.fields.has("vertex_colors"): mesh.vertexColors = data.fields.vertex_colors
		if not material.is_empty(): mesh.material = material.fields
		meshes.append(mesh)
	for ref in block.fields.get("children",[]): _visit_mesh(blocks[int(ref.ref)],properties,visible,now,worlds,meshes)

func authored_meshes(now: float) -> Array:
	var meshes := []
	var worlds: Dictionary = authored_world_transforms(now)
	for root in asset.roots: _visit_mesh(blocks[int(root)],{},true,now,worlds,meshes)
	return meshes

func meshes(camera: Dictionary) -> Array:
	return particle_meshes(camera)+authored_meshes(time)

func batch_meshes(camera: Dictionary) -> Array:
	var meshes := particle_system_meshes(camera)
	if not batch_error.is_empty(): return []
	# Authored splash columns/rings retain distinct geometry, controllers and
	# materials. Their sort key uses the source geometry's bound, before waves.
	for record: Dictionary in authored_meshes(time):
		var data: Dictionary = blocks[int(blocks[int(record.block)].fields.data.ref)].fields
		record.bounds = {"center":Math.vector(data.center),"radius":data.radius}
		meshes.append(record)
	return meshes
