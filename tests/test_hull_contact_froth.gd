extends SceneTree
## Actual ship hull sections drive bounded contact ribbons and world droplets.
const Ship=preload("res://game/presentation/ships/ship_view.gd")
const Packet=preload("res://game/presentation/world/source_water_packet.gd")
const PATH:="res://modules/scene_engine/water/hull_contact_froth.gd"
var assertions:=0
var failures:=0
var observations:Array=[]
var water_calls:=0
func _initialize()->void:_run.call_deferred()
func check(ok:bool,message:String)->bool:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL: ",message)
	return ok
func _water(x:float,z:float,_time:float)->float:
	water_calls+=1
	return 2.0+.003*x-.002*z
func _flat(_x:float,_z:float,_time:float)->float:
	water_calls+=1;return 0.0
func _state(kind:String,speed:float)->Dictionary:
	return {"id":"contact","kind":kind,"time":0.0,"hull":100.0,"sailDeployment":1.0,"visual":{"position":{"x":20.0,"y":1.2,"z":10.0},"velocity":{"x":cos(.3)*speed,"z":sin(.3)*speed},"heading":.3,"pitch":.12,"heel":.08}}
func _packet(actor:Node3D,kind:String,speed:float)->Dictionary:
	var state:=_state(kind,speed);actor.apply_snapshot(state,{},0.0)
	var source:Dictionary=Packet.compose({"time":0.0,"environment":{"route":"sailing","acceptedTime":0.0,"sourceCallIndex":0},"ships":[state]},{"contact":actor},null).ships[0].sourceWake
	var packet:Dictionary=source.duplicate(true);packet.merge(source.froth,true)
	# Module contract: targetSpeed is m/s, independent of native source scale.
	packet.targetSpeed=speed;return packet
func _node(owner:Node3D,name:String)->MeshInstance3D:
	for parent:Node in owner.get_children():
		for node:Node in parent.get_children():
			if node is MeshInstance3D and node.name==name:return node
	return null
func _snapshot(effect:RefCounted)->PackedByteArray:
	return var_to_bytes({"droplets":effect._droplets,"flow":effect.diagnostics().flow_distance,"births":effect.diagnostics().target_births,"time":effect.diagnostics().visual_time})
func _crosssection(profile:Dictionary,point:Vector3)->Dictionary:
	var rings:Array=profile.get("verticalSections",[])
	if rings.is_empty() or point.y<float(rings[0].height) or point.y>float(rings[-1].height):return {}
	var lower:Dictionary=rings[0];var upper:Dictionary=rings[-1]
	for ring:Dictionary in rings:
		if float(ring.height)<=point.y:lower=ring
		if float(ring.height)>=point.y:upper=ring;break
	for ring:Dictionary in [lower,upper]:
		if point.z<float(ring.sections[0].z) or point.z>float(ring.sections[-1].z):return {}
	var weight:=inverse_lerp(float(lower.height),float(upper.height),point.y) if upper.height!=lower.height else 0.0
	var values:Array=[]
	for ring:Dictionary in [lower,upper]:
		var section:Vector2=Vector2.ZERO
		for i in range(1,ring.sections.size()):
			var a:Dictionary=ring.sections[i-1];var b:Dictionary=ring.sections[i]
			if point.z<=float(b.z):
				var t:=inverse_lerp(float(a.z),float(b.z),point.z)
				section=Vector2(lerpf(float(a.left),float(b.left),t),lerpf(float(a.right),float(b.right),t));break
		values.append(section)
	return {"edges":values[0].lerp(values[1],weight)}
