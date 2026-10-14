extends RefCounted
## Target presentation: narrow waterline flow and bounded world-space spray.
## No authored carrier, native particle pool or history wake is used here.
const Foam=preload("res://modules/scene_engine/water/hull_contact_foam.gdshader")
const Spray=preload("res://modules/scene_engine/water/hull_contact_spray.gdshader")
const ROWS:=48
const COLUMNS:=5
const CAPACITY:=48
## Own packed upload buffers; no shared source/wake Surface state is involved.
class ContactBuffer:
	extends RefCounted
	var vertices:=PackedVector3Array()
	var uv:=PackedVector2Array()
	var colors:=PackedColorArray()
	var vertex_bytes:=PackedByteArray()
	var attribute_bytes:=PackedByteArray()
	var wet:=PackedByteArray()
	var previous_wet:=PackedByteArray()
	var indices:=PackedInt32Array()
	var submitted_indices:=PackedInt32Array()
	var supported:=false
	func resize(count:int)->void:
		vertices.resize(count);uv.resize(count);colors.resize(count)
		vertex_bytes.resize(count*12);attribute_bytes.resize(count*12);wet.resize(count)
		previous_wet.clear();submitted_indices.clear();supported=false
	func write(index:int,point:Vector3,texcoord:Vector2,color:Color)->void:
		vertices[index]=point;uv[index]=texcoord;colors[index]=color
		var offset:=index*12
		vertex_bytes.encode_float(offset,point.x);vertex_bytes.encode_float(offset+4,point.y);vertex_bytes.encode_float(offset+8,point.z)
		attribute_bytes[offset]=int(clampf(color.r*255.0,0.0,255.0));attribute_bytes[offset+1]=int(clampf(color.g*255.0,0.0,255.0))
		attribute_bytes[offset+2]=int(clampf(color.b*255.0,0.0,255.0));attribute_bytes[offset+3]=int(clampf(color.a*255.0,0.0,255.0))
		attribute_bytes.encode_float(offset+4,texcoord.x);attribute_bytes.encode_float(offset+8,texcoord.y)
var _container:Node3D
var _nodes:Dictionary={}
var _buffers:Dictionary={}
var _row_data:Array=[]
var _cross_values:=PackedFloat64Array()
var _cross_crest:=PackedFloat64Array()
var _cross_alpha:=PackedFloat64Array()
var _detail_level:=0
var _rows:=ROWS
var _columns:=COLUMNS
var _geometry_water_samples:=0
var _mesh_rebuilds:=0
var _region_updates:=0
var _last_gap:Variant=null
var _last_forward:Variant=null
var _sample_finite:=true
var _impact_strength:=0.0
var _closing_speed:=0.0
var _turn_bias:=0.0
var _impact_armed:=true
var _droplets:Array=[]
var _rng:=RandomNumberGenerator.new()
var _last_time:Variant=null
var _last_origin:Variant=null
var _epoch:Variant=null
var _flow_distance:=0.0
var _strength:=0.0
var _birth_accumulator:=0.0
var _births:=0
var _visual_time:=0.0
var _camera:Dictionary={}
var _profile:Dictionary={}
var _water:Callable
var _sea:Callable
var _tip_z:=0.0
var _forward:=1.0
var _span:=0.0
var _lateral_scale:=1.0
var _length_scale:=1.0
var _velocity:=Vector3.ZERO
var _water_samples:=0
var _ribbon_indices:=PackedInt32Array()

