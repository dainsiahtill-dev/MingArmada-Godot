extends RefCounted
## Ports completed atmosphere reference math, not original engine scheduling.
## Native float stores are explicit; source matrices use original storage rows.
const Math = preload("res://modules/scene_engine/fidelity_island/native_math.gd")
const DEG2RAD := 0.01745329238474369
const CLOUD_THRESHOLD := 0.03333333507180214
const NAME_SCALE := 0.0010000000474974513
const FOG_PHASE_SCALE := 0.05000000074505806

class OriginalCrtRand extends RefCounted:
	var state: int
	var draws := 0
	func _init(seed_value: int) -> void:
		state = seed_value & 0xffffffff
	func next() -> int:
		state = (state*0x343fd+0x269ec3) & 0xffffffff
		draws += 1
		return (state >> 16) & 0x7fff

static func f32(value: float) -> float:
	return Math.f32(value)

static func identity() -> Array:
	return [1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,1.0]

static func rotation_z(angle: float) -> Array:
	var c := f32(cos(angle))
	var s := f32(sin(angle))
	return [c,s,0.0,-s,c,0.0,0.0,0.0,1.0]

static func rotation_x(angle: float) -> Array:
	var c := f32(cos(angle))
	var s := f32(sin(angle))
	return [1.0,0.0,0.0,0.0,c,s,0.0,-s,c]

static func multiply_matrix(a: Array, b: Array) -> Array:
	var result: Array = []
	for i in 9:
		var row := int(i/3)
		var col := i%3
		result.append(f32(float(a[row*3])*float(b[col])+float(a[row*3+1])*float(b[3+col])+float(a[row*3+2])*float(b[6+col])))
	return result

static func transform_vector(matrix: Array, vector: Array) -> Array:
	var result: Array = []
	for row in 3:
		result.append(f32(float(matrix[row*3])*float(vector[0])+float(matrix[row*3+1])*float(vector[1])+float(matrix[row*3+2])*float(vector[2])))
	return result

static func transform_transpose(matrix: Array, vector: Array) -> Array:
	var result: Array = []
	for col in 3:
		result.append(f32(float(matrix[6+col])*float(vector[2])+float(matrix[3+col])*float(vector[1])+float(matrix[col])*float(vector[0])))
	return result

static func billboard_mode0(rotation: Array, camera: Dictionary) -> Array:
	if not camera.has_all(["direction","up","right"]): return []
	var direction: Array = camera.direction.duplicate()
	for i in 3: direction[i] = f32(-float(direction[i]))
	var d := transform_transpose(rotation,direction)
	var u := transform_transpose(rotation,camera.up)
	var r := transform_transpose(rotation,camera.right)
	var length := sqrt(float(u[1])*float(u[1])+float(r[1])*float(r[1]))
	var adjust := identity()
	adjust[2] = d[0]; adjust[5] = d[1]; adjust[8] = d[2]
	if length <= 9.999999974752427e-7:
		for i in 3:
			adjust[i*3] = f32(-float(r[i]))
			adjust[i*3+1] = f32(-float(u[i]))
	else:
		var v18 := float(u[1])/length
		var v19 := -float(r[1])/length
		for i in 3:
			adjust[i*3] = f32(float(u[i])*v19+float(r[i])*v18)
			adjust[i*3+1] = f32(float(u[i])*v18-float(r[i])*v19)
	return multiply_matrix(rotation,adjust)

static func create_cloud_ring(seed_value: int) -> Dictionary:
	var rng := OriginalCrtRand.new(seed_value)
	return create_cloud_ring_from_rand(rng.next)

static func create_cloud_ring_from_rand(rand_value: Callable) -> Dictionary:
	var nodes: Array = []
	var angle := 0
	var draws := 0
	while angle < 360:
		var name := "%5d" % -(int(rand_value.call())%1500)
		var prototype := int(rand_value.call())%5+1
		var tilt := -(int(rand_value.call())%10)
		nodes.append({"name":name,"prototype":"domecloud%d.nif"%prototype,"azimuthDegrees":angle,"tiltDegrees":tilt,"translation":[0,1,0],"scale":1.0,"rotation":multiply_matrix(rotation_z(f32(angle*DEG2RAD)),rotation_x(f32(tilt*DEG2RAD)))})
		angle += int(rand_value.call())%5+10
		draws += 4
	return {"nodes":nodes,"accumulator":0.0,"updates":0,"draws":draws}

