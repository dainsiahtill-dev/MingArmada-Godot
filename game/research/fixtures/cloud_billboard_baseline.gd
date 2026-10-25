extends RefCounted
## Private render-state compiler. Original source replay remains the full oracle.
## Immutable graph/geometry/controller references resolve once. Private kernels
## preserve the source operation/store order using one owner-local binary32 buffer.
const Native=preload("res://modules/scene_engine/fidelity_fx/cloud_native.gd")
const SourceMath=preload("res://modules/scene_engine/fidelity_island/native_math.gd")
const TransformKernel=preload("res://modules/scene_engine/fidelity_fx/cloud_transform_kernel.gd")
const CurveSampler=preload("res://modules/scene_engine/fidelity_fx/cloud_curve_sampler.gd")
var _float_store:=PackedFloat32Array()

func _init()->void:_float_store.resize(1)

func _f32(value:float)->float:
	_float_store[0]=value
	return _float_store[0]

func _advance_clock(clock:RefCounted,app_time:float)->float:
	# SourceMath.ControllerClock's expression/store sequence, with this
	# compiler's owner-local store. Native/SourceMath remain untouched oracles.
	# Clock state still belongs to its compiled controller, and is reset before
	# each render sample. This compiler is consumed sequentially by its owner;
	# neither its float storage nor mutable clocks are shared between workers.
	var c:Dictionary=clock.controller
	var now:float=_f32(app_time)
	var flags:int=int(c.get("flags",0))
	var delta:float=now-clock.last if clock.started else (0.0 if flags&1 else now)
	var sum:float=delta*float(c.get("frequency",1.0))+clock.accumulated
	clock.accumulated=_f32(sum)
	clock.last=now
	clock.started=true
	var raw:float=_f32(sum+float(c.get("phase",0.0)))
	var start:float=_f32(float(c.get("start_time",0.0)))
	var stop:float=_f32(float(c.get("stop_time",0.0)))
	var span:float=_f32(stop-start)
	var cycle:int=(flags >> 1)&3
	var mapped:float=raw
	if cycle==0:
		if span==0.0:mapped=start
		else:
			mapped=fmod(raw-start,span)+start
			if mapped<start:mapped+=span
	elif cycle==1:
		if span==0.0:mapped=start
		else:
			var twice:float=_f32(span+span)
			mapped=fmod(raw,twice)
			if mapped<0.0:mapped+=twice
			if mapped>span:mapped=twice-mapped
			mapped+=start
	mapped=clampf(mapped,start,stop)
	if flags&16:mapped=stop-(mapped-start)
	# No final float32 store: the original returns this mapped double value.
	return mapped

func _interpolate_float_keys(group:Dictionary,time:float)->float:
	var mapped:float=_f32(time)
	var keys:Array=group.get("keys",[])
	var kind:int=int(group.get("interpolation",0))
	if keys.is_empty() or kind not in [1,2]:return NAN
	if mapped<=float(keys[0].time):return _f32(float(keys[0].value))
	if mapped>=float(keys[-1].time):return _f32(float(keys[-1].value))
	var index:=0
	while mapped>float(keys[index+1].time):index+=1
	var left:Dictionary=keys[index];var right:Dictionary=keys[index+1]
	var t:float=_f32((mapped-_f32(float(left.time)))/(_f32(float(right.time))-_f32(float(left.time))))
	if kind==1:return _f32((1.0-t)*_f32(float(left.value))+t*_f32(float(right.value)))
	return _f32(SourceMath.native_bezier(t,_f32(float(left.value)),_f32(float(left.backward)),_f32(float(right.value)),_f32(float(right.forward))))

func _sample(group:Dictionary,time:float)->Variant:
	var keys:Array=group.get("keys",[])
	if keys.is_empty():return null
	if keys[0].value is float or keys[0].value is int:return _interpolate_float_keys(group,time)
	var mapped:=_f32(time)
	var a:Dictionary=keys[0];var b:Dictionary=keys[-1]
	if mapped<=float(a.time):return Native._vector(a.value)
	if mapped>=float(b.time):return Native._vector(b.value)
	var index:=0
	while mapped>float(keys[index+1].time):index+=1
	a=keys[index];b=keys[index+1]
	var fraction:=_f32((mapped-float(a.time))/(float(b.time)-float(a.time)))
	var av:=Native._vector(a.value);var bv:=Native._vector(b.value)
	var result:Array=[]
	for i in 3:result.append(_f32(_f32((1.0-fraction)*float(av[i]))+_f32(fraction*float(bv[i]))))
	return result

