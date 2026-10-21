extends RefCounted
## Conservative scene-local visibility for immutable shore topology. The shader
## changes world Y only. Both desired and still-submitted displacement must be
## outside every active view before the caller may leave old materials untouched.
const HEIGHT_OFFSET:=0.055
const HEIGHT_GUARD:=1.0
const PLANE_EPSILON:=0.01
var _main:Camera3D
var _reflection:Camera3D
var _reflection_enabled:=false
var _geometry:=AABB()
var _transform:=Transform3D.IDENTITY
var _has_geometry:=false
var visible:=true
var reason:="missing-main-camera"
var bounds:=AABB()
var view_hits:Array[bool]=[]

func set_cameras(main:Camera3D,reflection:Camera3D=null,reflection_enabled:bool=false)->void:
	_main=main;_reflection=reflection;_reflection_enabled=reflection_enabled

func reset()->void:
	_main=null;_reflection=null;_reflection_enabled=false
	_has_geometry=false;_geometry=AABB();_transform=Transform3D.IDENTITY
	visible=true;reason="missing-main-camera";bounds=AABB();view_hits.clear()

func _capture_geometry(owner:Node3D)->bool:
	_has_geometry=false;_transform=owner.global_transform
	if not _transform.is_finite():return false
	var captured:=AABB();var found:=false
	# Children and mesh topology are private and built only during configure().
	# Configure/dispose reset this cache; movement of the owner refreshes it.
	for child:Node in owner.get_children():
		if not child is MeshInstance3D or child.mesh==null:continue
		var local:AABB=child.mesh.get_aabb()
		if not local.position.is_finite() or not local.size.is_finite() or not child.global_transform.is_finite():return false
		for corner in 8:
			var point:Vector3=child.global_transform*local.get_endpoint(corner)
			if not point.is_finite():return false
			if not found:captured=AABB(point,Vector3.ZERO);found=true
			else:captured=captured.expand(point)
	_geometry=captured;_has_geometry=found
	return _has_geometry

func _displacement(components:Variant,count:Variant,tide:Variant)->Vector2:
	if not components is PackedVector4Array or not (count is int or count is float) or not is_finite(float(count)) or int(count)!=float(count) or int(count)<0 or int(count)>8 or components.size()<int(count) or not (tide is float or tide is int) or not is_finite(float(tide)):return Vector2(NAN,NAN)
	var amplitude:=0.0
	for component:Vector4 in components:
		if not component.is_finite():return Vector2(NAN,NAN)
	for index in int(count):amplitude+=absf(components[index].x)
	return Vector2(float(tide)+HEIGHT_OFFSET-amplitude-HEIGHT_GUARD,float(tide)+HEIGHT_OFFSET+amplitude+HEIGHT_GUARD)

func _unknown(detail:String)->bool:
	visible=true;reason=detail;return true

func keep_visible(detail:String)->void:
	view_hits.clear();visible=true;reason=detail

func may_draw(owner:Node3D,ocean:ShaderMaterial,submitted:Dictionary)->bool:
	view_hits.clear()
	if not is_instance_valid(owner) or not owner.is_inside_tree():return _unknown("unknown-owner")
	if not _has_geometry or owner.global_transform!=_transform:
		if not _capture_geometry(owner):return _unknown("unknown-geometry")
	if ocean==null or ocean.shader==null:return _unknown("unknown-surface")
	var surface_time:Variant=ocean.get_shader_parameter("simulation_time")
	if not (surface_time is float or surface_time is int) or not is_finite(float(surface_time)):return _unknown("unknown-surface-clock")
	var desired:=_displacement(ocean.get_shader_parameter("wave_components"),ocean.get_shader_parameter("wave_count"),ocean.get_shader_parameter("u_tide"))
	var previous:=_displacement(submitted.get("wave_components"),submitted.get("wave_count"),submitted.get("surface_tide"))
	if not desired.is_finite() or not previous.is_finite():return _unknown("unknown-wave-displacement")
	var low:=minf(desired.x,previous.x);var high:=maxf(desired.y,previous.y)
	bounds=AABB(Vector3(_geometry.position.x,low,_geometry.position.z),Vector3(_geometry.size.x,high-low,_geometry.size.z))
	if not is_instance_valid(_main) or not _main.is_inside_tree():return _unknown("missing-main-camera")
	var cameras:Array[Camera3D]=[_main]
	if _reflection_enabled:
		if not is_instance_valid(_reflection) or not _reflection.is_inside_tree():return _unknown("missing-reflection-camera")
		cameras.append(_reflection)
	visible=false
	for camera:Camera3D in cameras:
		var planes:Array[Plane]=camera.get_frustum()
		if planes.size()!=6:return _unknown("unknown-frustum")
		var outside:=false
		for plane:Plane in planes:
			if not plane.normal.is_finite() or not is_finite(plane.d):return _unknown("unknown-frustum")
			var all_outside:=true
			for corner in 8:
				if plane.distance_to(bounds.get_endpoint(corner))<=PLANE_EPSILON:all_outside=false;break
			if all_outside:outside=true;break
		view_hits.append(not outside);visible=visible or not outside
	reason="visible-union" if visible else "outside-complete-union"
	return visible

func diagnostics()->Dictionary:
	return {"visible":visible,"reason":reason,"bounds":bounds,"viewHits":view_hits.duplicate()}
