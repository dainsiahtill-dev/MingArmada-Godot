extends SceneTree
## Independent CPU batch, not scene frame time or GPU performance.
const Baseline=preload("res://game/research/fixtures/cloud_billboard_baseline.gd")
const Candidate=preload("res://game/research/demos/architecture_billboard_candidate.gd")
const Native=preload("res://modules/scene_engine/fidelity_fx/cloud_native.gd")
const REPEATS:=24
const PAIRS:=12
var failures:Array[String]=[]
var output:=""

func _initialize()->void:run.call_deferred()
func check(ok:bool,reason:String)->bool:
	if not ok:failures.append(reason);printerr("FAIL billboard cost: ",reason)
	return ok
func stats(values:Array)->Dictionary:
	var sorted:=values.duplicate();sorted.sort()
	return {"count":values.size(),"mean":values.reduce(func(a,b):return a+b,0.0)/values.size(),"p50":sorted[ceili(.5*values.size())-1],"p95":sorted[ceili(.95*values.size())-1],"minimum":sorted[0],"maximum":sorted[-1]}
func batch(compiler:RefCounted,graphs:Dictionary,cases:Array)->Dictionary:
	var checksum:=0.0
	var start:=Time.get_ticks_usec()
	for repeat in REPEATS:
		for input:Dictionary in cases:
			var states:Array=compiler.render_minimum_states(graphs[input.prototype],input.outer,input.camera)
			if not states.is_empty():checksum+=float(states[0].minimumZ)
	return {"milliseconds":float(Time.get_ticks_usec()-start)/1000.0,"checksum":checksum}
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	if not check(not output.is_empty() and not FileAccess.file_exists(output),"fresh explicit output required"):quit(1);return
	var baseline:=Baseline.new();var candidate:=Candidate.new()
	var files:Dictionary={}
	for path:String in ["res://tools/measure-cloud-billboard-reuse.gd","res://game/research/fixtures/cloud_billboard_baseline.gd","res://game/research/demos/architecture_billboard_candidate.gd","res://modules/scene_engine/fidelity_fx/cloud_render_compiler.gd"]:files[path]=FileAccess.get_sha256(path)
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/fidelity_fx/manifest.json"))
	var bg:Dictionary={};var cg:Dictionary={};var assets:Dictionary={}
	for entry:Dictionary in manifest.atmosphere.assets:
		if not String(entry.file).begins_with("domecloud"):continue
		files[entry.data_path]=FileAccess.get_sha256(entry.data_path)
		var asset:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(entry.data_path))
		assets[entry.file]=asset;bg[entry.file]=baseline.compile_asset(asset);cg[entry.file]=candidate.compile_asset(asset)
	# Encounter seed1661 is independent of WeatherState's default sky CRT1.
	var ring:Dictionary=Native.create_cloud_ring(1)
	var cameras:Array=[{"direction":[.36085122,-.43081242,.82719978],"up":[.17228565,.90244198,.3949131],"right":[-.91659197,0.0,.39982493]}, {"direction":[0,1,0],"up":[0,0,1],"right":[1,0,0]}]
	var cases:Array=[]
	for index in ring.nodes.size():
		var clone:Dictionary=ring.nodes[index]
		cases.append({"prototype":clone.prototype,"outer":{"rotation":clone.rotation,"translation":Native.transform_vector(clone.rotation,[0,1,0]),"scale":1.0},"camera":cameras[index%2]})
	check(cases.size()==30,"actual default sky CRT1 produces30 clones")
	var inputs_before:=var_to_bytes([assets,ring,cases])
	for input:Dictionary in cases:
		var a:Array=baseline.render_minimum_states(bg[input.prototype],input.outer,input.camera)
		var b:Array=candidate.render_minimum_states(cg[input.prototype],input.outer,input.camera)
		check(var_to_bytes(a)==var_to_bytes(b),"complete static input state exact: "+input.prototype)
	var rows:Array=[];var full:Array=[];var reused:Array=[];var faster:=0
	# Both orderings receive equal warmup; measured pairs alternate first path.
	for warmup in 2:
		if warmup%2==0:batch(baseline,bg,cases);batch(candidate,cg,cases)
		else:batch(candidate,cg,cases);batch(baseline,bg,cases)
	for pair in PAIRS:
		var a:Dictionary;var b:Dictionary
		if pair%2==0:a=batch(baseline,bg,cases);b=batch(candidate,cg,cases)
		else:b=batch(candidate,cg,cases);a=batch(baseline,bg,cases)
		check(a.checksum==b.checksum,"timed batches consume identical output checksum")
		rows.append({"pair":pair,"first":"baseline" if pair%2==0 else "candidate","baseline":a,"candidate":b})
		full.append(a.milliseconds);reused.append(b.milliseconds)
		if b.milliseconds<a.milliseconds:faster+=1
	check(var_to_bytes([assets,ring,cases])==inputs_before,"all input assets/ring/cameras remain unchanged")
	for path:String in files:check(FileAccess.get_sha256(path)==files[path],"run source unchanged: "+path)
	var bs:=stats(full);var cs:=stats(reused)
	var ratio:float=cs.mean/bs.mean
	# Prospective cost gate: >5% mean reduction and >=10/12 faster pairs.
	var accepted:bool=failures.is_empty() and ratio<=.95 and faster>=10
	var report:Dictionary={"topic":"architecture-convergence-2026-10-21","scope":"Independent headless CPU; 30 original skyCRT1 cloud clones matching ordinary encounter seed1661 default sky configuration, two fixed camera bases, each batch repeats24 times. Compilation, byte checks and file IO outside timed interval. Not a GPU/scene/full-game FPS measurement.","engine":Engine.get_version_info(),"display":DisplayServer.get_name(),"processorIdentifier":OS.get_environment("PROCESSOR_IDENTIFIER"),"controls":{"encounterSeed":1661,"skyCrtSeed":1,"clones":cases.size(),"repeatsPerBatch":REPEATS,"warmupPairs":2,"measuredPairs":PAIRS,"order":"alternating","units":"milliseconds per 24*30-clone batch","quantile":"nearest-rank ceil(q*n)-1","powerTemperatureBackground":"unknown"},"sourceFiles":files,"inputsSha256":inputs_before.hex_encode().sha256_text(),"rows":rows,"baselineMs":bs,"candidateMs":cs,"meanRatio":ratio,"fasterPairs":faster,"acceptance":{"meanRatioAtMost":.95,"fasterPairsAtLeast":10,"byteEqualityRequired":true,"passed":accepted},"failures":failures,"verdict":"cost-gate-passed; GPU/integration not yet verified" if accepted else "candidate rejected or invalid; no production integration"}
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("CLOUD_BILLBOARD_COST failures=",failures.size()," accepted=",accepted," baselineMs=",bs.mean," candidateMs=",cs.mean," ratio=",ratio," fasterPairs=",faster," output=",output)
	quit(1 if not failures.is_empty() else 0)