func configure(parent:Node3D,_family:int,seed:int,_source_resource_name:String="")->Dictionary:
	dispose()
	if not is_instance_valid(parent):return {"ok":false,"error":"Contact foam requires a live parent"}
	_rng.seed=seed
	_container=Node3D.new();_container.name="HullContactFroth";_container.top_level=true;parent.add_child(_container);_container.global_transform=Transform3D.IDENTITY
	for name:String in ["FlowPort","FlowStarboard","ContactSpray"]:
		var node:=MeshInstance3D.new();node.name=name
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.mesh=ArrayMesh.new()
		var material:=ShaderMaterial.new();material.shader=Spray if name=="ContactSpray" else Foam
		material.render_priority=3;node.material_override=material
		if name!="ContactSpray":material.set_shader_parameter("side_phase",.53 if name=="FlowPort" else .0)
		node.visible=false;_container.add_child(node);_nodes[name]=node
		_buffers[name]=ContactBuffer.new()
	_set_grid(ROWS,COLUMNS)
	var spray:ContactBuffer=_buffers.ContactSpray;spray.resize(CAPACITY*4)
	for index in CAPACITY:
		var first:=index*4
		spray.indices.append_array(PackedInt32Array([first,first+2,first+1,first+1,first+2,first+3]))
	for _index in CAPACITY:_droplets.append({"active":false})
	return {"ok":true,"policy":"target hull contact; independent from source and wake"}

func _set_grid(rows:int,columns:int)->void:
	_rows=rows;_columns=columns;_ribbon_indices.clear();_row_data.resize(rows)
	_cross_values.resize(columns);_cross_crest.resize(columns);_cross_alpha.resize(columns)
	for column in columns:
		var cross:=float(column)/float(columns-1);var crest:=sin(PI*cross)
		_cross_values[column]=cross;_cross_crest[column]=crest;_cross_alpha[column]=pow(1.0-cross,1.4)*(.75+.25*crest)
	for row in rows:_row_data[row]={}
	for row in rows-1:
		for column in columns-1:
			var a:=row*columns+column;var b:=a+columns
			_ribbon_indices.append_array(PackedInt32Array([a,b,a+1,a+1,b,b+1]))
	for name:String in ["FlowPort","FlowStarboard"]:_buffers[name].resize(rows*columns)

func _select_detail(value:Variant)->bool:
	var distance:=float(value) if value is float or value is int else 0.0
	if not is_finite(distance) or distance<0.0:distance=0.0
	var next:=_detail_level
	# Hysteresis keeps scroll/ship motion near a boundary from resizing every frame.
	match _detail_level:
		0:next=2 if distance>115.0 else (1 if distance>47.0 else 0)
		1:next=2 if distance>115.0 else (0 if distance<43.0 else 1)
		2:next=0 if distance<43.0 else (1 if distance<105.0 else 2)
	if next==_detail_level:return false
	_detail_level=next
	_set_grid([ROWS,24,12][next],[COLUMNS,3,3][next])
	return true

func _accept_profile(packet:Dictionary)->bool:
	var profile:Variant=packet.get("surfaceProfile")
	if not profile is Dictionary:return false
	var sections:Variant=profile.get("sections")
	if not sections is Array or sections.size()<2 or not profile.get("hullToWorld") is Transform3D or not profile.get("worldToHull") is Transform3D:return false
	var transform:Transform3D=profile.hullToWorld
	if not transform.is_finite():return false
	_length_scale=transform.basis.z.length()
	if _length_scale<.00001 or absf(transform.basis.y.y)<.00001:return false
	# Local height is solved along hull Y below. Measure the projected lateral
	# direction on a level water plane so heel cannot widen the external strip.
	var lateral:=transform.basis.x-transform.basis.y*(transform.basis.x.y/transform.basis.y.y)
	_lateral_scale=Vector2(lateral.x,lateral.z).length()
	if _lateral_scale<.00001:return false
	var previous:=-INF
	for section:Variant in sections:
		if not section is Dictionary:return false
		var z:=float(section.get("z",NAN));var left:=float(section.get("left",NAN));var right:=float(section.get("right",NAN))
		if not is_finite(z) or not is_finite(left) or not is_finite(right) or z<=previous or right<left:return false
		previous=z
	var unit:=float(packet.get("sourceToWorld",1.0))
	var position:Variant=packet.get("sourceBowPosition")
	var origin_array:Variant=packet.get("worldOrigin",[0.0,0.0,0.0])
	if not position is Array or position.size()!=3 or not origin_array is Array or origin_array.size()!=3 or not is_finite(unit) or unit<=0.0:return false
	var marker:=Vector3(float(position[0]),float(position[2]),-float(position[1]))*unit+Vector3(float(origin_array[0]),float(origin_array[1]),float(origin_array[2]))
	if not marker.is_finite():return false
	var local_marker:Vector3=profile.worldToHull*marker
	var first:=float(sections[0].z);var last:=float(sections[-1].z)
	var near_first:=absf(local_marker.z-first)<=absf(local_marker.z-last)
	_tip_z=first if near_first else last;_forward=-1.0 if near_first else 1.0
	_span=(last-first)*_length_scale
	_profile=profile
	return _span>.01