func _texture_transform(desc:Dictionary,overrides:Dictionary={})->PackedFloat32Array:
	var kind:int=int(desc.get("transform_type",-1))
	if kind not in [0,1]:return PackedFloat32Array()
	var translation:Dictionary=desc.get("translation",{})
	var scale:Dictionary=desc.get("tiling",desc.get("scale",{}))
	var center:Dictionary=desc.get("center_offset",desc.get("center",{}))
	var tu:float=float(overrides.get("translationU",translation.get("u",0.0)))
	var tv:float=float(overrides.get("translationV",translation.get("v",0.0)))
	var su:float=float(overrides.get("scaleU",scale.get("u",1.0)))
	var sv:float=float(overrides.get("scaleV",scale.get("v",1.0)))
	var cu:float=float(center.get("u",0.0));var cv:float=float(center.get("v",0.0))
	var angle:float=float(overrides.get("rotation",desc.get("w_rotation",desc.get("rotation",0.0))))
	var c:float=_f32(cos(angle));var s:float=_f32(sin(angle))
	# Each returned matrix remains owned by this result. The scratch scalar
	# store never escapes into a retained cloud/fog phase or another compiler.
	if kind==0:return PackedFloat32Array([c*su,s*su,0.0,-s*sv,c*sv,0.0,_f32(tu-cu)*c-(tv-cv)*s+cu,(tu-cu)*s+(tv-cv)*c+cv,1.0])
	return PackedFloat32Array([c*su,-s*sv,0.0,s*su,c*sv,0.0,su*(_f32(-cu-tu)*c+(tv-cv)*s)+cu,sv*((tv-cv)*c-_f32(-cu-tu)*s)+cv,1.0])

func _multiply_matrix(a:Array,b:Array)->Array:
	return TransformKernel.multiply(a,b)

func _transform_vector(matrix:Array,vector:Array)->Array:
	return TransformKernel.transform(matrix,vector)

func _transform_transpose(matrix:Array,vector:Array)->Array:
	return TransformKernel.transpose_transform(matrix,vector)

func _compose_transform(parent:Dictionary,local:Dictionary)->Dictionary:
	var moved:=_transform_vector(parent.rotation,local.translation)
	for i in 3:
		var product:=float(moved[i])*float(parent.scale)
		moved[i]=_f32((product if i==0 else _f32(product))+float(parent.translation[i]))
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

func bind_sequence(asset:Dictionary,sequence:Dictionary)->Dictionary:
	# Target adapter: bind explicit KF target names to owned per-target property
	# copies. KFM event selection is not recovered; caller chooses this sequence.
	var result:=asset.duplicate(true)
	var blocks:Dictionary={}
	var next_id:=0
	for block:Dictionary in result.blocks:
		blocks[int(block.id)]=block;next_id=maxi(next_id,int(block.id)+1)
	var remap:Dictionary={}
	for block:Dictionary in sequence.blocks:remap[int(block.id)]=next_id;next_id+=1
	for original:Dictionary in sequence.blocks:
		var block:=original.duplicate(true)
		block.id=remap[int(original.id)]
		_remap_references(block.fields,remap)
		result.blocks.append(block);blocks[int(block.id)]=block
	var source_root:Dictionary=sequence.blocks[int(sequence.roots[0])]
	for link:Dictionary in source_root.fields.get("controlled_blocks",[]):
		var names:=str(link.target_name).split("\nPROP\n")
		var target:Dictionary={}
		for block:Dictionary in result.blocks:
			if str(block.get("name",block.fields.get("name","")))==names[0] and str(block.type) in ["NiNode","NiBillboardNode","NiTriStrips","NiTriShape"]:target=block;break
		if target.is_empty():continue
		if names.size()==2:
			for property:Variant in target.fields.get("properties",[]):
				if property is Dictionary and str(property.type)==names[1]:
					var owned:Dictionary=blocks[int(property.ref)].duplicate(true)
					owned.id=next_id;next_id+=1
					result.blocks.append(owned);blocks[int(owned.id)]=owned
					property.ref=owned.id;target=owned;break
		var controller:Dictionary=blocks[int(remap[int(link.controller.ref)])]
		controller.fields.next_controller=target.fields.get("controller")
		target.fields.controller={"ref":controller.id,"type":controller.type}
	return result