static func advance_clouds(state: Dictionary, delta: float) -> void:
	var stored_delta := f32(delta)
	var accumulated := float(state.accumulator)+stored_delta
	state.accumulator = f32(accumulated)
	# Original performs exactly one subtraction and rotates using input delta.
	if accumulated > CLOUD_THRESHOLD:
		state.accumulator = f32(accumulated-CLOUD_THRESHOLD)
		for node: Dictionary in state.nodes:
			var angle := f32(float(str(node.name))*NAME_SCALE*stored_delta*DEG2RAD)
			node.rotation = multiply_matrix(rotation_z(angle),node.rotation)
		state.updates = int(state.updates)+1

static func compose_transform(parent: Dictionary, local: Dictionary) -> Dictionary:
	var scaled: Array = []
	for value: Variant in local.translation: scaled.append(float(value)*float(parent.scale))
	var moved := transform_vector(parent.rotation,scaled)
	for i in 3: moved[i] = f32(float(moved[i])+float(parent.translation[i]))
	return {"rotation":multiply_matrix(parent.rotation,local.rotation),"translation":moved,"scale":f32(float(parent.scale)*float(local.scale))}

static func _vector(value: Dictionary) -> Array:
	return [float(value.get("x",0.0)),float(value.get("y",0.0)),float(value.get("z",0.0))]

static func _static_transform(fields: Dictionary) -> Dictionary:
	var r: Dictionary = fields.get("rotation",{})
	var rotation := identity() if r.is_empty() else [r.m_11,r.m_21,r.m_31,r.m_12,r.m_22,r.m_32,r.m_13,r.m_23,r.m_33]
	return {"rotation":rotation,"translation":_vector(fields.get("translation",{})),"scale":float(fields.get("scale",1.0))}

static func _ref(blocks: Dictionary, reference: Variant) -> Dictionary:
	return blocks.get(int(reference.get("ref",-1)),{}) if reference is Dictionary else {}

static func _controllers(blocks: Dictionary, block: Dictionary) -> Array:
	var result: Array = []
	var current := _ref(blocks,block.get("fields",{}).get("controller"))
	while not current.is_empty():
		result.append(current)
		current = _ref(blocks,current.fields.get("next_controller"))
	return result

static func _controller_time(fields: Dictionary, time: float) -> float:
	var clock := Math.ControllerClock.new(fields)
	if int(fields.get("flags",0)) & 1: clock.advance(0.0)
	return clock.advance(time)

static func _sample(group: Dictionary, time: float) -> Variant:
	var keys: Array = group.get("keys",[])
	if keys.is_empty(): return null
	if keys[0].value is float or keys[0].value is int:
		return Math.interpolate_float_keys(group,time)
	var mapped := f32(time)
	var a: Dictionary = keys[0]
	var b: Dictionary = keys[-1]
	if mapped <= float(a.time): return _vector(a.value)
	if mapped >= float(b.time): return _vector(b.value)
	var index := 0
	while mapped > float(keys[index+1].time): index += 1
	a = keys[index]; b = keys[index+1]
	var fraction := f32((mapped-float(a.time))/(float(b.time)-float(a.time)))
	var av := _vector(a.value)
	var bv := _vector(b.value)
	var result: Array = []
	for i in 3: result.append(f32(f32((1.0-fraction)*float(av[i]))+f32(fraction*float(bv[i]))))
	return result

static func original_meshes(asset: Dictionary, time: float = 0.0, outer: Dictionary = {}, animate: bool = false, camera: Dictionary = {}) -> Array:
	var blocks := {}
	for block: Dictionary in asset.get("blocks",[]): blocks[int(block.id)] = block
	var result: Array = []
	var initial := {"rotation":identity(),"translation":[0,0,0],"scale":1.0} if outer.is_empty() else outer
	for source_root: Variant in asset.get("roots",[]):
		_visit(blocks,blocks.get(int(source_root),{}),initial,{},time,animate,camera,str(asset.get("name","")),result)
	return result