func apply_snapshot(packet:Dictionary,accepted_time:float,water:Callable,sea:Callable)->void:
	if not is_instance_valid(_container) or not is_finite(accepted_time) or accepted_time<0.0:return
	_water=water;_sea=sea
	_water_samples=0
	if not _accept_profile(packet):
		_clear_droplets()
		_reset_dynamics()
		for node:MeshInstance3D in _nodes.values():node.visible=false
		return
	var origin:Vector3=_profile.hullToWorld.origin
	var raw_elapsed:=0.0 if _last_time==null else accepted_time-float(_last_time)
	var next_epoch:Variant=packet.get("epoch")
	# GDScript rejects e.g. String != int. A differently typed timeline ID is
	# still a new timeline, without invoking that invalid comparison.
	var changed_epoch:bool=_epoch!=null and (typeof(next_epoch)!=typeof(_epoch) or next_epoch!=_epoch)
	var discontinuity:bool=raw_elapsed<0.0 or changed_epoch or (_last_origin!=null and origin.distance_to(_last_origin)>maxf(8.0,_span*1.5))
	var speed:=float(packet.get("targetSpeed",0.0))
	if not is_finite(speed):speed=0.0
	speed=clampf(speed,0.0,30.0)
	var supplied_velocity:Variant=packet.get("targetVelocity")
	_velocity=_forward_world()*speed
	if supplied_velocity is Array and supplied_velocity.size()==3:
		_velocity=Vector3(float(supplied_velocity[0]),0.0,float(supplied_velocity[2]))
		if not _velocity.is_finite():_velocity=Vector3.ZERO
		_velocity=_velocity.limit_length(30.0)
		speed=maxf(0.0,_velocity.dot(_forward_world()))
	var enabled:bool=bool(packet.get("enabled",true)) and speed>.35
	var target:=smoothstep(.35,6.0*.514444,speed) if enabled else 0.0
	if discontinuity:
		_clear_droplets();_flow_distance=0.0;_birth_accumulator=0.0
		_reset_dynamics()
		raw_elapsed=0.0;_strength=target
	if _last_time==null:_strength=target
	var dt:=clampf(raw_elapsed,0.0,.25)
	_camera=packet.get("sourceCamera",_camera).duplicate(true)
	_select_detail(packet.get("targetCameraDistance",_camera.get("targetDistance",0.0)))
	# A same-time pose/camera repaint may redraw geometry, but keeps the previous
	# accepted gap/heading so it cannot contaminate the next physical derivative.
	if _last_time==null or discontinuity or raw_elapsed>0.0:
		_update_dynamics(accepted_time,raw_elapsed,enabled)
	if raw_elapsed>0.0:
		_strength=lerpf(_strength,target,1.0-exp(-minf(raw_elapsed,2.0)/.2))
		_flow_distance+=speed*dt if enabled else 0.0
		_age_droplets(raw_elapsed,accepted_time)
		if enabled:
			_birth_accumulator+=(lerpf(8.0,18.0,target)+16.0*_impact_strength)*[1.0,.55,.25][_detail_level]*dt
			var births:=mini(CAPACITY,floori(_birth_accumulator));_birth_accumulator-=births
			for _index in births:_birth(accepted_time,target)
		else:_birth_accumulator=0.0
	_visual_time=accepted_time;_last_time=accepted_time;_last_origin=origin;_epoch=next_epoch
	var before:=_water_samples
	_draw_ribbons(accepted_time)
	_geometry_water_samples=_water_samples-before
	_draw_droplets()