func _remap_references(value:Variant,remap:Dictionary)->void:
	if value is Dictionary:
		if value.has("ref") and remap.has(int(value.ref)):value.ref=remap[int(value.ref)]
		else:
			for child:Variant in value.values():_remap_references(child,remap)
	elif value is Array:
		for child:Variant in value:_remap_references(child,remap)

func _instance_controllers(compiled:Dictionary)->Array:
	var result:Array=[]
	for node:Dictionary in compiled.roots:_collect_controllers(node,result)
	return result
func _collect_controllers(node:Dictionary,result:Array)->void:
	if node.is_empty():return
	result.append_array(node.keyframes)
	if node.has("leaf"):
		result.append_array(node.leaf.alphaControllers);result.append_array(node.leaf.uvControllers)
	for child:Dictionary in node.children:_collect_controllers(child,result)
func controller_snapshot(compiled:Dictionary)->Array:
	var result:Array=[]
	for controller:Dictionary in _instance_controllers(compiled):
		var clock:RefCounted=controller.clock
		result.append({"last":clock.last,"accumulated":clock.accumulated,"started":clock.started})
	return result
func restore_controllers(compiled:Dictionary,snapshot:Array)->bool:
	var controllers:=_instance_controllers(compiled)
	if controllers.size()!=snapshot.size():return false
	for index in controllers.size():
		var clock:RefCounted=controllers[index].clock
		clock.last=float(snapshot[index].last);clock.accumulated=float(snapshot[index].accumulated);clock.started=bool(snapshot[index].started)
	return true
func advance_controllers(compiled:Dictionary,app_time:float)->void:
	for controller:Dictionary in _instance_controllers(compiled):_clock_time(controller,app_time,true)

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
	var prepared:Dictionary={"clock":SourceMath.ControllerClock.new(controller.fields),"flags":int(controller.fields.get("flags",0)),"data":data,"sampler":CurveSampler.new(data)}
	if not data.has("keys"):
		for name:String in ["translations","scales"]:
			if not data.get(name,{}).get("keys",[]).is_empty():prepared[name]=CurveSampler.new(data[name])
	return prepared

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
		var static_uv:PackedFloat32Array=_texture_transform(desc,{}) if has_transform else PackedFloat32Array([1,0,0,0,1,0,0,0,1])
		var source:Dictionary={"asset":asset_name,"block":int(block.id),"texture":str(Native._ref(blocks,desc.get("source")).get("fields",{}).get("file_name","")).to_lower(),"localVertices":local_vertices,"sourceUV":data.fields.uv_sets[int(desc.get("uv_set",0))],"triangles":data.effective_triangles,"alpha":float(material.get("fields",{}).get("alpha",1.0)),"color":[float(diffuse.get("r",1.0)),float(diffuse.get("g",1.0)),float(diffuse.get("b",1.0))],"uvMatrix":static_uv,"alphaFlags":int(props.get("NiAlphaProperty",{}).get("fields",{}).get("flags",0)),"threshold":int(props.get("NiAlphaProperty",{}).get("fields",{}).get("threshold",0)),"clampMode":int(desc.get("clamp_mode",3)),"filterMode":int(desc.get("filter_mode",2)),"depthFlags":int(props.get("NiZBufferProperty",{}).get("fields",{}).get("flags",3)),"depthFunction":int(props.get("NiZBufferProperty",{}).get("fields",{}).get("function",3)),"stencil":props.get("NiStencilProperty",{}).get("fields",{}).duplicate(true)}
		# Retain inherited/overridden source properties rather than globally
		# enabling vertex alpha on clouds, shadow planes or particle systems.
		var vertex_property:Dictionary=props.get("NiVertexColorProperty",{}).get("fields",{})
		var authored_colors:=PackedColorArray()
		if bool(data.fields.get("has_vertex_colors",false)):
			for color:Dictionary in data.fields.get("vertex_colors",[]):authored_colors.append(Color(float(color.r),float(color.g),float(color.b),float(color.a)))
		source.authoredVertexColors=authored_colors
		source.hasVertexColors=authored_colors.size()==local_vertices.size() and not authored_colors.is_empty()
		source.vertexMode=int(vertex_property.get("vertex_mode",2))
		source.lightingMode=int(vertex_property.get("lighting_mode",1))
		var emissive:Dictionary=material.get("fields",{}).get("emissive_color",{})
		source.emissiveColor=[float(emissive.get("r",0.0)),float(emissive.get("g",0.0)),float(emissive.get("b",0.0))]
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

