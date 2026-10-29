extends SceneTree
## Research-only selection; real three LODs, coaming obstacles and formal default.
const Experiment=preload("res://game/research/demos/hero_fuchuan_experiment.gd")
const Palette=preload("res://game/research/fixtures/hero_palette_provider.gd")
const Formal=preload("res://modules/scene_engine/assets/hero_ship_provider.gd")
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,detail:String)->bool:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",detail)
	return ok
func run()->void:
	var demo=Experiment.new();root.add_child(demo)
	var result:Dictionary=demo.configure({"model":"art_r14b","animated":false,"paused":true,"shadows":"authored"})
	check(result.get("ok",false),"R14b research configures")
	var choices:Array=demo.control_spec().filter(func(row):return row.id=="model")[0].choices
	check(choices.any(func(x):return x.value=="art_r14b"),"R14b research choice visible")
	check(demo.set_parameter("model","art_r14b").get("ok",false),"R14b accepted as model")
	if result.get("ok",false):check(demo._ship.get_model().get_meta("source_path","").contains("hero_fuchuan_v3_r14b/"),"demo actually loads R14b")
	var candidate:=Palette.new("art_r6",true,"r14b")
	for lod in range(3):
		var model:Node3D=candidate.instantiate_ship("fuchuan",lod)
		if not check(model!=null,"actual R14b LOD%d loads"%lod):continue
		check(model.get_meta("source_path","")=="res://assets/models/hero_fuchuan_v3_r14b/fuchuan-lod%d.glb"%lod,"actual R14b identity")
		check(model.get_meta("art_revision",0)==14,"R14b revision metadata")
		for name:String in ["cargo_hold_coaming_-3_2","cargo_hold_coaming_5_8"]:
			var node:=model.find_child(name,true,false) as MeshInstance3D
			check(node!=null and node.get_meta("deck_obstacle",false),"actual coaming is obstacle "+name)
		check(model.find_children("cannon_port_*","Node3D",true,false).size()==4 and model.find_children("cannon_starboard_*","Node3D",true,false).size()==4,"four guns each side")
		model.free()
	var formal:=Formal.new();var default:Node3D=formal.instantiate_ship("fuchuan",0)
	check(default!=null and default.get_meta("source_path","").contains("hero_fuchuan_v3_r7c"),"formal default remains R7c")
	if default:default.free()
	demo.dispose();demo.free()
	print("HERO_R14B_EXPERIMENT checks=",checks," failures=",failures)
	quit(1 if failures else 0)
