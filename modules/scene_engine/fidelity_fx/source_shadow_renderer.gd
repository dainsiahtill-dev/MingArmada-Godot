extends RefCounted
const Math=preload("res://modules/scene_engine/fidelity_fx/source_shadow_math.gd")
const Backend=preload("res://modules/scene_engine/fidelity_fx/source_shadow_rd.gd")
const Effect=preload("res://modules/scene_engine/fidelity_fx/source_shadow_compositor.gd")
const PLANE_ASSET="res://modules/scene_engine/fidelity_fx/source_shadow_assets/fluyt.nif.json"
var _parent:Node3D
var _camera:Camera3D
var _effect:CompositorEffect
var _original_compositor:Compositor
var _owned_compositor:Compositor
var _volumes:Dictionary={}
var _planes:Dictionary={}
var _imperative_planes:Dictionary={}
var _snapshot_planes:Dictionary={}
var _rebuild_count:=0
var _errors:Array=[]
var _epoch:Variant=null
var _options:Dictionary={}

func configure(parent:Node3D,camera:Camera3D,options:Dictionary={})->Dictionary:
	dispose();_parent=parent;_camera=camera;_options=options.duplicate(true)
	_rebuild_count=0;_errors=[]
	if is_instance_valid(camera) and DisplayServer.get_name()!="headless" and str(RenderingServer.get_current_rendering_method())!="gl_compatibility":
		_effect=Effect.new();_original_compositor=camera.compositor
		_owned_compositor=Compositor.new()
		var effects:Array[CompositorEffect]=[]
		if _original_compositor!=null:effects.assign(_original_compositor.compositor_effects)
		effects.append(_effect);_owned_compositor.compositor_effects=effects;camera.compositor=_owned_compositor
	var result:=Backend.capability();result.activeCompositor=_effect!=null
	return result

func apply_snapshot(native:Dictionary,actor_nodes:Dictionary={},environment:Dictionary={})->void:
	if not is_instance_valid(_parent):return
	var epoch:Variant=environment.get("epoch",native.get("environment",{}).get("epoch",null))
	var epoch_changed:bool=epoch!=_epoch
	if epoch_changed:_volumes.clear();_epoch=epoch
	var state:Dictionary=native.get("sourceShadows",{})
	var retained:Dictionary={};_errors=[]
	for caster:Dictionary in state.get("casters",[]):
		var id:=str(caster.get("id",""));var actor:Node3D=actor_nodes.get(str(caster.get("actorId",id))) as Node3D
		if id.is_empty() or not is_instance_valid(actor):continue
		if not Math.registration_allowed(bool(caster.get("displayShadows",state.get("displayShadows",true))),int(caster.get("featureBits",0x20)),true,bool(caster.get("actor144",false))):continue
		if not caster.has_all(["positions","localLight","edges","capIndices","worldRotation"]):_errors.append("%s missing explicit source caster fields" % id);continue
		var previous:Dictionary=_volumes.get(id,{})
		var rebuild:bool=bool(caster.get("dirty",false)) or previous.get("light",[])!=caster.localLight or Math.should_rebuild(bool(caster.get("skinned",false)),not previous.is_empty(),caster.worldRotation,previous.get("rotation",[]))
		var geometry:Dictionary=previous.get("geometry",{})
		if rebuild:
			geometry=Math.build_volume_component(caster.positions,caster.localLight,caster.edges,caster.capIndices)
			if geometry.has("error"):_errors.append("%s: %s" % [id,geometry.error]);continue
			_rebuild_count+=1
		var transform:Transform3D=caster.get("worldTransform",actor.global_transform)
		# Caller provides source-to-target basis and units in this transform.
		retained[id]={"id":id,"geometryRevision":_rebuild_count if rebuild else previous.geometryRevision,"geometry":geometry,"rotation":caster.worldRotation.duplicate() if rebuild else previous.rotation,"light":caster.localLight.duplicate(),"transform":transform}
	_volumes=retained
	_reconcile_snapshot_planes(state.get("texturePlanes",{}),actor_nodes,epoch_changed)
	if _effect!=null:_effect.submit(_volumes.values(),state.get("color",_options.get("color",Color(0,0,0,0.5))))

func diagnostics()->Dictionary:
	_prune_dead_planes()
	var result:=Backend.capability()
	result.volumeCount=_volumes.size();result.rebuildCount=_rebuild_count;result.texturePlaneCount=_planes.size();result.errors=_errors.duplicate()
	result.gpu=_effect.status() if _effect!=null else {"initialized":false,"frames":0,"draws":0,"error":"No active rendering compositor"}
	return result

func _trs(fields:Dictionary)->Transform3D:
	var r:Dictionary=fields.rotation;var t:Dictionary=fields.translation
	return Transform3D(Basis(Vector3(r.m_11,r.m_21,r.m_31),Vector3(r.m_12,r.m_22,r.m_32),Vector3(r.m_13,r.m_23,r.m_33))*float(fields.scale),Vector3(t.x,t.y,t.z))

