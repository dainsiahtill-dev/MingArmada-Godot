extends SceneTree
## Frozen-compiler byte oracle and countable actual-render work, then alternating CPU A/B.
const Native=preload("res://modules/scene_engine/fidelity_fx/cloud_native.gd")
const PATH="res://modules/scene_engine/fidelity_fx/cloud_render_compiler.gd"
const FROZEN="res://docs/research/evidence/architecture-convergence-2026-10-21/baseline/source/modules/scene_engine/fidelity_fx/cloud_render_compiler.gd.txt"
var assertions:=0
var failures:Array=[]
var output:=""
func check(ok:bool,message:String)->void:
	assertions+=1
	if not ok:failures.append(message);printerr("FAIL cloud curve precompile: ",message)
func _initialize()->void:run.call_deferred()
func json(path:String)->Dictionary:return JSON.parse_string(FileAccess.get_file_as_string(path))
func digest(value:Variant)->String:return var_to_bytes(value).hex_encode().sha256_text()
func observed(path:String)->RefCounted:
	var source:=FileAccess.get_file_as_string(path)
	source=source.replace("func _sample(group:Dictionary,time:float)->Variant:","func _sample(group:Dictionary,time:float)->Variant:\n\tprobe_samples+=1")
	var script:=GDScript.new();script.source_code=source+"\nvar probe_samples:=0\n"
	check(script.reload()==OK,"observed compiler compiles: "+path)
	return script.new()
func stats(values:Array)->Dictionary:
	var sorted:=values.duplicate();sorted.sort();var total:=0.0
	for value:float in values:total+=value
	return {"count":values.size(),"mean":total/values.size(),"p50":sorted[int(ceil(values.size()*.5))-1],"p95":sorted[int(ceil(values.size()*.95))-1],"minimum":sorted[0],"maximum":sorted[-1]}
