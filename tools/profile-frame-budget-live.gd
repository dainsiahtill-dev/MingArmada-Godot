extends "res://tools/profile-world-live-components.gd"
## Actual automatic public entry; in-memory nested CPU timers, no product edits.
## Instrumented frame intervals are diagnostic, never unmodified game FPS.
const AudioCleanup=preload("res://tests/fixtures/audio_cleanup.gd")
var callback_flags:Array=[]
var measured:Array=[]
func attach(object:Object,label:String,methods:Array,sets:bool=false)->void:
	var original:Script=object.get_script();var source:=original.source_code
	if not originals.has(label):originals[label]={"path":original.resource_path,"sha256":source.sha256_text()}
	var values:Dictionary={}
	for property:Dictionary in original.get_script_property_list():values[property.name]=object.get(property.name)
	# This is an existing initialized instance. Never rerun its constructor;
	# Simulation._init requires an Encounter and has no zero-argument form.
	source=source.replace("func _init(","func _probe_saved_init(")
	var wrappers:=""
	for entry:Array in methods:
		var method:String=entry[0];var signature:String=entry[1];var arguments:String=entry[2];var kind:String=entry[3]
		if not check(source.contains("func "+method+"("),label+" actual method exists: "+method):return
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
	for name:String in values:check(var_to_bytes(object.get(name))==var_to_bytes(values[name]),label+" original field restored: "+name)
	observed.append(object);labels[object.get_instance_id()]=label
func remember_flags(node:Node)->void:
	callback_flags.append({"node":node,"process":node.is_processing(),"physics":node.is_physics_processing(),"input":node.is_processing_input(),"unhandled":node.is_processing_unhandled_input()})
	for child:Node in node.get_children():remember_flags(child)
func restore_flags()->void:
	for row:Dictionary in callback_flags:
		row.node.set_process(row.process);row.node.set_physics_process(row.physics)
		row.node.set_process_input(row.input);row.node.set_process_unhandled_input(row.unhandled)
func install_frame_timers()->void:
	install()
	attach(game,"game",[["_process","delta:float","delta","void"],["_physics_process","delta:float","delta","void"],["_present","consumed:float","consumed","void"]])
	attach(game.runtime,"runtime",[["advance","seconds:float","seconds","float"],["snapshot","","","Dictionary"]])
	attach(game.runtime.simulation,"simulation",[["snapshot","","","Dictionary"]])
	attach(game.sea,"sea",[["apply_snapshot","native:Dictionary,events:Array=[],consumed:float=0.0","native,events,consumed","Array"],["_apply_source_shadows","native:Dictionary","native","void"],["_apply_interactive_water","native:Dictionary","native","void"],["remember_authoritative_poses","native:Dictionary,consumed:float=0.0","native,consumed","void"],["observe_projectiles","native:Dictionary","native","void"]])
	for view:Node3D in game.sea.ships.values():attach(view,"ship",[["apply_snapshot","ship:Dictionary,wind:Dictionary={},consumed:float=0.0","ship,wind,consumed","void"]])
	for crew:Node3D in game.sea.sailors.values():attach(crew,"crew",[["apply_snapshot","ship:Dictionary,wind:Dictionary={},consumed:float=0.0","ship,wind,consumed","void"]])
	attach(game.sea.effects,"effects",[["begin_snapshot","native:Dictionary,consumed:float=0.0","native,consumed","void"],["finish_snapshot","","","void"]])
	attach(game.sea.wakes,"wakes",[["apply_snapshot","native:Dictionary","native","void"]])
	attach(game.interface,"interface",[["apply_snapshot","packet:Dictionary","packet","void"]])
	attach(game.services,"services",[["present","native:Dictionary,events:Array,consumed:float,paused:bool","native,events,consumed,paused","void"]])
	attach(game.minimap,"minimap",[["present","native:Dictionary,overlays:Dictionary={},blocked:bool=false","native,overlays,blocked","void"]])
func actors()->Dictionary:
	var visible:=0
	for crew:Node3D in game.sea.sailors.values():visible+=crew.get_visible_count()
	return {"ships":game.sea.ships.size(),"visibleCrew":visible}
func render_times()->Array:
	var rows:Array=[]
	for entry:Dictionary in measured:
		rows.append({"name":entry.name,"cpuMs":RenderingServer.viewport_get_measured_render_time_cpu(entry.rid),"gpuMs":RenderingServer.viewport_get_measured_render_time_gpu(entry.rid)})
	return rows