func _shape(effect:RefCounted,owner:Node3D,packet:Dictionary,require_rings:bool=true)->float:
	var profile:Dictionary=packet.surfaceProfile
	if require_rings:check(profile.get("verticalSections",[]).size()>=10,"actual profile includes multiple real hull-height slices")
	var length_scale:float=profile.hullToWorld.basis.z.length()
	var sections:Array=profile.sections
	var span:=absf(float(sections[-1].z)-float(sections[0].z))*length_scale
	var maximum_crest:=0.0
	for key:String in ["FlowPort","FlowStarboard"]:
		var node:=_node(owner,key)
		if not check(node!=null,"actual contact ribbon exists "+key):continue
		var arrays:Array=node.mesh.surface_get_arrays(0)
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var uv:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
		var colors:PackedColorArray=arrays[Mesh.ARRAY_COLOR]
		check(vertices.size()==48*5 and arrays[Mesh.ARRAY_INDEX].size()>0 and arrays[Mesh.ARRAY_INDEX].size()<=47*4*6,"ribbon uses bounded48 by5 geometry with actual contact clipping")
		var all_finite:=true;var water_fit:=true;var outer_clear:=true;var crest_max:=-INF;var width_max:=0.0
		for row in 48:
			width_max=maxf(width_max,Vector2(vertices[row*5].x-vertices[row*5+4].x,vertices[row*5].z-vertices[row*5+4].z).length())
			for column in 5:
				var i:=row*5+column;var point:=vertices[i]
				all_finite=all_finite and point.is_finite() and uv[i].is_finite()
				var relief:=point.y-_water(point.x,point.z,0.0)-.045
				water_fit=water_fit and relief>=-.00002 and relief<.22
				crest_max=maxf(crest_max,relief)
				if column==4:outer_clear=outer_clear and colors[i].a==0.0
		check(all_finite and water_fit,"actual pose gives finite sampled-water ribbons with small3D crest")
		check(crest_max>.015,"contact crest retains visible3D relief")
		maximum_crest=maxf(maximum_crest,crest_max)
		check(width_max>=.17 and width_max<=.60,"floating strip remains narrow while following actual hull flare")
		check(outer_clear and colors[0].a==0.0 and colors[47*5].a==0.0,"outer edge and longitudinal ends fade rather than surrounding hull")
		check(absf(uv[0].x)<.00001 and absf(uv[-1].x-span*.85)<.0001,"longitudinalUV follows true world-metre bow-to-aft distance")
		check(uv[0].y==0.0 and uv[4].y==1.0,"transverseUV spans0 to1")
		check(node.material_override.get_shader_parameter("strength")>.9,"actual contact shader receives moving strength")
		var clear_shell:=true
		var minimum_clearance:=INF;var maximum_clearance:=0.0;var clearance_vertex:=-1
		for index:int in arrays[Mesh.ARRAY_INDEX]:
			if colors[index].a<=.02:continue
			var local:Vector3=profile.worldToHull*vertices[index]
			var sampled:=_crosssection(profile,local)
			if sampled.is_empty():continue
			var edges:Vector2=sampled.edges
			var clearance:=edges.x-local.x if key=="FlowPort" else local.x-edges.y
			maximum_clearance=maxf(maximum_clearance,clearance)
			if clearance<minimum_clearance:minimum_clearance=clearance;clearance_vertex=index
			clear_shell=clear_shell and (local.x<=edges.x-.015 if key=="FlowPort" else local.x>=edges.y+.015)
		check(clear_shell,"visible raised crest clears actual hull at its own local height "+key+" beam="+str(profile.beam)+" clearance="+str(minimum_clearance)+" vertex="+str(clearance_vertex))
		# Measure against each vertex's actual-height shell, rather than the
		# difference between two hull edges at different water/heel heights.
		var transform:Transform3D=profile.hullToWorld
		var lateral:=transform.basis.x-transform.basis.y*(transform.basis.x.y/transform.basis.y.y)
		check(maximum_clearance*Vector2(lateral.x,lateral.z).length()<=.55+.025+.01,"visible foam stays inside55cm external band plus attachment gap")
		var head_row:=0
		for row in 48:
			if absf(uv[row*5].x-.8)<absf(uv[head_row*5].x-.8):head_row=row
		if not require_rings:check(colors[head_row*5].a>.55,"breaking-water alpha focuses near bow.8m rather than hull middle")
		check(colors[24*5].a<.45,"midbody foam is lighter than bow to prevent a wide white skirt")
	check(effect.diagnostics().authored_meshes==0 and effect.diagnostics().particle_systems==0 and effect.diagnostics().native_births==0,"target contact module uses no original wide authored resources/native owner")
	return maximum_crest

