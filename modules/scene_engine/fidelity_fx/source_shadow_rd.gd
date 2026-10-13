extends RefCounted
## Actual two-draw stencil z-pass backend. Owned stencil, sampled scene depth.
## The sampled reverse-Z receiver test is a declared Godot adaptation.
var rd:RenderingDevice
var _owned:Array[RID]=[]
var _frame_owned:Array[RID]=[]
var _dependency_kinds:Dictionary={}
var _volume_shader:=RID()
var _quad_shader:=RID()
var _sampler:=RID()
var _vertex_format:=-1
var _size:=Vector2i.ZERO
var _color:=RID()
var _stencil:=RID()
var _framebuffer:=RID()
var _increment:=RID()
var _decrement:=RID()
var _quad:=RID()
var last_error:=""
var draw_count:=0
var upload_count:=0
var _mesh_cache:Dictionary={}
const VERTEX_SOURCE="""#version 450
layout(location=0) in vec3 position;
layout(push_constant,std430) uniform Params { mat4 mvp; vec4 color; } params;
void main(){ gl_Position=params.mvp*vec4(position,1.0); }
"""
const FRAGMENT_SOURCE="""#version 450
layout(set=0,binding=0) uniform sampler2D scene_depth;
layout(location=0) out vec4 out_color;
void main(){
 float receiver=texelFetch(scene_depth,ivec2(gl_FragCoord.xy),0).r;
 if(gl_FragCoord.z < receiver) discard;
 out_color=vec4(0.0);
}
"""
const QUAD_VERTEX="""#version 450
vec2 points[6]=vec2[](vec2(-1,-1),vec2(1,-1),vec2(1,1),vec2(-1,-1),vec2(1,1),vec2(-1,1));
void main(){gl_Position=vec4(points[gl_VertexIndex],0.01,1.0);}
"""
const QUAD_FRAGMENT="""#version 450
layout(push_constant,std430) uniform Params { mat4 mvp; vec4 color; } params;
layout(location=0) out vec4 out_color;
void main(){out_color=params.color;}
"""

static func capability()->Dictionary:
	return {"backend":"rd_two_pass_stencil_sampled_reverse_z","twoFaceStencilAPI":ClassDB.class_exists("RDPipelineDepthStencilState"),"nativePixelEquivalent":false,"targetAdaptation":"private stencil attachment, sampled resolved reverse-Z scene depth, actual per-pass camera; transparent receivers only when they wrote depth","missingOriginalRuntime":"full source caster classification/skinning and original receiver schedule are not recovered"}

func initialize(device:RenderingDevice)->bool:
	rd=device
	if rd==null:last_error="RenderingDevice unavailable (headless or Compatibility)";return false
	_volume_shader=_compile(VERTEX_SOURCE,FRAGMENT_SOURCE)
	_quad_shader=_compile(QUAD_VERTEX,QUAD_FRAGMENT)
	if not _volume_shader.is_valid() or not _quad_shader.is_valid():return false
	_sampler=rd.sampler_create(RDSamplerState.new());_owned.append(_sampler)
	var attribute:=RDVertexAttribute.new()
	attribute.location=0;attribute.format=RenderingDevice.DATA_FORMAT_R32G32B32_SFLOAT;attribute.stride=12
	_vertex_format=rd.vertex_format_create([attribute])
	return true

func _compile(vertex:String,fragment:String)->RID:
	var source:=RDShaderSource.new();source.source_vertex=vertex;source.source_fragment=fragment
	var spirv:=rd.shader_compile_spirv_from_source(source)
	if not spirv.compile_error_vertex.is_empty() or not spirv.compile_error_fragment.is_empty():
		last_error=spirv.compile_error_vertex+spirv.compile_error_fragment;return RID()
	var shader:=rd.shader_create_from_spirv(spirv);_owned.append(shader);return shader

static func stencil_state(operation:int,quad:bool=false)->RDPipelineDepthStencilState:
	var state:=RDPipelineDepthStencilState.new()
	state.enable_stencil=true
	for face in ["front","back"]:
		state.set(face+"_op_fail",RenderingDevice.STENCIL_OP_KEEP)
		state.set(face+"_op_depth_fail",RenderingDevice.STENCIL_OP_KEEP)
		state.set(face+"_op_pass",operation)
		state.set(face+"_op_compare",RenderingDevice.COMPARE_OP_LESS_OR_EQUAL if quad else RenderingDevice.COMPARE_OP_ALWAYS)
		state.set(face+"_op_compare_mask",255)
		state.set(face+"_op_write_mask",0 if quad else 255)
		state.set(face+"_op_reference",1)
	return state

