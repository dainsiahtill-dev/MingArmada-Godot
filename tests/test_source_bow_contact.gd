extends SceneTree
## Actual fuchuan model/markers -> production water packet -> source bow mesh.
## Target contact dimensions are presentation policy, not native owner scale.
const Ship=preload("res://game/presentation/ships/ship_view.gd")
const Packet=preload("res://game/presentation/world/source_water_packet.gd")
const Froth=preload("res://modules/scene_engine/water/source_froth.gd")
var assertions:=0
var failures:=0
var observations:Array=[]

func _initialize()->void:_run.call_deferred()
func check(ok:bool,message:String)->bool:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL: ",message)
	return ok
func _water(_x:float,_z:float,_time:float)->float:return 0.0
func _state(speed:float)->Dictionary:
	return {"id":"bow_contact","kind":"fuchuan","time":1.0,"hull":100.0,"sailDeployment":1.0,"visual":{"position":{"x":0.0,"y":0.0,"z":0.0},"velocity":{"x":speed,"z":0.0},"heading":0.0,"pitch":0.0,"heel":0.0}}
func _edges(sections:Array,z:float)->Vector2:
	if z<=float(sections[0].z):return Vector2(float(sections[0].left),float(sections[0].right))
	for i in range(1,sections.size()):
		if z<=float(sections[i].z):
			var a:Dictionary=sections[i-1];var b:Dictionary=sections[i]
			var weight:float=(z-float(a.z))/(float(b.z)-float(a.z))
			return Vector2(lerpf(float(a.left),float(b.left),weight),lerpf(float(a.right),float(b.right),weight))
	return Vector2(float(sections[-1].left),float(sections[-1].right))

