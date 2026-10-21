extends "res://tools/profile-hull-dynamics-world.gd"
## Instrument the configured current source, preserving its fields and sequence.
## No manual reimplementation of World.apply_snapshot or missing mirror camera.
const PROBE_HELPER := '\nvar probe_costs:Dictionary={}\nvar probe_counts:Dictionary={}\nfunc _probe_call(key:String,job:Callable)->Variant:\n\tvar start:=Time.get_ticks_usec()\n\tvar value:Variant=job.call()\n\tprobe_costs[key]=int(probe_costs.get(key,0))+Time.get_ticks_usec()-start\n\tprobe_counts[key]=int(probe_counts.get(key,0))+1\n\treturn value\nfunc _probe_set(material:ShaderMaterial,key:String,value:Variant)->void:\n\tprobe_counts["shader:"+key]=int(probe_counts.get("shader:"+key,0))+1\n\tmaterial.set_shader_parameter(key,value)\n'
var observed:Array=[]
var labels:Dictionary={}
var originals:Dictionary={}
func attach(object:Object,label:String,methods:Array,sets:bool=false)->void:
	var original:Script=object.get_script();var source:=original.source_code
	if not originals.has(label):originals[label]={"path":original.resource_path,"sha256":source.sha256_text()}
	var values:Dictionary={}
	for property:Dictionary in original.get_script_property_list():values[property.name]=object.get(property.name)
	var wrappers:=""
	for entry:Array in methods:
		var method:String=entry[0];var signature:String=entry[1];var arguments:String=entry[2];var kind:String=entry[3]
		check(source.contains("func "+method+"("),label+" actual method exists: "+method)
		source=source.replace("func "+method+"(","func _probe_original_"+method+"(")
		wrappers+="\nfunc "+method+"("+signature+") -> "+kind+":\n"
		wrappers+=("\t_probe_call(" if kind=="void" else "\treturn _probe_call(")+'"'+method+'",func():'+(' ' if kind=="void" else 'return ')+"_probe_original_"+method+"("+arguments+"))\n"
	if sets:
		source=source.replace('_materials[i].set_shader_parameter(', '_probe_set(_materials[i],')
		source=source.replace('material.set_shader_parameter(key,current)', '_probe_set(material,key,current)')
	var script:=GDScript.new();script.source_code=source+PROBE_HELPER+wrappers
	if not check(script.reload()==OK,label+" instrumented source compiles"):return
	object.set_script(script)
	for name:String in values:object.set(name,values[name])
	for name:String in values:
		check(var_to_bytes(object.get(name))==var_to_bytes(values[name]),label+" original field restored: "+name)
	observed.append(object);labels[object.get_instance_id()]=label
func clear_costs()->void:
	for object:Object in observed:object.set("probe_costs",{});object.set("probe_counts",{})
func collect()->Dictionary:
	var result:Dictionary={}
	for object:Object in observed:
		var label:String=labels[object.get_instance_id()]
		if not result.has(label):result[label]={"usec":{},"counts":{}}
		for field:String in ["probe_costs","probe_counts"]:
			var target:String="usec" if field=="probe_costs" else "counts"
			for key:String in object.get(field):result[label][target][key]=int(result[label][target].get(key,0))+int(object.get(field)[key])
	return result
func install()->void:
	var world:Node3D=game.sea.world
	attach(world,"world",[["apply_snapshot","snapshot:Dictionary, consumed:float=0.0","snapshot,consumed","void"],["_sync_terrain_surface","","","void"],["_update_window","focus:Vector2","focus","void"],["_apply_source_lighting","","","void"]])
	var natural:Node3D=world.get("_natural_world")
	attach(natural,"naturalWorld",[["apply_snapshot","snapshot:Dictionary, consumed:float=0.0","snapshot,consumed","void"],["sync_surface_state","material:ShaderMaterial,state:Dictionary={}","material,state","void"]])
	for shore:Node3D in natural.get("_dynamic_shore"):
		attach(shore,"shore",[["apply_snapshot","snapshot:Dictionary, consumed:float=0.0","snapshot,consumed","void"],["sync_surface_state","material:ShaderMaterial,state:Dictionary={}","material,state","bool"]],true)
		if "--sampler-detail" in OS.get_cmdline_user_args():attach(shore.get("_sampler"),"shoreSampler",[["sample_into","index:int,time:float,state:Dictionary","index,time,state","void"]])
	for trees:Node3D in natural.get("_trees"):
		attach(trees,"forest",[["apply_snapshot","snapshot:Dictionary, consumed:float=0.0","snapshot,consumed","void"]])
	var atmosphere:RefCounted=world.atmosphere
	attach(atmosphere,"atmosphere",[["apply_snapshot","snapshot:Dictionary,camera:Camera3D,focus:Vector3=Vector3.ZERO,reflection_camera:Camera3D=null","snapshot,camera,focus,reflection_camera","void"],["_apply_weather","environment:Dictionary,camera:Dictionary,view:Camera3D,reflection:Camera3D","environment,camera,view,reflection","void"],["_update_group","records:Array,meshes:Array,placement:Transform3D,scale_adaptation:float","records,meshes,placement,scale_adaptation","void"]])
	var compiler_methods:Array=[["render_states","compiled:Dictionary,time:float=0.0,outer:Dictionary={},animate:bool=false,camera:Dictionary={},include_vertices:bool=false,minimum_z:bool=false,persistent:bool=false","compiled,time,outer,animate,camera,include_vertices,minimum_z,persistent","Array"],["render_minimum_states","compiled:Dictionary,outer:Dictionary,camera:Dictionary","compiled,outer,camera","Array"]]
	if "--compiler-detail" in OS.get_cmdline_user_args():
		compiler_methods.append_array([["_compose_transform","parent:Dictionary,local:Dictionary","parent,local","Dictionary"],["_minimum_z","vertices:Array,world:Dictionary","vertices,world","float"],["_sample","group:Dictionary,time:float","group,time","Variant"],["_interpolate_float_keys","group:Dictionary,time:float","group,time","float"],["_texture_transform","desc:Dictionary,overrides:Dictionary={}","desc,overrides","PackedFloat32Array"],["_clock_time","controller:Dictionary,time:float,persistent:bool=false","controller,time,persistent","float"],["_billboard_mode0","rotation:Array,camera:Dictionary","rotation,camera","Array"]])
	attach(atmosphere.get("_render_compiler"),"cloudCompiler",compiler_methods)
	attach(atmosphere.get("_cloud_lifecycle"),"cloudLifecycle",[["advance","index:int,packet:Dictionary,time:float,radius:float,visible:Callable","index,packet,time,radius,visible","Dictionary"]])
	attach(world.get_ocean(),"ocean",[["set_simulation_time","seconds:float","seconds","void"],["set_surface_wind","direction:Vector2,speed:float","direction,speed","void"],["update_projection","","","void"]])
	attach(game.sea.source_shadows,"sourceShadow",[["apply_snapshot","native:Dictionary,actor_nodes:Dictionary={},environment:Dictionary={}","native,actor_nodes,environment","void"],["_reconcile_snapshot_planes","requests:Dictionary,actor_nodes:Dictionary,epoch_changed:bool","requests,actor_nodes,epoch_changed","void"]])
