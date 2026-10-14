extends RefCounted
## Distinct original bowfroth + family sidefroth, source controllers/pools intact.
const Compiler=preload("res://modules/scene_engine/fidelity_fx/cloud_render_compiler.gd")
const Runtime=preload("res://modules/scene_engine/fidelity_fx/particle_runtime.gd")
const Math=preload("res://modules/scene_engine/fidelity_fx/native_particle_math.gd")
const Surface=preload("res://modules/scene_engine/water/source_surface.gd")
const Footprint=preload("res://modules/scene_engine/water/target_froth_fit.gd")
const FAMILIES:=["sloop","brigantine","frigate","barque","fluyt","merchantman","treasuregalleon","fast_galleon","tartane"]
var _compiler:=Compiler.new()
var _side:Dictionary={}
var _bow:Dictionary={}
var _particles:RefCounted
var _surface:RefCounted
var _container:Node3D
var _last_time:Variant=null
var _mesh_count:=0
var _side_uv:Variant=null
var _error:=""
var _packet:Dictionary={}
var _last_camera:Dictionary={}
var _last_accepted_time:=-1.0
var _last_sea:Callable
var _authored_keys:Dictionary={}
var _authored_uv_windows:Dictionary={}
var _authored_uv_graphs:Dictionary={}
var _authored_uv_origin:Variant=null
var _footprint_carriers:Dictionary={}

static func asset(name:String)->Dictionary:return JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/source_wake/"+name+".json"))
func configure(parent:Node3D,family:int,seed:int,source_resource_name:String="")->Dictionary:
	dispose()
	var family_name:=""
	if not source_resource_name.is_empty():
		for name:String in FAMILIES:
			if source_resource_name=="fx_ship_sidefroth_"+name+".nif":family_name=name;break
	elif family>=0 and family<FAMILIES.size():family_name=FAMILIES[family]
	if family_name.is_empty():return {"ok":false,"error":"Explicit source sidefroth resource name or target family enum required"}
	_container=Node3D.new();_container.name="AuthoredFroth";parent.add_child(_container);_surface=Surface.new(_container)
	var bow_asset:=asset("fx_ship_bowfroth.nif");_bow=_compiler.compile_asset(bow_asset);_side=_compiler.compile_asset(asset("fx_ship_sidefroth_"+family_name+".nif"))
	for kind:String in ["bow","side"]:
		var graph:Dictionary=_bow if kind=="bow" else _side
		var window:=_authored_uv_window(graph)
		if window.is_empty():
			_error="Continuous authored froth requires an audited UV-only graph and shared finite source clip"
			return {"ok":false,"error":_error}
		_authored_uv_windows[kind]=window
		_authored_uv_graphs[kind]=graph
	var runtime:=Runtime.new()
	if not runtime.configure(bow_asset,seed,false):_error=runtime.get_last_error();return {"ok":false,"error":_error}
	_particles=runtime.spawn_native(seed)
	return {"ok":true,"family":family_name,"native_equivalent":false,"unresolved":["native type%9 name/index mapping","475550 birth gate/full lifecycle","DX9/Godot pixels"]}

static func _collect_authored_uv_clocks(node:Dictionary,intervals:Array)->bool:
	if node.is_empty():return true
	# The continuous seek must never re-time a transform, material-alpha curve
	# or particle owner. Current compiled authored meshes have UV channels only.
	if not node.keyframes.is_empty():return false
	if node.has("leaf"):
		var leaf:Dictionary=node.leaf
		if not leaf.alphaControllers.is_empty():return false
		for controller:Dictionary in leaf.uvControllers:
			var source:Dictionary=controller.clock.controller
			var start:=float(source.get("start_time",NAN));var stop:=float(source.get("stop_time",NAN))
			if not is_finite(start) or not is_finite(stop) or stop<=start or float(source.get("frequency",1.0))!=1.0 or float(source.get("phase",0.0))!=0.0:return false
			intervals.append({"start":start,"stop":stop,"period":stop-start})
	for child:Dictionary in node.children:
		if not _collect_authored_uv_clocks(child,intervals):return false
	return true

