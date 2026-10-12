extends RefCounted
## Private render-state compiler. Original source replay remains the full oracle.
## Immutable graph/geometry/controller references resolve once. Private kernels
## preserve the source operation/store order using one owner-local binary32 buffer.
const Native=preload("res://modules/scene_engine/fidelity_fx/cloud_native.gd")
const SourceMath=preload("res://modules/scene_engine/fidelity_island/native_math.gd")
var _float_store:=PackedFloat32Array()

func _init()->void:_float_store.resize(1)

func _f32(value:float)->float:
	_float_store[0]=value
	return _float_store[0]

func _multiply_matrix(a:Array,b:Array)->Array:
	var result:Array=[]
	for i in 9:
		var row:=int(i/3);var col:=i%3
		result.append(_f32(float(a[row*3])*float(b[col])+float(a[row*3+1])*float(b[3+col])+float(a[row*3+2])*float(b[6+col])))
	return result

func _transform_vector(matrix:Array,vector:Array)->Array:
	var result:Array=[]
	for row in 3:result.append(_f32(float(matrix[row*3])*float(vector[0])+float(matrix[row*3+1])*float(vector[1])+float(matrix[row*3+2])*float(vector[2])))
	return result

func _transform_transpose(matrix:Array,vector:Array)->Array:
	var result:Array=[]
	for col in 3:result.append(_f32(float(matrix[6+col])*float(vector[2])+float(matrix[3+col])*float(vector[1])+float(matrix[col])*float(vector[0])))
	return result

func _compose_transform(parent:Dictionary,local:Dictionary)->Dictionary:
	var scaled:Array=[]
	for value:Variant in local.translation:scaled.append(float(value)*float(parent.scale))
	var moved:=_transform_vector(parent.rotation,scaled)
	for i in 3:moved[i]=_f32(float(moved[i])+float(parent.translation[i]))
	return {"rotation":_multiply_matrix(parent.rotation,local.rotation),"translation":moved,"scale":_f32(float(parent.scale)*float(local.scale))}

func _billboard_mode0(rotation:Array,camera:Dictionary)->Array:
	if not camera.has_all(["direction","up","right"]):return []
	var direction:Array=camera.direction.duplicate()
	for i in 3:direction[i]=_f32(-float(direction[i]))
	var d:=_transform_transpose(rotation,direction)
	var u:=_transform_transpose(rotation,camera.up)
	var r:=_transform_transpose(rotation,camera.right)
	var length:=sqrt(float(u[1])*float(u[1])+float(r[1])*float(r[1]))
	var adjust:=Native.identity()
	adjust[2]=d[0];adjust[5]=d[1];adjust[8]=d[2]
	if length<=9.999999974752427e-7:
		for i in 3:
			adjust[i*3]=_f32(-float(r[i]))
			adjust[i*3+1]=_f32(-float(u[i]))
	else:
		var v18:=float(u[1])/length;var v19:=-float(r[1])/length
		for i in 3:
			adjust[i*3]=_f32(float(u[i])*v19+float(r[i])*v18)
			adjust[i*3+1]=_f32(float(u[i])*v18-float(r[i])*v19)
	return _multiply_matrix(rotation,adjust)

func compile_asset(asset:Dictionary)->Dictionary:
	var blocks:Dictionary={}
	for block:Dictionary in asset.get("blocks",[]):blocks[int(block.id)]=block
	var roots:Array=[]
	for id:Variant in asset.get("roots",[]):
		var node:=_compile_node(blocks,blocks.get(int(id),{}),{},str(asset.get("name","")))
		_compile_static_billboard(node,{})
		roots.append(node)
	return {"roots":roots}

func _compile_static_billboard(node:Dictionary,inherited:Dictionary)->void:
	if node.is_empty():return
	var relative:Dictionary=_compose_transform(inherited,node.local) if not inherited.is_empty() else {}
	if node.billboard:relative={"rotation":Native.identity(),"translation":[0.0,0.0,0.0],"scale":1.0}
	# The unanimated cloud-relative frame depends only on authored local TRS.
	# Preserve its sequential binary32 composition, without recomposing it for
	# each clone/current camera or copying unchanged arrays through descendants.
	node.staticBillboardRelative=relative
	for child:Dictionary in node.children:_compile_static_billboard(child,relative)