func run()->void:
	output=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	if not check(not output.is_empty() and not FileAccess.file_exists(output),"fresh explicit output required"):quit(1);return
	if not check(DisplayServer.get_name()!="headless","automatic native GPU profile requires real renderer"):quit(1);return
	create_timer(120).timeout.connect(func():printerr("FRAME_BUDGET_PROFILE watchdog expired");quit(1))
	root.size=Vector2i(1600,900);root.content_scale_size=root.size;root.unresizable=true
	var career:=MemorySlot.new();var legacy:=MemorySlot.new();slots=[career,legacy]
	main=Main.new();main.router=Router.new({"mingqi_storage":career,"legacy_storage":legacy,"settings_storage":Settings.new("user://verification/frame-budget-no-write-%d.json"%OS.get_process_id())});root.add_child(main)
	for frame in 5:await process_frame
	seed(1661);main.menu.find_child("sail",true,false).pressed.emit()
	for frame in 400:
		await process_frame
		if is_instance_valid(main.current_scene) and main.current_scene.get("startup_receipt").get("ok",false):break
	if not check(is_instance_valid(main.current_scene),"ordinary sail initialized"):main.free();quit(1);return
	game=main.current_scene
	remember_flags(main);freeze_callbacks(main)
	var state_before:Dictionary=game.runtime.snapshot()
	install_frame_timers()
	check(state_before==game.runtime.snapshot(),"instrumentation preserves complete authoritative snapshot")
	if not failures.is_empty():
		DirAccess.make_dir_recursive_absolute(output.get_base_dir())
		var failure_file:=FileAccess.open(output,FileAccess.WRITE)
		failure_file.store_string(JSON.stringify({"scope":"invalid instrumentation attempt; no timing conclusions","failures":failures},"\t"));failure_file.close()
		printerr("FRAME_BUDGET_PROFILE instrumentation invalid; stopping before automatic callbacks")
		quit(1);return
	var files:Dictionary={"res://tools/profile-frame-budget-live.gd":FileAccess.get_sha256("res://tools/profile-frame-budget-live.gd")}
	for row:Dictionary in originals.values():files[row.path]=FileAccess.get_sha256(row.path)
	measured.append({"name":"main","rid":root.get_viewport_rid()})
	for viewport:SubViewport in root.find_children("*","SubViewport",true,false):measured.append({"name":str(viewport.name),"rid":viewport.get_viewport_rid()})
	for entry:Dictionary in measured:RenderingServer.viewport_set_measure_render_time(entry.rid,true)
	restore_flags();root.grab_focus()
	for reason:String in ["menu","player","blur"]:game.runtime.set_pause(reason,false)
	var start:=Time.get_ticks_usec();var previous:=start;var warmed:=false;var rows:Array=[];var summaries:Dictionary={};var invalid:Array=[]
	clear_costs()
	while rows.size()<120:
		await process_frame;await RenderingServer.frame_post_draw
		var now:=Time.get_ticks_usec();var elapsed:=float(now-start)/1000000.0
		if elapsed>=5.0 and warmed:
			var stages:=collect();var paused:bool=game.runtime.is_paused()
			if paused or not root.has_focus():invalid.append({"row":rows.size(),"paused":paused,"focused":root.has_focus()})
			rows.append({"wallSeconds":elapsed,"diagnosticIntervalMs":float(now-previous)/1000.0,"nativeTime":game.sea.get("_snapshot").get("time"),"stages":stages,"actors":actors(),"renderTimes":render_times(),"paused":paused,"focused":root.has_focus()})
			for label:String in stages:
				for method:String in stages[label].usec:
					var key:=label+"."+method
					if not summaries.has(key):summaries[key]=[]
					summaries[key].append(float(stages[label].usec[method])/1000.0)
		if elapsed>=5.0:warmed=true
		clear_costs();previous=now
	game.runtime.set_pause("player",true)
	var results:Dictionary={}
	for key:String in summaries:results[key]=stats(summaries[key])
	var unchanged:=true
	for path:String in files:unchanged=unchanged and files[path]==FileAccess.get_sha256(path)
	check(unchanged,"source files unchanged during instrumented run")
	check(career.writes==0 and legacy.writes==0,"no save writes")
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var png:=output.trim_suffix(".json")+".png";root.get_texture().get_image().save_png(png)
	var proof:Dictionary={"scope":"Actual automatic Main/router/NavalPractice public sail, seed1661, 1600x900 default quality/actors. In-memory method wrappers restore every field and authoritative snapshot. Five seconds warmup then120 rendered frames. Nested timers include wrapper overhead; do not sum parent/child. Instrumented intervals are not unmodified FPS; GPU queries are separately observed. No actor/quality/effect removal.","engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"sourceFiles":files,"sourceOriginal":originals,"sourcesUnchanged":unchanged,"rows":rows,"stageMs":results,"invalid":invalid,"failures":failures,"capture":{"path":png,"sha256":FileAccess.get_sha256(png)}}
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(proof,"\t"));file.close()
	var playbacks:Array[WeakRef]=AudioCleanup.stop_players(main);main.free();main=null
	check(await AudioCleanup.wait_for_release(self,playbacks),"audio cleanup completed")
	print("FRAME_BUDGET_PROFILE rows=",rows.size()," invalid=",invalid.size()," failures=",failures.size()," output=",output)
	quit(1 if not failures.is_empty() or not invalid.is_empty() else 0)