func _case(module:Script,kind:String)->void:
	var actor:=Ship.new();root.add_child(actor)
	if not check(actor.configure(kind),"actual ship configures "+kind):actor.free();return
	var packet:=_packet(actor,kind,6.0*.514444)
	var owner:=Node3D.new();root.add_child(owner)
	var effect:RefCounted=module.new()
	check(effect.configure(owner,int(packet.family),17,str(packet.sourceResourceName)).ok,"contact effect configures "+kind)
	water_calls=0;effect.apply_snapshot(packet,0.0,_water,Callable())
	check(water_calls<=1000,"single real contact frame stays within1000 water queries")
	var peak_crest:=_shape(effect,owner,packet)
	var peak_samples:=0
	for index in range(1,17):
		water_calls=0;effect.apply_snapshot(packet,float(index)*.025,_water,Callable())
		peak_samples=maxi(peak_samples,water_calls)
		check(water_calls<=1000,"moving geometry plus spray stays within1000 water queries")
	var diag:Dictionary=effect.diagnostics()
	check(diag.target_ribbons==2 and diag.target_droplets>=0 and diag.target_droplets<=48,"moving hull has two ribbons and bounded droplets only where bow intersects sea")
	check(absf(float(diag.flow_distance)-6.0*.514444*.4)<.00001,"texture travel integrates actual speed in metres")
	var droplet_bounds:=true
	for drop:Dictionary in effect._droplets:
		if not drop.get("active",false):continue
		droplet_bounds=droplet_bounds and float(drop.radius)>=.035 and float(drop.radius)<=.10 and float(drop.life)>=.3 and float(drop.life)<=.65
		var birth:Vector3=drop.birth_position
		droplet_bounds=droplet_bounds and birth.y>=_water(birth.x,birth.z,0.0) and birth.y<=_water(birth.x,birth.z,0.0)+.20
		var local:Vector3=packet.surfaceProfile.worldToHull*birth
		var bow_local:Vector3=packet.surfaceProfile.worldToHull*(Vector3(float(packet.sourceBowPosition[0]),float(packet.sourceBowPosition[2]),-float(packet.sourceBowPosition[1]))*float(packet.sourceToWorld))
		var sections:Array=packet.surfaceProfile.sections
		var first:=float(sections[0].z);var last:=float(sections[-1].z)
		var tip:=first if absf(bow_local.z-first)<=absf(bow_local.z-last) else last
		var direction:=-1.0 if tip==first else 1.0
		var actual_distance:float=direction*(tip-local.z)*packet.surfaceProfile.hullToWorld.basis.z.length()
		droplet_bounds=droplet_bounds and actual_distance>=.3-.00002 and actual_distance<=1.3+.00002 and local.is_finite()
	check(droplet_bounds,"births are small finite waterline droplets behind bow, below deck")
	var prior:=_snapshot(effect)
	effect.apply_snapshot(packet,.4,_water,Callable())
	effect.redraw_camera({"right":[0.0,1.0,0.0],"up":[0.0,0.0,1.0],"direction":[-1.0,0.0,0.0]})
	check(prior==_snapshot(effect),"duplicate accepted time and camera redraw never advance simulation or births")
	var paused:float=effect.diagnostics().flow_distance
	var stopped:Dictionary=packet.duplicate(true);stopped.enabled=false;stopped.targetSpeed=0.0
	effect.apply_snapshot(stopped,.425,_water,Callable())
	check(effect.diagnostics().strength>0.0 and effect.diagnostics().strength<1.0,"stop smoothly fades attached ribbons")
	var births:int=effect.diagnostics().target_births
	for index in range(18,61):effect.apply_snapshot(stopped,float(index)*.025,_water,Callable())
	check(effect.diagnostics().target_births==births and effect.diagnostics().target_droplets==0,"stop disables new births while existing droplets age/land/recycle")
	check(effect.diagnostics().strength<.01 and effect.diagnostics().flow_distance==paused,"stopped ribbons fade within bounded time without flowing")
	water_calls=0;effect.apply_snapshot(stopped,2.5,_water,Callable())
	check(water_calls==0,"fully faded stopped contact effect performs no hidden sea sampling")
	effect.apply_snapshot(packet,.1,_water,Callable())
	check(effect.diagnostics().target_droplets==0 and effect.diagnostics().flow_distance==0.0,"rewind clears world droplets and accumulated flow")
	effect.apply_snapshot(packet,.125,_water,Callable())
	var leap:Dictionary=packet.duplicate(true)
	leap.surfaceProfile.hullToWorld.origin+=Vector3(100.0,0.0,0.0);leap.surfaceProfile.worldToHull=leap.surfaceProfile.hullToWorld.affine_inverse()
	leap.sourceBowPosition[0]+=100.0/float(packet.sourceToWorld)
	effect.apply_snapshot(leap,.15,_water,Callable())
	check(effect.diagnostics().target_droplets==0 and effect.diagnostics().flow_distance==0.0,"teleport clears old world-space droplets rather than drawing a bridge")
	effect.apply_snapshot(leap,1000.0,_water,Callable())
	check(effect.diagnostics().target_droplets<=48 and effect.diagnostics().flow_distance<=6.0*.514444*.25+.00001,"large elapsed time bounds integration and avoids a birth storm")
	observations.append({"kind":kind,"beam":packet.surfaceProfile.beam,"movingDroplets":diag.target_droplets,"birthsAtStop":births,"peakWaterSamples":peak_samples,"peakCrestMetres":peak_crest})
	effect.dispose();check(owner.get_child_count()==0,"dispose frees all contact render nodes")
	owner.free();actor.dispose();actor.free()