func _pipeline(shader:RID,operation:int,cull:int,quad:bool=false)->RID:
	var raster:=RDPipelineRasterizationState.new();raster.cull_mode=cull
	var blend:=RDPipelineColorBlendState.new();var attachment:=RDPipelineColorBlendStateAttachment.new()
	attachment.write_r=quad;attachment.write_g=quad;attachment.write_b=quad;attachment.write_a=false
	if quad:
		attachment.enable_blend=true
		attachment.src_color_blend_factor=RenderingDevice.BLEND_FACTOR_SRC_ALPHA
		attachment.dst_color_blend_factor=RenderingDevice.BLEND_FACTOR_ONE_MINUS_SRC_ALPHA
	blend.attachments=[attachment]
	var result:=rd.render_pipeline_create(shader,rd.framebuffer_get_format(_framebuffer),-1 if quad else _vertex_format,RenderingDevice.RENDER_PRIMITIVE_TRIANGLES,raster,RDPipelineMultisampleState.new(),stencil_state(operation,quad),blend)
	_frame_owned.append(result);_dependency_kinds[result]="pipeline";return result

func _device_owns(resource:RID)->bool:
	if not resource.is_valid():return false
	# A nonzero RID token survives dependency-driven deletion. In particular,
	# resizing the scene auto-frees our framebuffer when its color is freed.
	match _dependency_kinds.get(resource,""):
		"framebuffer":return rd.framebuffer_is_valid(resource)
		"pipeline":return rd.render_pipeline_is_valid(resource)
		"texture":return rd.texture_is_valid(resource)
		"uniform_set":return rd.uniform_set_is_valid(resource)
	# Shader/sampler and mesh buffer trees are entirely owner-local; reverse
	# teardown releases their arrays before their buffers and shaders last.
	return true

func _free_list(items:Array[RID])->void:
	if rd!=null:
		for i in range(items.size()-1,-1,-1):
			if _device_owns(items[i]):rd.free_rid(items[i])
			_dependency_kinds.erase(items[i])
	items.clear()

func _ensure_target(color:RID,size:Vector2i)->bool:
	if _color==color and _size==size and rd.framebuffer_is_valid(_framebuffer):return true
	_free_list(_frame_owned);_color=color;_size=size
	var format:=RDTextureFormat.new();format.width=size.x;format.height=size.y
	format.format=RenderingDevice.DATA_FORMAT_D24_UNORM_S8_UINT
	format.usage_bits=RenderingDevice.TEXTURE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT
	if not rd.texture_is_format_supported_for_usage(format.format,format.usage_bits):format.format=RenderingDevice.DATA_FORMAT_D32_SFLOAT_S8_UINT
	if not rd.texture_is_format_supported_for_usage(format.format,format.usage_bits):last_error="No supported depth-stencil attachment";return false
	_stencil=rd.texture_create(format,RDTextureView.new());_frame_owned.append(_stencil);_dependency_kinds[_stencil]="texture"
	_framebuffer=rd.framebuffer_create([color,_stencil]);_frame_owned.append(_framebuffer);_dependency_kinds[_framebuffer]="framebuffer"
	if not _framebuffer.is_valid():last_error="Scene color cannot be used as attachment";return false
	_increment=_pipeline(_volume_shader,RenderingDevice.STENCIL_OP_INCREMENT_AND_CLAMP,RenderingDevice.POLYGON_CULL_BACK)
	_decrement=_pipeline(_volume_shader,RenderingDevice.STENCIL_OP_DECREMENT_AND_CLAMP,RenderingDevice.POLYGON_CULL_FRONT)
	_quad=_pipeline(_quad_shader,RenderingDevice.STENCIL_OP_KEEP,RenderingDevice.POLYGON_CULL_DISABLED,true)
	return _increment.is_valid() and _decrement.is_valid() and _quad.is_valid()

func _push(matrix:Projection,color:Color)->PackedByteArray:
	var data:=PackedFloat32Array()
	for column in 4:
		for row in 4:data.append(matrix[column][row])
	data.append_array(PackedFloat32Array([color.r,color.g,color.b,color.a]))
	return data.to_byte_array()