func frames(compiler:RefCounted,graphs:Array,time:float,camera:Dictionary)->Array:
	var result:Array=[]
	for i in graphs.size():result.append(compiler.render_states(graphs[i],time+(Native.f32(i*33.333335876464844*Native.FOG_PHASE_SCALE) if i<6 else 0.0),{},true,{} if i<6 else camera,false,false,true))
	return result
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	if output.is_empty() or FileAccess.file_exists(output):printerr("fresh explicit output required");quit(1);return
	var baseline:=observed(FROZEN);var candidate:=observed(PATH)
	var assets:Dictionary={};var asset_hashes:Dictionary={}
	for entry:Dictionary in json("res://assets/data/fidelity_fx/manifest.json").atmosphere.assets:assets[entry.file]=json(entry.data_path)
	var weather:=json("res://assets/data/fidelity_fx/weather/manifest.json")
	for entry:Dictionary in weather.assets:
		var asset:=json(entry.data_path)
		if entry.file=="stormcloud_sound.nif":asset=baseline.bind_sequence(asset,json(weather.stormSequence))
		assets[entry.file]=asset
	for name:String in assets:asset_hashes[name]=digest(assets[name])
	var cameras:Array=[{}, {"direction":[0.0,-1.0,0.0],"up":[0.0,0.0,1.0],"right":[1.0,0.0,0.0]}, {"direction":[.36085122,-.43081242,.82719978],"up":[.17228565,.90244198,.3949131],"right":[-.91659197,0.0,.39982493]}]
	var outer:Dictionary={"rotation":Native.multiply_matrix(Native.rotation_x(.17),Native.rotation_z(.55)),"translation":[.1,.2,.3],"scale":1.15}
	var proofs:Array=[]
	for name:String in assets:
		var old:Dictionary=baseline.compile_asset(assets[name]);var current:Dictionary=candidate.compile_asset(assets[name])
		var held:Array=[];var held_bytes:=PackedByteArray()
		for persistent:bool in [false,true]:
			for time:float in [0.0,.1,.1,12.0,19.200000762939453,33.333335876464844,33.5,66.8,.1,0.0,-.2]:
				for camera:Dictionary in cameras:
					for mode:int in 3:
						var expected:Array=baseline.render_states(old,time,outer,true,camera,mode==1,mode==2,persistent)
						var actual:Array=candidate.render_states(current,time,outer,true,camera,mode==1,mode==2,persistent)
						check(var_to_bytes(actual)==var_to_bytes(expected),"complete frozen dictionary bytes "+name+" "+str([persistent,time,mode,camera]))
						check(var_to_bytes(candidate.controller_snapshot(current))==var_to_bytes(baseline.controller_snapshot(old)),"mutable clock snapshots "+name)
						proofs.append({"asset":name,"persistent":persistent,"time":time,"mode":mode,"camera":camera,"baseline":digest(expected),"candidate":digest(actual)})
						if held.is_empty():held=actual;held_bytes=var_to_bytes(held)
		check(var_to_bytes(held)==held_bytes,"later sampling cannot mutate prior published state "+name)
		check(digest(assets[name])==asset_hashes[name],"compile/sample cannot mutate source asset "+name)
	var old_graphs:Array=[];var new_graphs:Array=[]
	for name:String in ["fx_groundfog01.nif","fx_groundfog01.nif","fx_groundfog01.nif","fx_groundfog01.nif","fx_groundfog01.nif","fx_groundfog01.nif","stormcloud_sound.nif","cloud00.nif","cloud00.nif"]:
		old_graphs.append(baseline.compile_asset(assets[name]));new_graphs.append(candidate.compile_asset(assets[name]))
	var rows:Array=[];var old_cost:Array=[];var new_cost:Array=[];var old_calls:=0;var new_calls:=0
	for tick in 40:
		baseline.probe_samples=0;candidate.probe_samples=0
		var time:float=(tick+1)/60.0;var expected:Array;var actual:Array;var old_us:=0;var new_us:=0
		var camera:Dictionary=cameras[2]
		if tick%2==0:
			var start:=Time.get_ticks_usec();expected=frames(baseline,old_graphs,time,camera);old_us=Time.get_ticks_usec()-start
			start=Time.get_ticks_usec();actual=frames(candidate,new_graphs,time,camera);new_us=Time.get_ticks_usec()-start
		else:
			var start:=Time.get_ticks_usec();actual=frames(candidate,new_graphs,time,camera);new_us=Time.get_ticks_usec()-start
			start=Time.get_ticks_usec();expected=frames(baseline,old_graphs,time,camera);old_us=Time.get_ticks_usec()-start
		check(var_to_bytes(actual)==var_to_bytes(expected),"alternating 9-instance complete states tick "+str(tick))
		old_calls=int(baseline.probe_samples);new_calls=int(candidate.probe_samples)
		if tick>=8:
			old_cost.append(old_us/1000.0);new_cost.append(new_us/1000.0)
			rows.append({"tick":tick,"baselineUsec":old_us,"candidateUsec":new_us,"baselineParsedSamples":old_calls,"candidateParsedSamples":new_calls,"baseline":digest(expected),"candidate":digest(actual)})
	check(old_calls==438,"representative actual 6-fog/3-weather batch exercises all 438 curve samples")
	check(new_calls==0,"compiled actual render path avoids repeated source key-dictionary sampling")
	var proof:Dictionary={"scope":"Headless exact frozen-compiler full-state/clock oracle and isolated alternating CPU microbenchmark; no GPU or world FPS claim. 8 actual atmosphere/weather assets with KF storm sequence; immutable private compiled curve inputs.","engine":Engine.get_version_info(),"baselineSourceSHA256":FileAccess.get_file_as_string(FROZEN).sha256_text(),"candidateSourceSHA256":FileAccess.get_file_as_string(PATH).sha256_text(),"helperSourceSHA256":FileAccess.get_file_as_string("res://modules/scene_engine/fidelity_fx/cloud_curve_sampler.gd").sha256_text(),"assetHashes":asset_hashes,"assertions":assertions,"failures":failures,"baselineMs":stats(old_cost),"candidateMs":stats(new_cost),"work":{"baselineParsedSamples":old_calls,"candidateParsedSamples":new_calls},"frames":proofs,"rows":rows}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(proof,"\t"));file.close()
	print("CLOUD_CURVE_PRECOMPILE_TESTS ",JSON.stringify({"assertions":assertions,"failures":failures,"baselineMs":proof.baselineMs,"candidateMs":proof.candidateMs,"work":proof.work,"output":output}))
	quit(0 if failures.is_empty() else 1)
