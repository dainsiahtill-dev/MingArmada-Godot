extends RefCounted
## Target-game world-space wake. Original source history/oracle is independent.
const Surface=preload("res://modules/scene_engine/water/source_surface.gd")
const ShaderSource=preload("res://modules/scene_engine/water/wake_flow.gdshader")
const CAPACITY:=128
const LIFETIME:=14.0
const CROSS:=[-1.0,-0.5,0.0,0.5,1.0]
const HEIGHT_OFFSET:=0.08
var _samples:Array=[]
var _node:MeshInstance3D
var _material:ShaderMaterial
var _time:=-1.0
var _updates:=0
var _distance_m:=0.0
var _last_position:=Vector2.ZERO
var _has_position:=false
var _last_emit_time:=-1.0
var _break_next:=true
var _emitting:=false
var _disposed:=false
var _vertices:=0
var _length_m:=0.0

func _init(parent:Node3D)->void:
	_node=MeshInstance3D.new();_node.name="TargetWakeFlow";_node.top_level=true
	_node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_node.visible=false;parent.add_child(_node)
	_material=ShaderMaterial.new();_material.shader=ShaderSource;_material.render_priority=3
	# Native wake3unique is a pre-shaped dual rail with an empty centre. It is
	# not a tiling grain field; use the retained froth texture for this adapter.
	var texture:=Surface.texture("fx_waterfroth_003.dds")
	_material.set_shader_parameter("source_texture",texture)
	_material.set_shader_parameter("source_texture_repeat",texture)
	_material.set_shader_parameter("source_repeat",true)
	_material.set_shader_parameter("source_clamp_mode",3)
	_material.set_shader_parameter("source_mip_count",texture.get_image().get_mipmap_count()+1)
	_material.set_shader_parameter("soft_depth_distance",0.08)
	_material.set_shader_parameter("lifetime_seconds",LIFETIME)
	_node.material_override=_material

static func _number(value:Variant)->bool:return (value is int or value is float) and is_finite(float(value))
static func _valid(packet:Dictionary)->bool:
	if not packet.get("enabled") is bool or not packet.get("hullAlive") is bool:return false
	if not packet.get("position") is Vector3 or not packet.position.is_finite():return false
	if not packet.get("forward") is Vector3 or not packet.forward.is_finite():return false
	if Vector2(packet.forward.x,packet.forward.z).length_squared()<0.000001:return false
	for key:String in ["speed","beam","length"]:
		if not _number(packet.get(key)):return false
	return packet.speed>=0.0 and packet.beam>0.0 and packet.length>0.0

func _reset()->void:
	_samples.clear();_distance_m=0.0;_has_position=false;_last_emit_time=-1.0
	_break_next=true;_emitting=false;_vertices=0;_length_m=0.0;_updates=0
	if is_instance_valid(_node):_node.visible=false;_node.mesh=null

func apply_snapshot(packet:Dictionary,seconds:float,water:Callable,sea:Callable)->void:
	if _disposed or not is_finite(seconds) or seconds<0.0 or not _valid(packet):return
	if seconds==_time:return
	if seconds<_time:_reset()
	var delta:=maxf(0.0,seconds-_time) if _time>=0.0 else 0.0
	_time=seconds;_updates+=1
	while not _samples.is_empty() and seconds-float(_samples[0].born)>=LIFETIME:_samples.pop_front()
	var position:=Vector2(packet.position.x,packet.position.z)
	var forward:=Vector2(packet.forward.x,packet.forward.z).normalized()
	var travel:=position.distance_to(_last_position) if _has_position else 0.0
	var teleport_limit:=maxf(float(packet.length)*1.5,float(packet.beam)*2.0+float(packet.speed)*maxf(delta,1.0/32.0)*4.0)
	var teleport:=_has_position and travel>teleport_limit
	if teleport:_break_next=true
	else:_distance_m+=travel
	_emitting=packet.enabled and packet.hullAlive and float(packet.speed)>0.25
	if not _emitting:_break_next=true
	if _emitting:
		var step:=clampf(float(packet.beam)*0.055,0.3,0.8)
		var moved:=_samples.is_empty() or position.distance_to(_samples.back().position)>=step
		if _samples.is_empty() or _break_next or (moved and seconds-_last_emit_time>=0.10):
			var broken:=_break_next or _samples.is_empty()
			if not _samples.is_empty() and forward.dot(_samples.back().forward)<0.25:broken=true
			_samples.append({"position":position,"forward":forward,"born":seconds,"distance":_distance_m,"beam":float(packet.beam),"speed":float(packet.speed),"break_before":broken})
			while _samples.size()>CAPACITY:_samples.pop_front()
			_last_emit_time=seconds;_break_next=false
	_last_position=position;_has_position=true
	_material.set_shader_parameter("accepted_time",seconds)
	_material.set_shader_parameter("trail_distance_m",_distance_m)
	_rebuild(water,sea)