func _fallback(module:Script)->void:
	var actor:=Ship.new();root.add_child(actor);check(actor.configure("fuchuan"),"legacy profile compatibility uses real fuchuan")
	var packet:=_packet(actor,"fuchuan",6.0*.514444);packet.surfaceProfile.erase("verticalSections")
	var owner:=Node3D.new();root.add_child(owner)
	var effect:RefCounted=module.new();check(effect.configure(owner,int(packet.family),7).ok,"legacy optional-ring fallback configures")
	water_calls=0;effect.apply_snapshot(packet,0.0,_water,Callable())
	check(water_calls<=1000,"legacy fallback also fits sampling budget")
	_shape(effect,owner,packet,false)
	effect.dispose();owner.free();actor.dispose();actor.free()

func _ghost(module:Script)->void:
	var actor:=Ship.new();root.add_child(actor);check(actor.configure("fuchuan"),"out-of-water fixture uses actual fuchuan hull")
	var state:=_state("fuchuan",6.0*.514444);state.visual.position={"x":0.0,"y":2.0,"z":0.0};state.visual.heading=0.0;state.visual.heel=.16;state.visual.velocity={"x":6.0*.514444,"z":0.0}
	actor.apply_snapshot(state,{},0.0)
	var source:Dictionary=Packet.compose({"time":0.0,"environment":{"route":"sailing","acceptedTime":0.0,"sourceCallIndex":0},"ships":[state]},{"contact":actor},null).ships[0].sourceWake
	var packet:Dictionary=source.duplicate(true);packet.merge(source.froth,true)
	var owner:=Node3D.new();owner.position=Vector3(30,4,-12);root.add_child(owner)
	var effect:RefCounted=module.new();check(effect.configure(owner,int(packet.family),29).ok,"out-of-water effect configures")
	for i in range(0,17):effect.apply_snapshot(packet,float(i)*.025,_flat,Callable())
	check(effect.diagnostics().target_births==0 and effect.diagnostics().target_droplets==0,"bow lifted2m out of water produces no ghost spray")
	var ghost:=false
	for name:String in ["FlowPort","FlowStarboard"]:
		var node:=_node(owner,name)
		check(node.global_transform==Transform3D.IDENTITY,"world vertex renderer is identity even under initially transformed parent")
		if not node.visible:continue
		var arrays:Array=node.mesh.surface_get_arrays(0);var uv:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
		for index:int in arrays[Mesh.ARRAY_INDEX]:
			if uv[index].x<1.3:ghost=true
	check(not ghost,"source rings without bow-water intersection do not clamp phantom ribbon rows")
	state.visual.position.y=0.0;state.visual.pitch=0.0;state.visual.heel=0.0;actor.apply_snapshot(state,{},0.0)
	source=Packet.compose({"time":0.0,"environment":{"route":"sailing","acceptedTime":0.0,"sourceCallIndex":0},"ships":[state]},{"contact":actor},null).ships[0].sourceWake
	packet=source.duplicate(true);packet.merge(source.froth,true)
	for i in range(17,33):effect.apply_snapshot(packet,float(i)*.025,_flat,Callable())
	check(effect.diagnostics().target_births>0 and effect.diagnostics().target_droplets>0 and effect.diagnostics().target_ribbons==2,"real contact restores ribbons and new spray after hull returns to sea")
	effect.dispose();owner.free();actor.dispose();actor.free()

