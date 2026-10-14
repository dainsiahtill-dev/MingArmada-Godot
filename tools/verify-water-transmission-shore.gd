extends SceneTree
const Main=preload("res://game/scenes/main/main_scene.tscn")
var output:=""
var failures:Array=[]
var captures:Array=[]
const SOURCES=["modules/scene_engine/ocean/reference_game_water.gdshader","modules/scene_engine/ocean/shore_edge_coverage.gdshaderinc","modules/scene_engine/ocean/reference_shore_foam.gdshaderinc","tools/verify-water-transmission-shore.gd"]
func _initialize()->void:run.call_deferred()
func frames(n:int)->void:
	for _i in n:await process_frame
func check(ok:bool,why:String)->void:
	if not ok:failures.append(why);printerr("FAIL TRANSMISSION SHORE ",why)
func hashes()->Dictionary:
	var out:Dictionary={}
	for p:String in SOURCES:out[p]=FileAccess.get_sha256("res://"+p)
	return out
func effective_float(material:ShaderMaterial,name:String)->float:
	var value:Variant=material.get_shader_parameter(name)
	if value is float or value is int:return float(value)
	# Godot may return null for a shader's implicit uniform default. Read that
	# declared default, rather than inventing a material value or setting it.
	var pattern:=RegEx.new();pattern.compile("uniform float "+name+"[^;]*=\\s*([0-9.]+)\\s*;")
	var found:=pattern.search(material.shader.code)
	return float(found.get_string(1)) if found else NAN
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	check(not output.is_empty() and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output)),"fresh output")
	if not failures.is_empty():quit(1);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var frozen:=hashes()
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT;root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_KEEP
	root.size=Vector2i(1600,1000);root.content_scale_size=root.size
	var main:Node=Main.instantiate();root.add_child(main);await frames(4)
	main.menu.find_child("fidelity-island",true,false).pressed.emit()
	for _i in 150:
		await process_frame
		if is_instance_valid(main.current_scene):break
	var scene:Control=main.current_scene
	check(is_instance_valid(scene) and scene.startup_receipt.ok,"actual shared world")
	if not failures.is_empty():main.free();quit(1);return
	scene.paused=true;scene.set_process(false);scene.seconds=24.0
	var original_controller:Callable=scene._update_camera
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/research/evidence/laboratory-environment-2026-10-14/candidate/shore-edge-width-35.png.json"))
	var values:Array=source.demo.camera_transform
	var pose:=Transform3D(Basis(Vector3(values[0],values[1],values[2]),Vector3(values[4],values[5],values[6]),Vector3(values[8],values[9],values[10])),Vector3(values[12],values[13],values[14]))
	var ocean:MeshInstance3D=scene.world._ocean
	var material:ShaderMaterial=ocean.material_override
	for angle:String in ["wide","edge"]:
		scene.sea.set_camera_controller(func():scene.camera.transform=pose) if angle=="edge" else scene.sea.set_camera_controller(original_controller)
		for mode:String in ["baseline","global035","selected"]:
			material.set_shader_parameter("water_scattering",0.0 if mode=="baseline" else .35)
			material.set_shader_parameter("water_linear_transmission",mode!="baseline")
			material.set_shader_parameter("preserve_shallow_transmission",mode=="selected")
			scene._render();await frames(5);await RenderingServer.frame_post_draw
			var image:Image=scene.view.get_texture().get_image()
			var name:=angle+"-"+mode+".png"
			check(image.save_png(output+"/"+name)==OK,"save "+name)
			check(is_equal_approx(effective_float(material,"shore_edge_feather_m"),.6),"shore width retained")
			check(is_equal_approx(effective_float(material,"shore_edge_water_weight"),.55),"shore transparency retained")
			check(scene.seconds==24.0,"no clock advance")
			captures.append({"image":name,"sha256":FileAccess.get_sha256(output+"/"+name),"angle":angle,"mode":mode,"camera":str(scene.camera.global_transform),"time":scene.seconds,"size":str(image.get_size()),"scatter":material.get_shader_parameter("water_scattering"),"linear":material.get_shader_parameter("water_linear_transmission"),"shore_width":effective_float(material,"shore_edge_feather_m"),"shore_weight":effective_float(material,"shore_edge_water_weight")})
	check(hashes()==frozen,"frozen source")
	main.free();await frames(3)
	var file:=FileAccess.open(output+"/GPU_VERIFY.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"valid":failures.is_empty(),"failures":failures,"sources":frozen,"captures":captures,"scope":"Same-time actual shared world coast; old optics versus selected 0.35 linear optics. Original shore feather parameters unchanged. No FPS claim."},"\t"));file.close()
	print("WATER_TRANSMISSION_SHORE captures=",captures.size()," failures=",failures.size());quit(0 if failures.is_empty() else 1)