static func _visit(blocks: Dictionary, block: Dictionary, parent: Dictionary, inherited: Dictionary, time: float, animate: bool, camera: Dictionary, asset_name: String, result: Array) -> void:
	if block.is_empty(): return
	var fields: Dictionary = block.fields
	var local := _static_transform(fields)
	if animate:
		for controller: Dictionary in _controllers(blocks,block):
			if controller.type != "NiKeyframeController": continue
			var data: Dictionary = _ref(blocks,controller.fields.data).get("fields",{})
			var mapped := _controller_time(controller.fields,time)
			if not data.get("translations",{}).get("keys",[]).is_empty(): local.translation = _sample(data.translations,mapped)
			if not data.get("scales",{}).get("keys",[]).is_empty(): local.scale = _sample(data.scales,mapped)
	var world := compose_transform(parent,local)
	var billboard: Dictionary = inherited.get("_draw_billboard",{}).duplicate(true)
	if not billboard.is_empty(): billboard.relative=compose_transform(billboard.relative,local)
	if block.type == "NiBillboardNode": billboard={"parent":world.duplicate(true),"relative":{"rotation":identity(),"translation":[0.0,0.0,0.0],"scale":1.0}}
	if block.type == "NiBillboardNode" and not camera.is_empty(): world.rotation = billboard_mode0(world.rotation,camera)
	var props := inherited.duplicate()
	if not billboard.is_empty(): props._draw_billboard=billboard
	for reference: Variant in fields.get("properties",[]):
		var property := _ref(blocks,reference)
		props[str(property.type)] = property
	if str(block.type) in ["NiTriStrips","NiTriShape"]:
		var data := _ref(blocks,fields.data)
		var material: Dictionary = props.get("NiMaterialProperty",{})
		var texturing: Dictionary = props.get("NiTexturingProperty",{})
		var desc: Dictionary = texturing.get("fields",{}).get("base_texture",{})
		var texture := str(_ref(blocks,desc.get("source")).get("fields",{}).get("file_name","")).to_lower()
		var alpha := float(material.get("fields",{}).get("alpha",1.0))
		var uv_values := {}
		if animate:
			for controller: Dictionary in _controllers(blocks,material):
				if controller.type == "NiAlphaController": alpha = _sample(_ref(blocks,controller.fields.data).fields.data,_controller_time(controller.fields,time))
			for controller: Dictionary in _controllers(blocks,texturing):
				if controller.type == "NiTextureTransformController": uv_values[int(controller.fields.operation)] = _sample(_ref(blocks,controller.fields.data).fields.data,_controller_time(controller.fields,time))
		var values := {}
		var names := ["translationU","translationV","rotation","scaleU","scaleV"]
		for operation: Variant in uv_values: values[names[int(operation)]] = uv_values[operation]
		var uv_matrix := Math.texture_transform(desc,values) if desc.get("has_texture_transform",false) else PackedFloat32Array([1,0,0,0,1,0,0,0,1])
		var vertices: Array = []
		var local_vertices: Array = []
		for v: Dictionary in data.fields.vertices:
			var original := _vector(v)
			local_vertices.append(original)
			var scaled: Array = []
			for value: Variant in original: scaled.append(float(value)*float(world.scale))
			var transformed := transform_vector(world.rotation,scaled)
			for i in 3: transformed[i] = f32(float(transformed[i])+float(world.translation[i]))
			vertices.append(transformed)
		var uv_source: Array = data.fields.uv_sets[int(desc.get("uv_set",0))]
		var uvs: Array = []
		for v: Dictionary in uv_source:
			uvs.append([f32(float(uv_matrix[0])*float(v.u)+float(uv_matrix[3])*float(v.v)+float(uv_matrix[6])),f32(float(uv_matrix[1])*float(v.u)+float(uv_matrix[4])*float(v.v)+float(uv_matrix[7]))])
		var diffuse: Dictionary = material.get("fields",{}).get("diffuse_color",{})
		result.append({"asset":asset_name,"block":int(block.id),"texture":texture,"vertices":vertices,"localVertices":local_vertices,"sourceUV":uv_source,"uvs":uvs,"uvMatrix":uv_matrix,"triangles":data.effective_triangles,"alpha":alpha,"color":[float(diffuse.get("r",1.0)),float(diffuse.get("g",1.0)),float(diffuse.get("b",1.0))],"alphaFlags":int(props.get("NiAlphaProperty",{}).get("fields",{}).get("flags",0)),"threshold":int(props.get("NiAlphaProperty",{}).get("fields",{}).get("threshold",0)),"clampMode":int(desc.get("clamp_mode",3)),"filterMode":int(desc.get("filter_mode",2)),"world":world})
		if not billboard.is_empty(): result[-1].billboard=billboard
	for reference: Variant in fields.get("children",[]): _visit(blocks,_ref(blocks,reference),world,props,time,animate,camera,asset_name,result)
