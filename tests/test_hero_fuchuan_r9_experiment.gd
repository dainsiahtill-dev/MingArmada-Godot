extends SceneTree
## Real imported candidate must remain an isolated research variant.
const Experiment=preload("res://game/research/demos/hero_fuchuan_experiment.gd")
const Provider=preload("res://game/research/fixtures/hero_palette_provider.gd")
const Formal=preload("res://modules/scene_engine/assets/hero_ship_provider.gd")
var assertions:=0
var failures:=0

func _initialize()->void: run.call_deferred()
func check(ok:bool,detail:String)->void:
	assertions+=1
	if not ok: failures+=1;printerr("FAIL: ",detail)

func run()->void:
	var demo=Experiment.new();root.add_child(demo)
	var revision:="r9b" if "--r9b" in OS.get_cmdline_user_args() else "r9"
	var model_option:="art_"+revision
	var png:="res://assets/textures/hero_fuchuan_r9/"+("sunfaded-cinnabar-hemp-sail.png" if revision=="r9b" else "cinnabar-hemp-sail.png")
	var result:Dictionary=demo.configure({"model":model_option,"animated":false,"paused":true,"shadows":"authored"})
	if not check_result(result): demo.free();finish();return
	var choices:Array=demo.control_spec().filter(func(row):return row.id=="model")[0].choices
	check(choices.any(func(choice):return choice.value==model_option),"laboratory exposes the requested candidate")
	check(demo._ship.get_model().get_meta("source_path","")=="res://assets/models/hero_fuchuan_v3_%s/fuchuan-lod0.glb"%revision,"actual demo loads the candidate LOD0")
	var expected:=Image.new()
	check(expected.load_png_from_buffer(FileAccess.get_file_as_bytes(png))==OK,"source PNG decodes in the isolated test")
	var provider:=Provider.new("art_r6",true,revision)
	for lod in range(3):
		var model:Node3D=provider.instantiate_ship("fuchuan",lod)
		check(model!=null,"candidate loads LOD "+str(lod))
		if model==null:continue
		check(model.get_meta("source_path","")=="res://assets/models/hero_fuchuan_v3_%s/fuchuan-lod%d.glb"%[revision,lod],"correct source path LOD "+str(lod))
		check(model.get_meta("art_revision",0)==9,"correct revision LOD "+str(lod))
		for index in range(3):
			var sail:=model.find_child("sail_%d"%index,true,false) as MeshInstance3D
			check(sail!=null and sail.mesh.get_blend_shape_count()==2,"live sail morphs LOD%d sail%d"%[lod,index])
			if sail==null:continue
			var found:=false
			for surface in sail.mesh.get_surface_count():
				var material=sail.get_active_material(surface)
				if material is StandardMaterial3D and material.resource_name=="canvas":
					found=true
					var image:Image=material.albedo_texture.get_image() if material.albedo_texture else null
					if image!=null and image.is_compressed():image.decompress()
					check(image!=null and image.get_size()==expected.get_size(),"canvas uses generated image dimensions")
					if image!=null and image.get_size()==expected.get_size():
						check(image.get_pixel(image.get_width()/2,image.get_height()/2).is_equal_approx(expected.get_pixel(expected.get_width()/2,expected.get_height()/2)),"canvas consumes real generated center pixel")
						check(image.has_mipmaps(),"canvas retains runtime mipmaps")
			check(found,"canvas name remains available to damage shader")
		model.free()
	var formal:=Formal.new()
	var baseline:Node3D=formal.instantiate_ship("fuchuan",0)
	check(baseline!=null and baseline.get_meta("source_path","").contains("hero_fuchuan_v3_r7c"),"formal default still uses r7c")
	if baseline:baseline.free()
	demo.dispose();demo.free();finish()

func check_result(result:Dictionary)->bool:
	check(result.get("ok",false),"candidate config is accepted by existing experiment")
	return result.get("ok",false)
func finish()->void:
	print("HERO_R9_EXPERIMENT_TEST assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