func _velocity_contract(module:Script)->void:
	var actor:=Ship.new();root.add_child(actor);check(actor.configure("fuchuan"),"velocity contract uses actual fuchuan")
	var packet:=_packet(actor,"fuchuan",6.0*.514444)
	var speed:=6.0*.514444;var forward:=Vector3(cos(.3),0.0,sin(.3))
	var owner:=Node3D.new();root.add_child(owner)
	for motion:Vector3 in [-forward*speed,Vector3(-forward.z,0.0,forward.x)*speed]:
		var drift:Dictionary=packet.duplicate(true);drift.targetVelocity=[motion.x,0.0,motion.z]
		var inactive:RefCounted=module.new();check(inactive.configure(owner,int(packet.family),31).ok,"reverse/side drift fixture configures")
		inactive.apply_snapshot(drift,0.0,_water,Callable());inactive.apply_snapshot(drift,.25,_water,Callable())
		check(inactive.diagnostics().target_births==0 and inactive.diagnostics().target_ribbons==0 and inactive.diagnostics().flow_distance==0.0,"reverse/side drift does not create forward breaking-water flow")
		inactive.dispose()
	var effect:RefCounted=module.new();var replay:RefCounted=module.new()
	check(effect.configure(owner,int(packet.family),37).ok and replay.configure(owner,int(packet.family),37).ok,"seeded world-spray fixtures configure")
	for i in range(0,17):
		var time:=float(i)*.025
		effect.apply_snapshot(packet,time,_water,Callable());replay.apply_snapshot(packet,time,_water,Callable())
	check(_snapshot(effect)==_snapshot(replay),"same fixed seed and accepted input produce identical whole world-droplet state")
	var inherited:=true;var live:=0
	for drop:Dictionary in effect._droplets:
		if not drop.active:continue
		live+=1
		var along:float=drop.velocity.dot(forward)
		inherited=inherited and along>=speed*.75-.82 and along<=speed*.75-.33
	check(live>0 and inherited,"newborn world droplets inherit75percent ship speed plus bounded aft drift")
	var changed:Dictionary=packet.duplicate(true);changed.epoch=str(packet.get("epoch",""))+":changed"
	effect.apply_snapshot(changed,.425,_water,Callable())
	check(effect.diagnostics().target_droplets==0 and effect.diagnostics().flow_distance==0.0,"epoch transition clears old droplets and flow without advancing an old timeline")
	changed.epoch=42;effect.apply_snapshot(changed,.45,_water,Callable())
	check(effect.diagnostics().target_droplets==0 and effect.diagnostics().flow_distance==0.0,"mixed timeline ID types reset without an invalid GDScript comparison")
	effect.dispose();replay.dispose();owner.free();actor.dispose();actor.free()

func _heave(module:Script)->void:
	var actor:=Ship.new();root.add_child(actor);check(actor.configure("fuchuan"),"heave uses real fuchuan")
	var state:=_state("fuchuan",6.0*.514444);state.visual.heel=.16;actor.apply_snapshot(state,{},0.0)
	var source:Dictionary=Packet.compose({"time":0.0,"environment":{"route":"sailing","acceptedTime":0.0,"sourceCallIndex":0},"ships":[state]},{"contact":actor},null).ships[0].sourceWake
	var packet:Dictionary=source.duplicate(true);packet.merge(source.froth,true);packet.targetSpeed=6.0*.514444
	var owner:=Node3D.new();root.add_child(owner)
	var effect:RefCounted=module.new();check(effect.configure(owner,int(packet.family),19).ok,"heave effect configures")
	for i in range(0,13):effect.apply_snapshot(packet,float(i)*.025,_water,Callable())
	check(effect.diagnostics().target_droplets>0,"heave fixture includes surviving real droplets")
	var before:=_snapshot(effect)
	var accepted:float=effect.diagnostics().visual_time
	for heave:float in [-.5,.5]:
		var moved:Dictionary=packet.duplicate(true)
		moved.surfaceProfile.hullToWorld.origin.y+=heave
		moved.surfaceProfile.worldToHull=moved.surfaceProfile.hullToWorld.affine_inverse()
		moved.sourceBowPosition[2]+=heave/float(packet.sourceToWorld)
		effect.apply_snapshot(moved,accepted,_water,Callable())
		check(_snapshot(effect)==before,"heave changes attachment geometry without translating surviving world-space droplets")
		var bounded:=true
		for name:String in ["FlowPort","FlowStarboard"]:
			var node:=_node(owner,name)
			for vertex:Vector3 in node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				var relief:=vertex.y-_water(vertex.x,vertex.z,.3)-.045
				bounded=bounded and vertex.is_finite() and relief>=-.00002 and relief<.22
		check(bounded,"pitch/heel with heave +/-.5 keeps contact geometry on sampled sea")
	# Parent movement must not drag emitted world-space particles up/down.
	var spray:=_node(owner,"ContactSpray")
	var prior_transform:Transform3D=spray.global_transform
	owner.position.y+=3.0
	check(spray.global_transform==prior_transform,"world-space contact container ignores attached-parent vertical translation")
	effect.dispose();owner.free();actor.dispose();actor.free()

func _run()->void:
	if not check(FileAccess.file_exists(PATH),"dedicated hull contact module exists"):
		print("HULL_CONTACT_FROTH_TESTS assertions=",assertions," failures=",failures);quit(1);return
	var module:Script=load(PATH)
	if not check(module!=null,"contact module loads"):
		print("HULL_CONTACT_FROTH_TESTS assertions=",assertions," failures=",failures);quit(1);return
	for kind:String in Ship.KINDS:_case(module,kind)
	_heave(module)
	_ghost(module)
	_fallback(module)
	_velocity_contract(module)
	print("HULL_CONTACT_FROTH_EVIDENCE ",JSON.stringify(observations))
	print("HULL_CONTACT_FROTH_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
