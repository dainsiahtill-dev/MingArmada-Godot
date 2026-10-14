extends SceneTree
## Real free-sail scene and command path; controlled accepted time, no live FPS claim.
const Practice = preload("res://game/scenes/naval_practice/naval_practice.gd")
const Settings = preload("res://game/persistence/user_settings.gd")
const AudioCleanup = preload("res://tests/fixtures/audio_cleanup.gd")
const SOURCES := ["game/presentation/world/naval_world_view.gd","modules/scene_engine/world/world_view.gd","modules/scene_engine/water/terrain_wet_mask.gd","modules/scene_engine/water/interactive_wake_system.gd","modules/scene_engine/water/interactive_wake_field.gd","modules/scene_engine/water/interactive_wake_field_rd.gd","modules/scene_engine/water/interactive_wake_height.glsl","modules/scene_engine/water/interactive_wake_foam.glsl","modules/scene_engine/water/ship_water_interaction.gd","modules/scene_engine/water/source_wake_renderer.gd","modules/scene_engine/water/source_surface.gd","game/presentation/water/wake_trails.gd","modules/scene_engine/ocean/projected_ocean.gd","modules/scene_engine/ocean/reference_game_water.gdshader","modules/scene_engine/ocean/interactive_wake_surface.gdshaderinc","tools/verify-interactive-wake-production-gpu.gd"]
var scene: Node3D
var output := ""
var baseline := false
var candidate_opt_in := false
var output_owned := false
var records: Array=[]
var failures: Array[String]=[]
var frozen: Dictionary={}
func isolate_input(node:Node)->void:
	node.set_process_input(false);node.set_process_unhandled_input(false);node.set_process_unhandled_key_input(false)
	for child:Node in node.get_children():isolate_input(child)
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok:failures.append(message);printerr("FAIL interactive production: ",message)
func hashes() -> Dictionary:
	var result: Dictionary={}
	for file: String in SOURCES:result[file]=FileAccess.get_sha256("res://"+file)
	for file: String in ["game/presentation/world/target_shadow_boundary.gd","game/presentation/world/target_rigid_shadow_caster.gd","game/presentation/world/prepared_rigid_shadow.gd","modules/scene_engine/fidelity_fx/source_shadow_math.gd","modules/scene_engine/fidelity_fx/source_shadow_rd.gd","modules/scene_engine/ocean/reference_shore_foam.gdshaderinc"]:
		result[file]=FileAccess.get_sha256("res://"+file)
	return result
func settle() -> bool:
	for attempt in 180:
		scene._present(0.0)
		if baseline:return true
		var status: Dictionary=scene.sea.interactive_water_status()
		if not str(status.get("error","")).is_empty():check(false,str(status.error));return false
		var field: Dictionary=status.get("field",{})
		var accepted:=float(scene.runtime.snapshot().naval.environment.acceptedTime)
		if status.get("bound",false) and not field.get("pending",true) and absf(float(field.get("time",-1))-accepted)<.00001:
			check(int(field.get("dropped_steps",-1))==0,"accepted field steps retained")
			return failures.is_empty()
		await process_frame
	check(false,"production field did not publish accepted time")
	return false
func ticks(count: int) -> void:
	for index in count:
		scene.runtime.set_pause("blur",false)
		scene._physics_process(1.0/60.0)
		if index%2==1:
			if not await settle():return
			await process_frame
