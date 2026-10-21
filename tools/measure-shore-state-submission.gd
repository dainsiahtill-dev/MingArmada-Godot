extends SceneTree
## Frozen production shore algorithm with counted submission; headless CPU only.
const Height=preload("res://modules/scene_engine/terrain/height_field.gd")
const Geography=preload("res://game/scenes/common/reference_geography.gd")
const Catalog=preload("res://game/domain/legacy/catalog.gd")
const BASELINE="res://docs/research/evidence/architecture-convergence-2026-10-21/baseline/source/modules/scene_engine/terrain/natural_shore_surf.gd.txt"
var failures:Array[String]=[]
var output:=""
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);printerr("FAIL shore submission: ",label)
func stats(values:Array)->Dictionary:
	var sorted:=values.duplicate();sorted.sort();var total:=0.0
	for value:float in values:total+=value
	return {"n":values.size(),"mean":total/maxi(1,values.size()),"p50":sorted[ceili(sorted.size()*.5)-1],"p95":sorted[ceili(sorted.size()*.95)-1],"min":sorted[0],"max":sorted[-1]}
func instrument(path:String)->GDScript:
	var source:=FileAccess.get_file_as_string(path)
	source=source.replace('_materials[i].set_shader_parameter(', '_counted_set(_materials[i],')
	source+='\nvar counted_writes:=0\nvar submit_parameters:=true\nfunc _counted_set(material:ShaderMaterial,key:String,value:Variant)->void:\n\tcounted_writes+=1\n\tif submit_parameters:material.set_shader_parameter(key,value)\n'
	var script:=GDScript.new();script.source_code=source
	check(script.reload()==OK,"instrumented actual source compiles")
	return script
func setup(script:GDScript,grids:Array,submit:bool,table:bool=false)->Array:
	var result:Array=[]
	for entry:Dictionary in grids:
		if entry.get("shoal",false):continue
		var surf:Node3D=script.new();root.add_child(surf)
		check(surf.configure(entry.field,{"wave_span":clampf(float(entry.radius)*.08,6.0,14.0)}),"real shore configures")
		surf.set("submit_parameters",submit)
		if table:check(surf.has_method("set_state_batching") and surf.call("set_state_batching",true).ok,"candidate table backend activates")
		result.append(surf)
	return result
func advance(group:Array,time:float)->Dictionary:
	var start:=Time.get_ticks_usec();var writes:=0
	for surf:Node3D in group:
		surf.set("counted_writes",0);surf.apply_snapshot({"time":time},0.0);writes+=int(surf.get("counted_writes"))
	return {"usec":Time.get_ticks_usec()-start,"writes":writes}
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	if output.is_empty() or FileAccess.file_exists(output):check(false,"fresh explicit output path required");finish();return
	var heights:=Height.new();check(heights.configure_ports(Catalog.DATA.PORTS,false,Geography.options()),"formal terrain configures")
	var grids:Array=heights.natural_terrain_grids()
	var baseline:=instrument(BASELINE)
	var full:=setup(baseline,grids,true);var compute:=setup(baseline,grids,false)
	var candidate:Array=[]
	if "--candidate" in OS.get_cmdline_user_args():candidate=setup(instrument("res://modules/scene_engine/terrain/natural_shore_surf.gd"),grids,true,true)
	var patches:=0;var initial_hash:=HashingContext.new();initial_hash.start(HashingContext.HASH_SHA256)
	for surf:Node3D in full:
		patches+=surf.get("_packets").size();initial_hash.update(var_to_bytes(surf.get("_packets")))
		for child:MeshInstance3D in surf.get_children():initial_hash.update(var_to_bytes(child.mesh.surface_get_arrays(0)))
	var rows:Array=[];var totals:={"full":[],"computeOnly":[],"candidate":[]}
	for tick in 40:
		var seconds:=float(tick+1)/60.0;var row:={"time":seconds}
		var names:=["full","computeOnly","candidate"] if tick%2==0 else ["candidate","computeOnly","full"]
		for key:String in names:
			var group:Array=full if key=="full" else compute if key=="computeOnly" else candidate
			if group.is_empty():continue
			row[key]=advance(group,seconds)
			if tick>=8:totals[key].append(row[key].usec)
		for i in full.size():
			check(full[i].get("_states")==compute[i].get("_states"),"omitting submit changes no native states")
			if not candidate.is_empty():check(full[i].get("_states")==candidate[i].get("_states"),"candidate changes no native states")
		if tick>=8:rows.append(row)
		await process_frame
	var summary:={}
	for key:String in totals:
		if not totals[key].is_empty():summary[key]=stats(totals[key])
	var proof:={"scope":"isolated actual production shore patches; headless CPU API calls, no GPU/FPS/world-frame claim","patches":patches,"acceptedStepSeconds":1.0/60.0,"warmup":8,"samples":32,"quantile":"nearest-rank ceil(q*n)-1","terrainPacketsMeshSHA256":initial_hash.finish().hex_encode(),"sourceBaselineSHA256":FileAccess.get_sha256(BASELINE),"sourceCandidateSHA256":FileAccess.get_sha256("res://modules/scene_engine/terrain/natural_shore_surf.gd"),"summaryUsec":summary,"rows":rows,"failures":failures,"engine":Engine.get_version_info(),"processor":OS.get_processor_name()}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(proof,"\t"));file.close()
	print("SHORE_SUBMISSION_PROFILE ",JSON.stringify({"patches":patches,"summaryUsec":summary,"output":output,"failures":failures}))
	for group:Array in [full,compute,candidate]:
		for surf:Node3D in group:surf.dispose();surf.free()
	finish()
func finish()->void:
	print("SHORE_SUBMISSION_MEASURE_TESTS failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