func _reset_dynamics()->void:
	_last_gap=null;_last_forward=null;_impact_strength=0.0;_closing_speed=0.0;_turn_bias=0.0;_impact_armed=true

func _update_dynamics(time:float,elapsed:float,enabled:bool)->void:
	if not enabled:
		_reset_dynamics();return
	var forward:=_forward_world()
	var z:=_tip_z-_forward*minf(.8,_span*.15)/_length_scale
	var probe:Vector3=_profile.hullToWorld*Vector3(0.0,0.0,z)
	var height:=_height(probe,time)
	if not _sample_finite:
		_reset_dynamics();return
	var gap:=probe.y-height
	_closing_speed=0.0
	if elapsed>0.0 and elapsed<=.25 and _last_gap!=null:
		_closing_speed=clampf((float(_last_gap)-gap)/elapsed,-30.0,30.0)
		_impact_strength*=exp(-elapsed/.28)
		var angle:float=atan2(_last_forward.cross(forward).y,_last_forward.dot(forward)) if _last_forward!=null else 0.0
		var target_bias:=clampf(angle/elapsed*.16,-.18,.18)
		_turn_bias=lerpf(_turn_bias,target_bias,1.0-exp(-elapsed/.12))
		if _closing_speed<=.35:_impact_armed=true
		elif _impact_armed and absf(gap)<=.5 and (not _sea.is_valid() or bool(_sea.call(probe.x,probe.z))):
			var contact:=_row_contact(z,time)
			if maxf(contact.coverage.x,contact.coverage.y)>.05:
				_impact_strength=maxf(_impact_strength,smoothstep(.35,4.0,_closing_speed));_impact_armed=false
	else:
		_impact_strength=0.0;_turn_bias=0.0;_impact_armed=true
	_last_gap=gap;_last_forward=forward

static func _section_edges(sections:Array,z:float)->Vector2:
	if z<=float(sections[0].z):return Vector2(float(sections[0].left),float(sections[0].right))
	if z>=float(sections[-1].z):return Vector2(float(sections[-1].left),float(sections[-1].right))
	var low:=0;var high:=sections.size()-1
	while high-low>1:
		var middle:=(low+high)/2
		if float(sections[middle].z)<z:low=middle
		else:high=middle
	var a:Dictionary=sections[low];var b:Dictionary=sections[high]
	var weight:float=(z-float(a.z))/(float(b.z)-float(a.z))
	return Vector2(lerpf(float(a.left),float(b.left),weight),lerpf(float(a.right),float(b.right),weight))

func _ring_edge(z:float,height:float,side:int)->Vector2:
	var rings:Array=_profile.get("verticalSections",[])
	if rings.is_empty():return Vector2(_section_edges(_profile.sections,z)[side],1.0)
	var minimum:=float(rings[0].height);var maximum:=float(rings[-1].height)
	if height<minimum or height>maximum:return Vector2(_section_edges(_profile.sections,z)[side],0.0)
	var low:=0;var high:=rings.size()-1
	while high-low>1:
		var middle:=(low+high)/2
		if float(rings[middle].height)<height:low=middle
		else:high=middle
	# At an authored ring plane, use that plane alone. Neighbouring rings may
	# have shorter ends; their extent must not clip exact-height contact.
	if float(rings[high].height)==height:low=high
	elif float(rings[low].height)==height:high=low
	var lower:Dictionary=rings[low];var upper:Dictionary=rings[high]
	var span:=float(upper.height)-float(lower.height)
	var weight:=clampf((height-float(lower.height))/span,0.0,1.0) if span>.00001 else 0.0
	var near:=maxf(float(lower.sections[0].z),float(upper.sections[0].z))
	var far:=minf(float(lower.sections[-1].z),float(upper.sections[-1].z))
	if z<near or z>far:return Vector2(_section_edges(_profile.sections,z)[side],0.0)
	var edge:=lerpf(_section_edges(lower.sections,z)[side],_section_edges(upper.sections,z)[side],weight)
	var coverage:=smoothstep(0.0,.45,minf(z-near,far-z)*_length_scale)*smoothstep(0.0,.06,minf(height-minimum,maximum-height))
	return Vector2(edge,coverage)