func capture(label: String) -> void:
	if not await settle():return
	await RenderingServer.frame_post_draw
	var image: Image=root.get_texture().get_image()
	check(image!=null and not image.is_empty(),"real framebuffer "+label)
	if image==null or image.is_empty():return
	check(image.save_png(output+"/"+label+".png")==OK,"save "+label)
	var native: Dictionary=scene.runtime.snapshot().naval
	var status: Dictionary=scene.sea.interactive_water_status()
	var covered: Array=status.get("covered",[])
	check(covered.size()<=3,"whole-ship near-view budget")
	if not baseline:check(status.get("bound",false),"new field bound in normal scene")
	if not baseline:check(status.field.get("land_masked",false),"actual island terrain mask installed")
	check(scene.sea.sailors.size()>0,"3D crew owners retained")
	var material: ShaderMaterial=scene.sea.world.get_ocean().material_override
	var transmission:Dictionary={"scattering":material.get_shader_parameter("water_scattering"),"linear":material.get_shader_parameter("water_linear_transmission"),"preserve_shallows":material.get_shader_parameter("preserve_shallow_transmission")}
	check(transmission.scattering==.35 and transmission.linear==true and transmission.preserve_shallows==true,"selected transmission survives normal owner updates")
	check(int(material.get_shader_parameter("wave_count"))==5,"original five sea waves retained")
	var original: RefCounted=scene.sea.wakes.get("_source_wakes")
	var visible: Dictionary={}
	for id: String in original._actors:
		var actor: Dictionary=original._actors[id]
		if actor.surface.nodes.has("SceneStrip"):
			visible[id]=actor.surface.nodes.SceneStrip.visible
			if id in covered:check(not visible[id],"covered ship original tail suppressed")
	var mask: Dictionary=scene.sea.world.get_interactive_water_mask()
	mask.erase("data")
	var shadow: Dictionary=scene.sea.source_shadow_status()
	check(shadow.get("casterAdapter",{}).get("errors",[]).is_empty(),"rigid shadow adapter errors absent")
	records.append({"label":label,"image":label+".png","image_sha256":FileAccess.get_sha256(output+"/"+label+".png"),"time":native.time,"player_id":native.playerId,"ship_states":native.ships,"field":status,"mask":mask,"source_visible":visible,"original_wake":scene.sea.wakes.diagnostics(),"crew_owners":scene.sea.sailors.size(),"camera":str(scene.sea.camera.global_transform),"physics_sha256":var_to_bytes(native).hex_encode().sha256_text()})
	records[-1].shadow=shadow
	records[-1].transmission=transmission
	print("INTERACTIVE_PRODUCTION_CAPTURE ",label," time=",native.time," covered=",covered)
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		elif arg=="--baseline":baseline=true
		elif arg=="--candidate":candidate_opt_in=true
		else:check(false,"unknown argument "+arg)
	check(not output.is_empty() and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output)),"fresh output required")
	check(DisplayServer.get_name()!="headless","real GPU required")
	check(not (baseline and candidate_opt_in),"choose baseline or candidate")
	if not failures.is_empty():finish();return
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))==OK,"output created")
	if not failures.is_empty():finish();return
	output_owned=true;frozen=hashes()
	root.size=Vector2i(1600,900);root.content_scale_size=root.size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	scene=Practice.new();scene.startup_options={"mode":"sail","staged":true}
	scene.settings_storage=Settings.new("user://tests/interactive-water-%d.json"%OS.get_process_id())
	root.add_child(scene);await process_frame;await process_frame
	scene.set_process(false);scene.set_physics_process(false)
	check(scene.startup_receipt.get("ok",false),"actual free-sail startup")
	if not failures.is_empty():finish();return
	scene.activate_entry();scene.sea.apply_settings({"quality":"balanced"})
	# QA commands are the only input. Desktop clicks/keys must not alter the
	# controlled timeline while the user continues working in other windows.
	root.gui_disable_input=true;root.unfocusable=true;isolate_input(scene)
	if baseline or candidate_opt_in:
		scene.sea._options.interactive_wake=candidate_opt_in
		scene.sea._configure_interactive_water();scene.sea.wakes.set_interactive_coverage([])
	scene.runtime.set_pause("blur",false)
	await capture("01-start")
	var start: Dictionary=scene.runtime.snapshot().naval.ships[0].visual.position
	check(scene.runtime.command({"type":"mouse-course","point":{"x":start.x+700,"z":start.z}}).ok,"mouse-course real command")
	await ticks(240);await capture("02-cruise-4s")
	await ticks(480);await capture("03-cruise-12s")
	var straight: Dictionary=scene.runtime.snapshot().naval.ships[0].visual.position
	check(Vector2(straight.x-start.x,straight.z-start.z).length()>10,"real ship moved clear of initial shore")
	check(scene.runtime.command({"type":"mouse-course","point":{"x":straight.x+160,"z":straight.z+650}}).ok,"real turn command")
	await ticks(480);await capture("04-turn-8s")
	check(scene.runtime.command({"type":"stop-sailing"}).ok,"real stop command")
	await ticks(600);await capture("05-stop-10s")
	var stopped:Dictionary=scene.runtime.snapshot().naval.ships[0]
	var stopped_velocity:Dictionary=stopped.visual.velocity
	check(float(stopped.sailDeployment)==0.0 and Vector2(stopped_velocity.x,stopped_velocity.z).length()<.05,"stop command reaches a stopped ship")
	var before: Dictionary=scene.sea.interactive_water_status()
	var physics:=var_to_bytes(scene.runtime.snapshot())
	scene.sea.apply_settings({"quality":"high"})
	await capture("06-quality-paused")
	check(var_to_bytes(scene.runtime.snapshot())==physics,"quality rebuild does not advance gameplay")
	if not baseline:
		var after: Dictionary=scene.sea.interactive_water_status()
		check(after.field.total_steps==before.field.total_steps,"same-mask quality keeps field history")
		check(after.mask_digest==before.mask_digest,"quality uses same rendered terrain mask")
	check(hashes()==frozen,"frozen source during production GPU")
	check(records.size()==6,"six nonzero captures")
	if not baseline:
		var found:=false
		for row: Dictionary in records:found=found or row.player_id in row.field.get("covered",[])
		check(found,"actual player covered by GPU field")
	finish()
func finish() -> void:
	if is_instance_valid(scene):
		var playbacks: Array[WeakRef]=AudioCleanup.stop_players(scene)
		scene.free();scene=null
		check(await AudioCleanup.wait_for_release(self,playbacks),"audio lifecycle")
	if output_owned:
		var file:=FileAccess.open(output+"/GPU_VERIFY.json",FileAccess.WRITE)
		if file!=null:file.store_string(JSON.stringify({"valid":failures.is_empty(),"failures":failures,"baseline":baseline,"candidate_opt_in":candidate_opt_in,"gpu":RenderingServer.get_video_adapter_name(),"sources":frozen,"captures":records,"scope":"Actual free-sail scene/command path with controlled time. Not live full-game FPS."},"\t"));file.close()
	print("INTERACTIVE_WAKE_PRODUCTION_GPU captures=",records.size()," failures=",failures.size())
	quit(1 if failures.size() else 0)