func _controller(controller:Dictionary,data:Dictionary)->Dictionary:
	return {"clock":SourceMath.ControllerClock.new(controller.fields),"flags":int(controller.fields.get("flags",0)),"data":data}

func _compile_node(blocks:Dictionary,block:Dictionary,inherited:Dictionary,asset_name:String)->Dictionary:
	if block.is_empty():return {}
	var fields:Dictionary=block.fields
	var props:Dictionary=inherited.duplicate()
	for reference:Variant in fields.get("properties",[]):
		var property:Dictionary=Native._ref(blocks,reference)
		props[str(property.type)]=property
	var node:Dictionary={"local":Native._static_transform(fields),"billboard":block.type=="NiBillboardNode","keyframes":[],"children":[]}
	for controller:Dictionary in Native._controllers(blocks,block):
		if controller.type=="NiKeyframeController":
			node.keyframes.append(_controller(controller,Native._ref(blocks,controller.fields.data).get("fields",{})))
	if str(block.type) in ["NiTriStrips","NiTriShape"]:
		var data:Dictionary=Native._ref(blocks,fields.data)
		var material:Dictionary=props.get("NiMaterialProperty",{})
		var texturing:Dictionary=props.get("NiTexturingProperty",{})
		var desc:Dictionary=texturing.get("fields",{}).get("base_texture",{})
		var diffuse:Dictionary=material.get("fields",{}).get("diffuse_color",{})
		var local_vertices:Array=[]
		for vertex:Dictionary in data.fields.vertices:local_vertices.append(Native._vector(vertex))
		var has_transform:bool=bool(desc.get("has_texture_transform",false))
		var static_uv:PackedFloat32Array=SourceMath.texture_transform(desc,{}) if has_transform else PackedFloat32Array([1,0,0,0,1,0,0,0,1])
		var source:Dictionary={"asset":asset_name,"block":int(block.id),"texture":str(Native._ref(blocks,desc.get("source")).get("fields",{}).get("file_name","")).to_lower(),"localVertices":local_vertices,"sourceUV":data.fields.uv_sets[int(desc.get("uv_set",0))],"triangles":data.effective_triangles,"alpha":float(material.get("fields",{}).get("alpha",1.0)),"color":[float(diffuse.get("r",1.0)),float(diffuse.get("g",1.0)),float(diffuse.get("b",1.0))],"uvMatrix":static_uv,"alphaFlags":int(props.get("NiAlphaProperty",{}).get("fields",{}).get("flags",0)),"threshold":int(props.get("NiAlphaProperty",{}).get("fields",{}).get("threshold",0)),"clampMode":int(desc.get("clamp_mode",3)),"filterMode":int(desc.get("filter_mode",2))}
		var leaf:Dictionary={"source":source,"desc":desc,"hasTransform":has_transform,"alphaControllers":[],"uvControllers":[]}
		for controller:Dictionary in Native._controllers(blocks,material):
			if controller.type=="NiAlphaController":leaf.alphaControllers.append(_controller(controller,Native._ref(blocks,controller.fields.data).fields.data))
		for controller:Dictionary in Native._controllers(blocks,texturing):
			if controller.type=="NiTextureTransformController":
				var prepared:Dictionary=_controller(controller,Native._ref(blocks,controller.fields.data).fields.data)
				prepared.operation=int(controller.fields.operation)
				leaf.uvControllers.append(prepared)
		node.leaf=leaf
	for reference:Variant in fields.get("children",[]):node.children.append(_compile_node(blocks,Native._ref(blocks,reference),props,asset_name))
	return node

func _clock_time(controller:Dictionary,time:float)->float:
	# The full oracle creates a fresh clock per sample. Reusing its allocation
	# requires an exact reset, including the source's optional advance(0) call.
	var clock:RefCounted=controller.clock
	clock.reset()
	if int(controller.flags)&1:clock.advance(0.0)
	return clock.advance(time)