func _row_contact(z:float,time:float,above:float=0.0)->Dictionary:
	var out:=_section_edges(_profile.sections,z)
	var transform:Transform3D=_profile.hullToWorld
	var center:=transform*Vector3(0.0,0.0,z)
	var water_height:=_height(center,time)
	var dry_point:=Vector3(center.x,water_height+above,center.z)
	var initial_y:=(water_height+above-center.y)/transform.basis.y.y
	var local_y:=Vector2(initial_y,initial_y)
	var coverage:=Vector2.ONE
	if _profile.get("verticalSections",[]).is_empty():return {"edges":out,"local_y":local_y,"coverage":coverage,"dry_point":dry_point}
	# Heave changes the contact height; heel gives different local heights on
	# each side. Solve against the actual sea, rather than reusing a y=0 beam.
	for side in 2:
		for _iteration in 2:
			var point:=transform*Vector3(out[side],local_y[side],z)
			local_y[side]+=(_height(point,time)+above-point.y)/transform.basis.y.y
			var sampled:=_ring_edge(z,local_y[side],side)
			out[side]=sampled.x;coverage[side]=minf(coverage[side],sampled.y)
	return {"edges":out,"local_y":local_y,"coverage":coverage,"dry_point":dry_point}

func _height(point:Vector3,time:float)->float:
	_water_samples+=1
	var height:=float(_water.call(point.x,point.z,time)) if _water.is_valid() else 0.0
	_sample_finite=is_finite(height)
	return height if _sample_finite else 0.0

func _surface_point(x:float,z:float,time:float,above:float)->Vector3:
	# Preserve exact hull-local X/Z while solving the water intersection along
	# the displayed hull's Y axis, including pitch/heel and nonuniform scale.
	var transform:Transform3D=_profile.hullToWorld
	var local_y:=0.0;var point:=transform*Vector3(x,local_y,z)
	for _iteration in 2:
		var error:=_height(point,time)+above-point.y
		local_y+=error/transform.basis.y.y
		point=transform*Vector3(x,local_y,z)
		if absf(error)<.0001:break
	return point

func _forward_world()->Vector3:
	var forward:Vector3=_profile.hullToWorld.basis.z*_forward
	forward.y=0.0;return forward.normalized()