func _rebuild(water:Callable,sea:Callable)->void:
	_vertices=0;_length_m=0.0
	if _samples.size()<2:_node.visible=false;_node.mesh=null;return
	var vertices:=PackedVector3Array();var uvs:=PackedVector2Array();var uv2:=PackedVector2Array();var colors:=PackedColorArray();var wet:=PackedByteArray();var indices:=PackedInt32Array()
	for row in _samples.size():
		var sample:Dictionary=_samples[row]
		var age:=maxf(0.0,_time-float(sample.born))
		var width:=float(sample.beam)*lerpf(0.65,1.5,smoothstep(0.0,LIFETIME,age))
		var side:=Vector2(-sample.forward.y,sample.forward.x)
		var strength:=smoothstep(0.25,3.0,float(sample.speed))
		for cross:float in CROSS:
			var point:Vector2=sample.position+side*(width*0.5*cross)
			var height:=float(water.call(point.x,point.y,_time)) if water.is_valid() else 0.0
			var allowed:=is_finite(height) and (not sea.is_valid() or bool(sea.call(point.x,point.y)))
			vertices.append(Vector3(point.x,(height if is_finite(height) else 0.0)+HEIGHT_OFFSET,point.y))
			uvs.append(Vector2(width*0.5*cross,float(sample.distance)))
			# Vertex R carries normalized birth speed for local flow advection;
			# alpha remains the retained birth intensity. RGB is not a surface tint.
			uv2.append(Vector2(float(sample.born),cross));colors.append(Color(clampf(float(sample.speed)/12.0,0.0,1.0),1,1,strength));wet.append(1 if allowed else 0)
		if row>0 and not sample.break_before:
			_length_m+=sample.position.distance_to(_samples[row-1].position)
			for column in CROSS.size()-1:
				var a:=(row-1)*CROSS.size()+column;var b:=row*CROSS.size()+column
				if wet[a] and wet[b] and wet[a+1]:indices.append_array(PackedInt32Array([a,b,a+1]))
				if wet[a+1] and wet[b] and wet[b+1]:indices.append_array(PackedInt32Array([a+1,b,b+1]))
	_vertices=vertices.size();_node.visible=not indices.is_empty()
	if indices.is_empty():_node.mesh=null;return
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_TEX_UV]=uvs;arrays[Mesh.ARRAY_TEX_UV2]=uv2;arrays[Mesh.ARRAY_COLOR]=colors;arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=_node.mesh as ArrayMesh
	if mesh==null:mesh=ArrayMesh.new();_node.mesh=mesh
	mesh.clear_surfaces();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)

func diagnostics()->Dictionary:
	return {"samples":_samples.size(),"time":_time,"length_m":_length_m,"emitting":_emitting,"visible":is_instance_valid(_node) and _node.visible,"vertices":_vertices,"updates":_updates,"lifetime_seconds":LIFETIME,"capacity":CAPACITY,"distance_m":_distance_m,"disposed":_disposed}

func dispose()->void:
	if _disposed:return
	_reset();_disposed=true
	if is_instance_valid(_node):_node.free()
	_node=null;_material=null
