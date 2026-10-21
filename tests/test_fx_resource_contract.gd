extends SceneTree
const Combat=preload("res://game/presentation/combat/combat_effects.gd")
const Source=preload("res://modules/scene_engine/fidelity_fx/presentation.gd")
const Runtime=preload("res://modules/scene_engine/fidelity_fx/particle_runtime.gd")
var assertions:=0
var failures:=0
func check(ok:bool,message:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL FX resource: ",message)
func _initialize()->void:run.call_deferred()
func run()->void:
	var combat:=Combat.new();root.add_child(combat)
	var before:=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	combat._puff(Vector3.ZERO,Color.WHITE,1,1,Vector3.ZERO,1,-1,"missing-research-texture.dds")
	check(combat._puffs.is_empty(),"failed texture emits no effect")
	check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))==before,"failed texture leaves no unowned Node")
	combat.free()
	var runtime:=Runtime.new()
	check(runtime.has_method("texture_dependencies"),"prewarm uses a public detached dependency query")
	if runtime.has_method("texture_dependencies"):
		check(runtime.configure(Source._asset("fx_cannon_fire_01.nif"),1,false),"real source configures")
		var names:PackedStringArray=runtime.texture_dependencies()
		check(not names.is_empty() and "fx_cannon_smoke_01.dds" in names,"real original texture dependencies are exposed")
		var saved:=names.duplicate();names.clear()
		check(runtime.texture_dependencies()==saved,"consumer cannot mutate runtime source through dependency query")
	print("FX_RESOURCE_CONTRACT_TESTS assertions=",assertions," failures=",failures);quit(1 if failures else 0)