func _draw_ribbons(time:float)->void:
	if _strength<=.001:
		_nodes.FlowPort.visible=false;_nodes.FlowStarboard.visible=false
		return
	for row in _rows:
		var distance:=float(row)/float(_rows-1)*_span*.85
		var z:=_tip_z-_forward*distance/_length_scale
		var contact:=_row_contact(z,time)
		# Forebody breaking water is strongest just aft of the tip. A weak
		# midbody tail gives flow continuity without painting a white skirt.
		var forebody:=.15+.85*exp(-distance/(_span*.22))
		var envelope:=smoothstep(0.0,.35,distance)*forebody*(1.0-smoothstep(_span*.70,_span*.85,distance))
		var data:Dictionary=_row_data[row]
		data.z=z;data.distance=distance;data.edges=contact.edges;data.local_y=contact.local_y;data.coverage=contact.coverage;data.dry_point=contact.dry_point
		data.envelope=envelope;data.width=lerpf(.18,.55,_strength)*(.35+.65*forebody)
		data.crest=(.16*_strength+.06*_impact_strength)*exp(-pow((distance-.8)/1.1,2.0))
	var transform:Transform3D=_profile.hullToWorld
	for side:float in [-1.0,1.0]:
		var name:="FlowPort" if side<0.0 else "FlowStarboard"
		var node:MeshInstance3D=_nodes[name]
		var buffer:ContactBuffer=_buffers[name]
		for row in _rows:
			var data:Dictionary=_row_data[row]
			var distance:=float(data.distance);var z:=float(data.z)
			var edges:Vector2=data.edges
			var edge:=edges.x if side<0.0 else edges.y
			var local_y:float=data.local_y[0 if side<0.0 else 1]
			var coverage:float=data.coverage[0 if side<0.0 else 1]
			var envelope:=float(data.envelope);var width:=float(data.width)
			for column in _columns:
				var cross:=_cross_values[column]
				var crest:float=data.crest*_cross_crest[column]
				var raised_edge:=edge
				var x:=raised_edge+side*(.025+cross*width)/_lateral_scale
				# A flared bow is wider at the raised crest than at the sea plane.
				# Select the actual cross section at this vertex's approximate
				# local height before the one final water query. This keeps the
				# bright core outside the opaque hull without weakening depth.
				if coverage>.001 and not _profile.get("verticalSections",[]).is_empty():
					for _iteration in 2:
						var extra_height:=.045+crest-transform.basis.x.y*(x-edge)
						var raised_local:Vector3=Vector3(x,local_y,z)+_profile.worldToHull.basis*Vector3.UP*extra_height
						var section:=_ring_edge(raised_local.z,raised_local.y,0 if side<0.0 else 1)
						if section.y>.0:raised_edge=minf(edge,section.x) if side<0.0 else maxf(edge,section.x)
						x=raised_edge+side*(.025+cross*width)/_lateral_scale
				var point:=transform*Vector3(x,local_y,z)
				# One final sample per rendered vertex: actual sea height remains
				# exact, while row contact/height work is shared by both ribbons.
				# Dry vertices participate in no triangle. Collapse them onto the
				# row's actually sampled center (also exact for arbitrary samplers),
				# rather than querying invisible vertices or assuming a flat sea.
				if coverage>.001:point.y=_height(point,time)+.045+crest
				else:point=data.dry_point+Vector3.UP*(.045+crest)
				var alpha:=envelope*coverage*_cross_alpha[column]
				if row==0 or row==_rows-1 or column==_columns-1:alpha=0.0
				var index:=row*_columns+column
				buffer.write(index,point,Vector2(distance,cross),Color(.87,.96,1.0,alpha))
				buffer.wet[index]=1 if coverage>.001 and (not _sea.is_valid() or bool(_sea.call(point.x,point.z))) else 0
		if buffer.wet!=buffer.previous_wet:
			buffer.indices.clear()
			for i in range(0,_ribbon_indices.size(),3):
				var a:=_ribbon_indices[i];var b:=_ribbon_indices[i+1];var c:=_ribbon_indices[i+2]
				if buffer.wet[a] and buffer.wet[b] and buffer.wet[c]:buffer.indices.append_array(PackedInt32Array([a,b,c]))
			buffer.previous_wet=buffer.wet.duplicate()
		_submit(node,buffer)
		var material:ShaderMaterial=node.material_override
		material.set_shader_parameter("flow_distance",_flow_distance)
		material.set_shader_parameter("visual_time",time)
		material.set_shader_parameter("strength",_strength)
		material.set_shader_parameter("impact_strength",_impact_strength)
		material.set_shader_parameter("turn_bias",-_turn_bias*side*_forward)
		node.visible=node.visible and _strength>.001

