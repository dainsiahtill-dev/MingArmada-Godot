extends SceneTree
var assertions:=0
var failures:=0
func check(ok:bool,label:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL shadow experiment: ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
	var demo:Node3D=load("res://game/research/demos/shadow_edges_experiment.gd").new()
	check(demo.configure({}).ok,"pre-tree configure")
	var viewport:=SubViewport.new();viewport.own_world_3d=true;viewport.size=Vector2i(960,640);root.add_child(viewport);viewport.add_child(demo)
	check(demo.inspection_snapshot().ready,"real isolated shadow components build")
	for tick in 120:demo.advance(1.0/60)
	var state:Dictionary=demo.inspection_snapshot()
	check(state.tick==120 and state.telemetry.mismatches==0 and state.samples.size()==120,"120 fixed frames compare exact original and prepared production volumes")
	check(state.telemetry.topology_builds<state.telemetry.classifications,"real moving light reuses identical face classification topology")
	demo.set_paused(true);demo.orbit_camera(.1,.1);demo.zoom_camera(-.12);demo.advance(1.0)
	check(demo.inspection_snapshot().tick==120 and demo.inspection_snapshot().telemetry==state.telemetry,"paused camera never rebuilds authority or topology")
	check(demo.set_parameter("prepared_enabled",false).ok and demo.inspection_snapshot().telemetry.mismatches==0,"switching oracle path preserves exact geometry")
	check(demo.reset_experiment({"paused":false}).ok,"same-input reset")
	for tick in 120:demo.advance(1.0/60)
	check(demo.inspection_snapshot().telemetry==state.telemetry,"fresh reset reproduces exact classifications and topology counts")
	var prior_height:float=demo.inspection_snapshot().camera_position.y
	demo.reset_experiment({"camera_mode":"high","paused":true})
	check(demo.inspection_snapshot().camera_position.y>prior_height+10.0,"explicit high camera reset applies the requested projection view")
	var evidence_path:="res://Temp/research/t2-shadow-volume-paired-%d.json"%OS.get_process_id()
	var file:=FileAccess.open(evidence_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(state,"\t"));file.close()
	print("SHADOW_VOLUME_PAIRED_PATH ",evidence_path)
	demo.dispose();demo.dispose();check(demo.get_child_count()==0 and demo.inspection_snapshot().resources.renderer==0,"all isolated owners released")
	demo.free();viewport.free()
	print("LABORATORY_SHADOW_EDGES_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