func _mesh_record(volume:Dictionary,retained:Dictionary)->Dictionary:
	var data:Dictionary=volume.geometry
	var revisioned:=volume.has_all(["id","geometryRevision"])
	var key:String=str(volume.id)+":"+str(volume.geometryRevision) if revisioned else str(hash(data))
	# Unversioned callers (including independent GPU fixtures) get exact
	# geometry equality collision checks. Production uses owner revisions.
	while _mesh_cache.has(key) and not revisioned and _mesh_cache[key].geometry!=data:key+="_"
	retained[key]=true
	if _mesh_cache.has(key):return _mesh_cache[key]
	var positions:=PackedFloat32Array()
	for point in data.positions:positions.append_array(PackedFloat32Array(point))
	var vertex_buffer:=rd.vertex_buffer_create(positions.size()*4,positions.to_byte_array())
	var vertex_array:=rd.vertex_array_create(data.positions.size(),_vertex_format,[vertex_buffer])
	var indices:=PackedInt32Array(data.indices)
	var index_buffer:=rd.index_buffer_create(indices.size(),RenderingDevice.INDEX_BUFFER_FORMAT_UINT32,indices.to_byte_array())
	var index_array:=rd.index_array_create(index_buffer,0,indices.size())
	var owned:Array[RID]=[vertex_buffer,vertex_array,index_buffer,index_array]
	var record:Dictionary={"vertices":vertex_array,"indices":index_array,"owned":owned,"geometry":{} if revisioned else data.duplicate(true)}
	_mesh_cache[key]=record;upload_count+=1;return record

func _retire_meshes(retained:Dictionary)->void:
	for key in _mesh_cache.keys():
		if not retained.has(key):_free_list(_mesh_cache[key].owned);_mesh_cache.erase(key)

func clear_geometry()->void:
	# Called by compositor on render thread even when there are no draws.
	_retire_meshes({})

func cached_mesh_count()->int:
	return _mesh_cache.size()

func render(color:RID,depth:RID,size:Vector2i,view_projection:Projection,volumes:Array,shadow_color:Color=Color(0,0,0,0.5))->bool:
	if rd==null or not _volume_shader.is_valid() or size.x<=0 or size.y<=0:return false
	if not rd.texture_is_valid(color) or not rd.texture_is_valid(depth):last_error="Scene render target no longer owned by device";return false
	if not _ensure_target(color,size):return false
	var uniform:=RDUniform.new();uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE;uniform.binding=0
	uniform.add_id(_sampler);uniform.add_id(depth)
	var set:=rd.uniform_set_create([uniform],_volume_shader,0)
	_dependency_kinds[set]="uniform_set"
	var transient:Array[RID]=[set];var prepared:Array=[];var retained:Dictionary={}
	for volume:Dictionary in volumes:
		var data:Dictionary=volume.geometry
		if data.indices.is_empty():continue
		var record:=_mesh_record(volume,retained)
		prepared.append({"vertices":record.vertices,"indices":record.indices,"push":_push(view_projection*Projection(volume.get("transform",Transform3D.IDENTITY)),shadow_color)})
	var list:=rd.draw_list_begin(_framebuffer,RenderingDevice.DRAW_CLEAR_DEPTH|RenderingDevice.DRAW_CLEAR_STENCIL,PackedColorArray(),0.0,0)
	# 0x511FE0 emits both faces for each caster before advancing manager list.
	# Clamped decrement means grouping all front faces changes source order.
	for item:Dictionary in prepared:
		for pipeline:RID in [_increment,_decrement]:
			rd.draw_list_bind_render_pipeline(list,pipeline);rd.draw_list_bind_uniform_set(list,set,0)
			rd.draw_list_bind_vertex_array(list,item.vertices);rd.draw_list_bind_index_array(list,item.indices)
			rd.draw_list_set_push_constant(list,item.push,item.push.size());rd.draw_list_draw(list,true,1);draw_count+=1
	rd.draw_list_bind_render_pipeline(list,_quad)
	var push:=_push(Projection.IDENTITY,shadow_color);rd.draw_list_set_push_constant(list,push,push.size())
	rd.draw_list_draw(list,false,1,6);draw_count+=1
	rd.draw_list_end()
	_free_list(transient)
	_retire_meshes(retained)
	return true

func dispose()->void:
	_retire_meshes({})
	_free_list(_frame_owned);_free_list(_owned);rd=null
	_dependency_kinds.clear()
	_volume_shader=RID();_quad_shader=RID();_framebuffer=RID();_color=RID();_size=Vector2i.ZERO