static func _authored_uv_window(graph:Dictionary)->Dictionary:
	var intervals:Array=[]
	for node:Dictionary in graph.roots:
		if not _collect_authored_uv_clocks(node,intervals):return {}
	if intervals.is_empty():return {}
	var selected:Dictionary=intervals[0]
	for interval:Dictionary in intervals:
		if interval!=selected:return {}
	return selected

static func outer(packet:Dictionary,bow:bool)->Dictionary:
	var heading:=float(packet.get("sourceHeading",0.0));var c:=cos(heading);var s:=sin(heading)
	# 475550 submits both templates at the same Dummy_bowfroth world position.
	# A root-position side override is a separately declared target policy.
	var bow_position:Array=packet.get("sourceBowPosition",packet.sourcePosition)
	var position:Array=bow_position if bow else packet.get("sourceSidePosition",bow_position)
	return {"rotation":packet.get("sourceRotation",[c,-s,0.0,s,c,0.0,0.0,0.0,1.0]),"translation":position,"scale":float(packet.get("bowScale" if bow else "sideScale",packet.modelScale))}

func apply_snapshot(packet:Dictionary,accepted_time:float,water:Callable,sea:Callable)->void:
	if _particles==null:return
	var now:=float(packet.get("controllerAppTime",accepted_time))
	if not is_finite(now) or now<0.0 or (_last_time!=null and now<float(_last_time)):return
	if _authored_uv_origin==null:_authored_uv_origin=now
	_packet=packet.duplicate(true)
	_last_accepted_time=accepted_time;_last_sea=sea
	# Target sailing birth gate, not a recovered 475550 lifecycle rule. Keep
	# source time and surviving world-space droplets alive when the hull stops.
	var enabled:=bool(packet.get("enabled",true));_container.visible=true
	if _last_time!=now:
		_particles.set_source_outer(outer(packet,true));_particles.advance_native(now,false,enabled);_last_time=now
	var used:Dictionary={};_mesh_count=0;_authored_keys.clear()
	for kind:String in ["bow","side"]:
		if not enabled:continue
		var graph:Dictionary=_bow if kind=="bow" else _side
		var window:Dictionary=_authored_uv_windows[kind]
		# Only the exact configure-validated graph is eligible. A separately
		# supplied graph may contain material-alpha/TRS controllers: retain its
		# original absolute clock rather than silently looping other channels.
		var local_playback:bool=graph==_authored_uv_graphs.get(kind,{})
		var phase:=float(window.start)+fposmod(now-float(_authored_uv_origin),float(window.period)) if local_playback else now
		# Target persistent sailing playback, not recovered 475550 lifecycle.
		# Source flags/keys stay intact. Explicit UV-only seek avoids a retained
		# CLAMP clock sticking at its endpoint after the global voyage time25.
		# Particle pools above continue receiving the unwrapped monotonic now.
		var states:Array=_compiler.render_states(graph,phase,outer(packet,kind=="bow"),true,{},true,false,not local_playback)
		for record:Dictionary in states:
			var controlled:Array=[];var matrix:PackedFloat32Array=record.uvMatrix
			for uv:Dictionary in record.sourceUV:controlled.append([Math.f32(matrix[0]*float(uv.u)+matrix[3]*float(uv.v)+matrix[6]),Math.f32(matrix[1]*float(uv.u)+matrix[4]*float(uv.v)+matrix[7])])
			record.uvs=controlled
			var key:=kind+"_"+str(record.block);_draw_record(key,record,packet,accepted_time,water,sea,true);used[key]=true;_authored_keys[key]=true;_mesh_count+=1
			if kind=="side":_side_uv=record.uvMatrix.duplicate()
	# Native camera basis must be provided by the scene adapter. A finite top
	# view fallback is explicitly target presentation only, never native evidence.
	var camera:Dictionary=packet.get("sourceCamera",{"right":[1.0,0.0,0.0],"up":[0.0,1.0,0.0],"direction":[0.0,0.0,-1.0]})
	used.merge(_draw_particles(packet,accepted_time,sea,camera));_last_camera=camera.duplicate(true)
	_surface.hide_unused(used)

