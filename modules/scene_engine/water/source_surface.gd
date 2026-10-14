extends RefCounted
## Shared original DDS/mip and bounded dynamic surface adapter for water effects.
const Mix=preload("res://modules/scene_engine/fidelity_fx/particle.gdshader")
const Add=preload("res://modules/scene_engine/fidelity_fx/particle_add.gdshader")
const SceneWake=preload("res://modules/scene_engine/water/source_scene_wake.gdshader")
const AttachedFroth=preload("res://modules/scene_engine/water/source_attached_froth.gdshader")
const Upload=preload("res://modules/scene_engine/fidelity_fx/presentation.gd")
static var _textures:Dictionary={}
var nodes:Dictionary={}
var layouts:Dictionary={}
var _materials:Dictionary={}
var region_uploads:=0
var rebuilds:=0
var parent:Node3D

static func native_to_world(p:Array,units:float,origin:Vector3=Vector3.ZERO)->Vector3:return origin+Vector3(p[0],p[2],-p[1])*units
static func texture(name:String)->Texture2D:
	name=name.to_lower()
	if _textures.has(name):return _textures[name]
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/source_wake/texture-manifest.json"))
	for entry:Dictionary in manifest.textures:
		if entry.name!=name:continue
		var formats:Dictionary={"DXT1":Image.FORMAT_DXT1,"DXT3":Image.FORMAT_DXT3,"DXT5":Image.FORMAT_DXT5}
		var image:=Image.create_from_data(int(entry.width),int(entry.height),bool(entry.mipmaps),formats[entry.format],FileAccess.get_file_as_bytes(entry.payload))
		if image==null or image.is_empty():return null
		var resource:=ImageTexture.create_from_image(image);_textures[name]=resource;return resource
	return null

func _init(owner:Node3D)->void:parent=owner
func material(record:Dictionary)->ShaderMaterial:
	var scene_trail:=bool(record.get("scene_trail",false))
	var target_role:=str(record.get("target_froth_role",""))
	var key:=str(record.texture)+":"+str(record.get("alphaFlags",4333))+":"+str(record.get("clampMode",3))+":"+str(scene_trail)+":"+target_role
	if _materials.has(key):
		if scene_trail:_scene_trail_parameters(_materials[key],record)
		if not target_role.is_empty():_froth_intensity(_materials[key],record)
		return _materials[key]
	var original:=texture(record.texture)
	if original==null:return null
	var flags:=int(record.get("alphaFlags",4333));var destination:=(flags>>5)&15
	var out:=ShaderMaterial.new();out.shader=AttachedFroth if target_role in ["side","bow"] else (SceneWake if scene_trail else (Add if flags&1 and destination==0 else Mix));out.render_priority=3
	out.set_shader_parameter("source_texture",original);out.set_shader_parameter("source_texture_repeat",original)
	var clamp_mode:=int(record.get("clampMode",3))
	out.set_shader_parameter("source_repeat",clamp_mode==3);out.set_shader_parameter("source_clamp_mode",clamp_mode)
	out.set_shader_parameter("source_mip_count",original.get_image().get_mipmap_count()+1)
	out.set_shader_parameter("alpha_threshold",float(record.get("threshold",0))/255.0 if flags&512 else -1.0)
	if scene_trail:
		# Surface overlay bypasses the transparent sea's different tessellation,
		# while opaque hulls and terrain retain a small contact-depth fade.
		out.set_shader_parameter("soft_depth_distance",0.08)
		_scene_trail_parameters(out,record)
	if not target_role.is_empty():_froth_intensity(out,record)
	_materials[key]=out;return out

static func _froth_intensity(out:ShaderMaterial,record:Dictionary)->void:
	var strength:=float(record.get("target_froth_intensity",1.0))
	out.set_shader_parameter("display_tint",Color(1,1,1,clampf(strength,0.0,1.0) if is_finite(strength) else 1.0))
	if str(record.get("target_froth_role","")) in ["side","bow"]:
		out.set_shader_parameter("soft_depth_distance",0.08)
		out.set_shader_parameter("hull_world_to_local",record.get("target_froth_world_to_hull",Transform3D.IDENTITY))
		out.set_shader_parameter("froth_visual_time",float(record.get("target_froth_time",0.0)))

static func scene_strip_descriptor(geometry:Dictionary)->Dictionary:
	var out:={"texture":"wake3unique.dds","alphaFlags":4333,"clampMode":3,"scene_trail":true,"tail_v":0.0,"tail_span_v":0.0}
	var uv:PackedVector2Array=geometry.get("uvs",PackedVector2Array())
	var count:=mini(uv.size(),int(geometry.get("draw_vertex_count",58)))
	var colors:PackedColorArray=geometry.get("colors",PackedColorArray())
	var tail:=count-1
	# Source draw count includes collapsed inactive rows, whose UVs deliberately
	# retain old values. Their alpha is zero: locate the actual visible prefix.
	if colors.size()>=count:
		while tail>=1 and colors[tail].a<=0.0 and colors[tail-1].a<=0.0:tail-=2
	if tail>=3:
		out.tail_v=uv[tail].y
		out.tail_span_v=uv[maxi(1,tail-6)].y-uv[tail].y
	return out

static func _scene_trail_parameters(out:ShaderMaterial,record:Dictionary)->void:
	var terminal:=float(record.get("tail_v",0.0));var span:=float(record.get("tail_span_v",0.0))
	out.set_shader_parameter("tail_v",terminal if is_finite(terminal) else 0.0)
	out.set_shader_parameter("tail_span_v",span if is_finite(span) else 0.0)

func submit(key:String,vertices:PackedVector3Array,uvs:PackedVector2Array,colors:PackedColorArray,indices:PackedInt32Array,record:Dictionary)->void:
	if not nodes.has(key):
		var node:=MeshInstance3D.new();node.name=key;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;parent.add_child(node);nodes[key]=node
	var node:MeshInstance3D=nodes[key]
	node.visible=not indices.is_empty()
	if indices.is_empty():return
	var mesh:ArrayMesh=node.mesh;var layout:Dictionary=layouts.get(key,{})
	var reuse:bool=DisplayServer.get_name()!="headless" and mesh!=null and layout.get("supported",false) and layout.get("count",0)==vertices.size() and layout.get("indices",PackedInt32Array())==indices
	if reuse:
		mesh.surface_update_vertex_region(0,0,vertices.to_byte_array());mesh.surface_update_attribute_region(0,0,Upload._surface_attributes(uvs,colors));mesh.custom_aabb=Upload._local_bounds(vertices);region_uploads+=1
	else:
		var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_TEX_UV]=uvs;arrays[Mesh.ARRAY_COLOR]=colors;arrays[Mesh.ARRAY_INDEX]=indices
		mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE);node.mesh=mesh
		var count:=vertices.size();var format:=mesh.surface_get_format(0)
		var supported:=RenderingServer.mesh_surface_get_format_vertex_stride(format,count)==12 and RenderingServer.mesh_surface_get_format_attribute_stride(format,count)==12 and RenderingServer.mesh_surface_get_format_offset(format,count,Mesh.ARRAY_TEX_UV)==4 and not format&Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES
		layouts[key]={"count":count,"indices":indices.duplicate(),"supported":supported};rebuilds+=1
	node.material_override=material(record)

func hide_unused(used:Dictionary)->void:
	for key:String in nodes:
		if not used.has(key):nodes[key].visible=false
func dispose()->void:
	for node:Node in nodes.values():node.free()
	nodes.clear();layouts.clear();_materials.clear()
