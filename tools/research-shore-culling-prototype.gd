extends RefCounted
## Research-only source-derived adapter. Never loaded by game/modules/tests.
const SOURCE="res://modules/scene_engine/terrain/natural_shore_surf.gd"
const BODY='''
var research_enabled:=false
var research_accepted_time:=0.0
var research_submitted_time:=0.0
var research_samples:=0
var research_writes:=0
var research_skipped_frames:=0
var research_diagnostic_evaluations:=0
var research_visible:=true
var research_reason:="not-enabled"
var research_views:Array=[]
var research_view_hits:Array=[]
var research_views_complete:=false
var research_ocean:ShaderMaterial
var research_geometry:=AABB()
var research_transform:=Transform3D.IDENTITY
var research_has_geometry:=false
var research_submit:=true
var research_staged:Dictionary={}
var research_bound:=AABB()

func research_enable(ocean:ShaderMaterial)->void:
	research_ocean=ocean;research_accepted_time=_time;research_submitted_time=_time
	research_enabled=true;research_capture_geometry()

func research_capture_geometry()->void:
	research_has_geometry=false;research_transform=global_transform
	for child:Node in get_children():
		if not child is MeshInstance3D or child.mesh==null:continue
		var bounds:AABB=child.mesh.get_aabb()
		for index in 8:
			var point:Vector3=child.global_transform*bounds.get_endpoint(index)
			if not research_has_geometry:research_geometry=AABB(point,Vector3.ZERO);research_has_geometry=true
			else:research_geometry=research_geometry.expand(point)

func research_set_views(main:Camera3D,reflection:Camera3D=null,reflection_enabled:bool=false,complete:bool=true)->void:
	research_views.clear();research_views_complete=complete
	if not is_instance_valid(main) or not main.is_inside_tree():research_views_complete=false;research_reason="missing-main-camera";return
	research_views.append(main.get_frustum())
	if reflection_enabled:
		if not is_instance_valid(reflection) or not reflection.is_inside_tree():research_views_complete=false;research_reason="missing-reflection-camera";return
		research_views.append(reflection.get_frustum())

func research_test_bounds()->bool:
	research_view_hits.clear()
	if global_transform!=research_transform:research_capture_geometry()
	if not research_has_geometry or research_ocean==null:research_reason="unknown-geometry-or-surface";research_visible=true;return true
	var waves:Variant=research_ocean.get_shader_parameter("wave_components")
	var count:Variant=research_ocean.get_shader_parameter("wave_count")
	var tide:Variant=research_ocean.get_shader_parameter("u_tide")
	var surface_time:Variant=research_ocean.get_shader_parameter("simulation_time")
	if not waves is PackedVector4Array or not (count is int or count is float) or not is_finite(float(count)) or float(count)!=int(count) or int(count)<0 or int(count)>8 or waves.size()<int(count) or not (tide is int or tide is float) or not is_finite(float(tide)) or not (surface_time is int or surface_time is float) or not is_finite(float(surface_time)):
		research_reason="unknown-wave-displacement";research_visible=true;return true
	var amplitude:=0.0
	for component:Vector4 in waves:
		if not component.is_finite():research_reason="invalid-wave-displacement";research_visible=true;return true
	for index in int(count):amplitude+=absf(waves[index].x)
	_surface_wave_count=int(count)
	# One metre is an explicitly conservative research guard, not a quality cut.
	var low:=float(tide)+0.055-amplitude-1.0;var high:=float(tide)+0.055+amplitude+1.0
	research_bound=AABB(Vector3(research_geometry.position.x,low,research_geometry.position.z),Vector3(research_geometry.size.x,high-low,research_geometry.size.z))
	if not research_views_complete or research_views.is_empty():research_visible=true;return true
	research_visible=false
	for planes:Array in research_views:
		var outside:=false
		for plane:Plane in planes:
			var all_outside:=true
			for corner in 8:
				if plane.distance_to(research_bound.get_endpoint(corner))<=0.01:all_outside=false;break
			if all_outside:outside=true;break
		research_view_hits.append(not outside)
		research_visible=research_visible or not outside
	research_reason="visible-union" if research_visible else "outside-complete-union"
	return research_visible

func _research_sample_into(index:int,time:float,state:Dictionary)->void:
	research_samples+=1;_sampler.sample_into(index,time,state)

func _research_set(material:ShaderMaterial,key:String,value:Variant)->void:
	if research_submit:research_writes+=1;material.set_shader_parameter(key,value)
	else:
		var identity:=material.get_instance_id()
		if not research_staged.has(identity):research_staged[identity]={}
		research_staged[identity][key]=value

func sync_surface_state(ocean:ShaderMaterial,state:Dictionary={})->bool:
	if not research_enabled:return _source_sync_surface_state(ocean,state)
	research_ocean=ocean
	if not research_test_bounds():return true
	return _source_sync_surface_state(ocean,state)

func apply_snapshot(snapshot:Dictionary,consumed:float=0.0)->void:
	if not research_enabled:_source_apply_snapshot(snapshot,consumed);return
	var value:Variant=snapshot.get("time")
	if not _configured or not (value is float or value is int) or not is_finite(float(value)):return
	research_accepted_time=float(value)
	if not research_test_bounds():research_skipped_frames+=1;return
	if research_ocean!=null:_source_sync_surface_state(research_ocean)
	if _has_applied_time and _time==research_accepted_time and research_submitted_time!=research_accepted_time:
		var complete:=research_staged.size()==_materials.size()
		if complete:
			for material:ShaderMaterial in _materials:
				var values:Dictionary=research_staged.get(material.get_instance_id(),{})
				if values.size()!=3:complete=false;break
		if complete:
			for material:ShaderMaterial in _materials:
				for key:String in research_staged[material.get_instance_id()]:_research_set(material,key,research_staged[material.get_instance_id()][key])
		else:_has_applied_time=false
	_source_apply_snapshot(snapshot,consumed)
	research_submitted_time=research_accepted_time;research_staged.clear()

func diagnostics()->Dictionary:
	if research_enabled and (not _has_applied_time or _time!=research_accepted_time):
		research_submit=false;_source_apply_snapshot({"time":research_accepted_time});research_submit=true;research_diagnostic_evaluations+=1
	var result:Dictionary=_source_diagnostics()
	result.research={"acceptedTime":research_accepted_time,"evaluatedTime":_time,"submittedTime":research_submitted_time,"visible":research_visible,"reason":research_reason,"viewHits":research_view_hits.duplicate(),"samples":research_samples,"writes":research_writes,"skippedFrames":research_skipped_frames,"diagnosticEvaluations":research_diagnostic_evaluations,"worldBounds":research_bound}
	return result
'''

static func make_script()->GDScript:
	var source:=FileAccess.get_file_as_string(SOURCE)
	source=source.replace("func apply_snapshot(","func _source_apply_snapshot(")
	source=source.replace("func sync_surface_state(","func _source_sync_surface_state(")
	source=source.replace("func diagnostics(","func _source_diagnostics(")
	source=source.replace("_sampler.sample_into(","_research_sample_into(")
	source=source.replace("_materials[i].set_shader_parameter(","_research_set(_materials[i],")
	source=source.replace("material.set_shader_parameter(key,current)","_research_set(material,key,current)")
	var script:=GDScript.new();script.source_code=source+BODY
	return script