func render_states(compiled:Dictionary,time:float=0.0,outer:Dictionary={},animate:bool=false,camera:Dictionary={},include_vertices:bool=false,minimum_z:bool=false)->Array:
	var result:Array=[]
	var initial:Dictionary={"rotation":Native.identity(),"translation":[0,0,0],"scale":1.0} if outer.is_empty() else outer
	for node:Dictionary in compiled.roots:_render_node(node,initial,{},time,animate,camera,include_vertices,minimum_z,result)
	return result

func render_minimum_states(compiled:Dictionary,outer:Dictionary,camera:Dictionary)->Array:
	return render_states(compiled,0.0,outer,false,camera,false,true)

func _minimum_z(vertices:Array,world:Dictionary)->float:
	var minimum:=INF
	var matrix:Array=world.rotation
	for original:Array in vertices:
		var x:=float(original[0])*float(world.scale)
		var y:=float(original[1])*float(world.scale)
		var z:=float(original[2])*float(world.scale)
		# Exact row2 of the full oracle, including its separate vector/addition
		# stores. X/Y results and transformed arrays never affect the minimum.
		var transformed:=_f32(float(matrix[6])*x+float(matrix[7])*y+float(matrix[8])*z)
		minimum=minf(minimum,_f32(float(transformed)+float(world.translation[2])))
	return minimum

func _render_node(node:Dictionary,parent:Dictionary,inherited_billboard:Dictionary,time:float,animate:bool,camera:Dictionary,include_vertices:bool,minimum_z:bool,result:Array)->void:
	if node.is_empty():return
	var local:Dictionary=node.local.duplicate() if animate else node.local
	if animate:
		for controller:Dictionary in node.keyframes:
			var data:Dictionary=controller.data
			var mapped:float=_clock_time(controller,time)
			if not data.get("translations",{}).get("keys",[]).is_empty():local.translation=Native._sample(data.translations,mapped)
			if not data.get("scales",{}).get("keys",[]).is_empty():local.scale=Native._sample(data.scales,mapped)
	var world:Dictionary=_compose_transform(parent,local)
	var billboard:Dictionary={}
	if not inherited_billboard.is_empty():billboard={"parent":inherited_billboard.parent,"relative":_compose_transform(inherited_billboard.relative,local) if animate else node.staticBillboardRelative}
	if node.billboard:billboard={"parent":world.duplicate(),"relative":{"rotation":Native.identity(),"translation":[0.0,0.0,0.0],"scale":1.0} if animate else node.staticBillboardRelative}
	if node.billboard and not camera.is_empty():world.rotation=_billboard_mode0(world.rotation,camera)
	if node.has("leaf"):
		var leaf:Dictionary=node.leaf
		var state:Dictionary=leaf.source.duplicate()
		if animate:
			for controller:Dictionary in leaf.alphaControllers:state.alpha=Native._sample(controller.data,_clock_time(controller,time))
			if leaf.hasTransform and not leaf.uvControllers.is_empty():
				var values:Dictionary={}
				var names:Array=["translationU","translationV","rotation","scaleU","scaleV"]
				for controller:Dictionary in leaf.uvControllers:values[names[int(controller.operation)]]=Native._sample(controller.data,_clock_time(controller,time))
				state.uvMatrix=SourceMath.texture_transform(leaf.desc,values)
		state.world=world
		if not billboard.is_empty():state.billboard=billboard
		if include_vertices:
			var vertices:Array=[]
			for original:Array in state.localVertices:
				var scaled:Array=[]
				for value:Variant in original:scaled.append(float(value)*float(world.scale))
				var transformed:Array=_transform_vector(world.rotation,scaled)
				for i in 3:transformed[i]=_f32(float(transformed[i])+float(world.translation[i]))
				vertices.append(transformed)
			state.vertices=vertices
		if minimum_z:state.minimumZ=_minimum_z(state.localVertices,world)
		result.append(state)
	for child:Dictionary in node.children:_render_node(child,world,billboard,time,animate,camera,include_vertices,minimum_z,result)
