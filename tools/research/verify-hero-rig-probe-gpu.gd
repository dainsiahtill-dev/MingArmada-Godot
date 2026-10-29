extends SceneTree
## Actual paused laboratory interface: no explicit refresh after a parameter.
const Demo=preload("res://game/research/demos/hero_fuchuan_experiment.gd")
const WATCHED=["res://game/research/demos/hero_fuchuan_experiment.gd","res://game/research/fixtures/hero_rig_shadow_probe.gd","res://tools/research/verify-hero-rig-probe-gpu.gd"]
var checks:=0
var failures:Array=[]
var rows:Array=[]
var demo:Node3D
var output:=""
var source_hashes:Dictionary={}
func check(value:bool,why:String)->bool:
	checks+=1
	if not value:failures.append(why);printerr("FAIL paused rig probe: ",why)
	return value
func _initialize()->void:run.call_deferred()
func settle()->void:
	for frame in 5:await process_frame
	await RenderingServer.frame_post_draw
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	if not check(output.begins_with("res://") and not DirAccess.dir_exists_absolute(output),"fresh output required"):quit(1);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	if not check(DisplayServer.get_name()!="headless","real GPU required"):quit(1);return
	for path:String in WATCHED:source_hashes[path]=FileAccess.get_sha256(path)
	create_timer(90).timeout.connect(func():printerr("PAUSED_RIG_GPU watchdog");quit(1))
	root.size=Vector2i(1280,900);root.msaa_3d=Viewport.MSAA_4X;root.unfocusable=true;root.gui_disable_input=true
	demo=Demo.new();check(demo.configure({"model":"art_r7c","shadows":"authored","paused":true,"animated":false,"rig_probe":"hull_visible"}).ok,"valid authored preset accepted")
	root.add_child(demo)
	await settle()
	check(demo.shadow_diagnostics().renderer.gpu.get("initialized",false),"actual compositor initialized")
	var accepted:Dictionary=demo.inspection_snapshot()
	for mode:String in ["hull_visible","deck_visible","baseline"]:
		var renderer:RefCounted=demo.get("_shadow")
		var before:Dictionary=renderer.get("_volumes").duplicate(true)
		check(demo.set_parameter("rig_probe",mode).ok,"paused public setter accepts "+mode)
		var rigid:RefCounted=demo.get("_rigid")
		var model:Node3D=demo.get("_ship").get_model()
		var actual:Dictionary={}
		for label:String in ["hull","deck"]:
			var node:MeshInstance3D=model.find_child(label,true,false)
			var proxy:Mesh=node.get_meta("target_shadow_geometry")
			var part:Dictionary=rigid.get("_parts")["hero:"+label]
			check(part.revision==proxy.get_instance_id(),"paused setter immediately submits actual "+label+" input for "+mode)
			var volume:Dictionary=renderer.get("_volumes")["hero:"+label]
			actual[label]={"proxyMeshId":proxy.get_instance_id(),"submittedInputRevision":part.revision,"renderVolumeRevision":volume.geometryRevision}
			if mode=="deck_visible" or mode=="baseline":
				var changed:bool=(mode=="deck_visible") or label=="deck"
				if changed:check(volume.geometryRevision!=before["hero:"+label].geometryRevision,"renderer volume rebuilt synchronously "+label+mode)
		await settle()
		var image_path:=output.path_join(mode+".png");check(root.get_texture().get_image().save_png(image_path)==OK,"actual paused frame saved "+mode)
		var now:Dictionary=demo.inspection_snapshot();now.parameters.rig_probe="hull_visible"
		check(now==accepted,"public factor switch preserves paused accepted state "+mode)
		rows.append({"mode":mode,"actual":actual,"image":image_path,"imageSHA256":FileAccess.get_sha256(image_path),"shadow":demo.shadow_diagnostics()})
	for path:String in WATCHED:check(FileAccess.get_sha256(path)==source_hashes[path],"watched source stable "+path)
	demo.dispose();demo.free()
	var file:=FileAccess.open(output.path_join("PAUSED_RIG_GPU.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"scope":"Actual paused registered Demo public parameter contract, not native sailing/performance","engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"sourceHashes":source_hashes,"checks":checks,"failures":failures,"captures":rows},"\t"));file.close()
	print("HERO_PAUSED_RIG_GPU checks=",checks," failures=",failures.size())
	quit(1 if not failures.is_empty() else 0)