static func authored_surface_colors(state:Dictionary)->PackedColorArray:
	# NiVertexColorProperty: 0=ignore, 1=emission, 2=ambient/diffuse.
	# Lighting 0 disables ambient/diffuse; 1 keeps them. Only the diffuse
	# source carries authored alpha. Preserve material/controller alpha once.
	# This is the existing unlit Godot observer's color selection, not a
	# reconstruction of DX9 specular/ambient/emission lighting and pixels.
	var mode:=int(state.get("vertexMode",0))
	var lighting:=int(state.get("lightingMode",1))
	var use_colors:=bool(state.get("hasVertexColors",false)) and (mode==1 or (mode==2 and lighting==1))
	var original:PackedColorArray=state.get("authoredVertexColors",PackedColorArray())
	var selected:Array=state.get("emissiveColor",[0.0,0.0,0.0]) if mode==2 and lighting==0 else state.get("color",[1.0,1.0,1.0])
	var alpha:=float(state.get("alpha",1.0))
	var colors:=PackedColorArray()
	for i in state.localVertices.size():
		if use_colors:
			var color:Color=original[i]
			colors.append(Color(color.r,color.g,color.b,color.a*alpha if mode==2 else alpha))
		else:colors.append(Color(float(selected[0]),float(selected[1]),float(selected[2]),alpha))
	return colors

func _clock_time(controller:Dictionary,time:float,persistent:bool=false)->float:
	# Native instance owns its history. Seek/rebuild is an explicit lifecycle
	# operation, never a hidden reset on every sample or camera pass.
	var clock:RefCounted=controller.clock
	if not persistent:clock.reset()
	if not clock.started and int(controller.flags)&1:_advance_clock(clock,0.0)
	return _advance_clock(clock,time)

func render_states(compiled:Dictionary,time:float=0.0,outer:Dictionary={},animate:bool=false,camera:Dictionary={},include_vertices:bool=false,minimum_z:bool=false,persistent:bool=false)->Array:
	var result:Array=[]
	var initial:Dictionary={"rotation":Native.identity(),"translation":[0,0,0],"scale":1.0} if outer.is_empty() else outer
	for node:Dictionary in compiled.roots:_render_node(node,initial,{},time,animate,camera,include_vertices,minimum_z,result,persistent)
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

func _render_node(node:Dictionary,parent:Dictionary,inherited_billboard:Dictionary,time:float,animate:bool,camera:Dictionary,include_vertices:bool,minimum_z:bool,result:Array,persistent:bool=false)->void:
	if node.is_empty():return
	var local:Dictionary=node.local.duplicate() if animate else node.local
	if animate:
		for controller:Dictionary in node.keyframes:
			var mapped:float=_clock_time(controller,time,persistent)
			if controller.has("translations"):local.translation=controller.translations.sample(mapped)
			if controller.has("scales"):local.scale=controller.scales.sample(mapped)
	var world:Dictionary=_compose_transform(parent,local)
	var billboard:Dictionary={}
	if not inherited_billboard.is_empty():billboard={"parent":inherited_billboard.parent,"relative":_compose_transform(inherited_billboard.relative,local) if animate else node.staticBillboardRelative}
	if node.billboard:billboard={"parent":world.duplicate(),"relative":{"rotation":Native.identity(),"translation":[0.0,0.0,0.0],"scale":1.0} if animate else node.staticBillboardRelative}
	if node.billboard and not camera.is_empty():world.rotation=_billboard_mode0(world.rotation,camera)
	if node.has("leaf"):
		var leaf:Dictionary=node.leaf
		var state:Dictionary=leaf.source.duplicate()
		if animate:
			for controller:Dictionary in leaf.alphaControllers:state.alpha=controller.sampler.sample(_clock_time(controller,time,persistent))
			if leaf.hasTransform and not leaf.uvControllers.is_empty():
				var values:Dictionary={}
				var names:Array=["translationU","translationV","rotation","scaleU","scaleV"]
				for controller:Dictionary in leaf.uvControllers:values[names[int(controller.operation)]]=controller.sampler.sample(_clock_time(controller,time,persistent))
				state.uvMatrix=_texture_transform(leaf.desc,values)
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
	for child:Dictionary in node.children:_render_node(child,world,billboard,time,animate,camera,include_vertices,minimum_z,result,persistent)