func run()->void:
	output=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	if not check(not output.is_empty() and not FileAccess.file_exists(output),"fresh explicit output path"):quit(1);return
	var career:=MemorySlot.new();var legacy:=MemorySlot.new()
	main=Main.new();main.router=Router.new({"mingqi_storage":career,"legacy_storage":legacy,"settings_storage":Settings.new("user://verification/world-live-no-write-%d.json"%OS.get_process_id())});root.add_child(main)
	for frame in 5:await process_frame
	main.menu.find_child("sail",true,false).pressed.emit()
	for frame in 400:
		await process_frame
		if is_instance_valid(main.current_scene) and main.current_scene.get("startup_receipt").get("ok",false):break
	if not check(is_instance_valid(main.current_scene),"actual public sail ready"):quit(1);return
	game=main.current_scene;freeze_callbacks(main)
	for reason:String in ["menu","player","blur"]:game.runtime.set_pause(reason,false)
	game._present(0.0);install()
	var rows:Array=[];var summary:Dictionary={}
	var prior_call:=int(game.sea.get("_snapshot").get("environment",{}).get("sourceCallIndex",-1))
	for tick in 40:
		clear_costs()
		var start:=Time.get_ticks_usec();var accepted:float=game.runtime.advance(STEP);var runtime_usec:=Time.get_ticks_usec()-start
		start=Time.get_ticks_usec();game._present(accepted);var present_usec:=Time.get_ticks_usec()-start
		var stages:=collect()
		var source_call:=int(game.sea.get("_snapshot").get("environment",{}).get("sourceCallIndex",-1))
		if tick>=8:
			rows.append({"tick":tick,"accepted":accepted,"sourceCallIndex":source_call,"freshSourceCall":source_call!=prior_call,"runtimeUsec":runtime_usec,"presentationUsec":present_usec,"stages":stages})
			for label:String in stages:
				for method:String in stages[label].usec:
					var key:=label+"."+method
					if not summary.has(key):summary[key]=[]
					summary[key].append(stages[label].usec[method]/1000.0)
		prior_call=source_call
		await process_frame
	clear_costs();game._present(0.0);var paused_stages:=collect()
	var stats_result:Dictionary={}
	for key:String in summary:stats_result[key]=stats(summary[key])
	var hashes:Dictionary={}
	for object:Object in observed:
		var label:String=labels[object.get_instance_id()]
		if not hashes.has(label):hashes[label]=object.get_script().source_code.sha256_text()
	var proof:={"scope":"Actual public sail scene and current direct World.apply_snapshot sequence. Runtime script instrumentation restores all existing fields; no production file is changed. Nested timers include call/clock overhead and must not be summed. Headless CPU only; no GPU/world FPS claim.","samplerDetail":"--sampler-detail" in OS.get_cmdline_user_args(),"compilerDetail":"--compiler-detail" in OS.get_cmdline_user_args(),"sourceOriginal":originals,"warmup":8,"samples":rows.size(),"sourceInstrumentedSHA256":hashes,"stageMs":stats_result,"rows":rows,"sameTimeRefresh":paused_stages,"failures":failures,"engine":Engine.get_version_info()}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(proof,"\t"));file.close()
	print("WORLD_LIVE_COMPONENTS ",JSON.stringify({"stageMs":stats_result,"failures":failures,"output":output}))
	main.free();quit(0 if failures.is_empty() else 1)
