extends SceneTree
## Actual authored UV playback; source clips remain unchanged and particle
## replay is independently compared at the same monotonic accepted appTime.
const Froth=preload("res://modules/scene_engine/water/source_froth.gd")
const Runtime=preload("res://modules/scene_engine/fidelity_fx/particle_runtime.gd")
const TIMES:=[0.0,0.01,24.99,25.01,26.0,40.0,60.0]
var assertions:=0
var failures:=0
func check(ok:bool,message:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL: ",message)
func _initialize()->void:_run.call_deferred()
func _water(_x:float,_z:float,_time:float)->float:return 0.0
func _packet(time:float,enabled:bool=true)->Dictionary:
	return {"sourcePosition":[0.0,0.0,0.0],"sourceBowPosition":[0.0,0.0,0.0],"sourceHeading":0.0,"modelScale":1.0,"sourceToWorld":0.021353528480495498,"controllerAppTime":time,"enabled":enabled}
func _uvs(froth:RefCounted,prefix:String)->PackedVector2Array:
	for key:String in froth._surface.nodes:
		if key.begins_with(prefix):return froth._surface.nodes[key].mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV].duplicate()
	return PackedVector2Array()
func _repeat_delta(a:float,b:float)->float:return fposmod(a-b+0.5,1.0)-0.5
func _particle_state(froth:RefCounted)->PackedByteArray:return var_to_bytes(froth._particles._native.source_state())
func _source_clips_unchanged(asset:Dictionary)->void:
	for block:Dictionary in asset.blocks:
		check(str(block.type) not in ["NiAlphaController","NiKeyframeController"],"UV phase never drives source alpha/TRS controllers")
		if str(block.type)=="NiTextureTransformController":check(int(block.fields.flags)==44,"original CLAMP controller flags unchanged")
func _run()->void:
	var parent:=Node3D.new();root.add_child(parent)
	_source_clips_unchanged(Froth.asset("fx_ship_bowfroth.nif"))
	for family in Froth.FAMILIES.size():
		var source:Dictionary=Froth.asset("fx_ship_sidefroth_"+Froth.FAMILIES[family]+".nif")
		var original:=var_to_bytes(source)
		_source_clips_unchanged(source)
		var froth:=Froth.new();check(froth.configure(parent,family,17).ok,"configure real authored family "+str(family))
		var oracle:=Runtime.new();check(oracle.configure(Froth.asset("fx_ship_bowfroth.nif"),17,false),"independent unchanged source particle owner")
		var replay:RefCounted=oracle.spawn_native(17)
		var samples:Dictionary={}
		for time:float in TIMES:
			var packet:=_packet(time)
			froth.apply_snapshot(packet,time,_water,Callable())
			replay.set_source_outer(Froth.outer(packet,true));replay.advance_native(time,false,true)
			check(_particle_state(froth)==var_to_bytes(replay._native.source_state()),"UV loop does not alter any native particle pool/RNG/controller/clock at "+str(time))
			samples[time]={"side":_uvs(froth,"side_"),"bow":_uvs(froth,"bow_")}
		for kind:String in ["side","bow"]:
			var initial:PackedVector2Array=samples[0.01][kind]
			var crossed:PackedVector2Array=samples[25.01][kind]
			check(initial.size()==crossed.size() and initial.size()>0,"real mesh persists across source clip endpoint")
			for i in mini(initial.size(),crossed.size()):
				check(absf(_repeat_delta(crossed[i].x,initial[i].x))<0.00002 and absf(_repeat_delta(crossed[i].y,initial[i].y))<0.00002,"25.01s equals 0.01s under actual repeat sampler "+kind+" vertex "+str(i))
			var before:PackedVector2Array=samples[24.99][kind]
			var after:PackedVector2Array=samples[25.01][kind]
			var expected_u:=-0.0032 if kind=="side" else 0.0
			var expected_v:=0.0016 if kind=="side" else -0.0048
			check(absf(_repeat_delta(after[0].x,before[0].x)-expected_u)<0.00002 and absf(_repeat_delta(after[0].y,before[0].y)-expected_v)<0.00002,"repeat seam retains source linear flow velocity, not an endpoint hold")
			check(samples[25.01][kind]!=samples[26.0][kind] and samples[26.0][kind]!=samples[40.0][kind] and samples[40.0][kind]!=samples[60.0][kind],"active authored flow continues past 25/26/40/60 seconds")
		var prior_particle:=_particle_state(froth)
		var prior_side:=_uvs(froth,"side_")
		froth.apply_snapshot(_packet(60.0),60.0,_water,Callable())
		check(prior_particle==_particle_state(froth) and prior_side==_uvs(froth,"side_"),"paused/repeated accepted time does not move texture or native particles")
		var births:int=froth.diagnostics().native_births
		var stopped:=_packet(61.0,false)
		froth.apply_snapshot(stopped,61.0,_water,Callable())
		replay.set_source_outer(Froth.outer(stopped,true));replay.advance_native(61.0,false,false)
		check(froth.diagnostics().authored_meshes==0 and froth.diagnostics().native_births==births,"stop retains previous authored visibility and birth gate")
		check(froth._particles._native.time==61.0 and _particle_state(froth)==var_to_bytes(replay._native.source_state()),"stop ages existing droplets on monotonic native time")
		froth.apply_snapshot(_packet(62.0),62.0,_water,Callable())
		replay.set_source_outer(Froth.outer(_packet(62.0),true));replay.advance_native(62.0,false,true)
		check(_particle_state(froth)==var_to_bytes(replay._native.source_state()) and _uvs(froth,"side_")!=prior_side,"resume keeps native clock monotonic and restores moving authored texture")
		check(var_to_bytes(Froth.asset("fx_ship_sidefroth_"+Froth.FAMILIES[family]+".nif"))==original,"original source data and keys unchanged")
		froth.dispose()
	# An instance created late in a voyage starts its target local UV lifecycle,
	# instead of immediately clamping all source texture channels at time25.
	var late:=Froth.new();late.configure(parent,3,17)
	late.apply_snapshot(_packet(100.0),100.0,_water,Callable())
	var at_birth:=_uvs(late,"side_")
	late.apply_snapshot(_packet(100.25),100.25,_water,Callable())
	check(at_birth!=_uvs(late,"side_"),"late created moving ship has local UV animation after absolute time100")
	late.dispose();parent.free()
	print("SOURCE_FROTH_ANIMATION_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
