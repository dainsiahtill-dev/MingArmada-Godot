extends SceneTree
const Experiment=preload("res://game/research/demos/hero_fuchuan_experiment.gd")
const Palette=preload("res://game/research/fixtures/hero_palette_provider.gd")
const Formal=preload("res://modules/scene_engine/assets/hero_ship_provider.gd")
var assertions:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,detail:String)->bool:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL R13 experiment: ",detail)
	return ok
func run()->void:
	var demo=Experiment.new();root.add_child(demo)
	var result:Dictionary=demo.configure({"model":"art_r13","animated":false,"paused":true,"shadows":"authored"})
	check(result.get("ok",false),"R13 experiment configures")
	var choices:Array=demo.control_spec().filter(func(row):return row.id=="model")[0].choices
	check(choices.any(func(choice):return choice.value=="art_r13"),"R13 visible in laboratory choice")
	check(demo.set_parameter("model","art_r13").get("ok",false),"R13 choice accepted")
	if result.get("ok",false):check(demo._ship.get_model().get_meta("source_path","").contains("hero_fuchuan_v3_r13/fuchuan-lod0.glb"),"R13 LOD0 bound in demo")
	var candidate:=Palette.new("art_r6",true,"r13")
	for lod in range(3):
		var model:Node3D=candidate.instantiate_ship("fuchuan",lod)
		if not check(model!=null,"R13 LOD%d loaded"%lod):continue
		check(model.get_meta("source_path","")=="res://assets/models/hero_fuchuan_v3_r13/fuchuan-lod%d.glb"%lod,"R13 LOD%d identity"%lod)
		check(model.get_meta("art_revision",0)==13,"R13 revision identity")
		model.free()
	var normal:Node3D=Formal.new().instantiate_ship("fuchuan",0)
	check(normal!=null and normal.get_meta("source_path","").contains("hero_fuchuan_v3_r7c"),"formal default remains R7c")
	if normal:normal.free()
	demo.dispose();demo.free();await process_frame
	print("HERO_R13_EXPERIMENT assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