func redraw_camera(camera:Dictionary)->void:
	# Pure rendering from last accepted source state. No history, clock advance,
	# native birth/pool/RNG work or authored water-fit/upload on camera changes.
	if _particles==null or _last_time==null or camera==_last_camera:return
	var used:=_authored_keys.duplicate()
	used.merge(_draw_particles(_packet,_last_accepted_time,_last_sea,camera))
	_last_camera=camera.duplicate(true);_surface.hide_unused(used)

func _draw_particles(packet:Dictionary,accepted_time:float,sea:Callable,camera:Dictionary)->Dictionary:
	var used:Dictionary={}
	for original:Dictionary in _particles.batch_meshes(camera):
		if original.get("kind","")!="particle system":continue
		var record:=original.duplicate();var transformed:Array=[];var batch:RefCounted=record.batch
		var controlled:Array=[];var triangles:Array=[];var vertex_colors:Array=[]
		for i in batch.vertex_count:
			var point:Vector3=batch.vertices[i]
			transformed.append(Math.point(record.world,[point.x,point.y,point.z]))
			controlled.append([batch.uvs[i].x,batch.uvs[i].y]);vertex_colors.append(batch.colors[i])
		for i in range(0,batch.index_count,3):triangles.append([batch.indices[i],batch.indices[i+1],batch.indices[i+2]])
		record.vertices=transformed;record.uvs=controlled;record.triangles=triangles;record.vertex_colors=vertex_colors
		var key:="ParticleSystem_"+str(record.block)
		_draw_record(key,record,packet,accepted_time,Callable(),sea,false);used[key]=true
	return used

