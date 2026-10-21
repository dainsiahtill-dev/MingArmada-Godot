extends RefCounted
## Target rigid hull/mast policy. Original classifier and actor+108 light
## producer remain unknown. Exact-position welding removes authored UV seams.
const Math=preload("res://modules/scene_engine/fidelity_fx/source_shadow_math.gd")
const Prepared=preload("res://modules/scene_engine/fidelity_fx/prepared_rigid_shadow.gd")
const Boundary=preload("res://game/presentation/world/target_shadow_boundary.gd")
var _geometry:Dictionary={}
var _parts:Dictionary={}
var _shadow_modes:Dictionary={}
var _errors:Array=[]
static func _toggle_indexed_edge(edges:Array,lookup:Dictionary,a:int,b:int)->void:
	Prepared.toggle_edge(edges,lookup,a,b)
func _mesh_geometry(mesh:Mesh)->Dictionary:
	var id:=mesh.get_instance_id()
	if _geometry.has(id):return _geometry[id]
	var positions:Array=[];var points:Array[Vector3]=[];var faces:Array=[];var welded:Dictionary={}
	for surface in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(surface)!=Mesh.PRIMITIVE_TRIANGLES:continue
		var arrays:=mesh.surface_get_arrays(surface)
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		var remap:Array=[]
		for p:Vector3 in vertices:
			if not p.is_finite():return {"error":"nonfinite rigid geometry"}
			if not welded.has(p):welded[p]=points.size();points.append(p);positions.append([p.x,p.y,p.z])
			remap.append(welded[p])
		if points.size()>=32768:return {"error":"rigid geometry exceeds signed edge index scope"}
		var count:=indices.size() if not indices.is_empty() else vertices.size()
		for offset in range(0,count-2,3):
			var a:int=remap[indices[offset] if not indices.is_empty() else offset]
			var b:int=remap[indices[offset+2] if not indices.is_empty() else offset+2]
			var c:int=remap[indices[offset+1] if not indices.is_empty() else offset+1]
			var normal:Vector3=(points[b]-points[a]).cross(points[c]-points[a])
			if normal.length_squared()<=1.0e-16:continue
			faces.append({"indices":[a,b,c],"normal":normal})
	var result:={"positions":positions,"faces":faces,"revision":id}
	_geometry[id]=result
	return result

func compose(native:Dictionary,ships:Dictionary,world_light:Vector3,stencil_active:bool,display_shadows:bool=true)->Dictionary:
	var casters:Array=[];var actors:Dictionary={};var live:Dictionary={};_errors=[]
	var state:Dictionary=native.get("sourceShadows",{}).duplicate(true)
	var effective_display:=display_shadows and bool(state.get("displayShadows",true))
	for ship_id:String in ships:
		var model:Node3D=ships[ship_id].get_model()
		if not is_instance_valid(model):continue
		# Explicit source caster/texture-plane actor IDs bind to the actual model
		# root, including its damage/LOD transform, not the outer gameplay actor.
		actors[ship_id]=model
		for node:Node in model.find_children("*","MeshInstance3D",true,false):
			var mesh:=node as MeshInstance3D
			if not mesh.get_meta("target_rigid_shadow_caster",false) or not mesh.is_visible_in_tree() or mesh.mesh==null:continue
			var id:="%s:%s"%[ship_id,mesh.name]
			var geometry:=_mesh_geometry(mesh.mesh)
			if geometry.has("error"):_errors.append(id+": "+geometry.error);continue
			var frame:=mesh.global_transform
			var direction:Vector3=(frame.basis.inverse()*world_light).normalized()
			if not direction.is_finite() or direction.is_zero_approx():continue
			var local_light:Array=[direction.x,direction.y,direction.z]
			var previous:Dictionary=_parts.get(id,{})
			var dirty:bool=previous.get("revision",-1)!=geometry.revision or previous.get("light",[])!=local_light
			if dirty:
				var prepared:RefCounted=previous.get("prepared")
				if prepared==null or previous.get("revision",-1)!=geometry.revision:
					prepared=Boundary.new()
					var configured:Dictionary=prepared.configure(geometry.positions,geometry.faces)
					if not configured.ok:_errors.append(id+": "+configured.reason);continue
				var topology:Dictionary=prepared.select_topology(local_light)
				if topology.has("error"):_errors.append(id+": "+topology.error);continue
				previous={"revision":geometry.revision,"light":local_light,"edges":topology.edges,"caps":topology.caps,"prepared":prepared}
				_parts[id]=previous
			var rotation:=frame.basis.orthonormalized()
			casters.append({"id":id,"actorId":id,"positions":previous.prepared.source_positions(),"localLight":local_light,"edges":previous.edges,"capIndices":previous.caps,"worldTransform":frame,"worldRotation":[rotation.x.x,rotation.y.x,rotation.z.x,rotation.x.y,rotation.y.y,rotation.z.y,rotation.x.z,rotation.y.z,rotation.z.z],"geometryRevision":geometry.revision,"dirty":dirty,"displayShadows":effective_display,"preparedRigid":previous.prepared,"policy":"target rigid hull/mast triangles; exact seam weld; target inverse-basis light"})
			actors[id]=mesh;live[id]=true
			if not _shadow_modes.has(mesh.get_instance_id()):_shadow_modes[mesh.get_instance_id()]={"node":weakref(mesh),"mode":mesh.cast_shadow}
			mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if stencil_active and effective_display else _shadow_modes[mesh.get_instance_id()].mode
	for id:String in _parts.keys():
		if not live.has(id):_parts.erase(id)
	for key:int in _shadow_modes.keys():
		var mesh:MeshInstance3D=_shadow_modes[key].node.get_ref()
		if not is_instance_valid(mesh):_shadow_modes.erase(key)
		elif not actors.values().has(mesh):mesh.cast_shadow=_shadow_modes[key].mode
	var result:=native.duplicate(false)
	for caster:Dictionary in state.get("casters",[]):
		caster.displayShadows=effective_display and bool(caster.get("displayShadows",true))
		casters.append(caster)
	state.casters=casters;state.displayShadows=effective_display
	if not effective_display:state.texturePlanes={}
	result.sourceShadows=state
	return {"native":result,"actors":actors}
func diagnostics()->Dictionary:
	var topology_builds:=0;var classifications:=0;var boundary_builds:=0;var added_sides:=0
	var errors:=_errors.duplicate()
	for id:String in _parts:
		var part:Dictionary=_parts[id]
		var counters:Dictionary=part.prepared.diagnostics();topology_builds+=counters.topologyBuilds;classifications+=counters.classifications
		boundary_builds+=int(counters.get("boundaryBuilds",0));added_sides+=int(counters.get("addedSides",0))
		if not str(counters.get("boundaryError","")).is_empty():errors.append(id+": "+str(counters.boundaryError))
	return {"policy":"target_rigid_hull_mast","geometryCache":_geometry.size(),"activeCasters":_parts.size(),"errors":errors,"topologyBuilds":topology_builds,"classifications":classifications,"boundaryBuilds":boundary_builds,"addedSides":added_sides}
func dispose()->void:
	for saved:Dictionary in _shadow_modes.values():
		var mesh:MeshInstance3D=saved.node.get_ref()
		if is_instance_valid(mesh):mesh.cast_shadow=saved.mode
	_shadow_modes.clear();_geometry.clear();_parts.clear();_errors.clear()
