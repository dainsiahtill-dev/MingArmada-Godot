extends SceneTree
## Real model -> cached waterline -> production packet, without GPU.
const Ship=preload("res://game/presentation/ships/ship_view.gd")
const Packet=preload("res://game/presentation/world/source_water_packet.gd")
var assertions:=0
var failures:=0
func _initialize()->void:_run.call_deferred()
func check(ok:bool,message:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL: ",message)
func _state(kind:String,time:float,speed:float)->Dictionary:
	return {"id":"audit","kind":kind,"time":time,"hull":100.0,"sailDeployment":1.0,"visual":{"position":{"x":20.0,"y":1.2,"z":10.0},"velocity":{"x":speed,"z":0.0},"heading":0.3,"pitch":0.12,"heel":0.08}}
func _compose(actor:Node3D,state:Dictionary,route:String="sailing")->Dictionary:
	return Packet.compose({"time":state.time,"environment":{"route":route,"acceptedTime":state.time,"sourceCallIndex":roundi(state.time*32.0)},"ships":[state]},{"audit":actor},null).ships[0].sourceWake
func _run()->void:
	var detached:=Ship.new()
	check(detached.configure("fuchuan"),"actor may configure before entering SceneTree")
	check(detached._waterline_profiles.size()==3 and detached._waterline_profiles[0].beam>4.9,"off-tree configuration builds actual local waterline")
	detached.dispose();detached.free()
	for kind:String in Ship.KINDS:
		var actor:=Ship.new();root.add_child(actor);check(actor.configure(kind),"actual ship configures "+kind)
		var state:=_state(kind,1.0,6.0*0.514444)
		actor.apply_snapshot(state,{},0.0)
		var attachment:Dictionary=actor.source_water_attachment()
		var profile:Dictionary=attachment.get("surfaceProfile",{})
		check(not profile.is_empty(),"actual hull-only waterline profile is configured "+kind)
		var packet:=_compose(actor,state)
		check(packet.froth.has("surfaceProfile"),"production froth packet carries profile "+kind)
		if profile.is_empty() or not packet.froth.has("surfaceProfile"):
			actor.dispose();actor.free();continue
		check(profile.sections.size()>=32,"waterline has enough longitudinal sections "+kind)
		var previous:=-INF;var maximum:=0.0
		for section:Dictionary in profile.sections:
			check(is_finite(section.z) and is_finite(section.left) and is_finite(section.right),"finite waterline section")
			check(section.z>previous and section.right>=section.left,"ordered consistent waterline section")
			previous=section.z;maximum=maxf(maximum,section.right-section.left)
		check(absf(profile.beam-maximum)<0.00001,"beam comes from actual waterline sections")
		if kind=="fuchuan":
			check(profile.beam>4.9 and profile.beam<5.2,"fuchuan waterline is about5m, excluding rigging/sails/deck bounds")
			check(packet.froth.surfaceProfile.targetOuterWidth>.72 and packet.froth.surfaceProfile.targetOuterWidth<.79,"fuchuan6kn has about.75m external band")
		check(absf(packet.froth.surfaceProfile.intensity-.65)<.00001,"6kn gives target intensity.65")
		check(profile.hullToWorld is Transform3D and profile.worldToHull is Transform3D,"internal profile uses exact Godot transforms")
		var test_point:=Vector3(1.0,0.0,2.0)
		check((profile.worldToHull*profile.hullToWorld*test_point).distance_to(test_point)<0.00001,"profile transforms invert actual model pose")
		check(profile.hullToWorld==actor.get_model().global_transform,"profile corresponds to displayed model full pose")
		check(packet.modelScale==attachment.modelScale,"source root modelScale remains unchanged")
		check(packet.sourcePosition==Packet.native_vector(attachment.trail/attachment.sourceToWorld),"scene30 retains planar original marker")
		check(packet.froth.sourcePosition==Packet.native_vector(attachment.wake/attachment.sourceToWorld),"local froth retains raw fullpose marker")
		check(packet.froth.sourceBowPosition==Packet.native_vector(attachment.bow/attachment.sourceToWorld),"bow original raw marker unchanged")
		check(packet.sourceRotation==Packet.native_rotation(attachment.rotation),"original source pose packet unchanged")
		var pose:=actor.global_transform
		var battle:=_compose(actor,state,"battle")
		check(battle.sourcePosition==Packet.native_vector(attachment.wake/attachment.sourceToWorld),"battle90 still uses raw marker")
		check(actor.global_transform==pose,"packet construction does not alter3D ship floating pose")
		var last_strength:=-1.0;var last_width:=-1.0
		for speed:float in [0.0,.35,.7,1.5,6.0*.514444,8.0]:
			var sample:=_state(kind,2.0,speed);actor.apply_snapshot(sample,{},0.0)
			var adapted:Dictionary=_compose(actor,sample).froth
			var fit:Dictionary=adapted.surfaceProfile
			check(fit.intensity>=last_strength and fit.targetOuterWidth>=last_width,"speed response is continuous monotonic")
			check(fit.intensity>=0.0 and fit.intensity<=.65 and fit.targetOuterWidth>=.35 and fit.targetOuterWidth<=.8,"bounded target dimensions and intensity")
			check(adapted.enabled==(speed>.35),"existing stop/birth gate preserved")
			last_strength=fit.intensity;last_width=fit.targetOuterWidth
		var stopped:Dictionary=_compose(actor,_state(kind,2.0,0.0)).froth
		check(stopped.surfaceProfile.intensity==0.0,"stationary hull has zero new local whitefroth strength")
		var future:=_state(kind,100.0,3.0);actor.apply_snapshot(future,{},0.0)
		var cached:Dictionary=actor.source_water_attachment().surfaceProfile
		check(is_same(profile.sections,cached.sections),"time/pose updates reuse configure-time waterline cache")
		var switched:=_state(kind,101.0,3.0)
		for lod in 3:
			actor.set_lod_distance([0.0,300.0,700.0][lod]);actor.apply_snapshot(switched,{},0.0)
			check(not actor.source_water_attachment().surfaceProfile.sections.is_empty(),"eachLOD has cached profile")
		actor.dispose();actor.free()
	print("HULL_WATERLINE_PROFILE_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