func _draw_record(key:String,record:Dictionary,packet:Dictionary,time:float,water:Callable,sea:Callable,fit:bool)->void:
	var units:=float(packet.sourceToWorld);var origin_array:Array=packet.get("worldOrigin",[0.0,0.0,0.0]);var origin:=Vector3(origin_array[0],origin_array[1],origin_array[2])
	var vertices:=PackedVector3Array();var uvs:=PackedVector2Array();var colors:=PackedColorArray();var indices:=PackedInt32Array();var wet:Array=[];var relief:=PackedFloat32Array()
	var color:Array=record.get("color",[1.0,1.0,1.0]);var alpha:=float(record.get("alpha",1.0))
	var authored_colors:PackedColorArray=Compiler.authored_surface_colors(record) if record.has("localVertices") else PackedColorArray()
	for i in record.vertices.size():
		var p:=Surface.native_to_world(record.vertices[i],units,origin)
		vertices.append(p)
		# Box03 is an authored three-dimensional bow crest. Rebase its rim onto
		# the sampled sea, retaining local vertical relief rather than flattening
		# the entire source surface. Side sheets and world-space particles differ.
		var raised:=0.0
		if key.begins_with("bow_") and record.has("localVertices"):
			raised=float(record.localVertices[i][2])*float(record.world.scale)*float(record.world.rotation[8])*units
		relief.append(raised)
		uvs.append(Vector2(record.uvs[i][0],record.uvs[i][1]))
		if record.has("vertex_colors"):colors.append(record.vertex_colors[i])
		elif not authored_colors.is_empty():colors.append(authored_colors[i])
		else:colors.append(Color(color[0],color[1],color[2],alpha))
	var fit_profile:Dictionary={};var target_role:=""
	if packet.get("surfaceProfile") is Dictionary:
		if key.begins_with("side_"):fit_profile=packet.surfaceProfile;target_role="side"
		elif key.begins_with("bow_") and packet.surfaceProfile.has("targetBowRun"):
			var anchor:=Surface.native_to_world(packet.get("sourceBowPosition",packet.sourcePosition),units,origin)
			fit_profile=Footprint.bow_profile(packet.surfaceProfile,anchor)
			if not fit_profile.is_empty():target_role="bow"
	if not target_role.is_empty():
		var cached:Dictionary=_footprint_carriers.get(key,{})
		var effective_scale:=float(packet.get("sideScale" if target_role=="side" else "bowScale",packet.modelScale))
		# Floating basis norms can differ by a few ulps. Do not create a new
		# expensive carrier/cache entry for every such display-scale jitter.
		if cached.is_empty() or not is_equal_approx(float(cached.units),units) or not is_equal_approx(float(cached.scale),effective_scale):
			cached={"units":units,"scale":effective_scale,"shape":Footprint.prepare(vertices,colors,fit_profile,record.triangles)};_footprint_carriers[key]=cached
		vertices=Footprint.apply(vertices,colors,fit_profile,cached.shape)
		if target_role=="bow":
			var peak:=0.0
			for value:float in relief:peak=maxf(peak,absf(value))
			var crest:=float(fit_profile.get("targetBowCrest",0.0))
			if peak>0.00001 and is_finite(crest) and crest>=0.0:
				for i in relief.size():relief[i]*=crest/peak
		record=record.duplicate();record.target_froth_role=target_role
		record.target_froth_intensity=float(packet.surfaceProfile.get("intensity" if target_role=="side" else "bowIntensity",1.0))
		record.target_froth_world_to_hull=packet.surfaceProfile.worldToHull
		record.target_froth_time=maxf(0.0,float(packet.get("controllerAppTime",time))-float(_authored_uv_origin))
	# Fit and coastline-test the final presentation positions, not the original
	# wide carrier. Native attributes/UV and particle submission are unchanged.
	for i in vertices.size():
		var p:=vertices[i]
		if fit and water.is_valid():
			var height:=float(water.call(p.x,p.z,time))
			if is_finite(height):p.y=height+0.10+relief[i]
		vertices[i]=p;wet.append(not sea.is_valid() or bool(sea.call(p.x,p.z)))
	for triangle:Array in record.triangles:
		if wet[int(triangle[0])] and wet[int(triangle[1])] and wet[int(triangle[2])]:indices.append_array(PackedInt32Array([int(triangle[0]),int(triangle[2]),int(triangle[1])]))
	_surface.submit(key,vertices,uvs,colors,indices,record)

func diagnostics()->Dictionary:
	var particles:Dictionary=_particles.diagnostics() if _particles!=null else {}
	return {"authored_meshes":_mesh_count,"particle_systems":particles.get("systems",0),"native_births":particles.get("births",0),"side_uv":_side_uv,"error":_error,"native_equivalent":false,"adaptations":["water_surface_fit","sea_triangle_clip","target_attachment/lifecycle","finite_camera_fallback","continuous_local_authored_uv_seek"],"authoredUVPlayback":{"origin":_authored_uv_origin,"windows":_authored_uv_windows.duplicate(true),"policy":"target continuous UV-only cycle; original 475550 lifecycle unknown"},"region_uploads":_surface.region_uploads if _surface!=null else 0}
func dispose()->void:
	if _surface!=null:_surface.dispose()
	if is_instance_valid(_container):_container.free()
	_surface=null;_container=null;_particles=null;_side.clear();_bow.clear();_last_time=null;_mesh_count=0;_side_uv=null;_last_camera.clear();_authored_keys.clear();_packet.clear();_last_accepted_time=-1.0;_last_sea=Callable()
	_authored_uv_windows.clear();_authored_uv_graphs.clear();_authored_uv_origin=null
	_footprint_carriers.clear()