func attach_ship_texture_plane(source_model_root:Node3D,resource:String)->Node3D:
	# Imperative opt-ins survive snapshot removal and epoch changes until the
	# actor is freed or this renderer is disposed. Adopt a shared node if any.
	var plane:=_attach_plane(source_model_root,resource)
	if plane!=null:_imperative_planes[source_model_root.get_instance_id()]=true
	return plane

func _prune_dead_planes()->void:
	for key in _planes.keys():
		if not is_instance_valid(_planes[key]):
			_planes.erase(key);_snapshot_planes.erase(key);_imperative_planes.erase(key)

func _reconcile_snapshot_planes(requests:Dictionary,actor_nodes:Dictionary,epoch_changed:bool)->void:
	_prune_dead_planes()
	var desired:Dictionary={}
	for actor_id in requests:
		var actor:Node3D=actor_nodes.get(str(actor_id)) as Node3D
		# Unsupported resource requests remove a previous snapshot-owned plane;
		# they never inherit the old resource simply because actor ID is stable.
		if is_instance_valid(actor) and str(requests[actor_id]).to_lower()=="fluyt":desired[actor.get_instance_id()]=actor
	for key in _snapshot_planes.keys():
		if epoch_changed or not desired.has(key):
			_snapshot_planes.erase(key)
			if not _imperative_planes.has(key):
				if is_instance_valid(_planes.get(key)):_planes[key].free()
				_planes.erase(key)
	for key in desired:
		if _attach_plane(desired[key],"fluyt")!=null:_snapshot_planes[key]=true

func _attach_plane(source_model_root:Node3D,resource:String)->Node3D:
	if resource.to_lower()!="fluyt" or not is_instance_valid(source_model_root):return null
	var key:=source_model_root.get_instance_id()
	if _planes.has(key) and is_instance_valid(_planes[key]):return _planes[key]
	var asset:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(PLANE_ASSET));var blocks:Dictionary={}
	for block:Dictionary in asset.selected_blocks:blocks[int(block.id)]=block
	var holder:=Node3D.new();holder.name="SourceFluytTextureShadow";source_model_root.add_child(holder)
	var parent:Node3D=holder
	for id in [0,5,7]:
		var node:=Node3D.new();node.name=blocks[id].name;node.transform=_trs(blocks[id].fields);parent.add_child(node);parent=node
	var mesh:=ArrayMesh.new();var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	var vertices:=PackedVector3Array();var normals:=PackedVector3Array();var uv:=PackedVector2Array();var indices:=PackedInt32Array()
	for p:Dictionary in blocks[213].fields.vertices:vertices.append(Vector3(p.x,p.y,p.z))
	for p:Dictionary in blocks[213].fields.normals:normals.append(Vector3(p.x,p.y,p.z))
	for p:Dictionary in blocks[213].fields.uv_sets[0]:uv.append(Vector2(p.u,p.v))
	for triangle in blocks[213].effective_triangles:indices.append_array(PackedInt32Array(triangle))
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_INDEX]=indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material:=ShaderMaterial.new();material.shader=load("res://modules/scene_engine/fidelity_fx/source_shadow_plane.gdshader")
	# Raw source bytes keep a .bin suffix: export includes *.bin, whereas an
	# imported .dds source file is remapped/omitted from the exported package.
	var dds:=FileAccess.get_file_as_bytes("res://modules/scene_engine/fidelity_fx/source_shadow_assets/ship_shadow.dds.bin")
	var fourcc:=dds.slice(84,88).get_string_from_ascii()
	var format:int={"DXT1":Image.FORMAT_DXT1,"DXT3":Image.FORMAT_DXT3,"DXT5":Image.FORMAT_DXT5}.get(fourcc,Image.FORMAT_MAX)
	if format==Image.FORMAT_MAX:holder.free();_errors.append("Unsupported source DDS format");return null
	var image:=Image.create_from_data(dds.decode_u32(16),dds.decode_u32(12),dds.decode_u32(28)>1,format,dds.slice(128))
	material.set_shader_parameter("source_texture",ImageTexture.create_from_image(image))
	var instance:=MeshInstance3D.new();instance.name="ship_shadow_plane";instance.mesh=mesh;instance.material_override=material;instance.transform=_trs(blocks[208].fields)
	instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.set_meta("sourceGeometryFlags",27);instance.set_meta("sourceUserPropBuffer","L:1")
	instance.set_meta("runtimeVisibilityUnknown",true);parent.add_child(instance)
	_planes[key]=holder;return holder

func dispose()->void:
	if _effect!=null:_effect.dispose()
	if is_instance_valid(_camera) and _camera.compositor==_owned_compositor:_camera.compositor=_original_compositor
	_effect=null;_owned_compositor=null;_original_compositor=null;_camera=null;_parent=null
	for node in _planes.values():
		if is_instance_valid(node):node.free()
	_planes.clear();_snapshot_planes.clear();_imperative_planes.clear();_volumes.clear();_epoch=null