func _birth(time:float,strength:float)->void:
	var index:=-1
	for i in _droplets.size():
		if not _droplets[i].active:index=i;break
	if index<0:return
	var side:=-1.0 if _rng.randf()<.5 else 1.0
	var distance:=_rng.randf_range(.3,1.3)
	var z:=_tip_z-_forward*distance/_length_scale
	var radius:=_rng.randf_range(.035,.10)
	var contact:=_row_contact(z,time,.06+radius)
	if float(contact.coverage[0 if side<0.0 else 1])<=.01:return
	var edges:Vector2=contact.edges
	var edge:=edges.x if side<0.0 else edges.y
	var x:=edge+side*_rng.randf_range(.035,.10)/_lateral_scale
	var point:=_surface_point(x,z,time,.06+radius)
	if _sea.is_valid() and not bool(_sea.call(point.x,point.z)):return
	var transform:Transform3D=_profile.hullToWorld
	var outward:=transform.basis.x;outward.y=0.0;outward=outward.normalized()*side
	var aft:=transform.basis.z;aft.y=0.0;aft=aft.normalized()*-_forward
	var velocity:=_velocity*.75+outward*_rng.randf_range(.35,.75)+aft*_rng.randf_range(.35,.80)+Vector3.UP*(_rng.randf_range(.8,1.4)+.6*_impact_strength)
	_droplets[index]={"active":true,"position":point,"birth_position":point,"velocity":velocity,"radius":radius,"life":_rng.randf_range(.3,.65),"age":0.0,"strength":strength,"bow_distance":distance}
	_births+=1

func _age_droplets(elapsed:float,time:float)->void:
	for drop:Dictionary in _droplets:
		if not drop.active:continue
		if float(drop.age)+elapsed>=float(drop.life):drop.active=false;continue
		var remaining:=elapsed
		while remaining>0.000001:
			var dt:=minf(remaining,.025);remaining-=dt
			var point:Vector3=drop.position;var velocity:Vector3=drop.velocity
			point+=velocity*dt+Vector3.DOWN*4.9*dt*dt;velocity.y-=9.8*dt
			drop.position=point;drop.velocity=velocity;drop.age=float(drop.age)+dt
			if velocity.y<0.0 and point.y<=_height(point,time)+.02:
				drop.active=false;break

static func _camera_axis(value:Variant,fallback:Vector3)->Vector3:
	if not value is Array or value.size()!=3:return fallback
	var axis:=Vector3(float(value[0]),float(value[2]),-float(value[1]))
	return axis.normalized() if axis.is_finite() and axis.length_squared()>.00001 else fallback

func _draw_droplets()->void:
	var right:=_camera_axis(_camera.get("right"),Vector3.RIGHT)
	var up:=_camera_axis(_camera.get("up"),Vector3.UP)
	up-=right*up.dot(right)
	if up.length_squared()<.00001:up=Vector3.UP if absf(right.y)<.9 else Vector3.FORWARD
	up=up.normalized()
	var active:=0
	var anchor:=Vector3.ZERO
	for drop:Dictionary in _droplets:
		if drop.active:
			active+=1
			if active==1:anchor=drop.position
	if active==0:_nodes.ContactSpray.visible=false;return
	var buffer:ContactBuffer=_buffers.ContactSpray
	for index in CAPACITY:
		var drop:Dictionary=_droplets[index]
		# Fixed inactive slots carry no area and share an active world anchor, so
		# they neither enlarge culling bounds to world zero nor retain dead trails.
		var point:Vector3=drop.position if drop.active else anchor
		var radius:=float(drop.radius) if drop.active else 0.0
		var alpha:=0.0
		if drop.active and index%[1,2,3][_detail_level]==0:
			var age:=float(drop.age);var life:=float(drop.life)
			alpha=smoothstep(0.0,.045,age)*(1.0-smoothstep(life*.55,life,age))*float(drop.strength)*.72
		for corner in 4:
			var horizontal:=1.0 if corner%2 else -1.0;var vertical:=1.0 if corner>=2 else -1.0
			buffer.write(index*4+corner,point+right*radius*horizontal+up*radius*vertical,Vector2(float(corner%2),float(corner/2)),Color(.86,.95,1.0,alpha))
	_submit(_nodes.ContactSpray,buffer)

