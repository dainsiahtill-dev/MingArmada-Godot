extends RefCounted
## Reversible display-only ablation. Never owns the scene or its time.
const MODES=["baseline","native_off","stencil_off","rig_cast_off","sail_cast_off","deck_visible","hull_visible","deck_down4mm","hull_down35mm"]
var _sun:DirectionalLight3D
var _effect:CompositorEffect
var _native_enabled:=true
var _effect_enabled:=true
var _meshes:Array[Dictionary]=[]
var _mode:="baseline"

func configure(actor:Node3D,sun:DirectionalLight3D,effect:CompositorEffect=null)->Dictionary:
	if not is_instance_valid(actor) or not is_instance_valid(sun):return {"ok":false,"reason":"invalid-scene"}
	dispose();_sun=sun;_effect=effect;_native_enabled=sun.shadow_enabled
	if _effect!=null:_effect_enabled=_effect.enabled
	for mesh:MeshInstance3D in actor.find_children("*","MeshInstance3D",true,false):
		var materials:Array=[]
		if mesh.mesh!=null:
			for surface in mesh.mesh.get_surface_count():materials.append(mesh.get_active_material(surface))
		_meshes.append({"node":mesh,"path":str(actor.get_path_to(mesh)),"cast":mesh.cast_shadow,"mesh":mesh.mesh,"materials":materials,"transform":mesh.transform,"visible":mesh.visible,"proxyPresent":mesh.has_meta("target_shadow_geometry"),"proxy":mesh.get_meta("target_shadow_geometry") if mesh.has_meta("target_shadow_geometry") else null,"derived":{}})
	return {"ok":true}

func _restore()->void:
	if is_instance_valid(_sun):_sun.shadow_enabled=_native_enabled
	if _effect!=null:_effect.enabled=_effect_enabled
	for entry:Dictionary in _meshes:
		if is_instance_valid(entry.node):
			entry.node.cast_shadow=entry.cast
			if entry.proxyPresent:entry.node.set_meta("target_shadow_geometry",entry.proxy)
			elif entry.node.has_meta("target_shadow_geometry"):entry.node.remove_meta("target_shadow_geometry")

func _translated_proxy(entry:Dictionary,mode:String)->Mesh:
	if entry.derived.has(mode):return entry.derived[mode]
	var result:=ArrayMesh.new();var offset:=-.004 if mode=="deck_down4mm" else -.035
	for surface in entry.proxy.get_surface_count():
		var arrays:Array=entry.proxy.surface_get_arrays(surface)
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		for index in vertices.size():vertices[index].y+=offset
		arrays[Mesh.ARRAY_VERTEX]=vertices
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		result.surface_set_material(surface,entry.proxy.surface_get_material(surface))
	entry.derived[mode]=result
	return result

func apply(mode:String)->Dictionary:
	if not is_instance_valid(_sun) or mode not in MODES:return {"ok":false,"reason":"invalid-factor-or-scene"}
	if mode=="stencil_off" and _effect==null:return {"ok":false,"reason":"no-template-compositor"}
	var proxy_mode:bool=mode.begins_with("deck_") or mode.begins_with("hull_")
	var target:="deck" if mode.begins_with("deck_") else "hull"
	if proxy_mode:
		var found:=false
		for entry:Dictionary in _meshes:
			if str(entry.node.name)==target and entry.proxy is Mesh:found=true
		if not found:return {"ok":false,"reason":"no-authored-proxy"}
	_restore();_mode=mode
	if mode=="native_off":_sun.shadow_enabled=false
	elif mode=="stencil_off":_effect.enabled=false
	elif mode in ["rig_cast_off","sail_cast_off"]:
		var prefix:="rigging_" if mode=="rig_cast_off" else "sail_"
		for entry:Dictionary in _meshes:
			if is_instance_valid(entry.node) and str(entry.node.name).begins_with(prefix):entry.node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif proxy_mode:
		for entry:Dictionary in _meshes:
			if str(entry.node.name)==target and entry.proxy is Mesh:
				entry.node.set_meta("target_shadow_geometry",entry.mesh if mode.ends_with("visible") else _translated_proxy(entry,mode))
	return {"ok":true,"inspection":inspection()}

func inspection()->Dictionary:
	var meshes:Array=[];var geometry_unchanged:=true
	for entry:Dictionary in _meshes:
		if not is_instance_valid(entry.node):geometry_unchanged=false;continue
		var node:MeshInstance3D=entry.node;var materials:Array=[]
		if node.mesh!=null:
			for surface in node.mesh.get_surface_count():materials.append(node.get_active_material(surface))
		geometry_unchanged=geometry_unchanged and node.mesh==entry.mesh and materials==entry.materials and node.transform==entry.transform and node.visible==entry.visible
		var proxy:Mesh=node.get_meta("target_shadow_geometry") if node.has_meta("target_shadow_geometry") else null
		meshes.append({"path":entry.path,"name":str(node.name),"cast":node.cast_shadow,"baselineCast":entry.cast,"globalTransform":node.global_transform,"proxyChanged":proxy!=entry.proxy,"proxyMeshId":proxy.get_instance_id() if proxy!=null else 0,"visibleMeshId":node.mesh.get_instance_id() if node.mesh!=null else 0,"baselineProxyId":entry.proxy.get_instance_id() if entry.proxy is Mesh else 0})
	return {"mode":_mode,"nativeEnabled":_sun.shadow_enabled if is_instance_valid(_sun) else null,"effectPresent":_effect!=null,"effectEnabled":_effect.enabled if _effect!=null else null,"meshCount":_meshes.size(),"geometryMaterialsPoseVisibilityUnchanged":geometry_unchanged,"meshes":meshes}

func dispose()->void:
	_restore();_sun=null;_effect=null;_meshes.clear();_mode="baseline"
