extends SceneTree
const Wake=preload("res://game/presentation/water/wake_trails.gd")
var assertions:=0
var failures:=0
func check(ok:bool,message:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL: ",message)
func _initialize()->void:_run.call_deferred()
func _water(_x:float,_z:float,_time:float)->float:return 0.35
func packet(call_index:int,source_clock:float,x:float,route:String="scene_30")->Dictionary:
	return {"time":source_clock,"environment":{"route":"sailing"},"wake":{"route":route,"epoch":1,"sourceCallIndex":call_index},"ships":[{"id":"ship","hull":100.0,"sourceWake":{"route":route,"sourceCallIndex":call_index,"sourceClock":source_clock,"sourcePosition":[x,100,0],"markerId":"Dummy_Wake","modelScale":0.1,"sourceToWorld":0.01,"sourceHeading":0.0,"froth":{"family":0,"seed":7,"controllerAppTime":source_clock,"sourceBowPosition":[x+20,100,0],"enabled":true}}}]}
func _run()->void:
	var wake:=Wake.new();root.add_child(wake);wake.configure(_water)
	for i in 60:wake.apply_snapshot(packet(i,float(i)/10,100+i*4))
	var report:Dictionary=wake.diagnostics()
	check(report.get("source_routes",{}).get("scene_30",0)==1,"explicit original scene route runs through production Wakes seam")
	check(report.get("source_updates",0)==60,"original update count accepted independently from rendering")
	check(report.get("source_samples",0)==30,"production history ring is 30")
	check(report.get("authored_froth_meshes",0)==2 and report.get("source_particle_systems",0)==4,"production seam displays distinct original bow/side/pool resources")
	if report.has("source_updates"):
		wake.apply_snapshot(packet(59,5.9,800));check(wake.diagnostics().source_updates==60,"repeated presentation call cannot consume history again")
		wake.apply_snapshot(packet(60,5.9,340));check(wake.diagnostics().source_updates==61,"new original source call accepts displacement at same source clock")
		var source_rewind:Dictionary=packet(61,5.0,344);source_rewind.time=6.0
		wake.apply_snapshot(source_rewind);check(wake.diagnostics().source_updates==61,"source clock rewind with forward target presentation time rejects without clearing native history")
		var rendered:=0
		for parent:Node in wake.get_children():
			for node:Node in parent.get_children():
				if node is MeshInstance3D and node.mesh!=null and node.visible:
					rendered+=1
					for vertex:Vector3 in node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:check(vertex.is_finite(),"production source mesh vertices finite")
		check(rendered>0,"native history produces an actual renderer mesh")
	check(wake.has_method("take_source_state") and wake.has_method("restore_source_state"),"quality rebuild can transfer owned histories/controller/pool clocks")
	if wake.has_method("take_source_state"):
		var state:RefCounted=wake.take_source_state()
		wake.configure(_water);wake.restore_source_state(state)
		var replay:Dictionary=packet(61,5.0,344);replay.time=6.0;wake.apply_snapshot(replay)
		check(wake.diagnostics().source_updates==61 and wake.diagnostics().source_samples==30,"same-call quality replay preserves original ring and rejects duplicate consumption")
	wake.apply_snapshot({"time":6.0,"wake":{"route":"scene_30","epoch":1,"sourceCallIndex":62},"ships":[]})
	check(wake.diagnostics().get("source_samples",0)==0,"removed actor releases original source history and attached resources")
	var battle:Dictionary=packet(63,6.1,100,"battle_90")
	battle.ships[0].sourceWake.battle={"type":0,"tick":7,"x":8000,"y":4000,"heading":0,"map_origin_x":100,"map_origin_y":100,"sine_boundary":0,"hold_history":false}
	wake.apply_snapshot(battle)
	check(wake.diagnostics().get("source_battle_draws",0)==21 and wake.diagnostics().get("source_samples",0)==90,"battle route produces seven three-layer carrier draws and independent 90 history")
	var source_nodes:int=wake.get_child(0).get_child_count()
	check(source_nodes>=21,"every original battle submission has a production mesh carrier")
	battle.time=6.2;battle.ships[0].sourceWake.sourceCallIndex=64;battle.ships[0].sourceWake.sourceClock=6.2;battle.ships[0].sourceWake.battle.hold_history=true
	wake.apply_snapshot(battle)
	check(wake.diagnostics().get("source_battle_draws",0)==21,"battle hold preserves all layer submits")
	wake.dispose();wake.free()
	print("SOURCE_WAKE_RENDERER_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