func _case(speed:float,kind:String="fuchuan")->Dictionary:
	var actor:=Ship.new();root.add_child(actor)
	if not check(actor.configure(kind),"actual "+kind+" configures"):actor.free();return {}
	var state:=_state(speed);state.kind=kind;actor.apply_snapshot(state,{},0.0)
	var attachment:Dictionary=actor.source_water_attachment()
	var composed:Dictionary=Packet.compose({"time":state.time,"environment":{"route":"sailing","acceptedTime":state.time,"sourceCallIndex":32},"ships":[state]},{"bow_contact":actor},null)
	var packet:Dictionary=composed.ships[0].sourceWake
	var local_packet:Dictionary=packet.duplicate(true);local_packet.merge(packet.froth,true)
	var profile:Dictionary=packet.froth.get("surfaceProfile",{})
	if not check(not profile.is_empty(),"production packet includes real waterline profile"):actor.dispose();actor.free();return {}
	var strength:=smoothstep(.35,6.0*.514444,speed)
	var width:=float(profile.targetOuterWidth)
	var expected_run:=clampf(float(profile.beam)*.5,1.25,3.0)
	var expected_crest:=lerpf(.04,minf(width*.42,.35),strength)
	var expected_intensity:=.65*strength if bool(packet.froth.enabled) else 0.0
	check(absf(float(profile.get("targetBowRun",0.0))-expected_run)<.00001,"production targetBowRun follows actual beam at speed "+str(speed))
	check(absf(float(profile.get("targetBowCrest",0.0))-expected_crest)<.00001,"production targetBowCrest follows same source speed strength")
	check(absf(float(profile.get("bowIntensity",-1.0))-expected_intensity)<.00001,"production bowIntensity follows same source speed strength and stop gate")
	check(not local_packet.has("bowScale") and Froth.outer(local_packet,true).scale==attachment.modelScale,"target contact adaptation never changes native bow owner scale")
	check(local_packet.sourceBowPosition==Packet.native_vector(attachment.bow/attachment.sourceToWorld),"native Dummy_bowfroth position remains original raw marker")
	var owner:=Node3D.new();root.add_child(owner)
	var effect:=Froth.new()
	check(effect.configure(owner,int(packet.froth.family),int(packet.froth.seed),str(packet.froth.sourceResourceName)).ok,"actual source bow and side resources configure")
	effect.apply_snapshot(local_packet,float(state.time),_water,Callable())
	var result:={"kind":kind,"speed":speed,"strength":strength,"beam":profile.beam,"outerWidth":width,"expectedRun":expected_run,"expectedCrest":expected_crest,"expectedIntensity":expected_intensity}
	if speed<=.35:
		check(not bool(packet.froth.enabled) and effect.diagnostics().authored_meshes==0,"stationary ship keeps authored bow/side carrier and birth gate closed")
		check(effect._particles._native.time==float(state.time),"stationary native particle owner retains monotonic accepted time")
	else:
		var bow:MeshInstance3D=effect._surface.nodes.get("bow_82")
		if check(bow!=null,"actual Box03 bow_82 is submitted"):
			var arrays:Array=bow.mesh.surface_get_arrays(0)
			var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var colors:PackedColorArray=arrays[Mesh.ARRAY_COLOR]
			check(vertices.size()==30 and arrays[Mesh.ARRAY_INDEX].size()==120,"target bow keeps original30 vertices and40 triangles")
			var sections:Array=profile.sections
			var world_to_hull:Transform3D=profile.worldToHull
			var marker_local:Vector3=world_to_hull*attachment.bow
			var first_z:=float(sections[0].z);var last_z:=float(sections[-1].z)
			var near_first:=absf(marker_local.z-first_z)<=absf(marker_local.z-last_z)
			var tip_z:=first_z if near_first else last_z
			var forward:=-1.0 if near_first else 1.0
			var opaque_count:=0;var rim_count:=0;var maximum_relief:=-INF
			var minimum_ahead:=INF;var maximum_ahead:=-INF;var maximum_lateral_violation:=-INF
			for i in vertices.size():
				maximum_relief=maxf(maximum_relief,vertices[i].y-.10)
				if colors[i].a==0.0:rim_count+=1
				if colors[i].a<.99:continue
				opaque_count+=1
				var local:Vector3=world_to_hull*vertices[i]
				var ahead:=forward*(local.z-tip_z)
				var edges:=_edges(sections,local.z)
				minimum_ahead=minf(minimum_ahead,ahead);maximum_ahead=maxf(maximum_ahead,ahead)
				maximum_lateral_violation=maxf(maximum_lateral_violation,maxf(edges.x-width-.05-local.x,local.x-edges.y-width-.05))
				check(ahead>=-expected_run-.00002 and ahead<=.65*width+.00002,"alpha1 bow core stays around true endpoint within aftRun/forward bound vertex "+str(i))
				check(local.x>=edges.x-width-.05-.00002 and local.x<=edges.y+width+.05+.00002,"alpha1 bow core respects local hull edge and external width vertex "+str(i))
			check(opaque_count==12 and rim_count==18,"source bright core and transparent rim RGBA are retained")
			check(is_finite(maximum_relief) and maximum_relief<=expected_crest+.01,"bow3D relief is bounded by target speed-dependent crest")
			if speed>=6.0*.514444:check(maximum_relief>.08,"6kn bow retains visibly three-dimensional crest")
			var bow_role:=false
			for key:String in effect._surface._materials:
				if key.ends_with(":bow") and effect._surface._materials[key]==bow.material_override:bow_role=true
			check(bow_role,"bow is submitted with independent target_froth_role=bow material")
			var tint:Variant=bow.material_override.get_shader_parameter("display_tint")
			check(tint is Color and absf(tint.a-expected_intensity)<.00001,"bow material display tint alpha equals bowIntensity")
			result.merge({"markerLocalZ":marker_local.z,"tipZ":tip_z,"forwardSign":forward,"opaqueVertices":opaque_count,"transparentRimVertices":rim_count,"coreAheadMin":minimum_ahead,"coreAheadMax":maximum_ahead,"maximumLateralViolation":maximum_lateral_violation,"maximumRelief":maximum_relief})
		for key:String in effect._surface.nodes:
			if not key.begins_with("side_"):continue
			var side:MeshInstance3D=effect._surface.nodes[key]
			var planar:=true
			for vertex:Vector3 in side.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:planar=planar and absf(vertex.y-.10)<.00002
			check(planar,"side foam remains independent planar water fit")
	observations.append(result)
	effect.dispose();owner.free();actor.dispose();actor.free();return result

func _run()->void:
	var original:=FileAccess.get_file_as_bytes("res://assets/data/source_wake/fx_ship_bowfroth.nif.json")
	var high:=_case(6.0*.514444)
	var low:=_case(.7)
	_case(0.0)
	for kind:String in ["fisherman","merchant","voc","patrol","heavy"]:_case(6.0*.514444,kind)
	if high.has("maximumRelief") and low.has("maximumRelief"):
		check(float(low.maximumRelief)<float(high.maximumRelief),"low speed reduces rendered bow crest rather than just multiplying alpha")
	check(FileAccess.get_file_as_bytes("res://assets/data/source_wake/fx_ship_bowfroth.nif.json")==original,"target fit leaves original source asset bytes intact")
	print("SOURCE_BOW_CONTACT_EVIDENCE ",JSON.stringify(observations))
	print("SOURCE_BOW_CONTACT_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
