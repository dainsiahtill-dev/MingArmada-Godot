extends SceneTree
const Runtime=preload("res://modules/scene_engine/fidelity_fx/particle_runtime.gd")
var assertions:=0
var failures:=0
func check(ok:bool,message:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL: ",message)
func _initialize()->void:_run.call_deferred()
func _run()->void:
	var asset:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/source_wake/fx_ship_bowfroth.nif.json"))
	var runtime:=Runtime.new();var configured:=runtime.configure(asset,7,false)
	check(configured,"original bow with four systems and absent optional reset controller validates: "+runtime.get_last_error())
	if configured:
		var owned=runtime.spawn_native(7)
		check(owned.has_method("set_source_outer"),"moving authored world-space emitters receive real source root before native advance")
		if owned.has_method("set_source_outer"):
			owned.set_source_outer({"rotation":[1,0,0,0,1,0,0,0,1],"translation":[100,100,0],"scale":1.0})
		for time:float in [0.0,0.25,0.5,24.9,25.1,25.4,26.0]:
			owned.advance_native(time,false)
			var state:Dictionary=owned.source_state()
			check(state.systems.size()==4,"all original pools survive absent reset and loop")
			for system:Dictionary in state.systems:
				check(int(system.numActive)<=10,"each source capacity bounded")
				for particle:Dictionary in system.particles:
					for component:Variant in particle.position:check(is_finite(float(component)),"native pool positions finite")
		check(owned.diagnostics().births>0,"original native emitters produce real births")
		if owned.has_method("set_source_outer"):
			var moving=runtime.spawn_native(17)
			var pose:Dictionary={"rotation":[1,0,0,0,1,0,0,0,1],"translation":[100,100,0],"scale":1.0}
			moving.set_source_outer(pose);moving.advance_native(0.0,false);moving.advance_native(0.25,false)
			pose.translation=[1100,100,0];moving.set_source_outer(pose);moving.advance_native(0.30,false)
			var old_cloud:=false;var new_cloud:=false
			for system:Dictionary in moving.source_state().systems:
				for i in int(system.numActive):
					var x:float=system.particles[i].position[0]*float(system.world.scale)
					old_cloud=old_cloud or x<400.0;new_cloud=new_cloud or x>800.0
			check(old_cloud and new_cloud,"moving source root emits at new marker while surviving world-space particles remain behind")
	print("SOURCE_FROTH_PARTICLE_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