func _submit(node:MeshInstance3D,buffer:ContactBuffer)->void:
	var mesh:ArrayMesh=node.mesh
	node.visible=not buffer.indices.is_empty()
	if not node.visible:return
	if mesh.get_surface_count()>0 and buffer.supported and buffer.submitted_indices==buffer.indices:
		mesh.surface_update_vertex_region(0,0,buffer.vertex_bytes)
		mesh.surface_update_attribute_region(0,0,buffer.attribute_bytes)
		_region_updates+=1
	else:
		mesh.clear_surfaces()
		var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=buffer.vertices;arrays[Mesh.ARRAY_TEX_UV]=buffer.uv;arrays[Mesh.ARRAY_COLOR]=buffer.colors;arrays[Mesh.ARRAY_INDEX]=buffer.indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
		var count:=buffer.vertices.size();var format:=mesh.surface_get_format(0)
		buffer.supported=RenderingServer.mesh_surface_get_format_vertex_stride(format,count)==12 and RenderingServer.mesh_surface_get_format_attribute_stride(format,count)==12 and RenderingServer.mesh_surface_get_format_offset(format,count,Mesh.ARRAY_TEX_UV)==4 and not format&Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES
		buffer.submitted_indices=buffer.indices.duplicate();_mesh_rebuilds+=1
	var low:=buffer.vertices[0];var high:=low
	for point:Vector3 in buffer.vertices:low=low.min(point);high=high.max(point)
	mesh.custom_aabb=AABB(low,(high-low).max(Vector3(.00001,.00001,.00001)))

func redraw_camera(camera:Dictionary)->void:
	if not is_instance_valid(_container) or camera==_camera:return
	_camera=camera.duplicate(true)
	if camera.has("targetDistance") and _select_detail(camera.targetDistance) and not _profile.is_empty():
		_water_samples=0
		_draw_ribbons(_visual_time);_geometry_water_samples=_water_samples
	_draw_droplets()

func _clear_droplets()->void:
	for drop:Dictionary in _droplets:drop.active=false

func diagnostics()->Dictionary:
	var active:=0
	for drop:Dictionary in _droplets:
		if drop.active:active+=1
	var ribbons:=0
	for name:String in ["FlowPort","FlowStarboard"]:
		if _nodes.has(name) and _nodes[name].visible:ribbons+=1
	return {"authored_meshes":0,"particle_systems":0,"native_births":0,"target_ribbons":ribbons,"target_droplets":active,"target_births":_births,"strength":_strength,"flow_distance":_flow_distance,"visual_time":_visual_time,"capacity":CAPACITY,"water_samples":_water_samples,"geometry_water_samples":_geometry_water_samples,"impact_strength":_impact_strength,"closing_speed":_closing_speed,"turn_bias":_turn_bias,"detail_level":_detail_level,"active_rows":_rows,"active_columns":_columns,"detail_rows":_rows,"detail_columns":_columns,"mesh_rebuilds":_mesh_rebuilds,"region_updates":_region_updates,"region_uploads":_region_updates,"render_backend":DisplayServer.get_name(),"native_equivalent":false}

func dispose()->void:
	if is_instance_valid(_container):_container.free()
	_container=null;_nodes.clear();_buffers.clear();_row_data.clear();_cross_values.clear();_cross_crest.clear();_cross_alpha.clear();_droplets.clear();_profile.clear();_camera.clear();_ribbon_indices.clear()
	_last_time=null;_last_origin=null;_epoch=null;_flow_distance=0.0;_strength=0.0;_birth_accumulator=0.0;_births=0;_visual_time=0.0;_velocity=Vector3.ZERO;_water_samples=0
	_water=Callable();_sea=Callable()
	_detail_level=0;_rows=ROWS;_columns=COLUMNS;_geometry_water_samples=0;_mesh_rebuilds=0;_region_updates=0;_reset_dynamics()
